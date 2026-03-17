`timescale 1ns / 1ps


// =============================================================================
// Module Name : MAC77_AddTree_s2
// Description : 面向 11x7 卷积窗的 77 路并行乘累加树。
//               采用 3 级流水线设计，确保满足 150MHz+ 时序要求。
//               带数据门控（Data Gating）技术，极致降低动态功耗。
// 本模块是第三个子模块，实现第二级加法：10 个 INT20 的部分和直接相加，并加上有符号偏置INT16，得到最终的 INT32 结果
// =============================================================================

module MAC77_AddTree_s2 (
	input wire                 clk,
	input wire                 rst_n,
	input wire                 valid_in,
	input wire [10*20-1:0]     psums_in,
	input wire signed [15:0]   bias_in,
	output reg                 valid_out,
	output reg signed [31:0]   mac_out
);

	wire signed [19:0] ps [0:9];
	genvar i;
	generate
		for (i = 0; i < 10; i = i + 1) begin : UNPACK_PSUMS
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
				mac_out <= ps[0] + ps[1] + ps[2] + ps[3] + ps[4] +
						   ps[5] + ps[6] + ps[7] + ps[8] + ps[9] +
						   $signed(bias_in);
			end
		end
	end

endmodule
