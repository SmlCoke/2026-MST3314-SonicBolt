`timescale 1ns / 1ps
module dwconv_param_store_rom (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             weight_rd_en,
    input  wire [2:0]       weight_rd_group,
    input  wire             bias_rd_en,
    input  wire [2:0]       bias_rd_group,
    output wire [3*96-1:0]  weight_data_bus,
    output wire [63:0]      bias_data_bus
);

    localparam integer WEIGHT_BANK_COUNT = 3;
    localparam integer GROUP_COUNT = 8;

    reg [3*96-1:0] weight_data_bus_reg;
    reg [63:0]     bias_data_bus_reg;
    integer idx;

    function [95:0] dwconv_weight_lookup;
        input [4:0] addr;
        begin
            case (addr)
            5'd0: dwconv_weight_lookup = 96'h33fbfaf4f905191807f905f8;
            5'd1: dwconv_weight_lookup = 96'hea1e2512eef5f70f0e0dff0e;
            5'd2: dwconv_weight_lookup = 96'hf6fded0fed00d11bd6161803;
            5'd3: dwconv_weight_lookup = 96'hf3fe12fbf11002f5fd0ceb1b;
            5'd4: dwconv_weight_lookup = 96'hf20d14fd10fe01ed0b03b8f0;
            5'd5: dwconv_weight_lookup = 96'h0308130c04111dfa0910fa08;
            5'd6: dwconv_weight_lookup = 96'h11eeef0502030ffefc1aebe7;
            5'd7: dwconv_weight_lookup = 96'h21c8eb12e002daeee9331c02;
            5'd8: dwconv_weight_lookup = 96'hf6ecea05080c060c00dc0a16;
            5'd9: dwconv_weight_lookup = 96'he922f1040cef0e0cfe060a05;
            5'd10: dwconv_weight_lookup = 96'hf00a09e11efb321010f5f80e;
            5'd11: dwconv_weight_lookup = 96'h03f5fcfc0512e61a10ebe719;
            5'd12: dwconv_weight_lookup = 96'hf3ec1bfb13eb111602801637;
            5'd13: dwconv_weight_lookup = 96'hf90b0c06fa01faf10500fe0f;
            5'd14: dwconv_weight_lookup = 96'hd3090c04090a061ff0191ce2;
            5'd15: dwconv_weight_lookup = 96'h2c190ef004021a032529f401;
            5'd16: dwconv_weight_lookup = 96'hfe0efcfd060cf30d12f4fb25;
            5'd17: dwconv_weight_lookup = 96'hdff3f4f1ecfef9fd0f0b01ff;
            5'd18: dwconv_weight_lookup = 96'hf717ebe4fdf9d2ccfd29ddfd;
            5'd19: dwconv_weight_lookup = 96'h2d2213fff30c15fa0f0411e5;
            5'd20: dwconv_weight_lookup = 96'h1bf1f80c0afb17f61c0a6adb;
            5'd21: dwconv_weight_lookup = 96'h04fe11f0130af51f110d06fe;
            5'd22: dwconv_weight_lookup = 96'h03f22f0e0710e4e2f518fef7;
            5'd23: dwconv_weight_lookup = 96'hb312d5d519f33029fecf11e3;
                default: dwconv_weight_lookup = 96'h0;
            endcase
        end
    endfunction

    function [63:0] dwconv_bias_lookup;
        input [2:0] addr;
        begin
            case (addr)
            3'd0: dwconv_bias_lookup = 64'h03f8fcecfb7403f1;
            3'd1: dwconv_bias_lookup = 64'hfeee044efc68fc0a;
            3'd2: dwconv_bias_lookup = 64'h026602850468fd14;
            3'd3: dwconv_bias_lookup = 64'hfa60fe56fc870013;
            3'd4: dwconv_bias_lookup = 64'hff42fe33fb29ff8a;
            3'd5: dwconv_bias_lookup = 64'hfcb6fc5bfba1fd11;
            3'd6: dwconv_bias_lookup = 64'h015cfba203bdfc25;
            3'd7: dwconv_bias_lookup = 64'h02500483fbbafdfe;
                default: dwconv_bias_lookup = 64'h0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_data_bus_reg <= {3*96{1'b0}};
            bias_data_bus_reg <= 64'd0;
        end else begin
            if (weight_rd_en) begin
                for (idx = 0; idx < WEIGHT_BANK_COUNT; idx = idx + 1) begin
                    weight_data_bus_reg[idx*96 +: 96] <= dwconv_weight_lookup((idx*GROUP_COUNT) + weight_rd_group);
                end
            end
            if (bias_rd_en) begin
                bias_data_bus_reg <= dwconv_bias_lookup(bias_rd_group);
            end
        end
    end

    assign weight_data_bus = weight_data_bus_reg;
    assign bias_data_bus = bias_data_bus_reg;

endmodule
