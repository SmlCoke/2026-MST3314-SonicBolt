`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_tile_mac_bias_add
 * 作者: SonicBolt 团队
 * 日期: 2026-04-12
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对 16 个 INT21 累加结果执行偏置叠加，输出 16 个 INT32。
 *
 * 输入组织:
 *   - in_accum_bus: 4(out) x 4(spatial) x INT21
 *   - in_bias_bus : 4(out) x INT16
 *
 * 运算复杂度分析: 
 *  - 4out x 4spa = 16 个并行计算单元
 *  - 每个并行计算单元为单级加法, INT21 + INT16 -> INT32
 *  - 逻辑深度为: 1A
 */
module pwconv_tile_mac_bias_add (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [16*21-1:0] in_accum_bus,
    input  wire [63:0]      in_bias_bus,
    output reg  [16*32-1:0] out_accum_bus
);

    integer out_idx;
    integer spatial_idx;

    reg signed [20:0] accum_value_21;
    reg signed [31:0] accum_value_32;
    reg signed [15:0] bias_value_16;
    reg signed [31:0] bias_value_32;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_accum_bus <= {(16*32){1'b0}};
        end else begin
            for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                for (spatial_idx = 0; spatial_idx < 4; spatial_idx = spatial_idx + 1) begin
                    // 每个部分和之和结果加上偏置
                    accum_value_21 = in_accum_bus[((out_idx*4 + spatial_idx) * 21) +: 21];
                    bias_value_16  = in_bias_bus[(out_idx * 16) +: 16];
                    accum_value_32 = {{11{accum_value_21[20]}}, accum_value_21};
                    bias_value_32  = {{16{bias_value_16[15]}}, bias_value_16};

                    out_accum_bus[((out_idx*4 + spatial_idx) * 32) +: 32] <=
                        accum_value_32 + bias_value_32;
                end
            end
        end
    end

endmodule
