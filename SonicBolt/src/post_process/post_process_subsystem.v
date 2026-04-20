`timescale 1ns / 1ps
/*
 * 模块名称: post_process_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-15
 * 版本: v1.4
 *
 * 功能概述:
 *   - 后处理子系统顶层：Maxpool -> Flatten -> FC -> Sigmoid
 *   - FC 与 Sigmoid 参数均改为 ROM 固化，只保留读链路
 *   - 输出 busy/done 状态，便于与其他子系统统一集成
 *
 * 设计说明:
 *   - 输入一个 tile 即开始流式处理，不等待整帧缓存
 *   - FC 到 Sigmoid 以及最终输出阶段只保留 valid 与数据总线
 *
 * 版本定位:
 *   - v1.0 完成基本功能实现
 *   - v1.1 优化了时序逻辑，删除了部分冗余逻辑，同时恢复 fire 信号作为启动信号的功能地位，
 *      将几个组合逻辑模块优化为流水线，确保逻辑综合优化顺利
 *   - v1.2 修复了 weight_sram 的时序错误、fc 的位宽错误以及恢复展平层信号
 *   - v1.3 FC 参数链路改为 ROM 只读，删除 FC 写口
 *   - v1.4 Sigmoid LUT 参数链路改为 ROM 只读，删除 Sigmoid 写口
 */
module post_process_subsystem #(
    parameter integer FC_M0      = 11,
    parameter integer FC_SHIFT_N = 15
) (
    input  wire         clk,
    input  wire         rst_n,
    output wire         busy,
    output wire         done,

    // ---------- 输入数据流接口（来自 PWConv） ----------
    input  wire         in_stream_valid,
    input  wire         in_stream_last,
    input  wire [3:0]   in_stream_pos,
    input  wire [2:0]   in_stream_group,
    input  wire         in_stream_fire,
    input  wire [127:0] in_stream_data,

    // ---------- 输出数据流接口 ----------
    output wire         out_stream_valid,
    output wire [63:0]  out_stream_data
);

    reg busy_reg;
    reg done_reg;

    // ---------- Maxpool 内部流 ----------
    wire         maxpool_out_valid_int;
    wire         maxpool_out_last_int;
    wire [3:0]   maxpool_out_pos_int;
    wire [2:0]   maxpool_out_group_int;
    wire         maxpool_out_fire_int;
    wire [31:0]  maxpool_out_data_int;

    // ---------- Flatten 内部流 ----------
    wire         flatten_out_valid_int;
    wire         flatten_out_last_int;
    wire [3:0]   flatten_out_pos_int;
    wire [2:0]   flatten_out_group_int;
    wire         flatten_out_fire_int;
    wire [31:0]  flatten_out_data_int;

    // ---------- FC 内部流 ----------
    wire         fc_out_valid_int;
    wire [15:0]  fc_out_data_int;

    // ---------- Sigmoid 内部流 ----------
    wire         sigmoid_out_valid_int;
    wire [63:0]  sigmoid_out_data_int;

    // 子系统忙闲状态：
    // - 收到本帧首个有效 token 后 busy 拉高
    // - Sigmoid 只输出单个结果，因此 valid 到来即可视为本次后处理完成
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_reg <= 1'b0;
            done_reg <= 1'b0;
        end else begin
            done_reg <= 1'b0;

            if (sigmoid_out_valid_int) begin
                // Sigmoid 输出有效，说明本次后处理完成
                busy_reg <= 1'b0;
                done_reg <= 1'b1;
            end else if (!busy_reg && in_stream_valid) begin
                busy_reg <= 1'b1;
            end
        end
    end

    // 最大池化层，对输入的 4x4 窗口进行池化，输出 4 个通道的结果。
    // 内置一级流水线
    maxpool u_maxpool (
        .clk(clk),
        .rst_n(rst_n),
        
        // ---------- 输入数据流接口 ----------
        .in_valid(in_stream_valid),         // in: 输入 tile 有效
        .in_last(in_stream_last),           // in: 输入 tile 是否是最后一个
        .in_pos(in_stream_pos),             // in: 输入 tile 位置
        .in_group(in_stream_group),         // in: 输入 tile 通道组
        .in_fire(in_stream_fire),           // in: 启动信号
        .in_data_bus(in_stream_data),       // in: 输入数据总线

        // ---------- 输出数据流接口 ----------
        .out_valid(maxpool_out_valid_int),  // out: 输出 tile 有效
        .out_last(maxpool_out_last_int),    // out: 输出 tile 是否是最后一个
        .out_pos(maxpool_out_pos_int),      // out: 输出 tile 位置
        .out_group(maxpool_out_group_int),  // out: 输出 tile 通道组
        .out_fire(maxpool_out_fire_int),    // out: 启动信号
        .out_data_bus(maxpool_out_data_int) // out: 输出数据总线
    );

    // 当前最大池化层输出已经是 FC 需要的 4(ch) x INT8 token 形式，
    // 因此这里直接复用 maxpool 输出作为 flatten 输出，避免再增加冗余模块。
    assign flatten_out_valid_int = maxpool_out_valid_int;
    assign flatten_out_last_int  = maxpool_out_last_int;
    assign flatten_out_pos_int   = maxpool_out_pos_int;
    assign flatten_out_group_int = maxpool_out_group_int;
    assign flatten_out_fire_int  = maxpool_out_fire_int;
    assign flatten_out_data_int  = maxpool_out_data_int;

    // 全连接层
    // 经过全连接层的内部状态积累后，五个元数据信号只保留 valid ，其他信号在 FC 内部发挥最后的定位作用
    fc #(
        .M0(FC_M0),
        .SHIFT_N(FC_SHIFT_N)
    ) u_fc (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(flatten_out_valid_int),      // in: 输入 tile 有效
        .in_last(flatten_out_last_int),        // in: 输入 tile 是否是最后一个
        .in_pos(flatten_out_pos_int),          // in: 输入 tile 位置
        .in_group(flatten_out_group_int),      // in: 输入 tile 通道组
        .in_fire(flatten_out_fire_int),        // in: 启动信号

        // ---------- 输入数据 ----------
        .in_data_bus(flatten_out_data_int),    // in: 输入数据总线

        // ---------- 输出数据 ----------
        .out_valid(fc_out_valid_int),         // out: 输出有效
        .out_data_bus(fc_out_data_int)        // out: 输出数据总线
    );

    // Sigmoid 激活函数模块
    post_process_sigmoid u_sigmoid (
        .clk(clk),
        .rst_n(rst_n),
        
        // ---------- 输入数据 ----------
        .in_valid(fc_out_valid_int),
        .in_data_bus(fc_out_data_int),

        // ---------- 输出数据 ----------
        .out_valid(sigmoid_out_valid_int),
        .out_data_bus(sigmoid_out_data_int)
    );

    assign busy = busy_reg;
    assign done = done_reg;

    assign out_stream_valid = sigmoid_out_valid_int;
    assign out_stream_data  = sigmoid_out_data_int;

endmodule
