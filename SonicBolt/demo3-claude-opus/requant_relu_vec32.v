// ===========================================================================
// 文件名: requant_relu_vec32.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   32 通道并行重量化向量单元。
//   例化 32 个 requant_relu_unit，并行处理 32 个 INT32 值。
//
// 流水线延迟: 2 个时钟周期（与单个 unit 相同）
// ---------------------------------------------------------------------------
// 端口说明:
//   clk          — 系统时钟
//   rst_n        — 异步低电平复位
//   valid_in     — 输入数据有效标志
//   in_data_flat — 32 × INT32 输入，展平为 1024-bit（ch[0]在低位）
//   valid_out    — 输出数据有效标志
//   out_data_flat— 32 × INT8 输出，展平为 256-bit（ch[0]在低位）
// ===========================================================================

module requant_relu_vec32 #(
    parameter signed [15:0] M0 = 16'sd111,
    parameter               N  = 14,
    parameter               USE_RELU = 1
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                valid_in,
    input  wire [1024-1:0]     in_data_flat,   // 32 × INT32
    output wire                valid_out,
    output wire [256-1:0]      out_data_flat   // 32 × INT8
);

    // ------------------------------------------------------------------
    // 32 个 requant_relu_unit 并行例化
    // ------------------------------------------------------------------
    wire [31:0] valid_vec;  // 每个 unit 的 valid_out（理论上全部相同）

    genvar ch;
    generate
        for (ch = 0; ch < 32; ch = ch + 1) begin : gen_rq
            requant_relu_unit #(
                .M0       (M0),
                .N        (N),
                .USE_RELU (USE_RELU)
            ) u_rq (
                .clk       (clk),
                .rst_n     (rst_n),
                .valid_in  (valid_in),
                .in_data   (in_data_flat[ch*32 +: 32]),
                .valid_out (valid_vec[ch]),
                .out_data  (out_data_flat[ch*8 +: 8])
            );
        end
    endgenerate

    // 取任意一个通道的 valid_out 作为整体输出
    assign valid_out = valid_vec[0];

endmodule
