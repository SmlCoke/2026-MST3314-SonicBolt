`timescale 1ns / 1ps
/*
 * 模块名称: conv_core
 * 功能概述: 面向 pos-major 数据流的 Conv1 计算核心
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 设计定位:
 *   - 本模块只负责调度与数据通路拼接，不负责真正保存参数。
 *   - Conv1 整层参数保存在独立的 conv_param_store 中。
 *   - 运行时每发出一个 {pos, group} token，就向参数存储请求该 group 的权重和偏置切片。
 *
 * 数据流语义:
 *   - 一张图共有 9 个 pos。
 *   - 每个 pos 对应 8 个 4-channel group。
 *   - 因此整张图共有 9 x 8 = 72 个 token。
 *   - 当前目标是 steady-state 下 1 token / cycle。
 *
 * 位宽说明:
 *   - pos_window_data : 14 x 10 x 8bit  = 1120bit
 *   - weight_data_bus : 4 x 11 x 7 x 8bit = 2464bit
 *   - bias_data_bus   : 4 x 16bit = 64bit
 *   - out_stream_data : 4 x 4 x 4 x 8bit = 512bit
 *
 * 更新说明:
 *   - MAC / 量化流水加深后，done 以 quant_valid && quant_last 为准。
 */
module conv_core #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位
    input  wire          start,            // 启动一次新图计算
    output reg           busy,             // 高电平表示当前仍在处理本张图
    output reg           done,             // 单拍完成脉冲

    // ---------- 输入图像交互接口 ----------
    output wire          pos_req_valid,    // 向输入缓存请求一个新的 pos 窗口
    output wire [3:0]    pos_req_pos,      // 请求的 pos 编号，范围 0~8，因此使用 4bit
    input  wire          pos_window_valid, // 输入缓存返回窗口有效
    input  wire [1119:0] pos_window_data,  // 14 x 10 x 8bit 输入窗口

    // ---------- 权重/偏置交互接口 ----------
    output wire          weight_rd_en,     // Conv1 权重 SRAM 读使能
    output wire [2:0]    weight_rd_group,  // 读取哪个输出通道组的权重，8 组因此使用 3bit
    output wire          bias_rd_en,       // Conv1 偏置 SRAM 读使能
    output wire [2:0]    bias_rd_group,    // 读取哪个输出通道组的偏置
    input  wire [2463:0] weight_data_bus,  // 当前 group 的完整 4x11x7 INT8 权重
    input  wire [63:0]   bias_data_bus,    // 当前 group 的完整 4 个 INT16 偏置

    input  wire          out_stream_ready, // 预留的下游握手，当前版本默认下游始终 ready
    output wire          out_stream_valid, // 输出 tile 有效
    output wire [3:0]    out_stream_pos,   // 输出 tile 所属的 pos
    output wire [2:0]    out_stream_group, // 输出 tile 所属的 group
    output wire [511:0]  out_stream_data   // 4 x 4 x 4 x 8bit 量化后输出 tile
);

    localparam integer TOKEN_COUNT = 72;  // 9 个 pos x 8 个 group

    reg  [3:0] issue_pos;          // 核心状态计数器：位置
    reg  [2:0] issue_group;        // 核心状态计数器：通道组
    reg  [6:0] issue_count;        // 当前已经发送的最近的 token 编号
    
    reg        stage0_valid;       // tile_mac 流水线输入元数据
    reg        stage0_last;        // tile_mac 流水线输入元数据
    reg  [3:0] stage0_pos;         // tile_mac 流水线输入元数据
    reg  [2:0] stage0_group;       // tile_mac 流水线输入元数据
    
    wire       issue_fire;         // 是否发射当前 token、wt/bs SRAM使能、发送buffer请求的组合逻辑信号
    wire [6:0] next_issue_count;   // 下一个时钟上升沿要发送的 token 的编号
    wire       mac_in_valid;       // tile_mac 流水线输入元数据
    
    wire       tile_valid;         // tile_mac 流水线输出元数据
    wire       tile_last;          // tile_mac 流水线输出元数据
    wire [3:0] tile_pos;           // tile_mac 流水线输出元数据
    wire [2:0] tile_group;         // tile_mac 流水线输出元数据
    
    // tile_mac 流水线输出数据总线，4(ch) x 4(row) x 4(col) x INT32 = 2048bit
    wire [2047:0] tile_accum_bus;  
    
    wire         quant_valid;
    wire         quant_last;
    wire [3:0]   quant_pos;
    wire [2:0]   quant_group;
    wire [511:0] quant_data;

    // 决定是否发射 token
    assign issue_fire       = busy && (issue_count < TOKEN_COUNT);
    assign next_issue_count = issue_count + 7'd1;   //下一个 token 编号
    // 与输入图像存储器交互的信号
    assign pos_req_valid    = issue_fire;
    assign pos_req_pos      = issue_pos;
    // 与权重/偏置 SRAM 交互的信号
    assign weight_rd_en     = issue_fire;
    assign weight_rd_group  = issue_group;
    assign bias_rd_en       = issue_fire;
    assign bias_rd_group    = issue_group;

    // 当 issue_fire 和 pos_window_valid 同时为高时，表示 tile_mac 流水线的输入数据和元数据都准备好了
    assign mac_in_valid     = stage0_valid && pos_window_valid;     // tile_mac 流水线的输入元数据

    // token 发射顺序固定为:
    // pos=0, group=0..7; pos=1, group=0..7; ...; pos=8, group=0..7
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
            end else if (quant_valid && quant_last) begin
                busy <= 1'b0;
                done <= 1'b1;
            end
            
            // tile_mac 流水线的输入元数据
            stage0_valid <= issue_fire;
            stage0_last  <= issue_fire && (issue_count == TOKEN_COUNT - 1);
            stage0_pos   <= issue_pos;
            stage0_group <= issue_group;
            
            // 每个上升沿更新状态计数器
            if (issue_fire) begin
                issue_count <= next_issue_count;
                if (issue_group == 3'd7) begin
                    issue_group <= 3'd0;
                    issue_pos   <= issue_pos + 4'd1;
                end else begin
                    issue_group <= issue_group + 3'd1;
                end
            end
        end
    end

    // tile_mac 模块内置 5 级流水线
    conv_tile_mac u_conv_tile_mac (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(mac_in_valid),             // in: 当前 token 有效     
        .in_last(stage0_last),               // in: 当前 token 是否为整张图最后一个 token   
        .in_pos(stage0_pos),                 // in: 当前 token 的 pos 编号，范围 0~8 
        .in_group(stage0_group),             // in: 当前 token 的 group 编号，范围 0~7     

        // ---------- 输入数据(总线) ----------
        .pos_window_data(pos_window_data),   // in: 14x10x8bit 输入窗口   
        .weight_data_bus(weight_data_bus),   // in: 当前 group 的完整 11x4x7 INT8 权重   
        .bias_data_bus(bias_data_bus),       // in: 当前 group 的完整 4 个 INT16 偏置  

        // ---------- 输出元数据 ----------
        .out_valid(tile_valid),              // out: 输出累加 tile 有效
        .out_last(tile_last),                // out: 输出累加 tile 是否为最后一个 token
        .out_pos(tile_pos),                  // out: 输出 tile 的 pos  
        .out_group(tile_group),              // out: 输出 tile 的 group

        // ---------- 输出数据 ----------
        .out_accum_bus(tile_accum_bus)       // out: 4(ch) x 4(row) x 4(col) x INT32 的输出累加结果
    );

    // rescale_relu 模块内置 3 级流水线
    conv_rescale_relu #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_conv_rescale_relu (
        .clk(clk),
        .rst_n(rst_n),
        // ---------- 输入元数据 ----------
        .in_valid(tile_valid),
        .in_last(tile_last),
        .in_pos(tile_pos),
        .in_group(tile_group),
        
        // ---------- 输入数据 ----------
        .in_data_bus(tile_accum_bus),

        // ---------- 输出元数据 ----------
        .out_valid(quant_valid),
        .out_last(quant_last),
        .out_pos(quant_pos),
        .out_group(quant_group),

        // ---------- 输出数据 ----------
        .out_data_bus(quant_data)
    );

    assign out_stream_valid = quant_valid;
    assign out_stream_pos   = quant_pos;
    assign out_stream_group = quant_group;
    assign out_stream_data  = quant_data;

endmodule
