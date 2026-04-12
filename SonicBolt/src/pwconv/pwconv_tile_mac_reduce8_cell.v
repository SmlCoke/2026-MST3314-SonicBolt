`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_reduce8_cell
 * 作者: SonicBolt 团队
 * 日期: 2026-04-12
 * 版本: v1.2
 *
 * 功能:
 *   对单个输出位置执行 8 路 INT18 部分和归约，输出 INT21。
 *
 * 运算复杂度分析: 
 *   - 三级加法树，8 x INT18 -> 1 x INT21
 *   - 逻辑深度为: 3A 
 */
module pwconv_tile_mac_reduce8_cell (
    input  wire signed [17:0] partial_0,
    input  wire signed [17:0] partial_1,
    input  wire signed [17:0] partial_2,
    input  wire signed [17:0] partial_3,
    input  wire signed [17:0] partial_4,
    input  wire signed [17:0] partial_5,
    input  wire signed [17:0] partial_6,
    input  wire signed [17:0] partial_7,
    output wire signed [20:0] accum_sum
);
    wire signed [18:0] sum_l1_0;
    wire signed [18:0] sum_l1_1;
    wire signed [18:0] sum_l1_2;
    wire signed [18:0] sum_l1_3;
    wire signed [19:0] sum_l2_0;
    wire signed [19:0] sum_l2_1;

    assign sum_l1_0 = {{1{partial_0[17]}}, partial_0} + {{1{partial_1[17]}}, partial_1};
    assign sum_l1_1 = {{1{partial_2[17]}}, partial_2} + {{1{partial_3[17]}}, partial_3};
    assign sum_l1_2 = {{1{partial_4[17]}}, partial_4} + {{1{partial_5[17]}}, partial_5};
    assign sum_l1_3 = {{1{partial_6[17]}}, partial_6} + {{1{partial_7[17]}}, partial_7};

    assign sum_l2_0 = {{1{sum_l1_0[18]}}, sum_l1_0} + {{1{sum_l1_1[18]}}, sum_l1_1};
    assign sum_l2_1 = {{1{sum_l1_2[18]}}, sum_l1_2} + {{1{sum_l1_3[18]}}, sum_l1_3};
    assign accum_sum = {{1{sum_l2_0[19]}}, sum_l2_0} + {{1{sum_l2_1[19]}}, sum_l2_1};
endmodule
