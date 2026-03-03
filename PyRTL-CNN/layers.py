"""
layers.py
=========
各网络层封装类（RTL 行为级仿真）。

网络结构：
  Input(1,30,10) → ConvLayer(32,1,11,7) → ReLU →
  DWConvLayer(32,1,3,3) → ReLU →
  PWConvLayer(32,32,1,1) → ReLU →
  MaxpoolLayer(2×2,s=2) → FlattenLayer →
  FCLayer(2,288) → SigmoidLayer → FP32 输出

每个类的结构：
  - load_weight(params)  ： 从参数字典初始化 WeightSRAM
  - compute(input_sram)  ： 读取输入 SRAM，执行逐元素运算，将 INT32 结果暂存
  - requant()            ： 执行重量化，输出 INT8 到输出 FeatureSRAM
                           （MaxpoolLayer / FlattenLayer 不含 requant）

RTL 模块对应关系（MiniCNN 参考设计）：
  ConvLayer    → Conv.v + Conv_MultAdd.v + Conv_WeightSelector.v + RescaleReLu.v
  DWConvLayer  → DWconv.v + DWconv_MultAdd.v + DWconv_RescaleReLu.v
  PWConvLayer  → PWconv.v + PWconv_Conv.v + PWconv_RescaleReLu.v
  MaxpoolLayer → PostProcess_Maxpool.v
  FlattenLayer → 控制逻辑（地址重排）
  FCLayer      → PostProcess_Linear.v + Rescale.v
  SigmoidLayer → PostProcess_Sigmoid.v（查找表实现）
"""

from rtl_primitives import (
    FeatureSRAM, WeightSRAM, LineBuffer, MACUnit, RequantUnit,
    clamp_int8, clamp_int32, relu_int8
)
from load_params import (
    load_conv_weight, load_conv_bias,
    load_dwconv_weight, load_dwconv_bias,
    load_pwconv_weight, load_pwconv_bias,
    load_linear_weight, load_linear_bias,
    load_rescale_params, load_sigmoid_lut
)


# ─────────────────────────────────────────────────────────────────────────────
# ConvLayer：第一层常规卷积（Conv 32,1,11,7）
# ─────────────────────────────────────────────────────────────────────────────

class ConvLayer:
    """
    常规卷积层。
    输入尺寸：(1, 30, 10)  INT8
    输出尺寸：(32, 20, 4)  INT8（经过重量化+ReLU）

    计算公式：
      O[i][j][k] = sum_{m=0}^{10} sum_{n=0}^{6} I[0][j+m][k+n] * W[i][0][m][n] + B[i]
      stride=1, padding=0：输出尺寸 = (30-11+1, 10-7+1) = (20, 4)
      i ranging from 0 to 31 (32 output channels), m from 0 to 10, n from 0 to 6

    RTL 对应：
      - Conv_WeightSelector.v：从 Weight SRAM 按地址选择卷积核
      - Conv_DataGroup.v：从输入 SRAM / LineBuffer 组织数据
      - Conv_MultAdd.v：并行 MAC 阵列（77 个乘法器）
      - RescaleReLu.v：重量化 + ReLU

    架构选择（高性能场景）：
      本实现按 for 循环串行模拟，等效于 RTL 中完全展开（fully unrolled）的 MAC 阵列。
      真实 RTL 可进一步并行/流水线处理以提升吞吐量。
    """

    # 网络结构常量
    IN_C, IN_H, IN_W       = 1, 30, 10
    KH,   KW               = 11, 7
    OUT_C                  = 32
    STRIDE                 = 1
    OUT_H = IN_H - KH + 1  # = 20
    OUT_W = IN_W - KW + 1  # = 4

    def __init__(self, rescale_params: dict):
        """
        参数：
          rescale_params (dict)：来自 load_rescale_params()，键为层名。
        """
        # Weight SRAM（模型参数）：在 load_weight() 中初始化
        self.weight_sram = None  # WeightSRAM，展平存放 (32,11,7) INT8 权重
        self.bias_sram   = None  # WeightSRAM，存放 (32,) INT16 偏置

        # 输出 FeatureSRAM：32 × 20 × 4 个 INT8
        self.out_sram = FeatureSRAM(
            capacity=self.OUT_C * self.OUT_H * self.OUT_W,
            name='conv_out_sram'
        )

        # 行缓冲：缓存 KH=11 行，宽度 = IN_W=10
        self.line_buffer = LineBuffer(
            num_rows=self.KH,     # 行缓冲行数等于卷积核高度
            row_width=self.IN_W,  # 行缓冲列数等于输入宽度
            name='conv_line_buffer'
        )

        # MAC 单元（串行复用，模拟硬件中的 MAC 阵列）
        self.mac = MACUnit(name='conv_mac')

        # 重量化单元：M0=111, n=14，不含 ReLU（ReLU 在 DWConvLayer 读取数据时施加）
        # 这样 out_sram 保存的是 pre-ReLU 的 INT8 值，与金标准 Out_Conv.txt 一致
        M0 = rescale_params['Conv']['M0']
        n  = rescale_params['Conv']['n']
        self.requant_unit = RequantUnit(M0=M0, n=n, use_relu=False, name='conv_requant')

        # 暂存 INT32 输出（在 compute() 和 requant() 之间）
        self._out_int32 = None  # list，形状 (OUT_C, OUT_H, OUT_W)

    def load_weight(self):
        """
        从参数文件加载权重和偏置，初始化 Weight SRAM。
        对应 RTL：SRAM 预加载阶段（上电 / reset 后由控制器写入）。
        """
        weights = load_conv_weight()  # shape (32, 11, 7)，INT8
        biases  = load_conv_bias()    # shape (32,)，INT16

        # 展平存入 Weight SRAM：地址 = i * KH * KW + m * KW + n
        flat_w = []
        for i in range(self.OUT_C):
            for m in range(self.KH):
                for n in range(self.KW):
                    flat_w.append(weights[i][m][n])
        self.weight_sram = WeightSRAM(flat_w, name='conv_weight_sram')
        self.bias_sram   = WeightSRAM(biases, name='conv_bias_sram')

    def _read_weight(self, out_ch, krow, kcol):
        """从 Weight SRAM 读取指定卷积核位置的权重，INT8。"""
        # 地址展平公式：i * KH * KW + m * KW + n
        addr = out_ch * self.KH * self.KW + krow * self.KW + kcol
        return self.weight_sram.read(addr)

    def compute(self, in_sram: FeatureSRAM):
        """
        执行卷积前向计算，结果（INT32）暂存于 self._out_int32。
        参数：in_sram，形状 (1, 30, 10) 的 FeatureSRAM，地址 = j * IN_W + k。
        对应 RTL：Conv_MultAdd + Conv_Add2nd + Conv_Add3rd 多级累加流水线。
        """
        assert self.weight_sram is not None, "请先调用 load_weight()"

        # 初始化 INT32 输出缓冲（保存所有空间位置的 INT32 累加结果）
        # out_int32[i][j][k] 对应输出通道 i、行 j、列 k
        out_int32 = [
            [[0] * self.OUT_W for _ in range(self.OUT_H)]
            for _ in range(self.OUT_C)
        ]

        # 对每个输出通道 i
        for i in range(self.OUT_C):
            bias_val = self.bias_sram.read(i)  # INT16

            # 滑窗：对每个输出空间位置 (j, k)
            # fj: 理解：在计算 Ouput Feature Map 的第 j 行时，需要缓存 Input Feature Map 的第 j 到 j+KH-1 行（共 KH 行）到 LineBuffer 中，以供卷积窗口使用。Output Feature Map的每一行只需进行一次行缓存
            for j in range(self.OUT_H):
                # 将 LineBuffer 加载输入行片段 [j, j+KH) 的 [0, IN_W) 列
                rows_for_lb = []
                for m in range(self.KH):
                    row_data = []
                    for c in range(self.IN_W):
                        addr = (j + m) * self.IN_W + c  # 输入 SRAM 地址（单通道）
                        row_data.append(in_sram.read(addr))
                    rows_for_lb.append(row_data)
                self.line_buffer.load_rows(rows_for_lb)

                for k in range(self.OUT_W):
                    # 读取 KH × KW 卷积窗口
                    window = self.line_buffer.get_window(col_start=k, kernel_w=self.KW)

                    # MAC：对 KH×KW=77 个位置累加
                    self.mac.reset()
                    for m in range(self.KH):
                        for n in range(self.KW):
                            pixel  = window[m][n]                   # INT8
                            weight = self._read_weight(i, m, n)     # INT8
                            self.mac.accumulate(pixel, weight)
                    # fj: 思考，这一段纯串行的操作在真正 RTL 实现时应该如何做？
                    # 加偏置
                    self.mac.add_bias(bias_val)

                    # 存入 INT32 缓冲
                    out_int32[i][j][k] = self.mac.get()   # INT32

        self._out_int32 = out_int32

    def requant(self):
        """
        重量化：INT32 → INT8（+ReLU），结果写入输出 FeatureSRAM。
        对应 RTL：RescaleReLu 模块（M0=111, n=14）。
        """
        assert self._out_int32 is not None, "请先调用 compute()"

        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    val_int32 = self._out_int32[i][j][k]          # INT32
                    val_int8  = self.requant_unit.requant(val_int32)  # INT8 + ReLU
                    addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    self.out_sram.write(addr, val_int8)

    def get_output_3d(self):
        """
        返回输出 FeatureSRAM 中的数据，重组为 3D 列表。
        返回：list[list[list[int]]]，形状 (32, 20, 4)，dtype INT8。
        """
        result = [
            [[0] * self.OUT_W for _ in range(self.OUT_H)]
            for _ in range(self.OUT_C)
        ]
        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    result[i][j][k] = self.out_sram.read(addr)
        return result


# ─────────────────────────────────────────────────────────────────────────────
# DWConvLayer：深度可分离卷积层（DWConv 32,1,3,3）
# ─────────────────────────────────────────────────────────────────────────────

class DWConvLayer:
    """
    深度可分离卷积层（Depthwise Convolution）。
    输入尺寸：(32, 20, 4)  INT8
    输出尺寸：(32, 18, 2)  INT8（经过重量化+ReLU）

    计算公式：
      O[i][j][k] = sum_{m=0}^{2} sum_{n=0}^{2} I[i][j+m][k+n] * W[i][0][m][n] + B[i]
      每个输出通道 i 只与相同通道 i 的输入相乘（无跨通道累加）。
      输出尺寸 = (20-3+1, 4-3+1) = (18, 2)

    RTL 对应：
      DWconv.v + DWconv_MultAdd.v + DWconv_RescaleReLu.v
    """

    IN_C, IN_H, IN_W       = 32, 20, 4
    KH,   KW               = 3,  3
    OUT_C                  = 32
    OUT_H = IN_H - KH + 1  # = 18
    OUT_W = IN_W - KW + 1  # = 2

    def __init__(self, rescale_params: dict):
        self.weight_sram = None
        self.bias_sram   = None
        self.out_sram = FeatureSRAM(
            capacity=self.OUT_C * self.OUT_H * self.OUT_W,
            name='dwconv_out_sram'
        )
        # 每个通道独立的 LineBuffer（3 行，宽度 4）
        self.line_buffers = [
            LineBuffer(num_rows=self.KH, row_width=self.IN_W, name=f'dwconv_lb_ch{i}')
            for i in range(self.IN_C)
        ]
        self.mac = MACUnit(name='dwconv_mac')

        M0 = rescale_params['DWConv']['M0']
        n  = rescale_params['DWConv']['n']
        # ReLU 不在 requant 中应用（out_sram 存 pre-ReLU；PWConvLayer 读取时施加 ReLU）
        self.requant_unit = RequantUnit(M0=M0, n=n, use_relu=False, name='dwconv_requant')
        self._out_int32 = None

    def load_weight(self):
        """加载 DWConv 权重 (32,3,3) 和偏置 (32,)。"""
        weights = load_dwconv_weight()  # shape (32, 3, 3)
        biases  = load_dwconv_bias()    # shape (32,)

        flat_w = []
        for i in range(self.OUT_C):
            for m in range(self.KH):
                for n in range(self.KW):
                    flat_w.append(weights[i][m][n])
        self.weight_sram = WeightSRAM(flat_w, name='dwconv_weight_sram')
        self.bias_sram   = WeightSRAM(biases, name='dwconv_bias_sram')

    def _read_weight(self, ch, krow, kcol):
        addr = ch * self.KH * self.KW + krow * self.KW + kcol
        return self.weight_sram.read(addr)

    def compute(self, in_sram: FeatureSRAM):
        """
        执行深度可分离卷积前向计算。
        in_sram 地址：i * IN_H * IN_W + j * IN_W + k
        """
        assert self.weight_sram is not None
        out_int32 = [
            [[0] * self.OUT_W for _ in range(self.OUT_H)]
            for _ in range(self.OUT_C)
        ]

        for i in range(self.OUT_C):
            bias_val = self.bias_sram.read(i)
            lb = self.line_buffers[i]

            for j in range(self.OUT_H):
                # 加载第 i 通道的行窗口 [j, j+KH)
                # 读取时施加 ReLU（对应 Conv 层输出的 Activation1）
                rows_for_lb = []
                for m in range(self.KH):
                    row_data = []
                    for c in range(self.IN_W):
                        addr = i * self.IN_H * self.IN_W + (j + m) * self.IN_W + c
                        pixel = relu_int8(in_sram.read(addr))  # ReLU applied here (Activation1)
                        row_data.append(pixel)
                    rows_for_lb.append(row_data)
                lb.load_rows(rows_for_lb)

                for k in range(self.OUT_W):
                    window = lb.get_window(col_start=k, kernel_w=self.KW)
                    self.mac.reset()
                    for m in range(self.KH):
                        for n in range(self.KW):
                            pixel  = window[m][n]
                            weight = self._read_weight(i, m, n)
                            self.mac.accumulate(pixel, weight)
                    self.mac.add_bias(bias_val)
                    out_int32[i][j][k] = self.mac.get()

        self._out_int32 = out_int32

    def requant(self):
        """重量化：INT32 → INT8（+ReLU），M0=59, n=11。"""
        assert self._out_int32 is not None
        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    val_int8 = self.requant_unit.requant(self._out_int32[i][j][k])
                    addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    self.out_sram.write(addr, val_int8)

    def get_output_3d(self):
        """返回形状 (32, 18, 2) 的输出，dtype INT8。"""
        result = [
            [[0] * self.OUT_W for _ in range(self.OUT_H)]
            for _ in range(self.OUT_C)
        ]
        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    result[i][j][k] = self.out_sram.read(addr)
        return result


# ─────────────────────────────────────────────────────────────────────────────
# PWConvLayer：逐点卷积层（PWConv 32,32,1,1）
# ─────────────────────────────────────────────────────────────────────────────

class PWConvLayer:
    """
    逐点卷积层（Pointwise Convolution，1×1 卷积）。
    输入尺寸：(32, 18, 2)  INT8
    输出尺寸：(32, 18, 2)  INT8（经过重量化+ReLU）

    计算公式：
      O[i][j][k] = sum_{p=0}^{31} W[i][p] * I[p][j][k] + B[i]
      1×1 卷积等价于通道维度的点积（每个空间位置独立）。

    RTL 对应：
      PWconv.v + PWconv_Conv.v + PWconv_Conv_1point.v + PWconv_RescaleReLu.v
    """

    IN_C, IN_H, IN_W = 32, 18, 2
    OUT_C             = 32
    OUT_H, OUT_W      = 18, 2

    def __init__(self, rescale_params: dict):
        self.weight_sram = None
        self.bias_sram   = None
        self.out_sram = FeatureSRAM(
            capacity=self.OUT_C * self.OUT_H * self.OUT_W,
            name='pwconv_out_sram'
        )
        self.mac = MACUnit(name='pwconv_mac')

        M0 = rescale_params['PWConv']['M0']
        n  = rescale_params['PWConv']['n']
        # ReLU 不在 requant 中应用（out_sram 存 pre-ReLU；MaxpoolLayer 读取时施加 ReLU）
        self.requant_unit = RequantUnit(M0=M0, n=n, use_relu=False, name='pwconv_requant')
        self._out_int32 = None

    def load_weight(self):
        """加载 PWConv 权重 (32,32) 和偏置 (32,)。"""
        weights = load_pwconv_weight()  # shape (32, 32)
        biases  = load_pwconv_bias()    # shape (32,)

        flat_w = []
        for i in range(self.OUT_C):
            for p in range(self.IN_C):
                flat_w.append(weights[i][p])
        self.weight_sram = WeightSRAM(flat_w, name='pwconv_weight_sram')
        self.bias_sram   = WeightSRAM(biases, name='pwconv_bias_sram')

    def _read_weight(self, out_ch, in_ch):
        addr = out_ch * self.IN_C + in_ch
        return self.weight_sram.read(addr)

    def compute(self, in_sram: FeatureSRAM):
        """
        执行逐点卷积前向计算。
        in_sram 地址：p * IN_H * IN_W + j * IN_W + k
        """
        assert self.weight_sram is not None
        out_int32 = [
            [[0] * self.OUT_W for _ in range(self.OUT_H)]
            for _ in range(self.OUT_C)
        ]

        for i in range(self.OUT_C):
            bias_val = self.bias_sram.read(i)
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    # 对所有输入通道 p 做点积
                    # 读取时施加 ReLU（对应 DWConv 层输出的 Activation2）
                    self.mac.reset()
                    for p in range(self.IN_C):
                        addr   = p * self.IN_H * self.IN_W + j * self.IN_W + k
                        pixel  = relu_int8(in_sram.read(addr))  # ReLU applied here (Activation2)
                        weight = self._read_weight(i, p)
                        self.mac.accumulate(pixel, weight)
                    self.mac.add_bias(bias_val)
                    out_int32[i][j][k] = self.mac.get()

        self._out_int32 = out_int32

    def requant(self):
        """重量化：INT32 → INT8（+ReLU），M0=69, n=13。"""
        assert self._out_int32 is not None
        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    val_int8 = self.requant_unit.requant(self._out_int32[i][j][k])
                    addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    self.out_sram.write(addr, val_int8)

    def get_output_3d(self):
        """返回形状 (32, 18, 2) 的输出，dtype INT8。"""
        result = [
            [[0] * self.OUT_W for _ in range(self.OUT_H)]
            for _ in range(self.OUT_C)
        ]
        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    result[i][j][k] = self.out_sram.read(addr)
        return result


# ─────────────────────────────────────────────────────────────────────────────
# MaxpoolLayer：最大值池化（2×2，stride=2）
# ─────────────────────────────────────────────────────────────────────────────

class MaxpoolLayer:
    """
    最大值池化层（2×2，stride=2）。
    输入尺寸：(32, 18, 2)  INT8
    输出尺寸：(32, 9,  1)  INT8

    计算公式：
      O[i][j][k] = max(I[i][2j][2k], I[i][2j+1][2k], I[i][2j][2k+1], I[i][2j+1][2k+1])
    注：当输入宽度=2，stride=2 时，只有 k=0 有效（2*0=0，2*1 超界）。

    RTL 对应：PostProcess_Maxpool.v（比较器树）
    """

    IN_C, IN_H, IN_W = 32, 18, 2
    POOL_H, POOL_W   =  2,  2
    STRIDE           =  2
    OUT_C            = 32
    OUT_H = IN_H // STRIDE   # = 9
    OUT_W = IN_W // STRIDE   # = 1

    def __init__(self):
        self.out_sram = FeatureSRAM(
            capacity=self.OUT_C * self.OUT_H * self.OUT_W,
            name='maxpool_out_sram'
        )

    def load_weight(self):
        """池化层无参数，此方法为空（保持接口一致性）。"""
        pass

    def compute(self, in_sram: FeatureSRAM):
        """
        执行最大值池化前向计算，结果直接写入输出 FeatureSRAM（INT8）。
        对应 RTL：比较器树，4 个输入比较两轮后得最大值。
        """
        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    # 读取 2×2 池化窗口内的 4 个像素
                    # 读取时施加 ReLU（对应 PWConv 层输出的 Activation3）
                    max_val = -128  # INT8 最小值
                    for pm in range(self.POOL_H):
                        for pn in range(self.POOL_W):
                            in_j = j * self.STRIDE + pm
                            in_k = k * self.STRIDE + pn
                            if in_j < self.IN_H and in_k < self.IN_W:
                                addr = i * self.IN_H * self.IN_W + in_j * self.IN_W + in_k
                                pixel = relu_int8(in_sram.read(addr))  # ReLU applied here (Activation3)
                                if pixel > max_val:
                                    max_val = pixel
                    out_addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    self.out_sram.write(out_addr, max_val)

    def get_output_3d(self):
        """返回形状 (32, 9, 1) 的输出，dtype INT8。"""
        result = [
            [[0] * self.OUT_W for _ in range(self.OUT_H)]
            for _ in range(self.OUT_C)
        ]
        for i in range(self.OUT_C):
            for j in range(self.OUT_H):
                for k in range(self.OUT_W):
                    addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
                    result[i][j][k] = self.out_sram.read(addr)
        return result


# ─────────────────────────────────────────────────────────────────────────────
# FlattenLayer：展平层
# ─────────────────────────────────────────────────────────────────────────────

class FlattenLayer:
    """
    展平层（Flatten）。
    输入尺寸：(32, 9, 1)  INT8
    输出尺寸：(288,)      INT8

    展平顺序（按通道优先展开，与设计规范一致）：
      O[32*j + i] = I[i][j][0]，其中 i=0..31，j=0..8
      即：先遍历空间位置 j，再遍历通道 i
      等价展开方式：顺序读取 maxpool_out_sram（按地址 i*9+j）

    注：规范公式中使用 1-based 索引，此处统一使用 0-based。
    """

    IN_C, IN_H, IN_W = 32, 9, 1
    OUT_SIZE          = 32 * 9 * 1  # = 288

    def __init__(self):
        self.out_sram = FeatureSRAM(capacity=self.OUT_SIZE, name='flatten_out_sram')

    def load_weight(self):
        """展平层无参数。"""
        pass

    def compute(self, in_sram: FeatureSRAM):
        """
        执行展平操作：将 (32,9,1) 的 FeatureSRAM 重排为 (288,) 的一维向量。
        展平顺序：O[i*9 + j] = I[i][j][0]，对应直接按 SRAM 顺序读取。
        对应 RTL：地址重映射逻辑（无实际数据移动，只是地址计数器重排序）。
        """
        # 直接按输入 SRAM 的地址顺序复制即可
        # 输入 SRAM 顺序：i * IN_H * IN_W + j * IN_W + k = i*9 + j（k 固定为 0）
        for idx in range(self.OUT_SIZE):
            val = in_sram.read(idx)
            self.out_sram.write(idx, val)

    def get_output_1d(self):
        """返回形状 (288,) 的输出，dtype INT8。"""
        return [self.out_sram.read(i) for i in range(self.OUT_SIZE)]


# ─────────────────────────────────────────────────────────────────────────────
# FCLayer：全连接层（FC 2,288）
# ─────────────────────────────────────────────────────────────────────────────

class FCLayer:
    """
    全连接层（Fully Connected Layer）。
    输入尺寸：(288,)  INT8
    输出尺寸：(2,)    INT8（经过重量化，无 ReLU）

    计算公式：
      O[i] = sum_{p=0}^{287} W[i][p] * I[p] + B[i]，i=0,1

    RTL 对应：
      PostProcess_Linear.v + PostProcess_Linear_1group.v +
      PostProcess_Rescale.v

    注意：FC 层不使用 ReLU（输出 INT8 后直接进入 Sigmoid 查找表）。
    """

    IN_SIZE  = 288
    OUT_SIZE = 2

    def __init__(self, rescale_params: dict):
        self.weight_sram = None
        self.bias_sram   = None
        self.out_sram = FeatureSRAM(capacity=self.OUT_SIZE, name='fc_out_sram')
        self.mac = MACUnit(name='fc_mac')

        M0 = rescale_params['Linear']['M0']
        n  = rescale_params['Linear']['n']
        # FC 层不加 ReLU
        self.requant_unit = RequantUnit(M0=M0, n=n, use_relu=False, name='fc_requant')
        self._out_int32 = None

    def load_weight(self):
        """加载 FC 权重 (2,288) 和偏置 (2,)。"""
        weights = load_linear_weight()  # shape (2, 288)
        biases  = load_linear_bias()    # shape (2,)

        flat_w = []
        for i in range(self.OUT_SIZE):
            for p in range(self.IN_SIZE):
                flat_w.append(weights[i][p])
        self.weight_sram = WeightSRAM(flat_w, name='fc_weight_sram')
        self.bias_sram   = WeightSRAM(biases, name='fc_bias_sram')

    def compute(self, in_sram: FeatureSRAM):
        """执行全连接层前向计算，INT32 结果暂存。"""
        assert self.weight_sram is not None
        out_int32 = [0] * self.OUT_SIZE

        for i in range(self.OUT_SIZE):
            bias_val = self.bias_sram.read(i)
            self.mac.reset()
            for p in range(self.IN_SIZE):
                addr   = p
                pixel  = in_sram.read(addr)
                weight = self.weight_sram.read(i * self.IN_SIZE + p)
                self.mac.accumulate(pixel, weight)
            self.mac.add_bias(bias_val)
            out_int32[i] = self.mac.get()

        self._out_int32 = out_int32

    def requant(self):
        """重量化：INT32 → INT8（无 ReLU），M0=11, n=15。"""
        assert self._out_int32 is not None
        for i in range(self.OUT_SIZE):
            val_int8 = self.requant_unit.requant(self._out_int32[i])
            self.out_sram.write(i, val_int8)

    def get_output_1d(self):
        """返回形状 (2,) 的输出，dtype INT8。"""
        return [self.out_sram.read(i) for i in range(self.OUT_SIZE)]


# ─────────────────────────────────────────────────────────────────────────────
# SigmoidLayer：Sigmoid 激活层（查找表实现）
# ─────────────────────────────────────────────────────────────────────────────

class SigmoidLayer:
    """
    Sigmoid 激活层（LUT 查找表实现）。
    输入尺寸：(2,)  INT8
    输出尺寸：(2,)  FP32

    实现方式：
      LUT[x & 0xFF] 直接映射，0x00 对应 INT8=-128，0xFF 对应 INT8=127。
      等价于：sigmoid(x * Linear_Out_Scale)，其中 Linear_Out_Scale ≈ 0.09916。

    RTL 对应：
      PostProcess_Sigmoid.v（SRAM 实现的 256 条目 LUT ROM）

    设计说明：
      在 RTL 中，256 条目 × 32bit FP32 = 8KB SRAM 或 ROM。
      行为级仿真直接用 Python list 实现，索引方式与 RTL SRAM 地址映射一致。
    """

    def __init__(self):
        self.lut = None  # list[float]，长度 256，在 load_weight() 中初始化

    def load_weight(self):
        """加载 Sigmoid 查找表（sigmoid_lookup_table.txt）。"""
        self.lut = load_sigmoid_lut()  # list[float], len=256

    def compute(self, in_data):
        """
        执行 Sigmoid 前向计算（LUT 查找）。
        参数：in_data，list[int] 或 FeatureSRAM，形状 (2,)，dtype INT8。
        返回：list[float]，形状 (2,)，dtype FP32。
        对应 RTL：用 INT8 输入作为 SRAM 地址（8 位地址，256 条目）读取预计算结果。
        """
        assert self.lut is not None, "请先调用 load_weight()"

        if isinstance(in_data, FeatureSRAM):
            inputs = [in_data.read(i) for i in range(2)]
        else:
            inputs = list(in_data)

        outputs = []
        for x in inputs:
            # 将 INT8 有符号值转为无符号地址（x & 0xFF）
            addr = int(x) & 0xFF   # INT8 → uint8 地址：-128→0x00，0→0x80，127→0x7F
            outputs.append(self.lut[addr])  # FP32

        return outputs  # list[float], shape (2,)
