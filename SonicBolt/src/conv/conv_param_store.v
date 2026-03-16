`timescale 1ns / 1ps
/*
 * 模块名称: conv_param_store
 * 功能概述: 保存 Conv1 整层全部权重和全部偏置的参数存储模块
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 设计定位:
 *   - 当前 Conv1 层内部完整持有本层全部参数 SRAM。
 *   - 运行时按 group 读取参数切片，但存储体本身覆盖的是整层全部 32 个输出通道。
 *   - 这符合 SonicBolt 后续“各层各自持有本层完整参数 SRAM”的总体规则。
 *
 * 权重组织:
 *   - 共 11 个 weight bank，对应 11 个 kernel_row。
 *   - 每个 bank 为 224bit x 8 depth。
 *   - word width = 4(ch) × 7(cow) × 8bit = 224bit
 *   - depth = 8 (8个 group, 每个 group 对应 4 个输出通道)
 *
 * 偏置组织:
 *   - 共 1 个 bias bank。
 *   - bank 宽度为 64bit，深度为 8。
 *   - word width = 4(ch) × 16bit = 64bit
 *   - depth = 8 (8个 group, 每个 group 对应 4 个输出通道)
 *
 * 接口说明:
 *   - 外部写口用于加载 Conv1 整层参数。
 *   - 读口用于运行时按 group 读取当前 token 所需的参数切片。
 *   - 所有 SRAM 例化端口均采用“信号对信号”的连接方式。
 */
module conv_param_store (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位

    // ------------ 权重 SRAM 写控制信号 ------------
    input  wire          weight_wr_en,     // 权重写使能
    input  wire [4:0]    weight_wr_bank,   // 写入哪个权重 bank，当前只使用 0..10
    input  wire [2:0]    weight_wr_addr,   // 写入哪个 group 地址，8 个 group 需要 3bit
    input  wire [223:0]  weight_wr_data,   // 权重写数据，4 x 7 x 8bit = 224bit

    // ------------ 偏置 SRAM 写控制信号 ------------
    input  wire          bias_wr_en,       // 偏置写使能
    input  wire          bias_wr_bank,     // 写入哪个偏置 bank，当前版本只允许 0
    input  wire [2:0]    bias_wr_addr,     // 写入哪个 group 地址
    input  wire [63:0]   bias_wr_data,     // 偏置写数据，4 x 16bit = 64bit

    // ------------ 权重 SRAM 读控制信号 ------------
    input  wire          weight_rd_en,     // 权重读使能
    input  wire [2:0]    weight_rd_group,  // 读取哪个 group 的权重，地址范围 0..7

    // ------------ 偏置 SRAM 读控制信号 ------------
    input  wire          bias_rd_en,       // 偏置读使能
    input  wire [2:0]    bias_rd_group,    // 读取哪个 group 的偏置，地址范围 0..7

    // ------------ SRAM 读出数据总线 ------------
    output wire [2463:0] weight_data_bus,  // 4 x 11 x 7 x 8bit = 2464bit
    output wire [63:0]   bias_data_bus     // 4 x INT16 = 64bit
);

    wire [223:0] weight_rdata [0:10];      // 11 个权重 bank 的读数据
    wire [63:0]  bias_rdata;               // 1 个偏置 bank 的读数据

    wire [10:0] weight_bank_sel_hit;       // 外部写口命中的权重 bank
    wire [10:0] weight_bank_en;            // 权重 bank 访问使能
    wire [10:0] weight_bank_wr_en;         // 权重 bank 写使能
    wire [2:0]  weight_bank_addr [0:10];   // 权重 bank 地址

    wire        bias_bank_sel_hit;         // 外部写口命中的偏置 bank
    wire        bias_bank_en;              // 偏置 bank 访问使能
    wire        bias_bank_wr_en;           // 偏置 bank 写使能
    wire [2:0]  bias_bank_addr;            // 偏置 bank 地址

    generate
        genvar g_weight;
        for (g_weight = 0; g_weight < 11; g_weight = g_weight + 1) begin : g_weight_bank
            // 如果写入，当前命中的是哪个 bank
            assign weight_bank_sel_hit[g_weight] = (weight_wr_bank == g_weight[4:0]);
            // 当前 bank 的写使能信号，必须是写操作且命中当前 bank
            assign weight_bank_wr_en[g_weight]   = weight_wr_en && weight_bank_sel_hit[g_weight];
            // 当前 bank 的使能信号，是否被读或被写
            assign weight_bank_en[g_weight]      = weight_rd_en || weight_bank_wr_en[g_weight];
            // 当前 bank 的访问地址来自两种：一种是读地址，读地址对于所有 bank 都是一样的；另一种是写地址。
            assign weight_bank_addr[g_weight]    = weight_rd_en ? weight_rd_group : weight_wr_addr;
            // 将当前 bank 的读数据放到对应的总线切片上
            // 总线切片格式：
            // [卷积核第0行，4个通道的 7 列数据] + [卷积核第1行，4个通道的 7 列数据] + ... + [卷积核第10行，4个通道的 7 列数据]
            assign weight_data_bus[g_weight*224 +: 224] = weight_rdata[g_weight];

            conv_sram_sp #(
                .DATA_W(224),
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

    // 如果写入 bank 0，那么命中，因为只有一个 bank
    assign bias_bank_sel_hit = ~bias_wr_bank;
    // 当前 bank 的写使能信号，必须是写操作且命中当前 bank
    assign bias_bank_wr_en   = bias_wr_en && bias_bank_sel_hit;
    // 当前 bank 的使能信号，是否被读或被写
    assign bias_bank_en      = bias_rd_en || bias_bank_wr_en;
    // 当前 bank 的访问地址来自两种：一种是读地址；另一种是写地址。
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
