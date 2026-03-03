# Pipeline

> Assisted by Google AI Studio

## 流水线代码示例：4通道并行 MAC 树
```verilog
module Parallel_MAC_Tree (
    input  wire        clk,
    input  wire        rst_n,
    
    // 控制信号
    input  wire        valid_in,  // 输入数据有效
    input  wire        last_in,   // 这是一个卷积窗的最后一次输入（指示累加结束）
    
    // 4路并行输入数据 (INT8)
    input  wire signed [7:0] weight_0, weight_1, weight_2, weight_3,
    input  wire signed [7:0] act_0,    act_1,    act_2,    act_3,
    
    // 输出信号
    output reg         valid_out, // 输出数据有效（此时代表一个完整的累加和完毕）
    output reg signed [31:0] mac_out    // 累加完成的最终结果 (INT32)
);

    // ====================================================================
    // Stage 1: 4个并行的乘法器 (INT8 * INT8 = INT16)
    // ====================================================================
    reg signed[15:0] mult_r0, mult_r1, mult_r2, mult_r3;
    reg               valid_s1, last_s1; // 流水线寄存器：同步传递控制信号

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_r0 <= 16'd0; mult_r1 <= 16'd0;
            mult_r2 <= 16'd0; mult_r3 <= 16'd0;
            valid_s1 <= 1'b0; last_s1 <= 1'b0;
        end else if (valid_in) begin
            // 只有输入有效时才计算，降低功耗
            mult_r0 <= weight_0 * act_0;
            mult_r1 <= weight_1 * act_1;
            mult_r2 <= weight_2 * act_2;
            mult_r3 <= weight_3 * act_3;
            valid_s1 <= 1'b1;
            last_s1  <= last_in;  // 把 "last" 标志打入第1级寄存器
        end else begin
            valid_s1 <= 1'b0;     // 无效数据，流水线产生气泡
            last_s1  <= 1'b0;
        end
    end

    // ====================================================================
    // Stage 2: 第一级加法树 (两两相加, INT16 + INT16 = INT17)
    // ====================================================================
    reg signed [16:0] add_tree_0; // mult_r0 + mult_r1
    reg signed [16:0] add_tree_1; // mult_r2 + mult_r3
    reg               valid_s2, last_s2; // 继续向后传递控制信号

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_tree_0 <= 17'd0;
            add_tree_1 <= 17'd0;
            valid_s2   <= 1'b0;
            last_s2    <= 1'b0;
        end else begin
            // 控制信号永远流动
            valid_s2   <= valid_s1;
            last_s2    <= last_s1;
            
            // 数据寄存器：只有在 valid 成立时才更新！
            // 这种写法会让综合工具自动推断出带有 Clock Enable (CE) 端的触发器。
            // 当 valid_s1=0 时，寄存器完全不翻转，极致省电！
            if (valid_s1) begin 
                add_tree_0 <= mult_r0 + mult_r1;
                add_tree_1 <= mult_r2 + mult_r3;
            end
        end
    end

    // ====================================================================
    // Stage 3: 第二级加法 + 累加器 (Accumulator) (INT17 + INT17 + INT32 = INT32)
    // ====================================================================
    reg signed [31:0] accumulator;
    wire signed[17:0] stage2_sum; 
    
    // 组合逻辑：算出当前这4个数的总和
    assign stage2_sum = add_tree_0 + add_tree_1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 32'd0;
            mac_out     <= 32'd0;
            valid_out   <= 1'b0;
        end else begin
            // 默认情况下输出无效
            valid_out <= 1'b0; 
            
            if (valid_s2) begin
                if (last_s2) begin
                    // 如果这是当前像素卷积计算的最后一次 4个数据
                    // 1. 把最终结果输出给下一级 (加上之前的累加值)
                    mac_out   <= accumulator + stage2_sum;
                    valid_out <= 1'b1;  // 告诉下一级（比如重量化模块）：这有个算完的 INT32 数据
                    // 2. 清空累加器，准备算下一个特征图的像素
                    accumulator <= 32'd0; 
                end else begin
                    // 如果还没算完，就不断累加到 accumulator 中
                    accumulator <= accumulator + stage2_sum;
                end
            end
        end
    end

endmodule
```


### 代码核心知识点解析：

1.  **控制信号跟踪**：
    - `valid_in`：告诉流水线这是一个有效输入，触发计算。如果 `valid_in` 是 0，流水线就会产生一个“气泡”（`valid_s1 = 0, last_s1 = 0`），后续阶段看到 `valid` 是 0 就不处理数据，保证了数据的安全性。
    - `last_in`：告诉流水线这是当前卷积窗的最后一次输入，触发累加器输出结果并清零。这个信号必须伴随 `valid` 一起传递到每个阶段（通过 `last_s1`, `last_s2`），**确保每个阶段都知道何时一个完整的卷积计算结束了**。
    - `valid_s1`：告诉流水线第一级乘法器的输出是有效的，**允许第二级执行计算**。**如果信号无效，也不会做任何操作**
        > 可能我们以为让加法结果为0要好点，实则并非，因为这会产生无意义的信号翻转，增加功耗。
    - `last_s1`：告诉流水线第一级乘法器的输出是当前卷积窗的最后一次输入，**允许第二级知道何时一个完整的卷积计算结束了**。
    - `valid_s2` 和 `last_s2`：同理，继续向后传递控制信号，**确保第三级加法器和累加器知道何时输出结果**。
    
    !!! note "控制信号永远流动！这非常重要！"
        寄存器打拍就像包裹过安检机器。包裹（数据）走到了哪一步，它的快递单（控制信号）必须跟着走到哪一步。否则，Stage 3 怎么知道此时到达的数据是不是最后一次累加？

2.  **流水线气泡（Bubble）**：
    如果 `valid_in` 突然变为 0（比如前面读内存卡了一下），Stage 1 的 `valid_s1` 就会变 0。这个“无效状态”会像一个气泡一样顺着流水线往后传。Stage 2 和 Stage 3 看到 valid 是 0，就不做实质性的处理。这样保证了数据的绝对安全。
    
    !!! note **流水线气泡的出现不一定是算的慢！**
        即使我们假设所有的加法器、乘法器都是神仙做的，计算时间为0纳秒（纯理想情况），气泡依然存在。
        **为什么？**
        > 1. **等待前级缓冲填满**：就像我们前面聊过的，DWConv 需要等 Conv1 算出 3 行数据（存满 Line Buffer）才能凑齐一个 3x3 窗口。在这个“等待攒够 3 行数据”的漫长时间里，DWConv 的 valid_in 就是 0，这就是气泡。
        > 2. **读取外部存储延迟（SRAM Latency）**：你要从片上 SRAM 读权重，给一个地址，SRAM 内部的存储阵列需要 1 到 2 个时钟周期才能把数据吐出来。在等待数据的这 1~2 个周期里，流水线只能空转产生气泡。
3.  **位宽增长（Bit-width Growth）**：
    *   乘法：8位 * 8位 = 16位。
    *   加法：16位 + 16位 = 17位（防止溢出，必须进位）。
    *   加法：17位 + 17位 = 18位。
    *   累加器：因为要加几十次，所以直接给了 32 位（文档里规定的 INT32 中间值）。硬件里位宽精打细算，能省则省，这直接关系到最终的面积（Area）。

