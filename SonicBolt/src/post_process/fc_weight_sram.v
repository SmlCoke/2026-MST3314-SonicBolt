`timescale 1ns / 1ps
/*
 * 模块名称: fc_weight_sram_if
 * 作者: SonicBolt 团队
 * 日期: 2026-04-05
 * 版本: v1.0
 *
 * 功能概述:
 *   - 封装 FC 权重 SRAM 的读写仲裁与实例化。
 *   - 写优先: 写请求与计算读请求同拍到达时，优先写入。
 */
module fc_weight_sram_if #(
    parameter integer WEIGHT_DEPTH = 72
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_fire,
    input  wire [3:0]  in_pos,
    input  wire [2:0]  in_group,

    input  wire        weight_wr_en,
    input  wire [6:0]  weight_wr_addr,// 72 地址空间
    input  wire [63:0] weight_wr_data,

    output wire [63:0] out_weight_rdata
);

    wire [6:0] token_addr;
    wire [6:0] weight_sram_addr;
    wire       weight_sram_en;

    assign token_addr = {in_pos, in_group};

    // fire 信号会比下一拍 valid 更早到达，因此在这一拍启动权重预读。
    // 当外部正在写权重时，仍保持写优先，避免读写同拍冲突。
    assign weight_sram_en   = weight_wr_en | in_fire;
    assign weight_sram_addr = weight_wr_en ? weight_wr_addr : token_addr;

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
