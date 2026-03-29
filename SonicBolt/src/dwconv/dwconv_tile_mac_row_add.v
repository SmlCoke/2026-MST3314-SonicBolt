`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_tile_mac_row_add
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 *
 * 功能概述:
 *   对 3 个 kernel_row 行和做第一层跨行归约，固定实现为 3+1 -> 1。
 *
 * 输入组织:
 *   - in_row_sum_bus 是 3 组 4*2*2*18bit 的拼接，总宽度 864bit。
 *   - 每组 864bit 对应一个 kernel_row 的 16 个 INT18 行和。
 *
 * 输出组织:
 *   - out_sum_bus 含 16 个 INT32，总宽度 512bit。
 *
 * 版本定位:
 */
module dwconv_tile_mac_row_add (
    input  wire                 clk,             // 时钟
    input  wire                 rst_n,           // 低有效复位
    input  wire [3*288-1:0]     in_row_sum_bus,  // 3 组行和
    input  wire [4*16-1:0]      bias_data_bus,   // 4 个偏置
    output reg  [511:0]         out_sum_bus      // 最终 64 个 INT32 累加结果

);

    integer idx;
    // 三个行和
    reg signed [17:0] row_0;
    reg signed [17:0] row_1;
    reg signed [17:0] row_2;

    // 偏置
    reg signed [15:0] bias_val;

    // 保存两两相加的部分和
    reg signed [18:0] partial_0;
    reg signed [18:0] partial_1;

    // Stage 1: 计算部分和并打拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < 64; idx = idx + 1) begin
                row_0 <= 18'sd0;
                row_0 <= 18'sd0;
                row_0 <= 18'sd0;
                partial_0 <= 19'sd0;
                partial_1 <= 19'sd0;
            end
        end else begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                row_0  = in_row_sum_bus[(0*288) + idx*18 +: 18];
                row_1  = in_row_sum_bus[(1*288) + idx*18 +: 18];
                row_2  = in_row_sum_bus[(2*288) + idx*18 +: 18];
                bias_val = bias_data_bus[(idx/4)*4 +: 16];

                partial_0 = row_0 + row_1;
                partial_1 = row_2 + bias_val;

                out_sum_bus[idx*32 +: 32] <= partial_0 + partial_1;
            end
        end
    end
endmodule
