`timescale 1ns / 1ps
/*
 * 模块名称: conv_rescale_relu
 * 功能概述: 对 Conv1 的 4ch x 4x4 INT32 累加结果进行重量化、ReLU 和 INT8 饱和
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 当前角色:
 *   - 主通路量化与激活模块。
 *   - 将 conv_tile_mac 产生的 64 个 INT32 值压缩成 64 个 INT8 值。
 *
 * 位宽说明:
 *   - 输入 2048bit  = 4 x 4 x 4 x 32bit
 *   - 输出 512bit   = 4 x 4 x 4 x 8bit
 *   - 乘法级输出为 3072bit = 64 x 48bit
 *
 * 原有流水说明保留:
 *   - 第一级: INT32 x M0
 *   - 第二级: 舍入、算术右移、ReLU、饱和到 INT8
 *
 * 更新说明:
 *   - 当前版本中，本模块主要负责流水级拼接，具体计算下沉到子模块。
 *   - 当前实际划分为 3 级:
 *       1. conv_rescale_mul_stage
 *       2. conv_rescale_shift_stage
 *       3. conv_relu_saturate_stage
 */
module conv_rescale_relu #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,             // 时钟
    input  wire          rst_n,           // 低有效复位

    // ---------- 输入元数据 -----------
    input  wire          in_valid,        // 输入 tile 有效
    input  wire          in_last,         // 输入 tile 是否为最后一个 token
    input  wire [3:0]    in_pos,          // 输入 tile 的 pos
    input  wire [2:0]    in_group,        // 输入 tile 的 group

    // ---------- 输入数据 -----------
    input  wire [2047:0] in_data_bus,     // 64 个 INT32 累加值

    // ---------- 输出元数据 ---------
    output wire          out_valid,       // 输出量化 tile 有效
    output wire          out_last,        // 输出量化 tile 是否为最后一个 token
    output wire [3:0]    out_pos,         // 输出 tile 的 pos
    output wire [2:0]    out_group,       // 输出 tile 的 group

    // ----------- 输出数据 ----------
    output wire [511:0]  out_data_bus     // 64 个 INT8 输出值
);

    // 3072 = 4 x 4 x 4 x 48 = 64 x 48
    wire [3071:0] stage1_mult_bus;  // 第一级乘法结果，64 个 INT48
    // 2048 = 4 x 4 x 4 x 32
    wire [2047:0] stage2_shift_bus; // 第二级右移结果，64 个 INT32

    // stage1: 元数据的打拍输出
    wire stage1_valid;
    wire stage1_last;
    wire [3:0] stage1_pos;
    wire [2:0] stage1_group;

    // stage2: 元数据的打拍输出
    wire stage2_valid;
    wire stage2_last;
    wire [3:0] stage2_pos;
    wire [2:0] stage2_group;

    // stage3: 元数据的打拍输出
    wire stage3_valid;
    wire stage3_last;
    wire [3:0] stage3_pos;
    wire [2:0] stage3_group;

    // ---------------------------------------------------------------------
    // ------------------------- 第一级流水：stage1 --------------------------
    // - 64 个 INT32 输入乘以 M0，得到 64 个 INT48 输出
    // - 元数据(valid, last, pos, group)打拍
    // ---------------------------------------------------------------------
    // stage1: 64 个 INT32 输入乘以 M0，得到 64 个 INT48 输出
    conv_rescale_mul_stage #(
        .M0(M0)
    ) u_conv_rescale_mul_stage (
        .clk(clk),
        .rst_n(rst_n),
        .in_data_bus(in_data_bus),
        .out_mult_bus(stage1_mult_bus)
    );

    // stage1: 元数据打拍
    conv_tile_mac_meta_pipe u_rescale_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        // 输入元数据
        .in_valid(in_valid),
        .in_last(in_last),
        .in_pos(in_pos),
        .in_group(in_group),
        // 输出元数据
        .out_valid(stage1_valid),
        .out_last(stage1_last),
        .out_pos(stage1_pos),
        .out_group(stage1_group)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第二级流水：stage2 --------------------------
    // - 64 个 INT48 进行移位
    // - 元数据(valid, last, pos, group)打拍
    // ---------------------------------------------------------------------
    // stage2: 64 个 INT48 进行移位，得到 64 个 INT32 输出
    conv_rescale_shift_stage #(
        .SHIFT_N(SHIFT_N)
    ) u_conv_rescale_shift_stage (
        .clk(clk),
        .rst_n(rst_n),
        .in_mult_bus(stage1_mult_bus),
        .out_shift_bus(stage2_shift_bus)
    );

    // stage2: 元数据打拍
    conv_tile_mac_meta_pipe u_rescale_meta_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .out_valid(stage2_valid),
        .out_last(stage2_last),
        .out_pos(stage2_pos),
        .out_group(stage2_group)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第三级流水：stage3 --------------------------
    // - 64 个 INT48 进行移位
    // - 元数据(valid, last, pos, group)打拍
    // ---------------------------------------------------------------------
    // stage3: 64 个 INT32 进行 ReLU 和 INT8 饱和阶段
    conv_relu_saturate_stage u_conv_relu_saturate_stage (
        .clk(clk),
        .rst_n(rst_n),
        .in_shift_bus(stage2_shift_bus),
        .out_data_bus(out_data_bus)
    );

    // stage3: 元数据打拍
    conv_tile_mac_meta_pipe u_rescale_meta_pipe_stage3 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2_valid),
        .in_last(stage2_last),
        .in_pos(stage2_pos),
        .in_group(stage2_group),
        .out_valid(stage3_valid),
        .out_last(stage3_last),
        .out_pos(stage3_pos),
        .out_group(stage3_group)
    );

    assign out_valid = stage3_valid;
    assign out_last  = stage3_last;
    assign out_pos   = stage3_pos;
    assign out_group = stage3_group;

endmodule
