# Conv1 代码阅读指南（新手入门版）

> 本文档帮助零基础的同学理解 Conv1 的 Verilog 代码。
> 阅读前建议先了解基本的 Verilog 语法（`module`, `wire`, `reg`, `always`, `assign`）。

---

## 1. 文件总览

```
demo2-claude/
├── rtl/                        ← 可综合的 RTL 代码
│   ├── Conv1_LineBuffer.v      ← 行缓冲器（数据暂存）
│   ├── Conv1_MACUnit.v         ← 乘累加单元（核心计算）
│   ├── Conv1_RequantUnit.v     ← 重量化单元（INT32→INT8）
│   └── Conv1_Top.v             ← 顶层模块（状态机+集成）
├── tb/
│   └── tb_Conv1.v              ← 仿真测试平台
├── scripts/
│   └── gen_testvec.py          ← 生成测试向量的 Python 脚本
├── sim/                        ← 仿真数据文件（由脚本生成）
│   ├── input.txt
│   ├── weight.txt
│   ├── bias.txt
│   └── golden_output.txt
└── docs/                       ← 文档
```

**建议阅读顺序**：先读子模块（从简单到复杂），最后读顶层。

```
Conv1_RequantUnit.v  →  Conv1_MACUnit.v  →  Conv1_LineBuffer.v  →  Conv1_Top.v  →  tb_Conv1.v
    (最简单)              (核心运算)          (数据管理)           (状态机集成)       (仿真)
```

---

## 2. 逐文件阅读指导

### 2.1 Conv1_RequantUnit.v — 从最简单的开始

**它做什么？**
把一个大数字（INT32）变成一个小数字（INT8）。

**核心公式**：
```
output = clamp( (input × 111) >> 14,  -128,  127 )
```

**关键概念**：
| 概念 | 解释 |
|------|------|
| `>>>` | 算术右移，保留符号位（正数补0，负数补1）|
| `clamp` | 限制数值范围：小于-128变-128，大于127变127 |
| `M0=111, n=14` | 量化参数，相当于乘以 0.006775 |

**为什么需要这一步？**
卷积的中间结果是 32 位整数（很大），但下一层需要 8 位输入。重量化就是做这个"缩放"。

---

### 2.2 Conv1_MACUnit.v — 核心乘累加

**它做什么？**
输入一个 11×7 的窗口（77 个像素）和同样大小的卷积核（77 个权重），做"逐元素相乘再求和"。

**核心运算**：
```
result = bias + Σ(input[i] × weight[i]),  i = 0, 1, ..., 76
```

**代码结构**：
1. **乘法器阵列**（generate for 循环）：77 个 8×8 乘法器并行工作
2. **加法树**（always 块中的 for 循环）：把 77 个乘积加起来

**位宽跟踪**：
```
输入: 8 bit × 8 bit = 16 bit 乘积
77 个 16-bit 相加 → 需要 23 bit（16 + log2(77) ≈ 23）
加上 16-bit 偏置（先符号扩展到 32 bit）→ 用 32 bit 就够了
```

**新手易混淆**：
- `genvar` vs `integer`：`genvar` 用于 `generate` 块（硬件展开），`integer` 用于 `always` 块（行为描述）
- `$signed()`: 告诉综合工具这是有符号数运算

---

### 2.3 Conv1_LineBuffer.v — 循环行缓冲

**它做什么？**
存储 11 行输入数据。每来一行新数据，替换掉最旧的那一行。输出按"逻辑顺序"排列（第 0 行 = 最旧，第 10 行 = 最新）。

**核心思路 — 循环缓冲**：
```
物理位置:  [0] [1] [2] [3] [4] [5] [6] [7] [8] [9] [10]
           ↑
         wr_ptr（写指针，指向下一个要被覆盖的位置）

新数据写入 wr_ptr 位置，然后 wr_ptr 向后移一格。
移到末尾就绕回开头（循环）。
```

**为什么用循环缓冲而不是移位？**
如果用移位，每来一行新数据需要把所有 11 行都搬一遍（10 × 80 = 800 个寄存器的数据移动）。
循环缓冲只需要写入 1 行 + 移动 1 个 4-bit 指针，功耗和面积都小很多。

**逻辑→物理映射**：
```
逻辑行 i → 物理位置 (wr_ptr + i) % 11
```
代码中用比较 + 减法代替取模（`%11` 不利于综合）。

---

### 2.4 Conv1_Top.v — 顶层模块（最复杂，分段读）

这个文件有 5 大部分，建议分段阅读：

#### 第一段：参数和信号声明（开头 ~ FSM 状态定义）
- 熟悉各个接口的含义
- 理解 `localparam` 定义的常量（NUM_FILTERS=32, KERNEL_H=11 等）

#### 第二段：子模块实例化（LineBuffer + 32 个 MAC + 32 个 Requant）
- `generate for` 循环创建 32 个 MAC 和 32 个 Requant
- 所有 32 个 MAC 共享同一个窗口数据（`window_flat`），但各自使用不同的权重

#### 第三段：窗口数据提取（Window Extraction）
- 从 11 行 × 10 列中，根据 `col_cnt` 提取 11×7 的窗口
- `col_cnt=0`: 取第 0~6 列
- `col_cnt=1`: 取第 1~7 列
- `col_cnt=3`: 取第 3~9 列

#### 第四段：FSM 状态机
```
IDLE → LOAD_WEIGHT → LOAD_BIAS → FILL_LB → CALC_RUN → DONE → IDLE
```
每个状态做什么：
| 状态 | 做什么 | 持续周期 |
|------|--------|----------|
| IDLE | 等待 start 信号 | 不定 |
| LOAD_WEIGHT | 从端口接收 2464 个权重 | 2464 |
| LOAD_BIAS | 从端口接收 32 个偏置 | 32 |
| FILL_LB | 从 SRAM 读取前 11 行 | 11 |
| CALC_RUN | 滑动窗口计算所有输出 | 80 |
| DONE | 发出完成信号 | 1 |

#### 第五段：计数器和地址生成
- `row_cnt` (0~19): 当前计算的输出行
- `col_cnt` (0~3): 当前计算的输出列
- `col_cnt==3` 时：触发读取下一行到行缓冲
- SRAM 地址生成：`FILL_LB` 时 `addr=0~10`，`CALC_RUN` 时 `addr=row_cnt+11`

---

### 2.5 tb_Conv1.v — 仿真测试平台

**它做什么？**
1. 用 `$readmemh` 从 `.txt` 文件加载测试数据
2. 驱动 Conv1_Top 的输入端口
3. 捕获输出并保存到 `hw_output.txt`
4. 自动与金标准比对，报告 PASS/FAIL

**仿真流程**：
```
复位 → start → 送权重(2464 clk) → 送偏置(32 clk) → 等待计算(~91 clk) → 完成
```

**如何运行**（以 iverilog 为例）：
```bash
cd scripts && python gen_testvec.py    # 生成测试向量
cd ../sim
iverilog -o sim.vvp -I ../rtl ../rtl/*.v ../tb/tb_Conv1.v
vvp sim.vvp
```

---

## 3. 常见问题

### Q: `generate for` 和 `always for` 有什么区别？
- `generate for` + `genvar`：在编译时展开，生成**多个独立的硬件实例**
- `always for` + `integer`：在运行时循环，描述**组合逻辑的行为**（综合器推导出加法树等）

### Q: 为什么用 `$signed()` 函数？
Verilog 默认把 `wire/reg` 当作无符号数。当你需要做有符号运算（如 INT8 的 -128~127），需要用 `$signed()` 或在声明时加 `signed` 关键字。

### Q: 非阻塞赋值 `<=` vs 阻塞赋值 `=`？
- `<=`（非阻塞）：用在 `always @(posedge clk)` 中，模拟寄存器行为，赋值在时钟沿结束时生效
- `=`（阻塞）：用在 `always @(*)` 中，模拟组合逻辑，立即生效

### Q: 窗口数据的排列顺序是什么？
```
window_flat[7:0]   = 第 0 行第 0 列的像素
window_flat[15:8]  = 第 0 行第 1 列的像素
...
window_flat[55:48] = 第 0 行第 6 列的像素
window_flat[63:56] = 第 1 行第 0 列的像素
...
window_flat[615:608] = 第 10 行第 6 列的像素
```
权重的排列顺序完全一致，这样第 i 个乘法器就是 `window[i] × weight[i]`。

### Q: `+:` 语法是什么意思？
```verilog
data[i*8 +: 8]   // 从第 i*8 位开始，取 8 位
                   // 等价于 data[i*8+7 : i*8]
```
这是 Verilog-2001 的 "indexed part-select" 语法，适用于循环中的位片选取。
