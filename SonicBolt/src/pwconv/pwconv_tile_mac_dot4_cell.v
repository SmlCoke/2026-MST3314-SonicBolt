`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_dot4_cell
 * 功能:
 *   对单个输出位置执行 4 路 INT8xINT8 点积，输出 INT18 部分和。
 */
module pwconv_tile_mac_dot4_cell (
    input  wire signed [7:0] act_0,
    input  wire signed [7:0] act_1,
    input  wire signed [7:0] act_2,
    input  wire signed [7:0] act_3,
    input  wire signed [7:0] wt_0,
    input  wire signed [7:0] wt_1,
    input  wire signed [7:0] wt_2,
    input  wire signed [7:0] wt_3,
    output wire signed [17:0] partial_sum
);
    wire signed [15:0] product_0;
    wire signed [15:0] product_1;
    wire signed [15:0] product_2;
    wire signed [15:0] product_3;
    wire signed [16:0] sum_l1_0;
    wire signed [16:0] sum_l1_1;

    assign product_0 = act_0 * wt_0;
    assign product_1 = act_1 * wt_1;
    assign product_2 = act_2 * wt_2;
    assign product_3 = act_3 * wt_3;

    assign sum_l1_0 = {{1{product_0[15]}}, product_0} + {{1{product_1[15]}}, product_1};
    assign sum_l1_1 = {{1{product_2[15]}}, product_2} + {{1{product_3[15]}}, product_3};
    assign partial_sum = {{1{sum_l1_0[16]}}, sum_l1_0} + {{1{sum_l1_1[16]}}, sum_l1_1};
endmodule
