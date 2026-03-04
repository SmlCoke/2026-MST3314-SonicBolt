`timescale 1ns / 1ps

// =============================================================================
// Module Name : MAC_Tree_77
// Description : 面向 11x7 卷积窗的 77 路并行乘累加树。
//               采用 3 级流水线设计，确保满足 150MHz+ 时序要求。
//               带数据门控（Data Gating）技术，极致降低动态功耗。
// =============================================================================

module MAC77 (
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

    wire valid_mult;
    wire valid_add_s1;
    wire valid_add_s2;
    wire [77*16-1:0] products;
    wire [10*20-1:0] psums_s1;
    wire signed [31:0] mac_s2;

    MAC77_Mult u_mult (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .act_flat_in(act_flat_in),
        .wgt_flat_in(wgt_flat_in),
        .valid_out  (valid_mult),
        .products   (products)
    );

    MAC77_AddTree_s1 u_addtree_s1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_mult),
        .products   (products),
        .valid_out  (valid_add_s1),
        .psums_out  (psums_s1)
    );

    MAC77_AddTree_s2 u_addtree_s2 (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_add_s1),
        .psums_in   (psums_s1),
        .bias_in    (bias_in),
        .valid_out  (valid_add_s2),
        .mac_out    (mac_s2)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            mac_out   <= 32'sd0;
        end else begin
            valid_out <= valid_add_s2;
            if (valid_add_s2) begin
                mac_out <= mac_s2;
            end
        end
    end

endmodule