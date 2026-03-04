# Ping-Pong Buffer（乒乓缓冲区）

> Assited by Google AI Studio

### 一、 为什么需要 Ping-Pong Buffer？（破除串行瓶颈）

按照你的场景描述：
如果只有**一块 SRAM**，Conv1 算完一整张图写进去，然后 DWConv 才能开始读。
这就像餐厅里**只有一张餐桌**：
* 厨师（Conv）把菜摆满桌子，退下。
* 顾客（DWConv）上桌把菜吃完，退下。
* 厨师再上来摆第二桌...
这就导致厨师和顾客**永远有一方在干等（闲置）**，硬件利用率只有 50%，吞吐量极其低下。

**乒乓操作（Ping-Pong Operation）的本质是：空间换时间。**
我们准备**两块完全独立的 SRAM（Bank A 和 Bank B）**（相当于两张餐桌）。

### 二、 Ping-Pong Buffer 的工作机制

我们引入一个极其简单的控制信号：**`pp_sel` (Ping-Pong Select，1 bit 触发器)**，每处理完一帧图像，它就翻转一次（0变1，1变0）。

#### 状态 0 (`pp_sel == 0`): "Ping" 阶段
* **Conv (上游模块)**：将第 **N** 帧的计算结果写入 **Bank A**。
* **DWConv (下游模块)**：从 **Bank B** 读取第 **N-1** 帧的数据进行计算。
*(两者并行工作，互不干扰！)*

#### 状态 1 (`pp_sel == 1`): "Pong" 阶段
* 当两边都宣告“我算完了”时，`pp_sel` 翻转为 1。
* **Conv (上游模块)**：将第 **N+1** 帧的计算结果写入 **Bank B**。
* **DWConv (下游模块)**：从 **Bank A** 读取刚才 Conv 刚写好的第 **N** 帧数据进行计算。

#### 宏观流水线效果：
除了第一帧 DWConv 需要等待 Conv 初始化外，从第二帧开始，**Conv 和 DWConv 100% 的时间都在全速运转**！你的吞吐量（FPS）瞬间翻倍。

---

### 三、 硬件 RTL 是如何实现 Ping-Pong 的？（解密连线）

很多初学者觉得 Ping-Pong 很难，其实在 Verilog 层面，它**就是一个纯粹的 MUX（多路选择器）和 DEMUX（多路分配器）的游戏**。

SRAM Bank A 和 Bank B 都有自己的引脚：`addr` (地址), `wdata` (写数据), `wen` (写使能), `rdata` (读出的数据)。

我们要做的，就是用 `pp_sel` 来充当**铁路道岔**。

#### Verilog 核心代码框架：

```verilog
// 1. 乒乓状态机（极其简单，就是一个 T触发器）
reg pp_sel;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pp_sel <= 1'b0;
    end else if (conv_done && dwconv_done) begin
        // 只有当上下游都处理完当前帧时，才交换场地！(握手同步)
        pp_sel <= ~pp_sel; 
    end
end

// ==========================================================
// 2. 路由连线逻辑 (使用组合逻辑 assign)
// ==========================================================

// ── 对 Bank A 的控制 ──
// 如果 pp_sel==0, Bank A 给 Conv 写；如果 pp_sel==1, Bank A 给 DWConv 读
assign sram_A_wen   = (pp_sel == 1'b0) ? conv_wen   : 1'b0;          // 读状态下严禁写入
assign sram_A_addr  = (pp_sel == 1'b0) ? conv_addr  : dwconv_addr;
assign sram_A_wdata = conv_wdata; // 写数据可以直接连，反正 wen 会阻断无效写入

// ── 对 Bank B 的控制 ──
// 如果 pp_sel==0, Bank B 给 DWConv 读；如果 pp_sel==1, Bank B 给 Conv 写
assign sram_B_wen   = (pp_sel == 1'b1) ? conv_wen   : 1'b0;
assign sram_B_addr  = (pp_sel == 1'b1) ? conv_addr  : dwconv_addr;
assign sram_B_wdata = conv_wdata;

// ── 吐给 DWConv 的读取数据 ──
// 如果 pp_sel==0, DWConv 应该拿到 Bank B 的数据；反之拿 Bank A 的数据
assign dwconv_rdata = (pp_sel == 1'b0) ? sram_B_rdata : sram_A_rdata;

```

看懂这段代码，你就掌握了数字 IC 中跨模块大规模数据交互的核心密码！`pp_sel` 就像一个红绿灯，精准地指挥着海量数据的流向。

---

### 四、 👑 架构师进阶：什么时候用 Line Buffer？什么时候用 Ping-Pong？

在这个课程设计里，你同时学到了 Line Buffer 和 Ping-Pong Buffer。很多同学会把它们搞混，或者到处滥用。
**请一定要在你们的架构设计中认清这两者的区别：**

1. **层间数据流动（Streaming）—— 优先用 Line Buffer**
   * 实际上，Conv 算出特征图的一行后，DWConv **不需要**等整张图算完，它只要拿到几行数据就可以开始滑动了！
   * 所以，在 `Conv -> DWConv -> PWConv` 这几个全卷积层之间，**最顶级的做法是完全不用 Ping-Pong，也不把中间整图存回主 SRAM！** 而是直接用 **Line Buffer** 把它们串起来，数据像流水一样穿过这三个层。这能省下巨大的 SRAM 面积！

2. **跨越维度鸿沟（Dimensionality Change）—— 必须用 Ping-Pong Buffer**
   * 看看你们网络规范的后半段：**`Maxpool (输出 32x9x1) -> Flatten -> FC 全连接层`**。
   * 全连接层需要把所有空间维度的特征图展平。FC 算第一个输出神经元时，就需要跨越不同通道、不同坐标的所有数据！
   * 此时，Line Buffer 失效了（因为 FC 不是局部滑动窗口）。
   * 此时，你**必须**使用 **Ping-Pong Buffer**。让卷积池化层把一整帧的 `32x9x1` 数据老老实实地写进 Ping-Pong SRAM A；当下一帧开始写 SRAM B 时，FC 层再从 SRAM A 里疯狂乱序读取数据进行矩阵乘法。

**团队项目策略建议：**
如果你想在答辩时脱颖而出，可以在 PPT 的架构图里画出这种**“混合缓存策略”**：
> “为了平衡面积与速度，我们在前端连续卷积层使用了基于移位寄存器的 **Line Buffer** 实现极致流式处理；而在池化层与全连接层之间，由于访存模式（Access Pattern）发生全局突变，我们采用了 **Ping-Pong SRAM** 架构进行帧级流水线遮掩。”

把这段话说出来，这门课你们绝对是最高分！如果你想进一步细化某一段的 Verilog 代码或者 FSM 状态机设计，我们可以继续深入！