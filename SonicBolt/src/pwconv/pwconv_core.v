`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_core
 * 作者: SonicBolt 团队
 * 日期: 2026-04-03
 * 版本: v1.q
 *
 * 功能概述:
 *   PWConv 的输入接收、token 调度、参数读取和计算核心拼接。
 *
 * 输入顺序约定:
 *   - 上游严格按 pos-major, group-minor 输入 72 个 token
 *   - pos=0..8，每个 pos 下 group=0..7
 *
 * 双缓冲映射:
 *   - 偶数 pos -> even buffer
 *   - 奇数 pos -> odd buffer
 *   - 首个 pos 收满后即可开始发射输出 token
 *
 * 调度思想:
 *   - recv_count 统计已接收输入 token 数，范围 0..72
 *   - issue_pos 表示当前正在计算哪个 pos
 *   - issue_group 表示当前正在计算哪个输出 group（0..7）
 *   - loaded_pos_count = recv_count / 8，表示已有多少个完整 pos tile 可用于计算 
 *   - 当 issue_pos < loaded_pos_count 时，说明当前 pos 已经拼齐，可以继续发射 
 *   - 接收侧负责“仓库里有没有货”，发射侧负责“现在要不要发货”
 * 
 * 版本定位:
    *   - v1.1 修复 fire 信号
 */
module pwconv_core #(
    parameter integer M0      = 69,
    parameter integer SHIFT_N = 13
) (
    input  wire          clk,
    input  wire          rst_n,
    output reg           busy,
    output reg           done,

    // ---------- 输入数据流接口 ----------
    input  wire          in_stream_valid,          // 输入 tile 有效
    input  wire          in_stream_fire,           // 输入的第三层启动信号
    input  wire          in_stream_last,           // 输入 tile 是否为整张图最后一个 token
    input  wire [3:0]    in_stream_pos,            // 输入 tile 的 pos 编号
    input  wire [2:0]    in_stream_group,          // 输入 tile 的 group 编号
    input  wire [1023:0] even_pos_data,            // 输入数据总线，来自于偶数pos
    input  wire [1023:0] odd_pos_data,             // 输入数据总线，来自于奇数pos

    // ---------- 权重/偏置交互接口 ----------
    output wire             weight_rd_en,          // DWConv 权重 SRAM 读使能      
    output wire [2:0]       weight_rd_group,       // 读取哪个 group 的权重         
    output wire             bias_rd_en,            // DWConv 偏置 SRAM 读使能    
    output wire [2:0]       bias_rd_group,         // 读取哪个 group 的偏置       
    input  wire [32*4*8-1:0] weight_data_bus,       // 权重 SRAM 读出数据总线         
    input  wire [63:0]      bias_data_bus,         // 偏置 SRAM 读出数据总线

    // ---------- 输出数据流接口 ----------           
    output wire          out_stream_valid,         // 输出元数据：有效   
    output wire          out_stream_last,          // 输出元数据：最后一个 token   
    output wire [3:0]    out_stream_pos,           // 输出元数据：位置    
    output wire [2:0]    out_stream_group,         // 输出元数据：通道组      
    output wire          out_stream_fire,          // 输出元数据：下一层启动信号     
    output wire [127:0]  out_stream_data           // 输出数据：量化后的 tile 数据    
);

    // 接收侧: 一共会收 9 x 8 = 72 个输入 token
    reg  [6:0] recv_count;

    // 发射侧: 每拍计算一个输出 group（4 个卷积核），每个卷积核覆盖全部 8 个输入 group。
    reg  [3:0] issue_pos;
    reg  [2:0] issue_group;

    // stage0 “调度完成、准备送入 MAC”的元数据寄存
    reg        stage0_valid;
    reg        stage0_last;
    reg  [3:0] stage0_pos;
    reg  [2:0] stage0_group;

    wire [3:0] loaded_pos_count;
    wire       input_fire;      // 状态信号，表示目前处于接收输入数据状态
    wire       issue_fire;      // 状态信号，高电平表示当前可以发送 token 进入计算

    // 当前发射的是哪一个 pos，就从对应奇偶缓冲里取完整 1024bit tile 送入 MAC。
    wire [1023:0] current_tile_data;

    // tile_valid/tile_last 对应 MAC 阶段末端的元数据
    wire         tile_valid;
    wire         tile_last;
    wire [3:0]   tile_pos;
    wire [2:0]   tile_group;
    wire         tile_fire;     
    wire [511:0] tile_accum_bus;

    // quant_* 对应量化 + ReLU 之后的最终输出元数据
    wire         quant_valid;
    wire         quant_last;
    wire [3:0]   quant_pos;
    wire [2:0]   quant_group;
    wire         quant_fire;
    wire [127:0] quant_data;

    // 只要系统 busy 就持续接收输入
    assign input_fire       = busy && in_stream_valid;
    assign loaded_pos_count = recv_count[6:3]; // recv_count / 8 = pos
    
    // issue_pos < loaded_pos_count pos 发射 < 输入，发射指令置 1 ，发射至计算单元
    // 例如：在8个tile发送过来的下一个时钟上升沿, rec_count变为8, 则 loaded_pos_count 从0变为1, 此时 pos 仍为0
    // 每一个tile有效时，要下一个时钟周期才能被buf读取，因此rec_count变为8的那个时钟周期，第8个tile刚好被buf读取
    // 此时 SRAM 读信号有效，下一个周期数据有效，参数有效，发送进入第一级流水
    assign issue_fire       = busy && (issue_pos < loaded_pos_count);
    // issue_fire 高电平每次只会维持8个时钟周期，之后的下一个上升沿 issue_pos = loaded_pos_count
    // 在这 8 个时钟周期内，issue_group 从0计数到7，发射完一个 pos 的 8 个 group 后，issue_pos 加1，但是此时 loaded_pos_count 也加1，仍然满足 issue_pos < loaded_pos_count 的条件，可以继续发射下一个 pos 的 token

    // 计算阶段每拍读取一个输出 group 对应的权重与偏置。
    assign weight_rd_en    = issue_fire;
    assign weight_rd_group = issue_group;
    assign bias_rd_en      = issue_fire;
    assign bias_rd_group   = issue_group;

    // 根据 pos 直接取完整 tile（8 个输入 group 全量参与计算）。
    assign current_tile_data = stage0_pos[0] ? odd_pos_data : even_pos_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            recv_count   <= 7'd0;
            issue_pos    <= 4'd0;
            issue_group  <= 3'd0;
            stage0_valid <= 1'b0;
            stage0_last  <= 1'b0;
            stage0_pos   <= 4'd0;
            stage0_group <= 3'd0;
        end else begin
            done <= 1'b0;

            // 当第一个输入token到来前一个上升沿(in_stream_fire拉高)，进入busy状态
            if (in_stream_fire && !busy) begin
                busy         <= 1'b1;
                recv_count   <= 7'd0;
                issue_pos    <= 4'd0;
                issue_group  <= 3'd0;
                stage0_valid <= 1'b0;
                stage0_last  <= 1'b0;
                stage0_pos   <= 4'd0;
                stage0_group <= 3'd0;
            end else if (quant_valid && quant_last) begin
                // 最后一个输出 tile 量化完成后，整层结束
                busy <= 1'b0;
                done <= 1'b1;
            end

            if (input_fire) begin
                recv_count <= recv_count + 7'd1;
            end

            // stage0 把本拍调度成功的 token 元数据送进 MAC
            stage0_valid <= issue_fire;
            stage0_last  <= issue_fire && (issue_pos == 4'd8) && (issue_group == 3'd7);
            stage0_pos   <= issue_pos;
            stage0_group <= issue_group;

            if (issue_fire) begin
                // 同一个 pos 需要连续 8 拍发射 out_group0..out_group7。
                if (issue_group == 3'd7) begin
                    issue_group <= 3'd0;
                    issue_pos   <= issue_pos + 4'd1;
                end else begin
                    issue_group <= issue_group + 3'd1;
                end
            end
        end
    end

    pwconv_tile_mac u_pwconv_tile_mac (
        .clk(clk),
        .rst_n(rst_n),
        // ---------- 输入元数据 ----------
        .in_valid(stage0_valid),              // in: 当前 token 是否有效
        .in_last(stage0_last),                // in: 当前 token 是否为整张图最后一个 token
        .in_pos(stage0_pos),                  // in: 当前 token 的 pos 编号
        .in_group(stage0_group),              // in: 当前 token 的输出 group 编号
        .in_fire(issue_fire),                 // in: 下一层启动信号

        // ---------- 输入数据(总线) ----------
        .tile_data_bus(current_tile_data),        // in: 当前 token 对应的完整 32ch x 2x2 输入 tile
        .weight_data_bus(weight_data_bus),        // in: 当前 out_group 对应的 8 组输入通道权重
        .bias_data_bus(bias_data_bus),        // in: 当前 group 的完整 4 个 INT16 偏置
        
        // ---------- 输出元数据 ----------
        .out_valid(tile_valid),               // out: 输出累加 tile 有效
        .out_last(tile_last),                 // out: 输出累加 tile 是否为最后一个 token
        .out_pos(tile_pos),                   // out: 输出 tile 的 pos 编号
        .out_group(tile_group),               // out: 输出 tile 的 group 编号
        .out_fire(tile_fire),                 // out: 下一层启动信号
        .out_accum_bus(tile_accum_bus)        // out: 
    );

    rescale_relu #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_rescale_relu (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(tile_valid),            // in: 输入 tile 有效
        .in_last(tile_last),              // in: 当前 token 是否为整张图最后一个 token
        .in_pos(tile_pos),                // in: 当前 token 的 pos 编号
        .in_group(tile_group),            // in: 当前 token 的 group 编号
        .in_fire(tile_fire),              // in: 当前 token 的启动信号

        // ---------- 输入数据(总线) ----------
        .in_data_bus(tile_accum_bus),     // in: 当前 token 的累加数据总线

        // ---------- 输出元数据 ----------
        .out_valid(quant_valid),          // out: 输出 tile 有效
        .out_last(quant_last),            // out: 输出 tile 是否为最后一个 token
        .out_pos(quant_pos),              // out: 输出 tile 的 pos 编号
        .out_group(quant_group),          // out: 输出 tile 的 group 编号
        .out_fire(quant_fire),            // out: 输出 tile 的启动信号

        // ---------- 输出数据(总线) ----------
        .out_data_bus(quant_data)         // out: 输出 tile 的数据总线
    );

    assign out_stream_valid = quant_valid;
    assign out_stream_last  = quant_last;
    assign out_stream_pos   = quant_pos;
    assign out_stream_group = quant_group;
    assign out_stream_data  = quant_data;
    assign out_stream_fire  = quant_fire;

endmodule
