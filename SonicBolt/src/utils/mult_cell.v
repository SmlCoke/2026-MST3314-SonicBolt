`timescale 1ns / 1ps
/*
 * 模块名称: mult_cell
 * 作者: SonicBolt 团队
 * 日期: 2026-04-12
 * 版本: v1.0
 *
 * 功能:
 *   对单个 INT8xINT8 输入对执行一次乘法，输出 INT16 乘积。
 *
 * 说明:
 *   该模块仅做组合计算，不含时序寄存器。
 */
module mult_cell (
    input  wire signed [7:0]  data,
    input  wire signed [7:0]  wt,
    output wire signed [15:0] out_prod
);
    assign out_prod = data * wt;
endmodule