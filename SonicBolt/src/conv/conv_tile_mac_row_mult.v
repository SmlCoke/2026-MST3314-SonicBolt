`timescale 1ns / 1ps
/*
 * 模块名称: conv_tile_mac_row_mult
 * 作者: SonicBolt 团队
 * 日期: 2026-04-10
 * 版本: v4.2
 *
 * 功能概述:
 *   计算某一条预切分 kernel_row 对应的 7 项行内卷积和。
 *   kernel 的一行需要与输入窗口中的 4 行输入条带做卷积。
 *
 * 计算分析:
 *   - 一共 4 个输出通道
 *   - 每个通道需要计算 4x4 个空间位置
 *   - 每个空间位置做 7 组 INT8 乘加
 *
 * 位宽说明:
 *   - row_window_data : 4(oy) x 10(col) x 8bit = 320bit
 *   - weight_row_data : 4(ch) x 7(kx) x 8bit = 224bit
 *   - out_row_sum_bus : 4(ch) x 4 x 4 x INT19 = 1216bit
 *
 * 设计说明:
 *   - 本级只处理 7 项乘法与行内加法树，不做跨 kernel_row 的累加。
 *   - 输入窗口已经在外部按 kernel_row 预切分，因此本模块不再接收整包 14x10 窗口。
 *   - 权重也已经在外部预切分为当前 kernel_row 的 224bit 行权重。
 * 
 * 版本定位:
 *   - v2.0 去掉了 in_val / wt_val / prod / sum 等中间变量，直接用一条表达式描述乘加树，
 *     让综合工具根据目标工艺自行推导乘法器和加法树结构。
 *   - v3.0 认为不需要在计算时对每个输入都拓展位宽，只需要保证 <= 左边的输出位宽就行。
 *   - v4.0 分析得出，7组INT8的乘累加配合得到的最大位宽为 INT19，因此将输出位宽从 INT32 缩减到 INT19
 *   - v4.1 在内部增加了数据/权重的下沉流水级，与外部 Stage1 的元数据/偏置打拍匹配
 *   - v4.2
 */
module conv_tile_mac_row_mult (
    input  wire                clk,             // 时钟
    input  wire                rst_n,           // 低有效复位
    input  wire [4*10*8-1:0]   row_window_data, // 当前 kernel_row 对应的 4 行输入条带
    input  wire [4*7*8-1:0]    weight_row_data, // 当前 kernel_row
    
    // 对应的 4 通道权重行
    output reg  [4*4*4*19-1:0] out_row_sum_bus  // 当前 kernel_row 的 64 个 INT19 行和
);

    integer ch_idx;  // 通道索引，范围 0..3
    integer oy_idx;  // 输出行索引，范围 0..3
    integer ox_idx;  // 输出列索引，范围 0..3

    // ---------- 将输入数据做打拍下沉 ----------
    reg [4*10*8-1:0] row_window_data_reg;
    reg [4*7*8-1:0]  weight_row_data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_window_data_reg <= {4*10*8{1'b0}};
            weight_row_data_reg <= {4*7*8{1'b0}};
        end else begin
            row_window_data_reg <= row_window_data;
            weight_row_data_reg <= weight_row_data;
        end
    end

    // ---------- 用打拍后的寄存器参与乘加 ----------
    reg signed [15:0] p_0, p_1, p_2, p_3, p_4, p_5, p_6;
    reg signed [16:0] s_l1_0, s_l1_1, s_l1_2;
    reg signed [17:0] s_l2_0, s_l2_1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_row_sum_bus <= {4*4*4*19{1'b0}};
        end else begin
            for (ch_idx = 0; ch_idx < 4; ch_idx = ch_idx + 1) begin
                for (oy_idx = 0; oy_idx < 4; oy_idx = oy_idx + 1) begin
                    for (ox_idx = 0; ox_idx < 4; ox_idx = ox_idx + 1) begin
                        // 1. 拆分乘法中间节点
                        p_0 = $signed(row_window_data_reg[(oy_idx * 10 + ox_idx + 0) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 56) + (0 * 8) +: 8]);
                        p_1 = $signed(row_window_data_reg[(oy_idx * 10 + ox_idx + 1) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 56) + (1 * 8) +: 8]);
                        p_2 = $signed(row_window_data_reg[(oy_idx * 10 + ox_idx + 2) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 56) + (2 * 8) +: 8]);
                        p_3 = $signed(row_window_data_reg[(oy_idx * 10 + ox_idx + 3) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 56) + (3 * 8) +: 8]);
                        p_4 = $signed(row_window_data_reg[(oy_idx * 10 + ox_idx + 4) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 56) + (4 * 8) +: 8]);
                        p_5 = $signed(row_window_data_reg[(oy_idx * 10 + ox_idx + 5) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 56) + (5 * 8) +: 8]);
                        p_6 = $signed(row_window_data_reg[(oy_idx * 10 + ox_idx + 6) * 8 +: 8]) * $signed(weight_row_data_reg[(ch_idx * 56) + (6 * 8) +: 8]);

                        // 2. 加法树 L1 节点
                        s_l1_0 = p_0 + p_1;
                        s_l1_1 = p_2 + p_3;
                        s_l1_2 = p_4 + p_5;

                        // 3. 加法树 L2 节点
                        s_l2_0 = s_l1_0 + s_l1_1;
                        s_l2_1 = s_l1_2 + p_6;

                        // 地址计算公式
                        // 输出填充：先按通道索引，每个通道16个结果；再按行索引，每行4个结果，一共4行，再按列索引。
                        // 4. 最终结合与非阻塞赋值推导触发器
                        out_row_sum_bus[((ch_idx * 16 + oy_idx * 4 + ox_idx) * 19) +: 19] <= s_l2_0 + s_l2_1;
                    end
                end
            end
        end
    end

endmodule


// `timescale 1ns / 1ps
// /*
//  * 模块名称: conv_tile_mac_row_mult
//  * 作者: SonicBolt 团队
//  * 日期: 2026-03-16
//  * 版本: v2.0
//  *
//  * 功能概述:
//  *   计算某一条预切分 kernel_row 对应的 7 项行内卷积和。
//  *   kernel 的一行需要与输入窗口中的 4 行输入条带做卷积。
//  *
//  * 计算分析:
//  *   - 一共 4 个输出通道
//  *   - 每个通道需要计算 4x4 个空间位置
//  *   - 每个空间位置做 7 组 INT8 乘加
//  *
//  * 位宽说明:
//  *   - row_window_data : 4(oy) x 10(col) x 8bit = 320bit
//  *   - weight_row_data : 4(ch) x 7(kx) x 8bit = 224bit
//  *   - out_row_sum_bus : 4(ch) x 4 x 4 x INT32 = 2048bit
//  *
//  * 设计说明:
//  *   - 本级只处理 7 项乘法与行内加法树，不做跨 kernel_row 的累加。
//  *   - 输入窗口已经在外部按 kernel_row 预切分，因此本模块不再接收整包 14x10 窗口。
//  *   - 权重也已经在外部预切分为当前 kernel_row 的 224bit 行权重。
//  *   - v2.0 去掉了 in_val / wt_val / prod / sum 等中间变量，直接用一条表达式描述乘加树，
//  *     让综合工具根据目标工艺自行推导乘法器和加法树结构。
//  *   - 这里仍然保留一个很小的符号扩展函数，用来避免 part-select 的 signed 位宽传播问题；
//  *     它不改变“单条表达式求和”的写法，只是保证 v2.0 与 v1.0 数值一致。
//  */
// module conv_tile_mac_row_mult (
//     input  wire                clk,             // 时钟
//     input  wire                rst_n,           // 低有效复位
//     input  wire [4*10*8-1:0]   row_window_data, // 当前 kernel_row 对应的 4 行输入条带
//     input  wire [4*7*8-1:0]    weight_row_data, // 当前 kernel_row
    
//     // 对应的 4 通道权重行
//     output reg  [4*4*4*32-1:0] out_row_sum_bus  // 当前 kernel_row 的 64 个 INT32 行和
// );

//     integer ch_idx;  // 通道索引，范围 0..3
//     integer oy_idx;  // 输出行索引，范围 0..3
//     integer ox_idx;  // 输出列索引，范围 0..3

//     // 将 INT8 显式符号扩展到 INT32，避免 part-select 直接参与有符号运算时的位宽歧义。
//     function automatic signed [31:0] sx8_to_s32;
//         input [7:0] data_in;
//         begin
//             sx8_to_s32 = {{24{data_in[7]}}, data_in};
//         end
//     endfunction

//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             out_row_sum_bus <= {4*4*4*32{1'b0}};
//         end else begin
//             for (ch_idx = 0; ch_idx < 4; ch_idx = ch_idx + 1) begin
//                 for (oy_idx = 0; oy_idx < 4; oy_idx = oy_idx + 1) begin
//                     for (ox_idx = 0; ox_idx < 4; ox_idx = ox_idx + 1) begin
//                         // 地址计算公式
//                         // 输出填充：先按通道索引，每个通道16个结果；再按行索引，每行4个结果，一共4行，再按列索引。
//                         // 数据选择：当前输入数据行：oy_idx，对应数据：i + oy_idx
//                         // 权重选择：第 ch_idx 个通道。
//                         out_row_sum_bus[((ch_idx * 16 + oy_idx * 4 + ox_idx) * 32) +: 32] <=
//                             (sx8_to_s32(row_window_data[(oy_idx * 10 + (ox_idx + 0)) * 8 +: 8]) *
//                              sx8_to_s32(weight_row_data[(ch_idx * 56) + (0 * 8) +: 8])) +
//                             (sx8_to_s32(row_window_data[(oy_idx * 10 + (ox_idx + 1)) * 8 +: 8]) *
//                              sx8_to_s32(weight_row_data[(ch_idx * 56) + (1 * 8) +: 8])) +
//                             (sx8_to_s32(row_window_data[(oy_idx * 10 + (ox_idx + 2)) * 8 +: 8]) *
//                              sx8_to_s32(weight_row_data[(ch_idx * 56) + (2 * 8) +: 8])) +
//                             (sx8_to_s32(row_window_data[(oy_idx * 10 + (ox_idx + 3)) * 8 +: 8]) *
//                              sx8_to_s32(weight_row_data[(ch_idx * 56) + (3 * 8) +: 8])) +
//                             (sx8_to_s32(row_window_data[(oy_idx * 10 + (ox_idx + 4)) * 8 +: 8]) *
//                              sx8_to_s32(weight_row_data[(ch_idx * 56) + (4 * 8) +: 8])) +
//                             (sx8_to_s32(row_window_data[(oy_idx * 10 + (ox_idx + 5)) * 8 +: 8]) *
//                              sx8_to_s32(weight_row_data[(ch_idx * 56) + (5 * 8) +: 8])) +
//                             (sx8_to_s32(row_window_data[(oy_idx * 10 + (ox_idx + 6)) * 8 +: 8]) *
//                              sx8_to_s32(weight_row_data[(ch_idx * 56) + (6 * 8) +: 8]));
//                     end
//                 end
//             end
//         end
//     end

// endmodule

// -----------------------------------------------------------------------------
// v1.0 参考源码保留区
// -----------------------------------------------------------------------------
// `timescale 1ns / 1ps
// /*
//  * 模块名称: conv_tile_mac_row_mult
//  * 作者: SonicBolt 团队
//  * 日期: 2026-03-15
//  * 版本: v1.0
//  *
//  * 功能概述:
//  *   计算某一条预切分 kernel_row 对应的 7 项行内卷积和。
//  *
//  * 位宽说明:
//  *   - row_window_data : 4(oy) x 10(col) x 8bit = 320bit
//  *   - weight_row_data : 4(ch) x 7(kx) x 8bit = 224bit
//  *   - out_row_sum_bus : 4(ch) x 4 x 4 x INT32 = 2048bit
//  *
//  * 设计说明:
//  *   - 本级只处理 7 项乘法与平衡加法树，不做跨 kernel_row 的累加。
//  *   - 输入窗口已经在外部按 kernel_row 预切分，因此本模块不再接收整包 14x10 窗口。
//  *   - 权重也已经在外部预切分为当前 kernel_row 的 224bit 行权重。
//  */
// module conv_tile_mac_row_mult (
//     input  wire                clk,             // 时钟
//     input  wire                rst_n,           // 低有效复位
//     input  wire [4*10*8-1:0]   row_window_data, // 当前 kernel_row 对应的 4 行输入条带
//     input  wire [4*7*8-1:0]    weight_row_data, // 当前 kernel_row 对应的 4 通道权重行
//     output reg  [4*4*4*32-1:0] out_row_sum_bus  // 当前 kernel_row 的 64 个 INT32 行和
// );
//
//     integer ch_idx;
//     integer oy_idx;
//     integer ox_idx;
//     integer out_idx;
//     reg signed [7:0] in_val_0;
//     reg signed [7:0] in_val_1;
//     reg signed [7:0] in_val_2;
//     reg signed [7:0] in_val_3;
//     reg signed [7:0] in_val_4;
//     reg signed [7:0] in_val_5;
//     reg signed [7:0] in_val_6;
//     reg signed [7:0] wt_val_0;
//     reg signed [7:0] wt_val_1;
//     reg signed [7:0] wt_val_2;
//     reg signed [7:0] wt_val_3;
//     reg signed [7:0] wt_val_4;
//     reg signed [7:0] wt_val_5;
//     reg signed [7:0] wt_val_6;
//     reg signed [15:0] prod_0;
//     reg signed [15:0] prod_1;
//     reg signed [15:0] prod_2;
//     reg signed [15:0] prod_3;
//     reg signed [15:0] prod_4;
//     reg signed [15:0] prod_5;
//     reg signed [15:0] prod_6;
//     reg signed [16:0] sum_l1_0;
//     reg signed [16:0] sum_l1_1;
//     reg signed [16:0] sum_l1_2;
//     reg signed [17:0] sum_l2_0;
//     reg signed [17:0] sum_l2_1;
//     reg signed [18:0] row_sum;
//
//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             out_row_sum_bus <= {4*4*4*32{1'b0}};
//         end else begin
//             for (ch_idx = 0; ch_idx < 4; ch_idx = ch_idx + 1) begin
//                 for (oy_idx = 0; oy_idx < 4; oy_idx = oy_idx + 1) begin
//                     for (ox_idx = 0; ox_idx < 4; ox_idx = ox_idx + 1) begin
//                         in_val_0 = row_window_data[(oy_idx * 10 + (ox_idx + 0)) * 8 +: 8];
//                         in_val_1 = row_window_data[(oy_idx * 10 + (ox_idx + 1)) * 8 +: 8];
//                         in_val_2 = row_window_data[(oy_idx * 10 + (ox_idx + 2)) * 8 +: 8];
//                         in_val_3 = row_window_data[(oy_idx * 10 + (ox_idx + 3)) * 8 +: 8];
//                         in_val_4 = row_window_data[(oy_idx * 10 + (ox_idx + 4)) * 8 +: 8];
//                         in_val_5 = row_window_data[(oy_idx * 10 + (ox_idx + 5)) * 8 +: 8];
//                         in_val_6 = row_window_data[(oy_idx * 10 + (ox_idx + 6)) * 8 +: 8];
//
//                         wt_val_0 = weight_row_data[(ch_idx * 56) + (0 * 8) +: 8];
//                         wt_val_1 = weight_row_data[(ch_idx * 56) + (1 * 8) +: 8];
//                         wt_val_2 = weight_row_data[(ch_idx * 56) + (2 * 8) +: 8];
//                         wt_val_3 = weight_row_data[(ch_idx * 56) + (3 * 8) +: 8];
//                         wt_val_4 = weight_row_data[(ch_idx * 56) + (4 * 8) +: 8];
//                         wt_val_5 = weight_row_data[(ch_idx * 56) + (5 * 8) +: 8];
//                         wt_val_6 = weight_row_data[(ch_idx * 56) + (6 * 8) +: 8];
//
//                         prod_0 = in_val_0 * wt_val_0;
//                         prod_1 = in_val_1 * wt_val_1;
//                         prod_2 = in_val_2 * wt_val_2;
//                         prod_3 = in_val_3 * wt_val_3;
//                         prod_4 = in_val_4 * wt_val_4;
//                         prod_5 = in_val_5 * wt_val_5;
//                         prod_6 = in_val_6 * wt_val_6;
//
//                         sum_l1_0 = prod_0 + prod_1;
//                         sum_l1_1 = prod_2 + prod_3;
//                         sum_l1_2 = prod_4 + prod_5;
//
//                         sum_l2_0 = sum_l1_0 + sum_l1_1;
//                         sum_l2_1 = sum_l1_2 + prod_6;
//                         row_sum  = sum_l2_0 + sum_l2_1;
//
//                         out_idx = ch_idx * 16 + oy_idx * 4 + ox_idx;
//                         out_row_sum_bus[out_idx*32 +: 32] <= $signed(row_sum);
//                     end
//                 end
//             end
//         end
//     end
//
// endmodule
