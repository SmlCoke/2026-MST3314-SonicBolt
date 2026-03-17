`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_bias_add
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 功能概述:
 *   对 64 个卷积和执行 bias 广播相加。
 *
 * 设计说明:
 *   - bias_data_bus 中有 4 个 INT16，对应 4 个输出通道。
 *   - 每个 bias 会广播到该通道的 16 个 4x4 空间输出。
 *   - 输出仍然保持 64 个 INT32。
 */
module conv_tile_mac_bias_add (
    input  wire               clk,           // 时钟
    input  wire               rst_n,         // 低有效复位
    input  wire [2047:0]      in_sum_bus,    // 64 个 INT32 卷积和
    input  wire [4*16-1:0]    bias_data_bus, // 4 个 INT16 bias
    output reg  [2047:0]      out_accum_bus  // 加 bias 后的 64 个 INT32
);

    integer ch_idx;
    integer oy_idx;
    integer ox_idx;
    integer out_idx;
    reg signed [31:0] sum_val;
    reg signed [15:0] bias_val;
    reg signed [31:0] accum_val;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_accum_bus <= 2048'd0;
        end else begin
            for (ch_idx = 0; ch_idx < 4; ch_idx = ch_idx + 1) begin
                // 每个通道一个 bias 广播到 16 个输出位置
                bias_val = bias_data_bus[ch_idx*16 +: 16];
                for (oy_idx = 0; oy_idx < 4; oy_idx = oy_idx + 1) begin
                    for (ox_idx = 0; ox_idx < 4; ox_idx = ox_idx + 1) begin
                        out_idx = ch_idx * 16 + oy_idx * 4 + ox_idx;
                        sum_val = in_sum_bus[out_idx*32 +: 32];
                        accum_val = sum_val + bias_val;
                        // 索引顺序：先通道、再输出行、再输出列
                        out_accum_bus[out_idx*32 +: 32] <= $signed(accum_val);
                    end
                end
            end
        end
    end

endmodule
