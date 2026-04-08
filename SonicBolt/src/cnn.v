`timescale 1ns / 1ps
/*
 * 模块名称: cnn
 * 作者: SonicBolt 团队
 * 日期: 2026-04-08
 * 版本: v1.3
 *
 * 功能概述:
 *   SonicBolt 顶层 CNN 管线，依次串接:
 *     Conv -> DWConv -> PWConv -> Post-Process(Maxpool + FC + Sigmoid)
 *
 * 当前版本说明:
 *   - 顶层已经接入 Conv 输入双帧 Ping-Pong 缓存握手。
 *   - 外部通过 `img_wr_commit` 提交一整帧输入，通过 `img_wr_ready` 判断何时可以继续写下一帧。
 *   - 为避免下一帧在级联传播过程中把 DWConv / PWConv 的首个 `fire` 冲丢，
 *     顶层使用 `run_enable` / `relaunch_pending` 只在 Conv、DWConv 与 PWConv 都可接受新帧时重新拉起下一帧。
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
    input  wire          clk,               // 时钟
    input  wire          rst_n,             // 低有效复位
    input  wire          start,             // 开始进入连续推理模式
    output wire          busy,              // CNN 任一子模块正在工作
    output wire          done,              // 当前帧完成脉冲，由后处理输出

    // ------------ 输入图像写控制信号 ------------
    input  wire          img_wr_en,         // 输入图像写使能
    input  wire [4:0]    img_wr_addr,       // 输入图像行地址，30 行因此使用 5bit
    input  wire [79:0]   img_wr_row_data,   // 输入图像写数据，一行 10 个像素，10 x 8bit = 80bit
    input  wire          img_wr_commit,     // 当前帧完整写入结束
    output wire          img_wr_ready,      // 当前允许写下一帧

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

    // ------------ 输出数据流接口 ------------
    output wire          out_stream_valid, // 输出数据有效
    output wire [63:0]   out_stream_data   // 输出 2 x FP32
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
    wire         conv_start_req;            // 真正送给 Conv 的启动脉冲
    wire         conv_launch_ready;         // 当前允许 Conv 拉起下一帧

    reg          run_enable;                // start 后进入连续推理模式
    reg          relaunch_pending;          // 当前已有待发车帧，等待 Conv / DWConv / PWConv 都准备好

    // 只要 Conv 本身空闲，且 DWConv / PWConv 都已经能安全接收本帧后续传播出来的 fire，
    // 就允许把待发车帧正式送入 Conv；这样比等待整条 CNN 空闲更早。
    assign conv_launch_ready = !conv_busy && !dwconv_busy && !pwconv_busy;
    assign conv_start_req    = relaunch_pending && conv_launch_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_enable       <= 1'b0;
            relaunch_pending <= 1'b0;
        end else begin
            // Conv 一旦真正进入 busy，说明当前待发车帧已经被接收，清掉 pending。
            if (conv_busy) begin
                relaunch_pending <= 1'b0;
            end

            // 第一次 start 用来进入连续运行模式；
            // 之后每次整帧 conv_done，都自动申请拉起下一帧。
            if (start) begin
                run_enable       <= 1'b1;
                relaunch_pending <= 1'b1;
            end else if (run_enable && conv_done) begin
                relaunch_pending <= 1'b1;
            end
        end
    end

    // Conv 子系统：
    // - 接收输入双帧缓存写入
    // - 只有在 ready bank 存在且顶层允许时才真正启动
    conv_subsystem #(
        .M0(CONV_M0),
        .SHIFT_N(CONV_SHIFT_N)
    ) conv_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(conv_start_req),
        .busy(conv_busy),
        .done(conv_done),

        // ---------- 输入数据流接口 ----------
        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_row_data(img_wr_row_data),
        .img_wr_commit(img_wr_commit),
        .img_wr_ready(img_wr_ready),

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

    // DWConv 子系统：直接消费 Conv 的 token 流。
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
        .in_stream_last(conv_out_stream_last),
        .in_stream_pos(conv_out_stream_pos),
        .in_stream_group(conv_out_stream_group),
        .in_stream_fire(conv_out_stream_fire),
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

    // PWConv 子系统：直接消费 DWConv 的 token 流。
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

    // 后处理子系统：Maxpool + FC + Sigmoid。
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
    assign out_stream_data  = post_process_out_stream_data;

    // 顶层 busy 只要任一子系统在工作就保持为高；
    // done 则以后处理完成为准，表示整帧真正走完整条 CNN。
    assign busy = conv_busy || dwconv_busy || pwconv_busy || post_process_busy;
    assign done = post_process_done;

endmodule
