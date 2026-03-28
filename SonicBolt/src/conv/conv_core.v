`timescale 1ns / 1ps
/*
 * 模块名称: conv_core
 * 作者: SonicBolt 团队
 * 日期: 2026-03-28
 * 版本: v2.1
 *
 * 功能概述:
 *   Conv 调度与主计算核心。
 *
 * 设计定位:
 *   - 本模块只负责 token 调度、输入工作集切换时机、参数读时机以及后级计算模块拼接。
 *   - Conv1 整层参数保存在独立的 conv_param_store 中。
 *   - 输入特征图的整帧缓存和工作集维护保存在 conv_shared_input_buffer 中。
 *
 * 当前数据流:
 *   - 同一 pos 的 8 个 group 复用同一份 14 行工作集
 *   - 只有在 pos 边界时才向输入缓存请求切换工作集
 *   - 权重和偏置仍然按 group 每拍读取
 *   - `consume_tick` 与 MAC 真正消费当前 token 的时刻对齐，供输入缓存后台预取下一 pos 的两行新数据
 *
 * 位宽说明:
 *   - pos_window_data    : 14 x 80bit = 1120bit，对应当前 pos 的 14 行工作集
 *   - weight_data_bus : 11 x 224bit = 2464bit，对应当前 group 的 11 条 kernel row
 *   - bias_data_bus       : 4 x 16bit = 64bit
 *   - out_stream_data     : 4 x 4 x 4 x 8bit = 512bit
 *
 * 调度语义:
 *   - 一张图共有 9 个 pos，每个 pos 对应 8 个 group。
 *   - 我们将一个 {pos, group} 组合称为一个 token，因此每张图共有 72 个 token。
 *   - token 发射顺序固定为:
 *       pos=0, group=0..7; pos=1, group=0..7; ...; pos=8, group=0..7
 *
 * 版本定位:
 *   - v2.0 相比 v1.0 `pos_req_valid` 不再每拍都请求窗口，而是只在初始化和 pos 边界请求，
 *     这样可以减少动态功耗, `consume_tick` 改为与 stage0_valid 对齐，用来驱动输入缓存预取。
 *   - v2.1 相比 v2.0 增加了第二层启动信号 out_stream_fire，当该信号为高时，告诉第二层 SRAM: 
 *     "马上开始准备参数, 下一个周期就要开始计算了"
 */
module conv_core #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,                    // 启动一次新图计算  
    output reg           busy,                     // 高电平表示当前仍在处理本张图 
    output reg           done,                     // 单拍完成脉冲 

    // ---------- 输入图像交互接口 ----------
    output wire          pos_req_valid,            // 向输入缓存请求一个新的 pos 窗口  
    output wire [3:0]    pos_req_pos,              // 请求的 pos 编号，范围 0~8，因此使用 4bit
    output wire          consume_tick,              
    input  wire          pos_window_valid,         // 输出窗口有效     
    input  wire [14*80-1:0] pos_window_data,       // 返回的 14x10 窗口，14 x 10 x 8bit = 1120bit        

    // ---------- 权重/偏置交互接口 ----------
    output wire          weight_rd_en,             // Conv 权重 SRAM 读使能    
    output wire [2:0]    weight_rd_group,          // 读取哪个 group 的权重       
    output wire          bias_rd_en,               // Conv 偏置 SRAM 读使能  
    output wire [2:0]    bias_rd_group,            // 读取哪个 group 的偏置     
    input  wire [11*224-1:0] weight_data_bus,      // 权重 SRAM 读出数据总线
    input  wire [63:0]   bias_data_bus,            // 偏置 SRAM 读出数据总线，4个偏置，每个16bit

    // ---------- 输出数据流接口 ----------
    output wire          out_stream_valid,         // 输出元数据：有效  
    output wire          out_stream_last,          // 输出元数据：最后
    output wire [3:0]    out_stream_pos,           // 输出元数据：位置
    output wire [2:0]    out_stream_group,         // 输出元数据：通道组  
    output wire          out_stream_fire,          // 输出元数据：夏优启动信号
    output wire [511:0]  out_stream_data           // 输出数据：量化后的 tile 数据
);

    // 9 个 pos x 8 个 group = 72 个 token
    localparam integer TOKEN_COUNT = 72;

    // issue_* 记录“下一个待发射 token”的坐标。
    reg  [3:0] issue_pos;
    reg  [2:0] issue_group;

    // issue_count 记录已经发出的 token 数量
    reg  [6:0] issue_count;

    // stage0_* 是送入 conv_tile_mac 的输入元数据寄存器。
    reg        stage0_valid;
    reg        stage0_last;
    reg  [3:0] stage0_pos;
    reg  [2:0] stage0_group;

    // 组合调度控制信号。
    wire       issue_fire;
    wire [6:0] next_issue_count;
    wire       req_init_pos;
    wire       req_next_pos;

    // MAC 输出的 INT32 tile 元数据与数据。
    wire       tile_valid;
    wire       tile_last;
    wire [3:0] tile_pos;
    wire [2:0] tile_group;
    wire       tile_fire;
    wire [2047:0] tile_accum_bus;

    // 量化 / ReLU 后的输出流。
    wire         quant_valid;
    wire         quant_last;
    wire [3:0]   quant_pos;
    wire [2:0]   quant_group;
    wire         quant_fire;
    wire [511:0] quant_data;

    // 只有当当前工作集已经有效，且本图还有 token 未发完时，才能真正发射一个 token。
    assign issue_fire        = busy && pos_window_valid && (issue_count < TOKEN_COUNT);
    assign next_issue_count  = issue_count + 7'd1;

    // 第一个 token 之前，输入缓存内部还没有建立工作集，因此需要显式请求 pos=0。
    assign req_init_pos = busy && !pos_window_valid && (issue_count == 7'd0);

    // 只有当当前 pos 的 group=7 已经实际送入 MAC 时，才请求下一个 pos 的工作集。
    // 这样可以确保输入缓存的工作集滚动与 MAC 消费时刻对齐。
    assign req_next_pos = stage0_valid && (stage0_group == 3'd7) && (stage0_pos < 4'd8);

    // 请求只有可能在第一次 token 发出和 pos 边界时发出，因此不会频繁切换，能够节省动态功耗。
    assign pos_req_valid = req_init_pos || req_next_pos;
    assign pos_req_pos   = req_next_pos ? (stage0_pos + 4'd1) : issue_pos;

    // consume_tick 专门给 conv_shared_input_buffer 使用，表示“当前 token 已真正被计算链路消费”。
    assign consume_tick  = stage0_valid;

    // 权重 / 偏置仍然按 token 粒度、按 group 发读请求。
    assign weight_rd_en    = issue_fire;
    assign weight_rd_group = issue_group;
    assign bias_rd_en      = issue_fire;
    assign bias_rd_group   = issue_group;


    // 主状态机：
    // 1. start 拉高后进入 busy
    // 2. 每次 issue_fire 推进一个 token
    // 3. 当量化输出的最后一个 token 出来时拉高 done，并退出 busy
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            issue_pos    <= 4'd0;
            issue_group  <= 3'd0;
            issue_count  <= 7'd0;
            stage0_valid <= 1'b0;
            stage0_last  <= 1'b0;
            stage0_pos   <= 4'd0;
            stage0_group <= 3'd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                busy         <= 1'b1;
                issue_pos    <= 4'd0;
                issue_group  <= 3'd0;
                issue_count  <= 7'd0;
                stage0_valid <= 1'b0;
                stage0_last  <= 1'b0;
                stage0_pos   <= 4'd0;
                stage0_group <= 3'd0;
            end else if (quant_valid && quant_last) begin
                busy <= 1'b0;
                done <= 1'b1;
            end

            // stage0_* 在当前拍锁存本拍真正发出去的 token 元数据。
            stage0_valid <= issue_fire;
            stage0_last  <= issue_fire && (issue_count == TOKEN_COUNT - 1);
            stage0_pos   <= issue_pos;
            stage0_group <= issue_group;

            if (issue_fire) begin
                issue_count <= next_issue_count;
                // group 先走完 0..7，再把 pos 加 1。
                if (issue_group == 3'd7) begin
                    issue_group <= 3'd0;
                    issue_pos   <= issue_pos + 4'd1;
                end else begin
                    issue_group <= issue_group + 3'd1;
                end
            end
        end
    end

    // MAC 负责把一个 {pos, group} token 映射成完整 4ch x 4x4 INT32 tile。
    conv_tile_mac u_conv_tile_mac (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(stage0_valid),              // in: 当前 token 有效     
        .in_last(stage0_last),                // in: 当前 token 是否为整张图最后一个 token   
        .in_pos(stage0_pos),                  // in: 当前 token 的 pos 编号，范围 0~8 
        .in_group(stage0_group),              // in: 当前 token 的 group 编号，范围 0~7     
        .in_fire(issue_fire),                 // in: 通知第二层准备启动计算
        
        // ---------- 输入数据(总线) ----------
        .pos_window_data(pos_window_data),    // in: 14x10x8bit 输入窗口         
        .weight_data_bus(weight_data_bus),    // in: 当前 group 的完整 11x4x7 INT8 权重
        .bias_data_bus(bias_data_bus),        // in: 当前 group 的完整 4 个 INT16 偏置
        
        // ---------- 输出元数据 ----------
        .out_valid(tile_valid),               // out: 输出累加 tile 有效
        .out_last(tile_last),                 // out: 输出累加 tile 是否为最后一个 token
        .out_pos(tile_pos),                   // out: 输出 tile 的 pos
        .out_group(tile_group),               // out: 输出 tile 的 group
        .out_fire(tile_fire),                 // out: 输出的第二层启动信号
        
        // ---------- 输出数据 ----------               
        .out_accum_bus(tile_accum_bus)        // out: 4(ch) x 4(row) x 4(col) x INT32 的输出累加结果
    );

    // 后级做 rescale + ReLU + 饱和裁剪，输出最终 8bit tile。
    conv_rescale_relu #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_conv_rescale_relu (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 -----------
        .in_valid(tile_valid),          // in: 输入 tile 有效     
        .in_last(tile_last),            // in: 输入 tile 是否为最后一个 token   
        .in_pos(tile_pos),              // in: 输入 tile 的 pos 
        .in_group(tile_group),          // in: 输入 tile 的 group    
        .in_fire(tile_fire),            // in: 输入的第二层启动信号
        
        // ---------- 输入数据 -----------
        .in_data_bus(tile_accum_bus),   // in: 64 个 INT32 累加值

        // ---------- 输出元数据 ---------
        .out_valid(quant_valid),        // out: 输出量化 tile 有效
        .out_last(quant_last),          // out: 输出量化 tile 是否为最后一个 token  
        .out_pos(quant_pos),            // out: 输出 tile 的 pos
        .out_group(quant_group),        // out: 输出 tile 的 group
        .out_fire(quant_fire),          // out: 输出的第二层启动信号

        // ----------- 输出数据 ----------
        .out_data_bus(quant_data)       // out: 64 个 INT8 输出值
    );

    assign out_stream_valid = quant_valid;
    assign out_stream_last  = quant_last;
    assign out_stream_pos   = quant_pos;
    assign out_stream_group = quant_group;
    assign out_stream_fire  = quant_fire;
    assign out_stream_data  = quant_data;

endmodule
