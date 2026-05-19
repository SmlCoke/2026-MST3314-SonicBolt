`timescale 1ns / 1ps
/*
 * 模块名称: conv_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-13
 * 版本: v2.7
 *
 * 功能概述:
 *   Conv 阶段顶层封装，负责把输入写口、共享输入缓存、参数 ROM 和 conv_core 拼接起来。
 *
 * 设计定位:
 *   - 在 img_wr_* 接口上保留 1 级输入寄存，用于收敛顶层到输入缓存的时序。
 *   - 共享输入缓存内部维护双帧 Ping-Pong bank 与 ready_bank_mask。
 *   - conv_core 只负责 token 调度和主计算，不直接关心 bank 管理细节。
 *
 * 接口语义:
 *   - img_wr_commit 表示当前帧写入结束。
 *   - img_wr_ready 表示当前仍存在可写 bank，并在提交窗口内保持屏蔽。
 */

module conv_subsystem #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output wire          busy,
    output wire          done,
    output wire          issue_done,

    input  wire          img_wr_en,
    input  wire [4:0]    img_wr_addr,
    input  wire [79:0]   img_wr_row_data,
    input  wire          img_wr_commit,
    output wire          img_wr_ready,

    output wire          out_stream_valid,
    output wire          out_stream_last,
    output wire [3:0]    out_stream_pos,
    output wire [2:0]    out_stream_group,
    output wire          out_stream_fire,
    output wire [511:0]  out_stream_data
);

    wire             pos_req_valid;
    wire [3:0]       pos_req_pos;
    wire             pos_window_valid;
    wire             consume_tick;
    wire [14*80-1:0] pos_window_data;

    wire              weight_rd_en;
    wire [2:0]        weight_rd_group;
    wire              bias_rd_en;
    wire [2:0]        bias_rd_group;
    wire [11*224-1:0] weight_data_bus;
    wire [63:0]       bias_data_bus;

    wire          tile_valid_int;
    wire          tile_last_int;
    wire [3:0]    tile_pos_int;
    wire [2:0]    tile_group_int;
    wire          tile_fire_int;
    wire [511:0]  tile_data_int;

    // Register the image-write interface for timing.
    reg            img_wr_en_r;
    reg [4:0]      img_wr_addr_r;
    reg [79:0]     img_wr_row_data_r;
    reg            img_wr_commit_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            img_wr_en_r       <= 1'b0;
            img_wr_addr_r     <= 5'd0;
            img_wr_row_data_r <= 80'd0;
            img_wr_commit_r   <= 1'b0;
        end else begin
            img_wr_en_r       <= img_wr_en;
            img_wr_addr_r     <= img_wr_addr;
            img_wr_row_data_r <= img_wr_row_data;
            img_wr_commit_r   <= img_wr_commit;
        end
    end

    wire [1:0] ready_bank_mask;
    wire       consume_bank_sel;
    wire       launch_start;
    wire       img_wr_ready_int;

    assign consume_bank_sel = ready_bank_mask[0] ? 1'b0 : 1'b1;
    assign launch_start     = start && (|ready_bank_mask);

    // Hide the extra input register stage from the upstream frame writer.
    // While commit is still in-flight, do not advertise the next frame slot yet.
    assign img_wr_ready = img_wr_ready_int && !img_wr_commit && !img_wr_commit_r;

    conv_shared_input_buffer u_conv_shared_input_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .img_wr_en(img_wr_en_r),
        .img_wr_addr(img_wr_addr_r),
        .img_wr_row_word(img_wr_row_data_r),
        .img_wr_commit(img_wr_commit_r),
        .img_wr_ready(img_wr_ready_int),

        .start_consume(launch_start),
        .consume_bank_sel(consume_bank_sel),
        .ready_bank_mask(ready_bank_mask),

        .pos_req_valid(pos_req_valid),
        .pos_req_pos(pos_req_pos),
        .pos_window_valid(pos_window_valid),
        .consume_tick(consume_tick),
        .pos_window_data(pos_window_data)
    );

    conv_param_store_rom u_conv_param_store (
        .clk(clk),
        .rst_n(rst_n),
        .weight_rd_en(weight_rd_en),
        .weight_rd_group(weight_rd_group),
        .bias_rd_en(bias_rd_en),
        .bias_rd_group(bias_rd_group),
        .weight_data_bus(weight_data_bus),
        .bias_data_bus(bias_data_bus)
    );

    conv_core #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_conv_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(launch_start),
        .busy(busy),
        .done(done),
        .issue_done(issue_done),

        .pos_req_valid(pos_req_valid),
        .pos_req_pos(pos_req_pos),
        .consume_tick(consume_tick),
        .pos_window_valid(pos_window_valid),
        .pos_window_data(pos_window_data),

        .weight_rd_en(weight_rd_en),
        .weight_rd_group(weight_rd_group),
        .bias_rd_en(bias_rd_en),
        .bias_rd_group(bias_rd_group),
        .weight_data_bus(weight_data_bus),
        .bias_data_bus(bias_data_bus),

        .out_stream_valid(tile_valid_int),
        .out_stream_last(tile_last_int),
        .out_stream_pos(tile_pos_int),
        .out_stream_group(tile_group_int),
        .out_stream_fire(tile_fire_int),
        .out_stream_data(tile_data_int)
    );

    assign out_stream_valid = tile_valid_int;
    assign out_stream_last  = tile_last_int;
    assign out_stream_pos   = tile_pos_int;
    assign out_stream_group = tile_group_int;
    assign out_stream_fire  = tile_fire_int;
    assign out_stream_data  = tile_data_int;

endmodule
