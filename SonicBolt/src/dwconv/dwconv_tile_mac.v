`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_tile_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-04-26
 * 版本: v1.1
 *
 * 功能概述:
 *   - 对一个 {pos, group} 输入 tile 计算完整的 DWConv 输出 tile。
 *
 * 当前角色:
 *   - 当前 dwconv 子系统的主计算模块。
 *   - 输入 4(ch)x4(row)x4(col)个INT8 的输入数据，3x4x3x8 的 weight 以及 4x16 的bias
 *   - 输出 4 个通道、每通道 2x2 空间位置的 INT32 累加结果。
 *
 * 版本定位:
 *   - v1.0 初始化
 *   - v1.1 row_mult v1.2 内部新增 product 寄存器(+1 拍)；本模块新增 stage2a meta/bias 打拍以对齐，
 *     总流水从 3 级增至 4 级。
 */
module dwconv_tile_mac (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位

    // ---------- 输入元数据 ----------
    input  wire                in_valid,        // 当前 token 有效
    input  wire                in_last,         // 当前 token 是否为整张图最后一个 token
    input  wire [3:0]          in_pos,          // 当前 token 的 pos 编号，范围 0~8
    input  wire [2:0]          in_group,        // 当前 token 的 group 编号，范围 0~7
    input  wire                in_fire,         // 通知第三层准备计算

    // ---------- 输入数据(总线) ----------
    input  wire [4*4*4*8-1:0]  in_data_bus,     // 当前 tile 的完整 4(ch)x4(row)x4(col)个INT8数据
    input  wire [3*4*3*8-1:0]  weight_data_bus, // 当前 group 的完整 3x4x3 INT8 权重
    input  wire [4*16-1:0]     bias_data_bus,   // 当前 group 的完整 4 个 INT16 偏置

    // ---------- 输出元数据 ----------
    output wire                out_valid,       // 输出累加 tile 有效
    output wire                out_last,        // 输出累加 tile 是否为最后一个 token
    output wire [3:0]          out_pos,         // 输出 tile 的 pos
    output wire [2:0]          out_group,       // 输出 tile 的 group
    output wire                out_fire,        // 输出的第三层启动信号

    // ---------- 输出数据 ----------
    output wire [4*2*2*32-1:0] out_accum_bus    // 4(ch) x 2(row) x 2(col) x INT32 的输出累加结果
);
    // ---------- stage1: 数据打拍 --------- 
    // 数据、权重、偏置的打拍已下沉到子模块内部
    // 元数据打拍结果
    wire                stage1_valid;      // stage1 out: 打一拍后的 valid
    wire                stage1_last;       // stage1 out: 打一拍后的 last
    wire [3:0]          stage1_pos;        // stage1 out: 打一拍后的 pos
    wire [2:0]          stage1_group;      // stage1 out: 打一拍后的 group
    wire                stage1_fire;       // stage1 out: 打一拍后的 fire

    // stage1: 偏置打拍结果
    wire [4*16-1:0]     stage1_bias_bus;

    // ---------- stage2a: 中间补偿级，对齐 row_mult v1.2 内部新增的 product 寄存器 ---------
    wire [4*16-1:0]     stage2a_bias_bus;
    wire                stage2a_valid;
    wire                stage2a_last;
    wire [3:0]          stage2a_pos;
    wire [2:0]          stage2a_group;
    wire                stage2a_fire;

    // ---------- stage2: 11 个 row_mult 单元计算结果 ---------
    // 4(ch) × 2(row) × 2(col) × 18(width) = 288bit
    wire [4*2*2*18-1:0]    row_sum_bus_0;
    wire [4*2*2*18-1:0]    row_sum_bus_1;
    wire [4*2*2*18-1:0]    row_sum_bus_2;

    // stage2_row_sum_bus 是连线关系，无组合逻辑开销
    wire [3*4*2*2*18-1:0]  stage2_row_sum_bus;

    // stage2: 偏置打拍结果
    wire [4*16-1:0]     stage2_bias_bus;

    // stage2: 元数据打拍结果
    wire                stage2_valid;
    wire                stage2_last;
    wire [3:0]          stage2_pos;
    wire [2:0]          stage2_group;
    wire                stage2_fire;

    // ---------- stage3: 64 个 row_add 单元计算结果 ---------
    // stage3: 元数据打拍结果
    wire                stage3_valid;
    wire                stage3_last;
    wire [3:0]          stage3_pos;
    wire [2:0]          stage3_group;
    wire                stage3_fire;

    // ---------------------------------------------------------------------
    // ------------------------- 第一级流水：stage1 --------------------------
    // - 偏置/元数据打拍，数据/权重打拍已下沉
    // ---------------------------------------------------------------------
    meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(in_valid),      // in: 当前 token 有效
        .in_last(in_last),        // in: 当前 token 是否为整张图最后一个 token
        .in_pos(in_pos),          // in: 当前 token 的 pos 编号，范围 0~8
        .in_group(in_group),      // in: 当前 token 的 group 编号，范围 0~7
        .in_fire(in_fire),        // in: 第二层启动信号

        // ---------- 输出元数据 ----------
        .out_valid(stage1_valid), // out: 打一拍后的 valid
        .out_last(stage1_last),   // out: 打一拍后的 last
        .out_pos(stage1_pos),     // out: 打一拍后的 pos
        .out_group(stage1_group), // out: 打一拍后的 group
        .out_fire(stage1_fire)    // out: 打一拍后的 fire
    );
    
    // stage2: bias 打拍
    bias_pipe u_bias_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(bias_data_bus),
        .out_bias_bus(stage1_bias_bus)
    );

    // ---------------------------------------------------------------------
    // ------------------------- 第二级流水：stage2 --------------------------
    // - 输入数据/权重的第一拍打拍（注意：这里是第一级流水）
    // - 4 个 channel 的 1 multiply + 1 add 并行计算单元
    // - 元数据(valid, last, pos, group, fire)打拍
    // ---------------------------------------------------------------------
    wire [4*2*4*8-1:0] row_window_data_0;   // 卷积核第一行对应的4通道输入
    wire [4*2*4*8-1:0] row_window_data_1;   // 卷积核第二行对应的4通道输入
    wire [4*2*4*8-1:0] row_window_data_2;   // 卷积核第三行对应的4通道输入

    assign row_window_data_0 = {in_data_bus[384 +: 64], in_data_bus[256 +: 64], in_data_bus[128 +: 64], in_data_bus[0 +: 64]};
    assign row_window_data_1 = {in_data_bus[(384 + 32) +: 64], in_data_bus[(256 + 32)+: 64], in_data_bus[(128 + 32) +: 64], in_data_bus[32 +: 64]};
    assign row_window_data_2 = {in_data_bus[(384 + 64) +: 64], in_data_bus[(256 + 64)+: 64], in_data_bus[(128 + 64) +: 64], in_data_bus[64 +: 64]};

    // 4个通道卷积核第一行对应的2(row)x2(col)次运算
    dwconv_tile_mac_row_mult u_mac_row_mult_0 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(row_window_data_0),
        .weight_row_data(weight_data_bus[4*3*8-1:0]),
        .out_row_sum_bus(row_sum_bus_0)
    );

    // 4个通道卷积核第二行对应的2(row)x2(col)次运算
    dwconv_tile_mac_row_mult u_mac_row_mult_1 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(row_window_data_1),
        .weight_row_data(weight_data_bus[2*4*3*8-1:4*3*8]),
        .out_row_sum_bus(row_sum_bus_1)
    );

    // 4个通道卷积核第三行对应的2(row)x2(col)次运算
    dwconv_tile_mac_row_mult u_mac_row_mult_2 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(row_window_data_2),
        .weight_row_data(weight_data_bus[3*4*3*8-1:2*4*3*8]),
        .out_row_sum_bus(row_sum_bus_2)
    );

    assign stage2_row_sum_bus = {row_sum_bus_2, row_sum_bus_1, row_sum_bus_0};

    // v1.1: stage2a —— 补偿 row_mult v1.2 内部新增的 product 寄存器延迟
    meta_pipe u_meta_pipe_stage2a (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .in_fire(stage1_fire),
        .out_valid(stage2a_valid),
        .out_last(stage2a_last),
        .out_pos(stage2a_pos),
        .out_group(stage2a_group),
        .out_fire(stage2a_fire)
    );

    bias_pipe u_bias_pipe_stage2a (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage1_bias_bus),
        .out_bias_bus(stage2a_bias_bus)
    );

    // stage2: 元数据打拍
    meta_pipe u_meta_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2a_valid),
        .in_last(stage2a_last),
        .in_pos(stage2a_pos),
        .in_group(stage2a_group),
        .in_fire(stage2a_fire),
        .out_valid(stage2_valid),
        .out_last(stage2_last),
        .out_pos(stage2_pos),
        .out_group(stage2_group),
        .out_fire(stage2_fire)
    );

    // stage2: bias 打拍
    bias_pipe u_bias_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage2a_bias_bus),
        .out_bias_bus(stage2_bias_bus)
    );


    // ---------------------------------------------------------------------
    // ------------------------- 第三级流水：stage3 -----------------------
    // - 16 组 INT18 * 3 + INT16 加法，做两级加法，得到 64 组 INT32 最终结果
    // - 元数据(valid, last, pos, group, fire)两拍
    // ---------------------------------------------------------------------

    // stage3 : 16个块，每一块计算 11 -> 1 的加法 (内部已打两拍)
    dwconv_tile_mac_row_add u_tile_mac_row_add (
        .clk(clk),
        .rst_n(rst_n),
        .in_row_sum_bus(stage2_row_sum_bus),
        .bias_data_bus(stage2_bias_bus),
        .out_sum_bus(out_accum_bus)
    );

    // stage3: 元数据打拍
    meta_pipe u_meta_pipe_stage3 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2_valid),
        .in_last(stage2_last),
        .in_pos(stage2_pos),
        .in_group(stage2_group),
        .in_fire(stage2_fire),
        .out_valid(stage3_valid),
        .out_last(stage3_last),
        .out_pos(stage3_pos),
        .out_group(stage3_group),
        .out_fire(stage3_fire)
    );


    // 综合后输出: 元数据传递给输出接口
    assign out_valid     = stage3_valid;
    assign out_last      = stage3_last;
    assign out_pos       = stage3_pos;
    assign out_group     = stage3_group;
    assign out_fire      = stage3_fire;

endmodule
