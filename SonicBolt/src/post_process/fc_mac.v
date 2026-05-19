`timescale 1ns / 1ps

module fc_mac (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               in_valid,
    input  wire               in_last,
    input  wire               in_fire,
    input  wire [31:0]        in_data_bus,
    input  wire [63:0]        in_weight_bus,
    output reg                out_valid,
    output reg                out_last,
    output reg                out_fire,
    output reg  signed [31:0] out_delta_cls0,
    output reg  signed [31:0] out_delta_cls1
);

    wire signed [7:0] data_lane0;
    wire signed [7:0] data_lane1;
    wire signed [7:0] data_lane2;
    wire signed [7:0] data_lane3;

    wire signed [7:0] weight_cls0_lane0;
    wire signed [7:0] weight_cls0_lane1;
    wire signed [7:0] weight_cls0_lane2;
    wire signed [7:0] weight_cls0_lane3;
    wire signed [7:0] weight_cls1_lane0;
    wire signed [7:0] weight_cls1_lane1;
    wire signed [7:0] weight_cls1_lane2;
    wire signed [7:0] weight_cls1_lane3;

    wire signed [15:0] product_cls0_lane0;
    wire signed [15:0] product_cls0_lane1;
    wire signed [15:0] product_cls0_lane2;
    wire signed [15:0] product_cls0_lane3;
    wire signed [15:0] product_cls1_lane0;
    wire signed [15:0] product_cls1_lane1;
    wire signed [15:0] product_cls1_lane2;
    wire signed [15:0] product_cls1_lane3;

    reg                stage1_valid;
    reg                stage1_last;
    reg                stage1_fire;
    reg signed [15:0]  product_cls0_lane0_reg;
    reg signed [15:0]  product_cls0_lane1_reg;
    reg signed [15:0]  product_cls0_lane2_reg;
    reg signed [15:0]  product_cls0_lane3_reg;
    reg signed [15:0]  product_cls1_lane0_reg;
    reg signed [15:0]  product_cls1_lane1_reg;
    reg signed [15:0]  product_cls1_lane2_reg;
    reg signed [15:0]  product_cls1_lane3_reg;

    wire signed [16:0] sum_l1_cls0_01;
    wire signed [16:0] sum_l1_cls0_23;
    wire signed [16:0] sum_l1_cls1_01;
    wire signed [16:0] sum_l1_cls1_23;
    wire signed [17:0] sum_l2_cls0;
    wire signed [17:0] sum_l2_cls1;
    wire signed [31:0] sum_cls0;
    wire signed [31:0] sum_cls1;

    assign data_lane0 = in_data_bus[7:0];
    assign data_lane1 = in_data_bus[15:8];
    assign data_lane2 = in_data_bus[23:16];
    assign data_lane3 = in_data_bus[31:24];

    assign weight_cls0_lane0 = in_weight_bus[7:0];
    assign weight_cls0_lane1 = in_weight_bus[15:8];
    assign weight_cls0_lane2 = in_weight_bus[23:16];
    assign weight_cls0_lane3 = in_weight_bus[31:24];

    assign weight_cls1_lane0 = in_weight_bus[39:32];
    assign weight_cls1_lane1 = in_weight_bus[47:40];
    assign weight_cls1_lane2 = in_weight_bus[55:48];
    assign weight_cls1_lane3 = in_weight_bus[63:56];

    assign product_cls0_lane0 = data_lane0 * weight_cls0_lane0;
    assign product_cls0_lane1 = data_lane1 * weight_cls0_lane1;
    assign product_cls0_lane2 = data_lane2 * weight_cls0_lane2;
    assign product_cls0_lane3 = data_lane3 * weight_cls0_lane3;

    assign product_cls1_lane0 = data_lane0 * weight_cls1_lane0;
    assign product_cls1_lane1 = data_lane1 * weight_cls1_lane1;
    assign product_cls1_lane2 = data_lane2 * weight_cls1_lane2;
    assign product_cls1_lane3 = data_lane3 * weight_cls1_lane3;

    assign sum_l1_cls0_01 = {{1{product_cls0_lane0_reg[15]}}, product_cls0_lane0_reg} +
                            {{1{product_cls0_lane1_reg[15]}}, product_cls0_lane1_reg};
    assign sum_l1_cls0_23 = {{1{product_cls0_lane2_reg[15]}}, product_cls0_lane2_reg} +
                            {{1{product_cls0_lane3_reg[15]}}, product_cls0_lane3_reg};
    assign sum_l1_cls1_01 = {{1{product_cls1_lane0_reg[15]}}, product_cls1_lane0_reg} +
                            {{1{product_cls1_lane1_reg[15]}}, product_cls1_lane1_reg};
    assign sum_l1_cls1_23 = {{1{product_cls1_lane2_reg[15]}}, product_cls1_lane2_reg} +
                            {{1{product_cls1_lane3_reg[15]}}, product_cls1_lane3_reg};

    assign sum_l2_cls0 = {{1{sum_l1_cls0_01[16]}}, sum_l1_cls0_01} +
                         {{1{sum_l1_cls0_23[16]}}, sum_l1_cls0_23};
    assign sum_l2_cls1 = {{1{sum_l1_cls1_01[16]}}, sum_l1_cls1_01} +
                         {{1{sum_l1_cls1_23[16]}}, sum_l1_cls1_23};

    assign sum_cls0 = {{14{sum_l2_cls0[17]}}, sum_l2_cls0};
    assign sum_cls1 = {{14{sum_l2_cls1[17]}}, sum_l2_cls1};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid <= 1'b0;
            stage1_last  <= 1'b0;
            stage1_fire  <= 1'b0;
            product_cls0_lane0_reg <= 16'sd0;
            product_cls0_lane1_reg <= 16'sd0;
            product_cls0_lane2_reg <= 16'sd0;
            product_cls0_lane3_reg <= 16'sd0;
            product_cls1_lane0_reg <= 16'sd0;
            product_cls1_lane1_reg <= 16'sd0;
            product_cls1_lane2_reg <= 16'sd0;
            product_cls1_lane3_reg <= 16'sd0;
            out_valid      <= 1'b0;
            out_last       <= 1'b0;
            out_fire       <= 1'b0;
            out_delta_cls0 <= 32'sd0;
            out_delta_cls1 <= 32'sd0;
        end else begin
            stage1_valid <= in_valid;
            stage1_last  <= in_last;
            stage1_fire  <= in_fire;

            product_cls0_lane0_reg <= product_cls0_lane0;
            product_cls0_lane1_reg <= product_cls0_lane1;
            product_cls0_lane2_reg <= product_cls0_lane2;
            product_cls0_lane3_reg <= product_cls0_lane3;
            product_cls1_lane0_reg <= product_cls1_lane0;
            product_cls1_lane1_reg <= product_cls1_lane1;
            product_cls1_lane2_reg <= product_cls1_lane2;
            product_cls1_lane3_reg <= product_cls1_lane3;

            out_valid <= stage1_valid;
            out_last  <= stage1_last;
            out_fire  <= stage1_fire;

            if (stage1_valid) begin
                out_delta_cls0 <= sum_cls0;
                out_delta_cls1 <= sum_cls1;
            end else begin
                out_delta_cls0 <= 32'sd0;
                out_delta_cls1 <= 32'sd0;
            end
        end
    end

endmodule
