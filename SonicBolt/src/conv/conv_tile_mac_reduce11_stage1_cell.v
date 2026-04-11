`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_reduce11_stage1_cell
 * 作者: SonicBolt 团队
 * 日期: 2026-04-11
 * 版本: v1.0
 *
 * 功能:
 *   对单个输出位置的 11 路行和做第一阶段归约，输出 6 路部分和。
 *
 * 说明:
 *   该模块是组合逻辑，上层在 Stage1 对输出部分和统一打拍。
 */
module conv_tile_mac_reduce11_stage1_cell (
    input  wire signed [18:0] row_0,
    input  wire signed [18:0] row_1,
    input  wire signed [18:0] row_2,
    input  wire signed [18:0] row_3,
    input  wire signed [18:0] row_4,
    input  wire signed [18:0] row_5,
    input  wire signed [18:0] row_6,
    input  wire signed [18:0] row_7,
    input  wire signed [18:0] row_8,
    input  wire signed [18:0] row_9,
    input  wire signed [18:0] row_10,
    input  wire signed [15:0] bias_val,
    output wire signed [19:0] partial_0,
    output wire signed [19:0] partial_1,
    output wire signed [19:0] partial_2,
    output wire signed [19:0] partial_3,
    output wire signed [19:0] partial_4,
    output wire signed [19:0] partial_5
);
    assign partial_0 = row_0 + row_1;
    assign partial_1 = row_2 + row_3;
    assign partial_2 = row_4 + row_5;
    assign partial_3 = row_6 + row_7;
    assign partial_4 = row_8 + row_9;
    assign partial_5 = row_10 + bias_val;
endmodule
