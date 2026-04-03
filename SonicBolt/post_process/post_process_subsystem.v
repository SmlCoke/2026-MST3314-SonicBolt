`timescale 1ns / 1ps
/*
 * 模块名称: post_process_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 后处理子系统顶层：Maxpool -> Flatten -> FC -> Sigmoid
 *   - FC 支持 72x64 权重 SRAM 在线写入，Bias 采用 2xINT16 寄存
 *   - 输出 busy/done 状态，便于与其他子系统统一集成
 *
 * 设计说明:
 *   - 输入一个 tile 即开始流式处理，不等待整帧缓存
 *   - busy=1 期间，禁止覆盖 FC 权重/Bias 与 Sigmoid LUT
 *   - done 在 Sigmoid 输出最后一个 token 时拉高 1 拍
 */
module post_process_subsystem #(
    parameter integer FC_M0      = 11,
    parameter integer FC_SHIFT_N = 15
) (
    input  wire         clk,
    input  wire         rst_n,
    output wire         busy,
    output wire         done,

    // ---------- 输入数据流接口（来自 PWConv） ----------
    input  wire         in_stream_valid,
    input  wire         in_stream_last,
    input  wire [3:0]   in_stream_pos,
    input  wire [2:0]   in_stream_group,
    input  wire         in_stream_fire,
    input  wire [127:0] in_stream_data,

    // ---------- FC 参数写接口 ----------
    input  wire         fc_weight_wr_en,
    input  wire [6:0]   fc_weight_wr_addr,
    input  wire [63:0]  fc_weight_wr_data,

    input  wire         fc_bias_wr_en,
    input  wire [15:0]  fc_bias_wr_data,

    // ---------- Sigmoid LUT 写接口 ----------
    input  wire         sigmoid_lut_wr_en,
    input  wire [7:0]   sigmoid_lut_wr_addr,
    input  wire [31:0]  sigmoid_lut_wr_data,

    // ---------- 输出数据流接口 ----------
    output wire         out_stream_valid,
    output wire         out_stream_last,
    output wire [3:0]   out_stream_pos,
    output wire [2:0]   out_stream_group,
    output wire         out_stream_fire,
    output wire [63:0]  out_stream_data
);

    reg busy_reg;
    reg done_reg;

    wire fc_weight_store_wr_en;
    wire fc_bias_store_wr_en;
    wire sigmoid_lut_store_wr_en;

    // ---------- Maxpool 内部流 ----------
    wire         maxpool_out_valid_int;
    wire         maxpool_out_last_int;
    wire [3:0]   maxpool_out_pos_int;
    wire [2:0]   maxpool_out_group_int;
    wire         maxpool_out_fire_int;
    wire [31:0]  maxpool_out_data_int;

    // ---------- Flatten 内部流 ----------
    wire         flatten_out_valid_int;
    wire         flatten_out_last_int;
    wire [3:0]   flatten_out_pos_int;
    wire [2:0]   flatten_out_group_int;
    wire         flatten_out_fire_int;
    wire [31:0]  flatten_out_data_int;

    // ---------- FC 内部流 ----------
    wire         fc_out_valid_int;
    wire         fc_out_last_int;
    wire [3:0]   fc_out_pos_int;
    wire [2:0]   fc_out_group_int;
    wire         fc_out_fire_int;
    wire [15:0]  fc_out_data_int;

    // ---------- Sigmoid 内部流 ----------
    wire         sigmoid_out_valid_int;
    wire         sigmoid_out_last_int;
    wire [3:0]   sigmoid_out_pos_int;
    wire [2:0]   sigmoid_out_group_int;
    wire         sigmoid_out_fire_int;
    wire [63:0]  sigmoid_out_data_int;

    // 忙于处理当前图时，禁止覆盖本层参数。
    assign fc_weight_store_wr_en   = fc_weight_wr_en && !busy_reg;
    assign fc_bias_store_wr_en     = fc_bias_wr_en && !busy_reg;
    assign sigmoid_lut_store_wr_en = sigmoid_lut_wr_en && !busy_reg;

    // 子系统忙闲状态：
    // - 收到本帧首个有效 token 后 busy 拉高
    // - Sigmoid 输出最后一个 token 时 done 脉冲 + busy 清零
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_reg <= 1'b0;
            done_reg <= 1'b0;
        end else begin
            done_reg <= 1'b0;

            if (sigmoid_out_valid_int && sigmoid_out_last_int) begin
                busy_reg <= 1'b0;
                done_reg <= 1'b1;
            end else if (!busy_reg && in_stream_valid) begin
                busy_reg <= 1'b1;
            end
        end
    end

    post_process_maxpool u_post_process_maxpool (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_stream_valid),
        .in_last(in_stream_last),
        .in_pos(in_stream_pos),
        .in_group(in_stream_group),
        .in_fire(in_stream_fire),
        .in_data_bus(in_stream_data),
        .out_valid(maxpool_out_valid_int),
        .out_last(maxpool_out_last_int),
        .out_pos(maxpool_out_pos_int),
        .out_group(maxpool_out_group_int),
        .out_fire(maxpool_out_fire_int),
        .out_data_bus(maxpool_out_data_int)
    );

    post_process_flatten u_post_process_flatten (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(maxpool_out_valid_int),
        .in_last(maxpool_out_last_int),
        .in_pos(maxpool_out_pos_int),
        .in_group(maxpool_out_group_int),
        .in_fire(maxpool_out_fire_int),
        .in_data_bus(maxpool_out_data_int),
        .out_valid(flatten_out_valid_int),
        .out_last(flatten_out_last_int),
        .out_pos(flatten_out_pos_int),
        .out_group(flatten_out_group_int),
        .out_fire(flatten_out_fire_int),
        .out_data_bus(flatten_out_data_int)
    );

    post_process_fc #(
        .M0(FC_M0),
        .SHIFT_N(FC_SHIFT_N)
    ) u_post_process_fc (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(flatten_out_valid_int),
        .in_last(flatten_out_last_int),
        .in_pos(flatten_out_pos_int),
        .in_group(flatten_out_group_int),
        .in_fire(flatten_out_fire_int),
        .in_data_bus(flatten_out_data_int),
        .weight_wr_en(fc_weight_store_wr_en),
        .weight_wr_addr(fc_weight_wr_addr),
        .weight_wr_data(fc_weight_wr_data),
        .bias_wr_en(fc_bias_store_wr_en),
        .bias_wr_data(fc_bias_wr_data),
        .out_valid(fc_out_valid_int),
        .out_last(fc_out_last_int),
        .out_pos(fc_out_pos_int),
        .out_group(fc_out_group_int),
        .out_fire(fc_out_fire_int),
        .out_data_bus(fc_out_data_int)
    );

    post_process_sigmoid u_post_process_sigmoid (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(fc_out_valid_int),
        .in_last(fc_out_last_int),
        .in_pos(fc_out_pos_int),
        .in_group(fc_out_group_int),
        .in_fire(fc_out_fire_int),
        .in_data_bus(fc_out_data_int),
        .lut_wr_en(sigmoid_lut_store_wr_en),
        .lut_wr_addr(sigmoid_lut_wr_addr),
        .lut_wr_data(sigmoid_lut_wr_data),
        .out_valid(sigmoid_out_valid_int),
        .out_last(sigmoid_out_last_int),
        .out_pos(sigmoid_out_pos_int),
        .out_group(sigmoid_out_group_int),
        .out_fire(sigmoid_out_fire_int),
        .out_data_bus(sigmoid_out_data_int)
    );

    assign busy = busy_reg;
    assign done = done_reg;

    assign out_stream_valid = sigmoid_out_valid_int;
    assign out_stream_last  = sigmoid_out_last_int;
    assign out_stream_pos   = sigmoid_out_pos_int;
    assign out_stream_group = sigmoid_out_group_int;
    assign out_stream_fire  = sigmoid_out_fire_int;
    assign out_stream_data  = sigmoid_out_data_int;

endmodule
