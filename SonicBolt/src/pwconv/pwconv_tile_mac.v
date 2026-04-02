`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-04-01
 * 版本: v3.1
 *
 * 功能概述:
 *   - 每拍处理一个完整 32ch x 2x2 输入 tile（8 个输入 group 全量参与计算）。
 *   - 每拍只计算一个输出 group（4 个卷积核）的 16 个 INT32 结果。
 *   - 采用 4 级流水：bank_mult -> bank_accum -> bias_add + metadata 对齐。
 *
 * 设计定位:
 *   - 保留模块名与实例名，对外接口不变。
 *   - 拆分子模块仍保持: bank_mult / bank_accum / bias_add。
 */
module pwconv_tile_mac (
    input  wire               clk,             // 时钟
    input  wire               rst_n,           // 低有效复位

    // ---------- 输入元数据 ----------
    input  wire               in_valid,        // 输入 token 有效
    input  wire               in_last,         // 输入 token 是否为整张图最后一个 token
    input  wire [3:0]         in_pos,          // 输入 token 的 pos 编号
    input  wire [2:0]         in_group,        // 输入 token 的输出 group 编号
    input  wire               in_fire,         // 下一层启动信号

    // ---------- 输入数据(总线) ----------
    input  wire [1023:0]      tile_data_bus,   // 当前 token 对应完整 32(ch)x2x2 INT8 tile
    input  wire [8*128-1:0]   weight_data_bus, // 当前 out_group 对应 8(in_group) x 4(out)x4(in) 权重
    input  wire [63:0]        bias_data_bus,   // 当前 out_group 对应的 4xINT16 bias

    // ---------- 输出元数据 ----------
    output wire               out_valid,       // 输出累加 tile 有效
    output wire               out_last,        // 输出累加 tile 是否为最后一个 token
    output wire [3:0]         out_pos,         // 输出 tile 的 pos
    output wire [2:0]         out_group,       // 输出 tile 的 out_group
    output wire               out_fire,        // 输出的下一层启动信号

    // ---------- 输出数据 ----------
    output wire [16*32-1:0]   out_accum_bus    // 4(out) x 2(row) x 2(col) x INT32
);

    // ---------- stage1: 输入打拍 ----------
    reg [1023:0]      stage1_tile_data;
    reg [8*128-1:0]   stage1_weight_data;
    reg [63:0]        stage1_bias_data;
    wire [63:0]       stage2_bias_data;
    wire [63:0]       stage3_bias_data;

    wire        stage1_valid;
    wire        stage1_last;
    wire [3:0]  stage1_pos;
    wire [2:0]  stage1_group;
    wire        stage1_fire;

    // ---------- stage2: 8 输入 group 局部点积 ----------
    wire [128*18-1:0] stage2_partial_bus;

    wire        stage2_valid;
    wire        stage2_last;
    wire [3:0]  stage2_pos;
    wire [2:0]  stage2_group;
    wire        stage2_fire;

    // ---------- stage3: 跨 8 输入 group 归约 ----------
    wire [16*21-1:0] stage3_accum_bus;

    wire       stage3_accum_valid;
    wire       stage3_meta_valid;
    wire       stage3_last;
    wire [3:0] stage3_pos;
    wire [2:0] stage3_group;
    wire       stage3_fire;

    // ---------- stage4: bias 叠加 ----------
    wire [16*32-1:0] stage4_accum_bus;

    wire       stage4_valid;
    wire       stage4_last;
    wire [3:0] stage4_pos;
    wire [2:0] stage4_group;
    wire       stage4_fire;

    // ---------------------------------------------------------------------
    // ------------------------- 第一级流水：stage1 --------------------------
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_tile_data   <= 1024'd0;
            stage1_weight_data <= {(8*128){1'b0}};
            stage1_bias_data   <= 64'd0;
        end else begin
            stage1_tile_data   <= tile_data_bus;
            stage1_weight_data <= weight_data_bus;
            stage1_bias_data   <= bias_data_bus;
        end
    end

    meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_last(in_last),
        .in_pos(in_pos),
        .in_group(in_group),
        .in_fire(in_fire),
        .out_valid(stage1_valid),
        .out_last(stage1_last),
        .out_pos(stage1_pos),
        .out_group(stage1_group),
        .out_fire(stage1_fire)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第二级流水：stage2 --------------------------
    // ---------------------------------------------------------------------
    // 利用全部 8 个输入 tile 以及当前 4 个卷积核，计算出 8 组局部乘加结果
    pwconv_tile_mac_bank_mult u_pwconv_tile_mac_bank_mult (
        .clk(clk),
        .rst_n(rst_n),
        .tile_data_bus(stage1_tile_data),
        .weight_data_bus(stage1_weight_data),
        .out_partial_bus(stage2_partial_bus)
    );

    bias_pipe u_bias_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage1_bias_data),
        .out_bias_bus(stage2_bias_data)
    );

    meta_pipe u_meta_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .in_fire(stage1_fire),
        .out_valid(stage2_valid),
        .out_last(stage2_last),
        .out_pos(stage2_pos),
        .out_group(stage2_group),
        .out_fire(stage2_fire)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第三级流水：stage3 --------------------------
    // ---------------------------------------------------------------------
    pwconv_tile_mac_bank_accum u_pwconv_tile_mac_bank_accum (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2_valid),
        .in_partial_bus(stage2_partial_bus),
        .out_valid(stage3_accum_valid),
        .out_accum_bus(stage3_accum_bus)
    );

    bias_pipe u_bias_pipe_stage3 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage2_bias_data),
        .out_bias_bus(stage3_bias_data)
    );

    meta_pipe u_meta_pipe_stage3 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2_valid),
        .in_last(stage2_last),
        .in_pos(stage2_pos),
        .in_group(stage2_group),
        .in_fire(stage2_fire),
        .out_valid(stage3_meta_valid),
        .out_last(stage3_last),
        .out_pos(stage3_pos),
        .out_group(stage3_group),
        .out_fire(stage3_fire)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第四级流水：stage4 --------------------------
    // ---------------------------------------------------------------------
    pwconv_tile_mac_bias_add u_pwconv_tile_mac_bias_add (
        .clk(clk),
        .rst_n(rst_n),
        .in_accum_bus(stage3_accum_bus),
        .in_bias_bus(stage3_bias_data),
        .out_accum_bus(stage4_accum_bus)
    );

    meta_pipe u_meta_pipe_stage4 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage3_meta_valid),
        .in_last(stage3_last),
        .in_pos(stage3_pos),
        .in_group(stage3_group),
        .in_fire(stage3_fire),
        .out_valid(stage4_valid),
        .out_last(stage4_last),
        .out_pos(stage4_pos),
        .out_group(stage4_group),
        .out_fire(stage4_fire)
    );

    assign out_valid     = stage4_valid;
    assign out_last      = stage4_last;
    assign out_pos       = stage4_pos;
    assign out_group     = stage4_group;
    assign out_fire      = stage4_fire;
    assign out_accum_bus = stage4_accum_bus;

endmodule
