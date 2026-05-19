`timescale 1ns / 1ps

module pwconv_tile_mac_bank_mult (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [1023:0]      tile_data_bus,
    input  wire [8*4*4*8-1:0] weight_data_bus,
    output reg  [128*18-1:0]  out_partial_bus
);

    reg  [128*4*16-1:0] product_bus_reg;
    wire [128*4*16-1:0] product_bus_comb;
    wire [128*18-1:0]   partial_bus_comb;

    genvar g_group;
    genvar g_out;
    genvar g_spatial;
    generate
        for (g_group = 0; g_group < 8; g_group = g_group + 1) begin : G_GROUP
            for (g_out = 0; g_out < 4; g_out = g_out + 1) begin : G_OUT
                for (g_spatial = 0; g_spatial < 4; g_spatial = g_spatial + 1) begin : G_SPATIAL
                    localparam integer OUT_IDX = g_group * 16 + g_out * 4 + g_spatial;

                    wire signed [15:0] product_0;
                    wire signed [15:0] product_1;
                    wire signed [15:0] product_2;
                    wire signed [15:0] product_3;

                    wire signed [15:0] product_0_reg;
                    wire signed [15:0] product_1_reg;
                    wire signed [15:0] product_2_reg;
                    wire signed [15:0] product_3_reg;

                    wire signed [17:0] product_0_ext;
                    wire signed [17:0] product_1_ext;
                    wire signed [17:0] product_2_ext;
                    wire signed [17:0] product_3_ext;
                    wire signed [17:0] sum_l1_0;
                    wire signed [17:0] sum_l1_1;
                    wire signed [17:0] partial_point;

                    mult_cell u_mult_cell_0 (
                        .data(tile_data_bus[(g_group*16 + 0*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 0) * 8 +: 8]),
                        .out_prod(product_0)
                    );
                    mult_cell u_mult_cell_1 (
                        .data(tile_data_bus[(g_group*16 + 1*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 1) * 8 +: 8]),
                        .out_prod(product_1)
                    );
                    mult_cell u_mult_cell_2 (
                        .data(tile_data_bus[(g_group*16 + 2*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 2) * 8 +: 8]),
                        .out_prod(product_2)
                    );
                    mult_cell u_mult_cell_3 (
                        .data(tile_data_bus[(g_group*16 + 3*4 + g_spatial) * 8 +: 8]),
                        .wt  (weight_data_bus[(g_group*16 + g_out*4 + 3) * 8 +: 8]),
                        .out_prod(product_3)
                    );

                    assign product_bus_comb[((OUT_IDX * 4 + 0) * 16) +: 16] = product_0;
                    assign product_bus_comb[((OUT_IDX * 4 + 1) * 16) +: 16] = product_1;
                    assign product_bus_comb[((OUT_IDX * 4 + 2) * 16) +: 16] = product_2;
                    assign product_bus_comb[((OUT_IDX * 4 + 3) * 16) +: 16] = product_3;

                    assign product_0_reg = product_bus_reg[((OUT_IDX * 4 + 0) * 16) +: 16];
                    assign product_1_reg = product_bus_reg[((OUT_IDX * 4 + 1) * 16) +: 16];
                    assign product_2_reg = product_bus_reg[((OUT_IDX * 4 + 2) * 16) +: 16];
                    assign product_3_reg = product_bus_reg[((OUT_IDX * 4 + 3) * 16) +: 16];

                    assign product_0_ext = {{2{product_0_reg[15]}}, product_0_reg};
                    assign product_1_ext = {{2{product_1_reg[15]}}, product_1_reg};
                    assign product_2_ext = {{2{product_2_reg[15]}}, product_2_reg};
                    assign product_3_ext = {{2{product_3_reg[15]}}, product_3_reg};

                    assign sum_l1_0 = product_0_ext + product_1_ext;
                    assign sum_l1_1 = product_2_ext + product_3_ext;
                    assign partial_point = sum_l1_0 + sum_l1_1;

                    assign partial_bus_comb[(OUT_IDX * 18) +: 18] = partial_point;
                end
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_bus_reg  <= {(128*4*16){1'b0}};
            out_partial_bus  <= {(128*18){1'b0}};
        end else begin
            product_bus_reg  <= product_bus_comb;
            out_partial_bus  <= partial_bus_comb;
        end
    end

endmodule
