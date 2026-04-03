`timescale 1ns / 1ps
/*
 * 模块名称: post_process_fc_bias_add
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 两路 INT32 帧累加 + 两路 INT16 bias
 */
module post_process_fc_bias_add (
    input  wire signed [31:0] in_sum_cls0,
    input  wire signed [31:0] in_sum_cls1,
    input  wire signed [15:0] in_bias_cls0,
    input  wire signed [15:0] in_bias_cls1,

    output wire signed [31:0] out_sum_cls0,
    output wire signed [31:0] out_sum_cls1
);

    wire signed [31:0] bias_cls0_32;
    wire signed [31:0] bias_cls1_32;

    assign bias_cls0_32 = {{16{in_bias_cls0[15]}}, in_bias_cls0};
    assign bias_cls1_32 = {{16{in_bias_cls1[15]}}, in_bias_cls1};

    assign out_sum_cls0 = in_sum_cls0 + bias_cls0_32;
    assign out_sum_cls1 = in_sum_cls1 + bias_cls1_32;

endmodule
