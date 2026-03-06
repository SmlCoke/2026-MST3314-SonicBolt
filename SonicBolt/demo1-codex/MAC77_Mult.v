`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: MAC77_Mult
// 功能  : 77 路 INT8xINT8 并行乘法（流水第 1 级）
// 输入  : act_flat_in / wgt_flat_in，均为 77x8bit 展平数据
// 输出  : products，77x16bit 展平乘积
// -----------------------------------------------------------------------------
module MAC77_Mult (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              valid_in,
    input  wire [615:0]      act_flat_in,
    input  wire [615:0]      wgt_flat_in,
    output reg               valid_out,
    output reg [1231:0]      products
);
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            products  <= 1232'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                for (i = 0; i < 77; i = i + 1) begin
                    products[i*16 +: 16] <=
                        $signed(act_flat_in[i*8 +: 8]) * $signed(wgt_flat_in[i*8 +: 8]);
                end
            end
        end
    end

endmodule

