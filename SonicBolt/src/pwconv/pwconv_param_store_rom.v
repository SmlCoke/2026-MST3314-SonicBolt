`timescale 1ns / 1ps
module pwconv_param_store_rom (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               weight_rd_en,
    input  wire [2:0]         weight_rd_group,
    input  wire               bias_rd_en,
    input  wire [2:0]         bias_rd_group,
    output wire [32*4*8-1:0]  weight_data_bus,
    output wire [63:0]        bias_data_bus
);

    localparam integer WEIGHT_BANK_COUNT = 8;
    localparam integer GROUP_COUNT = 8;

    reg [32*4*8-1:0] weight_data_bus_reg;
    reg [63:0]       bias_data_bus_reg;
    integer idx;

    function [127:0] pwconv_weight_lookup;
        input [5:0] addr;
        begin
            case (addr)
            6'd0: pwconv_weight_lookup = 128'h6c309b7f7850c163d24739122d2c24e4;
            6'd1: pwconv_weight_lookup = 128'hba37c5f6d7baf7c65ebe4dbc010f1128;
            6'd2: pwconv_weight_lookup = 128'h2448ce1eca3bcad5f51afc1822c73ce9;
            6'd3: pwconv_weight_lookup = 128'h401306b9f9d012fb1d06d4df5357f226;
            6'd4: pwconv_weight_lookup = 128'h2bec31431bedff1f431022cb0bd505cc;
            6'd5: pwconv_weight_lookup = 128'he60ed326091b24e1150fd00fd0111ad8;
            6'd6: pwconv_weight_lookup = 128'h1af4e1f935e0e8f225e3c9cfad0c29e2;
            6'd7: pwconv_weight_lookup = 128'hf703d9042639d9d9012615be49aedd1b;
            6'd8: pwconv_weight_lookup = 128'he40353f80354fbec27d0cacaf62d13e0;
            6'd9: pwconv_weight_lookup = 128'hc5f01be117c6c7ded8eb41fdec2cea0e;
            6'd10: pwconv_weight_lookup = 128'h0cc037eed20a3fcc22fd0708ab393825;
            6'd11: pwconv_weight_lookup = 128'hc92f472d27d432ddde09dd191357e914;
            6'd12: pwconv_weight_lookup = 128'hb601be3624142c02cfb7e2fbe6d6262a;
            6'd13: pwconv_weight_lookup = 128'h2ff11b3424ed2612f10ee42d1fcb29eb;
            6'd14: pwconv_weight_lookup = 128'h45a92618cbc7032b254ad809edddbe24;
            6'd15: pwconv_weight_lookup = 128'h0c13360d33b0e8dcd2f3cc28c8515508;
            6'd16: pwconv_weight_lookup = 128'hab3dd71fb63609db0ee3123506ee2811;
            6'd17: pwconv_weight_lookup = 128'ha2101bed2b2c24f7c21647c4dcdb2ae8;
            6'd18: pwconv_weight_lookup = 128'h1346d2eff2db3207f330c4e0fb19d8d5;
            6'd19: pwconv_weight_lookup = 128'hf04d26b60202f2ddced20607dd012fe7;
            6'd20: pwconv_weight_lookup = 128'h0742dff330dad4df0923bb1518fbf8f1;
            6'd21: pwconv_weight_lookup = 128'h011228dd090be72307e41e3ae0dcf908;
            6'd22: pwconv_weight_lookup = 128'hfd33edbbf12945ecf5a1e1f1f03becda;
            6'd23: pwconv_weight_lookup = 128'h2a161d2d2d1729202711c95627f1e7d4;
            6'd24: pwconv_weight_lookup = 128'hfb42c3dac8e4372e2df0dd16e3f01e20;
            6'd25: pwconv_weight_lookup = 128'h4f22fa3618cb1231cdddc63613e4e5e9;
            6'd26: pwconv_weight_lookup = 128'h16f434f036ffc82a2815e436e33bfa4e;
            6'd27: pwconv_weight_lookup = 128'h231ff122f8f504181b31edf11abbe501;
            6'd28: pwconv_weight_lookup = 128'hb8c60e15f6fb2edd1b36b014cce304ef;
            6'd29: pwconv_weight_lookup = 128'hecfc261ee0181ce8061fe03931dfcae3;
            6'd30: pwconv_weight_lookup = 128'h0fec0c12b6e94c2298cd13373c203513;
            6'd31: pwconv_weight_lookup = 128'h0bced9ee1bc8151737f4f0e90e60ffb2;
            6'd32: pwconv_weight_lookup = 128'hac2a12205bd4e45fd2171fccecd93028;
            6'd33: pwconv_weight_lookup = 128'h38eae3b016f2cff85be5a722ed1d17cc;
            6'd34: pwconv_weight_lookup = 128'hcb1f25c42fd4ffdef82722175dd7e1e2;
            6'd35: pwconv_weight_lookup = 128'h23f8dbd80818220f05332a38be09276d;
            6'd36: pwconv_weight_lookup = 128'h0feadd3df4fa05f305421dc4192e12dd;
            6'd37: pwconv_weight_lookup = 128'hd610d2f317e6d5e3e535231114f0c82c;
            6'd38: pwconv_weight_lookup = 128'h0b3c3a143a1df4373ee9c9a211320b14;
            6'd39: pwconv_weight_lookup = 128'hedc6e9ece0230d34dfe80f39ef109d10;
            6'd40: pwconv_weight_lookup = 128'h40c54a0ceedf01edc0e133cd0d1e2f12;
            6'd41: pwconv_weight_lookup = 128'he02b3c02ba43fcf8c9210948dbcf31d5;
            6'd42: pwconv_weight_lookup = 128'hf6f9e3eedef71fc1fdc9ebceda11f2b0;
            6'd43: pwconv_weight_lookup = 128'h41b80fb41ccff0c837083514e205e8be;
            6'd44: pwconv_weight_lookup = 128'h19080fdf07072df800481dbde226da23;
            6'd45: pwconv_weight_lookup = 128'h13d735e8edfee31be63411d538eb0729;
            6'd46: pwconv_weight_lookup = 128'hfc2fcbccd6b9202a0b414cd618eff2bb;
            6'd47: pwconv_weight_lookup = 128'h372a123819c1fde60a2a2d0c1dfd35f6;
            6'd48: pwconv_weight_lookup = 128'hc1d2e0018ad9b31318d3cb1c2ff617d8;
            6'd49: pwconv_weight_lookup = 128'hb15c45153523c5322ef72329d4e3d413;
            6'd50: pwconv_weight_lookup = 128'h332fe321d4342629ea31d42dab293334;
            6'd51: pwconv_weight_lookup = 128'hc019ee1913291ff614e3d8e9d31e1deb;
            6'd52: pwconv_weight_lookup = 128'hf02c391fec01e72fbdc0be3a161be0fa;
            6'd53: pwconv_weight_lookup = 128'hfa3525d2f61e0f04f8e122d1ce2207d5;
            6'd54: pwconv_weight_lookup = 128'hd63fece1f612ce264e5438270100091a;
            6'd55: pwconv_weight_lookup = 128'h0f21fed1032aae202d0941f65cf4d8e4;
            6'd56: pwconv_weight_lookup = 128'h582ecd29e9b4221a040ef208d8d9e533;
            6'd57: pwconv_weight_lookup = 128'hf1d8101fc7ef01d8c3572bd7f636c51e;
            6'd58: pwconv_weight_lookup = 128'h3817ecf93be41ecdd41eebfc44f1f321;
            6'd59: pwconv_weight_lookup = 128'h44d3e24520ff050df0300ccad7d00fe1;
            6'd60: pwconv_weight_lookup = 128'h262b2335d801222835d4f615d6092b20;
            6'd61: pwconv_weight_lookup = 128'h23d2d10e07ed0a113437152aca3e20e9;
            6'd62: pwconv_weight_lookup = 128'hfb18f1df05b63bfafc2856f13e0beaed;
            6'd63: pwconv_weight_lookup = 128'h0503ce09fc45d3e73102c2de255ab33c;
                default: pwconv_weight_lookup = 128'h0;
            endcase
        end
    endfunction

    function [63:0] pwconv_bias_lookup;
        input [2:0] addr;
        begin
            case (addr)
            3'd0: pwconv_bias_lookup = 64'hf36ffce905cff05d;
            3'd1: pwconv_bias_lookup = 64'hfd9b0e75fa2508e7;
            3'd2: pwconv_bias_lookup = 64'hf63303a1fd9ff8cd;
            3'd3: pwconv_bias_lookup = 64'hf7bcfe6ffbf9fa9f;
            3'd4: pwconv_bias_lookup = 64'hf029f804079f0319;
            3'd5: pwconv_bias_lookup = 64'hfbd9fb7cedd708ca;
            3'd6: pwconv_bias_lookup = 64'h0043fd52f847fcd9;
            3'd7: pwconv_bias_lookup = 64'hf99efde0f691f5a4;
                default: pwconv_bias_lookup = 64'h0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_data_bus_reg <= {32*4*8{1'b0}};
            bias_data_bus_reg <= 64'd0;
        end else begin
            if (weight_rd_en) begin
                for (idx = 0; idx < WEIGHT_BANK_COUNT; idx = idx + 1) begin
                    weight_data_bus_reg[idx*128 +: 128] <= pwconv_weight_lookup((idx*GROUP_COUNT) + weight_rd_group);
                end
            end
            if (bias_rd_en) begin
                bias_data_bus_reg <= pwconv_bias_lookup(bias_rd_group);
            end
        end
    end

    assign weight_data_bus = weight_data_bus_reg;
    assign bias_data_bus = bias_data_bus_reg;

endmodule
