`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_dot7_cell
 * 功能:
 *   计算一个 7 项 INT8xINT8 点积，对应一个 (ch, oy, ox) 位置的行内卷积和。
 *
 * 说明:
 *   该模块仅做组合计算，不含时序寄存器。
 *   上层模块负责对输入/输出打拍，以保持原有流水级数。
 */
module conv_tile_mac_dot7_cell (
    input  wire signed [7:0] data_0,
    input  wire signed [7:0] data_1,
    input  wire signed [7:0] data_2,
    input  wire signed [7:0] data_3,
    input  wire signed [7:0] data_4,
    input  wire signed [7:0] data_5,
    input  wire signed [7:0] data_6,
    input  wire signed [7:0] wt_0,
    input  wire signed [7:0] wt_1,
    input  wire signed [7:0] wt_2,
    input  wire signed [7:0] wt_3,
    input  wire signed [7:0] wt_4,
    input  wire signed [7:0] wt_5,
    input  wire signed [7:0] wt_6,
    output wire signed [18:0] out_sum
);
    wire signed [15:0] p_0;
    wire signed [15:0] p_1;
    wire signed [15:0] p_2;
    wire signed [15:0] p_3;
    wire signed [15:0] p_4;
    wire signed [15:0] p_5;
    wire signed [15:0] p_6;
    wire signed [16:0] s_l1_0;
    wire signed [16:0] s_l1_1;
    wire signed [16:0] s_l1_2;
    wire signed [17:0] s_l2_0;
    wire signed [17:0] s_l2_1;

    assign p_0 = data_0 * wt_0;
    assign p_1 = data_1 * wt_1;
    assign p_2 = data_2 * wt_2;
    assign p_3 = data_3 * wt_3;
    assign p_4 = data_4 * wt_4;
    assign p_5 = data_5 * wt_5;
    assign p_6 = data_6 * wt_6;

    assign s_l1_0 = p_0 + p_1;
    assign s_l1_1 = p_2 + p_3;
    assign s_l1_2 = p_4 + p_5;

    assign s_l2_0 = s_l1_0 + s_l1_1;
    assign s_l2_1 = s_l1_2 + p_6;
    assign out_sum = s_l2_0 + s_l2_1;
endmodule
