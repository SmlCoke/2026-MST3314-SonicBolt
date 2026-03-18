`timescale 1ns / 1ps
/*
 * 模块名称: conv_rescale_mul_stage
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v2.0
 *
 * 功能概述:
 *   量化流水第 1 级，负责 64 个 INT32 与常数 M0 的乘法以及移位 SHIFT_N。
 */
module conv_rescale #(
    parameter integer M0 = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,          // 时钟
    input  wire          rst_n,        // 低有效复位
    input  wire [2047:0] in_data_bus,  // 64 个 INT32 输入值
    output reg  [2047:0] out_rescale_bus  // 64 个 INT48 乘法结果
);

    integer idx;
    reg signed [31:0] current_value;
    reg signed [47:0] mult_value;
    reg signed [31:0] shifted_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_rescale_bus <= 2048'd0;
        end else begin
            for (idx = 0; idx < 64; idx = idx + 1) begin
                current_value = in_data_bus[idx*32 +: 32];
                mult_value = current_value * M0;
                shifted_value = mult_value >>> SHIFT_N;
                out_rescale_bus[idx*32 +: 32] <= shifted_value;
            end
        end
    end

endmodule
