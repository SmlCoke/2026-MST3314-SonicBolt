`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-12
 * 版本: v4.4
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
 */
module conv_tile_mac_row_mult (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位
    input  wire [2*10*8-1:0]   row_window_data, // 当前 kernel_row 对应的 2 行 10 列输入条带
    input  wire [4*7*8-1:0]    weight_row_data, // 当前 kernel_row 对应的 4 通道权重
    output reg  [4*2*4*19-1:0] out_row_sum_bus  // 当前 kernel_row 的 32 个 INT19 部分和
);
    // 将输入数据和权重下沉打一拍，保持与外层 metadata/bias 的流水对齐。
    reg [2*10*8-1:0] row_window_data_reg;
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
                    localparam integer DATA_BASE  = (g_oy * 10 + g_ox) * 8;
                    localparam integer WT_BASE    = g_ch * 56;

                    // 7 个 INT8 的乘法结果
                    wire signed [15:0] product_0;
                    wire signed [15:0] product_1;
                    wire signed [15:0] product_2;
                    wire signed [15:0] product_3;
                    wire signed [15:0] product_4;
                    wire signed [15:0] product_5;
                    wire signed [15:0] product_6;

                    // 位扩展后的 7 个 INT 8 乘法结果
                    wire signed [18:0] product_0_ext;
                    wire signed [18:0] product_1_ext;
                    wire signed [18:0] product_2_ext;
                    wire signed [18:0] product_3_ext;
                    wire signed [18:0] product_4_ext;
                    wire signed [18:0] product_5_ext;
                    wire signed [18:0] product_6_ext;

                    // 部分和结果以及总结果
                    wire signed [18:0] sum_l1_0;
                    wire signed [18:0] sum_l1_1;
                    wire signed [18:0] sum_l1_2;
                    wire signed [18:0] sum_l2_0;
                    wire signed [18:0] sum_l2_1;
                    wire signed [18:0] row_sum_point;

                    // 例化 7 个子模块，每个子模块就是一个 INT8xINT8 的乘法器，输出 INT16 的乘积。
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

                    assign product_0_ext = {{3{product_0[15]}}, product_0}; // 将 INT16 的乘积拓展到 INT19，符号位扩展
                    assign product_1_ext = {{3{product_1[15]}}, product_1};
                    assign product_2_ext = {{3{product_2[15]}}, product_2};
                    assign product_3_ext = {{3{product_3[15]}}, product_3};
                    assign product_4_ext = {{3{product_4[15]}}, product_4};
                    assign product_5_ext = {{3{product_5[15]}}, product_5};
                    assign product_6_ext = {{3{product_6[15]}}, product_6};

                    assign sum_l1_0 = product_0_ext + product_1_ext;
                    assign sum_l1_1 = product_2_ext + product_3_ext;
                    assign sum_l1_2 = product_4_ext + product_5_ext;
                    assign sum_l2_0 = sum_l1_0 + sum_l1_1;
                    assign sum_l2_1 = sum_l1_2 + product_6_ext;
                    assign row_sum_point = sum_l2_0 + sum_l2_1;

                    assign row_sum_bus_comb[(OUT_IDX * 19) +: 19] = row_sum_point;
                end
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {2*10*8{1'b0}};
            weight_row_data_reg <= {4*7*8{1'b0}};
            out_row_sum_bus     <= {4*2*4*19{1'b0}};
        end else begin
            // stage 1 流水级：数据和权重下沉打拍，输出部分和总线
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;

            // stage 3 流水级：输出部分和总线
            out_row_sum_bus     <= row_sum_bus_comb;
        end
    end

endmodule
