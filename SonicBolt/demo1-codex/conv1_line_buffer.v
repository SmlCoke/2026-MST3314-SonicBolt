`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: conv1_line_buffer
// 功能  : Conv1 行缓冲，保存 11 行输入特征图（每行 10 个 INT8 = 80bit）
// 说明  :
//   1. line_buf[0] 表示最旧的一行（窗口顶部）
//   2. line_buf[10] 表示最新的一行（窗口底部）
//   3. push_row=1 时执行“整体上移 + 新行写入底部”
// -----------------------------------------------------------------------------
module conv1_line_buffer (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         push_row,
    input  wire [79:0]  row_in,
    output wire [879:0] line_flat
);
    reg [79:0] line_buf [0:10];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 11; i = i + 1) begin
                line_buf[i] <= 80'd0;
            end
        end else if (push_row) begin
            for (i = 0; i < 10; i = i + 1) begin
                line_buf[i] <= line_buf[i + 1];
            end
            line_buf[10] <= row_in;
        end
    end

    genvar g;
    generate
        for (g = 0; g < 11; g = g + 1) begin : GEN_PACK
            assign line_flat[g*80 +: 80] = line_buf[g];
        end
    endgenerate

endmodule

