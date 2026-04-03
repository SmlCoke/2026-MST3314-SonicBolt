`timescale 1ns / 1ps
/*
 * 模块名称: post_process_fc
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 执行全连接层 FC(2,288)：INT8 输入向量 -> 2 路 INT32 累加
 *   - 执行偏置叠加后重量化（M0=11, SHIFT_N=15）并饱和到 INT8
 *   - 输出 2 路 INT8，供 Sigmoid 层查表
 *
 * 设计说明:
 *   - 输入 token 为 4 路 INT8，配合 metadata 的 pos/group 还原 flatten 索引
 *   - flatten 索引定义：idx = ch * 9 + pos，ch = group * 4 + lane
 *   - 权重改为 72x64 单端口 SRAM：addr = pos * 8 + group，每个 word 打包 8 个 INT8：低 32bit 为 class0 四路，高 32bit 为 class1 四路
 *   - 内部按功能拆分为多个 fc_* 子模块，顶层负责阶段编排与 metadata 对齐
 */
module post_process_fc #(
    parameter integer M0      = 11,
    parameter integer SHIFT_N = 15
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---------- 输入 metadata ----------
    input  wire        in_valid,
    input  wire        in_last,
    input  wire [3:0]  in_pos,
    input  wire [2:0]  in_group,
    input  wire        in_fire,

    // ---------- 输入数据 ----------
    input  wire [31:0] in_data_bus,// 4(ch) x INT8 = 32bit

    // ---------- FC 参数写接口 ----------
    input  wire        weight_wr_en,
    input  wire [6:0]  weight_wr_addr,
    input  wire [63:0] weight_wr_data,

    input  wire        bias_wr_en,
    //input  wire        bias_wr_cls,
    input  wire [15:0] bias_wr_data,

    // ---------- 输出 metadata ----------
    output wire        out_valid,
    output wire        out_last,
    output wire [3:0]  out_pos,
    output wire [2:0]  out_group,
    output wire        out_fire,

    // ---------- 输出数据 ----------
    output wire [15:0] out_data_bus
);

    localparam integer WEIGHT_DEPTH = 72;

    wire signed [15:0] bias_cls0;
    wire signed [15:0] bias_cls1;

    wire [63:0] weight_sram_rdata;

    wire        req_valid;
    wire        req_last;
    wire [31:0] req_data_bus;

    wire signed [31:0] req_delta_cls0;
    wire signed [31:0] req_delta_cls1;

    wire               frame_emit_valid;
    wire               frame_emit_last;
    wire signed [31:0] frame_sum_cls0;
    wire signed [31:0] frame_sum_cls1;

    wire signed [31:0] frame_bias_sum_cls0;
    wire signed [31:0] frame_bias_sum_cls1;

    wire        stage0_valid;
    wire        stage0_last;
    wire [3:0]  stage0_pos;
    wire [2:0]  stage0_group;
    wire        stage0_fire;
    wire [63:0] stage0_data_bus;

    wire        stage1_valid;
    wire        stage1_last;
    wire [3:0]  stage1_pos;
    wire [2:0]  stage1_group;
    wire        stage1_fire;

    wire [63:0] stage1_rescale_bus;

    wire [15:0] stage2_data_bus_next;

    // 权重 SRAM 读写接口且写优先
    post_process_fc_weight_sram_if #(
        .WEIGHT_DEPTH(WEIGHT_DEPTH)
    ) u_post_process_fc_weight_sram_if (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_pos(in_pos),
        .in_group(in_group),
        .weight_wr_en(weight_wr_en),
        .weight_wr_addr(weight_wr_addr),
        .weight_wr_data(weight_wr_data),
        .out_weight_rdata(weight_sram_rdata)
    );

    // bias 写入与存储
    post_process_fc_bias_store u_post_process_fc_bias_store (
        .clk(clk),
        .rst_n(rst_n),
        .bias_wr_en(bias_wr_en),
        .bias_wr_data(bias_wr_data),
        .out_bias_cls0(bias_cls0),
        .out_bias_cls1(bias_cls1)
    );

    //专有 meta_pip，看到条件是 in_valid 且 非 weight_wr_en 才放行
    //它还负责数据寄存与无效周期清零
    post_process_fc_req_pipe u_post_process_fc_req_pipe (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_last(in_last),
        .in_data_bus(in_data_bus),
        .weight_wr_en(weight_wr_en),
        .out_valid(req_valid),
        .out_last(req_last),
        .out_data_bus(req_data_bus)
    );

    // token 级 4-lane MAC 增量
    post_process_fc_lane_mac u_post_process_fc_lane_mac (
        .in_data_bus(req_data_bus),
        .in_weight_bus(weight_sram_rdata),
        .out_delta_cls0(req_delta_cls0),
        .out_delta_cls1(req_delta_cls1)
    );

    // 帧级累加
    post_process_fc_frame_accum u_post_process_fc_frame_accum (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(req_valid),
        .in_last(req_last),
        .in_delta_cls0(req_delta_cls0),
        .in_delta_cls1(req_delta_cls1),
        .out_emit_valid(frame_emit_valid),
        .out_emit_last(frame_emit_last),
        .out_sum_cls0(frame_sum_cls0),
        .out_sum_cls1(frame_sum_cls1)
    );

    // 偏置叠加
    post_process_fc_bias_add u_post_process_fc_bias_add (
        .in_sum_cls0(frame_sum_cls0),
        .in_sum_cls1(frame_sum_cls1),
        .in_bias_cls0(bias_cls0),
        .in_bias_cls1(bias_cls1),
        .out_sum_cls0(frame_bias_sum_cls0),
        .out_sum_cls1(frame_bias_sum_cls1)
    );

    // Stage0 bypass: 直接使用帧末结果
    assign stage0_valid    = frame_emit_valid;
    assign stage0_last     = frame_emit_last;
    assign stage0_pos      = 4'd0;
    assign stage0_group    = 3'd0;
    assign stage0_fire     = frame_emit_last;
    assign stage0_data_bus = {frame_bias_sum_cls1, frame_bias_sum_cls0};

    // Stage1: FC 专用 rescale（两路 INT32）
    post_process_fc_rescale #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_fc_rescale (
        .clk(clk),
        .rst_n(rst_n),
        .in_data_bus(stage0_data_bus),
        .out_rescale_bus(stage1_rescale_bus)
    );

    meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage0_valid),
        .in_last(stage0_last),
        .in_pos(stage0_pos),
        .in_group(stage0_group),
        .in_fire(stage0_fire),
        .out_valid(stage1_valid),
        .out_last(stage1_last),
        .out_pos(stage1_pos),
        .out_group(stage1_group),
        .out_fire(stage1_fire)
    );

    // Stage2: 有符号饱和到 INT8（无 ReLU）
    post_process_fc_saturate u_post_process_fc_saturate (
        .in_value_cls0(stage1_rescale_bus[31:0]),
        .in_value_cls1(stage1_rescale_bus[63:32]),
        .out_data_bus(stage2_data_bus_next)
    );

    assign out_valid    = stage1_valid;
    assign out_last     = stage1_last;
    assign out_pos      = stage1_pos;
    assign out_group    = stage1_group;
    assign out_fire     = stage1_fire;
    assign out_data_bus = stage2_data_bus_next;

endmodule
