`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-03-18
 * 版本: v2.0
 *
 * 功能概述:
 *   对一个 {pos, group} token 计算完整的 Conv1 输出 tile。
 *
 * 当前角色:
 *   - 当前 conv 子系统的主计算模块。
 *   - 输入一个 14x10 输入窗口、当前 group 的完整 4x11x7 权重和 4 个 bias。
 *   - 输出 4 个通道、每通道 4x4 空间位置的 INT32 累加结果。
 *
 * 位宽说明:
 *   - pos_window_data : 14(row) x 10(col) x 8bit  = 1120bit
 *   - weight_data_bus : 11(row) x 4(ch) x 7(col) x 8bit = 2464bit
 *   - bias_data_bus   : 4(ch) x 16bit = 64bit
 *   - out_accum_bus   : 4(ch) x 4(row) x 4(col) x 32bit = 2048bit
 *
 * 索引规则:
 *   - 输入窗口像素:
 *       (待补充)
 *   - 权重:
 *       (待补充)
 *   - 输出:
 *       out_idx = ch * 16 + oy * 4 + ox
 *
 * 更新说明:
 *   - 当前版本中，本模块不再在单个 always 中直接完成 77 次 MAC。
 *   - 当前版本中，本模块主要负责流水级拼接，具体计算下沉到子模块。
 *   - 当前流水拆分为:
 *       1. input_stage
 *       2. 11 个 row_mult
 *       3. row_reduce_row_add
 */
module conv_tile_mac (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位

    // ---------- 输入元数据 ----------
    input  wire                in_valid,        // 当前 token 有效
    input  wire                in_last,         // 当前 token 是否为整张图最后一个 token
    input  wire [3:0]          in_pos,          // 当前 token 的 pos 编号，范围 0~8
    input  wire [2:0]          in_group,        // 当前 token 的 group 编号，范围 0~7

    // ---------- 输入数据(总线) ----------
    input  wire [14*10*8-1:0]  pos_window_data, // 14x10x8bit 输入窗口
    input  wire [11*4*7*8-1:0] weight_data_bus, // 当前 group 的完整 11x4x7 INT8 权重
    input  wire [4*16-1:0]     bias_data_bus,   // 当前 group 的完整 4 个 INT16 偏置

    // ---------- 输出元数据 ----------
    output wire                out_valid,       // 输出累加 tile 有效
    output wire                out_last,        // 输出累加 tile 是否为最后一个 token
    output wire [3:0]          out_pos,         // 输出 tile 的 pos
    output wire [2:0]          out_group,       // 输出 tile 的 group

    // ---------- 输出数据 ----------
    output wire [4*4*4*32-1:0] out_accum_bus    // 4(ch) x 4(row) x 4(col) x INT32 的输出累加结果
);
    // ---------- stage1: 数据打拍 --------- 
    // 输入数据打拍结果
    wire [14*10*8-1:0]  stage1_pos_window; // stage1 out: 寄存器打一拍后的完整输入窗口
    wire [4*11*7*8-1:0] stage1_weight_bus; // stage1 out: 寄存器打一拍后的完整权重总线
    wire [4*16-1:0]     stage1_bias_bus;   // stage1 out: 寄存器打一拍后的偏置总线

    // 元数据打拍结果
    wire                stage1_valid;      // stage1 out: 打一拍后的 valid
    wire                stage1_last;       // stage1 out: 打一拍后的 last
    wire [3:0]          stage1_pos;        // stage1 out: 打一拍后的 pos
    wire [2:0]          stage1_group;      // stage1 out: 打一拍后的 group


    // ---------- stage2: 11 个 row_mult 单元计算结果 ---------
    // 4(ch) × 4(row) × 4(col) × 19(width) = 1216bit
    wire [4*4*4*19-1:0]       row_sum_bus_0;
    wire [4*4*4*19-1:0]       row_sum_bus_1;
    wire [4*4*4*19-1:0]       row_sum_bus_2;
    wire [4*4*4*19-1:0]       row_sum_bus_3;
    wire [4*4*4*19-1:0]       row_sum_bus_4;
    wire [4*4*4*19-1:0]       row_sum_bus_5;
    wire [4*4*4*19-1:0]       row_sum_bus_6;
    wire [4*4*4*19-1:0]       row_sum_bus_7;
    wire [4*4*4*19-1:0]       row_sum_bus_8;
    wire [4*4*4*19-1:0]       row_sum_bus_9;
    wire [4*4*4*19-1:0]       row_sum_bus_10;
    
    // stage2_row_sum_bus 是连线关系，无组合逻辑开销
    wire [11*4*4*4*19-1:0]  stage2_row_sum_bus;
    
    // stage2: 偏置打拍结果
    wire [63:0]         stage2_bias_bus;
    
    // stage2: 元数据打拍结果
    wire                stage2_valid;
    wire                stage2_last;
    wire [3:0]          stage2_pos;
    wire [2:0]          stage2_group;

    wire                stage3_valid;
    wire                stage3_last;
    wire [3:0]          stage3_pos;
    wire [2:0]          stage3_group;


    // ---------------------------------------------------------------------
    // ------------------------- 第一级流水：stage1 --------------------------
    // - 输入数据(input, weight, bias)打拍
    // - 元数据(valid, last, pos, group)打拍
    // ---------------------------------------------------------------------

    conv_tile_mac_input_stage u_conv_tile_mac_input_stage (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入数据(总线形式) ----------
        .in_pos_window(pos_window_data),   // in: 14x10x8bit 输入窗口
        .in_weight_bus(weight_data_bus),   // in: 当前 group 的完整权重总线
        .in_bias_bus(bias_data_bus),       // in: 当前 group 的 4 个 INT16 偏置

        // ---------- 寄存器打拍输出 ----------
        .out_pos_window(stage1_pos_window), // out: 打一拍后的窗口
        .out_weight_bus(stage1_weight_bus), // out: 打一拍后的权重总线
        .out_bias_bus(stage1_bias_bus)      // out: 打一拍后的偏置总线
    );

    conv_tile_mac_meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(in_valid),      // in: 当前 token 有效
        .in_last(in_last),        // in: 当前 token 是否为整张图最后一个 token
        .in_pos(in_pos),          // in: 当前 token 的 pos 编号，范围 0~8
        .in_group(in_group),      // in: 当前 token 的 group 编号，范围 0~7

        // ---------- 输出元数据 ----------
        .out_valid(stage1_valid), // out: 打一拍后的 valid
        .out_last(stage1_last),   // out: 打一拍后的 last
        .out_pos(stage1_pos),     // out: 打一拍后的 pos
        .out_group(stage1_group)  // out: 打一拍后的 group
    );
    

    // ---------------------------------------------------------------------
    // ------------------------- 第二级流水：stage2 --------------------------
    // - 11 个 kernel_row 的 row_mult 并行计算单元
    // - 元数据(valid, last, pos, group)打拍
    // - bias 打拍
    // ---------------------------------------------------------------------
    // row_sum_bus 格式：输出填充：先按通道索引，每个通道16个结果；再按行索引，每行4个结果，一共4行，再按列索引。
    // ((ch_idx * 16 + oy_idx * 4 + ox_idx) * 19) +: 19
    conv_tile_mac_row_mult u_row_mult_0 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[4*80-1:0]),  // 0~3 行输入条带（这四行与卷积核第一行对应）
        .weight_row_data(stage1_weight_bus[224-1:0]),   // 卷积核第一行
        .out_row_sum_bus(row_sum_bus_0)
    );
    conv_tile_mac_row_mult u_row_mult_1 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[5*80-1:1*80]),  // 1~4 行输入条带（这四行与卷积核第二行对应）
        .weight_row_data(stage1_weight_bus[2*224-1:1*224]),   // 卷积核第二行
        .out_row_sum_bus(row_sum_bus_1)
    );
    conv_tile_mac_row_mult u_row_mult_2 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[6*80-1:2*80]),  // 2~5 行输入条带（这四行与卷积核第二行对应）
        .weight_row_data(stage1_weight_bus[3*224-1:2*224]),   // 卷积核第三行
        .out_row_sum_bus(row_sum_bus_2)
    );
    conv_tile_mac_row_mult u_row_mult_3 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[7*80-1:3*80]),  // 3~6 行输入条带（这四行与卷积核第三行对应）
        .weight_row_data(stage1_weight_bus[4*224-1:3*224]),   // 卷积核第四行
        .out_row_sum_bus(row_sum_bus_3)
    );
    conv_tile_mac_row_mult u_row_mult_4 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[8*80-1:4*80]), 
        .weight_row_data(stage1_weight_bus[5*224-1:4*224]), 
        .out_row_sum_bus(row_sum_bus_4)
    );
    conv_tile_mac_row_mult u_row_mult_5 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[9*80-1:5*80]), 
        .weight_row_data(stage1_weight_bus[6*224-1:5*224]), 
        .out_row_sum_bus(row_sum_bus_5)
    );
    conv_tile_mac_row_mult u_row_mult_6 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[10*80-1:6*80]), 
        .weight_row_data(stage1_weight_bus[7*224-1:6*224]), 
        .out_row_sum_bus(row_sum_bus_6)
    );
    conv_tile_mac_row_mult u_row_mult_7 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[11*80-1:7*80]), 
        .weight_row_data(stage1_weight_bus[8*224-1:7*224]), 
        .out_row_sum_bus(row_sum_bus_7)
    );
    conv_tile_mac_row_mult u_row_mult_8 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[12*80-1:8*80]), 
        .weight_row_data(stage1_weight_bus[9*224-1:8*224]), 
        .out_row_sum_bus(row_sum_bus_8)
    );
    conv_tile_mac_row_mult u_row_mult_9 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[13*80-1:9*80]), 
        .weight_row_data(stage1_weight_bus[10*224-1:9*224]), 
        .out_row_sum_bus(row_sum_bus_9)
    );
    conv_tile_mac_row_mult u_row_mult_10 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(stage1_pos_window[14*80-1:10*80]), 
        .weight_row_data(stage1_weight_bus[11*224-1:10*224]), 
        .out_row_sum_bus(row_sum_bus_10)
    );

    // stage2_row_sum_bus 索引方法
    // 11输出行，每个输出行64个 INT20
    // 每一输出行，4个通道，每一个通道6个 INT20
    // 每一个通道，4个输入行，每个输入行4个 INT20
    assign stage2_row_sum_bus = {
        row_sum_bus_10, row_sum_bus_9, row_sum_bus_8, row_sum_bus_7, row_sum_bus_6, row_sum_bus_5,
        row_sum_bus_4, row_sum_bus_3, row_sum_bus_2, row_sum_bus_1, row_sum_bus_0
    };

    // stage2: 元数据打拍
    conv_tile_mac_meta_pipe u_meta_pipe_stage2 (
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

    // stage2: bias 打拍
    conv_tile_mac_bias_pipe u_bias_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage1_bias_bus),
        .out_bias_bus(stage2_bias_bus)
    );


    // ---------------------------------------------------------------------
    // ------------------------- 第三级流水：stage3 --------------------------
    // - 64 组 INT20 * 11 加法，做一级加法，得到 64 组 INT32 部分和
    // - 元数据(valid, last, pos, group)打拍
    // ---------------------------------------------------------------------

    // stage3: 64个块，每一块计算 11 -> 1 的加法
    conv_tile_mac_row_add u_conv_tile_mac_row_add (
        .clk(clk),
        .rst_n(rst_n),
        .in_row_sum_bus(stage2_row_sum_bus),
        .bias_data_bus(stage2_bias_bus),
        .out_sum_bus(out_accum_bus)
    );

    // stage3: 元数据打拍
    conv_tile_mac_meta_pipe u_meta_pipe_stage3 (
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


    // stage3: 元数据传递给输出接口
    assign out_valid     = stage3_valid;
    assign out_last      = stage3_last;
    assign out_pos       = stage3_pos;
    assign out_group     = stage3_group;

endmodule
