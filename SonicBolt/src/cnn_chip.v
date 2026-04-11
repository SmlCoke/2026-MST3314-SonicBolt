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


    wire         net_out_stream_valid;
    wire [63:0]  net_out_stream_data;
    // 说明:
    //   下方这些内部“伪配置”连线仅用于综合场景绕开工具对大规模常量端口折叠时的崩溃问题。
    //   课程当前阶段把参数 SRAM 视作片内已写好（ROM 使用），因此这里不再对外暴露参数写 PAD。
    //   为避免 ZenSyn 在常量传播阶段崩溃，这里使用非恒定信号驱动 cnn 的参数写端口。
    //   其中 wr_en 只在复位期间拉高，正常运行阶段保持为 0。
    wire         cfg_wr_en;
    wire [4:0]   cfg_bank5;
    wire [2:0]   cfg_bank3;
    wire [1:0]   cfg_bank2;
    wire [2:0]   cfg_addr3;
    wire [6:0]   cfg_addr7;
    wire [7:0]   cfg_addr8;
    wire [223:0] cfg_data224;
    wire [127:0] cfg_data128;
    wire [95:0]  cfg_data96;
    wire [63:0]  cfg_data64;
    wire [31:0]  cfg_data32;

    assign cfg_wr_en   = ~net_rst_n;
    assign cfg_bank5   = net_img_wr_addr;
    assign cfg_bank3   = net_img_wr_addr[2:0];
    assign cfg_bank2   = net_img_wr_addr[1:0];
    assign cfg_addr3   = net_img_wr_addr[2:0];
    assign cfg_addr7   = {net_img_wr_en, net_img_wr_addr, net_img_wr_en};
    assign cfg_addr8   = {net_img_wr_en, net_img_wr_addr, net_img_wr_addr[1:0]};
    assign cfg_data224 = {net_img_wr_row_data, net_img_wr_row_data, net_img_wr_row_data[63:0]};
    assign cfg_data128 = {net_img_wr_row_data, net_img_wr_row_data[47:0]};
    assign cfg_data96  = {net_img_wr_row_data, net_img_wr_row_data[15:0]};
    assign cfg_data64  = net_img_wr_row_data[63:0];
    assign cfg_data32  = net_img_wr_row_data[31:0];

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

        .conv_weight_wr_en(cfg_wr_en),
        .conv_weight_wr_bank(cfg_bank5),
        .conv_weight_wr_addr(cfg_addr3),
        .conv_weight_wr_data(cfg_data224),

        .dwconv_weight_wr_en(cfg_wr_en),
        .dwconv_weight_wr_bank(cfg_bank2),
        .dwconv_weight_wr_addr(cfg_addr3),
        .dwconv_weight_wr_data(cfg_data96),

        .pwconv_weight_wr_en(cfg_wr_en),
        .pwconv_weight_wr_bank(cfg_bank3),
        .pwconv_weight_wr_addr(cfg_addr3),
        .pwconv_weight_wr_data(cfg_data128),

        .conv_bias_wr_en(cfg_wr_en),
        .conv_bias_wr_bank(cfg_bank3[0]),
        .conv_bias_wr_addr(cfg_addr3),
        .conv_bias_wr_data(cfg_data64),

        .dwconv_bias_wr_en(cfg_wr_en),
        .dwconv_bias_wr_bank(cfg_bank3[0]),
        .dwconv_bias_wr_addr(cfg_addr3),
        .dwconv_bias_wr_data(cfg_data64),

        .pwconv_bias_wr_en(cfg_wr_en),
        .pwconv_bias_wr_bank(cfg_bank3[0]),
        .pwconv_bias_wr_addr(cfg_addr3),
        .pwconv_bias_wr_data(cfg_data64),

        .fc_weight_wr_en(cfg_wr_en),
        .fc_weight_wr_addr(cfg_addr7),
        .fc_weight_wr_data(cfg_data64),
        .fc_bias_wr_en(cfg_wr_en),
        .fc_bias_wr_data(cfg_data32),
        .sigmoid_lut_wr_en(cfg_wr_en),
        .sigmoid_lut_wr_addr(cfg_addr8),
        .sigmoid_lut_wr_data(cfg_data32),

        .out_stream_valid(net_out_stream_valid),
        .out_stream_data(net_out_stream_data)
    );

endmodule
