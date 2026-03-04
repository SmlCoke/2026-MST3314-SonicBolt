# 2026-MSST3314-SonicBolt

> 数字集成电路设计课程设计 · 高性能 CNN 加速器全流程设计
> 工艺：0.18 μm · 目标：Speed ≥ 1000K frames/s · 评价指标：FoM = Speed / Area

---

## I. 项目简介

本项目为 SJTU MAST3314《数字集成电路设计课程设计》课程的完整设计仓库，目标是完成一款面向**语音关键词识别**的 CNN 加速器芯片全流程设计，覆盖架构设计、RTL 编码、逻辑仿真、逻辑综合、时序分析与物理设计。

**网络结构（MobileNet v2 简化版）**：

```
Input(1,30,10) → Conv(32,1,11,7) → ReLU
               → DWConv(32,1,3,3) → ReLU
               → PWConv(32,32,1,1) → ReLU
               → Maxpool(2×2, s=2)
               → Flatten(288)
               → FC(2,288)
               → Sigmoid → 二分类输出
```

所有卷积层采用 INT8 量化，中间累加使用 INT32，通过定点化乘移位（`M0 × 2^{-n}`）重量化回 INT8。

---

## II. 仓库结构

```
CNN-Accelerator/
│
├── Materials/                  # 课程资料
│   ├── introduction.md         # 课程简介与评分标准
│   ├── Design_Specifications.md# 电路设计规范（网络结构、层参数、重量化公式）
│   ├── PyCode-Specifications.md# Python 行为模型编写规范
│   └── Skill-Plan.md           # 技能树与推进计划（参考）
│
├── MiniCNN/                    # 参考资料：上一届课程的示例项目
│   └── sim/samples/            # ★ 模型参数与测试数据（GitHub 上仅保留此目录）
│       ├── Param/              # 网络权重与偏置
│       ├── Scale/              # 量化/重量化参数
│       ├── In/                 # 496 个输入 MFCC 特征图（INT8）
│       ├── Test/               # 单样本各层金标准输出
│       └── sigmoid_lookup_table.txt  # Sigmoid LUT（256 条目，FP32）
│
├── Notes/                      # 学习笔记
│   ├── demo                    # 示例 verilog 模块，与 slices/下的相关笔记一同阅读
│   ├── guide/                  # AI 给出的学习/涉及指导
│   └── slices/                 # 学习到的零散知识点 
│
├── PyRTL-CNN/                  # ★ Python 行为级仿真模型（本团队编写）
│   ├── load_params.py          # 参数加载模块
│   ├── rtl_primitives.py       # 底层硬件原语（SRAM / LineBuffer / MAC / Requant）
│   ├── layers.py               # 各网络层类
│   ├── top_module.py           # 顶层推理模块
│   ├── run_inference.py        # 推理入口脚本
│   ├── test_golden.py          # 金标准对比验证
│   └── README.md               # 详细说明与学习指南
│
└── SonicBolt/                  # ★ RTL 实现（Verilog，待补充）
    └── pre-test/               # 预览测试模块，与真实 RTL 实现基本无关，用于测试
```

---

## III. 各模块说明

### 3.1 `Materials/` — 课程资料

课程给定的设计规范文档，包含：
- 完整网络结构定义及各层参数（输入/输出尺寸、位宽、stride/padding）
- 重量化公式与各层 `(M0, n)` 参数
- 两种应用场景的指标要求（本团队选择**高性能场景**，Speed ≥ 1000K）

阅读起点：[Design_Specifications.md](Materials/Design_Specifications.md)

---

### 3.2 `MiniCNN/sim/samples/` — 模型参数与测试数据

助教统一提供的网络参数和测试数据，是整个项目的数据基础：

| 目录/文件 | 内容 |
|---|---|
| `Param/` | 各层权重（INT8）和偏置（INT16）的 txt 文件 |
| `Scale/Rescale.txt` | 各层重量化参数：浮点 M 值及定点化 `(M0, n)` |
| `Scale/Scale.txt` | 量化 Scale 参数，含 `Linear_Out_Scale`（Sigmoid 反量化用）|
| `In/0.txt` ~ `In/495.txt` | 496 个 INT8 MFCC 输入样本，每个 30×10 |
| `Test/` | 单样本各层输出的金标准，用于逐层调试 |
| `sigmoid_lookup_table.txt` | 256 条目 Sigmoid LUT，IEEE 754 FP32 十六进制格式 |

> **注**：上一届参考项目的 Verilog 源码在发布前已从仓库中移除，仅保留上述参数文件。参数文件由课程助教提供，不涉及知识产权。

---

### 3.3 `PyRTL-CNN/` — Python 行为级仿真模型

在正式编写 Verilog 之前，用纯 Python 实现的完整 CNN 行为模型，作用：

1. **理解架构**：通过可执行代码直观学习片上 SRAM、行缓冲、MAC 阵列、重量化单元等硬件模块的工作原理
2. **RTL 映射参考**：每个 Python 类对应一个 Verilog 模块，数据流、位宽约束和地址计算与后续 RTL 设计保持一致
3. **Testbench 金标准**：提供逐层 INT8 参考输出，可直接用于验证 Verilog 仿真结果的数值正确性

**验证状态**：已通过全部层金标准对比（INT8 层逐元素完全匹配，Sigmoid FP32 误差 < 1e-6）。

快速验证：
```bash
cd PyRTL-CNN
python test_golden.py    # 逐层金标准对比
python run_inference.py  # 单样本推理，打印每层 I/O 尺寸
```

详见 [PyRTL-CNN/README.md](PyRTL-CNN/README.md)。

---

### 3.4 `SonicBolt/` — Verilog RTL 实现（待补充）

本团队针对**高性能场景**设计的 Verilog 实现，目标：

- 每秒处理 ≥ 1000K 帧 `(1,30,10)` 输入
- 评价指标：FoM = Speed / Area（面效）
- 设计方向：提升 MAC 并行度 + 流水线深度

---

## IV. 设计进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| 架构研究 | 阅读规范、参考 MiniCNN、建立 Python 行为模型 | ✅ 完成 |
| RTL 设计 | Verilog 模块编写（SonicBolt） | 🔲 进行中 |
| 逻辑仿真 | Testbench 编写与功能验证 | 🔲 待开始 |
| 逻辑综合 | Design Compiler，时序/面积/功耗分析 | 🔲 待开始 |
| 时序分析 | PrimeTime 时序签核 | 🔲 待开始 |
| 物理设计 | ICC/Encounter 布局布线，后仿真 | 🔲 待开始 |
