`timescale 1ns / 1ps
/*
 * 模块名称: post_process_fc_req_pipe
 * 作者: SonicBolt 团队
 * 日期: 2026-04-03
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对齐输入 token 与同步读权重
 *   - 本拍锁存输入 token，下拍用于 MAC
 */
module post_process_fc_req_pipe (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire        in_last,
    input  wire [31:0] in_data_bus,
    input  wire        weight_wr_en,

    output reg         out_valid,
    output reg         out_last,
    output reg  [31:0] out_data_bus
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid    <= 1'b0;
            out_last     <= 1'b0;
            out_data_bus <= 32'd0;
        end else begin
            if (in_valid && !weight_wr_en) begin
                out_valid    <= 1'b1;
                out_last     <= in_last;
                out_data_bus <= in_data_bus;
            end else begin
                out_valid    <= 1'b0;
                out_last     <= 1'b0;
                out_data_bus <= 32'd0;
            end
        end
    end

endmodule
