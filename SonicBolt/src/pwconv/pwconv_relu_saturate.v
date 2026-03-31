`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_relu_saturate
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 *
 * 功能概述:
 *   PWConv 量化流水第 2 级，对 16 个 INT32 结果执行 ReLU 和 INT8 饱和裁剪。
 *
 * 裁剪规则:
 *   - <= 0   -> 0
 *   - 1..127 -> 原值
 *   - > 127  -> 127
 */
module pwconv_relu_saturate (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [511:0]  in_shift_bus,
    output reg  [127:0]  out_data_bus
);

    integer idx;
    reg signed [31:0] shifted_value;
    reg [7:0] packed_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data_bus <= 128'd0;
        end else begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
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
