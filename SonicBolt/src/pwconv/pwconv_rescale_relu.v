`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_rescale_relu
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 *
 * 功能概述:
 *   PWConv 后级量化 + ReLU 流水，处理 16 个 INT32 输出值
 *
 * 流水划分:
 *   - stage1: pwconv_rescale 完成乘 M0 和右移
 *   - stage2: pwconv_relu_saturate 完成 ReLU + INT8 饱和
 *
 * 元数据对齐:
 *   复用 conv_tile_mac_meta_pipe，把 valid / last / pos / group 与数据流水保持一致。
 */
module pwconv_rescale_relu #(
    parameter integer M0      = 69,
    parameter integer SHIFT_N = 13
) (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          in_valid,
    input  wire          in_last,
    input  wire [3:0]    in_pos,
    input  wire [2:0]    in_group,
    input  wire [511:0]  in_data_bus,

    output wire          out_valid,
    output wire          out_last,
    output wire [3:0]    out_pos,
    output wire [2:0]    out_group,
    output wire [127:0]  out_data_bus
);

    wire [511:0] stage1_rescale_bus;

    wire       stage1_valid;
    wire       stage1_last;
    wire [3:0] stage1_pos;
    wire [2:0] stage1_group;

    wire       stage2_valid;
    wire       stage2_last;
    wire [3:0] stage2_pos;
    wire [2:0] stage2_group;

    pwconv_rescale #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_pwconv_rescale (
        .clk(clk),
        .rst_n(rst_n),
        .in_data_bus(in_data_bus),
        .out_rescale_bus(stage1_rescale_bus)
    );

    conv_tile_mac_meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_last(in_last),
        .in_pos(in_pos),
        .in_group(in_group),
        .out_valid(stage1_valid),
        .out_last(stage1_last),
        .out_pos(stage1_pos),
        .out_group(stage1_group)
    );

    pwconv_relu_saturate u_pwconv_relu_saturate (
        .clk(clk),
        .rst_n(rst_n),
        .in_shift_bus(stage1_rescale_bus),
        .out_data_bus(out_data_bus)
    );

    conv_tile_mac_meta_pipe u_meta_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .out_valid(stage2_valid),
        .out_last(stage2_last),
        .out_pos(stage2_pos),
        .out_group(stage2_group)
    );

    assign out_valid = stage2_valid;
    assign out_last  = stage2_last;
    assign out_pos   = stage2_pos;
    assign out_group = stage2_group;

endmodule
