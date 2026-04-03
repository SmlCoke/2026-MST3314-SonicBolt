`timescale 1ns / 1ps
/*
 * 模块名称: post_process_flatten
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 将 Maxpool 输出 tile 进行流式展平，逐 tile 直接送入 FC
 *   - 输入/输出 tile 位宽均为 4(ch) x INT8 = 32bit
 *
 * 设计说明:
 *   - 不等待整帧，输入一个 tile 即输出一个 tile
 *   - 展平索引定义：idx = ch * 9 + pos，ch = group * 4 + lane
 */
module post_process_flatten (
    input  wire        clk,
    input  wire        rst_n,

    // ---------- 输入 metadata ----------
    input  wire        in_valid,
    input  wire        in_last,
    input  wire [3:0]  in_pos,
    input  wire [2:0]  in_group,
    input  wire        in_fire,

    // ---------- 输入数据 ----------
    input  wire [31:0] in_data_bus,

    // ---------- 输出 metadata ----------
    output wire        out_valid,
    output wire        out_last,
    output wire [3:0]  out_pos,
    output wire [2:0]  out_group,
    output wire        out_fire,

    // ---------- 输出数据 ----------
    output wire [31:0] out_data_bus
);

    reg [31:0] stage0_data_bus;// 展平前的原始数据
    reg [31:0] stage1_data_bus;// 展平后的数据，直接送往下一层

    reg        raw_valid;
    reg        raw_last;
    reg [3:0]  raw_pos;
    reg [2:0]  raw_group;
    reg        raw_fire;

    // 流式展平：输入 tile 直接送往下一层
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage0_data_bus <= 32'd0;
            stage1_data_bus <= 32'd0;

            raw_valid    <= 1'b0;
            raw_last     <= 1'b0;
            raw_pos      <= 4'd0;
            raw_group    <= 3'd0;
            raw_fire     <= 1'b0;
        end else begin
            // stage1 与 meta_pipe 的一拍输出对齐
            stage1_data_bus <= stage0_data_bus;

            if (in_valid) begin
                stage0_data_bus <= in_data_bus;
            end else begin
                stage0_data_bus <= 32'd0;
            end

            raw_valid <= in_valid;
            raw_last  <= in_last;
            raw_pos   <= in_pos;
            raw_group <= in_group;
            raw_fire  <= in_fire;
        end
    end

    meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(raw_valid),
        .in_last(raw_last),
        .in_pos(raw_pos),
        .in_group(raw_group),
        .in_fire(raw_fire),
        .out_valid(out_valid),
        .out_last(out_last),
        .out_pos(out_pos),
        .out_group(out_group),
        .out_fire(out_fire)
    );

    assign out_data_bus = stage1_data_bus;

endmodule
