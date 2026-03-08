// ===========================================================================
// 文件名: requant_relu_unit.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   单通道重量化单元，可选是否执行 ReLU。
//   将 INT32 乘累加结果转换为 INT8 输出。
//
// 计算公式:
//   mul = in_data * M0           (INT32 × INT16 → INT48)
//   shifted = mul >>> N          (算术右移)
//   USE_RELU=1: out = clamp(max(shifted, 0), 127)
//   USE_RELU=0: out = clamp(shifted, -128, 127)
//
// 默认参数（Conv1 层）:
//   M0 = 111, N = 14
//
// 流水线延迟: 2 个时钟周期
//   Stage 1: 乘法 (in_data × M0)
//   Stage 2: 移位 + ReLU + 饱和截断
// ---------------------------------------------------------------------------
// 端口说明:
//   clk       — 系统时钟
//   rst_n     — 异步低电平复位
//   valid_in  — 输入数据有效标志
//   in_data   — INT32 输入（MAC 输出）
//   valid_out — 输出数据有效标志（延迟 2 拍）
//   out_data  — INT8 输出（补码编码）
// ===========================================================================

module requant_relu_unit #(
    parameter signed [15:0] M0 = 16'sd111,  // 重量化乘数
    parameter               N  = 14,        // 右移位数
    parameter               USE_RELU = 1    // 1: ReLU, 0: 仅做有符号饱和
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               valid_in,
    input  wire signed [31:0] in_data,
    output reg                valid_out,
    output reg  [7:0]         out_data
);

    // ==================================================================
    // Stage 1: 乘法
    // ==================================================================
    reg                valid_s1;
    reg signed [47:0]  mul_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            mul_s1   <= 48'sd0;
        end else begin
            valid_s1 <= valid_in;
            if (valid_in)
                mul_s1 <= in_data * M0;
        end
    end

    // ==================================================================
    // Stage 2: 算术右移 + ReLU + 饱和截断
    // ==================================================================
    wire signed [47:0] shifted = mul_s1 >>> N;  // 算术右移

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            out_data  <= 8'd0;
        end else begin
            valid_out <= valid_s1;
            if (valid_s1) begin
                if (USE_RELU) begin
                    if (shifted < 48'sd0)
                        out_data <= 8'd0;
                    else if (shifted > 48'sd127)
                        out_data <= 8'd127;
                    else
                        out_data <= shifted[7:0];
                end else begin
                    if (shifted < -48'sd128)
                        out_data <= 8'h80;
                    else if (shifted > 48'sd127)
                        out_data <= 8'h7f;
                    else
                        out_data <= shifted[7:0];
                end
            end
        end
    end

endmodule
