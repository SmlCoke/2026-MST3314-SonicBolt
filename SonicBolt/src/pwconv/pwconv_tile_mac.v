`timescale 1ns / 1ps

module pwconv_tile_mac (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire               in_last,
    input  wire [3:0]         in_pos,
    input  wire [2:0]         in_group,
    input  wire               in_fire,
    input  wire [1023:0]      tile_data_bus,
    input  wire [8*128-1:0]   weight_data_bus,
    input  wire [63:0]        bias_data_bus,
    output wire               out_valid,
    output wire               out_last,
    output wire [3:0]         out_pos,
    output wire [2:0]         out_group,
    output wire               out_fire,
    output wire [16*32-1:0]   out_accum_bus
);

    reg [1023:0]      stage1_tile_data;
    reg [8*128-1:0]   stage1_weight_data;
    reg [63:0]        stage1_bias_data;

    wire        stage1_valid;
    wire        stage1_last;
    wire [3:0]  stage1_pos;
    wire [2:0]  stage1_group;
    wire        stage1_fire;

    wire        stage2_valid;
    wire        stage2_last;
    wire [3:0]  stage2_pos;
    wire [2:0]  stage2_group;
    wire        stage2_fire;
    wire [63:0] stage2_bias_data;

    wire        stage3_valid;
    wire        stage3_last;
    wire [3:0]  stage3_pos;
    wire [2:0]  stage3_group;
    wire        stage3_fire;
    wire [63:0] stage3_bias_data;
    wire [128*18-1:0] stage3_partial_bus;

    wire        stage4_valid;
    wire        stage4_last;
    wire [3:0]  stage4_pos;
    wire [2:0]  stage4_group;
    wire        stage4_fire;
    wire [63:0] stage4_bias_data;

    wire        stage5_valid;
    wire        stage5_last;
    wire [3:0]  stage5_pos;
    wire [2:0]  stage5_group;
    wire        stage5_fire;
    wire [63:0] stage5_bias_data;
    wire        stage5_accum_valid;
    wire [16*21-1:0] stage5_accum_bus;

    wire        stage6_valid;
    wire        stage6_last;
    wire [3:0]  stage6_pos;
    wire [2:0]  stage6_group;
    wire        stage6_fire;
    wire [16*32-1:0] stage6_accum_bus;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_tile_data   <= 1024'd0;
            stage1_weight_data <= {(8*128){1'b0}};
            stage1_bias_data   <= 64'd0;
        end else begin
            stage1_tile_data   <= tile_data_bus;
            stage1_weight_data <= weight_data_bus;
            stage1_bias_data   <= bias_data_bus;
        end
    end

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
        .in_bias_bus(stage1_bias_data),
        .out_bias_bus(stage2_bias_data)
    );

    pwconv_tile_mac_bank_mult u_pwconv_tile_mac_bank_mult (
        .clk(clk),
        .rst_n(rst_n),
        .tile_data_bus(stage1_tile_data),
        .weight_data_bus(stage1_weight_data),
        .out_partial_bus(stage3_partial_bus)
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
        .in_bias_bus(stage2_bias_data),
        .out_bias_bus(stage3_bias_data)
    );

    pwconv_tile_mac_bank_accum u_pwconv_tile_mac_bank_accum (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage3_valid),
        .in_partial_bus(stage3_partial_bus),
        .out_valid(stage5_accum_valid),
        .out_accum_bus(stage5_accum_bus)
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
        .in_bias_bus(stage3_bias_data),
        .out_bias_bus(stage4_bias_data)
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

    bias_pipe u_bias_pipe_stage5 (
        .clk(clk),
        .rst_n(rst_n),
        .in_bias_bus(stage4_bias_data),
        .out_bias_bus(stage5_bias_data)
    );

    pwconv_tile_mac_bias_add u_pwconv_tile_mac_bias_add (
        .clk(clk),
        .rst_n(rst_n),
        .in_accum_bus(stage5_accum_bus),
        .in_bias_bus(stage5_bias_data),
        .out_accum_bus(stage6_accum_bus)
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

    assign out_valid     = stage6_valid;
    assign out_last      = stage6_last;
    assign out_pos       = stage6_pos;
    assign out_group     = stage6_group;
    assign out_fire      = stage6_fire;
    assign out_accum_bus = stage6_accum_bus;

endmodule
