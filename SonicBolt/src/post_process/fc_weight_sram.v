`timescale 1ns / 1ps
/*
 * 模块名称: fc_weight_sram
 * 作者: SonicBolt 团队
 * 日期: 2026-04-06
 * 版本: v1.1
 *
 * 功能概述:
 *   - 封装 FC 权重 SRAM 的读写仲裁与实例化。
 *   - 写优先: 写请求与计算读请求同拍到达时，优先写入。
 *
 * 版本定位:
 *  - v1.0: 基础功能实现，支持权重写入和读取
 *  - v1.1: 修复了 v1.0 的时序错误，确保下一个周期需要用到的参数这个周期生成地址信号
 */
module fc_weight_sram #(
    parameter integer WEIGHT_DEPTH = 72
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_fire,
    input  wire        in_valid,
    input  wire [3:0]  in_pos,
    input  wire [2:0]  in_group,

    input  wire        weight_wr_en,
    input  wire [6:0]  weight_wr_addr,// 72 地址空间
    input  wire [63:0] weight_wr_data,

    output wire [63:0] out_weight_rdata
);

    wire [6:0] token_addr;
    wire [6:0] next_token_addr;
    wire [6:0] weight_sram_addr;
    wire       weight_sram_en;
    wire       prefetch_first_word;
    wire       prefetch_next_word;

    assign token_addr = {in_pos, in_group};
    assign next_token_addr = token_addr + 7'd1;

    // fire 仅用于整帧启动时的首个权重预取，此时 valid 还未拉高。
    // 后续 token 连续到来时，使用当前 valid 对应的 pos/group 预取下一拍要用的权重，
    // 这样可以对齐同步 SRAM 的一拍读延迟，避免权重始终落后一个 token。
    assign prefetch_first_word = in_fire && !in_valid;
    assign prefetch_next_word  = in_valid && (token_addr != (WEIGHT_DEPTH - 1));

    // 当外部正在写权重时，仍保持写优先，避免读写同拍冲突。
    assign weight_sram_en   = weight_wr_en | prefetch_first_word | prefetch_next_word;
    assign weight_sram_addr = weight_wr_en ? weight_wr_addr :
                              (prefetch_first_word ? token_addr : next_token_addr);

    sram_sp #(
        .DATA_W(64),
        .DEPTH(WEIGHT_DEPTH),
        .ADDR_W(7)
    ) u_fc_weight_sram (
        .clk(clk),
        .rst_n(rst_n),
        .en(weight_sram_en),
        .wr_en(weight_wr_en),
        .addr(weight_sram_addr),
        .wdata(weight_wr_data),
        .rdata(out_weight_rdata)
    );

endmodule
