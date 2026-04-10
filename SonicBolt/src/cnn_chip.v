`timescale 1ns / 1ps
/*
 * 模块名称: cnn
 * 作者: SonicBolt 团队
 * 日期: 2026-04-10
 * 版本: v1.0
 *
 * 功能概述:
 *  CNN 顶层模块，连接外部接口与内部 cnn 模块。
 */
module cnn_chip #(
    parameter integer CONV_M0        = 111,
    parameter integer CONV_SHIFT_N   = 14,
    parameter integer DWCONV_M0      = 59,
    parameter integer DWCONV_SHIFT_N = 11,
    parameter integer PWCONV_M0      = 69,
    parameter integer PWCONV_SHIFT_N = 13,
    parameter integer FC_M0          = 11,
    parameter integer FC_SHIFT_N     = 15
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output wire          busy,
    output wire          done,

    input  wire          img_wr_en,
    input  wire [4:0]    img_wr_addr,
    input  wire [79:0]   img_wr_row_data,
    input  wire          img_wr_commit,
    output wire          img_wr_ready,

    input  wire          conv_weight_wr_en,
    input  wire [4:0]    conv_weight_wr_bank,
    input  wire [2:0]    conv_weight_wr_addr,
    input  wire [223:0]  conv_weight_wr_data,

    input  wire          dwconv_weight_wr_en,
    input  wire [1:0]    dwconv_weight_wr_bank,
    input  wire [2:0]    dwconv_weight_wr_addr,
    input  wire [95:0]   dwconv_weight_wr_data,

    input  wire          pwconv_weight_wr_en,
    input  wire [2:0]    pwconv_weight_wr_bank,
    input  wire [2:0]    pwconv_weight_wr_addr,
    input  wire [127:0]  pwconv_weight_wr_data,

    input  wire          conv_bias_wr_en,
    input  wire          conv_bias_wr_bank,
    input  wire [2:0]    conv_bias_wr_addr,
    input  wire [63:0]   conv_bias_wr_data,

    input  wire          dwconv_bias_wr_en,
    input  wire          dwconv_bias_wr_bank,
    input  wire [2:0]    dwconv_bias_wr_addr,
    input  wire [63:0]   dwconv_bias_wr_data,

    input  wire          pwconv_bias_wr_en,
    input  wire          pwconv_bias_wr_bank,
    input  wire [2:0]    pwconv_bias_wr_addr,
    input  wire [63:0]   pwconv_bias_wr_data,

    input  wire          fc_weight_wr_en,
    input  wire [6:0]    fc_weight_wr_addr,
    input  wire [63:0]   fc_weight_wr_data,
    input  wire          fc_bias_wr_en,
    input  wire [31:0]   fc_bias_wr_data,
    input  wire          sigmoid_lut_wr_en,
    input  wire [7:0]    sigmoid_lut_wr_addr,
    input  wire [31:0]   sigmoid_lut_wr_data,

    output wire          out_stream_valid,
    output wire [63:0]   out_stream_data
);

    wire         net_clk;
    wire         net_rst_n;
    wire         net_start;
    wire         net_busy;
    wire         net_done;

    wire         net_img_wr_en;
    wire [4:0]   net_img_wr_addr;
    wire [79:0]  net_img_wr_row_data;
    wire         net_img_wr_commit;
    wire         net_img_wr_ready;

    wire         net_conv_weight_wr_en;
    wire [4:0]   net_conv_weight_wr_bank;
    wire [2:0]   net_conv_weight_wr_addr;
    wire [223:0] net_conv_weight_wr_data;

    wire         net_dwconv_weight_wr_en;
    wire [1:0]   net_dwconv_weight_wr_bank;
    wire [2:0]   net_dwconv_weight_wr_addr;
    wire [95:0]  net_dwconv_weight_wr_data;

    wire         net_pwconv_weight_wr_en;
    wire [2:0]   net_pwconv_weight_wr_bank;
    wire [2:0]   net_pwconv_weight_wr_addr;
    wire [127:0] net_pwconv_weight_wr_data;

    wire         net_conv_bias_wr_en;
    wire         net_conv_bias_wr_bank;
    wire [2:0]   net_conv_bias_wr_addr;
    wire [63:0]  net_conv_bias_wr_data;

    wire         net_dwconv_bias_wr_en;
    wire         net_dwconv_bias_wr_bank;
    wire [2:0]   net_dwconv_bias_wr_addr;
    wire [63:0]  net_dwconv_bias_wr_data;

    wire         net_pwconv_bias_wr_en;
    wire         net_pwconv_bias_wr_bank;
    wire [2:0]   net_pwconv_bias_wr_addr;
    wire [63:0]  net_pwconv_bias_wr_data;

    wire         net_fc_weight_wr_en;
    wire [6:0]   net_fc_weight_wr_addr;
    wire [63:0]  net_fc_weight_wr_data;
    wire         net_fc_bias_wr_en;
    wire [31:0]  net_fc_bias_wr_data;
    wire         net_sigmoid_lut_wr_en;
    wire [7:0]   net_sigmoid_lut_wr_addr;
    wire [31:0]  net_sigmoid_lut_wr_data;

    wire         net_out_stream_valid;
    wire [63:0]  net_out_stream_data;

    PIW PIW_clk(.PAD(clk), .C(net_clk));
    PIW PIW_rst_n(.PAD(rst_n), .C(net_rst_n));
    PIW PIW_start(.PAD(start), .C(net_start));

    PIW PIW_img_wr_en(.PAD(img_wr_en), .C(net_img_wr_en));
    PIW PIW_img_wr_commit(.PAD(img_wr_commit), .C(net_img_wr_commit));

    PIW PIW_conv_weight_wr_en(.PAD(conv_weight_wr_en), .C(net_conv_weight_wr_en));
    PIW PIW_dwconv_weight_wr_en(.PAD(dwconv_weight_wr_en), .C(net_dwconv_weight_wr_en));
    PIW PIW_pwconv_weight_wr_en(.PAD(pwconv_weight_wr_en), .C(net_pwconv_weight_wr_en));

    PIW PIW_conv_bias_wr_en(.PAD(conv_bias_wr_en), .C(net_conv_bias_wr_en));
    PIW PIW_conv_bias_wr_bank(.PAD(conv_bias_wr_bank), .C(net_conv_bias_wr_bank));
    PIW PIW_dwconv_bias_wr_en(.PAD(dwconv_bias_wr_en), .C(net_dwconv_bias_wr_en));
    PIW PIW_dwconv_bias_wr_bank(.PAD(dwconv_bias_wr_bank), .C(net_dwconv_bias_wr_bank));
    PIW PIW_pwconv_bias_wr_en(.PAD(pwconv_bias_wr_en), .C(net_pwconv_bias_wr_en));
    PIW PIW_pwconv_bias_wr_bank(.PAD(pwconv_bias_wr_bank), .C(net_pwconv_bias_wr_bank));

    PIW PIW_fc_weight_wr_en(.PAD(fc_weight_wr_en), .C(net_fc_weight_wr_en));
    PIW PIW_fc_bias_wr_en(.PAD(fc_bias_wr_en), .C(net_fc_bias_wr_en));
    PIW PIW_sigmoid_lut_wr_en(.PAD(sigmoid_lut_wr_en), .C(net_sigmoid_lut_wr_en));

    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : gen_piw_img_wr_addr
            PIW u_piw(.PAD(img_wr_addr[i]), .C(net_img_wr_addr[i]));
        end

        for (i = 0; i < 80; i = i + 1) begin : gen_piw_img_wr_row_data
            PIW u_piw(.PAD(img_wr_row_data[i]), .C(net_img_wr_row_data[i]));
        end

        for (i = 0; i < 5; i = i + 1) begin : gen_piw_conv_weight_wr_bank
            PIW u_piw(.PAD(conv_weight_wr_bank[i]), .C(net_conv_weight_wr_bank[i]));
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_piw_conv_weight_wr_addr
            PIW u_piw(.PAD(conv_weight_wr_addr[i]), .C(net_conv_weight_wr_addr[i]));
        end

        for (i = 0; i < 224; i = i + 1) begin : gen_piw_conv_weight_wr_data
            PIW u_piw(.PAD(conv_weight_wr_data[i]), .C(net_conv_weight_wr_data[i]));
        end

        for (i = 0; i < 2; i = i + 1) begin : gen_piw_dwconv_weight_wr_bank
            PIW u_piw(.PAD(dwconv_weight_wr_bank[i]), .C(net_dwconv_weight_wr_bank[i]));
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_piw_dwconv_weight_wr_addr
            PIW u_piw(.PAD(dwconv_weight_wr_addr[i]), .C(net_dwconv_weight_wr_addr[i]));
        end

        for (i = 0; i < 96; i = i + 1) begin : gen_piw_dwconv_weight_wr_data
            PIW u_piw(.PAD(dwconv_weight_wr_data[i]), .C(net_dwconv_weight_wr_data[i]));
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_piw_pwconv_weight_wr_bank
            PIW u_piw(.PAD(pwconv_weight_wr_bank[i]), .C(net_pwconv_weight_wr_bank[i]));
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_piw_pwconv_weight_wr_addr
            PIW u_piw(.PAD(pwconv_weight_wr_addr[i]), .C(net_pwconv_weight_wr_addr[i]));
        end

        for (i = 0; i < 128; i = i + 1) begin : gen_piw_pwconv_weight_wr_data
            PIW u_piw(.PAD(pwconv_weight_wr_data[i]), .C(net_pwconv_weight_wr_data[i]));
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_piw_conv_bias_wr_addr
            PIW u_piw(.PAD(conv_bias_wr_addr[i]), .C(net_conv_bias_wr_addr[i]));
        end

        for (i = 0; i < 64; i = i + 1) begin : gen_piw_conv_bias_wr_data
            PIW u_piw(.PAD(conv_bias_wr_data[i]), .C(net_conv_bias_wr_data[i]));
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_piw_dwconv_bias_wr_addr
            PIW u_piw(.PAD(dwconv_bias_wr_addr[i]), .C(net_dwconv_bias_wr_addr[i]));
        end

        for (i = 0; i < 64; i = i + 1) begin : gen_piw_dwconv_bias_wr_data
            PIW u_piw(.PAD(dwconv_bias_wr_data[i]), .C(net_dwconv_bias_wr_data[i]));
        end

        for (i = 0; i < 3; i = i + 1) begin : gen_piw_pwconv_bias_wr_addr
            PIW u_piw(.PAD(pwconv_bias_wr_addr[i]), .C(net_pwconv_bias_wr_addr[i]));
        end

        for (i = 0; i < 64; i = i + 1) begin : gen_piw_pwconv_bias_wr_data
            PIW u_piw(.PAD(pwconv_bias_wr_data[i]), .C(net_pwconv_bias_wr_data[i]));
        end

        for (i = 0; i < 7; i = i + 1) begin : gen_piw_fc_weight_wr_addr
            PIW u_piw(.PAD(fc_weight_wr_addr[i]), .C(net_fc_weight_wr_addr[i]));
        end

        for (i = 0; i < 64; i = i + 1) begin : gen_piw_fc_weight_wr_data
            PIW u_piw(.PAD(fc_weight_wr_data[i]), .C(net_fc_weight_wr_data[i]));
        end

        for (i = 0; i < 32; i = i + 1) begin : gen_piw_fc_bias_wr_data
            PIW u_piw(.PAD(fc_bias_wr_data[i]), .C(net_fc_bias_wr_data[i]));
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_piw_sigmoid_lut_wr_addr
            PIW u_piw(.PAD(sigmoid_lut_wr_addr[i]), .C(net_sigmoid_lut_wr_addr[i]));
        end

        for (i = 0; i < 32; i = i + 1) begin : gen_piw_sigmoid_lut_wr_data
            PIW u_piw(.PAD(sigmoid_lut_wr_data[i]), .C(net_sigmoid_lut_wr_data[i]));
        end
    endgenerate

    PO8W PO8W_busy(.I(net_busy), .PAD(busy));
    PO8W PO8W_done(.I(net_done), .PAD(done));
    PO8W PO8W_img_wr_ready(.I(net_img_wr_ready), .PAD(img_wr_ready));
    PO8W PO8W_out_stream_valid(.I(net_out_stream_valid), .PAD(out_stream_valid));

    generate
        for (i = 0; i < 64; i = i + 1) begin : gen_po8w_out_stream_data
            PO8W u_po8w(.I(net_out_stream_data[i]), .PAD(out_stream_data[i]));
        end
    endgenerate

    cnn #(
        .CONV_M0(CONV_M0),
        .CONV_SHIFT_N(CONV_SHIFT_N),
        .DWCONV_M0(DWCONV_M0),
        .DWCONV_SHIFT_N(DWCONV_SHIFT_N),
        .PWCONV_M0(PWCONV_M0),
        .PWCONV_SHIFT_N(PWCONV_SHIFT_N),
        .FC_M0(FC_M0),
        .FC_SHIFT_N(FC_SHIFT_N)
    ) inst_cnn (
        .clk(net_clk),
        .rst_n(net_rst_n),
        .start(net_start),
        .busy(net_busy),
        .done(net_done),

        .img_wr_en(net_img_wr_en),
        .img_wr_addr(net_img_wr_addr),
        .img_wr_row_data(net_img_wr_row_data),
        .img_wr_commit(net_img_wr_commit),
        .img_wr_ready(net_img_wr_ready),

        .conv_weight_wr_en(net_conv_weight_wr_en),
        .conv_weight_wr_bank(net_conv_weight_wr_bank),
        .conv_weight_wr_addr(net_conv_weight_wr_addr),
        .conv_weight_wr_data(net_conv_weight_wr_data),

        .dwconv_weight_wr_en(net_dwconv_weight_wr_en),
        .dwconv_weight_wr_bank(net_dwconv_weight_wr_bank),
        .dwconv_weight_wr_addr(net_dwconv_weight_wr_addr),
        .dwconv_weight_wr_data(net_dwconv_weight_wr_data),

        .pwconv_weight_wr_en(net_pwconv_weight_wr_en),
        .pwconv_weight_wr_bank(net_pwconv_weight_wr_bank),
        .pwconv_weight_wr_addr(net_pwconv_weight_wr_addr),
        .pwconv_weight_wr_data(net_pwconv_weight_wr_data),

        .conv_bias_wr_en(net_conv_bias_wr_en),
        .conv_bias_wr_bank(net_conv_bias_wr_bank),
        .conv_bias_wr_addr(net_conv_bias_wr_addr),
        .conv_bias_wr_data(net_conv_bias_wr_data),

        .dwconv_bias_wr_en(net_dwconv_bias_wr_en),
        .dwconv_bias_wr_bank(net_dwconv_bias_wr_bank),
        .dwconv_bias_wr_addr(net_dwconv_bias_wr_addr),
        .dwconv_bias_wr_data(net_dwconv_bias_wr_data),

        .pwconv_bias_wr_en(net_pwconv_bias_wr_en),
        .pwconv_bias_wr_bank(net_pwconv_bias_wr_bank),
        .pwconv_bias_wr_addr(net_pwconv_bias_wr_addr),
        .pwconv_bias_wr_data(net_pwconv_bias_wr_data),

        .fc_weight_wr_en(net_fc_weight_wr_en),
        .fc_weight_wr_addr(net_fc_weight_wr_addr),
        .fc_weight_wr_data(net_fc_weight_wr_data),
        .fc_bias_wr_en(net_fc_bias_wr_en),
        .fc_bias_wr_data(net_fc_bias_wr_data),
        .sigmoid_lut_wr_en(net_sigmoid_lut_wr_en),
        .sigmoid_lut_wr_addr(net_sigmoid_lut_wr_addr),
        .sigmoid_lut_wr_data(net_sigmoid_lut_wr_data),

        .out_stream_valid(net_out_stream_valid),
        .out_stream_data(net_out_stream_data)
    );

endmodule
