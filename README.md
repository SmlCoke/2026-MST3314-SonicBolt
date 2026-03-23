<div align="center">

# ⚡️SonicBolt(声速闪电)
**数字集成电路设计 · 高性能 CNN 加速器全流程设计**

[![Version](https://img.shields.io/badge/Version-v2.0-blue.svg)]() [![Institution](https://img.shields.io/badge/Institution-SJTU-red.svg)](https://www.sjtu.edu.cn/) [![SmlCoke](https://img.shields.io/badge/SmlCoke-https://smlcoke.com-brightgreen.svg)](https://smlcoke.com) [![License](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)

[项目简介](#i-项目简介) • [仓库结构](#ii-仓库结构) • [各模块说明](#iii-各模块说明) • [设计进度](#iv-设计进度)

</div>

---


## I. 项目简介

SonicBolt(声速闪电)项目为 SJTU MAST3314《数字集成电路设计课程设计》课程的完整设计仓库，目标是完成一款面向**语音关键词识别**的 CNN 加速器芯片全流程设计，采用工艺：0.18 μm ，预估实现目标：Speed ≥ 1000K frames/s ，评价指标：FoM = Speed / Area。覆盖架构设计、RTL 编码、逻辑仿真、逻辑综合、时序分析与物理设计。

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
├── Demo/
│   ├── demo1-codex             # 第一版 Conv 层实现，由 Codex 5.3 生成，供参考学习
│   ├── demo2-claude            # 第二版 Conv 层实现，由 Claude Opus 4.6 生成，供参考学习 
│   ├── demo2-claude-opus       # 第三版 Conv 层实现，由 Claude Opus 4.6 生成，修复了第二版的 Bug 
│   └── pre-test/               # 预览测试模块，与真实 RTL 实现基本无关，用于测试
│
├── Materials/                  # 课程资料
│   ├── introduction.md         # 课程简介与评分标准
│   ├── Design_Specifications.md# 电路设计规范（网络结构、层参数、重量化公式）
│   ├── PyCode-Specifications.md# Python 行为模型编写规范
│   └── Skill-Plan.md           # 技能树与推进计划（参考）
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
├── Scripts/                    # 辅助脚本（如参数转换、仿真自动化等）
│   └── search_files_by_name    # 根据文件名片段搜索文件
│
└── SonicBolt/                  # ★ RTL 实现（本团队编写）
    ├── data/                   # 测试数据和网络参数，供仿真使用
    ├── docs/                   # 设计文档、模块说明、架构示意图等 
    └── src/
        ├── conv/               # Conv 层 RTL 实现
```


## III. 各模块说明

### 3.1 `Materials/` — 课程资料

课程给定的设计规范文档，包含：
- 完整网络结构定义及各层参数（输入/输出尺寸、位宽、stride/padding）
- 重量化公式与各层 `(M0, n)` 参数
- 两种应用场景的指标要求（本团队选择**高性能场景**，Speed ≥ 1000K）

阅读起点：[Design_Specifications.md](Materials/Design_Specifications.md)

---

### 3.2 `PyRTL-CNN/` — Python 行为级仿真模型

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

### 3.3 `Scripts/` — 辅助工具脚本

包含一些实用的脚本，如：
- `search_files_by_name.py`：根据文件名片段搜索项目中的相关文件，方便快速定位资料、参数或代码片段。使用方法：
  ```bash
  python search_files_by_name.py <root_directory> <filename_keyword>
  ```

---

### 3.4 `Demo/` — AI 生成的示例实现

包含 Codex 5.3 和 Claude Opus 4.6 生成的多个版本的 Conv 实现，供学习和参考。

**注意**：这些实现可能存在功能性错误或性能问题，不建议直接使用于正式设计，但可以作为理解 Conv 层设计思路的参考。

> 此外，在 SonicBolt 的 Conv 实现后，`Demo/` 版本中的所有 Conv 模块由于位宽过大或者关键路径过长等各种原因，已经被正式舍弃，没有被应用到 SonicBolt 架构中。


---

### 3.5 `SonicBolt/` — Verilog RTL 实现（待完善）

本团队针对**高性能场景**设计的 Verilog 实现，目标：

- 每秒处理 ≥ 1000K 帧 `(1,30,10)` 输入
- 评价指标：FoM = Speed / Area（面效）
- 设计方向：提升 MAC 并行度 + 流水线深度

架构示意图可以参照 [figures.pptx](./SonicBolt/docs/figures.pptx) ，其中涵盖了各个版本的电路架构示意图以及时序分析图，供设计参考。

---

## IV. 设计进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| 架构研究 | 阅读规范、建立 Python 行为模型 | ✅ 完成 |
| RTL 设计 | Verilog 模块编写（SonicBolt） | 🔲 进行中 |
| 逻辑仿真 | Testbench 编写与功能验证 | 🔲 进行中 |
| 逻辑综合 | Design Compiler，时序/面积/功耗分析 | 🔲 待开始 |
| 时序分析 | PrimeTime 时序签核 | 🔲 待开始 |
| 物理设计 | ICC/Encounter 布局布线，后仿真 | 🔲 待开始 |
