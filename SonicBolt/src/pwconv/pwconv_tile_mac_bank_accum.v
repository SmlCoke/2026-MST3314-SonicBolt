`timescale 1ns / 1ps

module pwconv_tile_mac_bank_accum (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire [128*18-1:0]  in_partial_bus,
    output reg                out_valid,
    output reg  [16*21-1:0]   out_accum_bus
);

    reg                  stage1_valid_reg;
    reg [16*2*20-1:0]    stage1_pair_bus_reg;
    wire [16*2*20-1:0]   stage1_pair_bus_comb;
    wire [16*21-1:0]     accum_bus_comb;

    genvar g_out;
    genvar g_spatial;
    generate
        for (g_out = 0; g_out < 4; g_out = g_out + 1) begin : G_OUT
            for (g_spatial = 0; g_spatial < 4; g_spatial = g_spatial + 1) begin : G_SPATIAL
                localparam integer IDX = g_out * 4 + g_spatial;

                wire signed [17:0] partial_0;
                wire signed [17:0] partial_1;
                wire signed [17:0] partial_2;
                wire signed [17:0] partial_3;
                wire signed [17:0] partial_4;
                wire signed [17:0] partial_5;
                wire signed [17:0] partial_6;
                wire signed [17:0] partial_7;
                wire signed [18:0] sum_l1_0;
                wire signed [18:0] sum_l1_1;
                wire signed [18:0] sum_l1_2;
                wire signed [18:0] sum_l1_3;
                wire signed [19:0] sum_l2_0;
                wire signed [19:0] sum_l2_1;
                wire signed [19:0] sum_l2_0_reg;
                wire signed [19:0] sum_l2_1_reg;
                wire signed [20:0] accum_point;

                assign partial_0 = in_partial_bus[((0*16 + IDX) * 18) +: 18];
                assign partial_1 = in_partial_bus[((1*16 + IDX) * 18) +: 18];
                assign partial_2 = in_partial_bus[((2*16 + IDX) * 18) +: 18];
                assign partial_3 = in_partial_bus[((3*16 + IDX) * 18) +: 18];
                assign partial_4 = in_partial_bus[((4*16 + IDX) * 18) +: 18];
                assign partial_5 = in_partial_bus[((5*16 + IDX) * 18) +: 18];
                assign partial_6 = in_partial_bus[((6*16 + IDX) * 18) +: 18];
                assign partial_7 = in_partial_bus[((7*16 + IDX) * 18) +: 18];

                assign sum_l1_0 = {{1{partial_0[17]}}, partial_0} + {{1{partial_1[17]}}, partial_1};
                assign sum_l1_1 = {{1{partial_2[17]}}, partial_2} + {{1{partial_3[17]}}, partial_3};
                assign sum_l1_2 = {{1{partial_4[17]}}, partial_4} + {{1{partial_5[17]}}, partial_5};
                assign sum_l1_3 = {{1{partial_6[17]}}, partial_6} + {{1{partial_7[17]}}, partial_7};

                assign sum_l2_0 = {{1{sum_l1_0[18]}}, sum_l1_0} + {{1{sum_l1_1[18]}}, sum_l1_1};
                assign sum_l2_1 = {{1{sum_l1_2[18]}}, sum_l1_2} + {{1{sum_l1_3[18]}}, sum_l1_3};

                assign stage1_pair_bus_comb[(IDX * 40) +: 20]      = sum_l2_0;
                assign stage1_pair_bus_comb[(IDX * 40 + 20) +: 20] = sum_l2_1;

                assign sum_l2_0_reg = stage1_pair_bus_reg[(IDX * 40) +: 20];
                assign sum_l2_1_reg = stage1_pair_bus_reg[(IDX * 40 + 20) +: 20];

                assign accum_point = {{1{sum_l2_0_reg[19]}}, sum_l2_0_reg} +
                                     {{1{sum_l2_1_reg[19]}}, sum_l2_1_reg};

                assign accum_bus_comb[(IDX * 21) +: 21] = accum_point;
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid_reg <= 1'b0;
            stage1_pair_bus_reg <= {(16*2*20){1'b0}};
            out_accum_bus <= {(16*21){1'b0}};
            out_valid <= 1'b0;
        end else begin
            stage1_valid_reg <= in_valid;
            if (in_valid) begin
                stage1_pair_bus_reg <= stage1_pair_bus_comb;
            end

            out_valid <= stage1_valid_reg;
            if (stage1_valid_reg) begin
                out_accum_bus <= accum_bus_comb;
            end
        end
    end

endmodule
