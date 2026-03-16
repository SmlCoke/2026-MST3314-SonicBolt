`timescale 1ns / 1ps
/*
 * 模块名称: conv_pos_window_gen
 * 功能概述: 从完整输入图中切出某个 pos 对应的 14x10 输入窗口。
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 当前角色:
 *   - 主通路输入切片模块
 *   - 把 30x10 的整图表示转换成 Conv1 所需的 14x10 pos 窗口表示
 *
 * 位宽说明:
 *   - frame_data  = 30 x 10 x 8bit = 2400bit，对应 [2399:0]
 *   - window_data = 14 x 10 x 8bit = 1120bit，对应 [1119:0]
 *   - pos_idx 取值范围 0~8，因此 4bit 足够
 *
 * pos 映射规则:
 *   - pos=0 取输入行 0..13
 *   - pos=1 取输入行 2..15
 *   - ...
 *   - pos=8 取输入行 16..29
 *   - 相邻 pos 之间只前进 2 行，这是整网后续形状变换的基础
 * 
 * 地址变换公式:
 *   - 窗口中第 row_idx 行与输入图第 src_row 行满足的变换关系为：
 *       src_row = pos_idx * 2 + row_idx
 */
module conv_pos_window_gen (
    input  wire [30*10*8-1:0] frame_data,   // 完整输入图，按 [row][col][8bit] 展平后的 2400bit 总线
    input  wire [3:0]    pos_idx,           // 当前要抽取的 pos 编号，范围 0~8
    output reg  [14*10*8-1:0] window_data   // 当前 pos 对应的 14x10 输入窗口，供 Conv1 计算使用
);

    integer row_idx;
    integer col_idx;
    integer src_row;

    // 纯组合切片逻辑：
    // 对于窗口中的第 row_idx 行，实际从原图的 src_row = pos_idx*2 + row_idx 读取
    // 每一行仍然保留 10 列，因此窗口总宽度仍然是 10 个 INT8 像素
    always @(*) begin
        window_data = 1120'd0;
        for (row_idx = 0; row_idx < 14; row_idx = row_idx + 1) begin
            src_row = pos_idx * 2 + row_idx;
            for (col_idx = 0; col_idx < 10; col_idx = col_idx + 1) begin
                window_data[(row_idx*10 + col_idx)*8 +: 8] = 
                 frame_data[(src_row*10 + col_idx)*8 +: 8];
            end
        end
    end

endmodule
