# 下一步开发提示

---

## 1. 当前状态

Conv1 层已完成：
- 完整的 RTL 代码（LineBuffer + MACUnit + RequantUnit + Top）
- Testbench 和测试向量生成脚本
- 功能验证框架

---

## 2. 接下来要做的事（按优先级）

### 2.1 仿真验证与调试

**第一步：运行仿真**
```bash
# 生成测试向量
cd scripts && python gen_testvec.py

# 编译仿真（iverilog 示例）
cd ../sim
iverilog -o sim.vvp -I ../rtl ../rtl/*.v ../tb/tb_Conv1.v
vvp sim.vvp

# 查看波形
gtkwave tb_Conv1.vcd
```

**常见问题排查**：
- 如果金标准比对失败，首先检查窗口提取的数据排列顺序
- 检查权重存储的地址映射是否与 gen_testvec.py 的顺序一致
- 用 `$display` 打印关键信号值进行调试

### 2.2 时序优化（如果关键路径过长）

当前 MAC + Requant 是纯组合逻辑，关键路径较长。如果综合后时序不满足：

**方案 A: 在 MAC 和 Requant 之间插入流水寄存器**
```verilog
// Conv1_Top.v 中添加
reg [31:0] mac_result_r [0:31];  // 流水寄存器
always @(posedge clk) begin
    for (i = 0; i < 32; i = i + 1)
        mac_result_r[i] <= mac_result[i];
end
// Requant 使用 mac_result_r 而非 mac_result
```
代价：增加 1 周期延迟，总推理 92 周期。

**方案 B: 将 MAC 内部加法树分为 2-3 级流水**
- Level 1: 77 个乘法 → 39 个加法
- Level 2: 39 → 10 个加法
- Level 3: 10 → 1 + bias
- 代价：增加 2 周期延迟，但可跑更高频率。

### 2.3 权重存储优化

当前权重用寄存器阵列（19712 bit），面积偏大。改进方案：

**使用 SRAM 宏单元**：
- 将 2464 × 8 bit 权重存入工艺库 SRAM
- SRAM 面积远小于等效寄存器
- 需要处理 SRAM 单端口的读写冲突（权重在 CALC_RUN 时只读）
- 可以使用多 bank SRAM 提供足够带宽（32 个 MAC 同时读权重）

**SRAM 组织建议**：
```
方案 1: 32 个小 SRAM（每个 filter 一个），每个 77×8 = 616 bit
         优点: 无地址冲突，全并行读取
         缺点: 小 SRAM 面积效率低

方案 2: 1 个大 SRAM（2464×8 bit），分时复用
         优点: 面积最小
         缺点: 需要 32 周期读取所有权重，性能下降

方案 3: 8 个 SRAM bank（类似 MiniCNN），每 bank 77×32 bit
         优点: 折中方案，面积和带宽兼顾
```

---

## 3. DWConv 层开发

### 3.1 DWConv 规格

| 参数 | 值 |
|------|-----|
| 输入 | (32, 20, 4) — 来自 Conv1 输出 |
| 卷积核 | (32, 1, 3, 3) — 逐通道卷积 |
| 输出 | (32, 18, 2) |
| 量化参数 | M0=59, n=11 |

### 3.2 架构建议

- **32 通道全并行**：每个通道独立的 9 路 MAC（共 288 个乘法器）
- **行缓冲**: 3 行 × 4 列 × 32 通道
- **Ping-Pong Buffer**: Conv1 和 DWConv 之间使用双 Bank 缓冲
  - Conv1 计算时写入 Bank A
  - DWConv 从 Bank B 读取上一帧的结果
  - 帧切换时交换 Bank

### 3.3 Conv1 → DWConv 数据转接

Conv1 输出顺序：每周期 32 个通道值，按 (row, col) 顺序
DWConv 需要：每个通道的行数据

**需要"转置存储"**：
```
Conv1 输出: ch0_hw00, ch1_hw00, ..., ch31_hw00    (一个空间位置的 32 通道)
DWConv 需要: ch0_row0 = [ch0_hw00, ch0_hw01, ch0_hw02, ch0_hw03]  (一个通道的一行)
```

建议使用 SRAM 作为中间缓冲，写入时按 Conv1 输出顺序，读取时按 DWConv 需要的通道-行顺序。

---

## 4. PWConv 层开发

### 4.1 PWConv 规格

| 参数 | 值 |
|------|-----|
| 输入 | (32, 18, 2) |
| 卷积核 | (32, 32, 1, 1) — 点卷积 |
| 输出 | (32, 18, 2) |
| 量化参数 | M0=69, n=13 |

### 4.2 架构建议

- 1×1 卷积 = 32 维向量点积
- 每个输出通道：32 个 INT8 乘法 + 加法树
- 32 路输出并行 → 32 × 32 = **1024 个乘法器**
- 每周期处理一个空间位置，共 18 × 2 = 36 周期

---

## 5. 后处理层（MaxPool + Flatten + FC + Sigmoid）

### MaxPool 2×2
- 输入 (32, 18, 2) → 输出 (32, 9, 1)
- 2×2 窗口取最大值，stride=2
- 纯组合逻辑（32 个独立的 4-way max）

### Flatten
- (32, 9, 1) → (288,) — 纯寻址重映射，无实际计算

### FC 层
- 输入 288 维 → 输出 2 维
- 2 × 288 = 576 个乘法
- M0=11, n=15

### Sigmoid
- 查表实现（Sigmoid LUT，参考 MiniCNN 的 sigmoid_lookup_table.txt）

---

## 6. 系统集成

### 6.1 顶层 CNN.v 框架

```
CNN_Top.v
├── Conv1_Top          (输入 → Conv1 输出)
├── PingPong_Buffer    (Conv1 ↔ DWConv 缓冲)
├── DWConv_Top         (DWConv)
├── PWConv_Top         (PWConv)
├── MaxPool            (下采样)
├── FC_Top             (全连接)
└── Sigmoid_LUT        (查表)
```

### 6.2 层间 Ping-Pong 工作模式

```
时间 →
Frame N:    [Conv1 → BufA]   [DWConv ← BufB]
Frame N+1:  [Conv1 → BufB]   [DWConv ← BufA]   [PWConv ← ...]
```

### 6.3 全局状态机

```
RESET → LOAD_ALL_WEIGHTS → INFERENCE_LOOP
                               │
                    ┌──────────┤
                    ▼          │
              [Load Input]     │
                    │          │
              [Conv1]          │
                    │          │
              [DWConv]         │
                    │          │
              [PWConv]         │
                    │          │
              [MaxPool+FC]     │
                    │          │
              [Sigmoid→Output] │
                    │          │
                    └──────────┘
```

---

## 7. 综合与后端提示

### 7.1 综合约束
```tcl
# 目标频率 100~120MHz
create_clock -period 10 [get_ports clk]

# 面积优化（如果面积超标）
set_max_area 0
```

### 7.2 面积优化方向
1. 将寄存器阵列替换为 SRAM 宏单元（权重、中间特征图）
2. 如果面积仍超标，降低并行度（如 Conv1 改为 16 通道并行，2 周期完成）
3. 复用 MAC 单元（Conv1/DWConv/PWConv/FC 共享乘法器阵列）

### 7.3 时序优化方向
1. 插入流水寄存器切割关键路径
2. 使用综合工具的 `compile_ultra` 选项
3. 考虑使用乘法器的流水版本（如果工艺库提供）
