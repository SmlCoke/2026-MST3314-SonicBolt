`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-04-26
 * 版本: v3.2
 *
 * 功能概述:
 *   - 每拍处理一个完整 32ch x 2x2 输入 tile（8 个输入 group 全量参与计算）。
 *   - 每拍只计算一个输出 group（4 个卷积核）的 16 个 INT32 结果。
 *   - 采用 6 级流水：bank_mult -> bank_accum -> bias_add + metadata 对齐。
 *
 * 版本定位:
 *   - v1.0~v3.1 暂时缺失
 *   - v3.2 bank_mult v1.3(+1 拍) + bank_accum v1.2(+1 拍)；
 *     新增 stage2a/stage2b/stage3a meta/bias 打拍以对齐，
 *     总流水从 4 级增至 6 级。
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

    wire        stage1_valid;
    wire        stage1_last;
    wire [3:0]  stage1_pos;
    wire [2:0]  stage1_group;
    wire        stage1_fire;

    // v3.2: stage2a —— 补偿 bank_mult v1.3 内部新增的 product 寄存器
    wire [63:0]       stage2a_bias_data;
    wire        stage2a_valid;
    wire        stage2a_last;
    wire [3:0]  stage2a_pos;
    wire [2:0]  stage2a_group;
    wire        stage2a_fire;

    // v3.2: stage2b —— 补偿 bank_mult v1.3 → 输出对齐 bank_accum 输入
    wire [63:0]       stage2b_bias_data;
    wire        stage2b_valid;
    wire        stage2b_last;
    wire [3:0]  stage2b_pos;
    wire [2:0]  stage2b_group;
    wire        stage2b_fire;

    // ---------- stage2: bank_mult 局部点积 ----------
    wire [128*18-1:0] stage2_partial_bus;

    // v3.2: stage3a —— 补偿 bank_accum v1.2 内部新增的 reduce8 寄存器
    wire [63:0]       stage3a_bias_data;
    wire        stage3a_valid;
    wire        stage3a_last;
    wire [3:0]  stage3a_pos;
    wire [2:0]  stage3a_group;
    wire        stage3a_fire;

    // ---------- stage3: 跨 8 输入 group 归约 ----------
    wire [16*21-1:0] stage3_accum_bus;
    wire [63:0]      stage3b_bias_data;

    wire       stage3_accum_valid;
    wire       stage3b_valid;
    wire       stage3b_last;
    wire [3:0] stage3b_pos;
    wire [2:0] stage3b_group;
    wire       stage3b_fire;

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

    // v3.2: stage2a meta/bias —— bank_mult product 寄存器对齐
    meta_pipe u_meta_pipe_stage2a (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .in_fire(stage1_fire),
        .out_valid(stage2a_valid),
        .out_last(stage2a_last),
        .out_pos(stage2a_pos),
        .out_group(stage2a_group),
        .out_fire(stage2a_fire)
    );

    bias_pipe u_bias_pipe_stage2a (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage1_bias_data),
        .out_bias_bus(stage2a_bias_data)
    );

    // v3.2: stage2b meta/bias —— bank_mult 输出寄存器 / bank_accum 输入对齐
    meta_pipe u_meta_pipe_stage2b (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2a_valid),
        .in_last(stage2a_last),
        .in_pos(stage2a_pos),
        .in_group(stage2a_group),
        .in_fire(stage2a_fire),
        .out_valid(stage2b_valid),
        .out_last(stage2b_last),
        .out_pos(stage2b_pos),
        .out_group(stage2b_group),
        .out_fire(stage2b_fire)
    );

    bias_pipe u_bias_pipe_stage2b (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage2a_bias_data),
        .out_bias_bus(stage2b_bias_data)
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

    // v3.2: stage3a meta/bias —— bank_accum reduce8 寄存器对齐
    meta_pipe u_meta_pipe_stage3a (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2b_valid),
        .in_last(stage2b_last),
        .in_pos(stage2b_pos),
        .in_group(stage2b_group),
        .in_fire(stage2b_fire),
        .out_valid(stage3a_valid),
        .out_last(stage3a_last),
        .out_pos(stage3a_pos),
        .out_group(stage3a_group),
        .out_fire(stage3a_fire)
    );

    bias_pipe u_bias_pipe_stage3a (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage2b_bias_data),
        .out_bias_bus(stage3a_bias_data)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第三级流水：stage3 --------------------------
    // 对 8 个输入 group 的部分和做归约，输出 4(out) x 4(spatial) 共 16 个 INT21。
    // ---------------------------------------------------------------------
    pwconv_tile_mac_bank_accum u_pwconv_tile_mac_bank_accum (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2b_valid),
        .in_partial_bus(stage2_partial_bus),
        .out_valid(stage3_accum_valid),
        .out_accum_bus(stage3_accum_bus)
    );

    // stage3b meta/bias —— bank_accum 输出对齐
    meta_pipe u_meta_pipe_stage3b (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage3a_valid),
        .in_last(stage3a_last),
        .in_pos(stage3a_pos),
        .in_group(stage3a_group),
        .in_fire(stage3a_fire),
        .out_valid(stage3b_valid),
        .out_last(stage3b_last),
        .out_pos(stage3b_pos),
        .out_group(stage3b_group),
        .out_fire(stage3b_fire)
    );

    bias_pipe u_bias_pipe_stage3b (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage3a_bias_data),
        .out_bias_bus(stage3b_bias_data)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第四级流水：stage4 --------------------------
    // 对 16 个 INT21 累加结果执行偏置叠加，输出 16 个 INT32。
    // ---------------------------------------------------------------------
    pwconv_tile_mac_bias_add u_pwconv_tile_mac_bias_add (
        .clk(clk),
        .rst_n(rst_n),
        .in_accum_bus(stage3_accum_bus),
        .in_bias_bus(stage3b_bias_data),
        .out_accum_bus(stage4_accum_bus)
    );

    meta_pipe u_meta_pipe_stage4 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage3b_valid),
        .in_last(stage3b_last),
        .in_pos(stage3b_pos),
        .in_group(stage3b_group),
        .in_fire(stage3b_fire),
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
