`timescale 1ns / 1ps
/*
 * 模块名称: bias_pipe
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 *
 * 功能概述:
 *   通用模块: bias 打拍寄存，用于对齐跨行归约的多级流水。
 *
 * 设计说明:
 *   - bias 总线宽度均为 64bit = 4 x INT16。
 *   - 由于跨行归约被拆成多级流水，bias 也需要同步打一拍对齐。
 *   - 本模块不做算术，只做寄存。
 */
module bias_pipe (
    input  wire         clk,          // 时钟
    input  wire         rst_n,        // 低有效复位
    input  wire [63:0]  in_bias_bus,  // 输入 bias 总线
    output reg  [63:0]  out_bias_bus  // 打一拍后的 bias 总线
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_bias_bus <= 64'd0;
        end else begin
            out_bias_bus <= in_bias_bus;
        end
    end

endmodule
