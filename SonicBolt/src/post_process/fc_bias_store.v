`timescale 1ns / 1ps
/*
 * 模块名称: fc_bias_store
 * 作者: SonicBolt 团队
 * 日期: 2026-04-05
 * 版本: v1.0
 *
 * 功能概述:
 *   - 维护 FC 的两路 bias 存储（class0/class1）
 *   - 采用顺序写入：第 1 次写 class0，第 2 次写 class1
 */
module fc_bias_store (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               bias_wr_en,
    input  wire signed [15:0] bias_wr_data,

    output wire signed [15:0] out_bias_cls0,
    output wire signed [15:0] out_bias_cls1
);

    reg signed [15:0] bias_mem [0:1];
    reg               bias_wr_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_mem[0] <= 16'sd0;
            bias_mem[1] <= 16'sd0;
            bias_wr_ptr <= 1'b0;
        end else begin
            if (bias_wr_en) begin
                bias_mem[bias_wr_ptr] <= bias_wr_data;
                bias_wr_ptr <= ~bias_wr_ptr;
            end
        end
    end

    assign out_bias_cls0 = bias_mem[0];
    assign out_bias_cls1 = bias_mem[1];

endmodule
