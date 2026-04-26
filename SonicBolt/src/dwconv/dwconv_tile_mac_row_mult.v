`timescale 1ns / 1ps
/*
 * 模块名称: dwconv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-26
 * 版本: v1.2
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
 *   - weight_row_data: 4(ch) x 1(row) x 3(col) x 8(width)
 *   - out_row_sum_bus: 4(ch) x 2(row) x 2(col) x 18(width)
 *
 * 设计说明:
 *   - 本级只处理 3 项乘法与行内加法树，不做跨 kernel_row 的累加。
 *   - 权重也已经在外部预切分为当前 kernel_row 的 96bit 行权重。
 *
 * 运算复杂度分析:
 *   - 4ch x 2oy x 2ox = 16 个并行计算单元
 *   - 每个并行计算单元包含 3 个 INT8 乘法器 级联 两级加法树: 3 x INT16 to 1 x INT18
 *   - 逻辑深度为: 1M (Stage2) + 2A (Stage3)，分拆为两级
 *   - 总共 16 x 3 = 48 个 INT8 乘法器
 *
 * 版本定位:
 *  - v1.0 初始版本，完成基本功能。
 *  - v1.1 为了降低综合复杂度，计算被拆成小单元 dwconv_tile_mac_dot3_cell 并用 generate 展开。
 *  - v1.2 原 1M+2A 在单周期完成，存在组合深度违规。将乘法与加法树拆为两级流水：
 *         Stage2: 乘法(comb) → product 寄存器
 *         Stage3: L1+L2 加法树(comb) → 输出寄存器
 *         内部延迟从 2 拍增至 3 拍(+1)。
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

    // ---------- stage1: 将输入数据做打拍下沉 ----------
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

    // ---------- stage2: 乘法(comb) + product 寄存器 ----------
    // ---------- stage3: 加法树(comb) + 输出寄存器 ----------
    wire signed [17:0] row_sum_wire [0:3][0:1][0:1];

    genvar g_ch;
    genvar g_oy;
    genvar g_ox;

    generate
        for (g_ch = 0; g_ch < 4; g_ch = g_ch + 1) begin : CH_LOOP
            for (g_oy = 0; g_oy < 2; g_oy = g_oy + 1) begin : OY_LOOP
                for (g_ox = 0; g_ox < 2; g_ox = g_ox + 1) begin : OX_LOOP
                    // v1.2: Stage2 —— 乘法节点(组合)，输出到 product 寄存器
                    wire signed [15:0] p_0_comb = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 0) * 8 +: 8]) * $signed(weight_row_data_reg[(g_ch * 24) + (0 * 8) +: 8]);
                    wire signed [15:0] p_1_comb = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 1) * 8 +: 8]) * $signed(weight_row_data_reg[(g_ch * 24) + (1 * 8) +: 8]);
                    wire signed [15:0] p_2_comb = $signed(row_window_data_reg[(g_ch * 8 + g_oy * 4 + g_ox + 2) * 8 +: 8]) * $signed(weight_row_data_reg[(g_ch * 24) + (2 * 8) +: 8]);

                    // v1.2: product 寄存器 —— 乘法结果打一拍
                    reg signed [15:0] p_0, p_1, p_2;
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin
                            p_0 <= 16'sd0;
                            p_1 <= 16'sd0;
                            p_2 <= 16'sd0;
                        end else begin
                            p_0 <= p_0_comb;
                            p_1 <= p_1_comb;
                            p_2 <= p_2_comb;
                        end
                    end

                    // v1.2: Stage3 —— 加法树级联(组合)，从已寄存的 product 计算
                    wire signed [16:0] s_l1_0 = p_0 + p_1;

                    // 结果连线
                    assign row_sum_wire[g_ch][g_oy][g_ox] = s_l1_0 + p_2;
                end
            end
        end
    endgenerate

    // ---------- stage3: 将加法树结果打一拍输出 ----------
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
