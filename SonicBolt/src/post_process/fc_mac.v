`timescale 1ns / 1ps
/*
 * 模块名称: fc_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-04-05
 * 版本: v1.0
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
 * 版本定位:
 *   - v1.0 完成基本功能实现
 *   - v1.1 将 v1.0 的组合逻辑模块升级为时序流水线，用寄存器打拍输出
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

    integer lane_idx;

    reg signed [7:0]  data_value;
    reg signed [7:0]  weight_value_cls0;
    reg signed [7:0]  weight_value_cls1;
    reg signed [15:0] product_cls0;
    reg signed [15:0] product_cls1;
    reg signed [31:0] sum_cls0;
    reg signed [31:0] sum_cls1;

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
                sum_cls0 = 32'sd0;
                sum_cls1 = 32'sd0;

                for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
                    data_value        = in_data_bus[(lane_idx * 8) +: 8];
                    weight_value_cls0 = in_weight_bus[(lane_idx * 8) +: 8];
                    weight_value_cls1 = in_weight_bus[32 + (lane_idx * 8) +: 8];

                    product_cls0 = data_value * weight_value_cls0;
                    product_cls1 = data_value * weight_value_cls1;

                    sum_cls0 = sum_cls0 + {{16{product_cls0[15]}}, product_cls0};
                    sum_cls1 = sum_cls1 + {{16{product_cls1[15]}}, product_cls1};
                end

                out_delta_cls0 <= sum_cls0;
                out_delta_cls1 <= sum_cls1;
            end else begin
                out_delta_cls0 <= 32'sd0;
                out_delta_cls1 <= 32'sd0;
            end
        end
    end

endmodule
