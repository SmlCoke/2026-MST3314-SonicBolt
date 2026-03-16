`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_reduce_l2
 * 功能概述:
 *   对第一层归约得到的 6 组中间和做第二层归约，固定实现为 6 -> 1。
 *
 * 输出:
 *   - out_sum_bus 含 64 个 INT32，总宽度 2048bit。
 */
module conv_tile_mac_row_reduce_l2 (
    input  wire               clk,             // 时钟
    input  wire               rst_n,           // 低有效复位
    input  wire [6*2048-1:0]  in_partial_bus,  // 6 组中间和
    output reg  [2047:0]      out_sum_bus      // 最终 64 个 INT32 卷积和
);

    integer idx;
    reg signed [31:0] partial_0;
    reg signed [31:0] partial_1;
    reg signed [31:0] partial_2;
    reg signed [31:0] partial_3;
    reg signed [31:0] partial_4;
    reg signed [31:0] partial_5;
    reg signed [32:0] sum_l1_0;
    reg signed [32:0] sum_l1_1;
    reg signed [32:0] sum_l1_2;
    reg signed [33:0] total_sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_sum_bus <= 2048'd0;
        end else begin
            for (idx = 0; idx < 64; idx = idx + 1) begin
                partial_0 = in_partial_bus[(0*2048) + idx*32 +: 32];
                partial_1 = in_partial_bus[(1*2048) + idx*32 +: 32];
                partial_2 = in_partial_bus[(2*2048) + idx*32 +: 32];
                partial_3 = in_partial_bus[(3*2048) + idx*32 +: 32];
                partial_4 = in_partial_bus[(4*2048) + idx*32 +: 32];
                partial_5 = in_partial_bus[(5*2048) + idx*32 +: 32];

                sum_l1_0 = partial_0 + partial_1;
                sum_l1_1 = partial_2 + partial_3;
                sum_l1_2 = partial_4 + partial_5;
                total_sum = sum_l1_0 + sum_l1_1 + sum_l1_2;

                out_sum_bus[idx*32 +: 32] <= $signed(total_sum);
            end
        end
    end

endmodule
