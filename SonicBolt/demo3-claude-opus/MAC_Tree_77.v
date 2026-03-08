// ===========================================================================
// 文件名: MAC_Tree_77.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   完整的 77 路并行乘累加树，封装三级流水线子模块：
//     S1: MAC77_Mult      — 77 路乘法器 (1 拍)
//     S2: MAC77_AddTree_s1 — 分组部分和  (1 拍)
//     S3: MAC77_AddTree_s2 — 最终求和    (1 拍)
//   总延迟: 3 个时钟周期
//
// 用途:
//   对 11×7 卷积窗口的 77 个激活值与 77 个权重值进行点积运算，
//   并加上 INT32 偏置，输出 INT32 MAC 结果。
//   Conv1 顶层例化 32 个 MAC_Tree_77（每通道一个）。
// ---------------------------------------------------------------------------
// 端口说明:
//   clk        — 系统时钟
//   rst_n      — 异步低电平复位
//   valid_in   — 输入数据有效标志
//   act_flat   — 77 × INT8 激活值（616-bit，elem[0]在低位）
//   wgt_flat   — 77 × INT8 权重值（616-bit，elem[0]在低位）
//   bias_in    — INT16 偏置
//   valid_out  — 输出数据有效标志（延迟 3 拍）
//   mac_out    — INT32 乘累加结果
// ===========================================================================

module MAC_Tree_77 (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                valid_in,
    input  wire [616-1:0]      act_flat,   // 77 × INT8 激活值
    input  wire [616-1:0]      wgt_flat,   // 77 × INT8 权重值
    input  wire signed [15:0]  bias_in,    // INT16 偏置
    output wire                valid_out,  // 输出有效
    output wire signed [31:0]  mac_out     // INT32 结果
);

    // ==================================================================
    // Stage 1: 77 路乘法器
    // ==================================================================
    wire        s1_valid;
    wire [1232-1:0] s1_prod;
    // 1232 = 77 * 16 (每个乘积结果为 INT16)
    MAC77_Mult u_mult (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .act_flat  (act_flat),
        .wgt_flat  (wgt_flat),
        .valid_out (s1_valid),
        .prod_flat (s1_prod)
    );

    // ==================================================================
    // Stage 2: 分组部分和（10 组）
    // ==================================================================
    wire        s2_valid;
    wire [200-1:0] s2_psum;

    MAC77_AddTree_s1 u_add_s1 (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (s1_valid),
        .prod_flat (s1_prod),
        .valid_out (s2_valid),
        .psum_flat (s2_psum)
    );

    // ==================================================================
    // bias 需要延迟 2 拍以对齐 Stage 3 的输入时序
    // ==================================================================
    reg signed [15:0] bias_d1, bias_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_d1 <= 16'sd0;
            bias_d2 <= 16'sd0;
        end else begin
            bias_d1 <= bias_in;
            bias_d2 <= bias_d1;
        end
    end

    // ==================================================================
    // Stage 3: 最终求和 + 偏置
    // ==================================================================
    MAC77_AddTree_s2 u_add_s2 (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (s2_valid),
        .psum_flat (s2_psum),
        .bias_in   (bias_d2),
        .valid_out (valid_out),
        .mac_out   (mac_out)
    );

endmodule
