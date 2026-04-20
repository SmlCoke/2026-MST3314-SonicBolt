`timescale 1ns / 1ps
/*
 * 模块名称: cnn
 * 作者: SonicBolt 团队
 * 日期: 2026-04-13
 * 版本: v1.9
 *
 * 功能概述:
 *   SonicBolt 顶层 CNN 管线，依次串接:
 *     Conv -> DWConv -> PWConv -> Post-Process(Maxpool + FC + Sigmoid)
 *
 * 版本定位:
 *   - v1.0 先实现 Conv-DWConv 级联
 *   - v1.1 在 v1.0 基础上集成 PWConv，完成三个卷积层的串联
 *   - v1.2 成功集成所有子系统，CNN 全流程实现成功，并且通过测试！
 *   - v1.3 接入 Conv 输入双帧 Ping-Pong 缓存握手。外部通过 `img_wr_commit` 提交一整帧输入，通过 
 *      `img_wr_ready` 判断何时可以继续写下一帧。为避免下一帧在级联传播过程中把 DWConv / PWConv 的首个 
 *      `fire` 冲丢，顶层使用 `run_enable` / `relaunch_pending` 只在 Conv、DWConv 可接新帧且 PWConv 已
 *       进入安全尾段时重新拉起下一帧。
 *   - v1.4 将 Conv 输出修改为半窗缓存，砍掉一半乘法器（2464个INT8）和一半加法树（32组四级加法树），同时元数据
 *     语义只在 Conv 层之间发生变动，通过还原机制使得 DWConv 层及之后元数据语义维持不变。
 *   - v1.5 删除 pwconv 引入的 launch_safe 信号，改为在顶层 conv_guard_done 保护窗结束时允许下一帧启动。根
 *      据经验回归结果，conv_guard_done 保护窗设置为 7 个周期，可以稳定通过多样本连续仿真测试，并且最大程度压
 *      缩帧间隔以提升吞吐。
 *   - v1.6 PWConv 参数链路改为 ROM 只读，删除 PWConv 顶层写口与写连线。
 *   - v1.7 FC 参数链路改为 ROM 只读；顶层 FC 写口暂保留兼容，但不再下发到后处理子系统。
 *   - v1.8 彻底删除顶层 FC 写口，形成全链路 FC 只读参数形态。
 *   - v1.9 彻底删除顶层 Sigmoid LUT 写口，形成后处理全链路只读参数形态。
 *     

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

    // ------------ 输出数据流接口 ------------
    output wire          out_stream_valid, // 输出数据有效
    output wire [63:0]   out_stream_data   // 输出 2 x FP32
);

    // 三个卷积层与后处理层状态信号
    wire         conv_busy;
    wire         conv_done;
    wire         conv_issue_done;
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
    wire         conv_start_req;            // 当前允许 Conv 拉起下一帧

    wire         conv_guard_done;           // Conv issue_done 之后的保护窗是否已结束
    reg          run_enable;                // start 后进入连续推理模式
    reg          relaunch_pending;          // 当前已有待发车帧，等待 Conv 前端准备好
    reg  [3:0]   conv_relaunch_guard;       // issue_done 之后的固定保护窗计数器

    // 经验回归结果：
    // - 保护窗 = 6 时，多样本连续仿真会串帧
    // - 保护窗 = 7 时，`run_cnn_test_tb.py` / `run_cnn_sim_tb.py` 均稳定通过
    // 因此这里取当前验证到的最小稳定值 7 ，把启动间隔压到 89 个周期。
    localparam integer CONV_RELAUNCH_GUARD = 7;

    // 当前版本将“Conv 最后一个输出流出”和“Conv 前端 80 个 token 发完”拆开：
    // - Conv 前端 issue 侧空闲，说明输入缓存 / 参数读口已经可以接下一帧
    // - 再额外保留一小段固定保护窗，让下一帧首个 fire 到达 PWConv / Post-Process 时，
    //   上一帧已经越过单帧语义的危险边界。
    assign conv_guard_done   = (conv_relaunch_guard == 4'd0);
    assign conv_start_req = !conv_busy && conv_guard_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_enable       <= 1'b0;
            relaunch_pending <= 1'b0;
            conv_relaunch_guard <= 4'd0;
        end else begin
            if (conv_issue_done) begin
                // issue 侧虽然已经空出来了，但下一帧过早启动会让更深层的单帧模块串帧。
                // 因此这里在 issue_done 之后保留一个小保护窗，再允许真正 launch。
                conv_relaunch_guard <= CONV_RELAUNCH_GUARD[3:0];
            end else if (conv_relaunch_guard != 4'd0) begin
                conv_relaunch_guard <= conv_relaunch_guard - 4'd1;
            end

            // 第一次 start 用来进入连续运行模式；
            // 之后每次 Conv 前端 80 个 token 发完，就自动申请拉起下一帧。
            if (start) begin
                run_enable       <= 1'b1;
                relaunch_pending <= 1'b1;
            end else if (run_enable && conv_issue_done) begin
                // 每当 Conv 前端发完当前帧的 80 个 token，就申请拉起下一帧(pending = 1)。真正的拉起时机由 conv_start_req 决定，以确保不会串帧。
                relaunch_pending <= 1'b1;
            end else if (conv_busy) begin
                // Conv 一旦真正进入 busy，说明当前待发车帧已经被接收，清掉 pending。
                relaunch_pending <= 1'b0;
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
        .issue_done(conv_issue_done),

        // ---------- 输入数据流接口 ----------
        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_row_data(img_wr_row_data),
        .img_wr_commit(img_wr_commit),
        .img_wr_ready(img_wr_ready),

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
