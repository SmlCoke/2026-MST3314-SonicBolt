`timescale 1ns / 1ps

module dwconv_tile_mac (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                in_valid,
    input  wire                in_last,
    input  wire [3:0]          in_pos,
    input  wire [2:0]          in_group,
    input  wire                in_fire,
    input  wire [4*4*4*8-1:0]  in_data_bus,
    input  wire [3*4*3*8-1:0]  weight_data_bus,
    input  wire [4*16-1:0]     bias_data_bus,
    output wire                out_valid,
    output wire                out_last,
    output wire [3:0]          out_pos,
    output wire [2:0]          out_group,
    output wire                out_fire,
    output wire [4*2*2*32-1:0] out_accum_bus
);

    wire                stage1_valid;
    wire                stage1_last;
    wire [3:0]          stage1_pos;
    wire [2:0]          stage1_group;
    wire                stage1_fire;
    wire [4*16-1:0]     stage1_bias_bus;

    wire [4*2*2*18-1:0] row_sum_bus_0;
    wire [4*2*2*18-1:0] row_sum_bus_1;
    wire [4*2*2*18-1:0] row_sum_bus_2;
    wire [3*4*2*2*18-1:0] stage2_row_sum_bus;

    wire                stage2_valid;
    wire                stage2_last;
    wire [3:0]          stage2_pos;
    wire [2:0]          stage2_group;
    wire                stage2_fire;
    wire [4*16-1:0]     stage2_bias_bus;

    wire                stage3_valid;
    wire                stage3_last;
    wire [3:0]          stage3_pos;
    wire [2:0]          stage3_group;
    wire                stage3_fire;
    wire [4*16-1:0]     stage3_bias_bus;

    wire                stage4_valid;
    wire                stage4_last;
    wire [3:0]          stage4_pos;
    wire [2:0]          stage4_group;
    wire                stage4_fire;

    wire [4*2*4*8-1:0] row_window_data_0;
    wire [4*2*4*8-1:0] row_window_data_1;
    wire [4*2*4*8-1:0] row_window_data_2;

    assign row_window_data_0 = {in_data_bus[384 +: 64], in_data_bus[256 +: 64], in_data_bus[128 +: 64], in_data_bus[0 +: 64]};
    assign row_window_data_1 = {in_data_bus[(384 + 32) +: 64], in_data_bus[(256 + 32) +: 64], in_data_bus[(128 + 32) +: 64], in_data_bus[32 +: 64]};
    assign row_window_data_2 = {in_data_bus[(384 + 64) +: 64], in_data_bus[(256 + 64) +: 64], in_data_bus[(128 + 64) +: 64], in_data_bus[64 +: 64]};

    meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_last(in_last),
        .in_pos(in_pos),
        .in_group(in_group),
        .in_fire(in_fire),
        .out_valid(stage1_valid),
        .out_last(stage1_last),
        .out_pos(stage1_pos),
        .out_group(stage1_group),
        .out_fire(stage1_fire)
    );

    bias_pipe u_bias_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(bias_data_bus),
        .out_bias_bus(stage1_bias_bus)
    );

    dwconv_tile_mac_row_mult u_mac_row_mult_0 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(row_window_data_0),
        .weight_row_data(weight_data_bus[4*3*8-1:0]),
        .out_row_sum_bus(row_sum_bus_0)
    );

    dwconv_tile_mac_row_mult u_mac_row_mult_1 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(row_window_data_1),
        .weight_row_data(weight_data_bus[2*4*3*8-1:4*3*8]),
        .out_row_sum_bus(row_sum_bus_1)
    );

    dwconv_tile_mac_row_mult u_mac_row_mult_2 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(row_window_data_2),
        .weight_row_data(weight_data_bus[3*4*3*8-1:2*4*3*8]),
        .out_row_sum_bus(row_sum_bus_2)
    );

    assign stage2_row_sum_bus = {row_sum_bus_2, row_sum_bus_1, row_sum_bus_0};

    meta_pipe u_meta_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .in_fire(stage1_fire),
        .out_valid(stage2_valid),
        .out_last(stage2_last),
        .out_pos(stage2_pos),
        .out_group(stage2_group),
        .out_fire(stage2_fire)
    );

    bias_pipe u_bias_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage1_bias_bus),
        .out_bias_bus(stage2_bias_bus)
    );

    meta_pipe u_meta_pipe_stage3 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2_valid),
        .in_last(stage2_last),
        .in_pos(stage2_pos),
        .in_group(stage2_group),
        .in_fire(stage2_fire),
        .out_valid(stage3_valid),
        .out_last(stage3_last),
        .out_pos(stage3_pos),
        .out_group(stage3_group),
        .out_fire(stage3_fire)
    );

    bias_pipe u_bias_pipe_stage3 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage2_bias_bus),
        .out_bias_bus(stage3_bias_bus)
    );

    dwconv_tile_mac_row_add u_tile_mac_row_add (
        .clk(clk),
        .rst_n(rst_n),
        .in_row_sum_bus(stage2_row_sum_bus),
        .bias_data_bus(stage3_bias_bus),
        .out_sum_bus(out_accum_bus)
    );

    meta_pipe u_meta_pipe_stage4 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage3_valid),
        .in_last(stage3_last),
        .in_pos(stage3_pos),
        .in_group(stage3_group),
        .in_fire(stage3_fire),
        .out_valid(stage4_valid),
        .out_last(stage4_last),
        .out_pos(stage4_pos),
        .out_group(stage4_group),
        .out_fire(stage4_fire)
    );

    assign out_valid = stage4_valid;
    assign out_last  = stage4_last;
    assign out_pos   = stage4_pos;
    assign out_group = stage4_group;
    assign out_fire  = stage4_fire;

endmodule
