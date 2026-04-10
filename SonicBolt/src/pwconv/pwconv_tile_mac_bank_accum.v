`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bank_accum
 * 作者: SonicBolt 团队
 * 日期: 2026-04-10
 * 版本: v1.1
 *
 * 功能概述:
 *   - 对 8 个输入 group 的部分和做归约，输出 4(out) x 4(spatial) 共 16 个 INT21。
 *
 * 设计说明:
 *   - 组合归约单元拆分为 pwconv_tile_mac_reduce8_cell。
 *   - 保持原接口语义：out_valid 与 in_valid 同拍；仅在 in_valid=1 时更新 out_accum_bus。
 */
module pwconv_tile_mac_bank_accum (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire [128*18-1:0]  in_partial_bus,
    output reg                out_valid,
    output reg  [16*21-1:0]   out_accum_bus
);

    wire [16*21-1:0] accum_bus_comb;

    genvar g_out;
    genvar g_spatial;
    generate
        for (g_out = 0; g_out < 4; g_out = g_out + 1) begin : G_OUT
            for (g_spatial = 0; g_spatial < 4; g_spatial = g_spatial + 1) begin : G_SPATIAL
                localparam integer IDX = g_out * 4 + g_spatial;

                wire signed [20:0] accum_point;
                pwconv_tile_mac_reduce8_cell u_reduce8_cell (
                    .partial_0(in_partial_bus[((0*16 + IDX) * 18) +: 18]),
                    .partial_1(in_partial_bus[((1*16 + IDX) * 18) +: 18]),
                    .partial_2(in_partial_bus[((2*16 + IDX) * 18) +: 18]),
                    .partial_3(in_partial_bus[((3*16 + IDX) * 18) +: 18]),
                    .partial_4(in_partial_bus[((4*16 + IDX) * 18) +: 18]),
                    .partial_5(in_partial_bus[((5*16 + IDX) * 18) +: 18]),
                    .partial_6(in_partial_bus[((6*16 + IDX) * 18) +: 18]),
                    .partial_7(in_partial_bus[((7*16 + IDX) * 18) +: 18]),
                    .accum_sum(accum_point)
                );

                assign accum_bus_comb[(IDX * 21) +: 21] = accum_point;
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_accum_bus <= {(16*21){1'b0}};
            out_valid     <= 1'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                out_accum_bus <= accum_bus_comb;
            end
        end
    end

endmodule
