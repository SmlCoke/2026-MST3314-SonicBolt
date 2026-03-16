`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: MAC77_AddTree_s2
// 功能  : 加法树第 2 级（流水第 3 级）
// 说明  : 10 个 INT20 局部和 + INT16 bias，输出 INT32
// -----------------------------------------------------------------------------
module MAC77_AddTree_s2 (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              valid_in,
    input  wire [199:0]      psums_in,
    input  wire signed [15:0] bias_in,
    output reg               valid_out,
    output reg signed [31:0] mac_out
);
    wire signed [19:0] ps [0:9];
    genvar i;

    generate
        for (i = 0; i < 10; i = i + 1) begin : GEN_PSUM_UNPACK
            assign ps[i] = $signed(psums_in[i*20 +: 20]);
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            mac_out   <= 32'sd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                mac_out <= ps[0] + ps[1] + ps[2] + ps[3] + ps[4]
                         + ps[5] + ps[6] + ps[7] + ps[8] + ps[9]
                         + $signed(bias_in);
            end
        end
    end

endmodule

