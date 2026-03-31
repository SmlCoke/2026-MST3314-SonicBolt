`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_param_store
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 *
 * 功能概述:
 *   保存 PWConv 整层权重和偏置，并按输出 group 读出当前 token 所需切片
 *
 * 存储组织:
 *   - 8 个 weight bank，对应 8 个输入通道组，每组 4 个输入通道，即 4 个卷积核
 *   - 每个 weight bank 深度 8，即每个 bank 里有 8 个地址，这 8 个地址分别对应 8 个输出通道组
 *   - 每个 weight word = 4(out) x 4(in) x INT8 = 128bit
 *   - 1 个 bias bank，深度 8，word = 4 x INT16 = 64bit
 *
 * 读写约定:
 *   - 写权重时: bank = 输入 group! addr = 输出 group!
 *   - 读权重时: 8 个 bank 同时读取同一个输出 group 地址
 *   - bias 只有 1 个 bank，因此 bank 端口仅保留接口对齐意义
 */
module pwconv_param_store (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          weight_wr_en,
    input  wire [2:0]    weight_wr_bank, // 0..7 对应输入 group 0..7
    input  wire [2:0]    weight_wr_addr, // 0..7 对应输出 group 0..7
    input  wire [127:0]  weight_wr_data, // 4(out) x 4(in) x INT8 = 128bit

    input  wire          bias_wr_en,
    input  wire          bias_wr_bank,
    input  wire [2:0]    bias_wr_addr,
    input  wire [63:0]   bias_wr_data,

    input  wire          weight_rd_en,
    input  wire [2:0]    weight_rd_group,
    input  wire          bias_rd_en,
    input  wire [2:0]    bias_rd_group,

    output wire [8*128-1:0] weight_data_bus, // 4 通道 × 32 输入 = 128bit/通道 × 8 bank
    output wire [63:0]      bias_data_bus
);

    // weight_rdata[g] 保存“输入 group = g”这个 bank 当前读出的 128bit 权重切片
    wire [127:0] weight_rdata [0:7];
    wire [63:0]  bias_rdata;

    wire [7:0]  weight_bank_sel_hit;// 写访问的 weight bank 
    wire [7:0]  weight_bank_en;// 读写访问的 weight bank 使能
    wire [7:0]  weight_bank_wr_en;// 写访问的 weight bank 地址；读访问时所有 bank 地址相同
    wire [2:0]  weight_bank_addr [0:7];

    wire        bias_bank_sel_hit;
    wire        bias_bank_en;
    wire        bias_bank_wr_en;
    wire [2:0]  bias_bank_addr;

    generate
        genvar g_weight;
        for (g_weight = 0; g_weight < 8; g_weight = g_weight + 1) begin : g_weight_bank
            // 写按 bank 顺序；读口则让所有 bank 对同一地址并行读取，送入MAC，MAC 内部再根据输入 group 选择对应的 weight 切片
            assign weight_bank_sel_hit[g_weight] = (weight_wr_bank == g_weight[2:0]);
            assign weight_bank_wr_en[g_weight]   = weight_wr_en && weight_bank_sel_hit[g_weight];
            assign weight_bank_en[g_weight]      = weight_rd_en || weight_bank_wr_en[g_weight];
            assign weight_bank_addr[g_weight]    = weight_rd_en ? weight_rd_group : weight_wr_addr;

            // 按 bank 顺序拼接成总线，供后级 MAC 统一取数
            assign weight_data_bus[g_weight*128 +: 128] = weight_rdata[g_weight];

            conv_sram_sp #(
                .DATA_W(128),
                .DEPTH(8),
                .ADDR_W(3)
            ) u_weight_bank (
                .clk(clk),
                .rst_n(rst_n),
                .en(weight_bank_en[g_weight]),
                .wr_en(weight_bank_wr_en[g_weight]),
                .addr(weight_bank_addr[g_weight]),
                .wdata(weight_wr_data),
                .rdata(weight_rdata[g_weight])
            );
        end
    endgenerate

    // bias 目前只用 1 个 bank，bias_wr_bank 为 0 时才允许写入
    assign bias_bank_sel_hit = ~bias_wr_bank;
    assign bias_bank_wr_en   = bias_wr_en && bias_bank_sel_hit;
    assign bias_bank_en      = bias_rd_en || bias_bank_wr_en;
    assign bias_bank_addr    = bias_rd_en ? bias_rd_group : bias_wr_addr;

    conv_sram_sp #(
        .DATA_W(64),
        .DEPTH(8),
        .ADDR_W(3)
    ) u_bias_bank (
        .clk(clk),
        .rst_n(rst_n),
        .en(bias_bank_en),
        .wr_en(bias_bank_wr_en),
        .addr(bias_bank_addr),
        .wdata(bias_wr_data),
        .rdata(bias_rdata)
    );

    assign bias_data_bus = bias_rdata;

endmodule
