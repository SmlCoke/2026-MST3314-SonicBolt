`timescale 1ns / 1ps

module conv_tile_mac (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                in_valid,
    input  wire                in_last,
    input  wire [3:0]          in_pos,
    input  wire [2:0]          in_group,
    input  wire                in_fire,
    input  wire [14*10*8-1:0]  pos_window_data,
    input  wire [11*4*7*8-1:0] weight_data_bus,
    input  wire [4*16-1:0]     bias_data_bus,
    output wire                out_valid,
    output wire                out_last,
    output wire [3:0]          out_pos,
    output wire [2:0]          out_group,
    output wire                out_fire,
    output wire [4*2*4*32-1:0] out_accum_bus
);

    wire [63:0] stage1_bias_bus;
    wire        stage1_valid;
    wire        stage1_last;
    wire [3:0]  stage1_pos;
    wire [2:0]  stage1_group;
    wire        stage1_fire;

    wire [4*2*4*19-1:0] row_sum_bus_0;
    wire [4*2*4*19-1:0] row_sum_bus_1;
    wire [4*2*4*19-1:0] row_sum_bus_2;
    wire [4*2*4*19-1:0] row_sum_bus_3;
    wire [4*2*4*19-1:0] row_sum_bus_4;
    wire [4*2*4*19-1:0] row_sum_bus_5;
    wire [4*2*4*19-1:0] row_sum_bus_6;
    wire [4*2*4*19-1:0] row_sum_bus_7;
    wire [4*2*4*19-1:0] row_sum_bus_8;
    wire [4*2*4*19-1:0] row_sum_bus_9;
    wire [4*2*4*19-1:0] row_sum_bus_10;
    wire [11*4*2*4*19-1:0] stage4_row_sum_bus;

    wire [63:0] stage2_bias_bus;
    wire        stage2_valid;
    wire        stage2_last;
    wire [3:0]  stage2_pos;
    wire [2:0]  stage2_group;
    wire        stage2_fire;

    wire [63:0] stage3_bias_bus;
    wire        stage3_valid;
    wire        stage3_last;
    wire [3:0]  stage3_pos;
    wire [2:0]  stage3_group;
    wire        stage3_fire;

    wire [63:0] stage4_bias_bus;
    wire        stage4_valid;
    wire        stage4_last;
    wire [3:0]  stage4_pos;
    wire [2:0]  stage4_group;
    wire        stage4_fire;

    wire        stage5_valid;
    wire        stage5_last;
    wire [3:0]  stage5_pos;
    wire [2:0]  stage5_group;
    wire        stage5_fire;

    wire        stage6_valid;
    wire        stage6_last;
    wire [3:0]  stage6_pos;
    wire [2:0]  stage6_group;
    wire        stage6_fire;

    wire        stage7_valid;
    wire        stage7_last;
    wire [3:0]  stage7_pos;
    wire [2:0]  stage7_group;
    wire        stage7_fire;

    bias_pipe u_bias_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(bias_data_bus),
        .out_bias_bus(stage1_bias_bus)
    );

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

    conv_tile_mac_row_mult u_row_mult_0 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[2*80-1:0]),
        .weight_row_data(weight_data_bus[224-1:0]),
        .out_row_sum_bus(row_sum_bus_0)
    );
    conv_tile_mac_row_mult u_row_mult_1 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[3*80-1:1*80]),
        .weight_row_data(weight_data_bus[2*224-1:1*224]),
        .out_row_sum_bus(row_sum_bus_1)
    );
    conv_tile_mac_row_mult u_row_mult_2 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[4*80-1:2*80]),
        .weight_row_data(weight_data_bus[3*224-1:2*224]),
        .out_row_sum_bus(row_sum_bus_2)
    );
    conv_tile_mac_row_mult u_row_mult_3 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[5*80-1:3*80]),
        .weight_row_data(weight_data_bus[4*224-1:3*224]),
        .out_row_sum_bus(row_sum_bus_3)
    );
    conv_tile_mac_row_mult u_row_mult_4 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[6*80-1:4*80]),
        .weight_row_data(weight_data_bus[5*224-1:4*224]),
        .out_row_sum_bus(row_sum_bus_4)
    );
    conv_tile_mac_row_mult u_row_mult_5 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[7*80-1:5*80]),
        .weight_row_data(weight_data_bus[6*224-1:5*224]),
        .out_row_sum_bus(row_sum_bus_5)
    );
    conv_tile_mac_row_mult u_row_mult_6 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[8*80-1:6*80]),
        .weight_row_data(weight_data_bus[7*224-1:6*224]),
        .out_row_sum_bus(row_sum_bus_6)
    );
    conv_tile_mac_row_mult u_row_mult_7 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[9*80-1:7*80]),
        .weight_row_data(weight_data_bus[8*224-1:7*224]),
        .out_row_sum_bus(row_sum_bus_7)
    );
    conv_tile_mac_row_mult u_row_mult_8 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[10*80-1:8*80]),
        .weight_row_data(weight_data_bus[9*224-1:8*224]),
        .out_row_sum_bus(row_sum_bus_8)
    );
    conv_tile_mac_row_mult u_row_mult_9 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[11*80-1:9*80]),
        .weight_row_data(weight_data_bus[10*224-1:9*224]),
        .out_row_sum_bus(row_sum_bus_9)
    );
    conv_tile_mac_row_mult u_row_mult_10 (
        .clk(clk),
        .rst_n(rst_n),
        .row_window_data(pos_window_data[12*80-1:10*80]),
        .weight_row_data(weight_data_bus[11*224-1:10*224]),
        .out_row_sum_bus(row_sum_bus_10)
    );

    assign stage4_row_sum_bus = {
        row_sum_bus_10, row_sum_bus_9, row_sum_bus_8, row_sum_bus_7, row_sum_bus_6, row_sum_bus_5,
        row_sum_bus_4, row_sum_bus_3, row_sum_bus_2, row_sum_bus_1, row_sum_bus_0
    };

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

    bias_pipe u_bias_pipe_stage4 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage3_bias_bus),
        .out_bias_bus(stage4_bias_bus)
    );

    conv_tile_mac_row_add u_conv_tile_mac_row_add (
        .clk(clk),
        .rst_n(rst_n),
        .in_row_sum_bus(stage4_row_sum_bus),
        .bias_data_bus(stage4_bias_bus),
        .out_sum_bus(out_accum_bus)
    );

    meta_pipe u_meta_pipe_stage5 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage4_valid),
        .in_last(stage4_last),
        .in_pos(stage4_pos),
        .in_group(stage4_group),
        .in_fire(stage4_fire),
        .out_valid(stage5_valid),
        .out_last(stage5_last),
        .out_pos(stage5_pos),
        .out_group(stage5_group),
        .out_fire(stage5_fire)
    );

    meta_pipe u_meta_pipe_stage6 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage5_valid),
        .in_last(stage5_last),
        .in_pos(stage5_pos),
        .in_group(stage5_group),
        .in_fire(stage5_fire),
        .out_valid(stage6_valid),
        .out_last(stage6_last),
        .out_pos(stage6_pos),
        .out_group(stage6_group),
        .out_fire(stage6_fire)
    );

    meta_pipe u_meta_pipe_stage7 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage6_valid),
        .in_last(stage6_last),
        .in_pos(stage6_pos),
        .in_group(stage6_group),
        .in_fire(stage6_fire),
        .out_valid(stage7_valid),
        .out_last(stage7_last),
        .out_pos(stage7_pos),
        .out_group(stage7_group),
        .out_fire(stage7_fire)
    );

    assign out_valid = stage7_valid;
    assign out_last  = stage7_last;
    assign out_pos   = stage7_pos;
    assign out_group = stage7_group;
    assign out_fire  = stage7_fire;

endmodule
