# Q2：数字 IC 逻辑综合的一般流程

使用工具进行逻辑综合，是将高度抽象的寄存器传输级代码 (RTL) 转换成具体工艺流程（譬如中芯国际 180nm）下的门级网表 (Gate-Level Netlist) 的过程。无论使用国外主流的 Synopsys Design Compiler (DC) 还是国产华大九天 (ZenSyn)，步骤和原理极其相近，总结如下：

## 1. 逻辑综合的主要步骤与常用命令

| 步骤 | 说明与目的 | 华大九天 ZenSyn 命令对应 | 设计所需输入文件 |
| :--- | :--- | :--- | :--- |
| **Step 1: 启动与初始化** | 在服务器的 `work/` 目录中，设置好软件的环境变量并唤起软件图形界面或 Shell。 | `source setup.sh` 然后敲 `zs_shell` | 环境变量许可配置 `setup.sh` |
| **Step 2: 库文件加载** | 让工具知道它将把代码转译给“哪个代工厂的哪条流水线（工艺包）”，提供门电路的基本延时、功耗、面积参数（ `.lib` / `.db` ）。由于涉及 SRAM 数据记录，还会包括 Memory Compiler 产生的库。 | `set search_path ...`<br>`set target_lib x.lib ...` | Foundry 提供的 `.lib` 库（Std Cell，SRAM 等） |
| **Step 3: 代码读入与顶层设置** | 读入 Verilog 源文件。工具会先做一次基本的语法检查和转化（GTECH转换），然后指定设计的顶层级 (Top Level)。 | `read_design -format verilog a.v b.v`<br>`set current_design my_top_module` | 你手写的 `src/*.v` 中所有的 RTL 源代码 |
| **Step 4: 链接与展开** | 将引用的各类库单元、多层级调用的子模块“链接”在一起，若有被实例化的参数化模块也在此做解构独立化操作 (Uniquify)。| `link_design`<br>`make_unique` | - |
| **Step 5: 约束施加 (Constraints)** | 这是非常核心的一步。给你的模块制定规则：要施加多少 MHz 的主频；输入引脚的数据会延迟多久到达；输出引脚外挂了多少负载（电容）等。工具会基于此评估工作量。 | `source my_design.sdc` | 你根据设计写出来的 `.sdc` 文件 |
| **Step 6: 高级优化映射 (Compile/Optimize)** | 工具在算法引擎下寻找最优解。经历：架构级优化（选用何种加法器）-> 逻辑级优化（化简布尔等式）-> 门级映射（插入对应的物理门）。| `optimize` (DC中该指令叫 `compile`) | - |
| **Step 7: 结果分析与检查 (Report)** | 综合结束后，查看报告以判断是否达到要求（有无 Timing Violation？Area 面积是否符合指标？）。若有违例，可能要修改 RTL 或调整 SDC，重复 Step 2-6。 | `analyze_constraint -all_violators`<br>`analyze_timing`<br>`analyze_area` | - |
| **Step 8: 网表输出 (Output)** | 如果所有的时钟与面积要求都已经 Meet，输出由底层标准单元组成的 `.v` 网表，交付给物理版图组（Physical Design/PNR）和后仿组使用。 | `write_design -format verilog -o gate.v`<br>`write_sdc final.sdc` | - |

## 2. 参与综合的核心文件总结

想要顺利跑通逻辑综合，你手中必须握有以下三大拼图：

1.  **输入设计 (RTL Codes)**: 你的 `src/` 目录下的 `.v` 源码。这就是你的设计灵魂。
2.  **工厂库文件 (Standard Cell & Hard Macro Libraries)**: 服务器 `/SMIC18/lib` 给定的 `.lib` 特性文件，它定义了最底层的与非门、触发器、甚至 SRAM 长什么样，跑多快，占多大地。
3.  **设计目标约束 (SDC Constraint File)**: 手写的 SDC 环境配置。它是逻辑综合的标尺。没有 SDC 的综合只能叫作翻译而无法触发深度优化。

拥有以上三个材料，再结合工具特有的一组控制脚本（`.tcl`），就可以开启工具将前两者揉合，最终输出你想要的物理门网表了。