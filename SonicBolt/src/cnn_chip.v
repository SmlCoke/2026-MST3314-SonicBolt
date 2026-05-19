`timescale 1ns / 1ps
/*
 * 模块名称: cnn
 * 作者: SonicBolt 团队
 * 日期: 2026-04-11
 * 版本: v1.0
 *
 * 功能概述:
 *  CNN 顶层模块，连接外部接口与内部 cnn 模块。
 * 
 * 说明:
 *  为了绕开工具对大规模常量端口折叠时的崩溃问题，将 SRAM 接口用 img 信号胡乱赋值成“伪配置”接口
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
    reg          net_img_wr_ready_r;


    wire         net_out_stream_valid;
    wire [63:0]  net_out_stream_data;

    PIW PIW_clk(.PAD(clk), .C(net_clk));
    PIW PIW_rst_n(.PAD(rst_n), .C(net_rst_n));
    PIW PIW_start(.PAD(start), .C(net_start));

    PIW PIW_img_wr_en(.PAD(img_wr_en), .C(net_img_wr_en));
    PIW PIW_img_wr_commit(.PAD(img_wr_commit), .C(net_img_wr_commit));


    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : gen_piw_img_wr_addr
            PIW u_piw(.PAD(img_wr_addr[i]), .C(net_img_wr_addr[i]));
        end

        for (i = 0; i < 80; i = i + 1) begin : gen_piw_img_wr_row_data
            PIW u_piw(.PAD(img_wr_row_data[i]), .C(net_img_wr_row_data[i]));
        end
    endgenerate

    PO8W PO8W_busy(.I(net_busy), .PAD(busy));
    PO8W PO8W_done(.I(net_done), .PAD(done));
    PO8W PO8W_out_stream_valid(.I(net_out_stream_valid), .PAD(out_stream_valid));

    // 在芯片边界打一拍 img_wr_ready，减轻输出端时序压力。
    always @(posedge net_clk or negedge net_rst_n) begin
        if (!net_rst_n) begin
            net_img_wr_ready_r <= 1'b0;
        end else begin
            net_img_wr_ready_r <= net_img_wr_ready;
        end
    end

    PO8W PO8W_img_wr_ready(.I(net_img_wr_ready_r), .PAD(img_wr_ready));

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

        .out_stream_valid(net_out_stream_valid),
        .out_stream_data(net_out_stream_data)
    );

endmodule
