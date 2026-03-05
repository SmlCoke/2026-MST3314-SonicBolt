`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: MAC_Tree_77
// 功能  : 77 路乘累加树（3 级流水）
// 延迟  : valid_in -> valid_out 共 3 拍
// -----------------------------------------------------------------------------
module MAC_Tree_77 (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              valid_in,
    input  wire [615:0]      act_flat_in,
    input  wire [615:0]      wgt_flat_in,
    input  wire signed [15:0] bias_in,
    output wire              valid_out,
    output wire signed [31:0] mac_out
);
    wire         valid_mult;
    wire         valid_s1;
    wire         valid_s2;
    wire [1231:0] products;
    wire [199:0]  psums_s1;
    wire signed [31:0] mac_s2;

    MAC77_Mult u_mult (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .act_flat_in(act_flat_in),
        .wgt_flat_in(wgt_flat_in),
        .valid_out  (valid_mult),
        .products   (products)
    );

    MAC77_AddTree_s1 u_addtree_s1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_mult),
        .products   (products),
        .valid_out  (valid_s1),
        .psums_out  (psums_s1)
    );

    MAC77_AddTree_s2 u_addtree_s2 (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_s1),
        .psums_in   (psums_s1),
        .bias_in    (bias_in),
        .valid_out  (valid_s2),
        .mac_out    (mac_s2)
    );

    assign valid_out = valid_s2;
    assign mac_out   = mac_s2;

endmodule

