`timescale 1ns / 1ps
/*
 * 模块名称: post_process_fc_rescale
 * 作者: SonicBolt 团队
 * 日期: 2026-04-03
 * 版本: v1.0
 *
 * 功能概述:
 *   - FC 专用 rescale：对两路 INT32 执行乘 M0 与右移 SHIFT_N
 *   - 输入/输出均为两路 INT32 打包总线（64bit）
 */
module post_process_fc_rescale #(
    parameter integer M0 = 11,
    parameter integer SHIFT_N = 15
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [63:0] in_data_bus,
    output reg  [63:0] out_rescale_bus
);

    integer idx;
    reg signed [31:0] current_value;
    reg signed [47:0] mult_value;
    reg signed [31:0] shifted_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_rescale_bus <= 64'd0;
        end else begin
            for (idx = 0; idx < 2; idx = idx + 1) begin
                current_value = in_data_bus[idx*32 +: 32];
                mult_value = current_value * M0;
                shifted_value = mult_value >>> SHIFT_N;
                out_rescale_bus[idx*32 +: 32] <= shifted_value;
            end
        end
    end

endmodule