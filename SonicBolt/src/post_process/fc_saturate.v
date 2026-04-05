`timescale 1ns / 1ps
/*
 * 模块名称: fc_saturate
 * 作者: SonicBolt 团队
 * 日期: 2026-04-05
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对两路 INT32 数据执行有符号 INT8 饱和
 *   - 输出格式: out_data_bus[7:0]=class0, out_data_bus[15:8]=class1
 *
 * 版本定位:
 *   - v1.0 完成基本功能实现
 *   - v1.1 将 v1.0 的组合逻辑模块升级为时序流水线，用寄存器打拍输出
 */
module fc_saturate (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire signed [31:0] in_value_cls0,
    input  wire signed [31:0] in_value_cls1,

    output reg                out_valid,
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid    <= 1'b0;
            out_data_bus <= 16'd0;
        end else begin
            // 元数据直接打拍输出
            out_valid <= in_valid;

            if (in_valid) begin
                out_data_bus[7:0]  <= saturate_int8_signed(in_value_cls0);
                out_data_bus[15:8] <= saturate_int8_signed(in_value_cls1);
            end else begin
                out_data_bus <= 16'd0;
            end
        end
    end

endmodule
