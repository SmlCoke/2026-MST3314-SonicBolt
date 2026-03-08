// ===========================================================================
// 文件名: MAC77_Mult.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   77 路 INT8 × INT8 并行乘法器阵列（MAC 树流水线第 1 级）
//   将 11×7 卷积窗口中的 77 个激活值与 77 个权重值逐一相乘，
//   输出 77 个 INT16 有符号乘积。
//
// 流水线延迟: 1 个时钟周期
// ---------------------------------------------------------------------------
// 端口说明:
//   clk        — 系统时钟
//   rst_n      — 异步低电平复位
//   valid_in   — 输入数据有效标志
//   act_flat   — 77 个 INT8 激活值，展平为 616-bit（elem[0]在低位）
//   wgt_flat   — 77 个 INT8 权重值，展平为 616-bit（elem[0]在低位）
//   valid_out  — 输出数据有效标志（延迟 1 拍）
//   prod_flat  — 77 个 INT16 乘积，展平为 1232-bit（elem[0]在低位）
// ===========================================================================

module MAC77_Mult (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                valid_in,
    input  wire [616-1:0]      act_flat,   // 77 × INT8
    input  wire [616-1:0]      wgt_flat,   // 77 × INT8
    output reg                 valid_out,
    output reg  [1232-1:0]     prod_flat   // 77 × INT16
);

    // ------------------------------------------------------------------
    // valid 信号延迟 1 拍
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_out <= 1'b0;
        else
            valid_out <= valid_in;
    end

    // ------------------------------------------------------------------
    // 77 路有符号乘法，结果寄存器打拍
    // Data Gating：仅在 valid_in=1 时更新寄存器，降低动态功耗
    // ------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 77; i = i + 1) begin : gen_mult
            wire signed [7:0] act_elem = act_flat[i*8 +: 8];
            wire signed [7:0] wgt_elem = wgt_flat[i*8 +: 8];
            wire signed [15:0] product = act_elem * wgt_elem;
            // fj0308: 这里是无论输入(mac_valid_in)是否有效都一定会计算乘法，可否以改成仅在 valid_in=1 时才计算乘法？（即乘法器输入加上 valid_in 作为使能信号）以降低功耗？
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    prod_flat[i*16 +: 16] <= 16'sd0;
                else if (valid_in)
                    prod_flat[i*16 +: 16] <= product;
            end
        end
    endgenerate

endmodule
