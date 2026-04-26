`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bank_accum
 * 作者: SonicBolt 团队
 * 日期: 2026-04-26
 * 版本: v1.2
 *
 * 功能概述:
 *   - 对 8 个输入 group 的部分和做归约，输出 4(out) x 4(spatial) 共 16 个 INT21。
 *
 * 运算复杂度分析:
 *   - 4ch/group x 4 spa = 16 个并行计算单元
 *   - 每个并行计算单元为两级流水加法树，每个加法树实现 8 x INT18 -> 1 x INT21 的归约。
 *   - 逻辑深度为: L1(1A) + reg + L2+L3(2A)
 *
 * 版本定位:
 *   - v1.1 为了降低综合复杂度，计算被拆成小单元 pwconv_tile_mac_reduce8_cell 并用 generate 展开。
 *   - v1.2 reduce8_cell 升级为 v2.0（L1→reg→L2+L3），内部增加 1 拍；本模块新增 valid 打拍以对齐，
 *     内部延迟从 1 拍增至 2 拍。
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
                
                // 将每个输出通道、每个空间位置对应的 8 个输入部分进行 8 -> 1 归约
                wire signed [20:0] accum_point;
                // v1.2: cell v2.0 内部有 1 拍流水，需接入 clk/rst_n
                pwconv_tile_mac_reduce8_cell u_reduce8_cell (
                    .clk(clk),
                    .rst_n(rst_n),
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

    // v1.2: 补偿 reduce8_cell v2.0 内部新增的 1 拍延迟 —— valid 额外打一拍
    reg in_valid_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_valid_d1 <= 1'b0;
        end else begin
            in_valid_d1 <= in_valid;
        end
    end

    // 将组合逻辑的计算结果打拍输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_accum_bus <= {(16*21){1'b0}};
            out_valid     <= 1'b0;
        end else begin
            out_valid <= in_valid_d1;
            if (in_valid_d1) begin
                out_accum_bus <= accum_bus_comb;
            end
        end
    end

endmodule
