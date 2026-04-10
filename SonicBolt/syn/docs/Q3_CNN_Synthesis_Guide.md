# Q3：CNN 项目逻辑综合实战指南

基于 IDCT 项目的经验，你的 `cnn` 项目是可以直接在修改 IDCT 模板的基础上进行逻辑综合跑批的。下面是操作手册与入手建议。

## 第一步：构建你自己的综合工作区

在你的 `/SonicBolt` 根目录下，建议建立一个像 IDCT 一样规范和隔离的综合目录体系。由于你在 Linux 上作业，可以使用以下方法准备基础目录结构：

1.  拷贝基础文件夹架构模型：
    你可以自己在 `SonicBolt` 下建立一个新目录如 `syn/`：
    ```bash
    mkdir -p syn/work syn/scripts syn/reports syn/outputs
    ```
2.  从 `IDCT/Syn/work` 把 `setup.sh` 拷到 `syn/work`。

## 第二步：改造 TCL 一键控制脚本
在 `syn/scripts/` 中新建文件 `cnn_syn.tcl`，根据 IDCT 中 `zs.tcl` 的写法进行改造。针对你的 CNN 项目核心需要修改这几个地方：

### 1. 替换模块来源文件路线
你的项目结构层次丰富，包含了 Conv, DWConv, PWConv 等诸多模块及子文件夹。你需要通过脚本依次把所有 `.v` 文件告诉综合工具（推荐先读底层模块，再读上层模块，最后读顶层，不需要读取 `_tb` 相关的测试文件）。

```tcl
# 路径依据你的执行目录 syn/work 为准, 找到 src/ 下的文件
set search_path "$search_path ../../src ../../src/conv ../../src/dwconv ../../src/pwconv ../../src/post_process ../../src/utils ../../../../SMIC18/lib ../../../../SMIC18/mem ../work"
# 注：一定要确认 SMIC18 在系统里的正确相对层级路径

set target_lib   "slow.lib S018V3EBCDSP_X16Y4D16_PR.lib S018V3EBCDSP_X8Y4D112_PR.lib ... SP018W_V1p8_max.lib"
# 尤其注意此行：你在 /src/utils 里调用了一些特定的 SRAM (如 X8Y4D112 / 128 / 64 等)，需要确保你在 target_lib 把对应的 SRAM .lib 也包含进去了，否则工具抓取不到这块记忆体。
```

### 2. 依次读入 Verilog 并设定 Top 模块
你不需要读任何 `_tb.v` 系列仿真脚本，只需要被综合的代码。
```tcl
read_design -format verilog ../../src/utils/sram_sp.v
read_design -format verilog ../../src/utils/relu_saturate.v
# ... (中间省略：读入conv/ dwconv/ pwconv/ post_process/ 里面的各项v文件)
read_design -format verilog ../../src/cnn.v

# 这是你的核心：设置 cnn 为顶层
set current_design cnn

link_design
make_unique
```

## 第三步：编写基于真实指标的 CNN 约束 (cnn.sdc)
IDCT 有 `idct.sdc`，你的 CNN 必须要写一个属于它的 `cnn.sdc` 放于 `syn/scripts/` 中。参考你的 `Design_Specifications.md`，比如给定的性能要求时钟是 200MHz。
一个基础版的 SDC 可能长这样：

```tcl
# 假设时钟频率要求为 200Mhz，对应的周期 (period) 就是 5 ns
create_clock -name "clk" -period 5.0 [get_ports clk]

# 对真实环境时钟信号的不确定性做适当悲观的修正 (Jitter)
set_clock_uncertainty 0.3 [get_clocks clk]

# 告诉综合工具外界给这些输入信号通常也要消耗时间的(Setup时间留裕度)
set_input_delay -max 1.0 -clock [get_clocks clk] [remove_from_collection [all_inputs] [get_ports clk]]

# 同样给予输出给下一级芯片留出的时间余量
set_output_delay -max 1.0 -clock [get_clocks clk] [all_outputs]

# （可选）添加一定的输出端口电容负载
set_load 0.05 [all_outputs]
```

然后在你的主脚本 `cnn_syn.tcl` 里包含它：
```tcl
source ../scripts/cnn.sdc
```

## 第四步：修改结果导出路径
修改报告输出阶段和最终网表的名字：
```tcl
optimize

analyze_constraint -all_violators > ../reports/violators.rpt
analyze_area > ../reports/area_report.rpt
analyze_timing > ../reports/timing_report.rpt

write_design -format verilog -hierarchy -o ../outputs/cnn_netlist.v
write_sdc ../outputs/cnn_mapped.sdc
```

## 第五步：实机上线与跑综合
按照服务器手册，进入 `syn/work`:
1.  输入 `csh` 进入指定的 Shell。
2.  输入 `source setup.sh` 使能证书。
3.  输入 `zs_shell -f ../scripts/cnn_syn.tcl`。
4.  紧盯屏幕，如果遇到 `Error` 则排查路径或者没有被加进来的库。如果是一路 `Warning` 且最终完成并在 `reports/` 下打印出了报告，那么恭喜你，你的 CNN 加速器逻辑综合跑通了！接下来就是阅读 `timing_report.rpt` 看 Slack 是否为正（非负数代表时序达标了）。