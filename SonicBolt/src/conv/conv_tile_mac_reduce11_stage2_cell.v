`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_reduce11_stage2_cell
 * 作者: SonicBolt 团队
 * 日期: 2026-04-26
 * 版本: v2.0
 *
 * 功能:
 *   对单个输出位置的 6 路部分和做第二阶段归约，输出最终 INT32 累加值。
 *
 * 运算复杂度分析:
 *  - 1 个计算单元, 2级流水加法树
 *  - 逻辑深度为: L1(1A) + reg + L2(2A)
 *
 * 版本定位:
 *  - v2.0 将原 3A 单周期组合逻辑拆为 L1(1A)→reg→L2(2A) 两级，
 *    消除 3A 组合深度违规。cell 内部增加 1 拍延迟。
 */
module conv_tile_mac_reduce11_stage2_cell (
    input  wire                clk,
    input  wire                rst_n,
    input  wire signed [19:0] partial_0,
    input  wire signed [19:0] partial_1,
    input  wire signed [19:0] partial_2,
    input  wire signed [19:0] partial_3,
    input  wire signed [19:0] partial_4,
    input  wire signed [19:0] partial_5,
    output wire signed [31:0] out_sum
);
    // L1: 3 组并行 2 输入加法 (1A)
    wire signed [20:0] s0_comb = partial_0 + partial_1;
    wire signed [20:0] s1_comb = partial_2 + partial_3;
    wire signed [20:0] s2_comb = partial_4 + partial_5;

    // L1 → L2 打拍
    reg signed [20:0] s0, s1, s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0 <= 21'sd0;
            s1 <= 21'sd0;
            s2 <= 21'sd0;
        end else begin
            s0 <= s0_comb;
            s1 <= s1_comb;
            s2 <= s2_comb;
        end
    end

    // L2+L3: 3→1 归约 (2A)，从寄存器输出组合得到最终结果
    assign out_sum = s0 + s1 + s2;
endmodule
