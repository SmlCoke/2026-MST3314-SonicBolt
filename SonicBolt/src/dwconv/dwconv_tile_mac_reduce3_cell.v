`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_tile_mac_reduce3_cell
 * 功能:
 *   对单个输出位置执行 3 路行和 + 偏置 的归约，输出 INT32。
 */
module dwconv_tile_mac_reduce3_cell (
    input  wire signed [17:0] row_0,
    input  wire signed [17:0] row_1,
    input  wire signed [17:0] row_2,
    input  wire signed [15:0] bias_val,
    output wire signed [31:0] out_sum
);
    wire signed [18:0] partial_0;
    wire signed [18:0] partial_1;

    assign partial_0 = row_0 + row_1;
    assign partial_1 = row_2 + bias_val;
    assign out_sum = partial_0 + partial_1;
endmodule
