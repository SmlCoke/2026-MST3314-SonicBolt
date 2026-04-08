`timescale 1ns / 1ps
/*
 * 模块名称: conv_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-08
 * 版本: v2.6
 *
 * 功能概述:
 *   Conv 子系统顶层，负责把输入图像缓存、卷积参数存储和 Conv 计算核心串接起来。
 *
 * 主数据流:
 *   输入图像 -> conv_shared_input_buffer -> conv_core -> out_stream_*
 *
 * 当前版本说明:
 *   - 输入侧已经升级为双帧 Ping-Pong 缓存。
 *   - `img_wr_commit` 用于在整帧写完后提交当前 bank。
 *   - `img_wr_ready` 用于向上层反馈“当前是否还能继续接收下一帧输入”。
 *   - `start` 不再直接驱动 conv_core，而是先与 ready bank 状态组合成 `launch_start`，
 *     只有至少有一帧完整输入已经准备好时才真正启动 Conv 计算。
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
    input  wire          img_wr_commit,    // 当前帧 30 行均已写完，提交当前写 bank
    output wire          img_wr_ready,     // 当前允许开始写下一帧

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
    wire             tile_fire_int;        // Conv 输出的第二层启动提示信号
    wire [511:0]  tile_data_int;           // Conv 输出数据：量化后的 tile 数据 

    // ---------- Ping-Pong 输入缓存控制 ----------
    wire [1:0]       ready_bank_mask;      // 哪个输入 bank 已经装好完整待消费帧
    wire             img_wr_ready_int;     // 输入缓存内部生成的“可继续写下一帧”信号
    wire             consume_bank_sel;     // 本次启动时应消费的 ready bank
    wire             launch_start;         // 真正送给输入缓存和 conv_core 的启动脉冲
    wire             core_busy_int;        // conv_core busy
    wire             core_done_int;        // conv_core done

    // 计算过程中禁止覆盖当前层参数 SRAM；
    // 当启动脉冲拉高的这个拍，也一并禁止参数写入，避免与读通路发生冲突。
    assign weight_store_wr_en = weight_wr_en && !core_busy_int && !launch_start;
    assign bias_store_wr_en   = bias_wr_en && !core_busy_int && !launch_start;

    // 当前策略下优先选择编号较小的 ready bank；
    // 由于 launch_start 已经要求 ready_bank_mask 非零，因此这里总能选出一个合法 bank。
    assign consume_bank_sel   = ready_bank_mask[0] ? 1'b0 : 1'b1;

    // 只有至少有一帧完整输入准备好时，外部 start 才会真正启动 Conv。
    assign launch_start       = start && (|ready_bank_mask);

    assign busy         = core_busy_int;
    assign done         = core_done_int;
    assign img_wr_ready = img_wr_ready_int;

    // 输入双帧缓存：
    // - 对外暴露逐行写接口
    // - 内部维护 Ping-Pong bank 的 ready / consume / write 状态
    // - 根据 conv_core 的 pos 请求返回 14x10 输入窗口
    conv_shared_input_buffer u_conv_shared_input_buffer (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入图写入接口 ----------
        .img_wr_en(img_wr_en),                    // in: 输入图逐行写使能
        .img_wr_addr(img_wr_addr),                // in: 写入行地址             
        .img_wr_row_word(img_wr_row_data),        // in: 一行 10 个像素
        .img_wr_commit(img_wr_commit),            // in: 当前写入 Bank 的30行已经写完，可以被消费
        .img_wr_ready(img_wr_ready_int),          // out:当前存在可写 bank                       

        // ---------- 消费启动接口 ----------
        .start_consume(launch_start),             // in: 启动消费当前 SRAM 中的一张新图
        .consume_bank_sel(consume_bank_sel),      // in: 本次 start_consume 要切换到哪个 bank
        .ready_bank_mask(ready_bank_mask),        // out: 哪几个 bank 已经 ready，可以开始启动消费

        // ---------- pos 窗口请求 / 返回接口 ----------
        .pos_req_valid(pos_req_valid),            // in: conv_core 请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),                // in: 请求的 pos 编号
        .pos_window_valid(pos_window_valid),      // out: 输入窗口有效
        .consume_tick(consume_tick),              // out: conv_core 确认当前 token 已被真正消费
        .pos_window_data(pos_window_data)         // out: 返回的 14x10 工作窗口
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
        .start(launch_start),                 // in: 启动一次新图计算
        .busy(core_busy_int),                 // out: 高电平表示当前仍在处理本张图
        .done(core_done_int),                 // out: 单拍完成脉冲

        // ---------- 输入输入窗口握手接口 ----------
        .pos_req_valid(pos_req_valid),        // out: 向输入缓存请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),            // out: 请求的 pos 编号，范围 0~8，因此使用 4bit
        .consume_tick(consume_tick),
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
