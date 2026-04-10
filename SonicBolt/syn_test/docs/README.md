# syn_test: 单模块综合诊断工程

## 目标
只综合 `conv_tile_mac_row_mult`，用于快速判断：
- 是否该模块本身就是综合瓶颈
- 放宽时钟后是否明显加速

## 目录结构
- `scripts/zs_row_mult.tcl`: ZenSyn 综合脚本（top=conv_tile_mac_row_mult）
- `scripts/row_mult.sdc`: 基础时序约束（不含 IO pad driving 约束）
- `reports/`: 综合报告输出
- `outputs/`: 网表和导出 SDC
- `work/`: 建议运行目录

## 运行方法
1. 进入工作目录：
   - `cd SonicBolt/syn_test/work`
2. 启动 ZenSyn 并执行脚本：
   - `zs_shell -f ../scripts/zs_row_mult.tcl`

> 如果你的环境需要先 source 工具环境脚本，请按你现有服务器流程先执行。

## 结果文件
- `../reports/row_mult_area.rpt`
- `../reports/row_mult_timing.rpt`
- `../reports/row_mult_violators.rpt`
- `../outputs/conv_tile_mac_row_mult_syn.v`

## 调参建议
- 先用 `period=20ns` 跑通看耗时
- 再逐步收紧到 `10ns / 8ns / 5ns`
- 对比每次综合耗时和 WNS/TNS，确认瓶颈是“结构复杂度”还是“约束过紧”
