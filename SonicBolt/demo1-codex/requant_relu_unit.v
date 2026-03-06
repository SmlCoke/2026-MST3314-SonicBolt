`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: requant_relu_unit
// 功能  : 对单通道 INT32 做 Requant + ReLU + 饱和截断
// 公式  : O = (I * M0) >>> N
// 规则  : <0 -> 0, >127 -> 127, 其余取低 8 位
// 延迟  : valid_in -> valid_out 共 2 拍
// -----------------------------------------------------------------------------
module requant_relu_unit #(
    parameter signed [15:0] M0 = 16'sd356,
    parameter integer       N  = 16
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               valid_in,
    input  wire signed [31:0] in_data,
    output reg                valid_out,
    output reg  [7:0]         out_data
);
    reg                valid_s1;
    reg signed [47:0]  mul_s1;
    wire signed [47:0] shift_w;

    assign shift_w = mul_s1 >>> N;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            mul_s1   <= 48'sd0;
        end else begin
            valid_s1 <= valid_in;
            if (valid_in) begin
                mul_s1 <= in_data * $signed(M0);
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            out_data  <= 8'd0;
        end else begin
            valid_out <= valid_s1;
            if (valid_s1) begin
                if (shift_w < 48'sd0) begin
                    out_data <= 8'd0;
                end else if (shift_w > 48'sd127) begin
                    out_data <= 8'd127;
                end else begin
                    out_data <= shift_w[7:0];
                end
            end
        end
    end

endmodule

