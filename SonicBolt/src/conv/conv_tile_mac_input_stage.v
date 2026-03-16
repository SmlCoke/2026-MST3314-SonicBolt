`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_input_stage
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 功能概述:
 *   作为 conv_tile_mac 的输入寄存级，锁存窗口、权重和偏置总线。
 *
 * 设计说明:
 *   - 该级的主要作用是切断输入窗口切片逻辑与后续乘法阵列之间的长路径。
 *   - 当前窗口位宽为 1120bit，权重总线位宽为 2464bit，偏置总线位宽为 64bit。
 *   - 本模块只做寄存，不做算术。消耗的寄存器资源：14*10*8 + 4*7*8*11 + 4*16 bit = 3648 bit = 456 B = 0.456 KB
 *   - 作用是把输入窗口、参数总线和元数据先切开，避免上游切窗和下游乘法直连
 */
module conv_tile_mac_input_stage (
    input  wire                clk,              // 时钟
    input  wire                rst_n,            // 低有效复位
    
    // ---------- 输入数据(总线形式) ----------
    input  wire [14*10*8-1:0]  in_pos_window,    // 14x10x8bit 输入窗口
    input  wire [4*7*8*11-1:0] in_weight_bus,    // 当前 group 的完整权重总线
    input  wire [4*16-1:0]     in_bias_bus,      // 当前 group 的 4 个 INT16 偏置
    
    // ---------- 寄存器打拍输出 ----------
    output reg  [14*10*8-1:0]  out_pos_window,   // 打一拍后的窗口
    output reg  [4*7*8*11-1:0] out_weight_bus,   // 打一拍后的权重总线
    output reg  [4*16-1:0]     out_bias_bus      // 打一拍后的偏置总线
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_pos_window <= {14*10*8{1'b0}};
            out_weight_bus <= {4*7*8*11{1'b0}};
            out_bias_bus   <= {4*16{1'b0}};
        end else begin
            out_pos_window <= in_pos_window;
            out_weight_bus <= in_weight_bus;
            out_bias_bus   <= in_bias_bus;
        end
    end

endmodule
