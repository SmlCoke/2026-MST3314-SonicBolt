`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-04-11
 * 版本: v2.3
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
 *       in_idx = row * 10 + col
 *   - 权重:
 *       weight_idx = ch * 11 * 7 + row * 7 + col
 *   - 输出:
 *       out_idx = ch * 16 + oy * 4 + ox
 *
 * 版本定位:
 *   - v2.0 中，本模块不再在单个 always 中直接完成 77 次 MAC。本模块主要负责流水级拼接，具体计算下沉到子模块。
 *      - 当前流水拆分为: input_stage + 11 个 row_mult + row_reduce_row_add
 *   - v2.1 中，将 input_stage 中数据与权重的打拍下沉到子模块内部，撤销长布线拉扯。此外，将 row_add 由一级流水*     拆分为两级，期望改善布线压力，降低时序拥堵。
 *   - v2.2 相比 v2.1 增加了第二层启动信号 out_stream_fire，当该信号为高时，告诉第二层 SRAM: 
 *     "马上开始准备参数, 下一个周期就要开始计算了"
 *   - v2.3 将所有公共子模块提取（例如bias_pipe, meta_pipe）到 utils/ 目录下
 */
module conv_tile_mac (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位

    // ---------- 输入元数据 ----------
    input  wire                in_valid,        // 当前 token 有效
    input  wire                in_last,         // 当前 token 是否为整张图最后一个 token
    input  wire [3:0]          in_pos,          // 当前 token 的 pos 编号，范围 0~8
    input  wire [2:0]          in_group,        // 当前 token 的 group 编号，范围 0~7
    input  wire                in_fire,         // 通知第二层准备计算

    // ---------- 输入数据(总线) ----------
    input  wire [14*10*8-1:0]  pos_window_data, // 14x10x8bit 输入窗口
    input  wire [11*4*7*8-1:0] weight_data_bus, // 当前 group 的完整 11x4x7 INT8 权重
    input  wire [4*16-1:0]     bias_data_bus,   // 当前 group 的完整 4 个 INT16 偏置

    // ---------- 输出元数据 ----------
    output wire                out_valid,       // 输出累加 tile 有效
    output wire                out_last,        // 输出累加 tile 是否为最后一个 token
    output wire [3:0]          out_pos,         // 输出 tile 的 pos
    output wire [2:0]          out_group,       // 输出 tile 的 group
    output wire                out_fire,        // 输出的第二层启动信号

    // ---------- 输出数据 ----------
    output wire [4*4*4*32-1:0] out_accum_bus    // 4(ch) x 4(row) x 4(col) x INT32 的输出累加结果
);
    // ---------- stage1: 数据打拍 --------- 
    // 偏置打拍结果（数据与权重的打拍已下沉到子模块内部）
    wire [4*16-1:0]     stage1_bias_bus;   // stage1 out: 寄存器打一拍后的偏置总线

    // 元数据打拍结果
    wire                stage1_valid;      // stage1 out: 打一拍后的 valid
    wire                stage1_last;       // stage1 out: 打一拍后的 last
    wire [3:0]          stage1_pos;        // stage1 out: 打一拍后的 pos
    wire [2:0]          stage1_group;      // stage1 out: 打一拍后的 group
    wire                stage1_fire;        // stage1 out: 打一拍后的 fire


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
    wire                stage2_fire;

    // ---------- stage3: 行归一结果 ---------
    wire                stage3_valid;
    wire                stage3_last;
    wire [3:0]          stage3_pos;
    wire [2:0]          stage3_group;
    wire                stage3_fire;

    // ---------- stage4: 最终输出元数据打拍 ---------
    wire                stage4_valid;
    wire                stage4_last;
    wire [3:0]          stage4_pos;
    wire [2:0]          stage4_group;
    wire                stage4_fire;


    // ---------------------------------------------------------------------
    // ------------------------- 第一级流水：stage1 --------------------------
    // - 偏置和元数据打拍，数据与权重打拍已下沉
    // ---------------------------------------------------------------------

    bias_pipe u_bias_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(bias_data_bus),
        .out_bias_bus(stage1_bias_bus)
    );

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
    

    // ---------------------------------------------------------------------
    // ------------------------- 第二级流水：stage2 --------------------------
    // - 输入数据/权重的第一拍打拍（注意：这里是第一级流水）
    // - 11 个 kernel_row 的 row_mult 并行计算单元（内部打第一拍）
    // - 元数据(valid, last, pos, group)打拍
    // - bias 打拍
    // ---------------------------------------------------------------------
    // row_sum_bus 格式：输出填充：先按通道索引，每个通道16个结果；再按行索引，每行4个结果，一共4行，再按列索引。
    // ((ch_idx * 16 + oy_idx * 4 + ox_idx) * 19) +: 19
    conv_tile_mac_row_mult u_row_mult_0 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[4*80-1:0]),  // 0~3 行输入条带（这四行与卷积核第一行对应）
        .weight_row_data(weight_data_bus[224-1:0]),   // 卷积核第一行
        .out_row_sum_bus(row_sum_bus_0)
    );
    conv_tile_mac_row_mult u_row_mult_1 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[5*80-1:1*80]),  // 1~4 行输入条带（这四行与卷积核第二行对应）
        .weight_row_data(weight_data_bus[2*224-1:1*224]),   // 卷积核第二行
        .out_row_sum_bus(row_sum_bus_1)
    );
    conv_tile_mac_row_mult u_row_mult_2 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[6*80-1:2*80]),  // 2~5 行输入条带（这四行与卷积核第二行对应）
        .weight_row_data(weight_data_bus[3*224-1:2*224]),   // 卷积核第三行
        .out_row_sum_bus(row_sum_bus_2)
    );
    conv_tile_mac_row_mult u_row_mult_3 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[7*80-1:3*80]),  // 3~6 行输入条带（这四行与卷积核第三行对应）
        .weight_row_data(weight_data_bus[4*224-1:3*224]),   // 卷积核第四行
        .out_row_sum_bus(row_sum_bus_3)
    );
    conv_tile_mac_row_mult u_row_mult_4 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[8*80-1:4*80]), 
        .weight_row_data(weight_data_bus[5*224-1:4*224]), 
        .out_row_sum_bus(row_sum_bus_4)
    );
    conv_tile_mac_row_mult u_row_mult_5 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[9*80-1:5*80]), 
        .weight_row_data(weight_data_bus[6*224-1:5*224]), 
        .out_row_sum_bus(row_sum_bus_5)
    );
    conv_tile_mac_row_mult u_row_mult_6 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[10*80-1:6*80]), 
        .weight_row_data(weight_data_bus[7*224-1:6*224]), 
        .out_row_sum_bus(row_sum_bus_6)
    );
    conv_tile_mac_row_mult u_row_mult_7 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[11*80-1:7*80]), 
        .weight_row_data(weight_data_bus[8*224-1:7*224]), 
        .out_row_sum_bus(row_sum_bus_7)
    );
    conv_tile_mac_row_mult u_row_mult_8 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[12*80-1:8*80]), 
        .weight_row_data(weight_data_bus[9*224-1:8*224]), 
        .out_row_sum_bus(row_sum_bus_8)
    );
    conv_tile_mac_row_mult u_row_mult_9 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[13*80-1:9*80]), 
        .weight_row_data(weight_data_bus[10*224-1:9*224]), 
        .out_row_sum_bus(row_sum_bus_9)
    );
    conv_tile_mac_row_mult u_row_mult_10 (
        .clk(clk), .rst_n(rst_n), 
        .row_window_data(pos_window_data[14*80-1:10*80]), 
        .weight_row_data(weight_data_bus[11*224-1:10*224]), 
        .out_row_sum_bus(row_sum_bus_10)
    );

    // stage2_row_sum_bus 索引方法
    // 11输出行，每个输出行 64个 INT19
    // 每一输出行，4个通道，每一个通道6个 INT20
    // 每一个通道，4个输入行，每个输入行4个 INT20
    assign stage2_row_sum_bus = {
        row_sum_bus_10, row_sum_bus_9, row_sum_bus_8, row_sum_bus_7, row_sum_bus_6, row_sum_bus_5,
        row_sum_bus_4, row_sum_bus_3, row_sum_bus_2, row_sum_bus_1, row_sum_bus_0
    };

    // stage2: 元数据打拍
    meta_pipe u_meta_pipe_stage2 (
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

    // stage2: bias 打拍
    bias_pipe u_bias_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage1_bias_bus),
        .out_bias_bus(stage2_bias_bus)
    );


    // ---------------------------------------------------------------------
    // ------------------------- 第三/四级流水：stage3/4 -----------------------
    // - 64 组 INT20 * 11 加法，做两级加法，得到 64 组 INT32 最终结果
    // - 元数据(valid, last, pos, group)随之打两拍
    // ---------------------------------------------------------------------

    // stage3 & 4: 64个块，每一块计算 11 -> 1 的加法 (内部已打两拍)
    conv_tile_mac_row_add u_conv_tile_mac_row_add (
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

    // stage4: 元数据再次打拍 (匹配 row_add 内的两级流水)
    meta_pipe u_meta_pipe_stage4 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage3_valid),
        .in_last(stage3_last),
        .in_pos(stage3_pos),
        .in_group(stage3_group),
        .in_fire(stage3_fire),
        .out_valid(stage4_valid),
        .out_last(stage4_last),
        .out_pos(stage4_pos),
        .out_group(stage4_group),
        .out_fire(stage4_fire)
    );

    // 综合后输出: 元数据传递给输出接口
    assign out_valid     = stage4_valid;
    assign out_last      = stage4_last;
    assign out_pos       = stage4_pos;
    assign out_group     = stage4_group;
    assign out_fire      = stage4_fire;

endmodule
