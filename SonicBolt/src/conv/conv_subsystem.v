`timescale 1ns / 1ps
/*
 * 模块名称: conv_subsystem
 * 功能概述: 基于 pos-major 数据流的 Conv 子系统顶层
 * 作者: OpenAI Codex
 * 日期: 2026-03-15
 *
 * 设计定位:
 *   - 当前只实现 Conv 层，但参数存储语义已经固定为“层内完整参数 SRAM”。
 *   - 本模块内部保存的是 Conv 整层的全部权重和全部偏置，不是“当前这次推理临时需要的参数”。
 *   - 后续 DWConv / PWConv / FC / PostProcess 也应遵循同样原则，在各自层模块内部保存本层全部参数。
 *
 * 主数据流:
 *   输入图像 -> conv_shared_input_buffer -> conv_core -> out_stream_*
 *
 *
 * 参数存储:
 *   - 由独立的 conv_param_store 管理 Conv 整层参数。
 *   - 当前组织为 11 个 weight bank + 1 个 bias bank。
 *   - 运行时只按 group 读取其中一部分切片。
 */
module conv_subsystem #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位
    input  wire          start,            // 启动一次新图计算
    input  wire          start_buf_sel,    // 本次计算使用哪个输入 buffer
    output wire          busy,             // 高电平表示 Conv 正在处理当前图
    output wire          done,             // 单拍完成脉冲

    input  wire          img_wr_en,        // 输入图像写使能
    input  wire          img_wr_buf_sel,   // 输入图像写入哪个 buffer
    input  wire [4:0]    img_wr_addr,      // 输入图像行地址，30 行因此使用 5bit
    input  wire [39:0]   img_wr_data_lo,   // 一行的低半部分，5 个 INT8 = 40bit
    input  wire [39:0]   img_wr_data_hi,   // 一行的高半部分，5 个 INT8 = 40bit

    // ------------ 权重 SRAM 写控制信号 ------------
    input  wire          weight_wr_en,     // Conv 权重写使能
    input  wire [4:0]    weight_wr_bank,   // Conv 权重 bank 编号，当前只使用 0..10
    input  wire [2:0]    weight_wr_addr,   // Conv 权重 group 地址，8 个 group 需要 3bit
    input  wire [223:0]  weight_wr_data,   // 1 个权重 word = 4 x 7 x 8bit = 224bit

    // ------------ 偏置 SRAM 写控制信号 ------------
    input  wire          bias_wr_en,       // Conv 偏置写使能
    input  wire          bias_wr_bank,     // Conv 偏置 bank 编号，当前版本只使用 0
    input  wire [2:0]    bias_wr_addr,     // Conv 偏置 group 地址
    input  wire [63:0]   bias_wr_data,     // 1 个偏置 word = 4 x INT16 = 64bit

    input  wire          out_stream_ready, // 预留的下游 ready，当前版本默认视作常高
    output wire          out_stream_valid, // 输出 tile 有效
    output wire [3:0]    out_stream_pos,   // 输出 tile 的 pos 编号
    output wire [2:0]    out_stream_group, // 输出 tile 的 group 编号
    output wire [511:0]  out_stream_data   // 输出 tile 数据，4 x 4 x 4 x 8bit = 512bit

);

    wire          active_buf_sel;   // 当前正在被主通路消费的输入图编号
    wire          pos_req_valid;    // 下游请求一个新的 pos 窗口
    wire [3:0]    pos_req_pos;      // 请求的 pos 编号
    wire          pos_window_valid; // 输出窗口有效
    wire [1119:0] pos_window_data;  // 返回的 14x10 窗口，14 x 10 x 8bit = 1120bit

    wire          weight_store_wr_en; // 权重 SRAM 写使能
    wire          bias_store_wr_en;   // 偏置 SRAM 写使能

    wire          weight_rd_en;       // 权重 SRAM 读使能
    wire [2:0]    weight_rd_group;    // 权重 SRAM 读地址

    wire          bias_rd_en;         // 偏置 SRAM 读使能
    wire [2:0]    bias_rd_group;      // 偏置 SRAM 读地址

    wire [2463:0] weight_data_bus;    // 权重 SRAM 读出数据总线
    wire [63:0]   bias_data_bus;      // 偏置 SRAM 读出数据总线

    wire          tile_valid_int;     // Conv 输出元数据：有效
    wire [3:0]    tile_pos_int;       // Conv 输出元数据：位置
    wire [2:0]    tile_group_int;     // Conv 输出元数据：通道组
    wire [511:0]  tile_data_int;      // Conv 输出数据：量化后的 tile 数据

    assign weight_store_wr_en = weight_wr_en && !busy;
    assign bias_store_wr_en   = bias_wr_en && !busy;

    conv_shared_input_buffer u_conv_shared_input_buffer (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入图写入接口 ----------
        .img_wr_en(img_wr_en),               // in: 输入图逐行写使能
        .img_wr_buf_sel(img_wr_buf_sel),     // in: 写入哪一份双缓冲寄存器
        .img_wr_addr(img_wr_addr),           // in: 写入行地址，范围
        .img_wr_data_lo(img_wr_data_lo),     // in: 一行的低半部分数据
        .img_wr_data_hi(img_wr_data_hi),     // in: 一行的高半部分数据

        // ---------- 当前活动输入图选择 ----------
        .start_consume(start),               // in: 启动消费一张新图，同时更新 active buffer 选择
        .start_buf_sel(start_buf_sel),       // in: 这次计算要消费哪一份输入图：0 选 frame_cache0，1 选 frame_cache1
        .active_buf_sel(active_buf_sel),     // out: 当前正在被主通路消费的输入图编号

        // ---------- pos 窗口请求 / 返回接口 ----------
        .pos_req_valid(pos_req_valid),       // in: 下游请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),           // in: 请求的 pos 编号，范围 0~8，因此使用 4bit
        .pos_window_valid(pos_window_valid), // out: 输出窗口有效
        .pos_window_data(pos_window_data)    // out: 返回的 14x10 窗口，14 x 10 x 8bit = 1120bit
    );

    conv_param_store u_conv_param_store (
        .clk(clk),
        .rst_n(rst_n),

        // ------------ 权重 SRAM 写控制信号 ------------
        .weight_wr_en(weight_store_wr_en),  // in: 权重写使能   
        .weight_wr_bank(weight_wr_bank),    // in: 写入哪个权重 bank，当前只使用 0..10 
        .weight_wr_addr(weight_wr_addr),    // in: 写入哪个 group 地址，8 个 group 需要 3bit 
        .weight_wr_data(weight_wr_data),    // in: 权重写数据，4 x 7 x 8bit = 224bit 

        // ------------ 偏置 SRAM 写控制信号 ------------
        .bias_wr_en(bias_store_wr_en),      // in: 偏置写使能
        .bias_wr_bank(bias_wr_bank),        // in: 写入哪个偏置 bank，当前版本只允许 0
        .bias_wr_addr(bias_wr_addr),        // in: 写入哪个 group 地址
        .bias_wr_data(bias_wr_data),        // in: 偏置写数据，4 x 16bit = 64bit

        // ------------ 权重 SRAM 读控制信号 ------------
        .weight_rd_en(weight_rd_en),        // in: 权重读使能
        .weight_rd_group(weight_rd_group),  // in: 读取哪个 group 的权重，地址范围 0..7

        // ------------ 偏置 SRAM 读控制信号 ------------
        .bias_rd_en(bias_rd_en),            // in: 偏置读使能
        .bias_rd_group(bias_rd_group),      // in: 读取哪个 group 的偏置，地址范围 0..7

        // ------------ SRAM 读出数据总线 ------------
        .weight_data_bus(weight_data_bus),  // out: 4个卷积核：4 x 11 x 7 x 8bit = 2464bit
        .bias_data_bus(bias_data_bus)       // out: 4个偏置：4 x 16 = 64bit
    );

    conv_core #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_conv_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),                        // in: 启动一次新图计算
        .busy(busy),                          // out: 高电平表示当前仍在处理本张图
        .done(done),                          // out: 单拍完成脉冲

        // ---------- 输入图像交互接口 ----------
        .pos_req_valid(pos_req_valid),        // out: 向输入缓存请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),            // out: 请求的 pos 编号，范围 0~8，因此使用 4bit
        .pos_window_valid(pos_window_valid),  // in: 输出窗口有效
        .pos_window_data(pos_window_data),    // in: 返回的 14x10 窗口，14 x 10 x 8bit = 1120bit

        // ---------- 权重/偏置交互接口 ----------
        .weight_rd_en(weight_rd_en),          // out: Conv 权重 SRAM 读使能
        .weight_rd_group(weight_rd_group),    // out: 读取哪个 group 的权重
        .bias_rd_en(bias_rd_en),              // out: Conv 偏置 SRAM 读使能
        .bias_rd_group(bias_rd_group),        // out: 读取哪个 group 的偏置
        .weight_data_bus(weight_data_bus),    // in: 权重 SRAM 读出数据总线
        .bias_data_bus(bias_data_bus),        // in: 偏置 SRAM 读出数据总线

        // ---------- 输出数据流接口 ----------
        .out_stream_ready(out_stream_ready),   // in: 下游握手信号
        .out_stream_valid(tile_valid_int),     // out: 输出元数据：有效
        .out_stream_pos(tile_pos_int),         // out: 输出元数据：位置
        .out_stream_group(tile_group_int),     // out: 输出元数据：通道组
        .out_stream_data(tile_data_int)        // out: 输出数据：量化后的 tile 数据
    );

    // 
    assign out_stream_valid = tile_valid_int;
    assign out_stream_pos   = tile_pos_int;
    assign out_stream_group = tile_group_int;
    assign out_stream_data  = tile_data_int;

endmodule
