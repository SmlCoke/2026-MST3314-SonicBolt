`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: MAC77_AddTree_s1
// 功能  : 加法树第 1 级（流水第 2 级）
// 说明  : 77 个 INT16 先分组求和为 10 个 INT20 局部和
//         前 9 组每组 8 个，最后 1 组 5 个
// -----------------------------------------------------------------------------
module MAC77_AddTree_s1 (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             valid_in,
    input  wire [1231:0]    products,
    output reg              valid_out,
    output reg [199:0]      psums_out
);
    wire signed [15:0] p [0:76];
    genvar i;

    generate
        for (i = 0; i < 77; i = i + 1) begin : GEN_P_UNPACK
            assign p[i] = $signed(products[i*16 +: 16]);
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            psums_out <= 200'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                psums_out[  0 +: 20] <= p[0]  + p[1]  + p[2]  + p[3]  + p[4]  + p[5]  + p[6]  + p[7];
                psums_out[ 20 +: 20] <= p[8]  + p[9]  + p[10] + p[11] + p[12] + p[13] + p[14] + p[15];
                psums_out[ 40 +: 20] <= p[16] + p[17] + p[18] + p[19] + p[20] + p[21] + p[22] + p[23];
                psums_out[ 60 +: 20] <= p[24] + p[25] + p[26] + p[27] + p[28] + p[29] + p[30] + p[31];
                psums_out[ 80 +: 20] <= p[32] + p[33] + p[34] + p[35] + p[36] + p[37] + p[38] + p[39];
                psums_out[100 +: 20] <= p[40] + p[41] + p[42] + p[43] + p[44] + p[45] + p[46] + p[47];
                psums_out[120 +: 20] <= p[48] + p[49] + p[50] + p[51] + p[52] + p[53] + p[54] + p[55];
                psums_out[140 +: 20] <= p[56] + p[57] + p[58] + p[59] + p[60] + p[61] + p[62] + p[63];
                psums_out[160 +: 20] <= p[64] + p[65] + p[66] + p[67] + p[68] + p[69] + p[70] + p[71];
                psums_out[180 +: 20] <= p[72] + p[73] + p[74] + p[75] + p[76];
            end
        end
    end

endmodule

