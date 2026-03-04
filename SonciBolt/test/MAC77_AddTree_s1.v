`timescale 1ns / 1ps

// =============================================================================
// Module Name : MAC77_AddTree_s1
// Description : 面向 11x7 卷积窗的 77 路并行乘累加树。
//               采用 3 级流水线设计，确保满足 150MHz+ 时序要求。
//               带数据门控（Data Gating）技术，极致降低动态功耗。
// 本模块是第二个子模块，实现第一级加法：77 个 INT16 分为 10 组，每组 8 个（最后一组只有 5 个），并行求和得到 10 个 INT20 的部分和
// =============================================================================

module MAC77_AddTree_s1 (
	input wire                 clk,
	input wire                 rst_n,
	input wire                 valid_in,
	input wire [77*16-1:0]     products,
	output reg                 valid_out,
	output reg [10*20-1:0]     psums_out
);

	wire signed [15:0] p [0:76];
	genvar i;
    // fj0304: 接口解包，抽离出 77 个 有符号 INT16 乘积结果，方便后续加树处理
	generate
		for (i = 0; i < 77; i = i + 1) begin : UNPACK_PRODUCTS
			assign p[i] = $signed(products[i*16 +: 16]);
            // fj0304: 这里已经明确指明 p[i] 是有符号数了，后续加法操作就会自动使用有符号加法
		end
	endgenerate

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			valid_out <= 1'b0;
			psums_out <= {(10*20){1'b0}};
		end else begin
			valid_out <= valid_in;
			if (valid_in) begin
				psums_out[0*20 +: 20] <= p[0] + p[1] + p[2] + p[3] + p[4] + p[5] + p[6] + p[7];
				psums_out[1*20 +: 20] <= p[8] + p[9] + p[10] + p[11] + p[12] + p[13] + p[14] + p[15];
				psums_out[2*20 +: 20] <= p[16] + p[17] + p[18] + p[19] + p[20] + p[21] + p[22] + p[23];
				psums_out[3*20 +: 20] <= p[24] + p[25] + p[26] + p[27] + p[28] + p[29] + p[30] + p[31];
				psums_out[4*20 +: 20] <= p[32] + p[33] + p[34] + p[35] + p[36] + p[37] + p[38] + p[39];
				psums_out[5*20 +: 20] <= p[40] + p[41] + p[42] + p[43] + p[44] + p[45] + p[46] + p[47];
				psums_out[6*20 +: 20] <= p[48] + p[49] + p[50] + p[51] + p[52] + p[53] + p[54] + p[55];
				psums_out[7*20 +: 20] <= p[56] + p[57] + p[58] + p[59] + p[60] + p[61] + p[62] + p[63];
				psums_out[8*20 +: 20] <= p[64] + p[65] + p[66] + p[67] + p[68] + p[69] + p[70] + p[71];
				psums_out[9*20 +: 20] <= p[72] + p[73] + p[74] + p[75] + p[76];
			end
		end
	end

endmodule
