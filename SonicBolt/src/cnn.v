`timescale 1ns / 1ps
/*
 * 模块名称: cnn
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述: SonicBolt 顶层电路
 *
 * 主数据流:
 *   输入图像
 *   -> conv_subsystem
 *   -> dwconv_subsystem
 *   -> pwconv_subsystem
 *   -> maxpool
 *   -> FC
 *   -> sigmoid
 *   -> 输出结果
 *
 * 版本定位:
 *   - v1.0 先实现 Conv-DWConv 级联
 */

module cnn #(
    parameter integer CONV_M0        = 111,
    parameter integer CONV_SHIFT_N   = 14,
    parameter integer DWCONV_M0      = 59,
    parameter integer DWCONV_SHIFT_N = 11
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output wire          busy,
    output wire          done,

    // ------------ 输入图像写控制信号 ------------
    input  wire          img_wr_en,        // 输入图像写使能
    input  wire [4:0]    img_wr_addr,      // 输入图像行地址，30 行因此使用 5bit
    input  wire [79:0]   img_wr_row_data,  // 输入图像写数据，一行 10 个像素，10 x 8bit = 80bit

    // ------------ Conv 权重 SRAM 写控制信号 ------------
    input  wire          conv_weight_wr_en,     // Conv 权重写使能
    input  wire [4:0]    conv_weight_wr_bank,   // Conv 权重 bank 编号
    input  wire [2:0]    conv_weight_wr_addr,   // Conv 权重 group 地址
    input  wire [223:0]  conv_weight_wr_data,   // Conv 权重写数据

    // ------------ DWConv 权重 SRAM 写控制信号 ------------
    input  wire          dwconv_weight_wr_en,   // DWConv 权重写使能
    input  wire [1:0]    dwconv_weight_wr_bank, // DWConv 权重 bank 编号
    input  wire [2:0]    dwconv_weight_wr_addr, // DWConv 权重 group 地址
    input  wire [95:0]   dwconv_weight_wr_data, // DWConv 权重写数据

    // ------------ Conv 偏置 SRAM 写控制信号 ------------
    input  wire          conv_bias_wr_en,       // Conv 偏置写使能
    input  wire          conv_bias_wr_bank,     // Conv 偏置 bank 编号
    input  wire [2:0]    conv_bias_wr_addr,     // Conv 偏置 group 地址
    input  wire [63:0]   conv_bias_wr_data,     // Conv 偏置写数据

    // ------------ DWConv 偏置 SRAM 写控制信号 ------------
    input  wire          dwconv_bias_wr_en,     // DWConv 偏置写使能
    input  wire          dwconv_bias_wr_bank,   // DWConv 偏置 bank 编号
    input  wire [2:0]    dwconv_bias_wr_addr,   // DWConv 偏置 group 地址
    input  wire [63:0]   dwconv_bias_wr_data,   // DWConv 偏置写数据

    // ------------ 输出数据流接口（当前为 DWConv 输出）------------
    output wire          out_stream_valid, // 输出 tile 有效
    output wire          out_stream_fire,  // 输出的下一层启动信号
    output wire          out_stream_last,  // 输出 tile 是否为最后一个
    output wire [3:0]    out_stream_pos,   // 输出 tile 的 pos 编号
    output wire [2:0]    out_stream_group, // 输出 tile 的 group 编号
    output wire [127:0]  out_stream_data   // 输出 tile 数据
);

    wire         conv_busy;
    wire         conv_done;
    wire         dwconv_busy;
    wire         dwconv_done;

    wire         conv_out_stream_valid;
    wire         conv_out_stream_fire;
    wire         conv_out_stream_last;
    wire [3:0]   conv_out_stream_pos;
    wire [2:0]   conv_out_stream_group;
    wire [511:0] conv_out_stream_data;

    conv_subsystem #(
        .M0(CONV_M0),
        .SHIFT_N(CONV_SHIFT_N)
    ) conv_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(conv_busy),
        .done(conv_done),

        // ---------- 输入数据流接口 ----------
        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_row_data(img_wr_row_data),

        // ------------ Conv 权重 SRAM 写控制信号 ------------
        .weight_wr_en(conv_weight_wr_en),
        .weight_wr_bank(conv_weight_wr_bank),
        .weight_wr_addr(conv_weight_wr_addr),
        .weight_wr_data(conv_weight_wr_data),

        // ------------ Conv 偏置 SRAM 写控制信号 ------------
        .bias_wr_en(conv_bias_wr_en),
        .bias_wr_bank(conv_bias_wr_bank),
        .bias_wr_addr(conv_bias_wr_addr),
        .bias_wr_data(conv_bias_wr_data),

        // ---------- Conv 输出数据流接口 ----------
        .out_stream_valid(conv_out_stream_valid),
        .out_stream_fire(conv_out_stream_fire),
        .out_stream_last(conv_out_stream_last),
        .out_stream_pos(conv_out_stream_pos),
        .out_stream_group(conv_out_stream_group),
        .out_stream_data(conv_out_stream_data)
    );

    dwconv_subsystem #(
        .M0(DWCONV_M0),
        .SHIFT_N(DWCONV_SHIFT_N)
    ) dwconv_inst (
        .clk(clk),
        .rst_n(rst_n),
        .busy(dwconv_busy),
        .done(dwconv_done),

        // ---------- DWConv 输入数据流接口 ----------
        .in_stream_valid(conv_out_stream_valid),
        .in_stream_fire(conv_out_stream_fire),
        .in_stream_last(conv_out_stream_last),
        .in_stream_pos(conv_out_stream_pos),
        .in_stream_group(conv_out_stream_group),
        .in_stream_data(conv_out_stream_data),

        // ------------ DWConv 权重 SRAM 写控制信号 ------------
        .weight_wr_en(dwconv_weight_wr_en),
        .weight_wr_bank(dwconv_weight_wr_bank),
        .weight_wr_addr(dwconv_weight_wr_addr),
        .weight_wr_data(dwconv_weight_wr_data),

        // ------------ DWConv 偏置 SRAM 写控制信号 ------------
        .bias_wr_en(dwconv_bias_wr_en),
        .bias_wr_bank(dwconv_bias_wr_bank),
        .bias_wr_addr(dwconv_bias_wr_addr),
        .bias_wr_data(dwconv_bias_wr_data),

        // ---------- DWConv 输出数据流接口 ----------
        .out_stream_valid(out_stream_valid),
        .out_stream_fire(out_stream_fire),
        .out_stream_last(out_stream_last),
        .out_stream_pos(out_stream_pos),
        .out_stream_group(out_stream_group),
        .out_stream_data(out_stream_data)
    );

    // 顶层当前只集成到 DWConv，因此完成信号以 DWConv 为准；
    // busy 则反映 Conv 或 DWConv 任一子系统仍在工作。
    assign busy = conv_busy || dwconv_busy;
    assign done = dwconv_done;

endmodule
