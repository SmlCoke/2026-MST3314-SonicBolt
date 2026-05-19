`timescale 1ns / 1ps

module conv_tile_mac_row_mult (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [2*10*8-1:0]   row_window_data,
    input  wire [4*7*8-1:0]    weight_row_data,
    output reg  [4*2*4*19-1:0] out_row_sum_bus
);

    reg [2*10*8-1:0] row_window_data_reg;
    reg [4*7*8-1:0]  weight_row_data_reg;
    reg [4*2*4*7*16-1:0] product_bus_reg;
    reg [4*2*4*2*19-1:0] pair_sum_bus_reg;

    wire [4*2*4*7*16-1:0] product_bus_comb;
    wire [4*2*4*2*19-1:0] pair_sum_bus_comb;
    wire [4*2*4*19-1:0]   row_sum_bus_comb;

    genvar g_ch;
    genvar g_oy;
    genvar g_ox;
    generate
        for (g_ch = 0; g_ch < 4; g_ch = g_ch + 1) begin : G_CH
            for (g_oy = 0; g_oy < 2; g_oy = g_oy + 1) begin : G_OY
                for (g_ox = 0; g_ox < 4; g_ox = g_ox + 1) begin : G_OX
                    localparam integer OUT_IDX   = g_ch * 8 + g_oy * 4 + g_ox;
                    localparam integer DATA_BASE = (g_oy * 10 + g_ox) * 8;
                    localparam integer WT_BASE   = g_ch * 56;

                    wire signed [15:0] product_0;
                    wire signed [15:0] product_1;
                    wire signed [15:0] product_2;
                    wire signed [15:0] product_3;
                    wire signed [15:0] product_4;
                    wire signed [15:0] product_5;
                    wire signed [15:0] product_6;

                    wire signed [15:0] product_0_reg;
                    wire signed [15:0] product_1_reg;
                    wire signed [15:0] product_2_reg;
                    wire signed [15:0] product_3_reg;
                    wire signed [15:0] product_4_reg;
                    wire signed [15:0] product_5_reg;
                    wire signed [15:0] product_6_reg;

                    wire signed [18:0] product_0_ext;
                    wire signed [18:0] product_1_ext;
                    wire signed [18:0] product_2_ext;
                    wire signed [18:0] product_3_ext;
                    wire signed [18:0] product_4_ext;
                    wire signed [18:0] product_5_ext;
                    wire signed [18:0] product_6_ext;
                    wire signed [18:0] sum_l1_0;
                    wire signed [18:0] sum_l1_1;
                    wire signed [18:0] sum_l1_2;
                    wire signed [18:0] sum_l2_0;
                    wire signed [18:0] sum_l2_1;
                    wire signed [18:0] sum_l2_0_reg;
                    wire signed [18:0] sum_l2_1_reg;
                    wire signed [18:0] row_sum_point;

                    mult_cell u_mult_cell_0 (
                        .data(row_window_data_reg[(DATA_BASE + 0*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 0*8) +: 8]),
                        .out_prod(product_0)
                    );
                    mult_cell u_mult_cell_1 (
                        .data(row_window_data_reg[(DATA_BASE + 1*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 1*8) +: 8]),
                        .out_prod(product_1)
                    );
                    mult_cell u_mult_cell_2 (
                        .data(row_window_data_reg[(DATA_BASE + 2*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 2*8) +: 8]),
                        .out_prod(product_2)
                    );
                    mult_cell u_mult_cell_3 (
                        .data(row_window_data_reg[(DATA_BASE + 3*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 3*8) +: 8]),
                        .out_prod(product_3)
                    );
                    mult_cell u_mult_cell_4 (
                        .data(row_window_data_reg[(DATA_BASE + 4*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 4*8) +: 8]),
                        .out_prod(product_4)
                    );
                    mult_cell u_mult_cell_5 (
                        .data(row_window_data_reg[(DATA_BASE + 5*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 5*8) +: 8]),
                        .out_prod(product_5)
                    );
                    mult_cell u_mult_cell_6 (
                        .data(row_window_data_reg[(DATA_BASE + 6*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 6*8) +: 8]),
                        .out_prod(product_6)
                    );

                    assign product_bus_comb[((OUT_IDX * 7 + 0) * 16) +: 16] = product_0;
                    assign product_bus_comb[((OUT_IDX * 7 + 1) * 16) +: 16] = product_1;
                    assign product_bus_comb[((OUT_IDX * 7 + 2) * 16) +: 16] = product_2;
                    assign product_bus_comb[((OUT_IDX * 7 + 3) * 16) +: 16] = product_3;
                    assign product_bus_comb[((OUT_IDX * 7 + 4) * 16) +: 16] = product_4;
                    assign product_bus_comb[((OUT_IDX * 7 + 5) * 16) +: 16] = product_5;
                    assign product_bus_comb[((OUT_IDX * 7 + 6) * 16) +: 16] = product_6;

                    assign product_0_reg = product_bus_reg[((OUT_IDX * 7 + 0) * 16) +: 16];
                    assign product_1_reg = product_bus_reg[((OUT_IDX * 7 + 1) * 16) +: 16];
                    assign product_2_reg = product_bus_reg[((OUT_IDX * 7 + 2) * 16) +: 16];
                    assign product_3_reg = product_bus_reg[((OUT_IDX * 7 + 3) * 16) +: 16];
                    assign product_4_reg = product_bus_reg[((OUT_IDX * 7 + 4) * 16) +: 16];
                    assign product_5_reg = product_bus_reg[((OUT_IDX * 7 + 5) * 16) +: 16];
                    assign product_6_reg = product_bus_reg[((OUT_IDX * 7 + 6) * 16) +: 16];

                    assign product_0_ext = {{3{product_0_reg[15]}}, product_0_reg};
                    assign product_1_ext = {{3{product_1_reg[15]}}, product_1_reg};
                    assign product_2_ext = {{3{product_2_reg[15]}}, product_2_reg};
                    assign product_3_ext = {{3{product_3_reg[15]}}, product_3_reg};
                    assign product_4_ext = {{3{product_4_reg[15]}}, product_4_reg};
                    assign product_5_ext = {{3{product_5_reg[15]}}, product_5_reg};
                    assign product_6_ext = {{3{product_6_reg[15]}}, product_6_reg};

                    assign sum_l1_0 = product_0_ext + product_1_ext;
                    assign sum_l1_1 = product_2_ext + product_3_ext;
                    assign sum_l1_2 = product_4_ext + product_5_ext;
                    assign sum_l2_0 = sum_l1_0 + sum_l1_1;
                    assign sum_l2_1 = sum_l1_2 + product_6_ext;

                    assign pair_sum_bus_comb[((OUT_IDX * 2 + 0) * 19) +: 19] = sum_l2_0;
                    assign pair_sum_bus_comb[((OUT_IDX * 2 + 1) * 19) +: 19] = sum_l2_1;

                    assign sum_l2_0_reg = pair_sum_bus_reg[((OUT_IDX * 2 + 0) * 19) +: 19];
                    assign sum_l2_1_reg = pair_sum_bus_reg[((OUT_IDX * 2 + 1) * 19) +: 19];

                    assign row_sum_point = sum_l2_0_reg + sum_l2_1_reg;
                    assign row_sum_bus_comb[(OUT_IDX * 19) +: 19] = row_sum_point;
                end
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {2*10*8{1'b0}};
            weight_row_data_reg <= {4*7*8{1'b0}};
            product_bus_reg     <= {4*2*4*7*16{1'b0}};
            pair_sum_bus_reg    <= {4*2*4*2*19{1'b0}};
            out_row_sum_bus     <= {4*2*4*19{1'b0}};
        end else begin
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;
            product_bus_reg     <= product_bus_comb;
            pair_sum_bus_reg    <= pair_sum_bus_comb;
            out_row_sum_bus     <= row_sum_bus_comb;
        end
    end

endmodule
