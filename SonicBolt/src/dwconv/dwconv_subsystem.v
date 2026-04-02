`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.1
 *
 * 功能概述: 基于 pos-major 数据流的 DWConv 子系统顶层
 *
 * 主数据流:
 *   Conv 输出的 tile -> DWConv MAC -> DWConv Rescale-ReLU
 *
 * 参数存储:
 *   - 由独立的 dwconv_param_store 管理 DWConv 整层参数。
 *   - 当前组织为 3 个 weight bank + 1 个 bias bank。
 *   - 运行时只按 group 读取其中一部分切片。
 * 版本定位:
 *   - 本模块只实现 DWConv 层，参数存储语义已经固定为“层内完整参数 SRAM”。
 *   - 本模块内部保存的是 DWConv 整层的全部权重和全部偏置，不是“当前这次推理临时需要的参数”。
 *   - v1.1 修补bug: 补齐 fire 信号
 */
module dwconv_subsystem #(
    parameter integer M0      = 59,
    parameter integer SHIFT_N = 11
) (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位
    output wire          busy,             // 高电平表示 DWConv 正在处理当前图
    output wire          done,             // 单拍完成脉冲

    // ------------ 输入数据流接口 ------------
    input wire           in_stream_valid,  // 输入 tile 有效
    input wire           in_stream_last,   // 输入 tile 是否是最后一个
    input wire [3:0]     in_stream_pos,    // 输入 tile 的 pos 编号
    input wire [2:0]     in_stream_group,  // 输入 tile 的 group 编号
    input wire           in_stream_fire,   // 第二层启动信号
    input wire [511:0]   in_stream_data,   // 输入 tile 数据，4 x 4 x 4 x 8bit = 512bit

    // ------------ 权重 SRAM 写控制信号 ------------
    input  wire          weight_wr_en,     // DWConv 权重写使能
    input  wire [1:0]    weight_wr_bank,   // DWConv 权重 bank 编号，当前只使用 0..2
    input  wire [2:0]    weight_wr_addr,   // DWConv 权重 group 地址，8 个 group 需要 3bit
    input  wire [95:0]   weight_wr_data,   // 1 个权重 word = 4 x 3 x 8bit = 96bit

    // ------------ 偏置 SRAM 写控制信号 ------------
    input  wire          bias_wr_en,       // DWConv 偏置写使能
    input  wire          bias_wr_bank,     // DWConv 偏置 bank 编号，当前版本只使用 0
    input  wire [2:0]    bias_wr_addr,     // DWConv 偏置 group 地址
    input  wire [63:0]   bias_wr_data,     // 1 个偏置 word = 4 x INT16 = 64bit

    // ------------ 输出数据流接口 ------------
    output wire          out_stream_valid, // 输出 tile 有效
    output wire          out_stream_fire,  // 输出的下一层启动信号
    output wire          out_stream_last,  // 输出 tile 是否是最后一个
    output wire [3:0]    out_stream_pos,   // 输出 tile 的 pos 编号
    output wire [2:0]    out_stream_group, // 输出 tile 的 group 编号
    output wire [127:0]  out_stream_data   // 输出 tile 数据，4 x 2 x 2 x 8bit = 128bit
);

    wire          weight_store_wr_en;      // 权重 SRAM 写使能 
    wire          bias_store_wr_en;        // 偏置 SRAM 写使能 

    wire          weight_rd_en;            // 权重 SRAM 读使能    
    wire [2:0]    weight_rd_group;         // 权重 SRAM 读地址    

    wire          bias_rd_en;              // 偏置 SRAM 读使能 
    wire [2:0]    bias_rd_group;           // 偏置 SRAM 读地址    

    wire [3*96-1:0] weight_data_bus;       // 3 条 kernel row，按 3 个 96bit 切片展平
    wire [63:0]   bias_data_bus;           // 偏置 SRAM 读出数据总线

    wire          tile_valid_int;          // DWConv 输出元数据：有效  
    wire          tile_fire_int;           // DWConv 输出元数据：下一层启动信号
    wire          tile_last_int;           // DWConv 输出元数据：最后
    wire [3:0]    tile_pos_int;            // DWConv 输出元数据：位置
    wire [2:0]    tile_group_int;          // DWConv 输出元数据：通道组  
    wire [127:0]  tile_data_int;           // DWConv 输出数据：量化后的 tile 数据 

    // 忙于计算当前图时，禁止覆盖本层参数 SRAM。
    assign weight_store_wr_en = weight_wr_en && !busy;
    assign bias_store_wr_en   = bias_wr_en && !busy;

    // 参数存储模块：
    // - 保存 DWConv 整层 3 个 kernel row bank + 1 个 bias bank
    // - 运行时按 group 输出当前 token 所需参数切片
    dwconv_param_store u_dwconv_param_store (
        .clk(clk),
        .rst_n(rst_n),

        // ------------ 权重 SRAM 写控制信号 ------------
        .weight_wr_en(weight_store_wr_en),  // in: 权重写使能   
        .weight_wr_bank(weight_wr_bank),    // in: 写入哪个weight bank，当前只使用 0..2
        .weight_wr_addr(weight_wr_addr),    // in: 写入哪个 group 地址，8 个 group 需要 3bit 
        .weight_wr_data(weight_wr_data),    // in: 权重写数据，4 x 3 x 8bit = 96bit 

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
        .weight_data_bus(weight_data_bus),  // out: 3 条 kernel row，按 3 个 96bit 切片展平     
        .bias_data_bus(bias_data_bus)       // out: 偏置 SRAM 读出数据总线
    );

    // 计算核心模块：
    // -  pos/group token 调度
    // - 负责驱动 MAC 与量化输出链
    dwconv_core #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_dwconv_core (
        .clk(clk),
        .rst_n(rst_n),
        .busy(busy),                          // out: 高电平表示当前仍在处理本张图
        .done(done),                          // out: 单拍完成脉冲

        // ---------- 输入数据流接口 ----------
        .in_stream_valid(in_stream_valid),    // in: 输入 tile 有效
        .in_stream_last(in_stream_last),      // in: 输入 tile 是否是最后一个
        .in_stream_pos(in_stream_pos),        // in: 输入 tile 的 pos 编号
        .in_stream_group(in_stream_group),    // in: 输入 tile 的 group 编号
        .in_stream_data(in_stream_data),      // in: 输入 tile 数据，4 x 4 x 4 x 8bit = 512bit
        .in_stream_fire(in_stream_fire),      // in: 输入的第二层启动信号

        // ---------- 权重/偏置交互接口 ----------
        .weight_rd_en(weight_rd_en),          // out: DWConv 权重 SRAM 读使能
        .weight_rd_group(weight_rd_group),    // out: 读取哪个 group 的权重
        .bias_rd_en(bias_rd_en),              // out: DWConv 偏置 SRAM 读使能
        .bias_rd_group(bias_rd_group),        // out: 读取哪个 group 的偏置
        .weight_data_bus(weight_data_bus),    // in: 权重 SRAM 读出数据总线
        .bias_data_bus(bias_data_bus),        // in: 偏置 SRAM 读出数据总线

        // ---------- 输出数据流接口 ----------
        .out_stream_valid(tile_valid_int),     // out: 输出元数据：有效
        .out_stream_fire(tile_fire_int),       // out: 输出元数据：下一层启动信号
        .out_stream_last(tile_last_int),       // out: 输出元数据：最后
        .out_stream_pos(tile_pos_int),         // out: 输出元数据：位置
        .out_stream_group(tile_group_int),     // out: 输出元数据：通道组
        .out_stream_data(tile_data_int)        // out: 输出数据：量化后的 tile 数据
    );

    assign out_stream_valid = tile_valid_int;
    assign out_stream_fire  = tile_fire_int;
    assign out_stream_last = tile_last_int;    
    assign out_stream_pos   = tile_pos_int;
    assign out_stream_group = tile_group_int;
    assign out_stream_data  = tile_data_int;

endmodule
