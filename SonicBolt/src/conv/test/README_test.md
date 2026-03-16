# Conv 子系统测试说明

## 1. 目标
这套测试环境用于验证当前 `SonicBolt/src/conv` 下的 `conv_subsystem`，验证范围只覆盖：

- Conv1 参数加载
- 输入样本写入
- `out_stream_*` 流式 tile 输出
- Conv1 卷积、重量化、ReLU 的结果正确性

## 2. 默认运行
在仓库根目录执行：

```powershell
python SonicBolt/src/conv/test/run_conv_tb.py
```

默认行为：

- 处理样本数为 `5`
- 起始样本为 `0`
- 不生成波形

## 3. 常用参数
指定样本数：

```powershell
python SonicBolt/src/conv/test/run_conv_tb.py --sample-count 1
```

指定起始样本和样本数：

```powershell
python SonicBolt/src/conv/test/run_conv_tb.py --start-index 10 --sample-count 3
```

打开波形：

```powershell
python SonicBolt/src/conv/test/run_conv_tb.py --wave
```

## 4. 数据预处理
Python 调度脚本会先调用：

```text
SonicBolt/data/prepare_conv_test_data.py
```

并将结果输出到：

```text
SonicBolt/data/prepared_conv_test/
```

主要输出包括：

- `weights/weight_bank_00.mem ~ weight_bank_10.mem`
- `weights/weight_words.mem`
- `bias/bias_bank_0.mem`
- `bias/bias_words.mem`
- `samples/sample_xxx_input_rows.mem`
- `samples/sample_xxx_tiles.mem`
- `manifest.json`

## 5. 仿真输出
testbench 在 `out_stream_valid` 有效时输出：

```text
TILE sample=<n> pos=<p> group=<g> data=<128hex>
```

Python 脚本会解析这些结果，并与黄金 tile 逐项比较。

## 6. 结果目录
所有测试产物都写到：

```text
SonicBolt/src/conv/test/results/
```

重点文件包括：

- `prepare_stdout.log`
- `prepare_stderr.log`
- `compile.log`
- `compile_stderr.log`
- `simulation_sample_xxx.log`
- `simulation_sample_xxx_stderr.log`
- `summary.json`
- `mismatch_report.txt`
- `conv_subsystem_tb.vvp`
