# PyRTL-CNN：卷积神经网络加速器 Python 行为级仿真

> 数字集成电路设计课程设计 · 高性能场景 · 行为级参考模型

---

## 项目概述

本项目实现了一个**纯 Python、RTL 风格的 CNN 加速器行为模型**，目的是：

1. **理解架构**：通过可执行代码直观理解流水线、片上存储（SRAM）、行缓冲（LineBuffer）、MAC 单元和重量化单元等关键硬件概念
2. **RTL 映射参考**：每个 Python 类对应一个 Verilog 模块，数据流、数据类型和计算逻辑与 RTL 设计保持一致
3. **Testbench 金标准**：为后续 Verilog 仿真提供逐层的参考输出，验证 RTL 数值正确性

**约束**：禁止使用 PyTorch/TensorFlow/NumPy 等向量化库，所有计算使用纯 Python for 循环，所有数据显式标注位宽（INT8/INT16/INT32）。

---

## 网络结构总览

| 层 | 输入尺寸 | 操作 | 输出尺寸 | 位宽（输入→累加→输出） | Rescale 参数 |
|---|---|---|---|---|---|
| **ConvLayer** | (1, 30, 10) | Conv 11×7, 32 个卷积核 | (32, 20, 4) | INT8 → INT32 → INT8 | M0=111, n=14 |
| ReLU | (32, 20, 4) | max(x, 0) | (32, 20, 4) | INT8 | — |
| **DWConvLayer** | (32, 20, 4) | DWConv 3×3 (32 通道独立) | (32, 18, 2) | INT8 → INT32 → INT8 | M0=59, n=11 |
| ReLU | (32, 18, 2) | max(x, 0) | (32, 18, 2) | INT8 | — |
| **PWConvLayer** | (32, 18, 2) | PWConv 1×1 (32→32 通道) | (32, 18, 2) | INT8 → INT32 → INT8 | M0=69, n=13 |
| ReLU | (32, 18, 2) | max(x, 0) | (32, 18, 2) | INT8 | — |
| **MaxpoolLayer** | (32, 18, 2) | MaxPool 2×2, stride=2 | (32, 9, 1) | INT8 | — |
| **FlattenLayer** | (32, 9, 1) | 展平（地址重排） | (288,) | INT8 | — |
| **FCLayer** | (288,) | 全连接 288→2 | (2,) | INT8 → INT32 → INT8 | M0=11, n=15 |
| **SigmoidLayer** | (2,) | LUT 查找（256 条目） | (2,) | INT8 → FP32 | Linear_Out_Scale ≈ 0.09916 |

**重量化公式**：`output_int8 = clamp((input_int32 × M0) >> n, -128, 127)` + ReLU（FC 层无 ReLU）

---

## 代码结构与 RTL 模块对应关系

```
PyRTL-CNN/
├── load_params.py      ← 参数加载（Weight SRAM 初始化数据源）
├── rtl_primitives.py   ← 底层硬件原语（FeatureSRAM / WeightSRAM / LineBuffer / MACUnit / RequantUnit）
├── layers.py           ← 各网络层类（Conv / DWConv / PWConv / Maxpool / Flatten / FC / Sigmoid）
├── top_module.py       ← TopModule 顶层类（串联所有层，管理数据流）
├── run_inference.py    ← 推理入口脚本
├── test_golden.py      ← 金标准对比验证脚本
└── README.md           ← 本文档
```

### Python 类 ↔ Verilog 模块对应表

| Python 类/函数 | 对应 Verilog 模块（MiniCNN 参考） | 说明 |
|---|---|---|
| `FeatureSRAM` | `asdrlspkb1pXXXx8cm2sw0_*.v` | 片上 SRAM 单元 |
| `WeightSRAM` | `asdrlspkb1pXXXx16cm2sw0_conv_weight.v` 等 | 只读权重 SRAM |
| `LineBuffer` | `Conv_DataGroup.v`, `DWconv_DataGroup.v` | 行缓冲移位寄存器 |
| `MACUnit` | `Conv_MultAdd_cell.v`, `DWconv_MultAdd_cell.v` | 乘累加单元 |
| `RequantUnit` | `RescaleReLu.v` = `RescaleReLu_Mult.v` + `RescaleReLu_ShifterReLu.v` | 重量化 + ReLU |
| `ConvLayer` | `Conv.v` + `Conv_WeightSelector.v` | 常规卷积层 |
| `DWConvLayer` | `DWconv.v` + `DWconv_WeightSelector.v` | 深度可分离卷积层 |
| `PWConvLayer` | `PWconv.v` + `PWconv_Conv.v` | 逐点卷积层 |
| `MaxpoolLayer` | `PostProcess_Maxpool.v` | 最大值池化层 |
| `FlattenLayer` | 控制器地址重排逻辑 | 展平层（无数据搬移） |
| `FCLayer` | `PostProcess_Linear.v` + `PostProcess_Rescale.v` | 全连接层 |
| `SigmoidLayer` | `PostProcess_Sigmoid.v` + `asdrlspkb1p256x32cm2sw0_sigmoid.v` | Sigmoid LUT |
| `TopModule` | `CNN.v` | 顶层模块 |

---

## 快速开始

### 1. 环境要求

- Python 3.7+
- 无需任何第三方库

### 2. 运行金标准验证

```bash
cd PyRTL-CNN

# 验证每层输出与 MiniCNN/sim/samples/Test/ 金标准一致性
python test_golden.py
```

预期输出（所有层全部通过）：

```
╔══════════════════════════════════════════════════════╗
║  PyRTL-CNN  Golden Model 验证（Testbench 金标准对比）║
╚══════════════════════════════════════════════════════╝

================================================================
层名称               形状             匹配率               最大误差     状态
================================================================
Conv+ReLU            (32,20,4)        2560/2560 (100.0%)   0            [ PASS ]
DWConv+ReLU          (32,18,2)        1152/1152 (100.0%)   0            [ PASS ]
PWConv+ReLU          (32,18,2)        1152/1152 (100.0%)   0            [ PASS ]
Flatten              (288,)           288/288   (100.0%)   0            [ PASS ]
FC                   (2,)             2/2       (100.0%)   0            [ PASS ]
Sigmoid LUT          (2,)             FP32 误差  < 1e-05   [ PASS ]
```

### 3. 单样本推理

```bash
# 使用金标准输入（默认）
python run_inference.py

# 使用指定编号的样本（0~495）
python run_inference.py --input 42

# 批量推理全部 496 个样本，统计类别分布
python run_inference.py --all
```

### 4. 参数加载自检

```bash
python load_params.py
```

### 5. 底层原语自检

```bash
python rtl_primitives.py
```

---

## 架构核心概念说明

### 片上存储层次（对应 SRAM 设计）

```
Weight SRAM（只读，上电初始化一次）：
  conv_weight_sram   : 32×11×7 = 2464 字节（INT8）
  conv_bias_sram     : 32 × 2  = 64  字节（INT16 → 按 2 字节存储）
  dwconv_weight_sram : 32×3×3  = 288  字节（INT8）
  pwconv_weight_sram : 32×32   = 1024 字节（INT8）
  fc_weight_sram     : 2×288   = 576  字节（INT8）
  sigmoid_lut        : 256×4   = 1024 字节（FP32）

Feature SRAM（运行时读写）：
  input_sram         : 1×30×10 = 300  字节（INT8）
  conv_out_sram      : 32×20×4 = 2560 字节（INT8）
  dwconv_out_sram    : 32×18×2 = 1152 字节（INT8）
  pwconv_out_sram    : 32×18×2 = 1152 字节（INT8）
  maxpool_out_sram   : 32×9×1  = 288  字节（INT8）
  flatten_out_sram   : 288      = 288  字节（INT8）
  fc_out_sram        : 2        = 2    字节（INT8）
```

### 行缓冲（LineBuffer）

LineBuffer 是实现滑窗卷积的关键：

```
ConvLayer 行缓冲：
  缓存 11 行（= 卷积核高度），每行宽 10 列
  滑窗：每次向右移动 1 列，读取 11×7 的窗口
  等效 RTL：11 × 10 = 110 个 D 触发器（寄存器）

DWConvLayer 行缓冲（每通道独立）：
  32 × 3 行，每行宽 4 列
  等效 RTL：32 × 3 × 4 = 384 个 D 触发器
```

### 重量化（Requantization）

定点化乘移位实现，避免浮点运算：

```
公式：output_int8 = clamp((input_int32 × M0) >> n, -128, 127)

各层参数：
  Conv:   M0=111, n=14  ≈ 0.006779 × 2^14 (误差 <1%)
  DWConv: M0=59,  n=11  ≈ 0.028809 × 2^11
  PWConv: M0=69,  n=13  ≈ 0.008423 × 2^13
  FC:     M0=11,  n=15  ≈ 0.000336 × 2^15

对应 RTL 模块：RescaleReLu.v（Mult → ShifterReLu 两级流水线）
```

### MAC 操作数估算

| 层 | MAC 次数（单次推理） |
|---|---|
| Conv | 32 × 20 × 4 × 1 × 11 × 7 = 197,120 |
| DWConv | 32 × 18 × 2 × 3 × 3 = 10,368 |
| PWConv | 32 × 18 × 2 × 32 = 36,864 |
| FC | 2 × 288 = 576 |
| **合计** | **~244,928** |

---

## 参数文件说明

详见 `MiniCNN/sim/samples/` 目录结构：

| 目录/文件 | 内容 | 格式 |
|---|---|---|
| `Param/Param_Conv_Weight.txt` | Conv 层权重 (32,1,11,7) → INT8 | 32 个 11×7 矩阵，空行分隔 |
| `Param/Param_Conv_Bias.txt` | Conv 层偏置 (32,) → INT16 | 一维向量，空格分隔 |
| `Param/Param_DWConv_Weight.txt` | DWConv 层权重 (32,1,3,3) → INT8 | 32 个 3×3 矩阵，空行分隔 |
| `Param/Param_DWConv_Bias.txt` | DWConv 层偏置 (32,) → INT16 | 一维向量 |
| `Param/Param_PWConv_Weight.txt` | PWConv 层权重 (32,32,1,1) → INT8 | 32×32 矩阵，每行 32 个值 |
| `Param/Param_PWConv_Bias.txt` | PWConv 层偏置 (32,) → INT16 | 一维向量 |
| `Param/Param_Linear_Weight.txt` | FC 层权重 (2,288) → INT8 | 2×288 矩阵 |
| `Param/Param_Linear_Bias.txt` | FC 层偏置 (2,) → INT16 | 一维向量 |
| `Scale/Rescale.txt` | 各层重量化参数 (M0, n) | C 风格赋值语句 |
| `Scale/Scale.txt` | 量化 Scale 参数（含 `Linear_Out_Scale`） | C 风格赋值语句 |
| `sigmoid_lookup_table.txt` | Sigmoid LUT（256 条目 FP32） | 每行 8 字符 IEEE754 十六进制 |
| `In/N.txt` (N=0~495) | 第 N 个输入 MFCC 特征图 (30,10) → INT8 | 30 行 × 10 列，空格分隔 |
| `Test/Input.txt` | 金标准测试输入 (30,10) → INT8 | 同上 |
| `Test/Out_Conv.txt` | Conv 层金标准输出 (32,20,4) | 32 个 20×4 矩阵，空行分隔 |
| `Test/Out_DWConv.txt` | DWConv 层金标准输出 (32,18,2) | 32 个 18×2 矩阵，空行分隔 |
| `Test/Out_PWConv.txt` | PWConv 层金标准输出 (32,18,2) | 32 个 18×2 矩阵，空行分隔 |
| `Test/Out_Flatten.txt` | Flatten 层金标准输出 (288,) | 一维向量 |
| `Test/Out_Linear.txt` | FC 层金标准输出 (2,) | 一维向量 |
| `Test/Out.txt` | Sigmoid 最终输出 (2,) → FP32 | 一维向量 |

---

## 如何通过代码学习 CNN 加速器架构

### 推荐阅读顺序

按下面的顺序阅读代码，每一步都对应一个具体的硬件概念。

#### 第一步：理解位宽与截断（`rtl_primitives.py`，约 10 分钟）

打开 [rtl_primitives.py](rtl_primitives.py)，先只看最开头的三个函数：

```python
def clamp_int8(x: int) -> int: ...
def clamp_int16(x: int) -> int: ...
def clamp_int32(x: int) -> int: ...
```

**关键认知**：硬件中的每根线/寄存器都有固定位宽，数据超出范围会被截断（饱和）。Python 的 int 没有位宽限制，所以要手动加 clamp。后续所有 MAC 累加结果都必须经过这个截断才能模拟真实硬件行为。

运行观察：
```bash
python rtl_primitives.py
```
观察 `clamp_int8(200)=127`（饱和到最大值），`clamp_int8(-200)=-128`（饱和到最小值）。

---

#### 第二步：理解片上存储（`rtl_primitives.py` 中的 SRAM）

继续读 `FeatureSRAM` 和 `WeightSRAM` 两个类。

**关键认知**：芯片上没有"内存"的概念，只有 SRAM。SRAM 通过地址读写，不能像 Python list 那样随机切片。重点理解地址计算公式：

```
(通道, 行, 列) → 地址 = 通道 × H × W + 行 × W + 列
```

这个**地址展平公式**在所有层的 `compute()` 中反复出现，是数据在 SRAM 和计算单元之间流动的核心。

**对照 RTL**：`FeatureSRAM` 对应 MiniCNN 中以 `asdrlspkb1p` 开头的 `.v` 文件，即工艺库提供的标准 SRAM 单元。

---

#### 第三步：理解行缓冲（`rtl_primitives.py` 中的 `LineBuffer`）

读 `LineBuffer` 类，重点看两个方法：
- `load_rows(rows_2d)`：将若干行数据填入缓冲
- `get_window(col_start, kernel_w)`：读取从 `col_start` 列开始的 `kernel_w` 列宽窗口

**关键认知**：卷积的"滑窗"操作在硬件中不是通过移动数据实现的，而是通过**行缓冲**缓存若干行，然后改变读取起始地址来模拟窗口滑动。这样数据只需要从主存储器读入一次，大幅降低带宽需求。

```
对于 ConvLayer（卷积核 11×7）：
  LineBuffer 缓存 11 行，每行 10 个像素
  当窗口滑动到列 k 时，调用 get_window(k, 7)，
  返回当前缓冲中第 k 到第 k+6 列的 11 行数据
```

**RTL 对应**：`Conv_DataGroup.v` 和 `DWconv_DataGroup.v`。

---

#### 第四步：理解 MAC 单元（`rtl_primitives.py` 中的 `MACUnit`）

读 `MACUnit` 类，重点看 `reset()` / `accumulate(a, b)` / `get()` 三个方法。

**关键认知**：MAC（乘累加）是神经网络加速器的核心计算单元，其工作流程是：

```
reset()           → 清空累加寄存器（一次新的输出像素开始）
accumulate(a, b)  → acc += a × b（一次乘法 + 一次加法）
get()             → 读取最终累加结果（INT32）
```

注意 `accumulate` 后有 `clamp_int32`，防止多次累加后 32 位溢出。单个 Conv 输出像素需调用 `accumulate` **77 次**（11×7），这对应 RTL 中的 77 级流水线或 77 个并行乘法器。

---

#### 第五步：理解重量化（`rtl_primitives.py` 中的 `RequantUnit`）

读 `RequantUnit` 类，重点看 `requant(x_int32)` 方法。

**关键认知**：卷积中间结果是 INT32，但下一层只接受 INT8 输入，因此需要"重量化"将 INT32 压缩回 INT8。为了避免浮点除法（硬件代价高），使用定点化乘移位实现：

```
output = clamp((x_int32 × M0) >> n, -128, 127)
```

这等价于乘以浮点数 `M = M0 × 2^{-n}`，但全程只用整数运算和移位，非常适合硬件实现。

**RTL 对应**：`RescaleReLu_Mult.v`（做乘法）→ `RescaleReLu_ShifterReLu.v`（做移位+截断）。

---

#### 第六步：从单层到完整推理（`layers.py`）

现在打开 [layers.py](layers.py)，读 `ConvLayer` 类（最长最复杂的一个），按以下思路阅读：

1. **`__init__`**：看实例化了哪些 SRAM 和原语 → 理解该层有哪些硬件资源
2. **`load_weight()`**：看如何将参数文件数据展平存入 WeightSRAM → 理解权重地址映射
3. **`compute()`**：核心！三重 for 循环 `(i, j, k)` 对应 `(输出通道, 输出行, 输出列)`，内层两重 `(m, n)` 对应卷积核扫描 → 这就是卷积的完整定义
4. **`requant()`**：遍历所有输出，逐一调用 `RequantUnit` → INT32 变 INT8

**阅读技巧**：`compute()` 中每一行的注释都标注了数据类型（INT8/INT32）和地址计算来源，对照这些注释逐行阅读即可完全理解数据流。

读完 `ConvLayer` 后，`DWConvLayer`（深度可分离）和 `PWConvLayer`（逐点卷积）只是计算公式的变体，结构完全相同，可快速扫过。

---

#### 第七步：数据流全貌（`top_module.py`）

打开 [top_module.py](top_module.py)，只读 `forward()` 方法（约 40 行）。

**关键认知**：整个网络就是 7 个 stage 的**顺序数据流**，每个 stage 从上一个 stage 的 `out_sram` 中读取数据，写入自己的 `out_sram`。这对应 RTL 中各模块通过总线/SRAM 串联的拓扑结构：

```
input_sram → Conv.out_sram → DWConv.out_sram → PWConv.out_sram
           → Maxpool.out_sram → Flatten.out_sram → FC.out_sram → Sigmoid输出
```

注意 `cycle_count` 计数器：每个 `accumulate()` 调用计 1 次，最终总计 244,928 次。这是串行执行时的理论最小计算量，也是评估并行度提升空间的基准。

---

### 运行脚本辅助学习

#### 观察每层输入输出尺寸变化

```bash
python run_inference.py
```

输出中每一行对应一个硬件 stage，可以直观看到特征图尺寸从 `(1,30,10)` 逐步变换到最终的 `(2,)` FP32 输出。

#### 逐层验证数值正确性

```bash
python test_golden.py
```

这是最重要的学习工具。脚本会将每层的 Python 计算结果与助教提供的金标准逐元素对比。当你修改了某层的计算逻辑时（例如尝试更改重量化参数、卷积顺序等），可以立即通过这个脚本看到哪里出错，快速建立对数值计算的直觉。

#### 验证参数加载理解

```bash
python load_params.py
```

输出中会打印各个参数文件的形状，可以对照 `MiniCNN/sim/samples/README.md` 中的格式描述，理解参数文件的组织方式（尤其是空行分隔的矩阵格式）。

#### 交互式单步调试（推荐）

在 VS Code 中对 [top_module.py](top_module.py) 的 `forward()` 方法中任意一行设置断点，然后在调试控制台中查看各 SRAM 的内容：

```python
# 在断点处可以执行：
conv_layer.out_sram.dump_flat()[:10]        # 查看 Conv 输出 SRAM 前 10 个值
dwconv_layer._out_int32[0][0][0]            # 查看 DWConv 第0通道第0行第0列的 INT32 中间值
req = RequantUnit(M0=59, n=11, use_relu=False)
req.requant(dwconv_layer._out_int32[0][0][0])  # 手动验证重量化结果
```

---

## 后续工作建议

本 Python 模型完成后，下一步推进 RTL 设计：

1. **对照代码设计 Verilog 模块**：每个 Python 类对应一个 `.v` 文件，数据流和位宽约束直接映射
2. **使用本脚本生成测试向量**：`test_golden.py` 输出的逐层数据可直接用于 Verilog Testbench
3. **架构优化方向（高性能场景）**：
   - 增加 MAC 并行度（展开 for 循环 → 多个并行乘法器）
   - 引入真实流水线寄存器（stage 间打注册）
   - 优化 LineBuffer 的行缓存策略（减少 SRAM 读写次数）
