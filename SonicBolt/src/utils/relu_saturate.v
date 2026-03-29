`timescale 1ns / 1ps
/*
 * 模块名称: relu_saturate
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 * 
 * 功能概述:
 *   量化流水第 2 级，只负责 ReLU、饱和和 pack。
 */
module relu_saturate #(
    parameter integer TILE_H = 2,
    parameter integer TILE_W = 2
)(
    input  wire          clk,           // 时钟
    input  wire          rst_n,         // 低有效复位
    input  wire [4*TILE_H*TILE_W*32-1:0] in_shift_bus,  // 4 x TILE_H x TILE_W 个 INT32 右移结果
    output reg  [4*TILE_H*TILE_W*8-1:0]  out_data_bus   // 4 x TILE_H x TILE_W 个 INT8 输出
);

    integer idx;
    reg signed [31:0] shifted_value;
    reg [7:0] packed_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data_bus <= {4*TILE_H*TILE_W{8'd0}};
        end else begin
            for (idx = 0; idx < 4*TILE_H*TILE_W; idx = idx + 1) begin
                shifted_value = in_shift_bus[idx*32 +: 32];
                if (shifted_value <= 0) begin
                    packed_value = 8'd0;
                end else if (shifted_value > 127) begin
                    packed_value = 8'd127;
                end else begin
                    packed_value = shifted_value[7:0];
                end
                out_data_bus[idx*8 +: 8] <= packed_value;
            end
        end
    end

endmodule
