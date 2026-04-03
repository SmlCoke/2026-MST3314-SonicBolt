`timescale 1ns / 1ps
/*
 * 模块名称: post_process_fc_frame_accum
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 维护 FC 帧级累加状态，也就是不同周期到达的累加
 *   - 每拍接收两路 token 增量(class0/class1)，更新帧内累加器
 *   - 当 in_last=1 时输出本帧最终累加结果并清空状态
 *
 * 设计说明:
 *   - out_sum_* 为组合结果（当前拍 base + delta）
 *   - 模块内部只持有 frame_busy 与 accum 状态
 */
module post_process_fc_frame_accum (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire               in_last,
    input  wire signed [31:0] in_delta_cls0,
    input  wire signed [31:0] in_delta_cls1,

    output wire               out_emit_valid,
    output wire               out_emit_last,
    output wire signed [31:0] out_sum_cls0,
    output wire signed [31:0] out_sum_cls1
);

    reg               frame_busy;
    reg signed [31:0] accum_cls0;
    reg signed [31:0] accum_cls1;

    reg signed [31:0] accum_next_cls0;
    reg signed [31:0] accum_next_cls1;

    wire signed [31:0] accum_base_cls0;
    wire signed [31:0] accum_base_cls1;

    assign accum_base_cls0 = frame_busy ? accum_cls0 : 32'sd0;
    assign accum_base_cls1 = frame_busy ? accum_cls1 : 32'sd0;

    assign out_sum_cls0 = accum_base_cls0 + in_delta_cls0;
    assign out_sum_cls1 = accum_base_cls1 + in_delta_cls1;

    assign out_emit_valid = in_valid && in_last;
    assign out_emit_last  = in_valid && in_last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_busy <= 1'b0;
            accum_cls0 <= 32'sd0;
            accum_cls1 <= 32'sd0;
        end else begin
            if (in_valid) begin
                accum_next_cls0 = accum_base_cls0 + in_delta_cls0;
                accum_next_cls1 = accum_base_cls1 + in_delta_cls1;

                if (in_last) begin
                    frame_busy <= 1'b0;
                    accum_cls0 <= 32'sd0;
                    accum_cls1 <= 32'sd0;
                end else begin
                    frame_busy <= 1'b1;
                    accum_cls0 <= accum_next_cls0;
                    accum_cls1 <= accum_next_cls1;
                end
            end
        end
    end

endmodule
