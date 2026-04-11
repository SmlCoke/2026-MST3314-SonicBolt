`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-11
 * 版本: v4.3
 *
 * 功能概述:
 *   计算某一条 kernel_row 对应的 7 项行内卷积和。
 *   当前版本只保留 2x4 半窗输出，因此每个 kernel_row 只需要覆盖 2 个输出行。
 *
 * 位宽说明:
 *   - row_window_data : 4(输入行载体) x 10(col) x 8bit = 320bit
 *   - weight_row_data : 4(ch) x 7(kx) x 8bit = 224bit
 *   - out_row_sum_bus : 4(ch) x 2(oy) x 4(ox) x INT19 = 608bit
 *
 * 设计说明:
 *   - 物理上仍然保留 4 行输入载体，方便与现有 14x10 工作集接口兼容。
 *   - 逻辑上只使用前 2 个输出行，对应半窗 2x4 结果，乘法器数量减半。
 */
module conv_tile_mac_row_mult (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位
    input  wire [4*10*8-1:0]   row_window_data, // 当前 kernel_row 对应的输入条带
    input  wire [4*7*8-1:0]    weight_row_data, // 当前 kernel_row 对应的 4 通道权重
    output reg  [4*2*4*19-1:0] out_row_sum_bus  // 当前 kernel_row 的 32 个 INT19 部分和
);
    // 将输入数据和权重下沉打一拍，保持与外层 metadata/bias 的流水对齐。
    reg [4*10*8-1:0] row_window_data_reg;
    reg [4*7*8-1:0]  weight_row_data_reg;

    // 展平后的 row_sum，总线索引规则:
    // ((ch_idx * 8 + oy_idx * 4 + ox_idx) * 19) +: 19
    wire [4*2*4*19-1:0] row_sum_bus_comb;

    genvar g_ch;
    genvar g_oy;
    genvar g_ox;
    generate
        for (g_ch = 0; g_ch < 4; g_ch = g_ch + 1) begin : G_CH
            for (g_oy = 0; g_oy < 2; g_oy = g_oy + 1) begin : G_OY
                for (g_ox = 0; g_ox < 4; g_ox = g_ox + 1) begin : G_OX
                    localparam integer OUT_IDX   = g_ch * 8 + g_oy * 4 + g_ox;
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {4*10*8{1'b0}};
            weight_row_data_reg <= {4*7*8{1'b0}};
            out_row_sum_bus     <= {4*2*4*19{1'b0}};
        end else begin
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;
            out_row_sum_bus     <= row_sum_bus_comb;
        end
    end

endmodule
