`timescale 1ns / 1ps
/*
 * 模块名称: fc_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-04-12
 * 版本: v1.2
 *
 * 功能概述:
 *   - 计算单个 token 的 4 路 lane 乘加增量
 *   - 输入: 4 路 INT8 激活 + 2 类权重(每类 4 路 INT8)
 *   - 输出: class0/class1 两路 INT32 增量
 *
 * 设计说明:
 *   - 该模块仅做 token 级组合计算，不持有帧级状态
 *   - 累加状态由 fc_frame_accum 维护
 * 
 * 运算复杂度分析: 
 *   - 8 个 并行 INT8 乘法器 级联 两组两级加法树 4 x INT8 -> 1 x INT32
 *   - 逻辑深度为: 1M + 2A
 *  
 * 版本定位:
 *   - v1.0 完成基本功能实现
 *   - v1.1 将 v1.0 的组合逻辑模块升级为时序流水线，用寄存器打拍输出
 *   - v1.2 优化了加法树结构，将原来的串行级联加法结构修改为平衡加法树，减少综合工具优化压力。
 */
module fc_mac (
    input  wire               clk,
    input  wire               rst_n,
    // ---------- 输入元数据 ----------
    input  wire               in_valid,         // 当前输入数据有效
    input  wire               in_last,          // 当前输入数据是否为最后一个 token
    input  wire               in_fire,          // 启动信号
    input  wire [31:0]        in_data_bus,      // 输入数据，4(ch) x INT8 = 32bit
    input  wire [63:0]        in_weight_bus,    // 输入权重，8 x INT8 = 64bit

    // ---------- 输出元数据 ----------
    output reg                out_valid,
    output reg                out_last,
    output reg                out_fire,

    // ---------- 输出增量 ----------
    output reg  signed [31:0] out_delta_cls0,
    output reg  signed [31:0] out_delta_cls1
);

    // 4 路 lane 的输入激活值，按低位到高位依次取出
    wire signed [7:0] data_lane0;
    wire signed [7:0] data_lane1;
    wire signed [7:0] data_lane2;
    wire signed [7:0] data_lane3;

    // 两个类别各自对应的 4 路权重
    wire signed [7:0] weight_cls0_lane0;
    wire signed [7:0] weight_cls0_lane1;
    wire signed [7:0] weight_cls0_lane2;
    wire signed [7:0] weight_cls0_lane3;
    wire signed [7:0] weight_cls1_lane0;
    wire signed [7:0] weight_cls1_lane1;
    wire signed [7:0] weight_cls1_lane2;
    wire signed [7:0] weight_cls1_lane3;

    // 先并行完成 4 路乘法
    wire signed [15:0] product_cls0_lane0;
    wire signed [15:0] product_cls0_lane1;
    wire signed [15:0] product_cls0_lane2;
    wire signed [15:0] product_cls0_lane3;
    wire signed [15:0] product_cls1_lane0;
    wire signed [15:0] product_cls1_lane1;
    wire signed [15:0] product_cls1_lane2;
    wire signed [15:0] product_cls1_lane3;

    // 再按 2 级平衡加法树归约，避免 RTL 上形成 4 项串行级联加法器
    wire signed [16:0] sum_l1_cls0_01;
    wire signed [16:0] sum_l1_cls0_23;
    wire signed [16:0] sum_l1_cls1_01;
    wire signed [16:0] sum_l1_cls1_23;
    wire signed [17:0] sum_l2_cls0;
    wire signed [17:0] sum_l2_cls1;

    // 最终输出仍保持 INT32，接口与时序均不变
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

    assign sum_l1_cls0_01 = {{1{product_cls0_lane0[15]}}, product_cls0_lane0} +
                            {{1{product_cls0_lane1[15]}}, product_cls0_lane1};
    assign sum_l1_cls0_23 = {{1{product_cls0_lane2[15]}}, product_cls0_lane2} +
                            {{1{product_cls0_lane3[15]}}, product_cls0_lane3};
    assign sum_l1_cls1_01 = {{1{product_cls1_lane0[15]}}, product_cls1_lane0} +
                            {{1{product_cls1_lane1[15]}}, product_cls1_lane1};
    assign sum_l1_cls1_23 = {{1{product_cls1_lane2[15]}}, product_cls1_lane2} +
                            {{1{product_cls1_lane3[15]}}, product_cls1_lane3};

    assign sum_l2_cls0 = {{1{sum_l1_cls0_01[16]}}, sum_l1_cls0_01} +
                         {{1{sum_l1_cls0_23[16]}}, sum_l1_cls0_23};
    assign sum_l2_cls1 = {{1{sum_l1_cls1_01[16]}}, sum_l1_cls1_01} +
                         {{1{sum_l1_cls1_23[16]}}, sum_l1_cls1_23};

    assign sum_cls0 = {{14{sum_l2_cls0[17]}}, sum_l2_cls0};
    assign sum_cls1 = {{14{sum_l2_cls1[17]}}, sum_l2_cls1};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid      <= 1'b0;
            out_last       <= 1'b0;
            out_fire       <= 1'b0;
            out_delta_cls0 <= 32'sd0;
            out_delta_cls1 <= 32'sd0;
        end else begin
            // 元数据直接打拍输出
            out_valid <= in_valid;
            out_last  <= in_last;
            out_fire  <= in_fire;

            if (in_valid) begin
                out_delta_cls0 <= sum_cls0;
                out_delta_cls1 <= sum_cls1;
            end else begin
                out_delta_cls0 <= 32'sd0;
                out_delta_cls1 <= 32'sd0;
            end
        end
    end

endmodule
