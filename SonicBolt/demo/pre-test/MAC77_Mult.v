`timescale 1ns / 1ps

// =============================================================================
// Module Name : MAC77_Mult
// Description : 面向 11x7 卷积窗的 77 路并行乘累加树。
//               采用 3 级流水线设计，确保满足 150MHz+ 时序要求。
//               带数据门控（Data Gating）技术，极致降低动态功耗。
// 本模块是第一个子模块，实现 77 路并行乘法
// =============================================================================

module MAC77_Mult (
    input wire                 clk,
    input wire                 rst_n,
    
    // 控制信号
    input wire                 valid_in,     // 输入数据有效
    
    // 数据输入 (由于77个端口太多，工业界标准做法是将数组展平为一维宽向量)
    // 77 * 8 bit = 616 bits
    input wire [615:0]         act_flat_in,  // 77个INT8激活值 (从Line Buffer来)
    input wire [615:0]         wgt_flat_in,  // 77个INT8权重值 (从SRAM/寄存器来)
    
    // 输出信号
    output reg                 valid_out,    // 输出数据有效
    output reg [77*16-1:0]     products      // 输出的 77 个 INT16
);

    integer i;
    // fj0304: 为了兼容老旧综合工具，这里要先声明 i 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            products  <= {(77*16){1'b0}};
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                for (i = 0; i < 77; i = i + 1) begin
                    products[i*16 +: 16] <=
                        $signed(act_flat_in[i*8 +: 8]) * $signed(wgt_flat_in[i*8 +: 8]);
                    // fj0304: 这种固定边界 for 会被综合展开为常量位选和并行乘法器
                    // fj0304: 也就是说，这里的 i 是编译时常量，不会带来任何循环控制逻辑开销
                end
            end
        end
    end

endmodule