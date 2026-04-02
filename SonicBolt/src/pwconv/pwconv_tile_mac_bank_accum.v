`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bank_accum
 * 作者: SonicBolt 团队
 * 日期: 2026-04-01
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对 8 个输入 group 局部和做归约，输出 4(out) x 4(spatial) 的 16 个 INT21 结果。
 */
module pwconv_tile_mac_bank_accum (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             in_valid,
    input  wire [128*18-1:0] in_partial_bus,
    output reg              out_valid,
    output reg  [16*21-1:0] out_accum_bus
);

    integer out_idx;
    integer spatial_idx;

    reg signed [17:0] partial_0;
    reg signed [17:0] partial_1;
    reg signed [17:0] partial_2;
    reg signed [17:0] partial_3;
    reg signed [17:0] partial_4;
    reg signed [17:0] partial_5;
    reg signed [17:0] partial_6;
    reg signed [17:0] partial_7;

    reg signed [18:0] sum_l1_0;
    reg signed [18:0] sum_l1_1;
    reg signed [18:0] sum_l1_2;
    reg signed [18:0] sum_l1_3;
    reg signed [19:0] sum_l2_0;
    reg signed [19:0] sum_l2_1;
    reg signed [20:0] accum_sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_accum_bus <= {(16*21){1'b0}};
            out_valid    <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                    for (spatial_idx = 0; spatial_idx < 4; spatial_idx = spatial_idx + 1) begin
                        // spatial 位置固定，输出通道固定，8组部分和进行求和
                        partial_0 = in_partial_bus[((0*16 + out_idx*4 + spatial_idx) * 18) +: 18];
                        partial_1 = in_partial_bus[((1*16 + out_idx*4 + spatial_idx) * 18) +: 18];
                        partial_2 = in_partial_bus[((2*16 + out_idx*4 + spatial_idx) * 18) +: 18];
                        partial_3 = in_partial_bus[((3*16 + out_idx*4 + spatial_idx) * 18) +: 18];
                        partial_4 = in_partial_bus[((4*16 + out_idx*4 + spatial_idx) * 18) +: 18];
                        partial_5 = in_partial_bus[((5*16 + out_idx*4 + spatial_idx) * 18) +: 18];
                        partial_6 = in_partial_bus[((6*16 + out_idx*4 + spatial_idx) * 18) +: 18];
                        partial_7 = in_partial_bus[((7*16 + out_idx*4 + spatial_idx) * 18) +: 18];

                        sum_l1_0 = {{1{partial_0[17]}}, partial_0} + {{1{partial_1[17]}}, partial_1};
                        sum_l1_1 = {{1{partial_2[17]}}, partial_2} + {{1{partial_3[17]}}, partial_3};
                        sum_l1_2 = {{1{partial_4[17]}}, partial_4} + {{1{partial_5[17]}}, partial_5};
                        sum_l1_3 = {{1{partial_6[17]}}, partial_6} + {{1{partial_7[17]}}, partial_7};

                        sum_l2_0 = {{1{sum_l1_0[18]}}, sum_l1_0} + {{1{sum_l1_1[18]}}, sum_l1_1};
                        sum_l2_1 = {{1{sum_l1_2[18]}}, sum_l1_2} + {{1{sum_l1_3[18]}}, sum_l1_3};
                        accum_sum = {{1{sum_l2_0[19]}}, sum_l2_0} + {{1{sum_l2_1[19]}}, sum_l2_1};

                        out_accum_bus[((out_idx*4 + spatial_idx) * 21) +: 21] <= accum_sum;
                    end
                end
            end
        end
    end

endmodule
