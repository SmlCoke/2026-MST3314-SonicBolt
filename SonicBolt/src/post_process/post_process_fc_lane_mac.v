`timescale 1ns / 1ps
/*
 * 模块名称: post_process_fc_lane_mac
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 计算单个 token 的 4 路 lane 乘加增量
 *   - 输入: 4 路 INT8 激活 + 2 类权重(每类 4 路 INT8)
 *   - 输出: class0/class1 两路 INT32 增量
 *
 * 设计说明:
 *   - 该模块仅做 token 级组合计算，不持有帧级状态
 *   - 累加状态由 post_process_fc_frame_accum 维护
 */
module post_process_fc_lane_mac (
    input  wire [31:0] in_data_bus,// 4(ch) x INT8 = 32bit
    input  wire [63:0] in_weight_bus,

    output reg  signed [31:0] out_delta_cls0,
    output reg  signed [31:0] out_delta_cls1
);

    integer lane_idx;

    reg signed [7:0]  data_value;
    reg signed [7:0]  weight_value_cls0;
    reg signed [7:0]  weight_value_cls1;
    reg signed [15:0] product_cls0;
    reg signed [15:0] product_cls1;

    always @(*) begin
        out_delta_cls0 = 32'sd0;
        out_delta_cls1 = 32'sd0;

        for (lane_idx = 0; lane_idx < 4; lane_idx = lane_idx + 1) begin
            data_value        = in_data_bus[(lane_idx * 8) +: 8];
            weight_value_cls0 = in_weight_bus[(lane_idx * 8) +: 8];
            weight_value_cls1 = in_weight_bus[32 + (lane_idx * 8) +: 8];

            product_cls0 = data_value * weight_value_cls0;
            product_cls1 = data_value * weight_value_cls1;

            out_delta_cls0 = out_delta_cls0 + {{16{product_cls0[15]}}, product_cls0};
            out_delta_cls1 = out_delta_cls1 + {{16{product_cls1[15]}}, product_cls1};
        end
    end

endmodule
