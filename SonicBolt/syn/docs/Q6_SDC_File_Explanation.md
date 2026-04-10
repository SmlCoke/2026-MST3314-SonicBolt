# Q6：SDC 时序约束文件逐行解析

SDC（Synopsys Design Constraints）是业界通用的设计约束格式。逻辑综合工具（DC 或 ZenSyn）在综合时，你的 RTL 代码决定了**逻辑功能**，而 SDC 决定了**物理性能**（跑多快、驱动多大、外部环境多么恶劣）。

以下以 `idct.sdc` 及常规约束的命令为例进行逐行归类解析：

## 1. 全局配置与单位 (Global Settings)

```tcl
set sdc_version 2.1
```
* **解释**：申明当前 SDC 文件的版本，以便解析器调用对应版本的语法。

```tcl
set_units -time ns -resistance kOhm -capacitance pF -power mW -voltage V -current mA
```
* **解释**：定义全局物理单位。后续写数字不带单位时，默认时间为纳秒 (ns)，电容为皮法 (pF)，以此类推。

```tcl
set_wire_load_mode segmented
```
* **解释**：线负载模型模式。在此阶段综合工具还不知道真实的版图走线多长。`segmented` 模式告知工具：在跨越不同层次的模块连线时，分别用各层级面积对应的预估线负载模型来计算连线延迟。

```tcl
set_max_transition 3 [current_design]
```
* **解释**：**设计规则约束 (DRC)**。要求整个设计里任何一根连线的信号高低电平翻转（Rise/Fall）时间不得超过 3ns。如果翻转太慢会引起极大的短路功耗。工具碰到长线会自动插 Buffer（缓冲器）来加快翻转。

---

## 2. 外部环境的电气建模 (Environment Constraints)

```tcl
set_driving_cell -lib_cell PO8W -pin PAD [get_ports {din[15]}]
# （通常你的 cnn.sdc 会精简为 set_driving_cell -lib_cell PO8W -pin PAD [all_inputs]）
```
* **解释**：**输入驱动建模**。告诉工具：“不要把输入端口当成具有无穷大驱动能力的理想信号”。假设外部是用一个库里叫做 `PO8W` 的单元的 `PAD` 引脚来驱动我们的。工具会根据 `PO8W` 的驱动能力计算出真实的信号到达斜率。

```tcl
set_load -pin_load 4.37 [get_ports {dout[15]}]
# （通常写为 set_load -pin_load 4.37 [all_outputs]）
```
* **解释**：**输出负载建模**。告诉工具：“我的输出引脚外面挂了一个 4.37 pF 的大电容”。综合工具看到后，会在输出端口内部选用驱动力更强的逻辑门（或者连续插多级大 buffer），以保证带得动这 4.37 pF 的外部负载而不违反时序。

---

## 3. 时钟网络定义 (Clock Definitions)

```tcl
create_clock [get_ports clk]  -period 10  -waveform {0 5}
```
* **解释**：**创建主时钟**。约束芯片的脉搏。频率为 1/10ns = 100MHz。占空比波形从 0ns 拉高，5ns 拉低（50%占空比）。这是时序分析的最根本基准。

```tcl
set_ideal_network [get_ports rstn]
```
* **解释**：**设置理想网络**。芯片内的复位线（rstn）和时钟线一样，会连接成千上万个触发器（高扇出）。逻辑综合阶段是不负责做时钟树和复位树的，因此设置为“理想网络”，告诉工具：“不要给复位线插 buffer，不要管它的延迟，当它的延迟为 0”。

```tcl
set_clock_latency -source 4  [get_clocks clk]
set_clock_latency 0.3  [get_clocks clk]
```
* **解释**：**时钟延迟**。
  * `-source 4` 指**源延迟 (Source latency)**：时钟从外部晶振板子，顺着 PCB 爬到芯片 `clk` 引脚所花的时间预估为 4ns。
  * `0.3` 指**网络延迟 (Network latency)**：信号进到引脚后，走到芯片最深处的触发器大概经历 0.3ns。

```tcl
set_clock_uncertainty 0.5  [get_clocks clk]
```
* **解释**：**时钟不确定性（非常重要）**。时钟的到达并不总是非常精准的（会受温度、电压波动导致的 Jitter 抖动，以及时钟树走线长短不一导致的 Skew 偏移）。这里设定 0.5ns 取悲观值，工具为了安全通过考试，会按照 `10ns - 0.5ns = 9.5ns` 这更加严苛的标准来压榨你的逻辑路径。

```tcl
# set_clock_transition -min/-max -fall/-rise 0.2 ...
```
* **解释**：设定时钟信号本身从 0 变 1 或 1 变 0 时，上升/下降沿所花费的爬坡时间（斜率过渡时间）预估为 0.2ns。

---

## 4. 输入输出路径的时序约束 (IO Delays)

在芯片与外部交互时，数据不仅要在本芯片走，还要在外部板子上走。

```tcl
set_input_delay -clock clk  -max 5  [get_ports {din[15]}]
```
* **解释**：**输入边界时间**。外部的芯片把数据发给你，外部芯片自身以及 PCB 走线“最多已经吃掉了当前此时钟周期的 5ns”。意味着，留给本芯片内部第一级触发器前的组合逻辑去计算的时间只剩下 `10ns - 5ns(外部吃掉) - 0.5ns(Uncertainty) = 4.5ns`。这对输入路径是很严苛的约束。

```tcl
set_output_delay -clock clk  -max 5  [get_ports {dout[15]}]
```
* **解释**：**输出边界时间**。本芯片算完数据发给下一个片子。外部的那个片子要求“数据必须提前 5ns 稳定送到我手里”。这意味着，留给本芯片从最后一级触发器出来向外推数据的可用耗时，最多只能用去 `10ns - 5ns(外部需要) - 0.5ns(Uncertainty) = 4.5ns` 就要把数据端出去。