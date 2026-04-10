`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-10
 * 版本: v1.1
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
 *  
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

    // ---------- 用打拍后的寄存器参与乘加（纯结构化展开） ----------
    wire signed [17:0] row_sum_wire [0:3][0:1][0:1];

    genvar g_ch;
    genvar g_oy;
    genvar g_ox;

    generate
        for (g_ch = 0; g_ch < 4; g_ch = g_ch + 1) begin : CH_LOOP
            for (g_oy = 0; g_oy < 2; g_oy = g_oy + 1) begin : OY_LOOP
                for (g_ox = 0; g_ox < 2; g_ox = g_ox + 1) begin : OX_LOOP
                    // 乘法节点
                    wire signed [15:0] p_0 = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 0) * 8 +: 8]) * 
                                             $signed(weight_row_data_reg[(g_ch * 24) + (0 * 8) +: 8]);
                    wire signed [15:0] p_1 = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 1) * 8 +: 8]) * 
                                             $signed(weight_row_data_reg[(g_ch * 24) + (1 * 8) +: 8]);
                    wire signed [15:0] p_2 = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 2) * 8 +: 8]) * 
                                             $signed(weight_row_data_reg[(g_ch * 24) + (2 * 8) +: 8]);

                    // 加法树级联
                    wire signed [16:0] s_l1_0 = p_0 + p_1;
                    
                    // 结果连线
                    assign row_sum_wire[g_ch][g_oy][g_ox] = s_l1_0 + p_2;
                end
            end
        end
    endgenerate

    // ---------- 将组合逻辑结果打一拍输出 ----------
    integer seq_ch, seq_oy, seq_ox;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_row_sum_bus <= {4*2*2*18{1'b0}};
        end else begin
            for (seq_ch = 0; seq_ch < 4; seq_ch = seq_ch + 1) begin
                for (seq_oy = 0; seq_oy < 2; seq_oy = seq_oy + 1) begin
                    for (seq_ox = 0; seq_ox < 2; seq_ox = seq_ox + 1) begin
                        out_row_sum_bus[((seq_ch * 4 + seq_oy * 2 + seq_ox) * 18) +: 18] <= row_sum_wire[seq_ch][seq_oy][seq_ox];
                    end
                end
            end
        end
    end

endmodule
