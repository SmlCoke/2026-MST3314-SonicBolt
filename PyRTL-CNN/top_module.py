"""
top_module.py
=============
顶层模块（TopModule）：顺序管理所有网络层，实现完整的 CNN 前向推理。

对应 RTL：
  CNN.v（顶层）→ 实例化并串联所有子模块，
  CNN_DataController.v → 生成本模块中的 cycle_count 计数器

架构说明（对应高性能场景设计）：
  本行为模型按顺序调用各层，每层输出存入对应的 FeatureSRAM，
  下一层从该 SRAM 读取输入。这对应 RTL 中的流水线数据通路：

  ┌──────────┐  FeatureSRAM  ┌───────────┐  FeatureSRAM  ┌───────────┐
  │ConvLayer │ ─────────────>│DWConvLayer│ ─────────────>│PWConvLayer│
  └──────────┘  (32,20,4)    └───────────┘  (32,18,2)    └───────────┘
                                                                 │
                                                          FeatureSRAM
                                                           (32,18,2)
                                                                 ↓
  ┌──────────┐  FeatureSRAM  ┌───────────┐  FeatureSRAM  ┌───────────┐
  │FCLayer   │ <─────────────│FlattenLayer│ <─────────────│MaxpoolLayer│
  └──────────┘   (288,)      └───────────┘   (32,9,1)    └───────────┘
        │
  FeatureSRAM
     (2,)
        ↓
  ┌──────────────┐
  │SigmoidLayer  │ → FP32 输出 (2,) → 分类结果
  └──────────────┘

模拟的流水线概念：
  cycle_count 累计所有层的 MAC 操作数，近似等于串行执行时的总计算量。
  在真实 RTL 流水线设计中，通过并行 MAC 阵列和 stage 重叠可将实际周期数大幅降低。
"""

import os
import sys

# 将当前目录添加到 Python 路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from load_params import load_rescale_params, load_input
from rtl_primitives import FeatureSRAM, clamp_int8
from layers import (
    ConvLayer, DWConvLayer, PWConvLayer,
    MaxpoolLayer, FlattenLayer, FCLayer, SigmoidLayer
)


class TopModule:
    """
    CNN 顶层模块（行为级仿真）。

    使用方法：
      top = TopModule()
      top.load_all_weights()
      result = top.forward(sample_id=0)
      print(result)  # [sigmoid_out0, sigmoid_out1]

    对应 RTL 顶层 CNN.v 的模块实例化和数据流连接。
    """

    def __init__(self, verbose: bool = True):
        """
        参数：
          verbose (bool)：是否打印每层 I/O 尺寸，默认 True。
        """
        self.verbose = verbose

        # ── 加载重量化参数（各层 M0, n）──────────────────────────────────────
        # 对应 RTL：各层 RescaleReLu 模块的参数寄存器，编译时确定（hardwired）
        rescale_params = load_rescale_params()
        if verbose:
            print("=== TopModule 初始化 ===")
            print("重量化参数（各层 Rescale M0/n）：")
            for layer, p in rescale_params.items():
                print(f"  {layer:8s}: M0={p['M0']}, n={p['n']}")
            print()

        # ── 实例化各层 ────────────────────────────────────────────────────────
        # 对应 RTL：CNN.v 中实例化所有子模块
        self.conv_layer    = ConvLayer(rescale_params)
        self.dwconv_layer  = DWConvLayer(rescale_params)
        self.pwconv_layer  = PWConvLayer(rescale_params)
        self.maxpool_layer = MaxpoolLayer()
        self.flatten_layer = FlattenLayer()
        self.fc_layer      = FCLayer(rescale_params)
        self.sigmoid_layer = SigmoidLayer()

        # ── 层间 FeatureSRAM（中间结果缓冲）──────────────────────────────────
        # 对应 RTL：各层之间的片上 SRAM 或寄存器堆
        # 注：各层内部已创建好 out_sram，此处直接复用
        self.input_sram = None  # 将在 forward() 中初始化

        # ── 性能计数器 ─────────────────────────────────────────────────────
        self.cycle_count = 0    # 累计 MAC 操作数（模拟周期计数）

    def load_all_weights(self):
        """
        加载所有层的权重参数（初始化各层 Weight SRAM）。
        对应 RTL：上电复位后从外部存储器加载权重到片上 SRAM 的初始化阶段。
        """
        if self.verbose:
            print("=== 加载网络参数（Weight SRAM 初始化）===")

        self.conv_layer.load_weight()
        if self.verbose:
            print(f"  Conv    weight SRAM: capacity={self.conv_layer.weight_sram.capacity} words (INT8)")
            print(f"  Conv    bias   SRAM: capacity={self.conv_layer.bias_sram.capacity} words (INT16)")

        self.dwconv_layer.load_weight()
        if self.verbose:
            print(f"  DWConv  weight SRAM: capacity={self.dwconv_layer.weight_sram.capacity} words (INT8)")
            print(f"  DWConv  bias   SRAM: capacity={self.dwconv_layer.bias_sram.capacity} words (INT16)")

        self.pwconv_layer.load_weight()
        if self.verbose:
            print(f"  PWConv  weight SRAM: capacity={self.pwconv_layer.weight_sram.capacity} words (INT8)")
            print(f"  PWConv  bias   SRAM: capacity={self.pwconv_layer.bias_sram.capacity} words (INT16)")

        self.maxpool_layer.load_weight()
        self.flatten_layer.load_weight()

        self.fc_layer.load_weight()
        if self.verbose:
            print(f"  FC      weight SRAM: capacity={self.fc_layer.weight_sram.capacity} words (INT8)")
            print(f"  FC      bias   SRAM: capacity={self.fc_layer.bias_sram.capacity} words (INT16)")

        self.sigmoid_layer.load_weight()
        if self.verbose:
            print(f"  Sigmoid LUT    ROM:  capacity={len(self.sigmoid_layer.lut)} entries (FP32)")
            print()

    def _print_layer_io(self, layer_name, in_shape, out_shape, dtype_in='INT8', dtype_out='INT8'):
        """打印层的 I/O 尺寸信息。"""
        if self.verbose:
            in_str  = 'x'.join(str(x) for x in in_shape)
            out_str = 'x'.join(str(x) for x in out_shape)
            print(f"  [{layer_name:<14}]  input: ({in_str}) {dtype_in}"
                  f"  →  output: ({out_str}) {dtype_out}")

    def forward(self, input_2d=None, sample_id: int = None):
        """
        执行完整的 CNN 前向推理。

        参数（二选一）：
          input_2d  (list[list[int]])：形状 (30,10) 的 INT8 输入，直接传入。
          sample_id (int)：从 MiniCNN/sim/samples/In/{id}.txt 读取输入。

        返回：
          dict，包含：
            'sigmoid_out'   : list[float]，Sigmoid 输出 [class0_prob, class1_prob]
            'fc_out_int8'   : list[int]，FC 层输出（INT8）
            'predicted_class': int，预测类别（argmax）
            'cycle_count'   : int，累计 MAC 操作数
        """
        assert self.conv_layer.weight_sram is not None, "请先调用 load_all_weights()"
        assert input_2d is not None or sample_id is not None, \
            "必须提供 input_2d 或 sample_id"

        # ── 加载输入数据到 Feature SRAM ────────────────────────────────────
        if input_2d is None:
            input_2d = load_input(sample_id)  # shape (30, 10)
        # 展平存入 input_sram：地址 = j * 10 + k（单通道，通道 0）
        self.input_sram = FeatureSRAM(capacity=1 * 30 * 10, name='input_sram')
        for j in range(30):
            for k in range(10):
                self.input_sram.write(j * 10 + k, input_2d[j][k])

        if self.verbose:
            display_id = sample_id if sample_id is not None else 'direct'
            print(f"=== 前向推理（样本 {display_id}）===")

        # ── Stage 1：Conv（常规卷积）+ ReLU ──────────────────────────────────
        # 对应 RTL：Conv 模块，77 个 MAC × 32 输出通道 × 20×4 空间位置
        self.conv_layer.compute(self.input_sram)
        self.conv_layer.requant()
        self._print_layer_io('Conv+ReLU', (1, 30, 10), (32, 20, 4))
        self.cycle_count += self.conv_layer.mac.total_ops

        # ── Stage 2：DWConv（深度可分离卷积）+ ReLU ──────────────────────────
        # 对应 RTL：DWconv 模块，9 个 MAC × 32 通道 × 18×2 空间位置
        self.dwconv_layer.compute(self.conv_layer.out_sram)
        self.dwconv_layer.requant()
        self._print_layer_io('DWConv+ReLU', (32, 20, 4), (32, 18, 2))
        self.cycle_count += self.dwconv_layer.mac.total_ops

        # ── Stage 3：PWConv（逐点卷积）+ ReLU ──────────────────────────────
        # 对应 RTL：PWconv 模块，32 个 MAC × 32 输出通道 × 18×2 空间位置
        self.pwconv_layer.compute(self.dwconv_layer.out_sram)
        self.pwconv_layer.requant()
        self._print_layer_io('PWConv+ReLU', (32, 18, 2), (32, 18, 2))
        self.cycle_count += self.pwconv_layer.mac.total_ops

        # ── Stage 4：Maxpool（2×2，stride=2）───────────────────────────────
        # 对应 RTL：PostProcess_Maxpool.v，比较器树，无 MAC 操作
        self.maxpool_layer.compute(self.pwconv_layer.out_sram)
        self._print_layer_io('Maxpool 2x2', (32, 18, 2), (32, 9, 1))

        # ── Stage 5：Flatten ─────────────────────────────────────────────────
        # 对应 RTL：地址重排逻辑，无实际数据运算
        self.flatten_layer.compute(self.maxpool_layer.out_sram)
        self._print_layer_io('Flatten', (32, 9, 1), (288,))

        # ── Stage 6：FC（全连接层）──────────────────────────────────────────
        # 对应 RTL：PostProcess_Linear.v，288 个 MAC × 2 输出
        self.fc_layer.compute(self.flatten_layer.out_sram)
        self.fc_layer.requant()
        self._print_layer_io('FC', (288,), (2,), dtype_out='INT8')
        self.cycle_count += self.fc_layer.mac.total_ops

        # ── Stage 7：Sigmoid（LUT 查找表）────────────────────────────────────
        # 对应 RTL：PostProcess_Sigmoid.v，SRAM LUT（256 条目 × 32bit）
        fc_out = self.fc_layer.get_output_1d()
        sigmoid_out = self.sigmoid_layer.compute(fc_out)
        self._print_layer_io('Sigmoid LUT', (2,), (2,), dtype_in='INT8', dtype_out='FP32')

        # ── 输出结果 ──────────────────────────────────────────────────────────
        predicted_class = 0 if sigmoid_out[0] >= sigmoid_out[1] else 1

        if self.verbose:
            print()
            print(f"  FC 输出（INT8）    : {fc_out}")
            print(f"  Sigmoid 输出（FP32）: [{sigmoid_out[0]:.6f}, {sigmoid_out[1]:.6f}]")
            print(f"  预测类别            : class {predicted_class}")
            print(f"  累计 MAC 操作数     : {self.cycle_count:,}")
            print()

        return {
            'sigmoid_out'      : sigmoid_out,
            'fc_out_int8'      : fc_out,
            'predicted_class'  : predicted_class,
            'cycle_count'      : self.cycle_count,
        }

    def get_intermediate_outputs(self):
        """
        获取所有中间层的输出（用于 Testbench 金标准对比）。
        返回：dict，包含各层输出数据。
        注：需在 forward() 之后调用。
        """
        return {
            'conv_out'    : self.conv_layer.get_output_3d(),      # (32, 20, 4) INT8
            'dwconv_out'  : self.dwconv_layer.get_output_3d(),    # (32, 18, 2) INT8
            'pwconv_out'  : self.pwconv_layer.get_output_3d(),    # (32, 18, 2) INT8
            'flatten_out' : self.flatten_layer.get_output_1d(),   # (288,) INT8
            'fc_out'      : self.fc_layer.get_output_1d(),        # (2,) INT8
        }

    def reset_cycle_count(self):
        """重置 MAC 操作计数器（用于多次推理计时）。"""
        self.cycle_count = 0
        self.conv_layer.mac.total_ops   = 0
        self.dwconv_layer.mac.total_ops = 0
        self.pwconv_layer.mac.total_ops = 0
        self.fc_layer.mac.total_ops     = 0


# ─────────────────────────────────────────────────────────────────────────────
# 快速自检（使用金标准测试样本）
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    from load_params import load_golden_input

    print("=========================================")
    print("  TopModule 快速自检（使用金标准输入）")
    print("=========================================\n")

    top = TopModule(verbose=True)
    top.load_all_weights()

    # 使用金标准输入（Test/Input.txt）
    golden_input = load_golden_input()  # shape (30, 10)
    result = top.forward(input_2d=golden_input)

    print("========= 推理完成 =========")
    print(f"Sigmoid 输出: [{result['sigmoid_out'][0]:.6f}, {result['sigmoid_out'][1]:.6f}]")
    print(f"预测类别: class {result['predicted_class']}")
    print(f"总 MAC 操作数: {result['cycle_count']:,}")
