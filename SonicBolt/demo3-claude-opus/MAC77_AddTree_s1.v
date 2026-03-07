// ===========================================================================
// 文件名: MAC77_AddTree_s1.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   MAC 树流水线第 2 级 — 分组部分和
//   将 77 个 INT16 乘积分为 10 组进行求和：
//     组 0~8: 各 8 个元素（8 × INT16 → INT20）
//     组  9 : 5 个元素（5 × INT16 → INT20）
//   输出 10 个 INT20 部分和。
//
// 流水线延迟: 1 个时钟周期
// ---------------------------------------------------------------------------
// 端口说明:
//   clk        — 系统时钟
//   rst_n      — 异步低电平复位
//   valid_in   — 输入数据有效标志
//   prod_flat  — 77 × INT16 乘积，展平为 1232-bit
//   valid_out  — 输出数据有效标志（延迟 1 拍）
//   psum_flat  — 10 × INT20 部分和，展平为 200-bit
// ===========================================================================

module MAC77_AddTree_s1 (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                valid_in,
    input  wire [1232-1:0]     prod_flat,   // 77 × INT16
    output reg                 valid_out,
    output reg  [200-1:0]      psum_flat    // 10 × INT20
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
    // 10 个分组求和
    // 组 0~8: 各取 8 个 INT16 相加 → INT20
    // 组   9: 取 5 个 INT16 相加 → INT20
    // ------------------------------------------------------------------
    genvar g;
    generate
        // 组 0 ~ 8：每组 8 个元素
        for (g = 0; g < 9; g = g + 1) begin : gen_group_8
            wire signed [15:0] p0 = prod_flat[(g*8+0)*16 +: 16];
            wire signed [15:0] p1 = prod_flat[(g*8+1)*16 +: 16];
            wire signed [15:0] p2 = prod_flat[(g*8+2)*16 +: 16];
            wire signed [15:0] p3 = prod_flat[(g*8+3)*16 +: 16];
            wire signed [15:0] p4 = prod_flat[(g*8+4)*16 +: 16];
            wire signed [15:0] p5 = prod_flat[(g*8+5)*16 +: 16];
            wire signed [15:0] p6 = prod_flat[(g*8+6)*16 +: 16];
            wire signed [15:0] p7 = prod_flat[(g*8+7)*16 +: 16];

            // 两级加法树结构（减少关键路径延迟）
            wire signed [16:0] s01 = p0 + p1;
            wire signed [16:0] s23 = p2 + p3;
            wire signed [16:0] s45 = p4 + p5;
            wire signed [16:0] s67 = p6 + p7;
            wire signed [17:0] s03 = s01 + s23;
            wire signed [17:0] s47 = s45 + s67;
            wire signed [19:0] sum = {{2{s03[17]}}, s03} + {{2{s47[17]}}, s47};

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    psum_flat[g*20 +: 20] <= 20'sd0;
                else if (valid_in)
                    psum_flat[g*20 +: 20] <= sum;
            end
        end

        // 组 9：最后 5 个元素 (索引 72~76)
        if (1) begin : gen_group_5
            wire signed [15:0] p0 = prod_flat[72*16 +: 16];
            wire signed [15:0] p1 = prod_flat[73*16 +: 16];
            wire signed [15:0] p2 = prod_flat[74*16 +: 16];
            wire signed [15:0] p3 = prod_flat[75*16 +: 16];
            wire signed [15:0] p4 = prod_flat[76*16 +: 16];

            wire signed [16:0] s01 = p0 + p1;
            wire signed [16:0] s23 = p2 + p3;
            wire signed [17:0] s03 = s01 + s23;
            wire signed [19:0] sum = {{2{s03[17]}}, s03} + {{4{p4[15]}}, p4};

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    psum_flat[9*20 +: 20] <= 20'sd0;
                else if (valid_in)
                    psum_flat[9*20 +: 20] <= sum;
            end
        end
    endgenerate

endmodule
