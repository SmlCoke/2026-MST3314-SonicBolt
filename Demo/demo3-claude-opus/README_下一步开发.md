# 下一步开发指南

> 本文档描述 Conv1 完成后的后续开发路线，包含 DWConv、PWConv、后处理链的接入方案以及全芯片集成建议。

---

## 一、整体开发路线图

```
Phase 1 ✅  Conv1（标准卷积）
Phase 2     DWConv（深度可分离卷积）+ Activation2
Phase 3     PWConv（逐点卷积）+ Activation3
Phase 4     后处理链（MaxPool → Flatten → FC → Sigmoid）
Phase 5     全芯片集成（顶层控制器 + SRAM接口 + I/O）
Phase 6     逻辑综合 + 时序分析 + 物理设计
```

---

## 二、Phase 2: DWConv 深度可分离卷积

### 2.1 算法规格

| 参数 | 值 |
|------|---|
| 输入 | (32, 20, 4) INT8 |
| 权重 | (32, 1, 3, 3) INT8 |
| 偏置 | (32) INT32 |
| 输出 | (32, 18, 2) INT8 |
| stride | 1 |
| padding | 0 |
| 重量化 | M0=59, N=11 |

### 2.2 架构建议

DWConv 的关键特点是**无跨通道计算** — 每个通道独立处理，卷积核只有 3×3=9 个元素。

**推荐架构**: 32 通道并行，每通道一个 9 路 MAC

```
输入数据 ──→ [32 通道行缓冲 + 窗口提取] ──→ [32 × MAC_Tree_9] ──→ [requant_relu_vec32]
                                                                      M0=59, N=11
```

**行缓冲设计**:
- 卷积核高度只有 3，行缓冲只需 3 行
- 但有 32 个通道，每通道 4 个 INT8 = 32 bit
- 总存储：32通道 × 3行 × 32-bit = 3072 bit
- 建议用寄存器实现（量小且多通道并行读取）

**MAC_Tree_9**:
- 复用 MAC_Tree_77 的设计模式，但规模小得多
- 9 路乘法 → 3 级加法树（4+4+1 → 2+1 → 1）→ +bias
- 可以 2 级流水甚至组合逻辑（关键路径短）

**性能估算**:
- 输出空间: 18×2 = 36 个位置
- 每位置 1 周期 → 36 周期/帧
- 行切换气泡: 17 次 × 1 周期 = 17 周期
- 总计: ~55 周期

### 2.3 Conv1 → DWConv 数据传递

Conv1 输出 (32, 20, 4) = 2560 字节。DWConv 需要按 (通道, 行, 列) 顺序访问。

**选项 A**: 片上 SRAM 缓存
- 将 Conv1 输出写入一块 2560×8-bit SRAM
- DWConv 从 SRAM 逐行读取
- 优点：简单可控；缺点：SRAM 面积

**选项 B**: Ping-Pong 双缓冲（推荐）
- 用两块 SRAM 交替读写
- Conv1 写入 Bank A 的同时，DWConv 读取 Bank B（上一帧数据）
- 实现帧级流水线，隐藏 SRAM 访问延迟

**选项 C**: 流式传递（高级）
- Conv1 的输出直接流入 DWConv 的行缓冲
- 需要仔细对齐两层的输出/输入时序
- 最省存储但控制复杂

### 2.4 数据排列问题

Conv1 输出顺序: `(row, col)` 遍历，每次输出 32 通道  
DWConv 输入顺序: 需要按通道独立读取行数据

→ 存储时按 `[row][col]` 排列，32 通道打包在同一地址，DWConv 读取时同一地址获取 32 通道的同一像素。

---

## 三、Phase 3: PWConv 逐点卷积

### 3.1 算法规格

| 参数 | 值 |
|------|---|
| 输入 | (32, 18, 2) INT8 |
| 权重 | (32, 32, 1, 1) INT8 |
| 偏置 | (32) INT32 |
| 输出 | (32, 18, 2) INT8 |
| 重量化 | M0=69, N=13 |

### 3.2 架构建议

PWConv 是 1×1 卷积，**无空间滑窗**，但需要**跨通道求和**（32 个输入通道加权求和）。

**推荐架构**: 32 输出通道并行，每通道一个 32 路 MAC

```
输入像素 ──→ [广播 32个INT8] ──→ [32 × MAC_Tree_32] ──→ [requant_relu_vec32]
                                  各通道权重 (32×INT8)     M0=69, N=13
```

**MAC_Tree_32**: 32 路 INT8×INT8 乘法 + 加法树 + bias

**性能估算**:
- 输出空间: 18×2 = 36 个像素
- 每像素 1 周期 → 36 周期/帧

### 3.3 权重存储

PWConv 权重: 32×32 = 1024 个 INT8 = 1024 字节  
建议预加载到片上寄存器（与 Conv1 相同策略）。

---

## 四、Phase 4: 后处理链

### 4.1 MaxPool

```
输入: (32, 18, 2) INT8
输出: (32, 9, 1)  INT8
核: 2×2, stride=2
```

- 每 2×2 区域取最大值
- 32 通道并行比较器
- 1 周期/输出 → 9 周期

### 4.2 Flatten

```
输入: (32, 9, 1) INT8
输出: (288)      INT8
```

纯地址映射，无计算。将 32通道×9行 展为 288 维向量。

### 4.3 FC 全连接层

```
输入: (288) INT8
权重: (2, 288) INT8
偏置: (2) INT32
输出: (2) INT8
重量化: M0=11, N=15
```

- 2 个输出神经元，各做 288 维点积
- 可用 2 个 MAC 累加器，每周期处理若干维度
- 288 周期全串行，或 32 路并行仅需 9 周期

### 4.4 Sigmoid 查找表

```
输入: (2) INT8
输出: (2) FP32
```

- 256 条查找表（INT8 索引 → FP32 值）
- 用 SRAM 或 ROM 实现
- 数据文件: `sigmoid_lookup_table.txt`

---

## 五、Phase 5: 全芯片集成

### 5.1 顶层控制器

```
CNN_Top
├── Conv1_Top         ← 已完成
├── DWConv_Top
├── PWConv_Top
├── PostProcess_Top
│   ├── MaxPool
│   ├── FC
│   └── Sigmoid
├── SRAM_Controller
├── Ping_Pong_Buffer
└── Global_FSM
```

**全局 FSM**:
```
IDLE → LOAD_INPUT → CONV1 → DWCONV → PWCONV → POSTPROCESS → OUTPUT → IDLE
```

Ping-Pong 模式下可以重叠相邻层的计算（双缓冲）。

### 5.2 SRAM 接口设计

**输入 SRAM**: 存储输入特征图 (300 B)
- 单端口，地址宽度 5 bit（30 行），数据宽度 80 bit

**参数 SRAM**: 存储所有层的权重和偏置
- Conv1 权重: 2464 B
- DWConv 权重: 288 B
- PWConv 权重: 1024 B
- 偏置: 128×3 = 384 B
- FC 权重: 576 B
- 总计: ~4736 B → 用 1 块大 SRAM 或按层分块

**中间缓存 SRAM**: Ping-Pong 双缓冲
- 最大层间数据: (32, 20, 4) = 2560 B
- 两块 SRAM: 2 × 2560 B = 5120 B

### 5.3 I/O 管脚规划

老师提到"IO 不能过多"。建议:

| 类别 | 管脚 | 位宽 |
|------|------|------|
| 时钟/复位 | clk, rst_n | 2 |
| 控制 | start, done | 2 |
| 输入数据 | data_in | 8 |
| 输入地址 | addr_in | 10 |
| 输入控制 | wr_en, rd_en | 2 |
| 输出数据 | data_out | 32 |
| 输出控制 | out_valid | 1 |
| **总计** | | **~57 管脚** |

---

## 六、Phase 6: 综合与优化

### 6.1 逻辑综合 (Design Compiler)

关键约束:
```tcl
set_clock_period 10.0 [get_clocks clk]   ;# 100MHz
set_input_delay 2.0 -clock clk [all_inputs]
set_output_delay 2.0 -clock clk [all_outputs]
```

### 6.2 时序分析重点

- MAC 树的乘法器链是**关键路径**
- 如果时序违例，可以:
  1. 在乘法器后增加一级寄存器
  2. 使用 DesignWare 的乘法器 IP
  3. 降低频率到 80MHz（但需调整并行度来补偿吞吐量）

### 6.3 面积优化

- 如果面积过大，考虑缩减通道并行度（如 16 通道分 2 轮）
- 权重寄存器可改为 SRAM（分时读取，但降低吞吐）
- 乘法器可以用 Booth 编码优化

### 6.4 功耗优化

- **Clock Gating**: 非计算阶段关闭 MAC 树时钟
- **Data Gating**: 已在设计中实现（valid 控制寄存器更新）
- **降低翻转率**: 环形行缓冲已优化

---

## 七、开发建议

### 7.1 验证策略

每完成一层，用 Python golden 数据逐层验证:
- `Test/Out_Conv.txt` → Conv1 验证 ✅
- `Test/Out_DWConv.txt` → DWConv 验证
- `Test/Out_PWConv.txt` → PWConv 验证
- `Test/Out_Linear.txt` → FC 验证
- `Test/Out.txt` → Sigmoid 验证

### 7.2 数据准备

每层都需要类似 `data_prepare.py` 的脚本:
- 读取原始参数和 golden 数据
- 生成 `$readmemh` 可加载的 hex 文件
- 确保数据排列与硬件遍历顺序一致

### 7.3 答辩重点

- **创新点**: 环形行缓冲（低功耗）、Input Broadcasting（高利用率）、寄存器预加载（避免 SRAM 冲突）
- **与其他团队的差异化**: 重点强调 32 通道全并行的设计决策和性能/面积折中分析
- **量化数据**: 每帧周期数、FPS、乘法器利用率、功耗估算
