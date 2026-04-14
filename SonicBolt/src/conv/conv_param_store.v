`timescale 1ns / 1ps
/*
 * 模块名称: conv_param_store
 * 作者: SonicBolt 团队
 * 日期: 2026-04-14
 * 版本: v2.2
 *
 * 功能概述:
 *   保存 Conv1 整层全部权重和偏置，并按 kernel row 直接输出到 MAC 的 row PE。
 *
 * 设计定位:
 *   - 当前 Conv1 层内部完整持有本层全部参数 SRAM。
 *   - 运行时按 group 读取参数切片，但存储体本身覆盖的是整层全部 32 个输出通道。
 *   - 这符合 SonicBolt 后续“各层各自持有本层完整参数 SRAM”的总体规则。
 *
 * 当前组织:
 *   - 11 个 weight bank，对应 11 个 kernel row
 *   - 每个 weight bank 深度 8，对应 group=0..7
 *   - 每个 weight word 宽度 224bit = 4(ch) x 7(col) x 8bit
 *   - 1 个 bias bank，深度 8，宽度 64bit = 4(ch) x 16bit
 *
 * 版本定位:
 *   - v2.1 引入了 Memory Compiler 生成的 SRAM 模块，重构了读写控制逻辑。
 *   - v2.2 删除了 SRAM 的写接口
 */
module conv_param_store (
    input  wire          clk,
    input  wire          rst_n,

    // ------------ 权重 SRAM 读控制信号 ------------
    input  wire          weight_rd_en,            // 权重读使能  
    input  wire [2:0]    weight_rd_group,         // 读取哪个 group 的权重，地址范围 0..7     

    // ------------ 偏置 SRAM 读控制信号 ------------
    input  wire          bias_rd_en,              // 偏置读使能
    input  wire [2:0]    bias_rd_group,           // 读取哪个 group 的偏置，地址范围 0..7   

    // ------------ SRAM 读出数据总线 ------------
    output wire [11*224-1:0] weight_data_bus,     // 4个卷积核的权重：4 x 11 x 7 x 8bit = 2464bit     
    output wire [63:0]   bias_data_bus            // 4个卷积核的偏置：4 x 16bit = 64bit
);

    // weight_rdata[g] : 第 g 个权重 bank 的同步读数据。
    wire [223:0] weight_rdata [0:10];
    wire [111:0] weight_rdata_lo [0:10];
    wire [111:0] weight_rdata_hi [0:10];
    // bias_rdata : 偏置 bank 的同步读数据。
    wire [63:0]  bias_rdata;

    // 每个 weight bank 各自独立的命中 / 使能 / 地址控制信号。
    wire [10:0] weight_bank_en;
    wire [2:0]  weight_bank_addr [0:10];
    wire [4:0]  weight_bank_macro_addr [0:10];

    // 偏置 bank 的访问控制信号。
    wire        bias_bank_en;
    wire [4:0]  bias_bank_addr;

    generate
        genvar g_weight;
        for (g_weight = 0; g_weight < 11; g_weight = g_weight + 1) begin : g_weight_bank
            // 每个 bank 只有两种访问来源：
            // 1. 运行时读：所有 bank 同时按当前 group 读
            // 2. 配置时写：只写命中的那个 bank
            assign weight_bank_en[g_weight]         = weight_rd_en;
            assign weight_bank_addr[g_weight]       = weight_rd_group;
            assign weight_bank_macro_addr[g_weight] = {2'b00, weight_bank_addr[g_weight]};

            // 读数据直接铺到展平总线中对应的 224bit 切片。
            assign weight_rdata[g_weight] = {weight_rdata_hi[g_weight], weight_rdata_lo[g_weight]};
            assign weight_data_bus[g_weight*224 +: 224] = weight_rdata[g_weight];

            S018V3EBCDSP_X8Y4D112_PR #(
            ) u_weight_bank_lo (
                .CLK(clk),
                .CEN(~weight_bank_en[g_weight]),
                .WEN(1'b1), // 只读不写
                .A(weight_bank_macro_addr[g_weight]),
                .D(112'b0), // 写入全零，实际不使用写功能
                .Q(weight_rdata_lo[g_weight])
            );

            S018V3EBCDSP_X8Y4D112_PR #(
            ) u_weight_bank_hi (
                .CLK(clk),
                .CEN(~weight_bank_en[g_weight]),
                .WEN(1'b1), // 只读不写
                .A(weight_bank_macro_addr[g_weight]),
                .D(112'b0), // 写入全零，实际不使用写功能
                .Q(weight_rdata_hi[g_weight])
            );
        end
    endgenerate

    // 当前只有 1 个 bias bank，因此只允许 bank=0 命中。
    assign bias_bank_en      = bias_rd_en;
    assign bias_bank_addr    = {3'b000, bias_rd_group};

    S018V3EBCDSP_X8Y4D64_PR #(
    ) u_bias_bank (
        .CLK(clk),
        .CEN(~bias_bank_en),
        .WEN(1'b1), // 只读不写
        .A(bias_bank_addr),
        .D(64'b0), // 写入全零，实际不使用写功能
        .Q(bias_rdata)
    );

    assign bias_data_bus = bias_rdata;

endmodule
