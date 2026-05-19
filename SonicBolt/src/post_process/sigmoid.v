`timescale 1ns / 1ps
module post_process_sigmoid (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [15:0] in_data_bus,
    output wire        out_valid,
    output wire [63:0] out_data_bus
);

    localparam [1:0] RD_IDLE  = 2'd0;
    localparam [1:0] RD_WAIT0 = 2'd1;
    localparam [1:0] RD_WAIT1 = 2'd2;

    reg [1:0]  rd_state;
    reg [7:0]  req_addr1;
    reg [31:0] first_lut_word;
    reg [31:0] lut_rdata_reg;
    reg [63:0] stage0_data_bus;
    reg        stage0_valid;

    wire       lut_read0_cmd;
    wire       lut_read1_cmd;
    wire       lut_rd_en;
    wire [7:0] lut_rd_addr;

    assign lut_read0_cmd = (rd_state == RD_IDLE) && in_valid;
    assign lut_read1_cmd = (rd_state == RD_WAIT0);
    assign lut_rd_en = lut_read0_cmd || lut_read1_cmd;
    assign lut_rd_addr = lut_read0_cmd ? in_data_bus[7:0] : req_addr1;

    function [31:0] sigmoid_lut_lookup;
        input [7:0] addr;
        begin
            case (addr)
            8'd0: sigmoid_lut_lookup = 32'h3f000000;
            8'd1: sigmoid_lut_lookup = 32'h3f06574c;
            8'd2: sigmoid_lut_lookup = 32'h3f0ca6a6;
            8'd3: sigmoid_lut_lookup = 32'h3f12e642;
            8'd4: sigmoid_lut_lookup = 32'h3f190ea3;
            8'd5: sigmoid_lut_lookup = 32'h3f1f18bc;
            8'd6: sigmoid_lut_lookup = 32'h3f24fe0f;
            8'd7: sigmoid_lut_lookup = 32'h3f2ab8c7;
            8'd8: sigmoid_lut_lookup = 32'h3f3043c8;
            8'd9: sigmoid_lut_lookup = 32'h3f359abe;
            8'd10: sigmoid_lut_lookup = 32'h3f3aba24;
            8'd11: sigmoid_lut_lookup = 32'h3f3f9f40;
            8'd12: sigmoid_lut_lookup = 32'h3f444821;
            8'd13: sigmoid_lut_lookup = 32'h3f48b396;
            8'd14: sigmoid_lut_lookup = 32'h3f4ce11c;
            8'd15: sigmoid_lut_lookup = 32'h3f50d0d5;
            8'd16: sigmoid_lut_lookup = 32'h3f54836c;
            8'd17: sigmoid_lut_lookup = 32'h3f57fa0e;
            8'd18: sigmoid_lut_lookup = 32'h3f5b364b;
            8'd19: sigmoid_lut_lookup = 32'h3f5e3a0e;
            8'd20: sigmoid_lut_lookup = 32'h3f610781;
            8'd21: sigmoid_lut_lookup = 32'h3f63a105;
            8'd22: sigmoid_lut_lookup = 32'h3f66091e;
            8'd23: sigmoid_lut_lookup = 32'h3f684267;
            8'd24: sigmoid_lut_lookup = 32'h3f6a4f88;
            8'd25: sigmoid_lut_lookup = 32'h3f6c3327;
            8'd26: sigmoid_lut_lookup = 32'h3f6defe6;
            8'd27: sigmoid_lut_lookup = 32'h3f6f8857;
            8'd28: sigmoid_lut_lookup = 32'h3f70fefb;
            8'd29: sigmoid_lut_lookup = 32'h3f72563a;
            8'd30: sigmoid_lut_lookup = 32'h3f739062;
            8'd31: sigmoid_lut_lookup = 32'h3f74afa4;
            8'd32: sigmoid_lut_lookup = 32'h3f75b612;
            8'd33: sigmoid_lut_lookup = 32'h3f76a5a3;
            8'd34: sigmoid_lut_lookup = 32'h3f77802a;
            8'd35: sigmoid_lut_lookup = 32'h3f78475f;
            8'd36: sigmoid_lut_lookup = 32'h3f78fcdb;
            8'd37: sigmoid_lut_lookup = 32'h3f79a21b;
            8'd38: sigmoid_lut_lookup = 32'h3f7a387f;
            8'd39: sigmoid_lut_lookup = 32'h3f7ac14e;
            8'd40: sigmoid_lut_lookup = 32'h3f7b3db3;
            8'd41: sigmoid_lut_lookup = 32'h3f7baec5;
            8'd42: sigmoid_lut_lookup = 32'h3f7c1583;
            8'd43: sigmoid_lut_lookup = 32'h3f7c72d5;
            8'd44: sigmoid_lut_lookup = 32'h3f7cc795;
            8'd45: sigmoid_lut_lookup = 32'h3f7d1485;
            8'd46: sigmoid_lut_lookup = 32'h3f7d5a5b;
            8'd47: sigmoid_lut_lookup = 32'h3f7d99ba;
            8'd48: sigmoid_lut_lookup = 32'h3f7dd339;
            8'd49: sigmoid_lut_lookup = 32'h3f7e0761;
            8'd50: sigmoid_lut_lookup = 32'h3f7e36af;
            8'd51: sigmoid_lut_lookup = 32'h3f7e6195;
            8'd52: sigmoid_lut_lookup = 32'h3f7e887a;
            8'd53: sigmoid_lut_lookup = 32'h3f7eabbe;
            8'd54: sigmoid_lut_lookup = 32'h3f7ecbb7;
            8'd55: sigmoid_lut_lookup = 32'h3f7ee8b1;
            8'd56: sigmoid_lut_lookup = 32'h3f7f02f5;
            8'd57: sigmoid_lut_lookup = 32'h3f7f1ac3;
            8'd58: sigmoid_lut_lookup = 32'h3f7f3055;
            8'd59: sigmoid_lut_lookup = 32'h3f7f43e2;
            8'd60: sigmoid_lut_lookup = 32'h3f7f5598;
            8'd61: sigmoid_lut_lookup = 32'h3f7f65a5;
            8'd62: sigmoid_lut_lookup = 32'h3f7f742f;
            8'd63: sigmoid_lut_lookup = 32'h3f7f815b;
            8'd64: sigmoid_lut_lookup = 32'h3f7f8d4b;
            8'd65: sigmoid_lut_lookup = 32'h3f7f981a;
            8'd66: sigmoid_lut_lookup = 32'h3f7fa1e6;
            8'd67: sigmoid_lut_lookup = 32'h3f7faac5;
            8'd68: sigmoid_lut_lookup = 32'h3f7fb2ce;
            8'd69: sigmoid_lut_lookup = 32'h3f7fba16;
            8'd70: sigmoid_lut_lookup = 32'h3f7fc0ae;
            8'd71: sigmoid_lut_lookup = 32'h3f7fc6a7;
            8'd72: sigmoid_lut_lookup = 32'h3f7fcc0f;
            8'd73: sigmoid_lut_lookup = 32'h3f7fd0f6;
            8'd74: sigmoid_lut_lookup = 32'h3f7fd566;
            8'd75: sigmoid_lut_lookup = 32'h3f7fd96b;
            8'd76: sigmoid_lut_lookup = 32'h3f7fdd0f;
            8'd77: sigmoid_lut_lookup = 32'h3f7fe05b;
            8'd78: sigmoid_lut_lookup = 32'h3f7fe357;
            8'd79: sigmoid_lut_lookup = 32'h3f7fe60c;
            8'd80: sigmoid_lut_lookup = 32'h3f7fe87f;
            8'd81: sigmoid_lut_lookup = 32'h3f7feab6;
            8'd82: sigmoid_lut_lookup = 32'h3f7fecb9;
            8'd83: sigmoid_lut_lookup = 32'h3f7fee8b;
            8'd84: sigmoid_lut_lookup = 32'h3f7ff030;
            8'd85: sigmoid_lut_lookup = 32'h3f7ff1ae;
            8'd86: sigmoid_lut_lookup = 32'h3f7ff308;
            8'd87: sigmoid_lut_lookup = 32'h3f7ff442;
            8'd88: sigmoid_lut_lookup = 32'h3f7ff55d;
            8'd89: sigmoid_lut_lookup = 32'h3f7ff65e;
            8'd90: sigmoid_lut_lookup = 32'h3f7ff747;
            8'd91: sigmoid_lut_lookup = 32'h3f7ff81a;
            8'd92: sigmoid_lut_lookup = 32'h3f7ff8d9;
            8'd93: sigmoid_lut_lookup = 32'h3f7ff986;
            8'd94: sigmoid_lut_lookup = 32'h3f7ffa22;
            8'd95: sigmoid_lut_lookup = 32'h3f7ffab0;
            8'd96: sigmoid_lut_lookup = 32'h3f7ffb30;
            8'd97: sigmoid_lut_lookup = 32'h3f7ffba5;
            8'd98: sigmoid_lut_lookup = 32'h3f7ffc0e;
            8'd99: sigmoid_lut_lookup = 32'h3f7ffc6d;
            8'd100: sigmoid_lut_lookup = 32'h3f7ffcc4;
            8'd101: sigmoid_lut_lookup = 32'h3f7ffd12;
            8'd102: sigmoid_lut_lookup = 32'h3f7ffd59;
            8'd103: sigmoid_lut_lookup = 32'h3f7ffd99;
            8'd104: sigmoid_lut_lookup = 32'h3f7ffdd3;
            8'd105: sigmoid_lut_lookup = 32'h3f7ffe07;
            8'd106: sigmoid_lut_lookup = 32'h3f7ffe37;
            8'd107: sigmoid_lut_lookup = 32'h3f7ffe62;
            8'd108: sigmoid_lut_lookup = 32'h3f7ffe89;
            8'd109: sigmoid_lut_lookup = 32'h3f7ffead;
            8'd110: sigmoid_lut_lookup = 32'h3f7ffecd;
            8'd111: sigmoid_lut_lookup = 32'h3f7ffeea;
            8'd112: sigmoid_lut_lookup = 32'h3f7fff04;
            8'd113: sigmoid_lut_lookup = 32'h3f7fff1c;
            8'd114: sigmoid_lut_lookup = 32'h3f7fff31;
            8'd115: sigmoid_lut_lookup = 32'h3f7fff45;
            8'd116: sigmoid_lut_lookup = 32'h3f7fff56;
            8'd117: sigmoid_lut_lookup = 32'h3f7fff66;
            8'd118: sigmoid_lut_lookup = 32'h3f7fff75;
            8'd119: sigmoid_lut_lookup = 32'h3f7fff82;
            8'd120: sigmoid_lut_lookup = 32'h3f7fff8e;
            8'd121: sigmoid_lut_lookup = 32'h3f7fff99;
            8'd122: sigmoid_lut_lookup = 32'h3f7fffa2;
            8'd123: sigmoid_lut_lookup = 32'h3f7fffab;
            8'd124: sigmoid_lut_lookup = 32'h3f7fffb3;
            8'd125: sigmoid_lut_lookup = 32'h3f7fffbb;
            8'd126: sigmoid_lut_lookup = 32'h3f7fffc1;
            8'd127: sigmoid_lut_lookup = 32'h3f7fffc7;
            8'd128: sigmoid_lut_lookup = 32'h364e5111;
            8'd129: sigmoid_lut_lookup = 32'h3663d2d3;
            8'd130: sigmoid_lut_lookup = 32'h367b9283;
            8'd131: sigmoid_lut_lookup = 32'h368ae5fa;
            8'd132: sigmoid_lut_lookup = 32'h3699609c;
            8'd133: sigmoid_lut_lookup = 32'h36a95d9f;
            8'd134: sigmoid_lut_lookup = 32'h36bb054d;
            8'd135: sigmoid_lut_lookup = 32'h36ce841d;
            8'd136: sigmoid_lut_lookup = 32'h36e40b2c;
            8'd137: sigmoid_lut_lookup = 32'h36fbd0b6;
            8'd138: sigmoid_lut_lookup = 32'h370b084e;
            8'd139: sigmoid_lut_lookup = 32'h3719867f;
            8'd140: sigmoid_lut_lookup = 32'h37298771;
            8'd141: sigmoid_lut_lookup = 32'h373b3373;
            8'd142: sigmoid_lut_lookup = 32'h374eb70b;
            8'd143: sigmoid_lut_lookup = 32'h37644360;
            8'd144: sigmoid_lut_lookup = 32'h377c0eba;
            8'd145: sigmoid_lut_lookup = 32'h378b2a84;
            8'd146: sigmoid_lut_lookup = 32'h3799ac3e;
            8'd147: sigmoid_lut_lookup = 32'h37a9b114;
            8'd148: sigmoid_lut_lookup = 32'h37bb6161;
            8'd149: sigmoid_lut_lookup = 32'h37cee9b2;
            8'd150: sigmoid_lut_lookup = 32'h37e47b3c;
            8'd151: sigmoid_lut_lookup = 32'h37fc4c50;
            8'd152: sigmoid_lut_lookup = 32'h380b4c77;
            8'd153: sigmoid_lut_lookup = 32'h3819d1a9;
            8'd154: sigmoid_lut_lookup = 32'h3829da50;
            8'd155: sigmoid_lut_lookup = 32'h383b8ed0;
            8'd156: sigmoid_lut_lookup = 32'h384f1bbe;
            8'd157: sigmoid_lut_lookup = 32'h3864b258;
            8'd158: sigmoid_lut_lookup = 32'h387c88fd;
            8'd159: sigmoid_lut_lookup = 32'h388b6dda;
            8'd160: sigmoid_lut_lookup = 32'h3899f664;
            8'd161: sigmoid_lut_lookup = 32'h38aa02b5;
            8'd162: sigmoid_lut_lookup = 32'h38bbbb36;
            8'd163: sigmoid_lut_lookup = 32'h38cf4c85;
            8'd164: sigmoid_lut_lookup = 32'h38e4e7e8;
            8'd165: sigmoid_lut_lookup = 32'h38fcc3c3;
            8'd166: sigmoid_lut_lookup = 32'h390b8e14;
            8'd167: sigmoid_lut_lookup = 32'h391a19b4;
            8'd168: sigmoid_lut_lookup = 32'h392a295d;
            8'd169: sigmoid_lut_lookup = 32'h393be57e;
            8'd170: sigmoid_lut_lookup = 32'h394f7ab6;
            8'd171: sigmoid_lut_lookup = 32'h39651a4e;
            8'd172: sigmoid_lut_lookup = 32'h397cfaae;
            8'd173: sigmoid_lut_lookup = 32'h398babf3;
            8'd174: sigmoid_lut_lookup = 32'h399a3a23;
            8'd175: sigmoid_lut_lookup = 32'h39aa4c83;
            8'd176: sigmoid_lut_lookup = 32'h39bc0b7c;
            8'd177: sigmoid_lut_lookup = 32'h39cfa3ac;
            8'd178: sigmoid_lut_lookup = 32'h39e54652;
            8'd179: sigmoid_lut_lookup = 32'h39fd29cd;
            8'd180: sigmoid_lut_lookup = 32'h3a0bc510;
            8'd181: sigmoid_lut_lookup = 32'h3a1a54c5;
            8'd182: sigmoid_lut_lookup = 32'h3a2a6895;
            8'd183: sigmoid_lut_lookup = 32'h3a3c28d9;
            8'd184: sigmoid_lut_lookup = 32'h3a4fc21a;
            8'd185: sigmoid_lut_lookup = 32'h3a65657f;
            8'd186: sigmoid_lut_lookup = 32'h3a7d4944;
            8'd187: sigmoid_lut_lookup = 32'h3a8bd4a2;
            8'd188: sigmoid_lut_lookup = 32'h3a9a63c3;
            8'd189: sigmoid_lut_lookup = 32'h3aaa7674;
            8'd190: sigmoid_lut_lookup = 32'h3abc34e6;
            8'd191: sigmoid_lut_lookup = 32'h3acfcb6e;
            8'd192: sigmoid_lut_lookup = 32'h3ae56af1;
            8'd193: sigmoid_lut_lookup = 32'h3afd495d;
            8'd194: sigmoid_lut_lookup = 32'h3b0bd114;
            8'd195: sigmoid_lut_lookup = 32'h3b1a5b72;
            8'd196: sigmoid_lut_lookup = 32'h3b2a67ec;
            8'd197: sigmoid_lut_lookup = 32'h3b3c1e54;
            8'd198: sigmoid_lut_lookup = 32'h3b4faa8f;
            8'd199: sigmoid_lut_lookup = 32'h3b653cf7;
            8'd200: sigmoid_lut_lookup = 32'h3b7d0ace;
            8'd201: sigmoid_lut_lookup = 32'h3b8ba75c;
            8'd202: sigmoid_lut_lookup = 32'h3b9a24a3;
            8'd203: sigmoid_lut_lookup = 32'h3baa20c0;
            8'd204: sigmoid_lut_lookup = 32'h3bbbc2c7;
            8'd205: sigmoid_lut_lookup = 32'h3bcf35b0;
            8'd206: sigmoid_lut_lookup = 32'h3be4a8b6;
            8'd207: sigmoid_lut_lookup = 32'h3bfc4fbb;
            8'd208: sigmoid_lut_lookup = 32'h3c0b31dc;
            8'd209: sigmoid_lut_lookup = 32'h3c19919a;
            8'd210: sigmoid_lut_lookup = 32'h3c29695f;
            8'd211: sigmoid_lut_lookup = 32'h3c3adebc;
            8'd212: sigmoid_lut_lookup = 32'h3c4e1ad3;
            8'd213: sigmoid_lut_lookup = 32'h3c634aa5;
            8'd214: sigmoid_lut_lookup = 32'h3c7a9f60;
            8'd215: sigmoid_lut_lookup = 32'h3c8a275b;
            8'd216: sigmoid_lut_lookup = 32'h3c984998;
            8'd217: sigmoid_lut_lookup = 32'h3ca7d649;
            8'd218: sigmoid_lut_lookup = 32'h3cb8f014;
            8'd219: sigmoid_lut_lookup = 32'h3ccbbc98;
            8'd220: sigmoid_lut_lookup = 32'h3ce06499;
            8'd221: sigmoid_lut_lookup = 32'h3cf71426;
            8'd222: sigmoid_lut_lookup = 32'h3d07fd65;
            8'd223: sigmoid_lut_lookup = 32'h3d15a5d7;
            8'd224: sigmoid_lut_lookup = 32'h3d249ed9;
            8'd225: sigmoid_lut_lookup = 32'h3d3505c4;
            8'd226: sigmoid_lut_lookup = 32'h3d46f9df;
            8'd227: sigmoid_lut_lookup = 32'h3d5a9c5c;
            8'd228: sigmoid_lut_lookup = 32'h3d70104c;
            8'd229: sigmoid_lut_lookup = 32'h3d83bd47;
            8'd230: sigmoid_lut_lookup = 32'h3d9080d3;
            8'd231: sigmoid_lut_lookup = 32'h3d9e66ca;
            8'd232: sigmoid_lut_lookup = 32'h3dad83c3;
            8'd233: sigmoid_lut_lookup = 32'h3dbdecc5;
            8'd234: sigmoid_lut_lookup = 32'h3dcfb711;
            8'd235: sigmoid_lut_lookup = 32'h3de2f7da;
            8'd236: sigmoid_lut_lookup = 32'h3df7c3fb;
            8'd237: sigmoid_lut_lookup = 32'h3e0717ca;
            8'd238: sigmoid_lut_lookup = 32'h3e1326d3;
            8'd239: sigmoid_lut_lookup = 32'h3e2017c9;
            8'd240: sigmoid_lut_lookup = 32'h3e2df24f;
            8'd241: sigmoid_lut_lookup = 32'h3e3cbcae;
            8'd242: sigmoid_lut_lookup = 32'h3e4c7b8e;
            8'd243: sigmoid_lut_lookup = 32'h3e5d31a9;
            8'd244: sigmoid_lut_lookup = 32'h3e6edf7c;
            8'd245: sigmoid_lut_lookup = 32'h3e80c180;
            8'd246: sigmoid_lut_lookup = 32'h3e8a8bb8;
            8'd247: sigmoid_lut_lookup = 32'h3e94ca83;
            8'd248: sigmoid_lut_lookup = 32'h3e9f7870;
            8'd249: sigmoid_lut_lookup = 32'h3eaa8e72;
            8'd250: sigmoid_lut_lookup = 32'h3eb603e1;
            8'd251: sigmoid_lut_lookup = 32'h3ec1ce88;
            8'd252: sigmoid_lut_lookup = 32'h3ecde2ba;
            8'd253: sigmoid_lut_lookup = 32'h3eda337b;
            8'd254: sigmoid_lut_lookup = 32'h3ee6b2b3;
            8'd255: sigmoid_lut_lookup = 32'h3ef35167;
                default: sigmoid_lut_lookup = 32'h00000000;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lut_rdata_reg <= 32'd0;
        end else if (lut_rd_en) begin
            lut_rdata_reg <= sigmoid_lut_lookup(lut_rd_addr);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;
            req_addr1 <= 8'd0;
            first_lut_word <= 32'd0;
            stage0_data_bus <= 64'd0;
            stage0_valid <= 1'b0;
        end else begin
            stage0_valid <= 1'b0;
            stage0_data_bus <= 64'd0;

            case (rd_state)
                RD_IDLE: begin
                    if (lut_read0_cmd) begin
                        req_addr1 <= in_data_bus[15:8];
                        rd_state <= RD_WAIT0;
                    end
                end
                RD_WAIT0: begin
                    first_lut_word <= lut_rdata_reg;
                    rd_state <= RD_WAIT1;
                end
                RD_WAIT1: begin
                    stage0_data_bus <= {lut_rdata_reg, first_lut_word};
                    stage0_valid <= 1'b1;
                    rd_state <= RD_IDLE;
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    assign out_valid = stage0_valid;
    assign out_data_bus = stage0_data_bus;

endmodule
