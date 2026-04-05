`timescale 1ns / 1ps
/*
 * 模块名称: cnn
 * 作者: SonicBolt 团队
 * 日期: 2026-04-06
 * 版本: v1.2
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
 *   - v1.1 在 v1.0 基础上集成 PWConv，完成三个卷积层的串联
 *   - v1.2 成功集成所有子系统，CNN 全流程实现成功，并且通过测试！
 */

module cnn #(
    parameter integer CONV_M0        = 111,
    parameter integer CONV_SHIFT_N   = 14,
    parameter integer DWCONV_M0      = 59,
    parameter integer DWCONV_SHIFT_N = 11,
    parameter integer PWCONV_M0      = 69,
    parameter integer PWCONV_SHIFT_N = 13,
    parameter integer FC_M0          = 11,
    parameter integer FC_SHIFT_N     = 15
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output wire          busy,
    output wire          done,

    // ------------ 输入图像写控制信号 ------------
    input  wire          img_wr_en,            // 输入图像写使能
    input  wire [4:0]    img_wr_addr,          // 输入图像行地址，30 行因此使用 5bit
    input  wire [79:0]   img_wr_row_data,      // 输入图像写数据，一行 10 个像素，10 x 8bit = 80bit

    // ------------ Conv 权重 SRAM 写控制信号 ------------
    input  wire          conv_weight_wr_en,    // Conv 权重写使能
    input  wire [4:0]    conv_weight_wr_bank,  // Conv 权重 bank 编号
    input  wire [2:0]    conv_weight_wr_addr,  // Conv 权重 group 地址
    input  wire [223:0]  conv_weight_wr_data,  // Conv 权重写数据

    // ------------ DWConv 权重 SRAM 写控制信号 ------------
    input  wire          dwconv_weight_wr_en,   // DWConv 权重写使能
    input  wire [1:0]    dwconv_weight_wr_bank, // DWConv 权重 bank 编号
    input  wire [2:0]    dwconv_weight_wr_addr, // DWConv 权重 group 地址
    input  wire [95:0]   dwconv_weight_wr_data, // DWConv 权重写数据

    // ------------ PWConv 权重 SRAM 写控制信号 ------------
    input  wire          pwconv_weight_wr_en,   // PWConv 权重写使能
    input  wire [2:0]    pwconv_weight_wr_bank, // PWConv 权重 bank 编号
    input  wire [2:0]    pwconv_weight_wr_addr, // PWConv 权重 group 地址
    input  wire [127:0]  pwconv_weight_wr_data, // PWConv 权重写数据

    // ------------ Conv 偏置 SRAM 写控制信号 ------------
    input  wire          conv_bias_wr_en,      // Conv 偏置写使能
    input  wire          conv_bias_wr_bank,    // Conv 偏置 bank 编号
    input  wire [2:0]    conv_bias_wr_addr,    // Conv 偏置 group 地址
    input  wire [63:0]   conv_bias_wr_data,    // Conv 偏置写数据

    // ------------ DWConv 偏置 SRAM 写控制信号 ------------
    input  wire          dwconv_bias_wr_en,    // DWConv 偏置写使能
    input  wire          dwconv_bias_wr_bank,  // DWConv 偏置 bank 编号
    input  wire [2:0]    dwconv_bias_wr_addr,  // DWConv 偏置 group 地址
    input  wire [63:0]   dwconv_bias_wr_data,  // DWConv 偏置写数据

    // ------------ PWConv 偏置 SRAM 写控制信号 ------------
    input  wire          pwconv_bias_wr_en,    // PWConv 偏置写使能
    input  wire          pwconv_bias_wr_bank,  // PWConv 偏置 bank 编号
    input  wire [2:0]    pwconv_bias_wr_addr,  // PWConv 偏置 group 地址
    input  wire [63:0]   pwconv_bias_wr_data,  // PWConv 偏置写数据

    // ------------ FC / Sigmoid 参数写控制信号 ------------
    input  wire          fc_weight_wr_en,      // FC 权重写使能
    input  wire [6:0]    fc_weight_wr_addr,    // FC 权重地址
    input  wire [63:0]   fc_weight_wr_data,    // FC 权重写数据
    input  wire          fc_bias_wr_en,        // FC 偏置写使能
    input  wire [31:0]   fc_bias_wr_data,      // FC 偏置写数据
    input  wire          sigmoid_lut_wr_en,    // Sigmoid LUT 写使能
    input  wire [7:0]    sigmoid_lut_wr_addr,  // Sigmoid LUT 地址
    input  wire [31:0]   sigmoid_lut_wr_data,  // Sigmoid LUT 写数据

    // ------------ 输出数据流接口（当前兼容旧 testbench 端口形状） ------------
    output wire          out_stream_valid, // 输出 tile 有效
    output wire          out_stream_fire,  // 输出的下一层启动信号
    output wire          out_stream_last,  // 输出 tile 是否为最后一个
    output wire [3:0]    out_stream_pos,   // 输出 tile 的 pos 编号
    output wire [2:0]    out_stream_group, // 输出 tile 的 group 编号
    output wire [127:0]  out_stream_data   // 输出 tile 数据
);

    // 三个卷积层与后处理层状态信号
    wire         conv_busy;
    wire         conv_done;
    wire         dwconv_busy;
    wire         dwconv_done;
    wire         pwconv_busy;
    wire         pwconv_done;
    wire         post_process_busy;
    wire         post_process_done;

    // Conv 子系统输出数据流
    wire         conv_out_stream_valid;
    wire         conv_out_stream_fire;
    wire         conv_out_stream_last;
    wire [3:0]   conv_out_stream_pos;
    wire [2:0]   conv_out_stream_group;
    wire [511:0] conv_out_stream_data;

    // DWConv 子系统输出数据流
    wire         dwconv_out_stream_valid;
    wire         dwconv_out_stream_fire;
    wire         dwconv_out_stream_last;
    wire [3:0]   dwconv_out_stream_pos;
    wire [2:0]   dwconv_out_stream_group;
    wire [127:0] dwconv_out_stream_data;

    // PWConv 子系统输出数据流
    wire         pwconv_out_stream_valid;
    wire         pwconv_out_stream_fire;
    wire         pwconv_out_stream_last;
    wire [3:0]   pwconv_out_stream_pos;
    wire [2:0]   pwconv_out_stream_group;
    wire [127:0] pwconv_out_stream_data;

    // Post-Process 子系统输出数据流
    wire         post_process_out_stream_valid;
    wire [63:0]  post_process_out_stream_data;

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
        .out_stream_valid(dwconv_out_stream_valid),
        .out_stream_fire(dwconv_out_stream_fire),
        .out_stream_last(dwconv_out_stream_last),
        .out_stream_pos(dwconv_out_stream_pos),
        .out_stream_group(dwconv_out_stream_group),
        .out_stream_data(dwconv_out_stream_data)
    );

    pwconv_subsystem #(
        .M0(PWCONV_M0),
        .SHIFT_N(PWCONV_SHIFT_N)
    ) pwconv_inst (
        .clk(clk),
        .rst_n(rst_n),
        .busy(pwconv_busy),
        .done(pwconv_done),

        // ---------- PWConv 输入数据流接口 ----------
        .in_stream_valid(dwconv_out_stream_valid),
        .in_stream_fire(dwconv_out_stream_fire),
        .in_stream_last(dwconv_out_stream_last),
        .in_stream_pos(dwconv_out_stream_pos),
        .in_stream_group(dwconv_out_stream_group),
        .in_stream_data(dwconv_out_stream_data),

        // ------------ PWConv 权重 SRAM 写控制信号 ------------
        .weight_wr_en(pwconv_weight_wr_en),
        .weight_wr_bank(pwconv_weight_wr_bank),
        .weight_wr_addr(pwconv_weight_wr_addr),
        .weight_wr_data(pwconv_weight_wr_data),

        // ------------ PWConv 偏置 SRAM 写控制信号 ------------
        .bias_wr_en(pwconv_bias_wr_en),
        .bias_wr_bank(pwconv_bias_wr_bank),
        .bias_wr_addr(pwconv_bias_wr_addr),
        .bias_wr_data(pwconv_bias_wr_data),

        // ---------- PWConv 输出数据流接口 ----------
        .out_stream_valid(pwconv_out_stream_valid),
        .out_stream_fire(pwconv_out_stream_fire),
        .out_stream_last(pwconv_out_stream_last),
        .out_stream_pos(pwconv_out_stream_pos),
        .out_stream_group(pwconv_out_stream_group),
        .out_stream_data(pwconv_out_stream_data)
    );

    post_process_subsystem #(
        .FC_M0(FC_M0),
        .FC_SHIFT_N(FC_SHIFT_N)
    ) post_process_inst (
        .clk(clk),
        .rst_n(rst_n),
        .busy(post_process_busy),
        .done(post_process_done),

        // ---------- Post-Process 输入数据流接口 ----------
        .in_stream_valid(pwconv_out_stream_valid),
        .in_stream_last(pwconv_out_stream_last),
        .in_stream_pos(pwconv_out_stream_pos),
        .in_stream_group(pwconv_out_stream_group),
        .in_stream_fire(pwconv_out_stream_fire),
        .in_stream_data(pwconv_out_stream_data),

        // ---------- FC / Sigmoid 参数写接口 ----------
        .fc_weight_wr_en(fc_weight_wr_en),
        .fc_weight_wr_addr(fc_weight_wr_addr),
        .fc_weight_wr_data(fc_weight_wr_data),
        .fc_bias_wr_en(fc_bias_wr_en),
        .fc_bias_wr_data(fc_bias_wr_data),
        .sigmoid_lut_wr_en(sigmoid_lut_wr_en),
        .sigmoid_lut_wr_addr(sigmoid_lut_wr_addr),
        .sigmoid_lut_wr_data(sigmoid_lut_wr_data),

        // ---------- Post-Process 输出数据流接口 ----------
        .out_stream_valid(post_process_out_stream_valid),
        .out_stream_data(post_process_out_stream_data)
    );

    // 输出数据流接口兼容旧 testbench 端口形状：
    // - 后处理真实输出只保留 valid + 64bit 数据
    // - 这里将结果放在 out_stream_data 低 64bit，其他 metadata 置 0
    assign out_stream_valid = post_process_out_stream_valid;
    assign out_stream_fire  = 1'b0;
    assign out_stream_last  = 1'b0;
    assign out_stream_pos   = 4'd0;
    assign out_stream_group = 3'd0;
    assign out_stream_data  = {64'd0, post_process_out_stream_data};

    // 顶层完成信号以后处理子系统为准；busy 则反映 4 个子系统任一仍在工作。
    assign busy = conv_busy || dwconv_busy || pwconv_busy || post_process_busy;
    assign done = post_process_done;

endmodule
