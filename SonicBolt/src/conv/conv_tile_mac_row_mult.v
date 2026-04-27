`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-26
 * 版本: v4.5
 *
 * 功能概述:
 *   计算某一条 kernel_row 对应的 7 项行内卷积和。
 *   当前版本只保留 2x4 半窗输出，因此每个 kernel_row 只需要覆盖 2 个输出行。
 *
 * 位宽说明:
 *   - row_window_data : 2(输入行载体) x 10(col) x 8bit = 160bit
 *   - weight_row_data : 4(ch) x 7(kx) x 8bit = 224bit
 *   - out_row_sum_bus : 4(ch) x 2(oy) x 4(ox) x INT19 = 608bit
 *
 * 设计说明:
 *   - 这里直接输入 2 行 10 列载体，与半窗 2x4 的逻辑需求完全一致。
 *
 * 运算复杂度分析:
 *   - 4ch x 2oy x 4ox = 32 个并行计算单元
 *   - 每个并行计算单元包含 7 个 INT8 乘法器 级联 三级加法树: 7 x INT16 to 1 x INT19
 *   - 加法树结构 (非对称):
 *        prod_0 ─┐
 *                ├─ L1_0 ─┐
 *        prod_1 ─┘        │
 *                         ├─ L2_0 ─┐
 *        prod_2 ─┐        │        │
 *                ├─ L1_1 ─┘        │
 *        prod_3 ─┘                 │
 *                                  ├─ row_sum (L3)
 *        prod_4 ─┐                 │
 *                ├─ L1_2 ─┐        │
 *        prod_5 ─┘        │        │
 *                         ├─ L2_1 ─┘
 *        prod_6 ──────────┘
 *   - 逻辑深度为: 1M + 3A
 *   - 总共 32 x 7 = 224 个 INT8 乘法器
 *
 * 版本定位:
 *   - v2.0 去掉了 in_val / wt_val / prod / sum 等中间变量，直接用一条表达式描述乘加树，
 *     让综合工具根据目标工艺自行推导乘法器和加法树结构。
 *   - v3.0 认为不需要在计算时对每个输入都拓展位宽，只需要保证 <= 左边的输出位宽就行。
 *   - v4.0 分析得出，7组INT8的乘累加配合得到的最大位宽为 INT19，因此将输出位宽从 INT32 缩减到 INT19
 *   - v4.1 在内部增加了数据/权重的下沉流水级，与外部 Stage1 的元数据/偏置打拍匹配
 *   - v4.2 为了降低综合复杂度，计算被拆成小单元 conv_tile_mac_dot7_cell 并用 generate 展开。
 *   - v4.3 实现半窗缓存逻辑，将乘法器数量减半，同时将输入数据从 4 行 10 列缩减到 2 行 10 列，输出从 4x4 个位
 *     置缩减到 2x4 个位置。
 *   - v4.4 将 dot7 再拆成 mult_cell，每个单元只做 1 组 INT8xINT8 乘法，
 *     再由 dot1 外层完成 7 项加法归约。
 *   - v4.5 将乘加路径拆分为四级流水：Stage0(输入打拍)→Stage1(乘法打拍)→Stage2(L1加法+prod6打拍)→
 *     Stage3(输出打拍)。每个周期只做一级乘法或一级加法，将逻辑深度从 1M+3A 降至每周期最多 1M 或 2A。
 *     特别注意：prod_6 在加法树中走捷径(直连L2_1=L3级)，因此需要额外的 product_6_s2 寄存器保持
 *     与 L1 加法结果相同的流水深度，确保所有 7 条路径的寄存器级数严格一致。
 */
module conv_tile_mac_row_mult (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位
    input  wire [2*10*8-1:0]   row_window_data, // 当前 kernel_row 对应的 2 行 10 列输入条带
    input  wire [4*7*8-1:0]    weight_row_data, // 当前 kernel_row 对应的 4 通道权重
    output reg  [4*2*4*19-1:0] out_row_sum_bus  // 当前 kernel_row 的 32 个 INT19 部分和
);
    // Stage 0 流水寄存器：将输入数据和权重下沉打一拍。
    reg [2*10*8-1:0] row_window_data_reg;
    reg [4*7*8-1:0]  weight_row_data_reg;

    // 展平后的 row_sum 组合总线，索引规则:
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
                    localparam integer DATA_BASE  = (g_oy * 10 + g_ox) * 8;
                    localparam integer WT_BASE    = g_ch * 56;

                    // 7 个 INT8 乘法器的组合输出（从 Stage 0 寄存器驱动）
                    wire signed [15:0] product_0;
                    wire signed [15:0] product_1;
                    wire signed [15:0] product_2;
                    wire signed [15:0] product_3;
                    wire signed [15:0] product_4;
                    wire signed [15:0] product_5;
                    wire signed [15:0] product_6;

                    // v4.5: Stage 1 流水寄存器 —— 7 个乘法结果打拍
                    reg signed [15:0] product_0_s1;
                    reg signed [15:0] product_1_s1;
                    reg signed [15:0] product_2_s1;
                    reg signed [15:0] product_3_s1;
                    reg signed [15:0] product_4_s1;
                    reg signed [15:0] product_5_s1;
                    reg signed [15:0] product_6_s1;

                    // 位扩展：从 Stage 1 寄存器驱动（组合逻辑）
                    wire signed [18:0] product_0_ext;
                    wire signed [18:0] product_1_ext;
                    wire signed [18:0] product_2_ext;
                    wire signed [18:0] product_3_ext;
                    wire signed [18:0] product_4_ext;
                    wire signed [18:0] product_5_ext;
                    wire signed [18:0] product_6_ext;

                    // v4.5: Stage 2 流水寄存器 —— L1 加法结果 + prod_6 额外打拍
                    // prod_6 在加法树中走捷径（直连 L2_1，即 L3 级），必须单独打一拍
                    // 以保证与 L1 加法结果处于同一流水深度
                    reg signed [18:0] sum_l1_0_s2;
                    reg signed [18:0] sum_l1_1_s2;
                    reg signed [18:0] sum_l1_2_s2;
                    reg signed [18:0] product_6_s2;  // prod_6 的额外流水级，匹配 L1 深度

                    // 第二、三级加法树（组合逻辑，从 Stage 2 寄存器驱动）
                    wire signed [18:0] sum_l2_0;
                    wire signed [18:0] sum_l2_1;
                    wire signed [18:0] row_sum_point;

                    // 例化 7 个 INT8xINT8 乘法器
                    mult_cell u_mult_cell_0 (
                        .data(row_window_data_reg[(DATA_BASE + 0*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 0*8) +: 8]),
                        .out_prod(product_0)
                    );
                    mult_cell u_mult_cell_1 (
                        .data(row_window_data_reg[(DATA_BASE + 1*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 1*8) +: 8]),
                        .out_prod(product_1)
                    );
                    mult_cell u_mult_cell_2 (
                        .data(row_window_data_reg[(DATA_BASE + 2*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 2*8) +: 8]),
                        .out_prod(product_2)
                    );
                    mult_cell u_mult_cell_3 (
                        .data(row_window_data_reg[(DATA_BASE + 3*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 3*8) +: 8]),
                        .out_prod(product_3)
                    );
                    mult_cell u_mult_cell_4 (
                        .data(row_window_data_reg[(DATA_BASE + 4*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 4*8) +: 8]),
                        .out_prod(product_4)
                    );
                    mult_cell u_mult_cell_5 (
                        .data(row_window_data_reg[(DATA_BASE + 5*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 5*8) +: 8]),
                        .out_prod(product_5)
                    );
                    mult_cell u_mult_cell_6 (
                        .data(row_window_data_reg[(DATA_BASE + 6*8) +: 8]),
                        .wt(weight_row_data_reg[(WT_BASE + 6*8) +: 8]),
                        .out_prod(product_6)
                    );

                    // 位扩展：INT16 → INT19（从 Stage 1 寄存器驱动）
                    assign product_0_ext = {{3{product_0_s1[15]}}, product_0_s1};
                    assign product_1_ext = {{3{product_1_s1[15]}}, product_1_s1};
                    assign product_2_ext = {{3{product_2_s1[15]}}, product_2_s1};
                    assign product_3_ext = {{3{product_3_s1[15]}}, product_3_s1};
                    assign product_4_ext = {{3{product_4_s1[15]}}, product_4_s1};
                    assign product_5_ext = {{3{product_5_s1[15]}}, product_5_s1};
                    // product_6_ext 从 product_6_s2 (Stage 2) 驱动，与 L1 加法结果同深度
                    assign product_6_ext = product_6_s2;

                    // L2 + L3 加法树（组合逻辑，从 Stage 2 寄存器驱动）
                    assign sum_l2_0 = sum_l1_0_s2 + sum_l1_1_s2;
                    assign sum_l2_1 = sum_l1_2_s2 + product_6_ext;
                    assign row_sum_point = sum_l2_0 + sum_l2_1;

                    assign row_sum_bus_comb[(OUT_IDX * 19) +: 19] = row_sum_point;

                    // ---------- 每个计算单元的 Stage 1 和 Stage 2 流水寄存器 ----------
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin
                            // Stage 1: 乘法结果复位
                            product_0_s1 <= 16'sd0;
                            product_1_s1 <= 16'sd0;
                            product_2_s1 <= 16'sd0;
                            product_3_s1 <= 16'sd0;
                            product_4_s1 <= 16'sd0;
                            product_5_s1 <= 16'sd0;
                            product_6_s1 <= 16'sd0;

                            // Stage 2: L1 加法结果 + prod_6 额外打拍复位
                            sum_l1_0_s2  <= 19'sd0;
                            sum_l1_1_s2  <= 19'sd0;
                            sum_l1_2_s2  <= 19'sd0;
                            product_6_s2 <= 19'sd0;
                        end else begin
                            // -------- Stage 1: 乘法结果打拍 --------
                            product_0_s1 <= product_0;
                            product_1_s1 <= product_1;
                            product_2_s1 <= product_2;
                            product_3_s1 <= product_3;
                            product_4_s1 <= product_4;
                            product_5_s1 <= product_5;
                            product_6_s1 <= product_6;

                            // -------- Stage 2: L1 加法打拍 + prod_6 对齐打拍 --------
                            // product_*_ext 由 product_*_s1 (OLD) 组合驱动；
                            // 在同一时钟沿非阻塞采样，捕获上一周期已稳定的 product_*_s1 的 L1 和。
                            sum_l1_0_s2 <= product_0_ext + product_1_ext;
                            sum_l1_1_s2 <= product_2_ext + product_3_ext;
                            sum_l1_2_s2 <= product_4_ext + product_5_ext;
                            // product_6 在加法树中走捷径，跳过 L1 加法直接进入 L2_1 (L3 级)。
                            // 为匹配 sum_l1_*_s2 的流水深度，这里对 product_6_s1 位扩展后额外打一拍。
                            product_6_s2 <= {{3{product_6_s1[15]}}, product_6_s1};
                        end
                    end
                end
            end
        end
    endgenerate

    // ---------- Stage 0 输入寄存器 & Stage 3 输出寄存器 ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {2*10*8{1'b0}};
            weight_row_data_reg <= {4*7*8{1'b0}};
            out_row_sum_bus     <= {4*2*4*19{1'b0}};
        end else begin
            // Stage 0: 输入数据与权重打拍
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;

            // Stage 3: L2 + L3 加法树结果打拍输出
            // row_sum_bus_comb 由 sum_l1_*_s2 / product_6_s2 经组合逻辑计算得出
            out_row_sum_bus     <= row_sum_bus_comb;
        end
    end

endmodule
