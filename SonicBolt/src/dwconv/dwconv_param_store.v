`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_param_store
 * 作者: SonicBolt 团队
 * 日期: 2026-04-14
 * 版本: v1.2
 *
 * 功能概述:
 *   保存 DWConv 整层全部权重和偏置，并按 kernel row 直接输出到 MAC 的 row PE。
 *
 * 设计定位:
 *   - 当前 DWConv 层内部完整持有本层全部参数 SRAM。
 *   - 运行时按 group 读取参数切片，但存储体本身覆盖的是整层全部 32 个输出通道。
 *
 * 当前组织:
 *   - 3 个 weight bank，对应 3 个 kernel row
 *   - 每个 weight bank 深度 8，对应 group=0..7
 *   - 每个 weight word 宽度 96bit = 4(ch) x 3(col) x 8bit
 *   - 1 个 bias bank，深度 8，宽度 64bit = 4(ch) x 16bit
 *
 * 版本定位:
 *   - v1.1 引入了 Memory Compiler 生成的 SRAM 模块，重构了读写控制逻辑。
 *   - v1.2 删除了所有 SRAM 写接口，改为在仿真测试时直接通过 $readmemh 初始化 SRAM 内容。
 *
 */
module dwconv_param_store (
    input  wire          clk,
    input  wire          rst_n,

    // ------------ 权重 SRAM 读控制信号 ------------
    input  wire          weight_rd_en,            // 权重读使能  
    input  wire [2:0]    weight_rd_group,         // 读取哪个 group 的权重，地址范围 0..7     

    // ------------ 偏置 SRAM 读控制信号 ------------
    input  wire          bias_rd_en,              // 偏置读使能
    input  wire [2:0]    bias_rd_group,           // 读取哪个 group 的偏置，地址范围 0..7   

    // ------------ SRAM 读出数据总线 ------------
    output wire [3*96-1:0] weight_data_bus,     // 4个卷积核的权重：4 x 3 x 8bit = 96bit     
    output wire [63:0]   bias_data_bus            // 4个卷积核的偏置：4 x 16bit = 64bit
);

    // weight_rdata[g] : 第 g 个权重 bank 的同步读数据。
    wire [95:0] weight_rdata [0:2];
    // bias_rdata : 偏置 bank 的同步读数据。
    wire [63:0]  bias_rdata;

    // 每个 weight bank 各自独立的命中 / 使能 / 地址控制信号。
    wire [2:0] weight_bank_en;
    wire [4:0] weight_bank_addr [0:2];

    // 偏置 bank 的访问控制信号。
    wire        bias_bank_en;
    wire [4:0]  bias_bank_addr;

    generate
        genvar g_weight;
        for (g_weight = 0; g_weight < 3; g_weight = g_weight + 1) begin : g_weight_bank
            // 每个 bank 只有两种访问来源：
            // 1. 运行时读：所有 bank 同时按当前 group 读
            // 2. 配置时写：只写命中的那个 bank
            assign weight_bank_en[g_weight]      = weight_rd_en ;
            assign weight_bank_addr[g_weight]    = {3'd0, weight_rd_group};

            // 读数据直接铺到展平总线中对应的 96bit 切片。
            assign weight_data_bus[g_weight*96 +: 96] = weight_rdata[g_weight];

            S018V3EBCDSP_X8Y4D96_PR u_weight_bank (
                .CLK(clk),
                .CEN(~weight_bank_en[g_weight]),
                .WEN(1'b1),  // 目前不支持运行时写入，因此写使能始终失效
                .A(weight_bank_addr[g_weight]),
                .D(96'b0),  // 运行时写入数据，目前不支持
                .Q(weight_rdata[g_weight])
            );
        end
    endgenerate

    // 当前只有 1 个 bias bank，因此只允许 bank=0 命中。
    assign bias_bank_en      = bias_rd_en;
    assign bias_bank_addr    = {3'd0, bias_rd_group};

    S018V3EBCDSP_X8Y4D64_PR u_bias_bank (
        .CLK(clk),
        .CEN(~bias_bank_en),
        .WEN(1'b1),
        .A(bias_bank_addr),
        .D(64'b0),
        .Q(bias_rdata)
    );

    assign bias_data_bus = bias_rdata;

endmodule
