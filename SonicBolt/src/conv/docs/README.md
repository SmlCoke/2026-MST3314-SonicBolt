# Conv1 高吞吐子系统设计说明

!!! note "注意"
    Conv 的输出 tile 是 $4\times 4\times 4 \times 8bit$ 张量
    排布方式：大通道编号在前$\rightarrow$大编号行在前$\rightarrow$大编号列在前
## 1. 设计目标
当前 `SonicBolt/src/conv` 的目标不是做一个“先算完整 Conv1 feature map，再把结果写回 SRAM”的独立层模块，而是直接对齐最终整网高吞吐实现。

本版设计固定采用：

- `pos-major` 作为层间主数据形态
- `4 通道/周期` 作为当前实现并行宽度
- 流式 tile 作为 Conv1 主输出接口
- banked SRAM 作为参数存储和调试存储基础

这意味着当前 `conv1` 不是孤立模块，而是后续 DWConv、PWConv、MaxPool 和 FC 前端的数据流模板。

## 2. 主数据形态
系统把整张输入图按 `pos` 划成 9 个空间位置：

- `pos = 0..8`

每个 `pos` 再按 32 个输出通道拆成 8 个通道组：

- `group = 0..7`
- 每组 `4` 个通道

因此整张图天然会被表示成：

- `9 pos x 8 groups = 72 token / image`

每个 token 的语义是：

- 当前 `pos`
- 当前 `group`
- 当前 `pos/group` 对应的完整 `4ch x 4x4` 输出 tile

当前版本只描述并实现这条主路径。旧版按 feature-map 行扫描、按 `kernel_row` 串行累计的实现已经删除，不再作为参考路径。

## 3. 目录内有效模块
当前 `SonicBolt/src/conv` 目录中，主通路模块如下：

- `conv_subsystem.v`
- `conv_param_store.v`
- `conv_shared_input_buffer.v`
- `conv_pos_window_gen.v`
- `conv_core.v`
- `conv_tile_mac.v`
- `conv_rescale_relu.v`
- `conv_sram_sp.v`

各模块职责如下：

### `conv_subsystem`
- 顶层封装
- 连接输入缓存、参数 SRAM 和计算核心

### `conv_param_store`
- 保存 Conv1 整层全部权重和全部偏置
- 向 `conv_core` 按 group 提供当前 token 需要的参数切片

### `conv_shared_input_buffer`
- 管理输入图像的双缓冲 shadow cache
- 对计算核心输出 `14x10` 输入窗口

### `conv_pos_window_gen`
- 根据 `pos` 从输入图中切出 `14x10` 窗口

### `conv_core`
- 按 `{pos, group}` 发出 token
- 驱动 MAC 与量化链路

### `conv_tile_mac`
- 计算一个完整 `4ch x 4x4` INT32 tile

### `conv_rescale_relu`
- 对 64 个 `INT32` 结果做统一量化和 ReLU

### `conv_sram_sp`
- 通用同步单端口 SRAM 行为模型

## 4. 输入缓存设计
### 4.1 输入图尺寸
当前 Conv1 输入图为：

- `30 x 10 x 8bit`

整帧总数据量为：

- `30 x 10 x 8 = 2400bit`

### 4.2 双缓冲 Shadow Cache
当前版本直接在 `conv_shared_input_buffer` 内维护两份整帧双缓冲 cache：

- `frame_cache0`
- `frame_cache1`

它们分别对应系统语义上的：

- `ping`
- `pong`

通过 `active_buf_sel` 选择当前哪一帧参与计算，另一帧则可继续被外部写入。



## 5. `pos` 到窗口的映射
`conv_pos_window_gen` 根据 `pos` 生成 `14x10` 窗口：

- `pos=0` 对应输入行 `0..13`
- `pos=1` 对应输入行 `2..15`
- `pos=2` 对应输入行 `4..17`
- ...
- `pos=8` 对应输入行 `16..29`

因此相邻 `pos` 之间只前进 2 行，这正是后续 DWConv、PWConv、MaxPool 能继续沿用 `pos-major` 形态的空间基础。

## 6. 权重与偏置组织
当前 `conv1` 不是只保存“当前计算正在使用的参数”，而是**在层内 SRAM 中完整保存整个 Conv1 层的全部参数**。运行时只是按 `group` 从中读取当前 token 所需的切片。

### 6.1 权重 bank
当前 Conv1 权重不是打包成一个超宽单 word，而是拆成 11 个 bank：

- `11` 个 `kernel_row`
- 每个 `kernel_row` 直接对应 1 个 bank

每个权重 bank 的规格为：

- `224bit x 8 depth`

位宽来源是：

- `4 channels x 7 weights x 8bit = 224bit`

深度 `4` 则对应：

- `8` 个输出通道组 `group=0..7`

bank 编号规则为：

- `bank = kernel_row`

所以对于一个固定 `group`，11 个 bank 同时读出后，可以拼成完整的：

- `4 x 11 x 7 x 8bit = 2464bit`

这正是 `conv_tile_mac` 的权重输入总线宽度。

### 6.2 bias bank
bias 采用 1 个 bank：

- 每个 bank `64bit x 8 depth`

位宽来源是：

- `4 x INT16 = 64bit`

一个 bank 读出后，可以得到当前 `group` 的完整：

- `4 x INT16 = 64bit`

这 11 个权重 bank 和 1 个偏置 bank 共同覆盖的是：

- Conv1 全部 32 个输出通道
- 全部 `11 x 7` 卷积核权重
- 全部 32 个 bias

后续 SonicBolt 其余计算层也遵循相同原则：

- 每一层在各自模块内部例化本层全部参数 SRAM
- 运行时只读取当前调度单元需要的参数切片
- 不采用单一全局参数总仓

## 7. 计算核心
### 7.1 调度粒度
`conv_core` 的基本工作单位是 `{pos, group}`。

一张图的调度顺序为：

- `pos=0, group=0..7`
- `pos=1, group=0..7`
- ...
- `pos=8, group=0..7`

总共发出：

- `72 token / image`

### 7.2 MAC 输出形态
`conv_tile_mac` 对每个 token 计算：

- `4` 个输出通道
- 每个输出通道 `4x4 = 16` 个空间输出

因此总输出数为：

- `4 x 16 = 64`

每个值在量化前是 `INT32`，所以 `conv_tile_mac` 输出总线宽度为：

- `64 x 32 = 2048bit`

即：

- `out_accum_bus[2047:0]`

### 7.3 量化与 ReLU
`conv_rescale_relu` 接收这 64 个 `INT32` 值，并执行：

1. 乘以 `M0`
2. 带符号右移 `SHIFT_N`
3. ReLU
4. 饱和到 `INT8`

因此其输出位宽为：

- `64 x 8 = 512bit`

对应当前主流 tile 数据：

- `4ch x 4x4 x 8bit`

## 8. 主输出与测试验证
### 8.1 主输出
当前主输出接口是：

- `out_stream_valid`
- `out_stream_pos`
- `out_stream_group`
- `out_stream_data`

其中：

- `out_stream_pos[3:0]` 表示 `0..8`
- `out_stream_group[2:0]` 表示 `0..7`
- `out_stream_data[511:0]` 表示一个完整 `4ch x 4x4` INT8 tile

这条接口是后续 DWConv 等层应该直接消费的主路径。


## 9. 性能评估
### 9.1 当前主节拍
当前 `conv1` 子系统的目标 steady-state 是：

- `1 token / cycle`

一张图共 36 个 token，因此理想主节拍为：

- `72 cycles / image`

这不包括少量流水填充和排空开销，但已经把最主要的吞吐上限定出来了。

### 9.2 Conv1 单层理论吞吐
如果按 `36 cycles / image` 估算：

在 `100 MHz` 下：

- `100M / 72 ≈ 1.39M image/s`

在 `120 MHz` 下：

- `120M / 72 ≈ 1.67M image/s`

所以从 Conv1 单层角度看，这版 `pos-major` 架构已经明显高于课程要求的 `1000k FPS` 门槛。

### 9.3 面向整网的速度预算
课程最终要求不是单层快，而是整网在 `100~120MHz` 下达到：

- `1000k FPS`

这等价于整图预算大约为：

- `100 cycles / image @ 100MHz`
- `120 cycles / image @ 120MHz`

当前架构选择 `72 token / image`，其意义在于：

- Conv1 本身不会成为节拍瓶颈
- 后续 DWConv、PWConv、MaxPool、Flatten/FC 仍有预算继续保持接近 `1 token / cycle`

如果后续层都沿用同样的 `pos-major` token 语义，并尽量避免整图回写再读回，整网落在：

- `<= 100 cycles / image`

这个目标窗口内是有机会实现的。

### 9.4 当前版本的实际定位
当前版本已经完成了三件关键的架构性工作：

1. 把主数据形态切到 `pos-major`
2. 把 Conv1 主输出切到流式 tile
3. 把参数组织改成适配高吞吐的 banked SRAM

这意味着当前版本已经具备“进入最终高吞吐系统”的接口形态和带宽形态。

但它仍然不是最终交付形态，后续还需要继续补：

- testbench 和数值对比
- DWConv / PWConv / MaxPool 的同形态接入
- 更细的流水和时序优化
- 层间 backpressure 策略

## 10. 总结
当前 `conv1` 子系统已经明确切换到面向最终系统的实现方向：

- 主数据流是 `pos-major`
- 主并行宽度是 `4 通道/周期`
- 主结果是流式 `4ch x 4x4` tile
- 参数依靠 banked SRAM 并行供数

这让 `conv1` 不再只是一个单独可运行的卷积层，而是变成了后续整网高吞吐实现的前端模板。
