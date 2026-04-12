`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bank_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-12
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
 * 运算复杂度分析: 
 *   - 8group x 4ch/group x 4spa = 128 个并行计算单元 
 *   - 每个并行计算单元包含 4 个并行 INT8 乘法器 级联 两级加法树: 4 x INT16 to 1 x INT18
 *   - 逻辑深度为: 1 (乘法) + 1 (加法树第一层) + 1 (加法树第二层) = 1M + 2A
 * 
 * 版本定位:
 *   - v1.1 修复了部分注释错误，理清了 bus 的维度和索引关系，功能上完全等价于v1.0
 *   - v1.2 为了降低综合复杂度，计算被拆成小单元 pwconv_tile_mac_dot4_cell 并用 generate 展开。
 *   - v1.2 将乘法单元改为独立的 mult_cell 模块，期望进一步降低逻辑综合复杂度
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

                    wire signed [15:0] product_0;
                    wire signed [15:0] product_1;
                    wire signed [15:0] product_2;
                    wire signed [15:0] product_3;
                    wire signed [16:0] sum_l1_0;
                    wire signed [16:0] sum_l1_1;
                    wire signed [17:0] partial_point;

                    // 4 个 INT8xINT8 乘法单元
                    mult_cell u_mult_cell_0 (
                        .data(tile_data_bus[(g_group*16 + 0*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 0) * 8 +: 8]),
                        .out_prod(product_0)
                    );
                    mult_cell u_mult_cell_1 (
                        .data(tile_data_bus[(g_group*16 + 1*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 1) * 8 +: 8]),
                        .out_prod(product_1)
                    );
                    mult_cell u_mult_cell_2 (
                        .data(tile_data_bus[(g_group*16 + 2*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 2) * 8 +: 8]),
                        .out_prod(product_2)
                    );
                    mult_cell u_mult_cell_3 (
                        .data(tile_data_bus[(g_group*16 + 3*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 3) * 8 +: 8]),
                        .out_prod(product_3)
                    );

                    // 平衡加法树
                    assign sum_l1_0    = {{1{product_0[15]}}, product_0} + {{1{product_1[15]}}, product_1};
                    assign sum_l1_1    = {{1{product_2[15]}}, product_2} + {{1{product_3[15]}}, product_3};
                    assign partial_point = {{1{sum_l1_0[16]}}, sum_l1_0} + {{1{sum_l1_1[16]}}, sum_l1_1};

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
