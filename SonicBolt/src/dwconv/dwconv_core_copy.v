`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_core
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 *
 * 功能概述:
 *   DWConv 调度与主计算核心。
 *
 * 设计定位:
 *   - 本模块负责
 *   - DWConv 整层参数保存在独立的 dwconv_param_store 中。
 *
 * 当前数据流:
 *   - 权重和偏置仍然按 group 每拍读取
 *
 * 位宽说明:
 *
 * 调度语义:
 *
 */
module dwconv_core_copy #(
    parameter integer M0      = 59,
    parameter integer SHIFT_N = 11
) (
    input  wire          clk,
    input  wire          rst_n,
    output reg           busy,                     // 高电平表示当前仍在处理本张图 
    output reg           done,                     // 单拍完成脉冲 

    // ---------- 输入数据流接口 ----------
    input wire           in_stream_valid,          // 输入 tile 有效
    input wire           in_stream_last,           // 输入 tile 是否是最后一个
    input wire [3:0]     in_stream_pos,            // 输入 tile 的 pos 编号
    input wire [2:0]     in_stream_group,          // 输入 tile 的 group 编号
    input wire           in_stream_fire,           // 输入的第二层启动信号
    input wire [511:0]   in_stream_data,           // 输入 tile 数据，4 x 4 x 4 x 8bit = 512bit

    // ---------- 权重/偏置交互接口 ----------
    output wire          weight_rd_en,             // DWConv 权重 SRAM 读使能    
    output wire [2:0]    weight_rd_group,          // 读取哪个 group 的权重       
    output wire          bias_rd_en,               // DWConv 偏置 SRAM 读使能  
    output wire [2:0]    bias_rd_group,            // 读取哪个 group 的偏置     
    input  wire [3*96-1:0] weight_data_bus,        // 权重 SRAM 读出数据总线
    input  wire [63:0]   bias_data_bus,            // 偏置 SRAM 读出数据总线，4个偏置，每个16bit

    // ---------- 输出数据流接口 ----------
    output wire          out_stream_valid,         // 输出元数据：有效  
    output wire          out_stream_last,          // 输出元数据：last
    output wire [3:0]    out_stream_pos,           // 输出元数据：位置
    output wire [2:0]    out_stream_group,         // 输出元数据：通道组  
    output wire [127:0]  out_stream_data           // 输出数据：量化后的 tile 数据
);

    // stage0_* 把上游 token 对齐到本层参数 SRAM 的同步读延迟。
    reg          stage0_valid;
    reg          stage0_last;
    reg  [3:0]   stage0_pos;
    reg  [2:0]   stage0_group;
    reg          stage0_fire;
    reg  [511:0] stage0_data_bus;

    // MAC 输出的 INT32 tile 元数据与数据。
    wire          tile_valid;
    wire          tile_last;
    wire [3:0]    tile_pos;
    wire [2:0]    tile_group;
    wire          tile_fire;
    wire [511:0]  tile_accum_bus;

    // 量化 / ReLU 后的输出流。
    wire          quant_valid;
    wire          quant_last;
    wire [3:0]    quant_pos;
    wire [2:0]    quant_group;
    wire          quant_fire;
    wire [127:0]  quant_data;

    // 参数 SRAM 是同步读，因此需要在输入 token 到来时先发起读请求，
    // 下一拍再把该 token 送入 MAC。
    assign weight_rd_en    = in_stream_fire;
    assign bias_rd_en      = in_stream_fire;
    // assign weight_rd_group = in_stream_group;
    // assign bias_rd_group   = in_stream_group;
    
    reg [3:0] issue_pos;
    reg [2:0] issue_group;
    assign weight_rd_group = issue_group;
    assign bias_rd_group   = issue_group;

    // 主状态机：
    // 1. in_stream_fire 拉高后进入 busy (第一个输入token到来时)
    // 2. 每次 in_stream_valid 推进一个 token
    // 3. 当量化输出的最后一个 token 出来时拉高 done，并退出 busy
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            issue_pos <= 4'b0;
            issue_group <= 3'b0;
            // stage0_valid    <= 1'b0;
            // stage0_last     <= 1'b0;
            // stage0_pos      <= 4'b0;
            // stage0_group    <= 3'b0;
            // stage0_fire     <= 1'b0;
            // stage0_data_bus <= 512'd0;
        end else begin
            done <= 1'b0;

            if (in_stream_valid && !busy) begin
                busy <= 1'b1;
            end else if (quant_valid && quant_last) begin
                busy <= 1'b0;
                done <= 1'b1;
            end

            // stage0_valid    <= in_stream_valid;
            // stage0_last     <= in_stream_last;
            // stage0_pos      <= in_stream_pos;
            // stage0_group    <= in_stream_group;
            // stage0_fire     <= in_stream_fire;
            // stage0_data_bus <= in_stream_data;

            // 输入 valid 到来时更新 tile 编号组
            if (in_stream_valid) begin
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
    dwconv_tile_mac u_dwconv_tile_mac (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        // .in_valid(stage0_valid),              // in: 当前 token 有效
        // .in_last(stage0_last),                // in: 当前 token 是否为整张图最后一个 token
        // .in_pos(stage0_pos),                  // in: 当前 token 的 pos 编号，范围 0~8
        // .in_group(stage0_group),              // in: 当前 token 的 group 编号，范围 0~7
        // .in_fire(stage0_fire),                // in: 传给下游的 metadata fire
        .in_valid(in_stream_valid),              // in: 当前 token 有效
        .in_last(in_stream_last),                // in: 当前 token 是否为整张图最后一个 token
        .in_pos(in_stream_pos),                  // in: 当前 token 的 pos 编号，范围 0~8
        .in_group(in_stream_group),              // in: 当前 token 的 group 编号，范围 0~7
        .in_fire(in_stream_fire),                // in: 传给下游的 metadata fire

        // ---------- 输入数据(总线) ----------
        .in_data_bus(stage0_data_bus),        // 输入 tile 数据，4 x 4 x 4 x 8bit = 512bit
        .weight_data_bus(weight_data_bus),    // in: 当前 group 的完整 11x4x7 INT8 权重
        .bias_data_bus(bias_data_bus),        // in: 当前 group 的完整 4 个 INT16 偏置
        
        // ---------- 输出元数据 ----------
        .out_valid(tile_valid),               // out: 输出累加 tile 有效
        .out_last(tile_last),                 // out: 输出累加 tile 是否为最后一个 token
        .out_pos(tile_pos),                   // out: 输出 tile 的 pos
        .out_group(tile_group),               // out: 输出 tile 的 group】
        .out_fire(tile_fire),                // out: 输出的第三层启动信号
        
        // ---------- 输出数据 ----------               
        .out_accum_bus(tile_accum_bus)        // out: 4(ch) x 4(row) x 4(col) x INT32 的输出累加结果
    );

    // 后级做 rescale + ReLU + 饱和裁剪，输出最终 8bit tile。
    dwconv_rescale_relu #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_dwconv_rescale_relu (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 -----------
        .in_valid(tile_valid),          // in: 输入 tile 有效     
        .in_last(tile_last),            // in: 输入 tile 是否为最后一个 token   
        .in_pos(tile_pos),              // in: 输入 tile 的 pos 
        .in_group(tile_group),          // in: 输入 tile 的 group   
        .in_fire(tile_fire),            // in: 输入的第三层启动信号 
        
        // ---------- 输入数据 -----------
        .in_data_bus(tile_accum_bus),   // in: 64 个 INT32 累加值

        // ---------- 输出元数据 ---------
        .out_valid(quant_valid),        // out: 输出量化 tile 有效
        .out_last(quant_last),          // out: 输出量化 tile 是否为最后一个 token
        .out_pos(quant_pos),            // out: 输出 tile 的 pos
        .out_group(quant_group),        // out: 输出 tile 的 group
        .out_fire(quant_fire),          // out: 输出的第三层启动信号

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
