`timescale 1ns / 1ps

module conv_tile_mac_row_add (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [11*608-1:0]   in_row_sum_bus,
    input  wire [4*16-1:0]     bias_data_bus,
    output reg  [1023:0]       out_sum_bus
);

    integer idx;

    reg signed [19:0] partial_0 [0:31];
    reg signed [19:0] partial_1 [0:31];
    reg signed [19:0] partial_2 [0:31];
    reg signed [19:0] partial_3 [0:31];
    reg signed [19:0] partial_4 [0:31];
    reg signed [19:0] partial_5 [0:31];
    reg signed [21:0] stage2_sum_0 [0:31];
    reg signed [21:0] stage2_sum_1 [0:31];

    wire [32*120-1:0] stage1_partial_bus_comb;
    wire [32*44-1:0]  stage2_pair_bus_comb;
    wire [1024-1:0]   stage3_sum_bus_comb;

    genvar g_idx;
    generate
        for (g_idx = 0; g_idx < 32; g_idx = g_idx + 1) begin : G_CELL
            localparam integer IDX = g_idx;

            wire signed [18:0] row_0;
            wire signed [18:0] row_1;
            wire signed [18:0] row_2;
            wire signed [18:0] row_3;
            wire signed [18:0] row_4;
            wire signed [18:0] row_5;
            wire signed [18:0] row_6;
            wire signed [18:0] row_7;
            wire signed [18:0] row_8;
            wire signed [18:0] row_9;
            wire signed [18:0] row_10;
            wire signed [15:0] bias_val;

            wire signed [19:0] p0;
            wire signed [19:0] p1;
            wire signed [19:0] p2;
            wire signed [19:0] p3;
            wire signed [19:0] p4;
            wire signed [19:0] p5;

            wire signed [20:0] s0_l1;
            wire signed [20:0] s1_l1;
            wire signed [20:0] s2_l1;
            wire signed [21:0] s0_l2;
            wire signed [21:0] s1_l2;
            wire signed [21:0] s0_l2_reg;
            wire signed [21:0] s1_l2_reg;
            wire signed [31:0] sum_point;

            assign row_0  = in_row_sum_bus[(0*608)  + IDX*19 +: 19];
            assign row_1  = in_row_sum_bus[(1*608)  + IDX*19 +: 19];
            assign row_2  = in_row_sum_bus[(2*608)  + IDX*19 +: 19];
            assign row_3  = in_row_sum_bus[(3*608)  + IDX*19 +: 19];
            assign row_4  = in_row_sum_bus[(4*608)  + IDX*19 +: 19];
            assign row_5  = in_row_sum_bus[(5*608)  + IDX*19 +: 19];
            assign row_6  = in_row_sum_bus[(6*608)  + IDX*19 +: 19];
            assign row_7  = in_row_sum_bus[(7*608)  + IDX*19 +: 19];
            assign row_8  = in_row_sum_bus[(8*608)  + IDX*19 +: 19];
            assign row_9  = in_row_sum_bus[(9*608)  + IDX*19 +: 19];
            assign row_10 = in_row_sum_bus[(10*608) + IDX*19 +: 19];
            assign bias_val = bias_data_bus[(IDX / 8) * 16 +: 16];

            conv_tile_mac_reduce11_stage1_cell u_stage1_cell (
                .row_0(row_0),
                .row_1(row_1),
                .row_2(row_2),
                .row_3(row_3),
                .row_4(row_4),
                .row_5(row_5),
                .row_6(row_6),
                .row_7(row_7),
                .row_8(row_8),
                .row_9(row_9),
                .row_10(row_10),
                .bias_val(bias_val),
                .partial_0(p0),
                .partial_1(p1),
                .partial_2(p2),
                .partial_3(p3),
                .partial_4(p4),
                .partial_5(p5)
            );

            assign stage1_partial_bus_comb[(IDX*120) +: 20]       = p0;
            assign stage1_partial_bus_comb[(IDX*120 + 20) +: 20]  = p1;
            assign stage1_partial_bus_comb[(IDX*120 + 40) +: 20]  = p2;
            assign stage1_partial_bus_comb[(IDX*120 + 60) +: 20]  = p3;
            assign stage1_partial_bus_comb[(IDX*120 + 80) +: 20]  = p4;
            assign stage1_partial_bus_comb[(IDX*120 + 100) +: 20] = p5;

            assign s0_l1 = partial_0[IDX] + partial_1[IDX];
            assign s1_l1 = partial_2[IDX] + partial_3[IDX];
            assign s2_l1 = partial_4[IDX] + partial_5[IDX];

            assign s0_l2 = {{1{s0_l1[20]}}, s0_l1} + {{1{s1_l1[20]}}, s1_l1};
            assign s1_l2 = {{1{s2_l1[20]}}, s2_l1};

            assign stage2_pair_bus_comb[(IDX * 44) +: 22]      = s0_l2;
            assign stage2_pair_bus_comb[(IDX * 44 + 22) +: 22] = s1_l2;

            assign s0_l2_reg = stage2_sum_0[IDX];
            assign s1_l2_reg = stage2_sum_1[IDX];

            assign sum_point = {{10{s0_l2_reg[21]}}, s0_l2_reg} +
                               {{10{s1_l2_reg[21]}}, s1_l2_reg};

            assign stage3_sum_bus_comb[(IDX*32) +: 32] = sum_point;
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < 32; idx = idx + 1) begin
                partial_0[idx]   <= 20'sd0;
                partial_1[idx]   <= 20'sd0;
                partial_2[idx]   <= 20'sd0;
                partial_3[idx]   <= 20'sd0;
                partial_4[idx]   <= 20'sd0;
                partial_5[idx]   <= 20'sd0;
                stage2_sum_0[idx] <= 22'sd0;
                stage2_sum_1[idx] <= 22'sd0;
            end
            out_sum_bus <= {1024{1'b0}};
        end else begin
            for (idx = 0; idx < 32; idx = idx + 1) begin
                partial_0[idx]   <= stage1_partial_bus_comb[(idx*120) +: 20];
                partial_1[idx]   <= stage1_partial_bus_comb[(idx*120 + 20) +: 20];
                partial_2[idx]   <= stage1_partial_bus_comb[(idx*120 + 40) +: 20];
                partial_3[idx]   <= stage1_partial_bus_comb[(idx*120 + 60) +: 20];
                partial_4[idx]   <= stage1_partial_bus_comb[(idx*120 + 80) +: 20];
                partial_5[idx]   <= stage1_partial_bus_comb[(idx*120 + 100) +: 20];
                stage2_sum_0[idx] <= stage2_pair_bus_comb[(idx * 44) +: 22];
                stage2_sum_1[idx] <= stage2_pair_bus_comb[(idx * 44 + 22) +: 22];
            end
            out_sum_bus <= stage3_sum_bus_comb;
        end
    end

endmodule
