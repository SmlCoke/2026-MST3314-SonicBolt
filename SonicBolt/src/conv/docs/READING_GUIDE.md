# Conv 子系统阅读指导

## 1. 先建立正确的阅读心智
当前 `SonicBolt/src/conv` 目录里只保留了一条主线：

- 主数据形态是 `pos-major`
- 主调度粒度是 `{pos, group}`
- 主输出是一个完整的 `4ch x 4x4` tile


## 2. 这版代码的总图景
整张输入图在当前设计里会被切成 9 个空间位置：

- `pos = 0..8`

每个 `pos` 再按 32 个输出通道拆成 8 个通道组：

- `group = 0..7`
- 每组 `4` 个输出通道

因此一张图总共只需要处理：

- `9 pos x 8 groups = 72 token / image`

每个 token 的语义是：

- 当前 `pos`
- 当前 `group`
- 该 `pos/group` 对应的完整 `4ch x 4x4` 输出 tile

## 3. 推荐阅读顺序
建议按下面顺序阅读：

1. `README_conv1_architecture.md`
2. `conv_subsystem.v`
3. `conv_param_store.v`
4. `conv_shared_input_buffer.v`
5. `conv_pos_window_gen.v`
6. `conv_core.v`
7. `conv_tile_mac.v`
8. `conv_rescale_relu.v`
9. `conv_sram_sp.v`

这个顺序的目的很简单：

- 先看顶层，知道系统怎么拼
- 再看参数到底放在哪里
- 然后看输入窗口怎么生成
- 再看 `{pos, group}` 怎么被调度
- 最后看一拍 tile 是怎么被算出来、量化并输出的

## 4. 先看顶层 `conv_subsystem.v`
这是整套 `conv1` 子系统的总装模块，也是理解系统最省力的入口。

阅读时重点看三件事：

1. 输入图像如何写入双缓冲输入 cache
2. `conv_param_store` 如何保存 Conv1 整层全部权重和全部偏置
3. 主结果为什么只走 `out_stream_*` 流式接口

当前版本已经明确把“调试缓存/调试 SRAM”从综合顶层中拿掉了。  
如果需要缓存 tile、按 bank 回看、做额外重排，这些工作统一在 testbench 中完成。

### `conv_param_store.v`
建议把它放在顶层之后立刻读，因为它回答了一个很关键的问题：

- 当前 SRAM 里存的到底是“整层参数”还是“当前 token 临时参数”？

答案是前者。

`conv_param_store` 里保存的是：

- Conv1 全部 32 个输出通道的权重
- 全部 `11 x 7` 卷积核系数
- 全部 32 个 bias

运行时 `conv_core` 只是按 `group` 去读其中一部分切片。

## 5. 输入前端怎么读
### `conv_shared_input_buffer.v`
这个模块负责把“外部按整帧写入”的图像，变成“内部按 `pos` 读取”的窗口数据。

它内部现在只保留两份东西：

- `frame_cache0`
- `frame_cache1`

这两份 cache 就是当前版本真正参与主通路的双缓冲输入缓存：

- 外部逐行把整帧写进其中一份
- `start_consume` 到来时，用 `start_buf_sel` 选择当前活动帧
- 之后 `active_buf_sel` 指向当前被消费的那一份 cache
- 再从该 cache 直接按 `pos` 切出 `14x10` 窗口

也就是说，当前实现已经删掉了那层未参与主通路的底层输入 SRAM，只保留真正用到的双缓冲 cache。

### `conv_pos_window_gen.v`
这个模块只做一件事：

- 根据 `pos=0..8`
- 从 `30x10` 输入图里切出对应的 `14x10` 输入窗口

这里最关键的映射关系是：

- `pos=0` 对应输入行 `0..13`
- `pos=1` 对应输入行 `2..15`
- ...
- `pos=8` 对应输入行 `16..29`

也就是说，相邻 `pos` 之间只前进 2 行。这正是 `docs/notes.md` 里那套形状变换的空间基础。

## 6. 核心调度怎么读
### `conv_core.v`
`conv_core` 是当前主通路的调度中心。

这一版它只围绕 `{pos, group}` 工作，不再做旧式的 feature-map 行扫描控制。你读它时重点看下面几组信号：

- `issue_pos / issue_group`
- `issue_count`
- `stage0_valid / stage0_pos / stage0_group / stage0_last`
- `weight_rd_* / bias_rd_*`
- `tile_*`
- `quant_*`

把它翻译成白话就是：

- 一张图总共发出 72 个 token
- 每拍发一个 token 请求
- 每个 token 请求都会带一个 `pos` 和一个 `group`
- 同时按 group 从 `conv_param_store` 读取当前 token 所需的参数切片
- 后面 MAC 和量化模块都只是在处理这个 token 对应的数据

## 7. 真正的计算核心怎么读
### `conv_tile_mac.v`
这是当前最核心的计算模块。

它的输入是：

- 一个 `14x10` 的输入窗口
- 当前 `group` 的完整权重
- 当前 `group` 的 4 个 bias

它的输出是：

- 一个完整的 `4ch x 4x4` INT32 tile

你读这个模块时，建议抓三个索引公式：

1. 输入窗口索引
2. 权重索引
3. 输出索引

尤其是输出索引：

- `out_idx = ch * 16 + oy * 4 + ox`

这表示：

- 每个通道有 16 个输出值
- 16 个值按照 `4x4` 的空间顺序排布
- 总共 4 个通道，所以一共 64 个 `INT32`

## 8. 量化和输出怎么读
### `conv_rescale_relu.v`
这个模块把 MAC 给出的 64 个 `INT32` 结果，统一转换成 64 个 `INT8`。

它做的事情是：

1. `int32 x M0`
2. 带舍入的算术右移
3. ReLU
4. 饱和到 `INT8`

你读它时重点不要只看算术，还要看元数据对齐：

- `in_pos / in_group / in_last`
- `out_pos / out_group / out_last`

这些信号说明当前 tile 属于哪一个 token，以及最后一个 token 什么时候出管线。

## 9. 参数存储怎么读
当前参数组织不是 MiniCNN 旧版那种 `77bit x 8` 切法，而是更适合当前高吞吐 `pos-major` 通路的 banked 组织。

这里最重要的阅读结论是：

- 当前 `conv` 子系统内部保存的是 **Conv1 整层完整参数**
- 不是“随着当前计算临时装入的一小部分参数”
- 后续 DWConv、PWConv、FC、sigmoid LUT 也都应在各自层模块内部保存本层完整参数 SRAM

### 权重 bank
- 一共 11 个 bank
- 每个 bank `224bit x 8`
- `8` 个地址对应 `8` 个 `group`

bank 编号规则是：

- `bank = kernel_row`

语义是：

- 一共有 11 个卷积核行
- 每个卷积核行直接存当前 group 的 4 个输出通道各自的 7 个 `INT8` 权重

因此对于一个 `group` 来说，11 个 bank 同时读出后，就能拼成完整的：

- `4 channels x 11 x 7`

### bias bank
- 一共 1 个 bank
- 每个 bank `64bit x 8`

语义是：

- 每个地址对应一个 `group`
- 一个 bank 直接给出该 `group` 的 4 个 `INT16 bias`

## 10. 阅读时最容易误解的点
### 误解 1：为什么主输出接口这么宽
因为当前目标不是“方便观察波形”，而是“为整网 `1000k FPS` 留住主通路吞吐”。

如果在 `conv1` 之后立刻把接口压窄，后面的层很容易又退回到：

- 先落完整 feature map
- 再读回继续算

那条路很难达到最终节拍目标。

### 误解 2：当前输入端是不是还有一层底层输入 SRAM
不是。当前版本已经把未参与主通路的那层输入 SRAM 删除了，只保留真正用于双缓冲和切窗的 `frame_cache0/frame_cache1`。

### 误解 3：为什么源码里没有调试 SRAM
这是刻意的结构收敛，不是遗漏。

当前版本把调试缓存逻辑放回 testbench，原因是：

- `out_stream_*` 已经足够表达主结果
- 调试缓存不属于综合后真正需要的硬件
- 放在 testbench 里更容易按需要缓存、重排和比较 tile

## 11. 读完后应该记住什么
如果你读完后只记住三件事，就记这三件：

1. 当前 `conv` 目录只保留 `pos-major + 4 通道/周期` 主架构
2. 每个 token 都是一个 `{pos, group}` 对应的完整 `4ch x 4x4` tile
3. 当前 `conv_shared_input_buffer` 只保留双缓冲 cache，当前 `conv_param_store` 保存的是 Conv1 整层全部参数

## 12. 当前测试主路径
当前自动化测试主路径走的是 `out_stream_*`。

这样设计的原因是：

- `out_stream_*` 才是当前架构真正的主输出接口
- 它直接反映 `{pos, group}` token 的流式语义
- 用它做比较，可以直接验证当前主通路是否正确

如果需要把 tile 暂存、按 bank 回看或做额外重排，统一在 testbench 中完成，不再把这类逻辑放入 `conv_subsystem`。

如果你接下来要阅读测试代码，推荐顺序是：

1. `src/conv/test/conv_subsystem_tb.v`
2. `src/conv/test/run_conv_tb.py`
3. `data/prepare_conv_test_data.py`

这三部分和 `conv_subsystem.v` 一起看，会最容易看清：

- 输入样本如何通过顶层写口进入当前活动 buffer
- Conv1 全层参数如何通过 banked 写口装入层内 SRAM
- `{pos, group}` tile 如何被打印、解析并和黄金值逐项比较
