`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-14
 * 版本: v1.3
 *
 * 功能概述:
 *   PWConv 独立子系统顶层。
 *
 * 设计定位:
 *   - 输入为 Activation2 之后的 DW 流输出
 *   - 输出为 Activation3 之后的 PW 流输出
 *   - 保持与 Conv1 顶层相近的 start / busy / done / out_stream_* 风格
 * 版本定位:
 *   - v1.1 增加了 fire 信号
 *   - v1.2 增加了 launch_safe 输出信号，暴露给顶层用于启动下一轮 conv 计算
 *   - v1.3 删除 launch_safe 信号，下一帧启动时机完全由顶层 cnn 的 guard 计数器以及 conv_core 控制
 */
module pwconv_subsystem #(
    parameter integer M0      = 69,
    parameter integer SHIFT_N = 13
) (
    input  wire          clk,
    input  wire          rst_n,
    output wire          busy,
    output wire          done,

    // ---------- 输入数据流接口 ----------
    input  wire          in_stream_valid,  // 输入 tile 有效
    input  wire          in_stream_fire,   // 第三层启动信号
    input  wire [3:0]    in_stream_pos,    // 输入 tile 的 pos 编号
    input  wire [2:0]    in_stream_group,  // 输入 tile 的 group 编号
    input  wire          in_stream_last,   // 输入 tile 是否为最后一个
    input  wire [127:0]  in_stream_data,   // 输入 tile 数据，4 x 2 x 2 x 8bit = 128bit

    // ---------- 输出数据流接口 ----------
    output wire          out_stream_valid, // 输出 tile 有效
    output wire          out_stream_last,  // 输出 tile 是否为最后一个 token
    output wire          out_stream_fire,  // 输出的下一层启动信号
    output wire [3:0]    out_stream_pos,   // 输出 tile 的 pos 编号
    output wire [2:0]    out_stream_group, // 输出 tile 的 group 编号
    output wire [127:0]  out_stream_data   // 输出 tile 数据，4 x 2 x 2 x 8bit = 128bit
);

    wire [1023:0] even_pos_data;
    wire [1023:0] odd_pos_data;

    wire          capture_en;

    wire          weight_rd_en;            // 权重 SRAM 读使能
    wire [2:0]    weight_rd_group;         // 权重 SRAM 读地址 
    wire          bias_rd_en;              // 偏置 SRAM 读使能
    wire [2:0]    bias_rd_group;           // 偏置 SRAM 读地址
    wire [8*128-1:0] weight_data_bus;      // 权重 SRAM 读出数据总线
    wire [63:0]      bias_data_bus;        // 偏置 SRAM 读出数据总线

    // 仅允许电路在工作状态(busy)并且输入数据有效(valid)时，写入数据到缓冲区
    assign capture_en         = busy && in_stream_valid;

    pwconv_input_buffer u_pwconv_input_buffer (
        .clk(clk),
        .rst_n(rst_n),
        // ---------- 输入元数据 ----------
        .capture_en(capture_en),          // in: 当前数据是否有效并且电路是否工作 
        .in_fire(in_stream_fire),         // in: 启动信号
        .in_pos(in_stream_pos),           // in: 输入 tile 的 pos 编号
        .in_group(in_stream_group),       // in: 输入 tile 的 group 编号
        .in_data(in_stream_data),         // in: 输入 tile 数据，4 x 2 x 2 x 8bit = 128bit

        // ---------- 输出数据接口 ----------
        .even_pos_data(even_pos_data),    // out: 输入数据总线，来自于偶数pos
        .odd_pos_data(odd_pos_data)       // out: 输入数据总线，来自于奇数pos
    );

    pwconv_param_store u_pwconv_param_store (
        .clk(clk),
        .rst_n(rst_n),

        // ------------ 权重 SRAM 读控制信号 ------------
        .weight_rd_en(weight_rd_en),            // in: 权重读使能  
        .weight_rd_group(weight_rd_group),      // in: 读取哪个 group 的权重，地址范围 0..7     
        
        // ------------ 偏置 SRAM 读控制信号 ------------
        .bias_rd_en(bias_rd_en),                // in: 偏置读使能    
        .bias_rd_group(bias_rd_group),          // in: 读取哪个 group 的偏置，地址范围 0..7  
        
        // ------------ SRAM 读出数据总线 ------------
        .weight_data_bus(weight_data_bus),      // out: 3 条 kernel row，按3个128bit切片展平
        .bias_data_bus(bias_data_bus)           // out: 偏置 SRAM 读出数据总线   
    );

    pwconv_core #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_pwconv_core (
        .clk(clk),
        .rst_n(rst_n),
        
        // 控制信号
        .busy(busy),                            // out: 高电平表示当前仍在处理本张图
        .done(done),                            // out: 单拍完成脉冲

        // ---------- 输入数据流接口 ----------
        .in_stream_valid(in_stream_valid),      // in: 输入 tile 有效
        .in_stream_fire(in_stream_fire),        // in: 输入的启动信号
        .in_stream_last(in_stream_last),        // in: 输入 tile 是否为最后一个
        .in_stream_pos(in_stream_pos),          // in: 输入 tile 的 pos 编号
        .in_stream_group(in_stream_group),      // in: 输入 tile 的 group 编号
        .even_pos_data(even_pos_data),          // in: 输入数据总线，来自于偶数pos
        .odd_pos_data(odd_pos_data),            // in: 输入数据总线，来自于奇数pos

        // ---------- 权重/偏置交互接口 ----------
        .weight_rd_en(weight_rd_en),            // out: DWConv 权重 SRAM 读使能       
        .weight_rd_group(weight_rd_group),      // out: 读取哪个 group 的权重             
        .bias_rd_en(bias_rd_en),                // out: DWConv 偏置 SRAM 读使能   
        .bias_rd_group(bias_rd_group),          // out: 读取哪个 group 的偏置         
        .weight_data_bus(weight_data_bus),      // in: 权重 SRAM 读出数据总线             
        .bias_data_bus(bias_data_bus),          // in: 偏置 SRAM 读出数据总线      
        
        // ---------- 输出数据流接口 ----------
        .out_stream_valid(out_stream_valid),    // out: 输出元数据：有效
        .out_stream_last(out_stream_last),      // out: 输出元数据：最后一个 token
        .out_stream_fire(out_stream_fire),      // out: 输出的下一层启动信号
        .out_stream_pos(out_stream_pos),        // out: 输出元数据：位置
        .out_stream_group(out_stream_group),    // out: 输出元数据：通道组
        .out_stream_data(out_stream_data)       // out: 输出数据：量化后的 tile 数据
    );

endmodule
