`timescale 1ns / 1ps
/*
 * 模块名称: conv_rescale_mul_stage
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 功能概述:
 *   量化流水第 1 级，只负责 64 个 INT32 与常数 M0 的乘法。
 */
module conv_rescale_mul_stage #(
    parameter integer M0 = 111
) (
    input  wire          clk,          // 时钟
    input  wire          rst_n,        // 低有效复位
    input  wire [2047:0] in_data_bus,  // 64 个 INT32 输入值
    output reg  [3071:0] out_mult_bus  // 64 个 INT48 乘法结果
);

    integer idx;
    reg signed [31:0] current_value;
    reg signed [47:0] mult_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_mult_bus <= 3072'd0;
        end else begin
            for (idx = 0; idx < 64; idx = idx + 1) begin
                current_value = in_data_bus[idx*32 +: 32];
                mult_value = current_value * M0;
                out_mult_bus[idx*48 +: 48] <= mult_value;
            end
        end
    end

endmodule
