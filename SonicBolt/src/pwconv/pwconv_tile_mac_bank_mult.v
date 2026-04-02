`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bank_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-01
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对单个输出 group 执行 8(group) x 4(out) x 4(spatial) 的局部点积。
 *   - 每个点积包含 4 项 INT8 x INT8 乘法与两级平衡加法树。
 *
 * 三条总线的展平维度顺序（从高维到低维）:
 *   - tile_data_bus  : [group][in_ch_group][spatial][8bit]
 *   - weight_data_bus: [group][out_ch_group][in_ch_group][8bit]
 *   - out_partial_bus: [group][out_ch_group][spatial][18bit]
 *
 * 位宽对应:
 *   - tile_data_bus   = 8 x 4 x 4 x 8  = 1024 bit
 *   - weight_data_bus = 8 x 4 x 4 x 8  = 1024 bit
 *   - out_partial_bus = 8 x 4 x 4 x 18 = 2304 bit
 *
 * 展平索引里常见乘数解释:
 *   - *4   : 一个维度固定 4 路（4 个输入通道 / 4 个输出通道 / 4 个 spatial 位置）
 *   - *16  : 16 = 4 x 4，表示一个 group 内 4x4 个元素
 *            1) 权重里是 4(out) x 4(in)
 *            2) partial 里是 4(out) x 4(spatial)
 *   - *128 : 128bit = 4(in) x 4(spatial) x 8bit，表示一个 group 的完整激活切片
 *
 * 注意:
 *   - group_idx 对应 group（输入组），不是输出组。
 *   - out_idx 对应当前输出 group 内的第几个输出通道（卷积核）。
 */
module pwconv_tile_mac_bank_mult (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [1023:0]    tile_data_bus,      // [group][in][spatial][8bit]
    input  wire [8*4*4*8-1:0] weight_data_bus,  // [group][out][in][8bit]
    output reg  [128*18-1:0] out_partial_bus    // [group][out][spatial][18bit]
);

    integer group_idx;
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
            // group_idx: 输入组索引 group，范围 0..7
            for (group_idx = 0; group_idx < 8; group_idx = group_idx + 1) begin
                // out_idx: 当前输出组中的输出通道索引，范围 0..3
                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                    // spatial_idx: 2x2 tile 的空间位置索引，范围 0..3
                    for (spatial_idx = 0; spatial_idx < 4; spatial_idx = spatial_idx + 1) begin
                        // 输入激活索引（单位：bit）
                        //   bit_base = group_idx*128 + (in_idx*4 + spatial_idx)*8
                        //   先定位 group 的 128bit 切片，再在切片内选 [in_idx, spatial_idx] 的 8bit
                        act_value_0 = tile_data_bus[(group_idx*16 + 0*4 + spatial_idx) * 8 +: 8];
                        act_value_1 = tile_data_bus[(group_idx*16 + 1*4 + spatial_idx) * 8 +: 8];
                        act_value_2 = tile_data_bus[(group_idx*16 + 2*4 + spatial_idx) * 8 +: 8];
                        act_value_3 = tile_data_bus[(group_idx*16 + 3*4 + spatial_idx) * 8 +: 8];

                        // 权重索引（单位：bit）
                        //   bit_base = (group_idx*16 + out_idx*4 + in_idx) * 8
                        //   其中 16 = 4(out) * 4(in)，表示一个 group 内共有 16 个 8bit 权重
                        wt_value_0 = weight_data_bus[((group_idx*16 + out_idx*4 + 0) * 8) +: 8];
                        wt_value_1 = weight_data_bus[((group_idx*16 + out_idx*4 + 1) * 8) +: 8];
                        wt_value_2 = weight_data_bus[((group_idx*16 + out_idx*4 + 2) * 8) +: 8];
                        wt_value_3 = weight_data_bus[((group_idx*16 + out_idx*4 + 3) * 8) +: 8];

                        product_0 = act_value_0 * wt_value_0;
                        product_1 = act_value_1 * wt_value_1;
                        product_2 = act_value_2 * wt_value_2;
                        product_3 = act_value_3 * wt_value_3;

                        sum_l1_0 = {{1{product_0[15]}}, product_0} + {{1{product_1[15]}}, product_1};
                        sum_l1_1 = {{1{product_2[15]}}, product_2} + {{1{product_3[15]}}, product_3};
                        partial_sum = {{1{sum_l1_0[16]}}, sum_l1_0} + {{1{sum_l1_1[16]}}, sum_l1_1};

                        // partial 输出索引（单位：bit）
                        //   bit_base = (group_idx*16 + out_idx*4 + spatial_idx) * 18
                        //   其中 16 = 4(out) * 4(spatial)
                        out_partial_bus[((group_idx*16 + out_idx*4 + spatial_idx) * 18) +: 18] <= partial_sum;
                    end
                end
            end
        end
    end

endmodule
