`timescale 1ns / 1ps

module dwconv_tile_mac_row_mult (
    input  wire                clk,
    input  wire                rst_n,
    input  wire [4*2*4*8-1:0]  row_window_data,
    input  wire [4*3*8-1:0]    weight_row_data,
    output reg  [4*2*2*18-1:0] out_row_sum_bus
);

    reg [4*2*4*8-1:0] row_window_data_reg;
    reg [4*3*8-1:0]   weight_row_data_reg;
    reg [4*2*2*3*16-1:0] product_bus_reg;

    wire [4*2*2*3*16-1:0] product_bus_comb;
    wire [4*2*2*18-1:0]   row_sum_bus_comb;

    genvar g_ch;
    genvar g_oy;
    genvar g_ox;
    generate
        for (g_ch = 0; g_ch < 4; g_ch = g_ch + 1) begin : CH_LOOP
            for (g_oy = 0; g_oy < 2; g_oy = g_oy + 1) begin : OY_LOOP
                for (g_ox = 0; g_ox < 2; g_ox = g_ox + 1) begin : OX_LOOP
                    localparam integer OUT_IDX = g_ch * 4 + g_oy * 2 + g_ox;

                    wire signed [15:0] p_0;
                    wire signed [15:0] p_1;
                    wire signed [15:0] p_2;

                    wire signed [15:0] prod_0_reg;
                    wire signed [15:0] prod_1_reg;
                    wire signed [15:0] prod_2_reg;

                    wire signed [17:0] prod_0_ext;
                    wire signed [17:0] prod_1_ext;
                    wire signed [17:0] prod_2_ext;
                    wire signed [17:0] sum_l1_0;
                    wire signed [17:0] row_sum_point;

                    assign p_0 = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 0) * 8 +: 8]) *
                                 $signed(weight_row_data_reg[(g_ch * 24) + (0 * 8) +: 8]);
                    assign p_1 = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 1) * 8 +: 8]) *
                                 $signed(weight_row_data_reg[(g_ch * 24) + (1 * 8) +: 8]);
                    assign p_2 = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 2) * 8 +: 8]) *
                                 $signed(weight_row_data_reg[(g_ch * 24) + (2 * 8) +: 8]);

                    assign product_bus_comb[((OUT_IDX * 3 + 0) * 16) +: 16] = p_0;
                    assign product_bus_comb[((OUT_IDX * 3 + 1) * 16) +: 16] = p_1;
                    assign product_bus_comb[((OUT_IDX * 3 + 2) * 16) +: 16] = p_2;

                    assign prod_0_reg = product_bus_reg[((OUT_IDX * 3 + 0) * 16) +: 16];
                    assign prod_1_reg = product_bus_reg[((OUT_IDX * 3 + 1) * 16) +: 16];
                    assign prod_2_reg = product_bus_reg[((OUT_IDX * 3 + 2) * 16) +: 16];

                    assign prod_0_ext = {{2{prod_0_reg[15]}}, prod_0_reg};
                    assign prod_1_ext = {{2{prod_1_reg[15]}}, prod_1_reg};
                    assign prod_2_ext = {{2{prod_2_reg[15]}}, prod_2_reg};

                    assign sum_l1_0    = prod_0_ext + prod_1_ext;
                    assign row_sum_point = sum_l1_0 + prod_2_ext;

                    assign row_sum_bus_comb[(OUT_IDX * 18) +: 18] = row_sum_point;
                end
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {4*2*4*8{1'b0}};
            weight_row_data_reg <= {4*3*8{1'b0}};
            product_bus_reg     <= {4*2*2*3*16{1'b0}};
            out_row_sum_bus     <= {4*2*2*18{1'b0}};
        end else begin
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;
            product_bus_reg     <= product_bus_comb;
            out_row_sum_bus     <= row_sum_bus_comb;
        end
    end

endmodule
