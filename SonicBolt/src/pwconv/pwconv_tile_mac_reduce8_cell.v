`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_reduce8_cell
 * 作者: SonicBolt 团队
 * 日期: 2026-04-26
 * 版本: v2.0
 *
 * 功能:
 *   对单个输出位置执行 8 路 INT18 部分和归约，输出 INT21。
 *
 * 运算复杂度分析:
 *   - 二级流水加法树，8 x INT18 -> 1 x INT21
 *   - 逻辑深度为: L1(1A) + reg + L2+L3(2A)
 *
 * 版本定位:
 *   - v1.2 原版本
 *   - v2.0 将原 3A 单周期组合逻辑拆为 L1(1A)→reg→L2+L3(2A) 两级，
 *     消除 3A 组合深度违规。cell 内部增加 1 拍延迟。
 */
module pwconv_tile_mac_reduce8_cell (
    input  wire                clk,
    input  wire                rst_n,
    input  wire signed [17:0] partial_0,
    input  wire signed [17:0] partial_1,
    input  wire signed [17:0] partial_2,
    input  wire signed [17:0] partial_3,
    input  wire signed [17:0] partial_4,
    input  wire signed [17:0] partial_5,
    input  wire signed [17:0] partial_6,
    input  wire signed [17:0] partial_7,
    output wire signed [20:0] accum_sum
);
    // L1: 4 组并行 2 输入加法 (1A)
    wire signed [18:0] sum_l1_0 = {{1{partial_0[17]}}, partial_0} + {{1{partial_1[17]}}, partial_1};
    wire signed [18:0] sum_l1_1 = {{1{partial_2[17]}}, partial_2} + {{1{partial_3[17]}}, partial_3};
    wire signed [18:0] sum_l1_2 = {{1{partial_4[17]}}, partial_4} + {{1{partial_5[17]}}, partial_5};
    wire signed [18:0] sum_l1_3 = {{1{partial_6[17]}}, partial_6} + {{1{partial_7[17]}}, partial_7};

    // L1 → L2 打拍
    reg signed [18:0] r_sum_l1_0, r_sum_l1_1, r_sum_l1_2, r_sum_l1_3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_sum_l1_0 <= 19'sd0;
            r_sum_l1_1 <= 19'sd0;
            r_sum_l1_2 <= 19'sd0;
            r_sum_l1_3 <= 19'sd0;
        end else begin
            r_sum_l1_0 <= sum_l1_0;
            r_sum_l1_1 <= sum_l1_1;
            r_sum_l1_2 <= sum_l1_2;
            r_sum_l1_3 <= sum_l1_3;
        end
    end

    // L2+L3: 从已寄存的 L1 结果做两级加法 (2A)
    wire signed [19:0] sum_l2_0 = {{1{r_sum_l1_0[18]}}, r_sum_l1_0} + {{1{r_sum_l1_1[18]}}, r_sum_l1_1};
    wire signed [19:0] sum_l2_1 = {{1{r_sum_l1_2[18]}}, r_sum_l1_2} + {{1{r_sum_l1_3[18]}}, r_sum_l1_3};
    assign accum_sum = {{1{sum_l2_0[19]}}, sum_l2_0} + {{1{sum_l2_1[19]}}, sum_l2_1};
endmodule
