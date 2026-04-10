# Q1：IDCT 示例工程目录及脚本分析

在你的作业资料中，`IDCT` 作为一个典型的逻辑综合参考设计，包含了完整的“前端代码 -> 逻辑综合 -> 网表输出”的工程目录结构。以下是详细分析。

## 1. 目录结构梳理

进入 `IDCT/IDCT/Syn/`（或相似结构的目录），你会看到以下子目录配置，这是典型的硅谷及芯片公司的综合工程结构：

*   **`rtl/`** (Register Transfer Level): 存放所有设计源代码（Verilog/VHDL等）。在本项目中存放的是 `idct_chip.v` 及各个子模块。
*   **`work/`** (工作目录): 运行综合工具时所在的初始目录，通常工具运行时产生的临时日志、中间垃圾文件会留在这里。包含启动工具环境的 `setup.sh`。
*   **`scripts/`** (脚本目录): 存放自动化综合控制文件。如 `zs.tcl`（综合主控脚本）和 `idct.sdc`（时序设计约束脚本）。
*   **`outputs/`** (输出目录): 综合成功后，最终导出的可以交由后段（物理设计）的产物。最核心的是工艺映射后的门级网表（`.v`）和映射约束配置（`.sdc`）。
*   **`reports/`** (报告目录): 综合完毕后输出的数据统计报告。用来供设计师查看此时序、面积（PPA）或存在的时序违例（Violations）是否满足指标。

## 2. 核心脚本解析

### 2.1 zs.tcl：一键综合控制脚本
这是一个 TCL (Tool Command Language) 脚本，是与国产 EDA 华大九天 ZenSyn 或 Synopsys DC 交互的控制台命令集。通常我们说“一键运行综合”，就是通过在工具里 `source` 这个文件来实现的。

**逐行解读 `zs.tcl`**：

```tcl
# 1. 导入库环境 (Library Setup)
set search_path "$search_path ../rtl/idct ../scripts ../../../SMIC18/lib ../../../SMIC18/mem ../work"
# ↑ 设置寻找代码、库文件、脚本等所需文件的默认搜索路径。
set target_lib   "slow.lib S018V3EBCDSP_X16Y4D16_PR.lib SP018W_V1p8_max.lib"
# ↑ 设置目标工艺库，也就是要把你的RTL代码映射成哪些厂家提供的实际门电路（如中芯国际180nm STD Cell库和SRAM库）。ZenSyn工具直接读取.lib文本文件。
set link_priority     "* slow S018V3EBCDSP_X16Y4D16_PR_tt_1.8_25 SP018W_V1p8_max"
# ↑ 设置链接优先级，当多个库存在同名单元时，优先从哪个库抓取物理版图库的连接关系。

# 2. 读取设计代码 (Read Design Files)
read_design -format verilog ../rtl/idct/even_odd.v
read_design -format verilog ../rtl/idct/mem4x4.v
... 
read_design -format verilog ../rtl/idct/idct_chip.v
# ↑ 读入你的 Verilog 源码。将语法结构翻译成工具内部的通用布尔逻辑或寄存器结构。

# 3. 指定顶层模块 (Set Top Module)
set current_design idct_chip
# ↑ 告知分析工具哪个模块是你芯片的最外层封装（Top Module），之后的所有时序、面积分析都将从它的引脚开始。在你的项目里，这里应该换成 `cnn`。

link_design
# ↑ 将你代码中实例化的各种子模块、以及引用的工艺底层门库链接起来，拼接成一个完整的系统网表。
make_unique
# ↑ 若多次例化了相同的子模块（如多个相同的加法器），这个命令会将它们打上独立的标记（如 add_1, add_2）。这在物理阶段进行不同位置优化时是必须的。

# 4. 读入时序及环境约束 (Read Timing Constraint)
source idct.sdc
# ↑ 导入 SDC (Synopsys Design Constraints) 约束文件，让工具知道目标工作频率是多少、外部输入有多大延迟等，它是驱动时序综合的心脏。

# 5. 执行逻辑综合指令 (Logic Synthesis)
optimize
# ↑ 最核心的一步（在DC里叫 compile）。把你的通用底层逻辑和寄存器，根据库文件，映射并最优化组合成真正的 SMIC180 门电路资源（如NAND、NOR、DFF），并尝试达到你的 SDC 时序和面积要求。

# 6. 报告导出 (Report)
analyze_constraint -all_violators > ../reports/violators_clk_with_driving.rpt
# ↑ 查错：输出有哪些路径没有达到时钟要求（时序违例），并保存到报告。
analyze_area > ../reports/area_report_clk_with_driving.rpt
# ↑ 审计：评估最终消耗了多少平方微米的硅面积。
analyze_timing > ../reports/timing_report_clk_with_driving.rpt
# ↑ 审计：输出关键路径时序余量（Setup/Hold Slack）。

# 7. 导出给后段物理设计的映射文件 (Output)
write_design -format verilog -hierarchy -o ../outputs/idct_chip_clk_with_driving.v
# ↑ 导出综合后的门级网表，供后仿和版图（PR）使用。
write_sdc ../outputs/idct_chip_clk_with_driving.sdc
# ↑ 导出供后端使用的最终优化后的约束文件。
```

### 2.2 idct.sdc：设计约束脚本
SDC (Synopsys Design Constraints) 定义了你芯片跑多快、外界环境的电容负载是多大、外界输入信号是在时钟沿多久后到达模块等等。
综合工具就像一个“考试做题机器”，你的代码是它的“能力”，但 SDC 的规则定义了这场考试要求“几分钟交卷（时序）以及能用几张草稿纸（面积）”。只有有了 SDC 给出的明确的 Clock Frequency (周期)，工具才会知道应该通过用多大的扇出门，或是插入多少 buffer 来抢时间。