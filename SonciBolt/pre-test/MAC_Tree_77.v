`timescale 1ns / 1ps

// =============================================================================
// Module Name : MAC_Tree_77
// Description : 面向 11x7 卷积窗的 77 路并行乘累加树。
//               采用 3 级流水线设计，确保满足 150MHz+ 时序要求。
//               带数据门控（Data Gating）技术，极致降低动态功耗。
// =============================================================================

module MAC_Tree_77 (
    input wire                 clk,
    input wire                 rst_n,
    
    // 控制信号
    input wire                 valid_in,     // 输入数据有效
    
    // 数据输入 (由于77个端口太多，工业界标准做法是将数组展平为一维宽向量)
    // 77 * 8 bit = 616 bits
    input wire [615:0]         act_flat_in,  // 77个INT8激活值 (从Line Buffer来)
    input wire [615:0]         wgt_flat_in,  // 77个INT8权重值 (从SRAM/寄存器来)
    input wire signed [15:0]   bias_in,      // INT16 偏置
    
    // 输出信号
    output reg                 valid_out,    // 输出数据有效
    output reg signed [31:0]   mac_out       // INT32 乘累加结果
);

    // =========================================================================
    // 0. 接口解包 (Unpacking) - 纯组合逻辑连线
    // fj0304: 这段接口解包代码不会带来额外流水级延迟，generate for 在综合后本质是静态位切片连线，更像“改名+接线”，不是算术运算。
    // fj0304: 为什么不在输入时设为输入二维数组端口？因为很多老旧的综合工具（比如某些版本的 DC 或 Quartus）会直接报错不支持
    // =========================================================================
    // 将 616 bit 的宽线缆，重新剥离成 77 根 8-bit 的有符号线缆
    wire signed [7:0] act [0:76];
    wire signed [7:0] wgt [0:76];
    
    genvar i;
    generate
        for (i = 0; i < 77; i = i + 1) begin : UNPACK
            assign act[i] = $signed(act_flat_in[i*8 +: 8]);
            assign wgt[i] = $signed(wgt_flat_in[i*8 +: 8]);
        end
    endgenerate

    // =========================================================================
    // Stage 1: 乘法级 (77个 INT8 * INT8 = INT16)
    // =========================================================================
    reg signed [15:0] mult_reg [0:76];
    reg               valid_s1;
    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            for (j = 0; j < 77; j = j + 1) begin
                mult_reg[j] <= 16'd0;
            end
        end else begin
            valid_s1 <= valid_in;
            // 【低功耗设计】：Data Gating。只有 valid_in=1 时乘法器才翻转
            if (valid_in) begin
                for (j = 0; j < 77; j = j + 1) begin
                    mult_reg[j] <= act[j] * wgt[j];
                end
            end
        end
    end

    // =========================================================================
    // Stage 2: 加法树第一级 (局部求和)
    // =========================================================================
    // 为了防止时序违例，我们不能一口气把77个数加完。
    // 这里将 77 个乘积分为 10 组：前9组每组加 8 个数，最后一组加 5 个数。
    // 8 个 16-bit 数相加，位宽扩展 3 位，最大为 19-bit。这里统一定义为 20-bit。
    reg signed[19:0] psum_reg [0:9];
    reg               valid_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s2 <= 1'b0;
            psum_reg[0] <= 20'd0; psum_reg[1] <= 20'd0; psum_reg[2] <= 20'd0; psum_reg[3] <= 20'd0;
            psum_reg[4] <= 20'd0; psum_reg[5] <= 20'd0; psum_reg[6] <= 20'd0; psum_reg[7] <= 20'd0;
            psum_reg[8] <= 20'd0; psum_reg[9] <= 20'd0;
        end else begin
            valid_s2 <= valid_s1;

            // fj0304: 仅在 valid_s1 信号有效时进行，避免无效翻转带来动态功耗，代价只是增加10个 2:1 mux？
            if (valid_s1) begin
                psum_reg[0] <= mult_reg[0] + mult_reg[1] + mult_reg[2] + mult_reg[3] + mult_reg[4] + mult_reg[5] + mult_reg[6] + mult_reg[7];
                psum_reg[1] <= mult_reg[8] + mult_reg[9] + mult_reg[10]+ mult_reg[11]+ mult_reg[12]+ mult_reg[13]+ mult_reg[14]+ mult_reg[15];
                psum_reg[2] <= mult_reg[16]+ mult_reg[17]+ mult_reg[18]+ mult_reg[19]+ mult_reg[20]+ mult_reg[21]+ mult_reg[22]+ mult_reg[23];
                psum_reg[3] <= mult_reg[24]+ mult_reg[25]+ mult_reg[26]+ mult_reg[27]+ mult_reg[28]+ mult_reg[29]+ mult_reg[30]+ mult_reg[31];
                psum_reg[4] <= mult_reg[32]+ mult_reg[33]+ mult_reg[34]+ mult_reg[35]+ mult_reg[36]+ mult_reg[37]+ mult_reg[38]+ mult_reg[39];
                psum_reg[5] <= mult_reg[40]+ mult_reg[41]+ mult_reg[42]+ mult_reg[43]+ mult_reg[44]+ mult_reg[45]+ mult_reg[46]+ mult_reg[47];
                psum_reg[6] <= mult_reg[48]+ mult_reg[49]+ mult_reg[50]+ mult_reg[51]+ mult_reg[52]+ mult_reg[53]+ mult_reg[54]+ mult_reg[55];
                psum_reg[7] <= mult_reg[56]+ mult_reg[57]+ mult_reg[58]+ mult_reg[59]+ mult_reg[60]+ mult_reg[61]+ mult_reg[62]+ mult_reg[63];
                psum_reg[8] <= mult_reg[64]+ mult_reg[65]+ mult_reg[66]+ mult_reg[67]+ mult_reg[68]+ mult_reg[69]+ mult_reg[70]+ mult_reg[71];
                psum_reg[9] <= mult_reg[72]+ mult_reg[73]+ mult_reg[74]+ mult_reg[75]+ mult_reg[76];
            end
        end
    end

    // =========================================================================
    // Stage 3: 加法树终级 + 偏置 (Bias) + 扩展至 INT32
    // =========================================================================
    // 将 10 个局部和 (20-bit) 以及 Bias (16-bit) 全部累加，存入最终的 32-bit 寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            mac_out   <= 32'd0;
        end else begin
            valid_out <= valid_s2;
            if (valid_s2) begin
                mac_out <= psum_reg[0] + psum_reg[1] + psum_reg[2] + psum_reg[3] + psum_reg[4] +
                           psum_reg[5] + psum_reg[6] + psum_reg[7] + psum_reg[8] + psum_reg[9] + 
                           $signed(bias_in); // bias也是有符号数，自动做符号位扩展后相加
            end
        end
    end

endmodule