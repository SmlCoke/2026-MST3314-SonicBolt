`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_param_store
 * 作者: SonicBolt 团队
 * 日期: 2026-04-14
 * 版本: v1.1
 *
 * 功能概述:
 *   保存 PWConv 整层权重和偏置，并按输出 group 读出当前 token 所需切片
 *
 * 存储组织:
 *   - 8 个 weight bank，对应 8 个输出通道组，每组 4 个输出通道，即 4 个卷积核
 *   - 每个 weight bank 深度 8，即每个 bank 里有 8 个地址，这 8 个地址分别对应 8 个输入通道组
 *   - 每个 weight word = 4(in_channels) x 4(kernels) x INT8 = 128bit
 *   - 1 个 bias bank，深度 8，word = 4 x INT16 = 64bit
 *
 * 读写约定:
 *   - 写权重时: bank=输入 group、addr=输出 group
 *   - 读权重时: 8 个 bank 同时读取同一个输出 group 地址
 *   - 输出总线按输入 group 顺序拼接，供 MAC 做跨 group 归约
 *   - bias 只有 1 个 bank，因此 bank 端口仅保留接口对齐意义
 *
 * 版本定位:
 *   - v1.1 引入了 Memory Compiler 生成的 SRAM 模块，重构了读写控制逻辑。
 */
module pwconv_param_store (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          weight_rd_en,
    input  wire [2:0]    weight_rd_group,
    input  wire          bias_rd_en,
    input  wire [2:0]    bias_rd_group,

    output wire [32*4*8-1:0] weight_data_bus, // 4 通道 × 32 输入 = 128bit/通道 × 8 bank
    output wire [63:0]      bias_data_bus
);

    // weight_rdata[g] 保存“输入 group = g”这个 bank 当前读出的 128bit 权重切片
    wire [127:0] weight_rdata [0:7];
    wire [63:0]  bias_rdata;

    wire [7:0]  weight_bank_en;             // 读写访问的 weight bank 使能
    wire [4:0]  weight_bank_addr [0:7];

    wire        bias_bank_en;
    wire [4:0]  bias_bank_addr;

    generate
        genvar g_weight;
        for (g_weight = 0; g_weight < 8; g_weight = g_weight + 1) begin : g_weight_bank
            assign weight_bank_en[g_weight]      = weight_rd_en;
            assign weight_bank_addr[g_weight]    ={3'b0, weight_rd_group};

            // 按输入 group 顺序拼接总线：g=0..7 对应 in_group=0..7。
            assign weight_data_bus[g_weight*128 +: 128] = weight_rdata[g_weight];

            S018V3EBCDSP_X8Y4D128_PR u_weight_bank (
                .CLK(clk),
                .CEN(~weight_bank_en[g_weight]),
                .WEN(1'b1),
                .A(weight_bank_addr[g_weight]),
                .D(128'b0),
                .Q(weight_rdata[g_weight])
            );
        end
    endgenerate

    assign bias_bank_en = bias_rd_en;
    assign bias_bank_addr    = {3'b0, bias_rd_group};

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
