`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_add
 * 作者: SonicBolt 团队
 * 日期: 2026-04-12
 * 版本: v3.3
 *
 * 功能概述:
 *   对 11 个 kernel_row 的部分和做跨行归约，生成 4ch x 2x4 半窗的最终 INT32 累加结果。
 *
 * 输入组织:
 *   - in_row_sum_bus 为 11 组 608bit 拼接，总宽 6688bit。
 *   - 每组 608bit 对应 32 个 INT19 行和。
 *   - 4ch x 2row x 4col = 32, 32 x INT19 = 608bit。
 *
 * 输出组织:
 *   - out_sum_bus 含 32 个 INT32，总宽 1024bit。
 *
 * 设计说明:
 *   - 偏置广播规则改为“每个通道覆盖 8 个空间点”，对应半窗 2x4。
 *   - 仍保留两级流水，降低 11 路归约的组合深度。
 *
 * 版本定位:
 *   - v3.1 相比 v3.0 在内部增加了一级流水线，将 11 -> 1 加法树拆分为两级，瓦解这个巨型组合逻辑组合拥堵点，期望*     为下步布线工具指明打拍切入的位置，改善可布线性和时序宽裕度
 *   - v3.2 为了降低综合复杂度，计算被拆成小单元，并用 generate 展开。
 *   - v3.3 修改以适配半窗缓存，主要改动为砍掉一半输入带宽（11 x 1216->11 x 608）
 *     以及一半的加法计算量（64组 11 x INT19 + INT16 -> 32组 11 x INT19 + INT16）
 */
module conv_tile_mac_row_add (
    input  wire                clk,            // 时钟
    input  wire                rst_n,          // 低有效复位
    input  wire [11*608-1:0]   in_row_sum_bus, // 11 组行和
    input  wire [4*16-1:0]     bias_data_bus,  // 4 个偏置
    output reg  [1023:0]       out_sum_bus     // 最终 32 个 INT32 累加结果
);
    integer idx;

    // 第一级流水寄存器：保存两两相加后的 6 组部分和。
    reg signed [19:0] partial_0 [0:31];
    reg signed [19:0] partial_1 [0:31];
    reg signed [19:0] partial_2 [0:31];
    reg signed [19:0] partial_3 [0:31];
    reg signed [19:0] partial_4 [0:31];
    reg signed [19:0] partial_5 [0:31];

    wire [32*120-1:0] stage1_partial_bus_comb;
    wire [1024-1:0]   stage2_sum_bus_comb;

    genvar g_idx;
    generate
        // 32 个输出位置的 11 个输入行和的归约计算单元。
        for (g_idx = 0; g_idx < 32; g_idx = g_idx + 1) begin : G_CELL
            localparam integer IDX = g_idx;

            // 每个输入行和的位宽为 19bit，偏置为 16bit。
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

            // stage 1 流水级：11 -> 6 的加法树，输出部分和。
            wire signed [19:0] p0;
            wire signed [19:0] p1;
            wire signed [19:0] p2;
            wire signed [19:0] p3;
            wire signed [19:0] p4;
            wire signed [19:0] p5;
            // stage 2 流水级：6 -> 1 的加法树，输出最终结果。
            wire signed [31:0] sum_point;

            assign row_0  = in_row_sum_bus[(0*608)  + IDX*19 +: 19];
            assign row_1  = in_row_sum_bus[(1*608)  + IDX*19 +: 19];
            assign row_2  = in_row_sum_bus[(2*608)  + IDX*19 +: 19];
            assign row_3  = in_row_sum_bus[(3*608)  + IDX*19 +: 19];
            assign row_4  = in_row_sum_bus[(4*608)  + IDX*19 +: 19];
            assign row_5  = in_row_sum_bus[(5*608)  + IDX*19 +: 19];
            assign row_6  = in_row_sum_bus[(6*608)  + IDX*19 +: 19];
            assign row_7  = in_row_sum_bus[(7*608)  + IDX*19 +: 19];
            assign row_8  = in_row_sum_bus[(8*608)  + IDX*19 +: 19];
            assign row_9  = in_row_sum_bus[(9*608)  + IDX*19 +: 19];
            assign row_10 = in_row_sum_bus[(10*608) + IDX*19 +: 19];
            assign bias_val = bias_data_bus[(IDX / 8) * 16 +: 16];

            // 例化 stage 1 的加法树单元，输入 11 行和与偏置，输出 6 组部分和。
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

            
            assign stage1_partial_bus_comb[(IDX*120) +: 20]       = p0;
            assign stage1_partial_bus_comb[(IDX*120 + 20) +: 20]  = p1;
            assign stage1_partial_bus_comb[(IDX*120 + 40) +: 20]  = p2;
            assign stage1_partial_bus_comb[(IDX*120 + 60) +: 20]  = p3;
            assign stage1_partial_bus_comb[(IDX*120 + 80) +: 20]  = p4;
            assign stage1_partial_bus_comb[(IDX*120 + 100) +: 20] = p5;

            // 例化 stage 2 的加法树单元，输入 6 组部分和，输出最终结果。
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

    // stage1: 归约前半段打拍。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < 32; idx = idx + 1) begin
                partial_0[idx] <= 20'sd0;
                partial_1[idx] <= 20'sd0;
                partial_2[idx] <= 20'sd0;
                partial_3[idx] <= 20'sd0;
                partial_4[idx] <= 20'sd0;
                partial_5[idx] <= 20'sd0;
            end
        end else begin
            for (idx = 0; idx < 32; idx = idx + 1) begin
                partial_0[idx] <= stage1_partial_bus_comb[(idx*120) +: 20];
                partial_1[idx] <= stage1_partial_bus_comb[(idx*120 + 20) +: 20];
                partial_2[idx] <= stage1_partial_bus_comb[(idx*120 + 40) +: 20];
                partial_3[idx] <= stage1_partial_bus_comb[(idx*120 + 60) +: 20];
                partial_4[idx] <= stage1_partial_bus_comb[(idx*120 + 80) +: 20];
                partial_5[idx] <= stage1_partial_bus_comb[(idx*120 + 100) +: 20];
            end
        end
    end

    // stage2: 汇总 6 组部分和并输出最终半窗结果。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_sum_bus <= {1024{1'b0}};
        end else begin
            out_sum_bus <= stage2_sum_bus_comb;
        end
    end

endmodule
