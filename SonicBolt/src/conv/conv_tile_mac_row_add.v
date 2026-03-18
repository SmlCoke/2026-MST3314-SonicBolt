`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_reduce_l1
 * 作者: SonicBolt 团队
 * 日期: 2026-03-18
 * 版本: v3.0
 *
 * 功能概述:
 *   对 11 个 kernel_row 行和做第一层跨行归约，固定实现为 11 -> 1。
 *   我们期望综合工具可以自动推断处加法树，得到总级数为 log2(11) ≈ 4 的加法链。
 *
 * 输入组织:
 *   - in_row_sum_bus 是 11 组 1216bit 的拼接，总宽度 13376bit。
 *   - 每组 1216bit 对应一个 kernel_row 的 64 个 INT19 行和。
 *
 * 输出组织:
 *   - out_sum_bus 含 64 个 INT32，总宽度 2048bit。
 */
module conv_tile_mac_row_add (
    input  wire                 clk,             // 时钟
    input  wire                 rst_n,           // 低有效复位
    input  wire [11*1216-1:0]   in_row_sum_bus,  // 11 组行和
    input  wire [4*16-1:0]      bias_data_bus,   // 4 个偏置
    output reg  [2047:0]        out_sum_bus      // 最终 64 个 INT32 累加结果

);

    integer idx;
    reg signed [18:0] row_0;
    reg signed [18:0] row_1;
    reg signed [18:0] row_2;
    reg signed [18:0] row_3;
    reg signed [18:0] row_4;
    reg signed [18:0] row_5;
    reg signed [18:0] row_6;
    reg signed [18:0] row_7;
    reg signed [18:0] row_8;
    reg signed [18:0] row_9;
    reg signed [18:0] row_10;
    reg signed [19:0] partial_0;
    reg signed [19:0] partial_1;
    reg signed [19:0] partial_2;
    reg signed [19:0] partial_3;
    reg signed [19:0] partial_4;
    reg signed [19:0] partial_5;
    reg signed [15:0] bias_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_sum_bus <= {2048{1'b0}};
        end else begin
            // 0~15: ch1 16~31: ch2 32~47: ch3 48~63: ch4
            // 0~3: oy0 ox0~ox3 4~7: oy1 ox0~ox3 8~11: oy2 ox0~ox3 12~15: oy3 ox0~ox3
            for (idx = 0; idx < 64; idx = idx + 1) begin
                row_0  = in_row_sum_bus[(0*1216) + idx*19 +: 19];
                row_1  = in_row_sum_bus[(1*1216) + idx*19 +: 19];
                row_2  = in_row_sum_bus[(2*1216) + idx*19 +: 19];
                row_3  = in_row_sum_bus[(3*1216) + idx*19 +: 19];
                row_4  = in_row_sum_bus[(4*1216) + idx*19 +: 19];
                row_5  = in_row_sum_bus[(5*1216) + idx*19 +: 19];
                row_6  = in_row_sum_bus[(6*1216) + idx*19 +: 19];
                row_7  = in_row_sum_bus[(7*1216) + idx*19 +: 19];
                row_8  = in_row_sum_bus[(8*1216) + idx*19 +: 19];
                row_9  = in_row_sum_bus[(9*1216) + idx*19 +: 19];
                row_10 = in_row_sum_bus[(10*1216) + idx*19 +: 19];
                bias_val = bias_data_bus[(idx/16)*16 +: 16];

                partial_0 = row_0 + row_1;
                partial_1 = row_2 + row_3;
                partial_2 = row_4 + row_5;
                partial_3 = row_6 + row_7;
                partial_4 = row_8 + row_9;
                partial_5 = row_10 + bias_val;

                out_sum_bus[idx*32 +: 32] <= partial_0 + partial_1 + partial_2 + partial_3 + partial_4 + partial_5;
            end
        end
    end

endmodule
