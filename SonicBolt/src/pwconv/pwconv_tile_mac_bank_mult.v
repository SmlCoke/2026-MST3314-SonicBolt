`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bank_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-11
 * 版本: v1.2
 *
 * 功能概述:
 *   - 对单个输出 group 执行 8(group) x 4(out) x 4(spatial) 的局部点积。
 *   - 每个点积包含 4 项 INT8 x INT8 乘法和两级加法树。
 *
 * 总线展开顺序:
 *   - tile_data_bus  : [in_group][channel_of_group][spatial][8bit]
 *   - weight_data_bus: [in_group][kernel][channel][8bit]
 *   - out_partial_bus: [in_group][channel_of_group][spatial][18bit]
 *
 * 设计说明:
 *   - 组合点积单元拆分为 pwconv_tile_mac_dot4_cell。
 *   - 本模块保持“组合计算 + 输出打一拍”的时序语义不变。
 *
 * 版本定位:
 *   - v1.1 修复了部分注释错误，理清了 bus 的维度和索引关系，功能上完全等价于v1.0
 *   - v1.2 为了降低综合复杂度，计算被拆成小单元 pwconv_tile_mac_dot4_cell 并用 generate 展开。
 */
module pwconv_tile_mac_bank_mult (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [1023:0]      tile_data_bus,      // [in_group][channel_of_group][spatial][8bit]
    input  wire [8*4*4*8-1:0] weight_data_bus,    // [in_group][kernel][channel][8bit]
    output reg  [128*18-1:0]  out_partial_bus     // [in_group][channel_of_group][spatial][18bit]
);

    wire [128*18-1:0] partial_bus_comb;

    genvar g_group;
    genvar g_out;
    genvar g_spatial;
    generate
        for (g_group = 0; g_group < 8; g_group = g_group + 1) begin : G_GROUP
            for (g_out = 0; g_out < 4; g_out = g_out + 1) begin : G_OUT
                for (g_spatial = 0; g_spatial < 4; g_spatial = g_spatial + 1) begin : G_SPATIAL
                    localparam integer OUT_IDX = g_group * 16 + g_out * 4 + g_spatial;

                    wire signed [17:0] partial_point;

                    // 4 路点积单元
                    pwconv_tile_mac_dot4_cell u_dot4_cell (
                        .act_0(tile_data_bus[(g_group*16 + 0*4 + g_spatial) * 8 +: 8]),
                        .act_1(tile_data_bus[(g_group*16 + 1*4 + g_spatial) * 8 +: 8]),
                        .act_2(tile_data_bus[(g_group*16 + 2*4 + g_spatial) * 8 +: 8]),
                        .act_3(tile_data_bus[(g_group*16 + 3*4 + g_spatial) * 8 +: 8]),
                        .wt_0(weight_data_bus[(g_group*16 + g_out*4 + 0) * 8 +: 8]),
                        .wt_1(weight_data_bus[(g_group*16 + g_out*4 + 1) * 8 +: 8]),
                        .wt_2(weight_data_bus[(g_group*16 + g_out*4 + 2) * 8 +: 8]),
                        .wt_3(weight_data_bus[(g_group*16 + g_out*4 + 3) * 8 +: 8]),
                        .partial_sum(partial_point)
                    );

                    assign partial_bus_comb[(OUT_IDX * 18) +: 18] = partial_point;
                end
            end
        end
    endgenerate

    // 将组合逻辑的计算结果打拍输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_partial_bus <= {(128*18){1'b0}};
        end else begin
            out_partial_bus <= partial_bus_comb;
        end
    end

endmodule
