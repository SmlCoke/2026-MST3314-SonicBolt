// `timescale 1ns / 1ps
// /*
//  * 模块名称: conv_rescale_shift_stage
//  * 作者: SonicBolt 团队
//  * 日期: 2026-03-15
//  * 版本: v1.0
//  *
//  * 功能概述:
//  *   量化流水第 2 级，只负责对称舍入和算术右移。
//  */
// module conv_rescale_shift_stage #(
//     parameter integer SHIFT_N = 14
// ) (
//     input  wire          clk,            // 时钟
//     input  wire          rst_n,          // 低有效复位
//     input  wire [3071:0] in_mult_bus,    // 64 个 INT48 乘法结果
//     output reg  [2047:0] out_shift_bus   // 64 个 INT32 右移结果
// );

//     integer idx;
//     reg signed [47:0] mult_value;
//     reg signed [47:0] rounded_value;
//     reg signed [47:0] round_bias;
//     reg signed [47:0] shifted_value;

//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             out_shift_bus <= 2048'd0;
//         end else begin
//             for (idx = 0; idx < 64; idx = idx + 1) begin
//                 mult_value = in_mult_bus[idx*48 +: 48];
                
//                 // 这里将移位替换为四舍五入，等效为：int(x+0.5)
//                 // 首先执行 + 0.5 操作，计算公式：
//                 // floor(result + 0.5) = floor(mult_value/2^shift_n + 0.5)
//                 // = floor((mult_value + 2^(shift_n-1)) / 2^shift_n)
//                 // 当然，在 Verilog 中，floor 通过算术右移实现，因此对于负数是 - 2^(shift_n-1)
//                 if (SHIFT_N > 0) begin
//                     round_bias = 48'sd1 <<< (SHIFT_N - 1);
//                     if (mult_value >= 0) begin
//                         rounded_value = mult_value + round_bias;
//                     end else begin
//                         rounded_value = mult_value - round_bias;
//                     end
//                 end else begin
//                     rounded_value = mult_value;
//                 end

//                 shifted_value = rounded_value >>> SHIFT_N;
//                 out_shift_bus[idx*32 +: 32] <= shifted_value[31:0];
//             end
//         end
//     end

// endmodule


`timescale 1ns / 1ps
/*
 * 模块名称: conv_rescale_shift_stage
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v0.0
 *
 * 功能概述:
 *   量化流水第 2 级，只负责算术右移。
 *   该模块相比 v1.0 去掉了四舍五入逻辑，原因在于训练得到的参数本就没有进行四舍五入，加入后反而会引入额外误差。
 */
module conv_rescale_shift_stage #(
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,            // 时钟
    input  wire          rst_n,          // 低有效复位
    input  wire [3071:0] in_mult_bus,    // 64 个 INT48 乘法结果
    output reg  [2047:0] out_shift_bus   // 64 个 INT32 右移结果
);

    integer idx;
    reg signed [47:0] mult_value;
    reg signed [47:0] rounded_value;
    reg signed [47:0] round_bias;
    reg signed [47:0] shifted_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_shift_bus <= 2048'd0;
        end else begin
            for (idx = 0; idx < 64; idx = idx + 1) begin
                mult_value = in_mult_bus[idx*48 +: 48];
                shifted_value = mult_value >>> SHIFT_N;
                out_shift_bus[idx*32 +: 32] <= shifted_value[31:0];
            end
        end
    end

endmodule
