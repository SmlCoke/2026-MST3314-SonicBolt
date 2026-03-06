`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: requant_relu_vec32
// 功能  : 32 通道并行 Requant + ReLU
// 输入  : 32xINT32 展平
// 输出  : 32xINT8 展平（out_data_flat[7:0] 为 ch0）
// -----------------------------------------------------------------------------
module requant_relu_vec32 #(
    parameter signed [15:0] M0 = 16'sd356,
    parameter integer       N  = 16
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              valid_in,
    input  wire [1023:0]     in_data_flat,
    output wire              valid_out,
    output wire [255:0]      out_data_flat
);
    wire [31:0] valid_ch;
    genvar g;

    generate
        for (g = 0; g < 32; g = g + 1) begin : GEN_REQUANT
            requant_relu_unit #(
                .M0(M0),
                .N (N)
            ) u_requant_relu_unit (
                .clk      (clk),
                .rst_n    (rst_n),
                .valid_in (valid_in),
                .in_data  ($signed(in_data_flat[g*32 +: 32])),
                .valid_out(valid_ch[g]),
                .out_data (out_data_flat[g*8 +: 8])
            );
        end
    endgenerate

    assign valid_out = valid_ch[0];

endmodule

