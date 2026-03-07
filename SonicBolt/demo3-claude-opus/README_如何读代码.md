# Conv1 代码阅读指南（新手入门）

> **目标读者**: 刚接触 Verilog RTL 设计的同学
> **阅读时间**: 约 30 分钟
> **前提知识**: 了解基本的 Verilog 语法（`module`、`always`、`assign`）

---

## 一、项目文件一览

```
demo3-claude-opus/
├── Conv1_Top.v              ← 顶层模块（从这里开始读！）
├── conv1_line_buffer.v      ← 环形行缓冲器
├── conv1_window_extract.v   ← 窗口提取（纯组合逻辑）
├── MAC_Tree_77.v            ← MAC 树封装（77路点积）
│   ├── MAC77_Mult.v         ← 流水线第1级：77路乘法
│   ├── MAC77_AddTree_s1.v   ← 流水线第2级：分组部分和
│   └── MAC77_AddTree_s2.v   ← 流水线第3级：最终求和+偏置
├── requant_relu_unit.v      ← 单通道重量化+ReLU
├── requant_relu_vec32.v     ← 32通道并行重量化
├── tb_Conv1.v               ← Testbench（仿真测试平台）
├── data_prepare.py          ← 数据格式转换脚本
└── *.hex                    ← Testbench 加载的数据文件
```

---

## 二、推荐阅读顺序

### 第一步：理解整体架构（Conv1_Top.v）

打开 `Conv1_Top.v`，先不看细节，只看以下三个部分：

1. **模块端口声明**（文件顶部）— 了解模块的输入输出
2. **FSM 状态定义**（`localparam S_IDLE` 等）— 了解有哪些工作阶段
3. **子模块例化**（`u_line_buffer`、`gen_mac`、`u_requant`）— 了解数据通路

> 💡 **技巧**: 在 Verilog 中，`u_xxx` 通常是子模块实例名，`gen_xxx` 是 generate 块名。

### 第二步：理解数据流（自底向上）

按以下顺序阅读子模块：

1. **`conv1_window_extract.v`** — 最简单的模块，纯组合逻辑，理解窗口提取过程
2. **`conv1_line_buffer.v`** — 理解环形缓冲的读写机制
3. **`MAC77_Mult.v`** — 理解 77 路并行乘法
4. **`MAC77_AddTree_s1.v`** — 理解分组加法树
5. **`MAC77_AddTree_s2.v`** — 理解最终求和 + 偏置
6. **`MAC_Tree_77.v`** — 理解三级流水线的封装
7. **`requant_relu_unit.v`** — 理解重量化与 ReLU 激活
8. **`requant_relu_vec32.v`** — 32 通道并行的简单封装

### 第三步：理解控制逻辑（Conv1_Top.v 深入）

回到 `Conv1_Top.v`，重点阅读：
- FSM 状态转移逻辑（`always @(*)` 中的 `case(state)`）
- FSM 输出控制（`always @(posedge clk)` 中的 `case(state)`）

### 第四步：理解验证方法（tb_Conv1.v）

阅读 Testbench 了解：
- 如何用 `$readmemh` 加载数据到存储器
- 如何模拟外部 SRAM 的行为
- 如何验证输出正确性

---

## 三、信号命名约定

本项目遵循以下命名规范：

| 后缀/前缀 | 含义 | 示例 |
|-----------|------|------|
| `_n` | 低电平有效 | `rst_n`（低电平复位） |
| `_d1`, `_d2` | 延迟 1/2 拍 | `bias_d1`（bias 延迟 1 拍） |
| `_s1`, `_s2` | 流水线阶段 1/2 | `mul_s1`（乘法阶段 1 结果） |
| `_flat` | 展平数组 | `act_flat`（77 个 INT8 展平为 616-bit） |
| `_cnt` | 计数器 | `col_cnt`（列计数器） |
| `_reg` | 寄存器文件 | `weight_reg`（权重寄存器） |
| `_mem` | 存储器 | `input_mem`（输入存储器） |
| `_in`, `_out` | 模块输入/输出 | `valid_in`（输入有效信号） |
| `u_` | 子模块实例 | `u_mult`（乘法器实例） |
| `gen_` | generate 块 | `gen_mac`（MAC 树生成块） |

---

## 四、关键概念速览

### 4.1 什么是展平（Flatten）？

Verilog 不支持多维数组端口（某些综合工具不兼容），因此我们将数据"展平"为一维向量：

```verilog
// 77 个 INT8 值，展平为 616-bit 向量
// 访问第 i 个元素：act_flat[i*8 +: 8]
wire [615:0] act_flat;
```

`[i*8 +: 8]` 语法表示"从 bit `i*8` 开始，取 8 个 bit"。

### 4.2 什么是流水线（Pipeline）？

流水线将一个复杂运算拆分成多个阶段，每阶段用寄存器隔开：

```
输入 → [乘法器|寄存器] → [加法树|寄存器] → [求和|寄存器] → 输出
         Stage 1           Stage 2           Stage 3
```

**优点**: 每个阶段的组合逻辑变短，时钟频率可以更高。
**代价**: 第一个结果需要等 3 拍才出来（3 级延迟），但之后每拍出一个结果。

### 4.3 什么是 Data Gating？

```verilog
always @(posedge clk) begin
    if (valid_in)            // ← Data Gating：仅在有效时更新
        prod <= a * b;
end
```

当 `valid_in=0` 时，寄存器不翻转，节省动态功耗。

### 4.4 什么是环形缓冲（Circular Buffer）？

传统方式：每来一新行，所有行向上移位（S1←S2, S2←S3, ...），翻转所有寄存器。

环形缓冲：用一个"写指针"指向最旧的位置，新行只覆盖最旧的行，其他行不动：

```
写指针 → [Row 2] ← 将被覆盖（最旧）
          [Row 3]
          [Row 4]
          ...
          [Row 1] ← 最新写入的
```

**优点**: 每次只翻转 1 行寄存器，节省 ~90% 功耗。

---

## 五、如何跟踪一个数据的完整路径

以"输入第一行、第一个像素"为例：

1. **Testbench** 从 `conv1_input.hex` 加载到 `input_mem[0]`
2. **DUT** 请求 `in_row_addr=0`，TB 返回 `in_row_data=input_mem[0]`
3. **Conv1_Top** 的 `S_FILL_LB` 状态将数据 push 到行缓冲
4. **conv1_line_buffer** 将 80-bit 行数据存入 `line_buf[wr_ptr]`
5. **conv1_window_extract** 从行缓冲输出中切出 11×7=77 个字节
6. **32 个 MAC_Tree_77** 同时接收这 77 个激活值
7. 每个 MAC 树用自己的权重进行点积运算（3 拍延迟）
8. **requant_relu_vec32** 将 32 个 INT32 结果转为 INT8（2 拍延迟）
9. `out_valid` 拉高时，`out_data` 携带 32 通道的输出

---

## 六、常见问题

**Q: 为什么权重需要预加载到寄存器？**
A: 32 个 MAC 树每周期都需要各自的权重，如果从 SRAM 读取，需要 32 个读端口（不现实）。预加载到寄存器后，可以同时并行读取。

**Q: 为什么 `col_cnt` 只有 0~3？**
A: 输入宽度 10，卷积核宽度 7，步长 1。输出宽度 = 10 - 7 + 1 = 4，所以 4 个水平位置。

**Q: 为什么输出有 80 个有效周期？**
A: 输出特征图 20×4 = 80 个空间位置。每个位置输出 32 个通道（一次性）。

**Q: `$signed()` 是什么意思？**
A: 告诉综合器把该信号当有符号数处理。INT8 的范围是 -128~127，需要有符号运算。

---

## 七、推荐调试方法

1. **查看波形**: 用 `$dumpfile`/`$dumpvars` 生成 VCD 文件，用 GTKWave 打开
2. **添加打印**: 在 `always @(posedge clk)` 中加 `$display` 打印关键信号
3. **单步分析**: 将 `TIMEOUT` 设小，观察前几个输出是否正确
4. **对比 Golden**: 用 `diff` 命令比较 `hw_output.txt` 和 `conv1_golden.hex`
