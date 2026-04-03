`timescale 1ns / 1ps
/*
 * 模块名称: post_process_fc_saturate
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对两路 INT32 数据执行有符号 INT8 饱和
 *   - 输出格式: out_data_bus[7:0]=class0, out_data_bus[15:8]=class1
 */
module post_process_fc_saturate (
    input  wire signed [31:0] in_value_cls0,
    input  wire signed [31:0] in_value_cls1,

    output reg  [15:0]        out_data_bus
);

    function [7:0] saturate_int8_signed;
        input signed [31:0] value;
        begin
            if (value > 32'sd127) begin
                saturate_int8_signed = 8'sd127;
            end else if (value < -32'sd128) begin
                saturate_int8_signed = 8'h80;
            end else begin
                saturate_int8_signed = value[7:0];
            end
        end
    endfunction

    always @(*) begin
        out_data_bus[7:0]  = saturate_int8_signed(in_value_cls0);
        out_data_bus[15:8] = saturate_int8_signed(in_value_cls1);
    end

endmodule
