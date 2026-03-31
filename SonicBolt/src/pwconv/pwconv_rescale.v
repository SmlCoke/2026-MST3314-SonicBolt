`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_rescale
 * 功能概述:
 *   PWConv 量化流水第 1 级，对 16 个 INT32 累加结果统一乘 M0 并右移 SHIFT_N。
 *
 * 说明:
 *   - 输入来自 pwconv_tile_mac 的 16 个 INT32
 *   - 输出仍保持 16 个 INT32，留给下一拍做 ReLU 和 INT8 饱和
 */
module pwconv_rescale #(
    parameter integer M0      = 69,
    parameter integer SHIFT_N = 13
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [511:0]  in_data_bus,
    output reg  [511:0]  out_rescale_bus
);

    integer idx;
    reg signed [31:0] current_value;
    reg signed [47:0] mult_value;
    reg signed [31:0] shifted_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_rescale_bus <= 512'd0;
        end else begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                current_value = in_data_bus[idx*32 +: 32];
                mult_value    = current_value * M0;
                shifted_value = mult_value >>> SHIFT_N;
                out_rescale_bus[idx*32 +: 32] <= shifted_value;
            end
        end
    end

endmodule
