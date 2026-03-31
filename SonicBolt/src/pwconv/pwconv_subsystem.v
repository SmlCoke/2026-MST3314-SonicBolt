`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 *
 * 功能概述:
 *   PWConv 独立子系统顶层。
 *
 * 设计定位:
 *   - 输入为 Activation2 之后的 DW 流输出
 *   - 输出为 Activation3 之后的 PW 流输出
 *   - 保持与 Conv1 顶层相近的 start / busy / done / out_stream_* 风格
 */
module pwconv_subsystem #(
    parameter integer M0      = 69,
    parameter integer SHIFT_N = 13
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output wire          busy,
    output wire          done,

    input  wire          in_stream_valid,
    output wire          in_stream_ready,
    input  wire [3:0]    in_stream_pos,
    input  wire [2:0]    in_stream_group,
    input  wire [127:0]  in_stream_data,

    input  wire          weight_wr_en,
    input  wire [2:0]    weight_wr_bank,
    input  wire [2:0]    weight_wr_addr,
    input  wire [127:0]  weight_wr_data,

    input  wire          bias_wr_en,
    input  wire          bias_wr_bank,
    input  wire [2:0]    bias_wr_addr,
    input  wire [63:0]   bias_wr_data,

    input  wire          out_stream_ready,
    output wire          out_stream_valid,
    output wire [3:0]    out_stream_pos,
    output wire [2:0]    out_stream_group,
    output wire [127:0]  out_stream_data
);

    wire [1023:0] even_pos_data;
    wire [1023:0] odd_pos_data;

    wire          weight_store_wr_en;
    wire          bias_store_wr_en;
    wire          capture_en;

    wire          weight_rd_en;
    wire [2:0]    weight_rd_group;
    wire          bias_rd_en;
    wire [2:0]    bias_rd_group;
    wire [8*128-1:0] weight_data_bus;
    wire [63:0]      bias_data_bus;

    assign weight_store_wr_en = weight_wr_en && !busy;
    assign bias_store_wr_en   = bias_wr_en && !busy;
    assign capture_en         = busy && in_stream_valid && in_stream_ready;

    pwconv_input_buffer u_pwconv_input_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .start_consume(start),
        .capture_en(capture_en),
        .in_pos(in_stream_pos),
        .in_group(in_stream_group),
        .in_data(in_stream_data),
        .even_pos_data(even_pos_data),
        .odd_pos_data(odd_pos_data)
    );

    pwconv_param_store u_pwconv_param_store (
        .clk(clk),
        .rst_n(rst_n),
        .weight_wr_en(weight_store_wr_en),
        .weight_wr_bank(weight_wr_bank),
        .weight_wr_addr(weight_wr_addr),
        .weight_wr_data(weight_wr_data),
        .bias_wr_en(bias_store_wr_en),
        .bias_wr_bank(bias_wr_bank),
        .bias_wr_addr(bias_wr_addr),
        .bias_wr_data(bias_wr_data),
        .weight_rd_en(weight_rd_en),
        .weight_rd_group(weight_rd_group),
        .bias_rd_en(bias_rd_en),
        .bias_rd_group(bias_rd_group),
        .weight_data_bus(weight_data_bus),
        .bias_data_bus(bias_data_bus)
    );

    pwconv_core #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_pwconv_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .in_stream_valid(in_stream_valid),
        .in_stream_ready(in_stream_ready),
        .in_stream_pos(in_stream_pos),
        .in_stream_group(in_stream_group),
        .even_pos_data(even_pos_data),
        .odd_pos_data(odd_pos_data),
        .weight_rd_en(weight_rd_en),
        .weight_rd_group(weight_rd_group),
        .bias_rd_en(bias_rd_en),
        .bias_rd_group(bias_rd_group),
        .weight_data_bus(weight_data_bus),
        .bias_data_bus(bias_data_bus),
        .out_stream_ready(out_stream_ready),
        .out_stream_valid(out_stream_valid),
        .out_stream_pos(out_stream_pos),
        .out_stream_group(out_stream_group),
        .out_stream_data(out_stream_data)
    );

endmodule
