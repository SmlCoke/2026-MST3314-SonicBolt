`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-11
 * 版本: v4.2
 *
 * 功能概述:
 *   计算某一条预切分 kernel_row 对应的 7 项行内卷积和。
 *   kernel 的一行需要与输入窗口中的 4 行条带做卷积。
 *
 * 计算分析:
 *   - 一共 4 个输出通道
 *   - 每个通道需要计算 4x4 个空间位置
 *   - 每个空间位置做 7 组 INT8 乘加
 *
 * 位宽说明:
 *   - row_window_data : 4(oy) x 10(col) x 8bit = 320bit
 *   - weight_row_data : 4(ch) x 7(kx) x 8bit  = 224bit
 *   - out_row_sum_bus : 4(ch) x 4 x 4 x INT19 = 1216bit
 *
 * 版本定位:
 *   - v2.0 去掉了 in_val / wt_val / prod / sum 等中间变量，直接用一条表达式描述乘加树，
 *     让综合工具根据目标工艺自行推导乘法器和加法树结构。
 *   - v3.0 认为不需要在计算时对每个输入都拓展位宽，只需要保证 <= 左边的输出位宽就行。
 *   - v4.0 分析得出，7组INT8的乘累加配合得到的最大位宽为 INT19，因此将输出位宽从 INT32 缩减到 INT19
 *   - v4.1 在内部增加了数据/权重的下沉流水级，与外部 Stage1 的元数据/偏置打拍匹配
 *   - v4.2 为了降低综合复杂度，计算被拆成小单元 conv_tile_mac_dot7_cell 并用 generate 展开。
 */
module conv_tile_mac_row_mult (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位
    input  wire [4*10*8-1:0]   row_window_data, // 当前 kernel_row 对应的 4 行输入条带
    input  wire [4*7*8-1:0]    weight_row_data, // 当前 kernel_row

    // 对应的 4 通道权重行
    output reg  [4*4*4*19-1:0] out_row_sum_bus  // 当前 kernel_row 的 64 个 INT19 行和
);
    // ---------- 将输入数据做打拍下沉 ----------
    reg [4*10*8-1:0] row_window_data_reg;
    reg [4*7*8-1:0]  weight_row_data_reg;

    // 展开后的 row_sum，总线索引规则保持不变:
    // ((ch_idx * 16 + oy_idx * 4 + ox_idx) * 19) +: 19
    wire [4*4*4*19-1:0] row_sum_bus_comb;

    genvar g_ch;
    genvar g_oy;
    genvar g_ox;
    generate
        for (g_ch = 0; g_ch < 4; g_ch = g_ch + 1) begin : G_CH
            for (g_oy = 0; g_oy < 4; g_oy = g_oy + 1) begin : G_OY
                for (g_ox = 0; g_ox < 4; g_ox = g_ox + 1) begin : G_OX
                    localparam integer OUT_IDX   = g_ch * 16 + g_oy * 4 + g_ox;
                    localparam integer DATA_BASE = (g_oy * 10 + g_ox) * 8;
                    localparam integer WT_BASE   = g_ch * 56;

                    wire signed [18:0] row_sum_point;
                    conv_tile_mac_dot7_cell u_dot7_cell (
                        .data_0(row_window_data_reg[(DATA_BASE + 0*8) +: 8]),
                        .data_1(row_window_data_reg[(DATA_BASE + 1*8) +: 8]),
                        .data_2(row_window_data_reg[(DATA_BASE + 2*8) +: 8]),
                        .data_3(row_window_data_reg[(DATA_BASE + 3*8) +: 8]),
                        .data_4(row_window_data_reg[(DATA_BASE + 4*8) +: 8]),
                        .data_5(row_window_data_reg[(DATA_BASE + 5*8) +: 8]),
                        .data_6(row_window_data_reg[(DATA_BASE + 6*8) +: 8]),
                        .wt_0(weight_row_data_reg[(WT_BASE + 0*8) +: 8]),
                        .wt_1(weight_row_data_reg[(WT_BASE + 1*8) +: 8]),
                        .wt_2(weight_row_data_reg[(WT_BASE + 2*8) +: 8]),
                        .wt_3(weight_row_data_reg[(WT_BASE + 3*8) +: 8]),
                        .wt_4(weight_row_data_reg[(WT_BASE + 4*8) +: 8]),
                        .wt_5(weight_row_data_reg[(WT_BASE + 5*8) +: 8]),
                        .wt_6(weight_row_data_reg[(WT_BASE + 6*8) +: 8]),
                        .out_sum(row_sum_point)
                    );

                    assign row_sum_bus_comb[(OUT_IDX * 19) +: 19] = row_sum_point;
                end
            end
        end
    endgenerate

    // ---------- 输入数据打拍下沉 ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {4*10*8{1'b0}};
            weight_row_data_reg <= {4*7*8{1'b0}};
            out_row_sum_bus     <= {4*4*4*19{1'b0}};
        end else begin
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;
            out_row_sum_bus     <= row_sum_bus_comb;
        end
    end

endmodule
