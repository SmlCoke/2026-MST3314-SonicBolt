`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bank_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-01
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对单个输出 group执行 8(in_group) x 4(out) x 4(spatial) 的局部点积。
 *   - 每个点积包含 4 项 INT8 x INT8 乘法与两级平衡加法树。
 */
module pwconv_tile_mac_bank_mult (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [1023:0]    tile_data_bus,    // 8(in_group) x 4(in) x 4(spatial) x INT8
    input  wire [8*128-1:0] weight_data_bus,  // 8(in_group) x 4(out) x 4(in) x INT8
    output reg  [128*18-1:0] out_partial_bus  // 8(in_group) x 4(out) x 4(spatial) x INT18
);

    integer bank_idx;
    integer out_idx;
    integer spatial_idx;

    reg signed [7:0]  act_value_0;
    reg signed [7:0]  act_value_1;
    reg signed [7:0]  act_value_2;
    reg signed [7:0]  act_value_3;

    reg signed [7:0]  wt_value_0;
    reg signed [7:0]  wt_value_1;
    reg signed [7:0]  wt_value_2;
    reg signed [7:0]  wt_value_3;

    reg signed [15:0] product_0;
    reg signed [15:0] product_1;
    reg signed [15:0] product_2;
    reg signed [15:0] product_3;

    reg signed [16:0] sum_l1_0;
    reg signed [16:0] sum_l1_1;
    reg signed [17:0] partial_sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_partial_bus <= {(128*18){1'b0}};
        end else begin
            for (bank_idx = 0; bank_idx < 8; bank_idx = bank_idx + 1) begin
                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                    for (spatial_idx = 0; spatial_idx < 4; spatial_idx = spatial_idx + 1) begin
                        // 输入分片索引：[(in_idx * 4 + spatial_idx) * 8 +: 8]
                        act_value_0 = tile_data_bus[(bank_idx*128) + ((0*4 + spatial_idx) * 8) +: 8];
                        act_value_1 = tile_data_bus[(bank_idx*128) + ((1*4 + spatial_idx) * 8) +: 8];
                        act_value_2 = tile_data_bus[(bank_idx*128) + ((2*4 + spatial_idx) * 8) +: 8];
                        act_value_3 = tile_data_bus[(bank_idx*128) + ((3*4 + spatial_idx) * 8) +: 8];

                        // 权重索引：[(bank_idx*16 + out_idx*4 + in_idx) * 8 +: 8]
                        wt_value_0 = weight_data_bus[((bank_idx*16 + out_idx*4 + 0) * 8) +: 8];
                        wt_value_1 = weight_data_bus[((bank_idx*16 + out_idx*4 + 1) * 8) +: 8];
                        wt_value_2 = weight_data_bus[((bank_idx*16 + out_idx*4 + 2) * 8) +: 8];
                        wt_value_3 = weight_data_bus[((bank_idx*16 + out_idx*4 + 3) * 8) +: 8];

                        product_0 = act_value_0 * wt_value_0;
                        product_1 = act_value_1 * wt_value_1;
                        product_2 = act_value_2 * wt_value_2;
                        product_3 = act_value_3 * wt_value_3;

                        sum_l1_0 = {{1{product_0[15]}}, product_0} + {{1{product_1[15]}}, product_1};
                        sum_l1_1 = {{1{product_2[15]}}, product_2} + {{1{product_3[15]}}, product_3};
                        partial_sum = {{1{sum_l1_0[16]}}, sum_l1_0} + {{1{sum_l1_1[16]}}, sum_l1_1};

                        out_partial_bus[((bank_idx*16 + out_idx*4 + spatial_idx) * 18) +: 18] <= partial_sum;
                    end
                end
            end
        end
    end

endmodule
