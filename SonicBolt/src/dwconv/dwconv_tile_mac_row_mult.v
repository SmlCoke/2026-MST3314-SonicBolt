`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 *
 * 功能概述:
 *   计算某一条预切分 kernel_row 对应的 3 项行内卷积和。
 *   kernel 的一行需要与输入窗口中的 2 行输入条带做卷积。
 *
 * 计算分析:
 *   - 一共 4 个输出通道
 *   - 每个通道需要计算 2x2 个空间位置
 *   - 每个空间位置做 3 组 INT8 乘加(3组结果)
 *
 * 位宽说明:
 *   - row_window_data: 4(ch) x 2(row) x 4(col) x 8(width)
 *   - weight_row_data: 4(ch) x 3(col) x 8(width)
 *   - out_row_sum_bus: 4(ch) x 2(row) x 2(col) x 18(width) 
 *
 * 设计说明:
 *   - 本级只处理 3 项乘法与行内加法树，不做跨 kernel_row 的累加。
 *   - 权重也已经在外部预切分为当前 kernel_row 的 96bit 行权重。
 * 
 * 版本定位:
 */
module dwconv_tile_mac_row_mult (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位
    input  wire [4*2*4*8-1:0]  row_window_data, // 当前 kernel_row 对应的 2 行输入条带
    input  wire [4*3*8-1:0]    weight_row_data, // 当前 kernel_row 的权重
    output reg  [4*2*2*18-1:0] out_row_sum_bus  // 当前 kernel_row 的 16 个 INT18 行和
);

    integer ch_idx;  // 通道索引，范围 0..3
    integer oy_idx;  // 输出行索引，范围 0..1
    integer ox_idx;  // 输出列索引，范围 0..1

    // ---------- 将输入数据做打拍下沉 ----------
    reg [4*2*4*8-1:0] row_window_data_reg;
    reg [4*3*8-1:0]   weight_row_data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {4*2*4*8{1'b0}};
            weight_row_data_reg <= {4*3*8{1'b0}};
        end else begin
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;
        end
    end

    // ---------- 用打拍后的寄存器参与乘加 ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_row_sum_bus <= {4*2*2*18{1'b0}};
        end else begin
            for (ch_idx = 0; ch_idx < 4; ch_idx = ch_idx + 1) begin
                for (oy_idx = 0; oy_idx < 2; oy_idx = oy_idx + 1) begin
                    for (ox_idx = 0; ox_idx < 2; ox_idx = ox_idx + 1) begin
                        // 地址计算公式
                        // 输出填充：先按通道索引，每个通道4个结果；再按行索引，每行2个结果，一共2行，再按列索引。
                        // 数据选择：当前输入数据行：oy_idx，对应数据：i + oy_idx
                        // 权重选择：第 ch_idx 个通道。
                        out_row_sum_bus[((ch_idx * 4 + oy_idx * 2 + ox_idx) * 18) +: 18] <=
                            ($signed(row_window_data_reg[(ch_idx * 8 + oy_idx * 4 + ox_idx + 0) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 24) + (0 * 8) +: 8])) +
                            ($signed(row_window_data_reg[(ch_idx * 8 + oy_idx * 4 + ox_idx + 1) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 24) + (1 * 8) +: 8])) +
                            ($signed(row_window_data_reg[(ch_idx * 8 + oy_idx * 4 + ox_idx + 2) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 24) + (2 * 8) +: 8]));
                    end
                end
            end
        end
    end

endmodule
