`timescale 1ns / 1ps
/*
 * 模块名称: conv_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-07
 * 版本: v2.5
 *
 * 功能概述: 基于 pos-major 数据流的 Conv 子系统顶层
 *
 * 主数据流:
 *   输入图像 -> conv_shared_input_buffer -> conv_core -> out_stream_*
 *
 * 当前实现要点:
 *   - 输入侧采用单口 SRAM 保存完整 30x10 输入图
 *   - `consume_tick` 从 conv_core 返回给输入缓存，用来驱动下一 pos 的后台预取。
 *
 * 参数存储:
 *   - 由独立的 conv_param_store 管理 Conv 整层参数。
 *   - 当前组织为 11 个 weight bank + 1 个 bias bank。
 *   - 运行时只按 group 读取其中一部分切片。
 * 
 * 版本定位:
 *   - 当前只实现 Conv 层，但参数存储语义已经固定为“层内完整参数 SRAM”。
 *   - 本模块内部保存的是 Conv 整层的全部权重和全部偏置，不是“当前这次推理临时需要的参数”。
 *   - 当前版本输入侧改为单帧缓存，不再保留双 bank ping-pong 输入缓冲
 *   - 相比 v2.0 版本，当前顶层为“单 SRAM 缓存完整输入 + 单 reg 缓存 window + conv_core 控制预取”主通路。
 *   - v2.3 相比 v2.2 增加了第二层启动信号 out_stream_fire，当该信号为高时，告诉第二层 SRAM: 
 *     "马上开始准备参数, 下一个周期就要开始计算了"
 *   - v2.3 有 bug，fire/last 信号并没有实际作为输出端口，v2.4已修复
 *   - v2.5 中，将模块下所有公共子模块提取到 utils/ 目录下
 *   - v2.6 增加了用于适配输入双帧Ping-Pong缓存的接口信号
 */
module conv_subsystem #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位
    input  wire          start,            // 启动一次新图计算
    output wire          busy,             // 高电平表示 Conv 正在处理当前图
    output wire          done,             // 单拍完成脉冲

    // ------------ 输入图像写控制信号 ------------
    input  wire          img_wr_en,        // 输入图像写使能
    input  wire [4:0]    img_wr_addr,      // 输入图像行地址，30 行因此使用 5bit
    input  wire [79:0]   img_wr_row_data,  // 输入图像写数据，一行 10 个像素，10 x 8bit = 80bit
    input  wire          img_wr_commit,    // 写入提交信号，写满一张图的30行后的下一个周期拉高，由外部控制

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

    // ------------ 输出数据流接口 ------------
    output wire          out_stream_valid, // 输出 tile 有效
    output wire          out_stream_last,  // 输出 tile 是否是最后一个
    output wire [3:0]    out_stream_pos,   // 输出 tile 的 pos 编号
    output wire [2:0]    out_stream_group, // 输出 tile 的 group 编号
    output wire          out_stream_fire,  // 输出的第二层启动信号
    output wire [511:0]  out_stream_data   // 输出 tile 数据，4 x 4 x 4 x 8bit = 512bit
);

    wire          pos_req_valid;           // 下游请求一个新的 pos 窗口
    wire [3:0]    pos_req_pos;             // 请求的 pos 编号
    wire          pos_window_valid;        // 输入窗口有效
    wire          consume_tick;            // conv_core 告诉输入缓存“当前 token 已被真正消费”
    wire [14*80-1:0] pos_window_data;      // 返回的 14x10 工作集，按 14 个 80bit 行展平

    wire          weight_store_wr_en;      // 权重 SRAM 写使能 
    wire          bias_store_wr_en;        // 偏置 SRAM 写使能 

    wire          weight_rd_en;            // 权重 SRAM 读使能    
    wire [2:0]    weight_rd_group;         // 权重 SRAM 读地址    

    wire          bias_rd_en;              // 偏置 SRAM 读使能 
    wire [2:0]    bias_rd_group;           // 偏置 SRAM 读地址    

    wire [11*224-1:0] weight_data_bus; // 11 条 kernel row，按 11 个 224bit 切片展平
    wire [63:0]   bias_data_bus;           // 偏置 SRAM 读出数据总线

    wire          tile_valid_int;          // Conv 输出元数据：有效  
    wire          tile_last_int;           // Conv 输出元数据：有效
    wire [3:0]    tile_pos_int;            // Conv 输出元数据：位置
    wire [2:0]    tile_group_int;          // Conv 输出元数据：通道组  
    wire [511:0]  tile_data_int;           // Conv 输出数据：量化后的 tile 数据 

    // 忙于计算当前图时，禁止覆盖本层参数 SRAM。
    assign weight_store_wr_en = weight_wr_en && !busy;
    assign bias_store_wr_en   = bias_wr_en && !busy;

    // 输入缓存模块：
    // - 保存输入图
    // - 维护当前 pos 的 14 行工作集
    // - 在 consume_tick 驱动下后台预取下一 pos 需要的两条新行
    conv_shared_input_buffer u_conv_shared_input_buffer (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入图写入接口 ----------
        .img_wr_en(img_wr_en),               // in: 输入图逐行写使能
        .img_wr_addr(img_wr_addr),           // in: 写入行地址，范围
        .img_wr_row_word(img_wr_row_data),   // in: 一行的完整数据

        // ---------- 消费启动接口 ----------
        .start_consume(start),               // in: 启动消费一张新图

        // ---------- pos 窗口请求 / 返回接口 ----------
        .pos_req_valid(pos_req_valid),       // in: 下游请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),           // in: 请求的 pos 编号，范围 0~8，因此使用 4bit
        .consume_tick(consume_tick),         // out: “当前 token 已被真正消费”，用来驱动输入缓存预取下一 pos 的两行新数据
        .pos_window_valid(pos_window_valid), // out: 输入窗口有效
        .pos_window_data(pos_window_data)  // out: 返回的 14x10 工作集
    );

    // 参数存储模块：
    // - 保存 Conv1 整层 11 个 kernel row bank + 1 个 bias bank
    // - 运行时按 group 输出当前 token 所需参数切片
    conv_param_store u_conv_param_store (
        .clk(clk),
        .rst_n(rst_n),

        // ------------ 权重 SRAM 写控制信号 ------------
        .weight_wr_en(weight_store_wr_en),  // in: 权重写使能   
        .weight_wr_bank(weight_wr_bank),    // in: 写入哪个weight bank，当前只使用 0..10 
        .weight_wr_addr(weight_wr_addr),    // in: 写入哪个 group 地址，8 个 group 需要 3bit 
        .weight_wr_data(weight_wr_data),    // in: 权重写数据，4 x 7 x 8bit = 224bit 

        // ------------ 偏置 SRAM 写控制信号 ------------
        .bias_wr_en(bias_store_wr_en),      // in: 偏置写使能
        .bias_wr_bank(bias_wr_bank),        // in: 写入哪个bias bank，当前版本只允许 0
        .bias_wr_addr(bias_wr_addr),        // in: 写入哪个 group 地址
        .bias_wr_data(bias_wr_data),        // in: 偏置写数据，4 x 16bit = 64bit

        // ------------ 权重 SRAM 读控制信号 ------------
        .weight_rd_en(weight_rd_en),        // in: 权重读使能
        .weight_rd_group(weight_rd_group),  // in: 读取哪个 group 的权重，地址范围 0..7

        // ------------ 偏置 SRAM 读控制信号 ------------
        .bias_rd_en(bias_rd_en),            // in: 偏置读使能
        .bias_rd_group(bias_rd_group),      // in: 读取哪个 group 的偏置，地址范围 0..7

        // ------------ SRAM 读出数据总线 ------------
        .weight_data_bus(weight_data_bus),  // out: 11 条 kernel row，按 11 个 224bit 切片展平     
        .bias_data_bus(bias_data_bus)       // out: 偏置 SRAM 读出数据总线
    );

    // 计算核心模块：
    // -  pos/group token 调度
    // - 负责驱动 MAC 与MAC 与量化输出链
    conv_core #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_conv_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),                        // in: 启动一次新图计算
        .busy(busy),                          // out: 高电平表示当前仍在处理本张图
        .done(done),                          // out: 单拍完成脉冲

        // ---------- 输入输入窗口握手接口 ----------
        .pos_req_valid(pos_req_valid),        // out: 向输入缓存请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),            // out: 请求的 pos 编号，范围 0~8，因此使用 4bit
        .consume_tick(consume_tick),          // out: conv_core 告诉输入缓存“当前 token 已被真正消费”，用来驱动输入缓存预取下一 pos 的两行新数据
        .pos_window_valid(pos_window_valid),  // in: 输入窗口有效
        .pos_window_data(pos_window_data),  // in: 返回的 14x10 窗口，14 x 10 x 8bit = 1120bit

        // ---------- 权重/偏置交互接口 ----------
        .weight_rd_en(weight_rd_en),          // out: Conv 权重 SRAM 读使能
        .weight_rd_group(weight_rd_group),    // out: 读取哪个 group 的权重
        .bias_rd_en(bias_rd_en),              // out: Conv 偏置 SRAM 读使能
        .bias_rd_group(bias_rd_group),        // out: 读取哪个 group 的偏置
        .weight_data_bus(weight_data_bus),  // in: 权重 SRAM 读出数据总线
        .bias_data_bus(bias_data_bus),        // in: 偏置 SRAM 读出数据总线

        // ---------- 输出数据流接口 ----------
        .out_stream_valid(tile_valid_int),     // out: 输出元数据：有效
        .out_stream_last(tile_last_int),       // out: 输出元数据：最后
        .out_stream_pos(tile_pos_int),         // out: 输出元数据：位置
        .out_stream_group(tile_group_int),     // out: 输出元数据：通道组
        .out_stream_fire(tile_fire_int),       // out: 输出元数据：第二层启动信号
        .out_stream_data(tile_data_int)        // out: 输出数据：量化后的 tile 数据
    );

    assign out_stream_valid = tile_valid_int;
    assign out_stream_last  = tile_last_int;
    assign out_stream_pos   = tile_pos_int;
    assign out_stream_group = tile_group_int;
    assign out_stream_fire  = tile_fire_int;
    assign out_stream_data  = tile_data_int;

endmodule
