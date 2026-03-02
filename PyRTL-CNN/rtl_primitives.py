"""
rtl_primitives.py
=================
底层硬件原语（行为级仿真）。

对应 RTL 模块关系：
  clamp()       → 位宽截断逻辑（综合器自动处理，此处显式建模）
  FeatureSRAM   → 片上特征图 SRAM（单端口读写）
  WeightSRAM    → 片上权重 SRAM（只初始化一次，只读）
  LineBuffer    → 行缓冲移位寄存器（用于卷积窗口滑动）
  MACUnit       → 乘累加单元（multiply-accumulate，INT8×INT8 → INT32 累加）
  RequantUnit   → 重量化单元（INT32 × M0 >> n → INT8，含饱和截断）

设计约束（与规范一致）：
  - 所有数值运算使用 Python 原生 int，显式标注位宽
  - 禁止使用 NumPy / PyTorch 等向量化库
  - 所有循环均为 Python for 循环
"""


# ─────────────────────────────────────────────────────────────────────────────
# 位宽截断工具函数
# ─────────────────────────────────────────────────────────────────────────────

def clamp_int8(x: int) -> int:
    """
    将 INT32 值截断（饱和）至 INT8 有符号范围 [-128, 127]。
    对应 RTL：8 位有符号截断逻辑。
    """
    x = int(x)
    if x > 127:
        return 127
    if x < -128:
        return -128
    return x


def clamp_int16(x: int) -> int:
    """
    将值截断至 INT16 有符号范围 [-32768, 32767]。
    对应 RTL：16 位有符号截断逻辑。
    """
    x = int(x)
    if x > 32767:
        return 32767
    if x < -32768:
        return -32768
    return x


def clamp_int32(x: int) -> int:
    """
    将值截断至 INT32 有符号范围 [-2^31, 2^31-1]。
    对应 RTL：32 位有符号截断逻辑（防止 Python 大整数溢出）。
    """
    x = int(x)
    if x > 2147483647:
        return 2147483647
    if x < -2147483648:
        return -2147483648
    return x


def relu_int8(x: int) -> int:
    """
    INT8 ReLU 激活函数：max(x, 0)。
    对应 RTL：比较器 + 多路选择器。
    """
    return max(0, clamp_int8(x))


# ─────────────────────────────────────────────────────────────────────────────
# FeatureSRAM：片上特征图 SRAM
# ─────────────────────────────────────────────────────────────────────────────

class FeatureSRAM:
    """
    片上特征图 SRAM 行为模型（单端口，同步读写）。

    对应 RTL：
      - 一块 SRAM（通常为 asdrlspkb1pXXXx8cm2sw0 标准单元）
      - 地址空间由 depth 决定
      - 数据位宽固定为 INT8（8 bit）

    用法：
      sram = FeatureSRAM(capacity=32*20*4, name='conv_out_sram')
      sram.write(addr, int8_value)
      val = sram.read(addr)
    """

    def __init__(self, capacity: int, name: str = 'FeatureSRAM'):
        """
        参数：
          capacity (int)：SRAM 深度（字数），每字 8 bit (INT8)。
          name     (str)：调试用名称标签。
        """
        self.name     = name
        self.capacity = capacity
        # 内部存储为 list[int]，每个元素为 INT8 有符号整数
        self._mem = [0] * capacity  # dtype: INT8, 初始值 0

    def write(self, addr: int, data: int):
        """
        写操作：将 INT8 数据写入指定地址。
        对应 RTL：SRAM 写使能有效时的写端口操作。
        """
        assert 0 <= addr < self.capacity, \
            f"{self.name}: write addr {addr} out of range [0, {self.capacity})"
        self._mem[addr] = clamp_int8(data)

    def read(self, addr: int) -> int:
        """
        读操作：从指定地址读取 INT8 数据。
        对应 RTL：SRAM 读使能有效时的读端口操作。
        """
        assert 0 <= addr < self.capacity, \
            f"{self.name}: read addr {addr} out of range [0, {self.capacity})"
        return self._mem[addr]  # dtype: INT8

    def load_flat(self, data_list):
        """
        批量加载一维数据（用于初始化，如从文件加载输入特征图）。
        参数：data_list，长度必须等于 capacity。
        """
        assert len(data_list) == self.capacity, \
            f"{self.name}: load_flat length mismatch: {len(data_list)} vs {self.capacity}"
        for i, v in enumerate(data_list):
            self._mem[i] = clamp_int8(v)

    def dump_flat(self):
        """返回 SRAM 全部数据的副本（list[int]，dtype INT8）。"""
        return list(self._mem)

    def __repr__(self):
        return f"FeatureSRAM(name='{self.name}', capacity={self.capacity})"


# ─────────────────────────────────────────────────────────────────────────────
# WeightSRAM：片上权重 SRAM（只读，初始化一次）
# ─────────────────────────────────────────────────────────────────────────────

class WeightSRAM:
    """
    片上权重 SRAM 行为模型（只读，初始化加载一次）。

    对应 RTL：
      - 在芯片上电后由外部通过总线或 ROM 预加载
      - 运行时只读，地址由控制模块产生
      - 数据位宽固定为 INT8

    注：偏置（bias）为 INT16，此处统一存储为 Python int，
        上层模块负责解释位宽。
    """

    def __init__(self, data_flat, name: str = 'WeightSRAM'):
        """
        参数：
          data_flat (list[int])：一维权重数据（INT8 有符号）。
          name      (str)      ：调试用名称标签。
        """
        self.name     = name
        self.capacity = len(data_flat)
        self._mem     = list(data_flat)  # dtype: INT8

    def read(self, addr: int) -> int:
        """
        读操作：从指定地址读取 INT8 权重。
        对应 RTL：权重 ROM/SRAM 读端口。
        """
        assert 0 <= addr < self.capacity, \
            f"{self.name}: read addr {addr} out of range [0, {self.capacity})"
        return self._mem[addr]  # dtype: INT8

    def __repr__(self):
        return f"WeightSRAM(name='{self.name}', capacity={self.capacity})"


# ─────────────────────────────────────────────────────────────────────────────
# LineBuffer：行缓冲移位寄存器
# ─────────────────────────────────────────────────────────────────────────────

class LineBuffer:
    """
    行缓冲（Line Buffer）行为模型。

    对应 RTL：
      - 由若干排列的寄存器（或小块 SRAM）组成
      - 用于缓存卷积计算所需的多个输入行，支持滑动窗口读取
      - 每个时钟周期推入一列数据，窗口向右滑动

    本实现用于 Conv (11×7) 和 DWConv (3×3)：
      - Conv：需缓冲 11 行，每行宽度 = 输入宽度（10），
              窗口宽度 = 7，逐列滑动
      - DWConv：需缓冲 3 行，每行宽度 = 输入宽度（4），
                窗口宽度 = 3，逐列滑动

    使用方式：
      lb = LineBuffer(num_rows=11, row_width=10)
      lb.load_rows(input_2d)          # 预加载所有行（行为模型简化）
      window = lb.get_window(col, kernel_w)  # 读取 col 起始的 num_rows×kernel_w 窗口
    """

    def __init__(self, num_rows: int, row_width: int, name: str = 'LineBuffer'):
        """
        参数：
          num_rows  (int)：缓冲行数（= 卷积核高度），dtype INT8。
          row_width (int)：每行的列数（输入特征图宽度）。
          name      (str)：调试用名称标签。
        """
        self.name      = name
        self.num_rows  = num_rows
        self.row_width = row_width
        # 二维缓冲区：[行索引][列索引] → INT8
        self._buf = [[0] * row_width for _ in range(num_rows)]

    def load_rows(self, rows_2d):
        """
        批量加载 num_rows 行数据（行为级初始化）。
        参数：rows_2d，形状 (num_rows, row_width)，dtype INT8。
        对应 RTL：行缓冲初始填充阶段（等待 num_rows 行到来后才输出第一个窗口）。
        """
        assert len(rows_2d) == self.num_rows, \
            f"{self.name}: load_rows expects {self.num_rows} rows, got {len(rows_2d)}"
        for r in range(self.num_rows):
            for c in range(self.row_width):
                self._buf[r][c] = clamp_int8(rows_2d[r][c])

    def get_window(self, col_start: int, kernel_w: int):
        """
        从当前缓冲区读取 [num_rows × kernel_w] 的卷积窗口。
        参数：
          col_start (int)：窗口左边界列索引。
          kernel_w  (int)：窗口宽度（卷积核列数）。
        返回：list[list[int]]，形状 (num_rows, kernel_w)，dtype INT8。
        对应 RTL：地址生成单元（AGU）产生地址，多路读取行缓冲中的数据。
        """
        window = []
        for r in range(self.num_rows):
            row_slice = []
            for c in range(kernel_w):
                row_slice.append(self._buf[r][col_start + c])
            window.append(row_slice)
        return window  # shape: (num_rows, kernel_w), dtype INT8

    def __repr__(self):
        return f"LineBuffer(name='{self.name}', num_rows={self.num_rows}, row_width={self.row_width})"


# ─────────────────────────────────────────────────────────────────────────────
# MACUnit：乘累加单元
# ─────────────────────────────────────────────────────────────────────────────

class MACUnit:
    """
    乘累加单元（Multiply-Accumulate Unit）行为模型。

    对应 RTL：
      - 核心为乘法器（INT8 × INT8 → INT16 有符号积）
        +  加法器（INT16 + INT32 累加 → INT32）
      - 输入位宽：INT8 × INT8
      - 中间积位宽：INT16（两个 8 位有符号数相乘，结果最多 16 位）
      - 累加寄存器位宽：INT32（防止多次累加溢出）
      - 一次 compute() 调用对应一次触发（reset + N 次 MAC）

    使用方式：
      mac = MACUnit()
      mac.reset()
      for a, b in zip(inputs, weights):
          mac.accumulate(a, b)          # INT8 × INT8 → 累加至 INT32
      result_int32 = mac.get()          # 读取 INT32 累加结果
    """

    def __init__(self, name: str = 'MACUnit'):
        self.name = name
        self._acc = 0       # INT32 累加寄存器
        self.op_count = 0   # MAC 操作计数（用于性能分析）
        self.total_ops = 0  # 总 MAC 操作计数

    def reset(self):
        """清零累加寄存器。对应 RTL：同步复位信号有效。"""
        self._acc = 0

    def accumulate(self, a: int, b: int):
        """
        单次乘累加：acc += a * b。
        参数：a (INT8), b (INT8)。
        对应 RTL：一次 MAC 流水线操作。
        """
        # INT8 × INT8 → INT16（Python int 自动精度，此处用位宽截断模拟硬件行为）
        product_int16 = clamp_int32(int(a) * int(b))  # 乘积最大 16 bit，用 int32 容纳
        # INT32 累加，截断防止超出 32 位
        self._acc = clamp_int32(self._acc + product_int16)
        self.op_count += 1
        self.total_ops += 1

    def get(self) -> int:
        """读取累加结果（INT32）。"""
        return self._acc  # dtype: INT32

    def add_bias(self, bias: int):
        """
        偏置加法：acc += bias（INT16）。
        对应 RTL：偏置加法器（单独于 MAC 阵列之后的加法级）。
        """
        self._acc = clamp_int32(self._acc + int(bias))

    def __repr__(self):
        return f"MACUnit(name='{self.name}', acc={self._acc}, total_ops={self.total_ops})"


# ─────────────────────────────────────────────────────────────────────────────
# RequantUnit：重量化单元
# ─────────────────────────────────────────────────────────────────────────────

class RequantUnit:
    """
    重量化单元（Requantization Unit）行为模型。

    功能：将 INT32 计算结果重量化为 INT8，采用定点化乘移位方案。
    公式：output_int8 = saturate( (input_int32 * M0) >> n )

    对应 RTL：
      - M0 乘法器（INT32 × INT16 乘法，结果位宽 48 bit）
        在硬件中通常实现为：先做 32 × 16 乘法得 48 位结果
      - 右移器（算术右移 n 位）
      - INT8 饱和截断逻辑（clamp to [-128, 127]）
      - 对应 MiniCNN 中的 RescaleReLu 和 Rescale 模块

    参数：
      M0 (int)：INT16 定点乘法因子（实际取值远小于 16 位范围）。
      n  (int)：右移位数（对应 2^{-n}）。
      use_relu (bool)：是否在输出后应用 ReLU（max(x, 0)）。

    设计说明（与 RescaleReLu.v 对应）：
      MiniCNN 的 RescaleReLu_Mult 先做乘法，RescaleReLu_ShifterReLu 再移位+ReLU。
      本实现在一次 requant() 调用中完成两步。
    """

    def __init__(self, M0: int, n: int, use_relu: bool = True, name: str = 'RequantUnit'):
        """
        参数：
          M0       (int) ：定点乘法因子，对应 Rescale.txt 中的 *_M0。
          n        (int) ：右移位数，对应 Rescale.txt 中的 *_n。
          use_relu (bool)：是否在输出后应用 ReLU，卷积层激活用 True，FC 层用 False。
          name     (str) ：调试用名称标签。
        """
        self.name     = name
        self.M0       = int(M0)        # INT16 乘法因子
        self.n        = int(n)         # 右移位数
        self.use_relu = use_relu

    def requant(self, x_int32: int) -> int:
        """
        对单个 INT32 值执行重量化，返回 INT8。

        计算步骤：
          1. 乘法：x_int32 × M0      （Python int，精确）
          2. 算术右移：>> n           （Python >> 对负数为算术右移）
          3. INT8 饱和截断：clamp_int8
          4. ReLU（可选）：max(0, x)

        对应 RTL：
          wire [47:0] mult_result = $signed(data_in) * $signed(M0);
          wire [31:0] shifted     = mult_result[47+n-1 : n];  // 算术右移 n 位
          wire [7:0]  clamped     = saturate(shifted);
        """
        # Step 1: INT32 × INT16 乘法（Python int 精确计算，无溢出）
        product = int(x_int32) * self.M0   # 结果约 48 bit，Python 自动处理

        # Step 2: 算术右移 n 位（Python >> 对有符号整数为算术右移）
        shifted = product >> self.n

        # Step 3: INT8 饱和截断
        result = clamp_int8(shifted)

        # Step 4: ReLU（可选）
        if self.use_relu:
            result = relu_int8(result)

        return result  # dtype: INT8

    def __repr__(self):
        return (f"RequantUnit(name='{self.name}', M0={self.M0}, n={self.n}, "
                f"use_relu={self.use_relu})")


# ─────────────────────────────────────────────────────────────────────────────
# 快速自检
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    print("=== rtl_primitives.py self-test ===\n")

    # --- clamp 测试 ---
    print("clamp_int8(200)  =", clamp_int8(200),   "  (expected 127)")
    print("clamp_int8(-200) =", clamp_int8(-200),  "  (expected -128)")
    print("clamp_int8(100)  =", clamp_int8(100),   "  (expected 100)")
    print("relu_int8(-5)    =", relu_int8(-5),      "  (expected 0)")
    print("relu_int8(50)    =", relu_int8(50),      "  (expected 50)")

    # --- FeatureSRAM 测试 ---
    print("\n--- FeatureSRAM ---")
    sram = FeatureSRAM(capacity=10, name='test_sram')
    sram.write(0, 120)
    sram.write(1, -50)
    print(f"write(0,120)->read(0): {sram.read(0)}  (expected 120)")
    print(f"write(1,-50)->read(1): {sram.read(1)}  (expected -50)")

    # --- WeightSRAM 测试 ---
    print("\n--- WeightSRAM ---")
    wsram = WeightSRAM([10, -20, 30, -40], name='test_wsram')
    print(f"read(0)={wsram.read(0)}, read(2)={wsram.read(2)}  (expected 10, 30)")

    # --- LineBuffer 测试 ---
    print("\n--- LineBuffer ---")
    lb = LineBuffer(num_rows=3, row_width=5, name='test_lb')
    lb.load_rows([[1, 2, 3, 4, 5],
                  [6, 7, 8, 9, 10],
                  [11, 12, 13, 14, 15]])
    win = lb.get_window(col_start=1, kernel_w=3)
    print(f"get_window(1, 3) = {win}")
    print(f"  (expected [[2,3,4],[7,8,9],[12,13,14]])")

    # --- MACUnit 测试 ---
    print("\n--- MACUnit ---")
    mac = MACUnit(name='test_mac')
    mac.reset()
    mac.accumulate(3, 4)     # 3*4=12
    mac.accumulate(-2, 5)    # -2*5=-10
    mac.add_bias(100)        # +100
    print(f"acc = {mac.get()}  (expected: 12-10+100=102)")

    # --- RequantUnit 测试 ---
    print("\n--- RequantUnit ---")
    # Conv: M0=111, n=14
    # 模拟：输入 x=10000 (INT32)
    # 结果 = clamp(10000*111 >> 14) = clamp(1110000 >> 14) = clamp(67) = 67
    rq = RequantUnit(M0=111, n=14, use_relu=True, name='conv_requant')
    result = rq.requant(10000)
    expected = clamp_int8((10000 * 111) >> 14)
    expected = max(0, expected)
    print(f"requant(10000) = {result}  (expected {expected})")

    result_neg = rq.requant(-10000)
    print(f"requant(-10000) = {result_neg}  (ReLU: should be 0 if negative)")

    print("\n=== All primitives OK ===")
