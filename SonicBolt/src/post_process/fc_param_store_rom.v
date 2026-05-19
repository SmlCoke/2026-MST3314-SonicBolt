`timescale 1ns / 1ps
module fc_param_store_rom #(
    parameter integer WEIGHT_DEPTH = 72
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_fire,
    input  wire               in_valid,
    input  wire [3:0]         in_pos,
    input  wire [2:0]         in_group,
    output wire [63:0]        out_weight_rdata,
    output wire signed [15:0] out_bias_cls0,
    output wire signed [15:0] out_bias_cls1
);

    reg [63:0] weight_rdata_reg;
    reg signed [15:0] bias_cls0_reg;
    reg signed [15:0] bias_cls1_reg;

    wire [6:0] token_addr;
    wire [6:0] next_token_addr;
    wire [6:0] weight_rd_addr;
    wire prefetch_first_word;
    wire prefetch_next_word;
    wire weight_rd_en;
    wire bias_rd_en;

    localparam [31:0] FC_BIAS_WORD = 32'h0000000f;

    assign token_addr = {in_pos, in_group};
    assign next_token_addr = token_addr + 7'd1;
    assign prefetch_first_word = in_fire && !in_valid;
    assign prefetch_next_word  = in_valid && (token_addr != (WEIGHT_DEPTH - 1));
    assign weight_rd_en        = prefetch_first_word || prefetch_next_word;
    assign weight_rd_addr      = prefetch_first_word ? token_addr : next_token_addr;
    assign bias_rd_en = in_fire;

    function [63:0] fc_weight_lookup;
        input [6:0] addr;
        begin
            case (addr)
            7'd0: fc_weight_lookup = 64'hd8cc041322180d0a;
            7'd1: fc_weight_lookup = 64'h0ddeeef8dc443d3d;
            7'd2: fc_weight_lookup = 64'h46ff2df5e11fe45d;
            7'd3: fc_weight_lookup = 64'hf31b2412f4c2e523;
            7'd4: fc_weight_lookup = 64'hf207daf022d7ff0f;
            7'd5: fc_weight_lookup = 64'h282ae05ab1fd3296;
            7'd6: fc_weight_lookup = 64'h481ac3f0e3062ce5;
            7'd7: fc_weight_lookup = 64'h0c1c1bc8e3c9cc1f;
            7'd8: fc_weight_lookup = 64'haca91cf95140ffe5;
            7'd9: fc_weight_lookup = 64'hd4d1b7150def29f5;
            7'd10: fc_weight_lookup = 64'h16d01addc6e4cd2d;
            7'd11: fc_weight_lookup = 64'hc32d23ef38dddf08;
            7'd12: fc_weight_lookup = 64'hcc0509fe13f123f4;
            7'd13: fc_weight_lookup = 64'h291eec4acacb08f5;
            7'd14: fc_weight_lookup = 64'h3cfcdb57b80a10c0;
            7'd15: fc_weight_lookup = 64'h3af7f79afffb0834;
            7'd16: fc_weight_lookup = 64'hb88d1cce573be22f;
            7'd17: fc_weight_lookup = 64'he601c90109e323fc;
            7'd18: fc_weight_lookup = 64'h2f210fb8cf04b843;
            7'd19: fc_weight_lookup = 64'hfb43cedffbda3031;
            7'd20: fc_weight_lookup = 64'hed3b02d8290212e2;
            7'd21: fc_weight_lookup = 64'h21ebe34be4d13ccc;
            7'd22: fc_weight_lookup = 64'h38fbd910ea163cb5;
            7'd23: fc_weight_lookup = 64'h3d59049bf3e6d464;
            7'd24: fc_weight_lookup = 64'h9dd211e94258dc0f;
            7'd25: fc_weight_lookup = 64'h23f2bab8f611402f;
            7'd26: fc_weight_lookup = 64'h36f714b7e107e268;
            7'd27: fc_weight_lookup = 64'h0e230fbf36ba1d34;
            7'd28: fc_weight_lookup = 64'h1f25d70803181022;
            7'd29: fc_weight_lookup = 64'h0a26fc51c0f706af;
            7'd30: fc_weight_lookup = 64'h381dc53ada081bc5;
            7'd31: fc_weight_lookup = 64'h064477c4d8c09a72;
            7'd32: fc_weight_lookup = 64'h83c827044c6fc8fc;
            7'd33: fc_weight_lookup = 64'hff4b0aad0901ff28;
            7'd34: fc_weight_lookup = 64'h2c1a47d0eb03a935;
            7'd35: fc_weight_lookup = 64'hbd4e11fb25bdea01;
            7'd36: fc_weight_lookup = 64'hdb1e000a0cfe0ed3;
            7'd37: fc_weight_lookup = 64'h3450f063b3b0e7bf;
            7'd38: fc_weight_lookup = 64'h6105ad45a2ee42f8;
            7'd39: fc_weight_lookup = 64'h493b268fdd86f436;
            7'd40: fc_weight_lookup = 64'hdbaa4c004a54ecdb;
            7'd41: fc_weight_lookup = 64'hc308aac847ca4b30;
            7'd42: fc_weight_lookup = 64'h30cf3d94d4f7b853;
            7'd43: fc_weight_lookup = 64'hc80bbee151b8383b;
            7'd44: fc_weight_lookup = 64'hfa0a0b2f16c4e5e4;
            7'd45: fc_weight_lookup = 64'h373ffe53fccfe8d0;
            7'd46: fc_weight_lookup = 64'h281dc220a0f129e4;
            7'd47: fc_weight_lookup = 64'h166b4ce1a0a2b161;
            7'd48: fc_weight_lookup = 64'hdf9d4bfee864e126;
            7'd49: fc_weight_lookup = 64'hb9049c0724d65945;
            7'd50: fc_weight_lookup = 64'h09d932dcaf12ea4c;
            7'd51: fc_weight_lookup = 64'he63906da4cddeb4a;
            7'd52: fc_weight_lookup = 64'hbefc0be52cd0de0b;
            7'd53: fc_weight_lookup = 64'h2cfafb29b9fdfffd;
            7'd54: fc_weight_lookup = 64'h4ae7d531d8105ecd;
            7'd55: fc_weight_lookup = 64'h11162ac4efb2ef0e;
            7'd56: fc_weight_lookup = 64'heea52300132eb9ed;
            7'd57: fc_weight_lookup = 64'ha42babd34d033425;
            7'd58: fc_weight_lookup = 64'h1cd72db5f11bc73d;
            7'd59: fc_weight_lookup = 64'hfa2ef3be2cdaf826;
            7'd60: fc_weight_lookup = 64'hff3730192b02b210;
            7'd61: fc_weight_lookup = 64'hf7405008fee5a5f1;
            7'd62: fc_weight_lookup = 64'h3ef8ab2fb0ea3de5;
            7'd63: fc_weight_lookup = 64'h4a4448e9c6e2d511;
            7'd64: fc_weight_lookup = 64'h14d82dd5f656d50e;
            7'd65: fc_weight_lookup = 64'hb40fdcc945f51d45;
            7'd66: fc_weight_lookup = 64'h43e536d7da32b30c;
            7'd67: fc_weight_lookup = 64'hb8f540d24406ce32;
            7'd68: fc_weight_lookup = 64'hd9dd67eae5dac822;
            7'd69: fc_weight_lookup = 64'hd5336b2f04fdb9ed;
            7'd70: fc_weight_lookup = 64'h35f1cb37b71554eb;
            7'd71: fc_weight_lookup = 64'h143f0cffe9c0df2e;
                default: fc_weight_lookup = 64'h0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_rdata_reg <= 64'd0;
            bias_cls0_reg <= 16'sd0;
            bias_cls1_reg <= 16'sd0;
        end else begin
            if (weight_rd_en) begin
                weight_rdata_reg <= fc_weight_lookup(weight_rd_addr);
            end
            if (bias_rd_en) begin
                bias_cls0_reg <= $signed(FC_BIAS_WORD[15:0]);
                bias_cls1_reg <= $signed(FC_BIAS_WORD[31:16]);
            end
        end
    end

    assign out_weight_rdata = weight_rdata_reg;
    assign out_bias_cls0 = bias_cls0_reg;
    assign out_bias_cls1 = bias_cls1_reg;

endmodule
