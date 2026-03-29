`timescale 1ns / 1ps
/*
 * 模块名称: meta_pipe
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 *
 * 功能概述:
 *   通用模块：元数据打拍寄存，用于对齐各个流水阶段。
 *   五大元数据信号：
 *     - valid: 当前 tile 是否有效
 *     - last: 当前 tile 是否为整张图的最后一个 token
 *     - pos: 当前 token 的 pos 编号
 *     - group: 当前 token 的 group 编号
 *     - fire: 后一层的启动信号，置高时间仅比 valid 早一个周期，用于启动参数 SRAM 的预读
 *
 * 设计说明:
 *   - 本模块只负责打一拍寄存，不参与任何算术。
 *   - 这样可以避免把 metadata 对齐逻辑分散到各个算术子模块中。
 *
 * 版本定位:
 */
module meta_pipe (
    input  wire       clk,       // 时钟
    input  wire       rst_n,     // 低有效复位
    
    // ---------- 输入 metadata ----------
    input  wire       in_valid,  // 输入 metadata 有效
    input  wire       in_last,   // 当前 tile 是否为整张图最后一个 tile
    input  wire [3:0] in_pos,    // 当前 tile 的 pos 编号
    input  wire [2:0] in_group,  // 当前 tile 的 group 编号
    input  wire       in_fire,   // 后一层启动信号

    // ---------- 输出 metadata ----------
    output reg        out_valid, // 打一拍后的 valid
    output reg        out_last,  // 打一拍后的 last
    output reg [3:0]  out_pos,   // 打一拍后的 pos
    output reg [2:0]  out_group, // 打一拍后的 group
    output reg        out_fire   // 打一拍后的后一层启动信号
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_last  <= 1'b0;
            out_pos   <= 4'd0;
            out_group <= 3'd0;
            out_fire  <= 1'b0;
        end else begin
            out_valid <= in_valid;
            out_last  <= in_last;
            out_pos   <= in_pos;
            out_group <= in_group;
            out_fire  <= in_fire;
        end
    end

endmodule
