`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_add
 * 作者: SonicBolt 团队
 * 日期: 2026-04-11
 * 版本: v3.2
 *
 * 功能概述:
 *   对 11 个 kernel_row 行和做跨行归约，实现 11 -> 1。
 *
 * 输入组织:
 *   - in_row_sum_bus 是 11 组 1216bit 的拼接，总宽 13376bit。
 *   - 每组 1216bit 对应 64 个 INT19 行和。
 *
 * 输出组织:
 *   - out_sum_bus 含 64 个 INT32，总宽 2048bit。
 *
 * 版本定位:
 *   - v3.1 相比 v3.0 在内部增加了一级流水线，将 11 -> 1 加法树拆分为两级，瓦解这个巨型组合逻辑组合拥堵点，期望*     为下步布线工具指明打拍切入的位置，改善可布线性和时序宽裕度
 *   - v3.2 为了降低综合复杂度，计算被拆成小单元，并用 generate 展开。
 */
module conv_tile_mac_row_add (
    input  wire                 clk,             // 时钟
    input  wire                 rst_n,           // 低有效复位
    input  wire [11*1216-1:0]   in_row_sum_bus,  // 11 组行和
    input  wire [4*16-1:0]      bias_data_bus,   // 4 个偏置
    output reg  [2047:0]        out_sum_bus      // 最终 64 个 INT32 累加结果
);

    integer idx;

    // 第一级流水寄存器：保存两两相加的部分和
    reg signed [19:0] partial_0 [0:63];
    reg signed [19:0] partial_1 [0:63];
    reg signed [19:0] partial_2 [0:63];
    reg signed [19:0] partial_3 [0:63];
    reg signed [19:0] partial_4 [0:63];
    reg signed [19:0] partial_5 [0:63];

    wire [64*120-1:0] stage1_partial_bus_comb;
    wire [2048-1:0]   stage2_sum_bus_comb;

    genvar g_idx;
    generate
        for (g_idx = 0; g_idx < 64; g_idx = g_idx + 1) begin : G_CELL
            localparam integer IDX = g_idx;

            wire signed [18:0] row_0;
            wire signed [18:0] row_1;
            wire signed [18:0] row_2;
            wire signed [18:0] row_3;
            wire signed [18:0] row_4;
            wire signed [18:0] row_5;
            wire signed [18:0] row_6;
            wire signed [18:0] row_7;
            wire signed [18:0] row_8;
            wire signed [18:0] row_9;
            wire signed [18:0] row_10;
            wire signed [15:0] bias_val;

            wire signed [19:0] p0;
            wire signed [19:0] p1;
            wire signed [19:0] p2;
            wire signed [19:0] p3;
            wire signed [19:0] p4;
            wire signed [19:0] p5;
            wire signed [31:0] sum_point;

            assign row_0  = in_row_sum_bus[(0*1216)  + IDX*19 +: 19];
            assign row_1  = in_row_sum_bus[(1*1216)  + IDX*19 +: 19];
            assign row_2  = in_row_sum_bus[(2*1216)  + IDX*19 +: 19];
            assign row_3  = in_row_sum_bus[(3*1216)  + IDX*19 +: 19];
            assign row_4  = in_row_sum_bus[(4*1216)  + IDX*19 +: 19];
            assign row_5  = in_row_sum_bus[(5*1216)  + IDX*19 +: 19];
            assign row_6  = in_row_sum_bus[(6*1216)  + IDX*19 +: 19];
            assign row_7  = in_row_sum_bus[(7*1216)  + IDX*19 +: 19];
            assign row_8  = in_row_sum_bus[(8*1216)  + IDX*19 +: 19];
            assign row_9  = in_row_sum_bus[(9*1216)  + IDX*19 +: 19];
            assign row_10 = in_row_sum_bus[(10*1216) + IDX*19 +: 19];
            assign bias_val = bias_data_bus[(IDX/16)*16 +: 16];

            // stage1: 计算每一个输出块，11 行 + 偏置 得到 6 个部分和
            conv_tile_mac_reduce11_stage1_cell u_stage1_cell (
                .row_0(row_0),
                .row_1(row_1),
                .row_2(row_2),
                .row_3(row_3),
                .row_4(row_4),
                .row_5(row_5),
                .row_6(row_6),
                .row_7(row_7),
                .row_8(row_8),
                .row_9(row_9),
                .row_10(row_10),
                .bias_val(bias_val),
                .partial_0(p0),
                .partial_1(p1),
                .partial_2(p2),
                .partial_3(p3),
                .partial_4(p4),
                .partial_5(p5)
            );

            assign stage1_partial_bus_comb[(IDX*120) +: 20] = p0;
            assign stage1_partial_bus_comb[(IDX*120 + 20) +: 20] = p1;
            assign stage1_partial_bus_comb[(IDX*120 + 40) +: 20] = p2;
            assign stage1_partial_bus_comb[(IDX*120 + 60) +: 20] = p3;
            assign stage1_partial_bus_comb[(IDX*120 + 80) +: 20] = p4;
            assign stage1_partial_bus_comb[(IDX*120 + 100) +: 20] = p5;

            // stage2: 6 个部分和相加得到最终结果
            conv_tile_mac_reduce11_stage2_cell u_stage2_cell (
                .partial_0(partial_0[IDX]),
                .partial_1(partial_1[IDX]),
                .partial_2(partial_2[IDX]),
                .partial_3(partial_3[IDX]),
                .partial_4(partial_4[IDX]),
                .partial_5(partial_5[IDX]),
                .out_sum(sum_point)
            );

            assign stage2_sum_bus_comb[(IDX*32) +: 32] = sum_point;
        end
    endgenerate

    // Stage1: 计算部分和并打拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < 64; idx = idx + 1) begin
                partial_0[idx] <= 20'sd0;
                partial_1[idx] <= 20'sd0;
                partial_2[idx] <= 20'sd0;
                partial_3[idx] <= 20'sd0;
                partial_4[idx] <= 20'sd0;
                partial_5[idx] <= 20'sd0;
            end
        end else begin
            for (idx = 0; idx < 64; idx = idx + 1) begin
                partial_0[idx] <= stage1_partial_bus_comb[(idx*120) +: 20];
                partial_1[idx] <= stage1_partial_bus_comb[(idx*120 + 20) +: 20];
                partial_2[idx] <= stage1_partial_bus_comb[(idx*120 + 40) +: 20];
                partial_3[idx] <= stage1_partial_bus_comb[(idx*120 + 60) +: 20];
                partial_4[idx] <= stage1_partial_bus_comb[(idx*120 + 80) +: 20];
                partial_5[idx] <= stage1_partial_bus_comb[(idx*120 + 100) +: 20];
            end
        end
    end

    // Stage2: 汇总部分和并打拍输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_sum_bus <= {2048{1'b0}};
        end else begin
            out_sum_bus <= stage2_sum_bus_comb;
        end
    end

endmodule
