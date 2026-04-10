`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_tile_mac_row_add
 * 作者: SonicBolt 团队
 * 日期: 2026-04-10
 * 版本: v1.1
 *
 * 功能概述:
 *   对 3 个 kernel_row 行和做跨行归约，并叠加 bias，得到 16 个 INT32 输出。
 *
 * 输入组织:
 *   - in_row_sum_bus: 3 组 * 16 点 * INT18
 *   - bias_data_bus : 4 个 INT16，每通道复用到对应 2x2 空间位置
 *
 * 输出组织:
 *   - out_sum_bus: 16 个 INT32
 *
 * 设计说明:
 *   - 组合归约单元拆分为 dwconv_tile_mac_reduce3_cell。
 *   - 本模块仅保留输出打一拍，时序语义与原实现一致。
 */
module dwconv_tile_mac_row_add (
    input  wire                 clk,             // 时钟
    input  wire                 rst_n,           // 低有效复位
    input  wire [3*288-1:0]     in_row_sum_bus,  // 3 组行和
    input  wire [4*16-1:0]      bias_data_bus,   // 4 个偏置
    output reg  [511:0]         out_sum_bus      // 最终 16 个 INT32 累加结果
);

    wire [511:0] sum_bus_comb;

    genvar g_idx;
    generate
        for (g_idx = 0; g_idx < 16; g_idx = g_idx + 1) begin : G_CELL
            localparam integer IDX = g_idx;

            wire signed [17:0] row_0;
            wire signed [17:0] row_1;
            wire signed [17:0] row_2;
            wire signed [15:0] bias_val;
            wire signed [31:0] sum_point;

            assign row_0    = in_row_sum_bus[(0*288) + IDX*18 +: 18];
            assign row_1    = in_row_sum_bus[(1*288) + IDX*18 +: 18];
            assign row_2    = in_row_sum_bus[(2*288) + IDX*18 +: 18];
            assign bias_val = bias_data_bus[(IDX/4)*16 +: 16];

            dwconv_tile_mac_reduce3_cell u_reduce3_cell (
                .row_0(row_0),
                .row_1(row_1),
                .row_2(row_2),
                .bias_val(bias_val),
                .out_sum(sum_point)
            );

            assign sum_bus_comb[(IDX*32) +: 32] = sum_point;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_sum_bus <= 512'd0;
        end else begin
            out_sum_bus <= sum_bus_comb;
        end
    end
endmodule
