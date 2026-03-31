`timescale 1ns / 1ps
/*
 * 模块名称：pwconv_tile_mac
 * 作者：SonicBolt 团队
 * 日期：2026-03-29
 * 版本：v1.4
 *
 * 版本说明：
 *   - v1.2：stage2 改为 4 项乘积的两级平衡加法树；stage3 增加一拍寄存，切断长加法链
 *   - v1.3：stage3_reduce_bus 收窄到 19bit，stage4_sum_l* 位宽也相应收紧，去掉冗余位宽
 *   - v1.4：去掉 partial_value_*、stage3_pair_*、reduce_value_* 这三组过程临时变量，
 *           直接从总线切片完成 stage3 / stage4 计算，流水结构与吞吐保持不变
 *
 * 功能概述：
 *   对一个 {pos, out_group} 输出 token 完成整块 PWConv MAC 计算
 *
 * 输入数据含义：
 *   - tile_data_bus  ：一个完整 pos 对应的 32ch x 2 x 2 INT8 输入 tile
 *   - weight_data_bus：当前 out_group 所需的全部权重，共 8 个输入 bank，每个 bank 对应 4(out) x 4(in) 个 INT8 权重
 *   - bias_data_bus  ：当前 out_group 对应的 4 个 INT16 bias
 *
 * 输出数据含义：
 *   - out_accum_bus  ：4(out) x 2(row) x 2(col) 的 16 个 INT32 累加结果
 *
 * 流水级划分：
 *   1. stage1：锁存当前 token 计算所需的 tile / weight / bias
 *   2. stage2：每个输入 bank 独立完成 4 项点积，采用两级平衡加法树生成局部部分和
 *   3. stage3：把 8 个 bank 的部分和先做两两配对相加，并寄存一拍以缩短关键路径
 *   4. stage4：完成最终归约并叠加 bias，得到 16 个 INT32 输出
 *
 * 设计说明：
 *   - 该实现保持 1 token / cycle 的稳态吞吐不变，只是在 stage3 / stage4 之间增加了一拍寄存
 *   - 这里的 for 循环是 RTL 描述方式，综合后会展开为并行硬件，
 */
module pwconv_tile_mac (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               in_valid,
    input  wire               in_last,
    input  wire [3:0]         in_pos,
    input  wire [2:0]         in_group,

    input  wire [1023:0]      tile_data_bus,
    input  wire [8*128-1:0]   weight_data_bus,
    input  wire [63:0]        bias_data_bus,

    output wire               out_valid,
    output wire               out_last,
    output wire [3:0]         out_pos,
    output wire [2:0]         out_group,
    output reg  [16*32-1:0]   out_accum_bus
);

    // -------------------------
    // stage1：输入数据与参数寄存
    // -------------------------
    reg [1023:0]    stage1_tile_data;    // 当前 token 对应的完整输入 tile
    reg [8*128-1:0] stage1_weight_data;  // 当前 token 对应的完整权重切片，包含 8 个 bank
    reg [63:0]      stage1_bias_data;    // 当前 out_group 对应的 4 个 INT16 bias

    // -------------------------
    // stage2：局部部分和总线
    // -------------------------
    // stage2_partial_bus 的组织方式：
    //   [bank][out_idx][spatial_idx] -> 18bit partial sum
    //   对于每个输入 bank，都要分别计算 4 个输出通道、4 个空间位置的局部点积，一共是 8 x 4 x 4 = 128 个部分和
    //
    // 位宽说明：
    //   单个 INT8 x INT8 乘积是 16bit，4 项求和后需要 18bit 才能安全容纳符号位和进位
    reg [8*16*18-1:0] stage2_partial_bus;
    reg [63:0]        stage2_bias_data;

    // -------------------------
    // stage3：中间归约总线
    // -------------------------
    // stage3_reduce_bus 的组织方式：
    //   [out_idx][spatial_idx][pair_idx] -> 19bit pairwise reduced sum
    //   先把来自 8 个 bank 的部分和两两配对，得到 4 个 19bit 中间和，再打一拍寄存到 stage3_reduce_bus 中，供下一拍继续归约
    reg [16*4*19-1:0] stage3_reduce_bus;
    reg [63:0]        stage3_bias_data;

    // 各级 metadata 与数据总线同步前进，用于输出 valid / last / pos / group 对齐
    wire        stage1_valid;
    wire        stage1_last;
    wire [3:0]  stage1_pos;
    wire [2:0]  stage1_group;

    wire        stage2_valid;
    wire        stage2_last;
    wire [3:0]  stage2_pos;
    wire [2:0]  stage2_group;

    wire        stage3_valid;
    wire        stage3_last;
    wire [3:0]  stage3_pos;
    wire [2:0]  stage3_group;

    wire        stage4_valid;
    wire        stage4_last;
    wire [3:0]  stage4_pos;
    wire [2:0]  stage4_group;

    integer bank_idx;
    integer out_idx;
    integer spatial_idx;

    // stage2 临时变量：
    // 每次处理一个 {bank, out_idx, spatial_idx} 时，先取 4 个输入激活值和 4 个权重值
    // 再形成 4 个乘积，并使用 2 级平衡加法树求和
    reg signed [7:0]  act_value_0;
    reg signed [7:0]  act_value_1;
    reg signed [7:0]  act_value_2;
    reg signed [7:0]  act_value_3;// 4 个输入激活值
    reg signed [7:0]  wt_value_0;
    reg signed [7:0]  wt_value_1;
    reg signed [7:0]  wt_value_2;
    reg signed [7:0]  wt_value_3;// 4 个权重值
    reg signed [15:0] product_0;
    reg signed [15:0] product_1;
    reg signed [15:0] product_2;
    reg signed [15:0] product_3;// 4 个乘积结果
    reg signed [16:0] stage2_sum_l1_0;
    reg signed [16:0] stage2_sum_l1_1;// stage2 的两级平衡加法树的第一层中间和
    reg signed [17:0] partial_sum;// 最终的部分和结果

    // stage4 临时变量：
    // stage4_sum_l1_* 表示第二层归约中的 2 个中间和
    // stage4_sum_l2   表示四路中间和进一步归约后的结果，最后再与 bias 相加
    reg signed [19:0] stage4_sum_l1_0;
    reg signed [19:0] stage4_sum_l1_1;
    reg signed [20:0] stage4_sum_l2;
    reg signed [15:0] bias_value;
    reg signed [31:0] bias_ext;
    reg signed [31:0] accum_value;

    // 显式符号扩展函数
    function automatic signed [18:0] sx18_to_s19;
        input [17:0] data_in;
        begin
            sx18_to_s19 = {data_in[17], data_in};
        end
    endfunction

    function automatic signed [19:0] sx19_to_s20;
        input [18:0] data_in;
        begin
            sx19_to_s20 = {data_in[18], data_in};
        end
    endfunction

    function automatic signed [20:0] sx20_to_s21;
        input [19:0] data_in;
        begin
            sx20_to_s21 = {data_in[19], data_in};
        end
    endfunction

    // stage1：锁存本拍进入 MAC 的 tile / weight / bias
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_tile_data   <= 1024'd0;
            stage1_weight_data <= {(8*128){1'b0}};
            stage1_bias_data   <= 64'd0;
        end else begin
            stage1_tile_data   <= tile_data_bus;
            stage1_weight_data <= weight_data_bus;
            stage1_bias_data   <= bias_data_bus;
        end
    end

    // stage1 metadata 延迟 1 拍，与锁存后的 tile / weight / bias 对齐
    conv_tile_mac_meta_pipe u_meta_pipe_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_last(in_last),
        .in_pos(in_pos),
        .in_group(in_group),
        .out_valid(stage1_valid),
        .out_last(stage1_last),
        .out_pos(stage1_pos),
        .out_group(stage1_group)
    );

    // stage2：每个 bank 独立完成 4 项点积
    //
    // 对于固定的 {bank, out_idx, spatial_idx}：
    //   1. 取出该 bank 对应空间点上的 4 个输入通道值
    //   2. 取出当前输出通道 out_idx 对应的 4 个权重
    //   3. 做 4 次 INT8 x INT8 乘法
    //   4. 通过两级平衡加法树把 4 个乘积加成 1 个 18bit partial_sum
    //
    // 相比链式累加：
    //   (a+b)+(c+d) 的树形结构比 (((a+b)+c)+d) 组合深度更浅
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_partial_bus <= {(8*16*18){1'b0}};
            stage2_bias_data   <= 64'd0;
        end else begin
            stage2_bias_data <= stage1_bias_data;

            for (bank_idx = 0; bank_idx < 8; bank_idx = bank_idx + 1) begin
                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                    for (spatial_idx = 0; spatial_idx < 4; spatial_idx = spatial_idx + 1) begin
                        // 输入 tile 的索引方式：
                        //   bank 内部共有 4 个本地输入通道，每个通道对应 2x2 共 4 个空间位置
                        //   spatial_idx 取值 0..3，表示 2x2 内部的 4 个位置
                        act_value_0 = stage1_tile_data[(bank_idx*128) + ((0*4 + spatial_idx) * 8) +: 8];
                        act_value_1 = stage1_tile_data[(bank_idx*128) + ((1*4 + spatial_idx) * 8) +: 8];
                        act_value_2 = stage1_tile_data[(bank_idx*128) + ((2*4 + spatial_idx) * 8) +: 8];
                        act_value_3 = stage1_tile_data[(bank_idx*128) + ((3*4 + spatial_idx) * 8) +: 8];

                        // 权重索引方式：
                        //   每个 bank 对应一个 4(out) x 4(in) 的权重块
                        //   这里固定 out_idx，再依次取 4 个输入通道的权重
                        wt_value_0 = stage1_weight_data[(bank_idx*128) + ((out_idx*4 + 0) * 8) +: 8];
                        wt_value_1 = stage1_weight_data[(bank_idx*128) + ((out_idx*4 + 1) * 8) +: 8];
                        wt_value_2 = stage1_weight_data[(bank_idx*128) + ((out_idx*4 + 2) * 8) +: 8];
                        wt_value_3 = stage1_weight_data[(bank_idx*128) + ((out_idx*4 + 3) * 8) +: 8];

                        product_0 = act_value_0 * wt_value_0;
                        product_1 = act_value_1 * wt_value_1;
                        product_2 = act_value_2 * wt_value_2;
                        product_3 = act_value_3 * wt_value_3;

                        // 这里显式做符号扩展，避免 part-select / 位宽推导带来的 signed 歧义
                        stage2_sum_l1_0 = {{1{product_0[15]}}, product_0} + {{1{product_1[15]}}, product_1};
                        stage2_sum_l1_1 = {{1{product_2[15]}}, product_2} + {{1{product_3[15]}}, product_3};
                        partial_sum     = {{1{stage2_sum_l1_0[16]}}, stage2_sum_l1_0} +
                                          {{1{stage2_sum_l1_1[16]}}, stage2_sum_l1_1};

                        // 把当前 bank / out / spatial 的局部部分和写入 stage2 总线
                        stage2_partial_bus[((bank_idx*16 + out_idx*4 + spatial_idx) * 18) +: 18] <= partial_sum;
                    end
                end
            end
        end
    end

    // stage2 metadata 延迟 1 拍，与 stage2_partial_bus / stage2_bias_data 对齐
    conv_tile_mac_meta_pipe u_meta_pipe_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage1_valid),
        .in_last(stage1_last),
        .in_pos(stage1_pos),
        .in_group(stage1_group),
        .out_valid(stage2_valid),
        .out_last(stage2_last),
        .out_pos(stage2_pos),
        .out_group(stage2_group)
    );

    // stage3：8 个 bank 的部分和先做两两配对相加
    //
    // 对每个 {out_idx, spatial_idx}：
    //   pair_0 = bank0 + bank1
    //   pair_1 = bank2 + bank3
    //   pair_2 = bank4 + bank5
    //   pair_3 = bank6 + bank7

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage3_reduce_bus <= {(16*4*19){1'b0}};
            stage3_bias_data  <= 64'd0;
        end else begin
            stage3_bias_data <= stage2_bias_data;

            for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                for (spatial_idx = 0; spatial_idx < 4; spatial_idx = spatial_idx + 1) begin
                    // 直接从 stage2_partial_bus 按片取出 8 个 bank 的部分和，并在写入 stage3_reduce_bus 时
                    // 完成两两配对相加，去掉 partial_value_* / stage3_pair_* 这两层中间变量。
                    // 单个 partial_sum 是 18bit，两个 partial_sum 相加后寄存为 19bit 即可覆盖位宽需求
                    stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 0) * 19) +: 19] <=
                        sx18_to_s19(stage2_partial_bus[((0*16 + out_idx*4 + spatial_idx) * 18) +: 18]) +
                        sx18_to_s19(stage2_partial_bus[((1*16 + out_idx*4 + spatial_idx) * 18) +: 18]);
                    stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 1) * 19) +: 19] <=
                        sx18_to_s19(stage2_partial_bus[((2*16 + out_idx*4 + spatial_idx) * 18) +: 18]) +
                        sx18_to_s19(stage2_partial_bus[((3*16 + out_idx*4 + spatial_idx) * 18) +: 18]);
                    stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 2) * 19) +: 19] <=
                        sx18_to_s19(stage2_partial_bus[((4*16 + out_idx*4 + spatial_idx) * 18) +: 18]) +
                        sx18_to_s19(stage2_partial_bus[((5*16 + out_idx*4 + spatial_idx) * 18) +: 18]);
                    stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 3) * 19) +: 19] <=
                        sx18_to_s19(stage2_partial_bus[((6*16 + out_idx*4 + spatial_idx) * 18) +: 18]) +
                        sx18_to_s19(stage2_partial_bus[((7*16 + out_idx*4 + spatial_idx) * 18) +: 18]);
                end
            end
        end
    end

    // stage3 metadata 延迟 1 拍，与 stage3_reduce_bus / stage3_bias_data 对齐
    conv_tile_mac_meta_pipe u_meta_pipe_stage3 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage2_valid),
        .in_last(stage2_last),
        .in_pos(stage2_pos),
        .in_group(stage2_group),
        .out_valid(stage3_valid),
        .out_last(stage3_last),
        .out_pos(stage3_pos),
        .out_group(stage3_group)
    );

    // stage4：完成最终归约并叠加 bias
    //
    // 归约顺序：
    //   sum_l1_0 = pair_0 + pair_1
    //   sum_l1_1 = pair_2 + pair_3
    //   final    = sum_l1_0 + sum_l1_1 + bias
    //   需要处理 4 个中间和再加 bias
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_accum_bus <= {(16*32){1'b0}};
        end else begin
            for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                for (spatial_idx = 0; spatial_idx < 4; spatial_idx = spatial_idx + 1) begin
                    // 第二层归约：直接从 stage3_reduce_bus 按片取回 4 个已寄存的中间和
                    // 去掉 reduce_value_* 这层中间变量，但保留 stage4_sum_l* 作为“归约层次”的表达
                    stage4_sum_l1_0 =
                        sx19_to_s20(stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 0) * 19) +: 19]) +
                        sx19_to_s20(stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 1) * 19) +: 19]);
                    stage4_sum_l1_1 =
                        sx19_to_s20(stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 2) * 19) +: 19]) +
                        sx19_to_s20(stage3_reduce_bus[((out_idx*16 + spatial_idx*4 + 3) * 19) +: 19]);
                    stage4_sum_l2 = sx20_to_s21(stage4_sum_l1_0) + sx20_to_s21(stage4_sum_l1_1);

                    // bias 由 16bit 显式符号扩展到 32bit，再参与最终求和
                    bias_value  = stage3_bias_data[out_idx*16 +: 16];
                    bias_ext    = {{16{bias_value[15]}}, bias_value};
                    accum_value = {{11{stage4_sum_l2[20]}}, stage4_sum_l2} + bias_ext;

                    out_accum_bus[((out_idx*4 + spatial_idx) * 32) +: 32] <= accum_value;
                end
            end
        end
    end

    // stage4 metadata 延迟 1 拍，与最终 out_accum_bus 对齐
    conv_tile_mac_meta_pipe u_meta_pipe_stage4 (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stage3_valid),
        .in_last(stage3_last),
        .in_pos(stage3_pos),
        .in_group(stage3_group),
        .out_valid(stage4_valid),
        .out_last(stage4_last),
        .out_pos(stage4_pos),
        .out_group(stage4_group)
    );

    assign out_valid = stage4_valid;
    assign out_last  = stage4_last;
    assign out_pos   = stage4_pos;
    assign out_group = stage4_group;

endmodule
