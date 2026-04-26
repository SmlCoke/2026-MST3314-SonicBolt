# CNN 加速器物理设计时序违例与拥塞修复报告

> 设计: `cnn_chip` | 工艺: SMIC 0.18um 5ML | 时钟频率: 100MHz (10ns) | ICC 版本: O-2018.06-SP1

---

## 目录

1. [时序违例汇总](#1-时序违例汇总)
2. [拥塞与 DRC 问题汇总](#2-拥塞与-drc-问题汇总)
3. [LVS / 连接性问题汇总](#3-lvs--连接性问题汇总)
4. [根因分析](#4-根因分析)
5. [修复方案](#5-修复方案)

---

## 1. 时序违例汇总

### 1.1 各阶段时序违例概览

| 阶段 | 时钟网络 | 最差路径 | Slack (ns) | 路径类型 |
|------|---------|----------|------------|----------|
| data_setup | Ideal (ZWL) | conv_tile_mac 乘加路径 | 0.00 (MET) | clk |
| data_setup_zic | Ideal (ZIC) | conv_tile_mac 乘加路径 | 0.00 (MET) | clk |
| **floorplan** | Ideal (0% routed) | **out_pos_reg[0] → g_weight_bank[2]** | **-49.99** | clk |
| **floorplan** | Ideal (0% routed) | **active_bank_reg → img_wr_ready** | **-24.76** | OUTPUTS |
| **floorplan** | Ideal (0% routed) | **img_wr_row_data[73] → shadow_cache_pong** | **-16.66** | INPUTS |
| **placement** | Ideal (0% routed) | **out_row_sum_bus_reg[530]** | **-27.96** | clk |
| **placement** | Ideal (0% routed) | **stage0_valid_reg → out_stream_valid** | **-21.39** | OUTPUTS |
| **placement** | Ideal (0% routed) | **img_wr_addr[3] → shadow_cache_ping** | **-5.47** | INPUTS |
| **cts_only_cts** | Propagated (90.47% routed) | **out_row_sum_bus_reg[530]** | **-31.80** | clk |
| **cts_only_cts** | Propagated (90.47% routed) | **stage0_valid → out_stream_valid** | **-25.78** | OUTPUTS |
| **cts_only_cts** | Propagated (90.47% routed) | **shadow_cache_pong_reg[0][10]** | **-8.77** | INPUTS |
| **cts_only_psyn** | Propagated (post hold fix) | **out_row_sum_bus_reg[606]** | **-27.51** | clk |
| **cts_only_psyn** | Propagated (post hold fix) | **stage0_valid_reg → out_stream_valid** | **-21.08** | OUTPUTS |
| **cts_only_psyn** | Propagated (post hold fix) | **shadow_cache_pong_reg[0][2]** | **-6.55** | INPUTS |
| **route_initial1** | RealRC | **out_delta_cls1_reg[16]** | **-3.73** | clk |
| **route_initial1** | RealRC | **shadow_cache_ping_reg[5][73]** | **-2.32** | INPUTS |
| **route_power1** | RealRC | **out_delta_cls1_reg[31]** | **-3.40** | clk |
| **route_power1** | RealRC | **u_frame_store_pong** | **-2.01** | INPUTS |

### 1.2 关键时序路径详细分析

#### 1.2.1 最严重违例路径 #1：conv_tile_mac 乘加路径 (clk, -31.80ns)

- **起点**: `u_row_mult_5/weight_row_data_reg_reg[191]` (DFFRHQXL)
- **终点**: `u_row_mult_5/out_row_sum_bus_reg[530]` (DFFRHQXL)
- **数据到达时间**: 51.63ns
- **数据要求时间**: 19.84ns
- **违例量**: **-31.80ns** (占时钟周期 318%)
- **特征**: 通过 7 级乘加树 + 大量 BUFFER 链（共约30级逻辑），其中插入了 BUFX20/BUFX12/BUFX8 等大驱动 buffer，表明该路径扇出或线负载较大
- **对应 RTL**: `src/conv/conv_tile_mac_row_mult.v` — 7 个 INT8 乘法器 + 三级加法树，全部组合逻辑，仅输出处打一拍

```
路径概要:
  weight_row_data_reg[191]/CK  →  Q (21.73ns cell delay)
  → CLKBUFX8 (6.25ns) → BUFX20 (0.33ns) → BUFX20 (0.25ns)
  → CLKBUFX20 (0.24ns) → BUFX20 (0.23ns) → BUFX12 (0.33ns)
  → NAND2BX1 → BUFX8 → OAI2BB1X1 → ...(~18 more gates)...
  → out_row_sum_bus_reg[530]/D
```

#### 1.2.2 最严重违例路径 #2：out_stream_valid 输出路径 (OUTPUTS, -25.78ns)

- **起点**: `u_sigmoid/stage0_valid_reg` (DFFRHQXL)
- **终点**: `out_stream_valid` (output port, PO8W pad)
- **数据到达时间**: 41.05ns
- **数据要求时间**: 15.27ns
- **违例量**: **-25.78ns**
- **特征**: 单级寄存器 Q 端有 20.58ns cell delay（DFFRHQXL），然后经过 CLKBUFX16 → BUFX16 → BUFX2 → PO8W pad
- **根本原因**: 寄存器到 pad 的物理距离过长，需要大驱动 buffer 链，且路径穿越了多个层级

#### 1.2.3 违例路径 #3：输入路径 (INPUTS, -8.77ns CTS / -2.32ns Route)

- **CTS阶段**: `img_wr_addr[2]` → `shadow_cache_pong_reg[0][10]`, -8.77ns
- **Route阶段**: `img_wr_row_data[73]` → `shadow_cache_ping_reg[5][73]`, -2.32ns
- **特征**: 从 pad (PIW) 到内部 shadow_cache 寄存器，经过大量 BUFX20/CLKBUFX20 链
- **根本原因**: pad ring 与内部 shadow cache 物理距离远，数据需要穿过整个芯片

#### 1.2.4 违例路径 #4：FC 层 MAC 路径 (clk, -3.73ns / -3.40ns)

- **起点**: `fc_weight_sram` (SRAM macro)
- **终点**: `out_delta_cls1_reg[16]` / `out_delta_cls1_reg[31]`
- **Route 阶段违例**: -3.73ns ~ -3.40ns
- **特征**: SRAM Q 端输出延迟 2.27ns，后接 25+ 级标准单元逻辑
- **对应 RTL**: `src/post_process/fc_mac.v` — 8 个 INT8 乘法器 + 2 级加法树 + 流水打拍

#### 1.2.5 Floorplan 阶段违例详情（3 条路径）

**背景**: floorplan 阶段时钟网络 0% 已布线，时钟为 ideal 网络，RC 使用 RealRVirtualC 模式。此阶段即使时钟为理想网络，依然出现严重的建立时间违例，说明组合逻辑深度已经超出时钟周期的承受能力。

##### Floorplan 路径 #1：dwconv weight_bank 使能路径 (clk, **-49.99ns** — 全场最差)

- **起点**: `u_conv_rescale_relu/u_meta_pipe_stage2/out_pos_reg[0]` (DFFRHQXL)
- **终点**: `u_dwconv_param_store/g_weight_bank[2].u_weight_bank` (S018V3EBCDSP_X8Y4D96_PR SRAM)
- **数据到达时间**: 61.94ns
- **数据要求时间**: 11.95ns
- **违例量**: **-49.99ns** (占时钟周期 500%)
- **关键瓶颈**:
  - 单级 `INVX1` 延迟高达 **36.35ns**（`inst_cnn/dwconv_inst/u69/Y`），表明该 inverter 距离 SRAM 的 CEN 端口物理距离极远
  - SRAM CEN 端口 setup time 要求 **1.85ns**（S018V3EBCDSP 工艺 SRAM 的特性）
  - 路径穿越 conv_core → conv_subsystem → dwconv_subsystem → dwconv_core → dwconv_param_store，跨多个层次模块

```
路径概要:
  out_pos_reg[0]/CK → Q (0.81ns)
  → OR4X2 (2.06ns) → NAND2X1 (0.75ns) → INVX1 (0.59ns)
  → INVX1 (2.48ns) → INVX1 (8.97ns)
  → [穿越 conv → dwconv 层次边界]
  → INVX1 (36.35ns!!) → u_weight_bank/CEN (5.64ns setup)
  = 61.94ns arrival vs 11.95ns required
```

##### Floorplan 路径 #2：img_wr_ready 输出路径 (OUTPUTS, **-24.76ns**)

- **起点**: `active_bank_reg` (DFFSX1)
- **终点**: `img_wr_ready` (output port, PO8W pad)
- **数据到达时间**: 33.56ns
- **数据要求时间**: 8.80ns
- **关键瓶颈**:
  - `AOI22X1` 延迟 **18.15ns** — 该 gate 到 pad 的物理距离远
  - `PO8W_img_wr_ready/PAD` 延迟 **5.94ns** — pad 驱动能力有限

```
路径概要:
  active_bank_reg/CK → Q (3.83ns) → INVX1 (0.19ns)
  → CLKINVX3 (0.97ns) → NOR2X1 (0.18ns) → AOI22X1 (18.15ns!!)
  → PO8W_img_wr_ready/PAD (5.94ns) → img_wr_ready
  = 33.56ns arrival vs 8.80ns required
```

##### Floorplan 路径 #3：输入数据到 shadow_cache 路径 (INPUTS, **-16.66ns**)

- **起点**: `img_wr_row_data[73]` (input port)
- **终点**: `shadow_cache_pong_reg[6][73]` (DFFRXL)
- **数据到达时间**: 30.20ns
- **数据要求时间**: 13.55ns
- **关键瓶颈**:
  - `gen_piw_.../u_piw/C` (PIW pad) 延迟 **9.05ns** — 输入 pad 延时大
  - `u35513/Y` (INVX1) 延迟 **8.09ns** — pad 到内部逻辑的长走线

```
路径概要:
  img_wr_row_data[73] → BUFX3 (0.89ns) → BUFX3 (0.61ns)
  → BUFX4 (0.28ns) → CLKBUFX16 (1.42ns) → PIW/PAD (9.05ns!!)
  → INVX1 (8.09ns!!) → MXI2X1 (0.54ns) → shadow_cache_pong_reg/D
  = 30.20ns arrival vs 13.55ns required
```

##### Floorplan 违例小结

| 违例根源 | 表现 | Slack |
|----------|------|-------|
| 跨层次长距离控制路径 (conv→dwconv) | `u69/Y` INV 单级延迟 36.35ns | -49.99ns |
| 内部寄存器到 pad 的长距离 | `AOI22X1` 单级延迟 18.15ns | -24.76ns |
| 输入 pad 到内部寄存器的长距离 | PIW pad 延迟 9.05ns | -16.66ns |

**共同特征**: 三条路径都在 ideal 时钟下就出现严重违例，说明物理布局（macro 位置、pad ring 位置）引入了巨大的线延迟。

#### 1.2.6 Placement 阶段违例详情（3 条路径）

**背景**: placement 阶段已完成 `place_opt`，但时钟网络仍为 ideal (0% routed)。违例相较 floorplan 阶段有所改善（工具的 place_opt 做了初步优化），但依然严重。

##### Placement 路径 #1：conv_tile_mac 乘加路径 (clk, **-27.96ns**)

- **起点**: `u_row_mult_5/weight_row_data_reg_reg[191]` (DFFRHQXL)
- **终点**: `u_row_mult_5/out_row_sum_bus_reg[530]` (DFFRHQXL)
- **数据到达时间**: 41.52ns
- **数据要求时间**: 13.56ns
- **违例量**: **-27.96ns**
- **关键瓶颈**:
  - 寄存器 Q 端延迟 **21.64ns** — 该寄存器的负载/扇出极大
  - 后续 30 级组合逻辑（XNOR/XOR/AND/OR/OAI/AOI 链条）
  - 中间 `OAI21XL` 延迟 **2.75ns**
  - `XNOR2X1` 延迟 **1.08ns**

**与 CTS 阶段对比**: cts_only_cts 报告中同一路径违例为 -31.80ns（恶化 3.84ns），说明 CTS 引入的实际时钟延迟使违例进一步恶化。

##### Placement 路径 #2：out_stream_valid 输出路径 (OUTPUTS, **-21.39ns**)

- **起点**: `u_sigmoid/stage0_valid_reg` (DFFRHQXL)
- **终点**: `out_stream_valid` (output port, PO8W pad)
- **数据到达时间**: 30.19ns
- **数据要求时间**: 8.80ns
- **关键瓶颈**: 寄存器 Q 端延迟 **20.53ns** — 该寄存器位于 post_process 子系统中，距离输出 pad 极远

**与 floorplan 阶段对比**: floorplan 时还存在 `img_wr_ready` 输出违例（-24.76ns），placement 后 img_wr_ready 得到改善，但 `out_stream_valid` 依然在 -21.39ns。

##### Placement 路径 #3：输入地址到 shadow_cache 路径 (INPUTS, **-5.47ns**)

- **起点**: `img_wr_addr[3]` (input port)
- **终点**: `shadow_cache_ping_reg[0][23]` (DFFRXL)
- **数据到达时间**: 19.12ns
- **数据要求时间**: 13.65ns
- **关键瓶颈**: PIW pad 延迟 1.35ns, 内部 MXI2X1 (多路选择器) 前经过多个 BUFX20 链

```
路径概要:
  img_wr_addr[3] → PIW/C (1.35ns) → CLKBUFX20 (0.37ns)
  → OR3X4 (0.74ns) → BUFX20 (0.27ns) → BUFX20 (0.33ns)
  → OAI31X2 (2.40ns) → BUFX8 (0.36ns) → NAND3X2 (1.95ns)
  → BUFX16 (0.61ns) → BUFX20 (0.32ns) → BUFX20 (0.40ns)
  → MXI2X1 (0.40ns) → shadow_cache_ping_reg/D
  = 19.12ns arrival vs 13.65ns required
```

##### Placement 违例小结

| 违例路径 | Floorplan Slack | Placement Slack | 变化 | 说明 |
|----------|----------------|-----------------|------|------|
| conv_tile_mac 乘加 | (floorplan 未报此路径) | -27.96ns | — | 成为 placement 后最差内部路径 |
| out_stream_valid 输出 | (未报/不同 register) | -21.39ns | — | 长距离 pad 路径难优化 |
| 输入到 shadow_cache | -16.66ns | -5.47ns | **+11.19ns 改善** | place_opt 大幅优化了输入路径 |

#### 1.2.7 CTS-only-PSYN 阶段违例详情（3 条路径）

**背景**: cts_only_psyn 是在 CTS 之后、post-CTS hold time optimization 之后的时序报告。此时时钟已插入实际 buffer tree，时钟不确定性已从 0.5ns 降至 0.2ns，时钟网络延迟为 propagated。

##### PSYN 路径 #1：conv_tile_mac 乘加路径 (clk, **-27.51ns**)

- **起点**: `u_row_mult_5/weight_row_data_reg_reg[188]` (DFFRHQXL) — 注意与 CTS 阶段的 bit[191] 不同
- **终点**: `u_row_mult_5/out_row_sum_bus_reg[606]` (DFFRHQXL) — 注意与 CTS 阶段的 bit[530] 不同
- **数据到达时间**: 47.72ns
- **数据要求时间**: 20.20ns
- **违例量**: **-27.51ns**
- **关键瓶颈**:
  - 寄存器 Q 端延迟 **22.09ns** — 与 CTS 报告中的 21.73ns 相当
  - 30 级组合逻辑链，其中 `OAI21XL` (u142639/Y) 延迟 **3.85ns** — 该 gate 位于加法树的收尾阶段，连接了多个高位进位
  - `XOR3X2` 延迟 **1.40ns** — 3 输入 XOR 门
  - `INVX20` 级联 (0.83ns + 0.51ns)

**与 cts_only_cts 对比**: cts_only_cts 报告中同一模块（row_mult_5）的不同 bit([191]→[530]) slack = -31.80ns。PSYN 阶段的不同 bit([188]→[606]) slack = -27.51ns，说明 hold time optimization（插入 delay buffer）轻微改善了 setup slack，但改善有限（+4.29ns）。

##### PSYN 路径 #2：out_stream_valid 输出路径 (OUTPUTS, **-21.08ns**)

- **起点**: `u_sigmoid/stage0_valid_reg` (DFFRHQXL)
- **终点**: `out_stream_valid` (output port, PO8W pad)
- **数据到达时间**: 36.65ns
- **数据要求时间**: 15.57ns
- **违例量**: **-21.08ns**
- **与本系列各阶段对比**:

| 阶段 | 寄存器 Q 延迟 | Arrival | Slack |
|------|-------------|---------|-------|
| placement | 20.53ns | 30.19ns | -21.39ns |
| cts_only_cts | 20.58ns | 41.05ns | -25.78ns |
| **cts_only_psyn** | **20.63ns** | **36.65ns** | **-21.08ns** |
| route_initial1 | — | — | — (busy path MET) |
| route_power1 | — | — | — (busy path MET) |

**说明**: 该路径从 placement 到 CTS 各阶段始终违例 -21ns 左右，route 后该特定路径没有再出现在报告中（tool 可能改为报告 busy 输出路径 = MET）。寄存器的 20ns+ cell delay 始终是瓶颈。

##### PSYN 路径 #3：输入路径 (INPUTS, **-6.55ns**)

- **起点**: `img_wr_addr[3]` (input port)
- **终点**: `shadow_cache_pong_reg[0][2]` (DFFRXL)
- **数据到达时间**: 26.86ns
- **数据要求时间**: 20.31ns
- **违例量**: **-6.55ns**
- **关键瓶颈**:
  - PIW pad 延迟 **1.35ns**
  - `CLKBUFX20` 延迟 **1.94ns**
  - `AOI31X2` 延迟 **1.85ns**
  - `NOR3X4` 延迟 **2.25ns**
  - 时钟传播延迟 **10.61ns** — 此时钟到达时间已经较大

**与 placement 阶段对比**: placement 时输入违例为 -5.47ns (img_wr_addr[3]→shadow_cache_ping)，PSYN 后为 -6.55ns (img_wr_addr[3]→shadow_cache_pong)，恶化了约 1ns，主因是 CTS 引入的时钟传播延迟（10.61ns actual vs ideal 4.30ns）。

##### PSYN 违例小结

| 违例路径 | cts_only_cts Slack | cts_only_psyn Slack | 变化 | 说明 |
|----------|-------------------|---------------------|------|------|
| conv_tile_mac 乘加 | -31.80ns ([191]→[530]) | -27.51ns ([188]→[606]) | +4.29ns* | hold fix 侧效应 |
| out_stream_valid | -25.78ns | -21.08ns | **+4.70ns** | hold fix 改善了输出路径 |
| 输入到 shadow_cache | -8.77ns | -6.55ns | **+2.22ns** | 改善但依然违例 |

> *注: 不同 bit 位置，不可直接比较，但趋势表明 hold fix 对 setup 有轻微改善。

### 1.3 各阶段违例趋势总览

```
阶段              内部clk路径      OUTPUTS路径      INPUTS路径
───────────────────────────────────────────────────────────
data_setup           0.00 (MET)     0.05 (MET)      0.01 (MET)
floorplan          -49.99          -24.76           -16.66
placement          -27.96          -21.39            -5.47
cts_only_cts       -31.80          -25.78            -8.77
cts_only_psyn      -27.51          -21.08            -6.55
route_initial1      -3.73           MET              -2.32
route_power1        -3.40           MET              -2.01
```

**趋势分析**:
1. **floorplan 是最差阶段**: 此时 macro 固定但标准单元未放置，所有跨层次路径都有巨大的线延迟（单级 gate 可达 36ns）
2. **placement 大幅改善**: `place_opt` 将标准单元靠近放置，违例从 -50ns 降至 -28ns
3. **CTS 阶段违例回升**: 实际时钟树插入后，传播延迟（~10.6ns）取代 ideal 延迟（4.3ns），导致 setup slack 恶化约 3-4ns
4. **Route 阶段大幅好转**: 从 -28ns 降至 -3.7ns，说明 route_opt 的 SI 优化和 incremental optimization 有效改善了关键路径。但这是**以其他非关键路径变差为代价**，且最终的 route 报告只显示少量路径
5. **INPUTS/OUTPUTS 路径逐步改善**: 从 floorplan 的 -16~-25ns 逐步降至 route 的 -2ns 或 MET

### 1.4 时钟树分析

| 指标 | 值 |
|------|-----|
| CTS 后时钟路由覆盖率 | **90.47%** (不完整!) |
| 时钟传播延迟范围 | 8.82ns ~ 11.42ns (range = 2.60ns) |
| 目标 skew | 0.3ns |
| 实际 skew | 远大于目标值 |
| CTS uncertainty | 0.5ns (CTS前) → 0.2ns (PSYN前) |
| Route uncertainty | 0.2ns |

**问题**: 时钟网络路由仅完成 90.47%，存在未布线的时钟分支，导致部分寄存器无法获得正确的时钟信号。

---

## 2. 拥塞与 DRC 问题汇总

### 2.1 布线后的 DRC 面积错误

从 `post_route.txt` (LVS 检查输出):

| 层 | 错误数量 | 说明 |
|----|---------|------|
| Layer 0 | 0 | OK |
| Layer 1 | 0 | OK |
| Layer 2 | 0 | OK |
| **Layer 3** | **1** | 面积错误, 0.0784 um² |
| Layer 4 | 0 | OK |
| **Layer 5** | **>20** | 大面积错误，从 (0,212) 到 (68,442) 区域，最大单个区域 4752 um² |
| Layer 6-15 | 0 | OK |

**Layer 5 错误特征**:
- 边缘区域 `(0.000, 444.210) → (66.000, 372.210)` 出现 -4752 um² 的错误
- 多个连续的矩形条带，每个约 15.7 um²，呈现规则的 stair-step 形态
- 集中在芯片左下角边缘区域
- 同一区域还有边界错误: `(0.000, 284.000) → (66.000, 212.000)`，-4752 um²

**可能原因**:
- Pad ring 与内部电源网络在 Metal5 层的重叠或间距不足
- 电源/地平面在角落区域的设计规则违规

### 2.2 布线过程中的 ZRT 错误

```
Error: The 'VIA12A' value specified for the '-from_via' option is invalid. (ZRT-476)
```
- 出现 **2 次**（第 1 行和第 9017 行）
- VIA12A 通孔在技术文件中缺失或名称不正确
- 影响 METAL1 到 METAL2 的互联

### 2.3 高扇出网络

| 网络名称 | 问题 | 阈值 |
|----------|------|------|
| `net_rst_n` | 超过 1000 pins，RC 提取被跳过 | >1000 |
| `inst_cnn/pwconv_inst/n282` | 超过 1000 pins，RC 提取被跳过 | >1000 |
| `inst_cnn/conv_inst/n619` | 超过 1000 pins，RC 提取被跳过 | >1000 |

**影响**: 高扇出网络（尤其是 reset）在 RC 提取时被跳过，导致其时序分析不准确。同时这些网络需要大量 buffer 树来驱动。

### 2.4 未完全连接的网络

```
Warning: Net 'inst_cnn/conv_inst/n270' is not fully connected and will be estimated. (RCEX-060)
Warning: Net 'inst_cnn/conv_inst/n2208' is not fully connected and will be estimated. (RCEX-060)
```

### 2.5 进程资源问题

```
Error: Could not fork child process. (PROC-2)
Error: Failed in separate process. (ZRT-407)
```
- 出现 **2 次**
- 布线过程中内存或进程数耗尽导致无法创建子进程
- 运行时内存使用量: ~6.1GB (extraction task 6158MB, main task 6403MB)

---

## 3. LVS / 连接性问题汇总

### 3.1 Output PortInst 未连接（open 输出）

以下标准单元的 Y/Q 输出端未连接任何网络（>20 个错误，仅列出前 20）：

| 实例路径 | 端口 |
|----------|------|
| `inst_cnn/pwconv_inst/u27` | Y (output) |
| `inst_cnn/dwconv_inst/u_dwconv_core/u154` | Y (output) |
| `inst_cnn/conv_inst/u_conv_core/u14389` | Y (output) |
| `inst_cnn/conv_inst/u12` | Y (output) |
| `inst_cnn/pwconv_inst/u_pwconv_input_buffer/u21840` | Y (output) |
| `inst_cnn/dwconv_inst/u73` | Y (output) |
| `inst_cnn/conv_inst/u_conv_core/u_conv_rescale_relu/u15` | Y (output) |
| `inst_cnn/pwconv_inst/u_pwconv_core/u3334` | Y (output) |
| `...conv_tile_mac_row_add/partial_5_reg[26][19]` | Q (output) |
| `...conv_tile_mac_row_add/partial_5_reg[27][19]` | Q (output) |
| `...conv_tile_mac_row_add/partial_5_reg[28][19]` | Q (output) |
| `...u_row_mult_5/out_row_sum_bus_reg[417]` | Q (output) |
| `...conv_tile_mac_row_add/partial_5_reg[31][19]` | Q (output) |
| `...conv_tile_mac_row_add/partial_5_reg[18][19]` | Q (output) |
| `...u_row_mult_0/out_row_sum_bus_reg[417]` | Q (output) |
| `...u_row_mult_6/out_row_sum_bus_reg[417]` | Q (output) |
| `...u_row_mult_8/out_row_sum_bus_reg[417]` | Q (output) |
| `...conv_tile_mac_row_add/partial_5_reg[24][19]` | Q (output) |
| `...u_row_mult_0/out_row_sum_bus_reg[398]` | Q (output) |
| `...u_row_mult_5/out_row_sum_bus_reg[398]` | Q (output) |

**分析**: `out_row_sum_bus_reg[417]` 和 `[398]` 在多个 row_mult 实例中都是 open 的，这些位可能是 INT19 部分和总线的最高几位，在后续 row_add 合并时未使用或被综合工具优化掉。另外 `partial_5_reg[*][19]` 多个行也出现 open Q 端，说明 row_add 的第 19 位 partial sum 没有被用到。

### 3.2 逻辑网络 open（weight_sram_rdata）

FC 权重 SRAM 的读取数据总线有 **19 个 bit** 是 open 的：

| 断开的 bit | 对应的 SRAM 数据线 |
|-----------|-------------------|
| weight_sram_rdata[2] | Q[2] |
| weight_sram_rdata[5] | Q[5] |
| weight_sram_rdata[10] | Q[10] |
| weight_sram_rdata[13] | Q[13] |
| weight_sram_rdata[16] | Q[16] |
| weight_sram_rdata[18] | Q[18] |
| weight_sram_rdata[19] | Q[19] |
| weight_sram_rdata[24] | Q[24] |
| weight_sram_rdata[26] | Q[26] |
| weight_sram_rdata[28] | Q[28] |
| weight_sram_rdata[29] | Q[29] |
| weight_sram_rdata[34] | Q[34] |
| weight_sram_rdata[37] | Q[37] |
| weight_sram_rdata[49] | Q[49] |
| weight_sram_rdata[50] | Q[50] |
| weight_sram_rdata[53] | Q[53] |
| weight_sram_rdata[58] | Q[58] |
| weight_sram_rdata[61] | Q[61] |
| weight_sram_rdata[62] | Q[62] |
| weight_sram_rdata[63] | Q[63] |

**分析**: 这些 open bit 分布在整个 64bit bus 中，不是连续的高位或低位，说明这可能是 SRAM 内容初始化问题（`$readmemh` 加载时某些地址未定义），或者 SRAM 实例的某些数据位端口在综合时被优化掉了。由于 fc.v v1.3 版本中 `bias_wr_en=1'b0`，SRAM 写接口已被删除，这些 open 的数据线可能是综合工具认为不需要的位。

### 3.3 未连接输入引脚

```
Warning: The non-constant Milkyway net 'IDS_UNCONNECTED' has a hierarchical load pin
         'inst_cnn/dwconv_inst/.../row_window_data[199]' but no driver.
         It will now be driven by logic zero. (MWDC-229)
```
- 4 个类似的 warning，都涉及 `IDS_UNCONNECTED` 网络
- 这些网络有负载但没有驱动源，被工具强制接地
- 集中在 dwconv 和 pwconv 模块

---

## 4. 根因分析

### 4.1 主要根因：RTL 组合逻辑深度过大

| 模块 | 组合逻辑描述 | 估计逻辑级数 | 最差违例 | 对时钟周期的影响 |
|------|-------------|-------------|----------|-----------------|
| `conv_tile_mac_row_mult` | 7×INT8 乘法 + 3 级加法树 + 位扩展 | ~30 级 | -31.80ns (CTS) | **致命**: 单周期内完成 7MAC |
| `conv→dwconv 跨层次控制` | out_pos 地址译码 + SRAM CEN 使能 | ~10 级 | **-49.99ns (floorplan)** | **致命**: 跨层次长走线 |
| `fc_mac` | 8×INT8 乘法 + 2 级加法树 | ~25 级 | -3.73ns (Route) | **严重**: 经 SRAM 读取延迟后更差 |
| `conv_shared_input_buffer` | 地址解码 + 多路选择器 | ~10 级 | -16.66ns (floorplan) | **严重**: 输入 pad 路径叠加 |
| `post_process/out_stream_valid` | 单寄存器到 pad 的长距离 buffer 链 | ~6 级 buffer | -25.78ns (CTS) | **严重**: 物理距离过长 |

**核心问题 #1**: `conv_tile_mac_row_mult.v` (v4.4) 的设计中，7 个乘法的结果全部由组合逻辑完成加法归约，仅在最后一级用寄存器(`out_row_sum_bus_reg`)打拍输出。这导致寄存器到寄存器之间的组合逻辑深度超过 30 级，在 SMIC 0.18um 工艺下根本无法在 10ns 时钟周期内完成。

**核心问题 #2**: Floorplan 阶段暴露出 `conv_core/out_pos_reg[0]` → `dwconv_param_store/weight_bank/CEN` 路径的跨层次 SRAM 控制使能路径，在 ideal 时钟下就有 **-49.99ns** 的违例。路径中 `dwconv_inst/u69/Y` (INVX1) 单级 gate 延迟高达 **36.35ns**，说明该 inverter 的物理位置距离 SRAM CEN 端口极远。这暴露了 SRAM macro 布局规划的根本性问题。

**RTL 文件位置**:
- `SonicBolt/src/conv/conv_tile_mac_row_mult.v` (核心违例)
- `SonicBolt/src/post_process/fc_mac.v` (FC 违例)

### 4.2 时钟树质量问题

- 90.47% 的时钟网未完全路由
- 传播延迟范围 2.6ns（远超 0.3ns 的目标 skew）
- 部分寄存器可能收不到正确的时钟信号
- 复位网络 (net_rst_n) 超过 1000 pins，高扇出导致 RC 提取被跳过
- **Ideal 时钟到 Propagated 时钟的退化**:
  - floorplan/placement 阶段: ideal clock delay = 4.30ns
  - CTS 后: propagated delay = 8.82~11.42ns（平均增加 ~6ns）
  - 这是造成 CTS 阶段违例比 placement 阶段更差的主要原因

### 4.3 物理设计规划问题

- **Core utilization 0.48**：虽然看起来保守，但芯片面积达 16.87mm × 8.57mm（约 145 mm²），长距离互联引入了大量线延迟
- **Pad ring 布局**：输入数据需要从芯片边缘的 pad 穿过整个 die 到达内部的 shadow cache，floorplan 阶段 PIW pad 单级延迟 9.05ns
- **SRAM macro 布局**：SRAM（frame_store, weight_bank 等）与计算逻辑之间的物理距离可能不合理。floorplan 阶段暴露出跨 conv→dwconv 层次的控制路径（单 gate 36ns 延迟），说明 dwconv weight_bank SRAM 与 conv 计算逻辑布局分散
- **跨层次路径长走线**: 设计中 conv、dwconv、pwconv 三个子系统级联，控制/数据信号需要穿越多个层次边界

### 4.4 约束文件问题

- **时钟周期 10ns (100MHz)**：对于 SMIC 0.18um 工艺下的深度组合逻辑不现实
- **set_max_transition 100ns**：过于宽松，掩盖了真实的 transition 违规
- **时钟源延迟 4.0ns + 网络延迟 0.3ns**：源延迟偏大（应约为 clock tree 实际延迟），网络延迟偏小
- **Floorplan/Placement 阶段使用 ideal clock**：使用 ideal 4.30ns 延迟，而实际 CTS 后的延迟约 10.6ns，导致 placement 阶段对时序过于乐观

### 4.5 设计完整性问题

- `out_row_sum_bus[417]` / `[398]` 在多个实例中 open：表明这些高 bit 在实际使用中被丢弃，可能是 RTL 设计时位宽计算不精确
- `weight_sram_rdata` 有 19 个 open bit：可能是 SRAM 预加载内容在综合后被优化
- 部分 `partial_5_reg[*][19]` open：row_add 的部分和位宽可能过大
- `IDS_UNCONNECTED` 网络：dwconv/pwconv 中有数据总线位无驱动源，被工具强制接地

---

## 5. 修复方案

### 5.1 方案 A：RTL 修改（推荐，优先级最高）

#### A1. 流水线化 conv_tile_mac_row_mult（解决 -31.80ns 违例）

**文件**: `SonicBolt/src/conv/conv_tile_mac_row_mult.v`

当前架构（1 级流水线）:
```
weight/data reg → 7×MULT (comb) → 3级加法树 (comb) → out_row_sum_bus_reg
```

建议架构（3 级流水线）:
```
stage1: weight/data reg → 7×MULT (comb) → product_*_reg (打拍)
stage2: product_*_reg → L1 加法 (3路) → sum_l1_*_reg (打拍)
stage3: sum_l1_*_reg → L2+L3 加法 → out_row_sum_bus_reg (打拍)
```

**修改方法**:
1. 在 7 个 `mult_cell` 输出后增加 `product_*_reg` 寄存器（第 1 级）
2. 在 `sum_l1` 计算后增加 `sum_l1_*_reg` 寄存器（第 2 级）
3. 保持现有的 `out_row_sum_bus_reg` 作为第 3 级
4. 同步调整外围 `conv_tile_mac_reduce11_stage1_cell` 的数据对齐时序

**预期效果**: 单级组合逻辑深度从 ~30 级降至 ~10 级，应可满足 10ns 时序

#### A2. 流水线化 fc_mac（解决 -3.73ns 违例）

**文件**: `SonicBolt/src/post_process/fc_mac.v`

当前架构（1 级流水线）:
```
SRAM Q → data split → 8×MULT (comb) → 2级加法树 (comb) → output reg
```

建议架构（2-3 级流水线）:
```
stage1: SRAM Q + in_data → data/weight split → product reg (打拍)
stage2: product → L1/L2 加法 → output reg (打拍)
```

#### A3. 修复未连接的输出端口

**文件**: `SonicBolt/src/conv/conv_tile_mac_row_mult.v`, `conv_tile_mac_row_add.v`

- 确认 `out_row_sum_bus[417]` 和 `[398]` 是否真正需要。如不需要，在 RTL 中显式赋值 `1'b0` 或缩减位宽
- 同理确认 `partial_5_reg[*][19]` 的使用情况
- 对于 `weight_sram_rdata` 的 open bit，检查 `fc_weight_sram.v` 中是否正确初始化了所有 SRAM 内容

#### A4. 修复 IDS_UNCONNECTED 网络

**文件**: `SonicBolt/src/dwconv/dwconv_*.v`, `pwconv/pwconv_*.v`

- 检查 `dwconv_tile_mac/row_window_data[199]` 等未驱动信号，确认是设计意图还是连接遗漏

#### A5. 处理高扇出复位网络

**文件**: `SonicBolt/src/cnn_chip.v`

- 将 `rst_n` 改为使用同步复位释放 (`reset_synchronizer`)
- 或在顶层添加复位 buffer 树，将大扇出复位拆分为多个子复位域

### 5.2 方案 B：SDC 约束修改

#### B1. 放宽时钟周期（快速缓解）

```tcl
# 将时钟周期从 10ns 放宽到 15ns (66MHz) 或 20ns (50MHz)
create_clock -name {clk} -period 15.0 -waveform {0.000 7.500} [get_ports {clk}]
```

**影响**: 这是最快的缓解方案，但会降低 CNN 加速器的推理吞吐量。

#### B2. 设置多周期路径

```tcl
# 对于 conv 乘加路径，设置 multi-cycle
set_multicycle_path -setup 2 -from [get_cells *u_row_mult*/weight_row_data_reg_reg*] \
    -to [get_cells *u_row_mult*/out_row_sum_bus_reg*]
set_multicycle_path -hold 1 -from [get_cells *u_row_mult*/weight_row_data_reg_reg*] \
    -to [get_cells *u_row_mult*/out_row_sum_bus_reg*]
```

#### B3. 修复 Transition 约束

```tcl
# 当前设置为 100ns，过于宽松
# 修改为基于工艺库推荐值
set_max_transition 3.0 [current_design]
```

#### B4. 修复时钟不确定性设置

```tcl
# 当前: set_clock_uncertainty 0.5 → 0.2 (跳变过大)
# 建议: 使用更合理的分阶段设置
# CTS 前: 0.5 (含 jitter + skew + margin)
# CTS 后: 0.3
# Route 后: 0.2
```

### 5.3 方案 C：物理设计脚本修改

#### C1. 调整 Floorplan 参数

```tcl
# run_design_planning.tcl
# 当前 core_utilization = 0.48
# 考虑适当增大芯片面积，或增大 io2core 距离
create_floorplan -core_utilization 0.55 \
    -left_io2core 50.0 -bottom_io2core 50.0 \
    -right_io2core 50.0 -top_io2core 50.0
```

#### C2. 修复 VIA12A 通孔定义问题

检查技术文件或 Milkyway 库中的 via 定义:

```tcl
# 检查可用的 via 定义
report_via_rules
# 确认 VIA12A 是否存在，或需改用 VIA12
```

需要在 `common_route_si_settings_zrt_icc.tcl` 中显式设置 via 选项:
```tcl
set_route_zrt_detail_options -via "VIA12"
# 或者从 Milkyway 库中确认正确的 via 名称
```

#### C3. 改进 Macro 布局（解决 floorplan -49.99ns 违例）

**问题**: floorplan 阶段 `out_pos_reg[0]` → `dwconv weight_bank/CEN` 路径单级 INV 延迟 36ns，说明 dwconv SRAM 距离 conv 控制逻辑极远。

当前 `run_design_planning.tcl` 中的 SRAM macro 布局已被注释掉。**强烈建议根据数据流方向手动规划 macro 位置**:

```tcl
# ##############################################
# 按数据流方向重新布局 SRAM macro:
# conv → dwconv → pwconv → post_process
# ##############################################

# 左列: conv 相关 SRAM (靠近 conv_tile_mac)
move_objects -to {250 250}  [get_cells {inst_cnn/conv_inst/u_frame_store_ping}]
move_objects -to {600 250}  [get_cells {inst_cnn/conv_inst/u_frame_store_pong}]

# 中列: dwconv/pwconv 相关 SRAM (减少跨层次走线)
move_objects -to {600 430}  [get_cells {inst_cnn/dwconv_inst/u_dwconv_param_store/*}]
move_objects -to {950 430}  [get_cells {inst_cnn/pwconv_inst/u_pwconv_param_store/*}]

# 右列: post_process 相关 SRAM (靠近 fc/sigmoid)
move_objects -to {950 610}  [get_cells {inst_cnn/post_process_inst/u_fc_weight_sram/*}]
move_objects -to {1300 610} [get_cells {inst_cnn/post_process_inst/u_sigmoid/*}]
```

**关键原则**: 将同一数据流阶段的 SRAM 和计算逻辑放在 `place_opt` 能有效优化的距离范围内，避免跨层次超长走线。

#### C4. 启用拥塞驱动的布局优化

```tcl
# common_placement_settings.tcl 中添加:
set_app_var placer_enable_enhanced_router true
set_congestion_options -max_util 0.80 -coordinate {x1 y1 x2 y2}
```

#### C5. 增加时钟树综合 effort

```tcl
# run_cts.tcl
set_clock_tree_options -max_fanout 32 -max_transition 1.5 -max_capacitance 0.5
clock_opt -only_cts -no_clock_route -update_clock_latency -effort high
```

#### C6. 优化布线选项

```tcl
# run_route.tcl
set_route_zrt_common_options -post_detail_route_redundant_via_insertion high
set_route_zrt_detail_options -optimize_wire_via_effort_level high
# 启用 SI 分析
set_si_options -delta_delay true -static_noise true \
    -timing_window true -analysis_effort high
```

### 5.4 方案 D：综合策略调整

#### D1. 使用更具侵略性的综合优化

在综合脚本 (`syn/scripts/`) 中:

```tcl
# 启用 retiming / pipelining
set_optimize_registers true
# 使用 compile_ultra 替代 compile
compile_ultra -retime -timing_high_effort_script
# 设置更紧的约束让 DC 进行更积极的优化
set_max_delay -from [all_registers] -to [all_registers] 8.0
```

#### D2. 检查未使用的输出

在综合后网表中检查出 `out_row_sum_bus[417]`、`partial_5_reg[*][19]` 等 open 端口是否在综合网表中就已被优化:

```tcl
# DC 中
report_disable_timing
check_design
```

### 5.5 推荐修复优先级

| 优先级 | 方案 | 预期效果 | 工作量 |
|--------|------|---------|--------|
| **P0 紧急** | C3: 手动重新布局 SRAM macro | 解决 floorplan -49.99ns 跨层次违例 | 小 |
| **P0 紧急** | A1: 流水线化 conv_tile_mac_row_mult | 解决所有阶段的乘加路径违例 (-31.80ns) | 中 |
| **P0 紧急** | C2: 修复 VIA12A 通孔 | 解决布线阻塞 | 小 |
| **P1 高** | A2: 流水线化 fc_mac | 解决 route 阶段 -3.73ns 违例 | 小 |
| **P1 高** | B1: 放宽时钟周期到 12-15ns | 缓解所有违例 | 极小 |
| **P1 高** | A3: 修复 open 输出端口 | 解决 LVS 错误 | 中 |
| **P1 高** | C1: 调整 floorplan (增大面积 / io2core) | 改善输入/输出路径 | 小 |
| **P2 中** | A5: 处理高扇出复位 | 改善 RC 提取精度 | 中 |
| **P2 中** | B2: 多周期路径设置 | 保留 10ns 周期作为备选 | 小 |
| **P2 中** | C4: 拥塞驱动布局 | 改善布线质量 | 小 |
| **P3 低** | D1: 综合策略调整 | 整体优化 | 中 |
| **P3 低** | A4: 修复 IDS_UNCONNECTED | 清理 warning | 小 |

---

## 附录: 相关文件清单

| 类别 | 路径 |
|------|------|
| RTL 源码 (关键) | `SonicBolt/src/conv/conv_tile_mac_row_mult.v` |
| RTL 源码 (关键) | `SonicBolt/src/post_process/fc_mac.v` |
| RTL 源码 (关键) | `SonicBolt/src/post_process/fc.v` |
| RTL 源码 | `SonicBolt/src/conv/conv_tile_mac_row_add.v` |
| RTL 源码 | `SonicBolt/src/dwconv/dwconv_tile_mac_row_mult.v` |
| 物理设计入口 | `SonicBolt/icc/scripts/icc.tcl` |
| 数据加载 | `SonicBolt/icc/scripts/run_data_setup.tcl` |
| 布图规划 | `SonicBolt/icc/scripts/run_design_planning.tcl` |
| 布局 | `SonicBolt/icc/scripts/run_placement.tcl` |
| 时钟树 | `SonicBolt/icc/scripts/run_cts.tcl` |
| 布线 | `SonicBolt/icc/scripts/run_route.tcl` |
| 约束文件 | `SonicBolt/icc/design/cnn_chip_clk_with_driving.sdc` |
| CTS 时序报告 | `SonicBolt/icc/reports/cts_only_cts.timing` |
| 布线时序报告 | `SonicBolt/icc/reports/route_initial1.timing` |
| 布线时序报告 | `SonicBolt/icc/reports/route_power1.timing` |
| 后布线 LVS 日志 | `SonicBolt/icc/work/post_route.txt` |
| 综合脚本 | `SonicBolt/syn/scripts/` |
