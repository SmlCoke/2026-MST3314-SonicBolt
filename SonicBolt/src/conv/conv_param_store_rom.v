`timescale 1ns / 1ps

module conv_param_store_rom (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bias_rd_en,
    input  wire [2:0]  bias_rd_group,
    output wire [63:0] bias_data_bus
);

    reg [63:0] bias_data_bus_reg;

    function [63:0] conv_bias_lookup;
        input [2:0] addr;
        begin
            case (addr)
                3'd0: conv_bias_lookup = 64'heac7f012ecbe1532;
                3'd1: conv_bias_lookup = 64'hf560f124f458037b;
                3'd2: conv_bias_lookup = 64'h0d81fd2ae9db0c77;
                3'd3: conv_bias_lookup = 64'h05f9036cf12bff9f;
                3'd4: conv_bias_lookup = 64'h0b160bde0f52eaf7;
                3'd5: conv_bias_lookup = 64'h0dee016de7fd04ca;
                3'd6: conv_bias_lookup = 64'h0a70e874f13d121c;
                3'd7: conv_bias_lookup = 64'h171011e6fc830327;
                default: conv_bias_lookup = 64'h0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_data_bus_reg <= 64'd0;
        end else if (bias_rd_en) begin
            bias_data_bus_reg <= conv_bias_lookup(bias_rd_group);
        end
    end

    assign bias_data_bus = bias_data_bus_reg;

endmodule
