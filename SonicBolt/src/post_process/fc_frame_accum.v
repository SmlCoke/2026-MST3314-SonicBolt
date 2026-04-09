`timescale 1ns / 1ps
/*
 * 模块名称: fc_frame_accum
 * 作者: SonicBolt 团队
 * 日期: 2026-04-09
 * 版本: v1.2
 *
 * 功能概述:
 *   - 维护 FC 帧级累加状态，也就是不同周期到达的 token 增量累加。
 *   - 每拍接收两路 token 增量(class0/class1)，更新帧内累加器。
 *   - 当 in_last=1 时输出本帧最终累加结果并清空状态。
 *
 * 设计说明:
 *   - 在 fire 到来时，将 bias 作为新一帧的初始累加值装入寄存器。
 *   - out_sum_* 为寄存器输出，避免将组合累加结果直接送往后级。
 *
 * 版本定位:
 *   - v1.0 完成基本功能实现
 *   - v1.1 优化了时序逻辑，删除了部分冗余逻辑，同时回复 fire 信号作为启动信号的功能地位
 *   - v1.2 将杂糅的状态转移逻辑重构为有限状态机
 */
module fc_frame_accum (
    input  wire               clk,
    input  wire               rst_n,

    // ---------- 输入元数据 ----------
    input  wire               in_valid,
    input  wire               in_last,
    input  wire               in_fire,
    
    // ---------- 输入两路增量数据 ----------
    input  wire signed [31:0] in_delta_cls0,
    input  wire signed [31:0] in_delta_cls1,

    // ---------- 输入偏置总线 ----------
    input  wire signed [15:0] in_bias_cls0,
    input  wire signed [15:0] in_bias_cls1,

    // ---------- 输出结果 ----------
    output wire               out_valid,
    output reg  signed [31:0] out_sum_cls0,
    output reg  signed [31:0] out_sum_cls1
);
    // 状态机状态列表
    parameter IDLE  = 2'b00;
    parameter BUSY  = 2'b01;
    parameter DONE  = 2'b10;
    reg  [1:0] current_state;
    reg  [1:0] next_state;

    reg               frame_busy;          // 模块状态
    reg               out_valid_reg;  // 输出有效寄存器，保持一拍
    reg signed [31:0] accum_cls0;          // 累加器：class0 累加结果
    reg signed [31:0] accum_cls1;          // 累加器：class1 累加结果

    wire               frame_start;        // 帧开始标志：fire 到来且当前不忙
    wire signed [31:0] bias_cls0_32;       // 扩展到 32bit 的 class0 bias，作为累加初始值
    wire signed [31:0] bias_cls1_32;       // 扩展到 32bit 的 class1 bias，作为累加初始值
    
    // 当前拍累加基准：如果在帧内则为累加器，否则为 bias(初始状态)
    wire signed [31:0] accum_base_cls0;    
    wire signed [31:0] accum_base_cls1;
    
    // 当前拍计算出的下一累加结果：基准 + 增量
    wire signed [31:0] sum_next_cls0;      
    wire signed [31:0] sum_next_cls1;      

    assign frame_start = in_fire && !frame_busy;
    assign bias_cls0_32 = {{16{in_bias_cls0[15]}}, in_bias_cls0};
    assign bias_cls1_32 = {{16{in_bias_cls1[15]}}, in_bias_cls1};

    // fire 只在一帧开始时装载 bias；若异常情况下 valid 先于 fire 到来，
    // 这里也会回退到“bias + delta”的兼容行为，避免从 0 开始累计。
    assign accum_base_cls0 = frame_busy ? accum_cls0 : bias_cls0_32;
    assign accum_base_cls1 = frame_busy ? accum_cls1 : bias_cls1_32;

    // 当前拍更新后的结果：中间拍写回 accum，最后一拍锁存到 out_sum。
    assign sum_next_cls0 = accum_base_cls0 + in_delta_cls0;
    assign sum_next_cls1 = accum_base_cls1 + in_delta_cls1;

    // 最后一个 token 到来当拍先拉高 fire，下一拍再拉高 valid。
    // assign out_fire  = in_valid && in_last;
    assign out_valid = out_valid_reg;

    // 三段式状态机第一段：状态更新逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // 三段式状态机第二段：下一个状态计算逻辑
    always @(*) begin
        next_state = current_state; // 默认保持当前状态
        case (current_state)
            IDLE: begin
                if (frame_start) begin
                    next_state = BUSY;
                end else begin
                    next_state = IDLE;
                end
            end

            BUSY: begin
                if (in_valid && in_last) begin
                    next_state = DONE;
                end else begin
                    next_state = BUSY;
                end
                 
            end

            DONE: begin
                next_state = IDLE;
            end
        endcase

    end

    // 三段式状态机第三段：输出逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_busy         <= 1'b0;
            out_valid_reg      <= 1'b0;
            accum_cls0         <= 32'sd0;
            accum_cls1         <= 32'sd0;
            out_sum_cls0       <= 32'sd0;
            out_sum_cls1       <= 32'sd0;
        end else begin
            // emit_valid 只保持一拍，数据由寄存器稳定输出。
            out_valid_reg <= 1'b0;
            case (current_state)
                IDLE: begin
                    // 本质就是 fire 信号，只在帧首装载一次 bias，避免 fire 连续为高时反复覆盖累加状态。
                    if (frame_start) begin
                        frame_busy <= 1'b1;
                        accum_cls0 <= bias_cls0_32;
                        accum_cls1 <= bias_cls1_32;
                    end
                end

                BUSY: begin
                    if (in_valid) begin
                        if (in_last) begin
                            // 最后一拍把最终结果打到寄存器，供下一拍外部采样。
                            frame_busy         <= 1'b0;
                            out_valid_reg      <= 1'b1;
                            accum_cls0         <= 32'sd0;
                            accum_cls1         <= 32'sd0;
                            out_sum_cls0       <= sum_next_cls0;
                            out_sum_cls1       <= sum_next_cls1;
                        end else begin
                            frame_busy <= 1'b1;
                            accum_cls0 <= sum_next_cls0;
                            accum_cls1 <= sum_next_cls1;
                        end
                    end
                end

                DONE: begin
                    frame_busy <= 1'b0;
                end
                default: begin
                    frame_busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
