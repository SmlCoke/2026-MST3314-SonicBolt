`timescale 1ns / 1ps
/*
 * 模块名称: fc_bias_store
 * 作者: SonicBolt 团队
 * 日期: 2026-04-06
 * 版本: v1.1
 *
 * 功能概述:
 *   - 维护 FC 的两路 bias 存储（class0/class1）
 *
 * 版本定位:
 *  - v1.0: 基础功能实现，支持 bias 写入和输出
 *  - v1.1: 双路同时写入
 */
module fc_bias_store (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               bias_wr_en,
    input  wire signed [31:0] bias_wr_data,

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
                bias_mem[0] <= bias_wr_data[15:0];
                bias_mem[1] <= bias_wr_data[31:16];
            end
        end
    end

    assign out_bias_cls0 = bias_mem[0];
    assign out_bias_cls1 = bias_mem[1];

endmodule
