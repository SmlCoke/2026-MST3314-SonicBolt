收到，综合和物理设计报告还没给，那 PPT 里第 4 章现在只能先做“占位框架”，不要写具体面积、功耗、slack、版图截图等结论。当前能确定讲的结果主要是 RTL 功能仿真和 496 样本连续仿真。

我建议整份答辩 PPT 按“目标约束 → 架构总览 → 关键技术 → 验证与结果”来讲。第 2 章不要急着深入每个模块细节，它的任务是让评委先建立一张全局地图。

**推荐结构**

1. **项目背景与目标**，约 3 页  
第 1 页讲项目定位：面向语音关键词识别的 INT8 CNN 加速器，课程全流程设计，0.18um，高性能场景。  
第 2 页讲算法网络：`Input -> Conv -> DWConv -> PWConv -> MaxPool -> FC -> Sigmoid`，配一张网络层级图和每层 tensor shape。  
第 3 页讲设计约束：`Speed >= 1000K frames/s`，`FoM = Speed / Area`，在 100MHz 下意味着平均帧间隔必须小于 100 cycles。

2. **系统架构概览**，建议 6-8 页  
这是你们现在最需要补强的部分。

第 1 页：算法到硬件的映射  
画一张“网络层 -> RTL 子系统”的对应图：

`Conv 子系统 -> DWConv 子系统 -> PWConv 子系统 -> Post Process`

下面标注：
`Conv: 1x30x10 -> 32x20x4`  
`DWConv: 32x20x4 -> 32x18x2`  
`PWConv: 32x18x2 -> 32x18x2`  
`Post: MaxPool -> 288 -> FC(2) -> Sigmoid`

这一页的讲法是：我们没有做通用 CNN accelerator，而是围绕固定网络结构做高度定制化流式硬件。

第 2 页：顶层数据通路  
用 [cnn.v](d:/Project/CNN-Accelerator-Bak/dev-test/2026-MST3314-SonicBolt/SonicBolt/src/cnn.v) 的连接关系画主图：

`Input Ping-Pong Buffer -> Conv -> DWConv -> PWConv -> MaxPool/FC/Sigmoid -> Output`

每条连线标注流接口元数据：
`valid / fire / last / pos / group / data`

这页重点讲：全系统不是“算完一层再存完整 feature map”，而是 tile stream 逐拍向后流动。

第 3 页：Token / Tile 抽象  
画一个 `9 pos x 8 group` 的网格。  
说明：

- `pos = 0..8`：MaxPool 后 9 个空间位置
- `group = 0..7`：32 通道按 4 通道一组
- 一帧正常输出 `9 x 8 = 72` 个有效 token
- 每个周期处理一个 `(pos, group)` 对应的 tile

这页是第 2 章的核心，后面第 3 章的 pos-group、五大元数据都从这里展开。

第 4 页：各子系统输入输出规格总览  
做成表格最清晰：

| 子系统 | 输入 tile | 输出 tile | 核心作用 | 特殊结构 |
|---|---|---|---|---|
| Conv | `14x10` 输入窗口 + 4 kernels | `4ch x 4x4` 或半窗拼接后完整 tile | 首层大卷积 | 输入双帧缓存、半窗缓存 |
| DWConv | `4ch x 4x4` | `4ch x 2x2` | 通道内 3x3 卷积 | 参数提前读取、流式透传 |
| PWConv | `4ch x 2x2` | `4ch x 2x2` | 32 通道融合 | odd/even pos ping-pong |
| Post | `4ch x 2x2` | 2 类概率 | MaxPool + FC + Sigmoid | 帧级累加、LUT Sigmoid |

第 5 页：片上存储组织  
这里不要展开到所有 bank 位宽细节，只讲为什么需要 SRAM/buffer：

- 输入图像：Conv 输入双 bank，当前帧计算时下一帧写入
- Conv/DWConv/PWConv 权重：按 row/group/bank 拆分，支持单拍取出当前 token 所需参数
- PWConv 输入缓存：同一 `pos` 的 8 个 group 先收齐，再发射 8 个输出 group
- FC 权重/LUT：后处理阶段流式寻址

图可以画成“数据 SRAM / 参数 SRAM / 计算核心”三块。

第 6 页：流水时序总览  
画横向 timeline：

`Conv issue 80 cycles -> DWConv pipeline -> PWConv delayed launch -> Post frame accumulation -> done`

标注几个关键数字：

- 理想 pos-group 有效 token：72 cycles
- 半窗缓存后 Conv issue：80 cycles
- v5.5 顶层 guard 后连续帧间隔：89 cycles
- 100MHz 下 `100M / 89 ≈ 1.12M fps`，满足 1000K fps 指标

第 7 页：控制协议总览  
用一页讲五大元数据，但只做概览，细节留给第 3 章：

- `pos/group`：定位当前 tile
- `valid`：当前 tile 是否有效
- `fire`：比 valid 提前启动参数读取
- `last`：标记当前帧最后一个 token

这一页可以配一张“fire 提前一拍，valid 对齐 data，last 收尾”的小波形图。

第 8 页：架构版本演进  
用时间线讲 v5.1 到 v5.5：

- v5.1：全链路基础功能
- v5.2：输入 Ping-Pong，支持连续帧
- v5.3：FSM 重构
- v5.4：半窗缓存，减少 Conv 重复计算
- v5.5：guard 保护窗，帧间隔压缩到 89 cycles

这页会让评委看到你们不是一次写完，而是在架构瓶颈中迭代优化。

3. **关键技术分析**，约 8-10 页  
这一章可以按你 `report.txt` 里的思路展开：

- Conv 流水计算：输入窗口、参数 bank、MAC、rescale/ReLU
- DWConv 流水计算：3x3 depthwise 如何单 token 处理
- PWConv：为什么需要 odd/even buffer 收齐 32 通道
- Post Process：MaxPool 逐 token 降维，FC 帧级累加
- pos-group 二维坐标架构
- 五大元数据协议
- 输入 Ping-Pong 缓存
- 半窗缓存：配 [repeated_window.png](d:/Project/CNN-Accelerator-Bak/dev-test/2026-MST3314-SonicBolt/SonicBolt/src/conv/docs/repeated_window.png)，讲 4928 个乘法器降到 2464 个乘法器的面积收益
- 下一帧启动 guard：103 cycles 压到 89 cycles

4. **项目结果分析**，现在先这样规划  
已有材料可以讲：

- RTL 仿真：单样本逐层输出可观察
- 连续仿真：`496 samples` 全部通过，最大误差约 `4.94e-7`
- 性能估算：基于 89 cycles/frame，在 100MHz 下满足 1000K fps

综合/物理设计等你们提供报告后再补：

- 逻辑综合：面积、功耗、最大频率、关键路径
- 物理设计：floorplan、utilization、placement/route、post-layout timing
- FoM：用最终 `Speed / Area` 计算
- 不足：guard=7 的理论解释尚不完全、Post Process 单帧累加器限制连续性、后端时序/拥塞风险

一个小建议：第 2 章标题可以改成 **“系统架构：面向 1 token/cycle 的流式 CNN”**。这样这一章从名字上就有技术主线，不只是“模块介绍”。