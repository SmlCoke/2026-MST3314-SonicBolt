`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_reduce11_stage2_cell
 * 功能:
 *   对单个输出位置的 6 路部分和做第二阶段归约，输出最终 INT32 累加值。
 *
 * 说明:
 *   该模块是组合逻辑，上层在 Stage2 对结果统一打拍。
 */
module conv_tile_mac_reduce11_stage2_cell (
    input  wire signed [19:0] partial_0,
    input  wire signed [19:0] partial_1,
    input  wire signed [19:0] partial_2,
    input  wire signed [19:0] partial_3,
    input  wire signed [19:0] partial_4,
    input  wire signed [19:0] partial_5,
    output wire signed [31:0] out_sum
);
    assign out_sum = partial_0 + partial_1 + partial_2 + partial_3 + partial_4 + partial_5;
endmodule
