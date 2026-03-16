`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_reduce_l1
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 功能概述:
 *   对 11 个 kernel_row 行和做第一层跨行归约，固定实现为 11 -> 6。
 *
 * 输入组织:
 *   - in_row_sum_bus 是 11 组 2048bit 的拼接，总宽度 22528bit。
 *   - 每组 2048bit 对应一个 kernel_row 的 64 个 INT32 行和。
 *
 * 输出组织:
 *   - out_partial_bus 是 6 组 2048bit 的拼接，总宽度 12288bit。
 */
module conv_tile_mac_row_reduce_l1 (
    input  wire                 clk,             // 时钟
    input  wire                 rst_n,           // 低有效复位
    input  wire [11*2048-1:0]   in_row_sum_bus,  // 11 组行和
    output reg  [6*2048-1:0]    out_partial_bus  // 6 组中间部分和
);

    integer idx;
    reg signed [31:0] row_0;
    reg signed [31:0] row_1;
    reg signed [31:0] row_2;
    reg signed [31:0] row_3;
    reg signed [31:0] row_4;
    reg signed [31:0] row_5;
    reg signed [31:0] row_6;
    reg signed [31:0] row_7;
    reg signed [31:0] row_8;
    reg signed [31:0] row_9;
    reg signed [31:0] row_10;
    reg signed [32:0] partial_0;
    reg signed [32:0] partial_1;
    reg signed [32:0] partial_2;
    reg signed [32:0] partial_3;
    reg signed [32:0] partial_4;
    reg signed [32:0] partial_5;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_partial_bus <= {6*2048{1'b0}};
        end else begin
            // 0~15: ch1 16~31: ch2 32~47: ch3 48~63: ch4
            // 0~3: oy0 ox0~ox3 4~7: oy1 ox0~ox3 8~11: oy2 ox0~ox3 12~15: oy3 ox0~ox3
            for (idx = 0; idx < 64; idx = idx + 1) begin
                row_0  = in_row_sum_bus[(0*2048) + idx*32 +: 32];
                row_1  = in_row_sum_bus[(1*2048) + idx*32 +: 32];
                row_2  = in_row_sum_bus[(2*2048) + idx*32 +: 32];
                row_3  = in_row_sum_bus[(3*2048) + idx*32 +: 32];
                row_4  = in_row_sum_bus[(4*2048) + idx*32 +: 32];
                row_5  = in_row_sum_bus[(5*2048) + idx*32 +: 32];
                row_6  = in_row_sum_bus[(6*2048) + idx*32 +: 32];
                row_7  = in_row_sum_bus[(7*2048) + idx*32 +: 32];
                row_8  = in_row_sum_bus[(8*2048) + idx*32 +: 32];
                row_9  = in_row_sum_bus[(9*2048) + idx*32 +: 32];
                row_10 = in_row_sum_bus[(10*2048) + idx*32 +: 32];

                partial_0 = row_0 + row_1;
                partial_1 = row_2 + row_3;
                partial_2 = row_4 + row_5;
                partial_3 = row_6 + row_7;
                partial_4 = row_8 + row_9;
                partial_5 = row_10;

                // 每个2048存放64个 INT32, 不同组同一位置的 INT32 属于同一个输出块的部分和
                out_partial_bus[(0*2048) + idx*32 +: 32] <= $signed(partial_0);
                out_partial_bus[(1*2048) + idx*32 +: 32] <= $signed(partial_1);
                out_partial_bus[(2*2048) + idx*32 +: 32] <= $signed(partial_2);
                out_partial_bus[(3*2048) + idx*32 +: 32] <= $signed(partial_3);
                out_partial_bus[(4*2048) + idx*32 +: 32] <= $signed(partial_4);
                out_partial_bus[(5*2048) + idx*32 +: 32] <= $signed(partial_5);
            end
        end
    end

endmodule
