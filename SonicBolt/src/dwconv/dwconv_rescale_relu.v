`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_rescale_relu
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 *
 * 功能概述: 
 *   对 DWConv 的 4ch x 2(row) x 2(col) x INT32 累加结果进行重量化、ReLU 和 INT8 饱和
 *
 * 当前角色:
 *   - 主通路量化与激活模块。
 *   - 将 conv_tile_mac 产生的 16 个 INT32 值压缩成 16 个 INT8 值。
 *
 * 位宽说明:
 *   - 输入 512bit  = 4 x 2 x 2 x 32bit
 *   - 输出 128bit   = 4 x 2 x 2 x 8bit
 *   - 乘法级输出为 768bit = 16 x 48bit
 *
 * 原有流水说明保留:
 *   - 第一级: INT32 x M0，移位
 *   - 第二级: ReLU、饱和到 INT8
 *
 * 版本定位:
 */
module dwconv_rescale_relu #(
    parameter integer M0      = 59,
    parameter integer SHIFT_N = 11
) (
    input  wire          clk,             // 时钟
    input  wire          rst_n,           // 低有效复位

    // ---------- 输入元数据 -----------
    input  wire          in_valid,        // 输入 tile 有效
    input  wire          in_last,         // 输入 tile 是否为最后一个 token
    input  wire [3:0]    in_pos,          // 输入 tile 的 pos
    input  wire [2:0]    in_group,        // 输入 tile 的 group
    input  wire          in_fire,         // 输入的第三层启动信号

    // ---------- 输入数据 -----------
    input  wire [511:0] in_data_bus,     // 64 个 INT32 累加值

    // ---------- 输出元数据 ---------
    output wire          out_valid,       // 输出量化 tile 有效
    output wire          out_last,        // 输出量化 tile 是否为最后一个 token
    output wire [3:0]    out_pos,         // 输出 tile 的 pos
    output wire [2:0]    out_group,       // 输出 tile 的 group
    output wire          out_fire,        // 输出的第三层启动信号

    // ----------- 输出数据 ----------
    output wire [127:0]  out_data_bus     // 64 个 INT8 输出值
);

    // 512 = 4 x 2 x 2 x 32
    wire [511:0] stage1_rescale_bus; // 第一级量化结果，16 个 INT32

    // stage1: 元数据的打拍输出
    wire       stage1_valid;
    wire       stage1_last;
    wire [3:0] stage1_pos;
    wire [2:0] stage1_group;
    wire       stage1_fire;

    // stage2: 元数据的打拍输出
    wire       stage2_valid;
    wire       stage2_last;
    wire [3:0] stage2_pos;
    wire [2:0] stage2_group;
    wire       stage2_fire;

    // ---------------------------------------------------------------------
    // ------------------------- 第一级流水：stage1 --------------------------
    // - 16 个 INT32 输入乘以 M0，得到 16 个 INT48 输出，然后进行移位，得到 16 个 INT32 输出
    // - 元数据(valid, last, pos, group)打拍
    // ---------------------------------------------------------------------
    // stage1: 16 个 INT32 输入乘以 M0，得到 16 个 INT48 输出，然后进行移位，得到 16 个 INT32 输出
    dwconv_rescale #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_dwconv_rescale (
        .clk(clk),
        .rst_n(rst_n),
        .in_data_bus(in_data_bus),
        .out_rescale_bus(stage1_rescale_bus)
    );

    // stage1: 元数据打拍
    dwconv_tile_meta_pipe u_rescale_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        // 输入元数据
        .in_valid(in_valid),
        .in_last(in_last),
        .in_pos(in_pos),
        .in_group(in_group),
        .in_fire(in_fire),
        // 输出元数据
        .out_valid(stage1_valid),
        .out_last(stage1_last),
        .out_pos(stage1_pos),
        .out_group(stage1_group),
        .out_fire(stage1_fire)
    );


    // ---------------------------------------------------------------------
    // ------------------------- 第二级流水：stage2 --------------------------
    // - 16 个 INT32 进行 ReLU 和饱和截断
    // - 元数据(valid, last, pos, group)打拍
    // ---------------------------------------------------------------------
    // stage2: 16 个 INT32 进行 ReLU 和 INT8 饱和阶段
    dwconv_relu_saturate u_dwconv_relu_saturate (
        .clk(clk),
        .rst_n(rst_n),
        .in_shift_bus(stage1_rescale_bus),
        .out_data_bus(out_data_bus)
    );

    // stage2: 元数据打拍
    dwconv_tile_meta_pipe u_rescale_meta_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .in_fire(stage1_fire),
        .out_valid(stage2_valid),
        .out_last(stage2_last),
        .out_pos(stage2_pos),
        .out_group(stage2_group),
        .out_fire(stage2_fire)
    );

    assign out_valid = stage2_valid;
    assign out_last  = stage2_last;
    assign out_pos   = stage2_pos;
    assign out_group = stage2_group;
    assign out_fire  = stage2_fire;

endmodule
