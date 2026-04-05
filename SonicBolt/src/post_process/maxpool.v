`timescale 1ns / 1ps
/*
 * 模块名称: maxpool
 * 作者: SonicBolt 团队
 * 日期: 2026-04-05
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对 PWConv 输出 token 执行 2x2 最大池化（stride=2, padding=0）
 *   - 输入 token: 4(ch) x 2(row) x 2(col) x INT8 = 128bit
 *   - 输出 token: 4(ch) x 1(row) x 1(col) x INT8 = 32bit
 *
 * 设计说明:
 *   - 每个通道独立完成 4 个点位的比较归约，共 4 个通道
 *   - metadata 通过 meta_pipe 打一拍，与数据寄存输出保持同拍对齐
 */
module maxpool (
    input  wire         clk,
    input  wire         rst_n,

    // ---------- 输入 metadata ----------
    input  wire         in_valid,
    input  wire         in_last,
    input  wire [3:0]   in_pos,
    input  wire [2:0]   in_group,
    input  wire         in_fire,

    // ---------- 输入数据 ----------
    input  wire [127:0] in_data_bus,

    // ---------- 输出 metadata ----------
    output wire         out_valid,
    output wire         out_last,
    output wire [3:0]   out_pos,
    output wire [2:0]   out_group,
    output wire         out_fire,

    // ---------- 输出数据 ----------
    output reg  [31:0]  out_data_bus
);

    integer ch_idx;

    reg signed [7:0] value_0;
    reg signed [7:0] value_1;
    reg signed [7:0] value_2;
    reg signed [7:0] value_3;// 每个通道的 4 个输入值

    reg signed [7:0] max_l1_0;
    reg signed [7:0] max_l1_1;
    reg signed [7:0] max_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data_bus <= 32'd0;
        end else begin
            if (in_valid) begin
                // 4 通道并行
                for (ch_idx = 0; ch_idx < 4; ch_idx = ch_idx + 1) begin
                    value_0 = in_data_bus[((ch_idx * 4 + 0) * 8) +: 8];  // 第一个值
                    value_1 = in_data_bus[((ch_idx * 4 + 1) * 8) +: 8];  // 第二个值
                    value_2 = in_data_bus[((ch_idx * 4 + 2) * 8) +: 8];  // 第三个值
                    value_3 = in_data_bus[((ch_idx * 4 + 3) * 8) +: 8];  // 第四个值

                    // 两两比较
                    max_l1_0 = (value_0 > value_1) ? value_0 : value_1;
                    max_l1_1 = (value_2 > value_3) ? value_2 : value_3;
                    max_value = (max_l1_0 > max_l1_1) ? max_l1_0 : max_l1_1;

                    out_data_bus[(ch_idx * 8) +: 8] <= max_value;
                end
            end else begin
                out_data_bus <= 32'd0;
            end
        end
    end

    // 元数据打拍模块
    meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_last(in_last),
        .in_pos(in_pos),
        .in_group(in_group),
        .in_fire(in_fire),
        .out_valid(out_valid),
        .out_last(out_last),
        .out_pos(out_pos),
        .out_group(out_group),
        .out_fire(out_fire)
    );

endmodule
