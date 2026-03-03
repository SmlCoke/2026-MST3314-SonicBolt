# RTL 设计基础知识：CNN 加速器关键技术

> 面向 SJTU MST3314 课程设计 · 高性能场景
> 本文档结合 `PyRTL-CNN/` 行为级仿真代码，逐一讲解在 RTL 实现 CNN 加速器时必须掌握的四个核心技术。

---

## 目录

1. [流水线架构（Pipeline Architecture）](#1-流水线架构)
2. [SRAM：片上静态存储器](#2-sram片上静态存储器)
3. [数据缓冲：LineBuffer 与 Ping-Pong Buffer](#3-数据缓冲linebuffer-与-ping-pong-buffer)
4. [并行计算单元：MAC 与 MAC 阵列](#4-并行计算单元mac-与-mac-阵列)

---

## 1. 流水线架构

### 1.1 基本概念

**流水线（Pipeline）** 是硬件设计中提升吞吐量最重要的手段。其核心思想来源于工厂的流水线作业：把一个复杂任务切成若干**段（Stage）**，每段之间插入**寄存器（Pipeline Register）**，各段同时工作，对不同数据并行推进。

| 概念 | 说明 |
|------|------|
| **吞吐量（Throughput）** | 单位时间处理的数据量，流水线的目标是最大化这个值 |
| **延迟（Latency）** | 一个数据从入口到出口需要的时间（周期数），流水线不减少延迟，甚至略有增加 |
| **流水线级数（Depth）** | 切成几段，每段对应一个时钟周期 |
| **关键路径（Critical Path）** | 组合逻辑中延迟最长的那条路径，决定了最高时钟频率 |

### 1.2 没有流水线会发生什么

以重量化单元（RequantUnit）为例。在 `PyRTL-CNN/rtl_primitives.py` 中，`RequantUnit.requant()` 完成两个操作：

```python
# Step 1: INT32 × INT16 乘法
product = int(x_int32) * self.M0

# Step 2: 算术右移 n 位
shifted = product >> self.n
```

如果直接映射到 RTL，且将这两个操作放在同一个组合逻辑级：

```verilog
// 不推荐：两级操作在同一个时钟周期完成
// 32×16 乘法（关键路径约 5-8ns）+ 移位器（约 1ns）
// 在 0.18μm 工艺下，这条路径总延迟约 6-9ns → 最高只能跑 ~110-166MHz
wire [47:0] product = $signed(data_in) * $signed(M0);
wire [7:0]  shifted = product[47 : n];  // 算术右移
```

这段代码的组合逻辑延迟太长，会限制整个芯片的时钟频率。

### 1.3 加入流水线寄存器

MiniCNN 参考设计中，`RescaleReLu.v` 被拆分为 `RescaleReLu_Mult.v` 和 `RescaleReLu_ShifterReLu.v` 两个模块，中间通过寄存器打一拍，这就是**两级流水线**：

```
时钟  |  Stage 1（乘法）  |  Stage 2（移位+截断）
------|-------------------|--------------------
clk0  |  数据A 计算乘积    |  --（空）
clk1  |  数据B 计算乘积    |  数据A 执行移位
clk2  |  数据C 计算乘积    |  数据B 执行移位
clk3  |  数据D 计算乘积    |  数据C 执行移位
```

对应的 Verilog 写法：

```verilog
// RescaleReLu 两级流水线示意
module RescaleReLu #(
    parameter M0 = 111,
    parameter N  = 14
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire signed [31:0] data_in,   // INT32 输入
    output reg         valid_out,
    output reg  signed [7:0]  data_out   // INT8 输出
);

// ── Stage 1 寄存器：乘法结果 ──────────────────────────────────
reg signed [47:0] mult_result_r;  // 32×16 = 48bit
reg               valid_s1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mult_result_r <= 0;
        valid_s1      <= 0;
    end else begin
        // Stage 1：完成 INT32 × M0 乘法，结果暂存
        mult_result_r <= $signed(data_in) * $signed(16'd0 + M0);
        valid_s1      <= valid_in;
    end
end

// ── Stage 2：移位 + 饱和截断 + ReLU ─────────────────────────
wire signed [31:0] shifted = mult_result_r >>> N;  // 算术右移

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out  <= 0;
        valid_out <= 0;
    end else begin
        // 饱和截断到 INT8，并施加 ReLU
        if      (shifted > 127)  data_out <= 8'sd127;
        else if (shifted < -128) data_out <= -8'sd128;
        else                     data_out <= shifted[7:0];
        // ReLU（若需要）：将负数置零
        if (shifted < 0)         data_out <= 8'sd0;
        valid_out <= valid_s1;
    end
end

endmodule
```

**关键点**：
- `valid_in` / `valid_out` 信号随数据一起流动，告诉下游数据是否有效
- Stage 1 和 Stage 2 各占约 5ns 组合逻辑延迟 → 时钟周期 ≥ 5ns → fmax ≈ 200MHz
- 如果不拆分，组合逻辑延迟约 6-8ns → fmax ≈ 125-167MHz

### 1.4 层间流水线（Inter-layer Pipeline）

除了层**内部**的流水线，层与层之间也可以形成流水线，如图所示：

```
时间轴 →
帧0: Conv处理 | DWConv处理 | PWConv处理 | FC处理 |
帧1:          | Conv处理   | DWConv处理 | PWConv处理 | FC处理 |
帧2:                      | Conv处理   | DWConv处理 | PWConv处理 | FC处理 |
```

每隔 `Conv_latency` 个周期就能产出一帧结果，吞吐量由**最慢的那一层（瓶颈层）**决定。实现层间流水线需要在相邻层之间使用 **Ping-Pong Buffer**（见第3节）。

---

## 2. SRAM：片上静态存储器

### 2.1 什么是 SRAM

芯片上不存在"内存"，只有 **SRAM（Static Random Access Memory，静态随机存取存储器）**。SRAM 由工艺库提供，以一个特定规格的黑盒单元（例如 `asdrlspkb1p2560x8cm2sw0.v`）的形式出现：

| 参数 | 含义 | 举例 |
|------|------|------|
| **深度（Depth）** | 可存多少个字（Word） | 2560 个字 |
| **位宽（Width）** | 每个字多少位 | 8 bit（1 字节） |
| **端口** | 单端口 / 双端口 | 单端口（同一时刻只能读或写，不能同时） |
| **读延迟** | 从发出地址到数据稳定的周期数 | 通常 1 个时钟周期（同步 SRAM） |

**SRAM 接口（简化）**：

```verilog
// 工艺库 SRAM 宏单元接口示意（实际以库文件为准）
module SRAM_2560x8 (
    input  wire        CLK,
    input  wire        CS,    // Chip Select（片选）
    input  wire        WE,    // Write Enable（写使能）
    input  wire [11:0] ADDR,  // 地址（ceil(log2(2560)) = 12 bit）
    input  wire [7:0]  DIN,   // 写数据
    output wire [7:0]  DOUT   // 读数据（同步，下一拍有效）
);
```

**重要**：SRAM 是**同步**器件。在 `posedge clk` 时，如果 `WE=1` 则写入，否则读取；读出的数据在**下一个时钟上升沿后**才稳定（即发出读请求后隔一拍才能用数据）。

### 2.2 本项目的 SRAM 组织

本项目中 SRAM 分为两类（对应 `PyRTL-CNN/rtl_primitives.py`）：

#### 权重 SRAM（WeightSRAM，只读）

```python
# rtl_primitives.py：WeightSRAM 行为模型
class WeightSRAM:
    def __init__(self, data_flat, name):
        self._mem = list(data_flat)  # 初始化一次，运行时只读
    def read(self, addr):
        return self._mem[addr]       # 只读操作
```

| SRAM 名 | 容量 | 位宽 | 说明 |
|---------|------|------|------|
| `conv_weight_sram` | 2464 字 | INT8 | Conv 层权重 (32×11×7) |
| `conv_bias_sram` | 32 字 | INT16 | Conv 偏置（2字节×32） |
| `dwconv_weight_sram` | 288 字 | INT8 | DWConv 权重 (32×3×3) |
| `pwconv_weight_sram` | 1024 字 | INT8 | PWConv 权重 (32×32) |
| `fc_weight_sram` | 576 字 | INT8 | FC 权重 (2×288) |
| `sigmoid_lut` | 256 字 | FP32/32bit | Sigmoid 查找表 |

#### 特征图 SRAM（FeatureSRAM，运行时读写）

```python
# rtl_primitives.py：FeatureSRAM 行为模型
class FeatureSRAM:
    def __init__(self, capacity, name):
        self._mem = [0] * capacity  # 可读写
    def write(self, addr, data):
        self._mem[addr] = clamp_int8(data)
    def read(self, addr):
        return self._mem[addr]
```

| SRAM 名 | 容量 | 说明 |
|---------|------|------|
| `input_sram` | 300 字 | 输入特征图 (1×30×10) |
| `conv_out_sram` | 2560 字 | Conv 输出 (32×20×4) |
| `dwconv_out_sram` | 1152 字 | DWConv 输出 (32×18×2) |
| `pwconv_out_sram` | 1152 字 | PWConv 输出 (32×18×2) |
| `maxpool_out_sram` | 288 字 | MaxPool 输出 (32×9×1) |

### 2.3 三维地址展平公式（Address Flattening）

特征图在逻辑上是三维的 `(C, H, W)`，但 SRAM 是一维地址空间。展平公式为：

```
addr(c, h, w) = c × H × W + h × W + w
```

在 `PyRTL-CNN/layers.py` 中随处可见：

```python
# layers.py，ConvLayer.compute() 中
# 读取输入 SRAM：输入通道 p=0，行 j+m，列 k+n
in_addr = (j + m) * self.IN_W + (k + n)   # 因为 IN_C=1，p×H×W 项=0
in_val  = input_sram.read(in_addr)

# 写入输出 SRAM：通道 i，行 j，列 k
out_addr = i * self.OUT_H * self.OUT_W + j * self.OUT_W + k
out_sram.write(out_addr, result_int8)
```

对应 RTL 中，地址生成由**控制器（FSM）** 或**地址生成单元（AGU）** 用计数器自动产生：

```verilog
// 控制器中用计数器生成 SRAM 地址
// 假设当前处理的是通道 i，行 j，列 k
assign out_sram_addr = i * OUT_H * OUT_W + j * OUT_W + k;
assign out_sram_wren = compute_done;   // 一个像素算完后写入
assign out_sram_din  = rescale_result; // 重量化后的 INT8 结果
```

### 2.4 SRAM 读写时序注意事项

```
           ┌──┐   ┌──┐   ┌──┐
CLK    ────┘  └───┘  └───┘  └────

       <──── 发出读地址 ────><──── 数据有效 ────>
ADDR   ─────[addr_0]──────────[addr_1]──────
DOUT   ──────────────[data_0]──────────[data_1]
                     ↑ 比地址晚一拍
```

**实际编码时**：发出地址后，必须等**下一个时钟**才能使用读出的数据。在 RTL 中，通常用 `valid` 信号配合 `+1` 的延迟来保证时序正确。

---

## 3. 数据缓冲：LineBuffer 与 Ping-Pong Buffer

### 3.1 为什么卷积需要行缓冲

卷积操作有一个"滑动窗口"，需要同时访问输入特征图中 `KH × KW` 个相邻像素。对于 Conv 层（核大小 11×7），每计算一个输出像素，需要访问输入中 **11 行 × 7 列 = 77 个元素**。

**问题**：如果每次都从 SRAM 重新读取这 77 个元素，当窗口向右滑动一步时，只有 **1 列（11个元素）是新的**，其余 **66 个元素已经读过**。重复读取会浪费大量 SRAM 带宽，且单端口 SRAM 每周期只能访问 1 个地址。

**解决方案**：**行缓冲（Line Buffer）** ── 预先把需要的 `KH` 行数据缓存在寄存器中，窗口滑动时只需移动读取起始地址，而不重复访问 SRAM。

### 3.2 LineBuffer 的硬件结构

```
输入特征图（存储在 SRAM 中，逐行读入行缓冲）：
  行 0: [p0, p1, p2, p3, ..., p9]
  行 1: [p10, p11, ...]
  ...

LineBuffer（KH=11 行，row_width=10 列）：
  寄存器阵列，共 11×10 = 110 个 D 触发器（每个存 1 个 INT8）

  ┌──────────────────────────────────┐
  │  row[0]:  [r0c0][r0c1]...[r0c9] │  ← 最旧的行
  │  row[1]:  [r1c0][r1c1]...[r1c9] │
  │  ...                             │
  │  row[10]: [r10c0]...[r10c9]     │  ← 最新的行
  └──────────────────────────────────┘
           ↑ 窗口左边界 col_start

  get_window(col_start=k, kernel_w=7)：
    返回 row[0..10][k..k+6]，共 77 个值
```

对应 `PyRTL-CNN/rtl_primitives.py` 中的 `LineBuffer` 类：

```python
class LineBuffer:
    def __init__(self, num_rows, row_width, name):
        # 行缓冲：num_rows × row_width 个寄存器
        self._buf = [[0] * row_width for _ in range(num_rows)]

    def load_rows(self, rows_2d):
        # 初始化：等待足够多的行到来后才能开始卷积
        for r in range(self.num_rows):
            for c in range(self.row_width):
                self._buf[r][c] = clamp_int8(rows_2d[r][c])

    def get_window(self, col_start, kernel_w):
        # 读取 col_start 开始的窗口，无需搬移数据
        window = []
        for r in range(self.num_rows):
            row_slice = [self._buf[r][col_start + c] for c in range(kernel_w)]
            window.append(row_slice)
        return window   # shape: (num_rows, kernel_w)
```

### 3.3 LineBuffer 的 Verilog 实现

在实际 RTL 中，行缓冲有两种常见实现方式：

#### 方式 A：寄存器阵列（适合小 buffer）

```verilog
// Conv 行缓冲：11 行 × 10 列，共 110 个 INT8 寄存器
// 每拍从 SRAM 读入 1 列（11 个新像素），旧数据保持不变
module LineBuffer_Conv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_en,          // 加载新列数据
    input  wire [7:0]  col_in [0:10],    // 新的一列（11 个 INT8）
    output wire [7:0]  window [0:10][0:6] // 当前 11×7 窗口
);

reg signed [7:0] buf [0:10][0:9];  // 11 行 × 10 列寄存器

// 逐列加载（行缓冲列位置由外部计数器指定）
// 这里简化：外部控制器负责填充所有列后再开始卷积
...

// 读取当前窗口（col_start 由外部计数器驱动）
// assign window[r][c] = buf[r][col_start + c];
endmodule
```

#### 方式 B：移位寄存器（适合流式输入）

```verilog
// 每次推入 1 行数据（从 SRAM 逐行读取），
// 内部用循环缓冲（ring buffer）或移位寄存器维护最新的 KH 行
// 实际项目中这种方式更常见，与真实的数据流方向吻合
```

### 3.4 Ping-Pong Buffer（乒乓缓冲）

**问题**：如果 Conv 层和 DWConv 层按串行顺序工作，则：
1. Conv 处理帧 N，将结果写入 `conv_out_sram`
2. Conv 完成后，DWConv 从 `conv_out_sram` 读取并处理
3. DWConv 完成后，才能处理下一帧...

这种串行方式无法实现层间流水线。

**解决方案**：**Ping-Pong Buffer** ── 为相邻层之间的中间特征图准备**两块 SRAM（Bank A 和 Bank B）**：

```
帧 N：
  Conv 写 Bank A（conv_out, 2560B）
  Conv 完成 → DWConv 读 Bank A

帧 N+1：
  Conv 写 Bank B（同时 DWConv 还在读 Bank A 处理帧 N）
  Conv 完成 → DWConv 切换，读 Bank B

帧 N+2：
  Conv 写 Bank A（同时 DWConv 还在读 Bank B 处理帧 N+1）
  ...
```

时序图：

```
时间 →
Conv:   [帧N写BankA]  [帧N+1写BankB]  [帧N+2写BankA]  ...
DWConv:               [读BankA/帧N]   [读BankB/帧N+1]  ...
```

只要 `Conv_latency ≥ DWConv_latency`（Conv 是瓶颈层），整个系统的吞吐量就由 Conv 的延迟决定，DWConv 可以永远不idle，实现全流水。

**Ping-Pong 控制逻辑（简化）**：

```verilog
reg bank_sel;  // 0 = Conv写A/DWConv读B，1 = Conv写B/DWConv读A

// Conv 完成一帧后切换 bank
always @(posedge clk) begin
    if (conv_frame_done)
        bank_sel <= ~bank_sel;
end

// Conv 写地址选择
assign conv_out_sram_sel  = bank_sel;       // 写 Bank A 或 Bank B
// DWConv 读地址选择
assign dwconv_in_sram_sel = ~bank_sel;      // 读另一个 Bank
```

---

## 4. 并行计算单元：MAC 与 MAC 阵列

### 4.1 MAC 单元基本概念

**MAC（Multiply-Accumulate，乘累加）** 是神经网络加速器的核心运算：

```
acc = acc + a × b
```

在 `PyRTL-CNN/rtl_primitives.py` 中：

```python
class MACUnit:
    def reset(self):
        self._acc = 0           # 清空累加器

    def accumulate(self, a, b):
        product = clamp_int32(int(a) * int(b))   # INT8 × INT8 → INT16/INT32
        self._acc = clamp_int32(self._acc + product)  # 累加至 INT32

    def get(self):
        return self._acc        # 返回 INT32 结果
```

位宽分析（非常重要）：

| 操作 | 输入位宽 | 输出位宽 | 说明 |
|------|---------|---------|------|
| `a × b` | INT8 × INT8 | INT16 | 两个有符号 8bit 数相乘，结果最多 16bit |
| `acc + product` | INT32 + INT16 | INT32 | 累加器必须足够宽防止溢出 |
| 卷积后重量化 | INT32 | INT8 | 经 RequantUnit 输出 |

### 4.2 单个 MAC 单元的 Verilog 实现

```verilog
// 单个 MAC 单元：INT8 × INT8 → INT32 累加
module MACUnit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reset_acc,   // 开始新像素时清空累加器
    input  wire        valid_in,
    input  wire signed [7:0]  a,    // 激活值（INT8）
    input  wire signed [7:0]  b,    // 权重（INT8）
    output reg  signed [31:0] acc   // 累加结果（INT32）
);

wire signed [15:0] product = a * b;  // INT8 × INT8 = INT16

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc <= 32'sd0;
    end else if (reset_acc) begin
        acc <= 32'sd0;           // 新像素开始：清空
    end else if (valid_in) begin
        acc <= acc + {{16{product[15]}}, product};  // 符号扩展后累加
    end
end

endmodule
```

### 4.3 从串行到并行：展开 for 循环

Python 行为模型的 for 循环在 RTL 中可以展开为**并行乘法器+加法树**。

以 Conv 层为例，对于一个输出像素 `O[i][j][k]`，需要计算 `11×7=77` 次 MAC：

```python
# PyRTL-CNN/layers.py 中的串行计算（行为模型）
mac.reset()
for m in range(11):
    for n in range(7):
        in_val  = input_sram.read(in_addr)   # INT8
        w_val   = weight_sram.read(w_addr)   # INT8
        mac.accumulate(in_val, w_val)        # 1 次 MAC
result = mac.get()                           # 77次迭代后得到 INT32
```

**串行实现（for 循环不展开）**：77 个时钟周期才能得到一个输出像素

**并行实现（完全展开）**：

```verilog
// 77 个并行乘法器 + 一棵加法树
// 在同一个时钟周期内完成 77 次乘法和加法树规约

wire signed [15:0] products [0:76];  // 77 个乘积

// 77 个乘法器同时工作
genvar idx;
generate
    for (idx = 0; idx < 77; idx = idx + 1) begin : MAC_TREE
        assign products[idx] = $signed(act[idx]) * $signed(wgt[idx]);
    end
endgenerate

// 加法树（分两级流水线以提高频率）
// Level 1：77个乘积 → 39个部分和
// Level 2：39个部分和 → 最终 INT32 结果
```

但完全展开需要 77 个乘法器，面积代价较大。

### 4.4 实用方案：部分展开 + 流水线

在**高性能场景**中，最常见的平衡点是**固定并行度 P**：

- 每周期计算 P 个乘法，经过流水线加法树规约
- 总共需要 `ceil(77/P)` 个周期完成一个像素的卷积

**本项目推荐方案**（见 `02_Architecture_Design.md` 详细分析）：

对于 Conv 层，设计 **32 个并行 MAC 阵列**（每个阵列处理一个输出通道），每个阵列完全展开 77 个乘法器，用一棵 7 级加法树在 1 个周期内完成：

```
并行度 = 32（通道维度）× 77（空间维度完全展开）= 2464 乘法器
每 1 个时钟周期输出 32 个通道的 1 个像素
总周期数 = OUT_H × OUT_W = 20 × 4 = 80 个时钟周期
```

### 4.5 偏置加法与重量化的集成

完整的卷积计算在 RTL 中分为三个阶段：

```
阶段 1（MAC）：accumulate() × 77   →  INT32 partial sum
阶段 2（Bias）：acc += bias         →  INT32 with bias
阶段 3（Requant）：INT32 × M0 >> n →  INT8 output
```

在 Verilog 中，这三个阶段形成一条**更深的流水线**，实现最大吞吐量。

---

## 小结：四个关键技术的相互关系

```
输入 SRAM
    │
    ▼
LineBuffer（行缓冲）
──────────────────────────────────────────
每拍输出一个 KH×KW 窗口（77 个 INT8 值）
    │
    ▼
MAC 阵列（并行计算单元）
──────────────────────────────────────────
C 个通道并行，每通道有 77 个乘法器
一个流水线加法树（7 级流水线）
每拍输出 C 个 INT32 累加中间值
    │
    ▼ （77 拍后 or 1 拍如果完全展开）
偏置加法 + 重量化（流水线化）
──────────────────────────────────────────
两级流水线（乘法 → 移位截断）
输出 C 个 INT8 像素
    │
    ▼
输出 SRAM（Ping-Pong 双 Bank）
──────────────────────────────────────────
当前帧写一个 Bank，下一层读另一个 Bank
```

这四个技术共同构成了 CNN 加速器 RTL 设计的完整计算-存储-缓冲体系。

---

*下一步：阅读 `02_Architecture_Design.md`，了解如何利用以上技术完成满足 1000K FPS 指标的完整架构设计。*
