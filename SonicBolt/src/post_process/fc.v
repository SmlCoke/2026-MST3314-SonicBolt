`timescale 1ns / 1ps
/*
 * 模块名称: fc
 * 作者: SonicBolt 团队
 * 日期: 2026-04-14
 * 版本: v1.3
 *
 * 功能概述:
 *   - 执行全连接层 FC(2,288): INT8 输入向量 -> 2 路 INT32 累加。
 *   - 执行偏置叠加后重量化(M0=11, SHIFT_N=15)并饱和到 INT8。
 *   - 输出 2 路 INT8，供 Sigmoid 层查表。
 *
 * 设计说明:
 *   - 输入 token 为 4 路 INT8，配合 metadata 的 pos/group 还原 flatten 索引。
 *   - flatten 索引定义: idx = ch * 9 + pos，ch = group * 4 + lane。
 *   - 权重组织为 72x64 单端口 SRAM: addr = pos * 8 + group，每个 word 打包 8 个 INT8。
 *   - 低 32bit 为 class0 四路，高 32bit 为 class1 四路。
 *
 * 版本定位:
 *   - v1.0 完成基本功
 *   - v1.1 删除了部分冗余信号，并且强制使 MAC 单元和 SATURATE 单元保持一级流水，防止组合逻辑输出
 *   - v1.2 修正了 bias_wr_data 输入位宽错误
 *   - v1.3 删除了所有 SRAM 写接口，改为在仿真测试时直接通过 $readmemh 初始化 SRAM 内容。
 */
module fc #(
    parameter integer M0      = 11,
    parameter integer SHIFT_N = 15
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---------- 输入 metadata ----------
    input  wire        in_valid,
    input  wire        in_last,
    input  wire [3:0]  in_pos,
    input  wire [2:0]  in_group,
    input  wire        in_fire,

    // ---------- 输入数据 ----------
    input  wire [31:0] in_data_bus,// 4(ch) x INT8 = 32bit

    // ---------- FC 参数写接口 ----------
    // ---------- 输出 valid ----------
    output wire        out_valid,

    // ---------- 输出数据 ----------
    output wire [15:0] out_data_bus
);

    // 全连接层权重组数（一共288x2个权重，每组8个）
    localparam integer WEIGHT_DEPTH = 72;

    // 偏执数据输出总线
    wire signed [15:0] bias_cls0;
    wire signed [15:0] bias_cls1;

    // 权重数据输出总线，8x8bit = 64bit
    wire [63:0] weight_sram_rdata;

    wire               lane_valid;
    wire               lane_last;
    wire               lane_fire;
    wire signed [31:0] lane_delta_cls0;
    wire signed [31:0] lane_delta_cls1;

    wire               frame_valid;
    wire signed [31:0] frame_sum_cls0;
    wire signed [31:0] frame_sum_cls1;

    wire [63:0] stage0_data_bus;

    wire        stage1_valid;
    wire [63:0] stage1_rescale_bus;
    wire        stage2_valid;
    wire [15:0] stage2_data_bus;

    // 权重 SRAM 在 fire 到来时提前一拍预读，保证 valid 到来时权重已经对齐。
    // SRAM 地址构造： {pos. group} 定位权重组
    fc_weight_sram #(
        .WEIGHT_DEPTH(WEIGHT_DEPTH)
    ) u_fc_weight_sram (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_fire(in_fire),                   // in: 启动 SRAM 访问，提前预读
        .in_valid(in_valid),                 // in: 当前 token 有效，用于预取下一拍权重
        .in_pos(in_pos),                     // in: 通过 pos/group 定位权重地址
        .in_group(in_group),                 // in: 通过 pos/group 定位权重地址
        
        // ---------- 权重写接口 ---------- 

        // ---------- 输出数据 ----------
        .out_weight_rdata(weight_sram_rdata) // out: 预读的权重数据, 64bit
    );

    // bias 写入与存储。
    fc_bias_store u_fc_bias_store (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入 bias 写接口 ----------
        .bias_wr_en(1'b0),                  // in: runtime bias writes disabled
        .bias_wr_data(32'd0),               // in: testbench preloads bias memory directly

        // ---------- 输出 bias ----------
        .out_bias_cls0(bias_cls0),          // out: class0 bias, 16bit
        .out_bias_cls1(bias_cls1)           // out: class1 bias, 16bit
    );

    // 全连接层 4 路通道乘加运算，内置一级流水。
    fc_mac u_fc_mac (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(in_valid),                // in: 输入有效信号
        .in_last(in_last),                  // in: 输入最后一个 token 的标志
        .in_fire(in_fire),                  // in: 帧起始 fire，随 stage 一起打拍

        // ---------- 输入数据 ----------
        .in_data_bus(in_data_bus),          // in: 输入数据, 4(ch) x INT8 = 32bit
        .in_weight_bus(weight_sram_rdata),  // in: 输入权重, 8(ch) x INT8 = 64bit

        // ---------- 输出元数据 ----------
        .out_valid(lane_valid),             // out: 打拍后的有效信号
        .out_last(lane_last),               // out: 打拍后的最后一个 token 标志
        .out_fire(lane_fire),               // out: 打拍后的帧起始 fire

        // ---------- 输出数据 -----------
        .out_delta_cls0(lane_delta_cls0),   // out: class0 增量, INT32
        .out_delta_cls1(lane_delta_cls1)    // out: class1 增量, INT32
    );

    // 全连接层 帧级累加：维护累加状态，每个周期接收增量，8个周期计算完毕
    fc_frame_accum u_fc_frame_accum (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(lane_valid),                 // in: 打拍后的输入有效信号
        .in_last(lane_last),                   // in: 打拍后的最后一个 token 标志
        .in_fire(lane_fire),                   // in: 打拍后的 fire，保持“比 valid 早一拍”的关系

        // ---------- 输入两路增量数据 ----------
        .in_delta_cls0(lane_delta_cls0),       // in: class0 增量, INT32
        .in_delta_cls1(lane_delta_cls1),       // in: class1 增量, INT32

        // ---------- 输入偏置总线 ----------
        .in_bias_cls0(bias_cls0),              // in: class0 bias, 16bit
        .in_bias_cls1(bias_cls1),              // in: class1 bias, 16bit

        // ---------- 输出元数据 ----------
        .out_valid(frame_valid),     // out: 发出结果的 valid 信号

        // ---------- 输出数据 ----------
        .out_sum_cls0(frame_sum_cls0),         // out: class0 累加结果, INT32
        .out_sum_cls1(frame_sum_cls1)          // out: class1 累加结果, INT32
    );

    // FC 在 frame_accum 之后只需要保留最终累加结果与 valid。
    assign stage0_data_bus = {frame_sum_cls1, frame_sum_cls0};

    // Stage1: FC 专用 rescale（两路 INT32）
    fc_rescale #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_fc_rescale (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(frame_valid),
        .in_data_bus(stage0_data_bus),
        .out_valid(stage1_valid),
        .out_rescale_bus(stage1_rescale_bus)
    );

    // Stage2: 有符号饱和到 INT8（无 ReLU），做成一级时序流水
    fc_saturate u_fc_saturate (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_value_cls0(stage1_rescale_bus[31:0]),
        .in_value_cls1(stage1_rescale_bus[63:32]),
        .out_valid(stage2_valid),
        .out_data_bus(stage2_data_bus)
    );

    assign out_valid    = stage2_valid;
    assign out_data_bus = stage2_data_bus;

endmodule
