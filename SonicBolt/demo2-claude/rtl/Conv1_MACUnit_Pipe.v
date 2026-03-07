// ============================================================================
// Module: Conv1_MACUnit_Pipe
// Description: 单通道 77 路乘累加单元 — 3 级流水线版本
//
// 功能概述：
//   与 Conv1_MACUnit 功能完全相同：对 11×7=77 个 INT8 输入与权重做乘累加，
//   加 INT16 偏置后输出 INT32 结果。
//   区别：将加法树手动分为 3 级流水线，每级后插入寄存器，缩短关键路径。
//
// 流水线结构（3 级，延迟 = 3 个时钟周期）：
//
//   输入
//    │
//    │ [组合] 77 路 8×8 乘法
//    │
//   ─┤ Stage 1 寄存器：77 个 16-bit 乘积 + 偏置
//    │
//    │ [组合] 4 级加法树：77 → 5
//    │   Level 1: 77 → 39 (38 对 + 1 剩余)
//    │   Level 2: 39 → 20 (19 对 + 1 剩余)
//    │   Level 3: 20 → 10
//    │   Level 4: 10 → 5
//    │
//   ─┤ Stage 2 寄存器：5 个 32-bit 中间和 + 偏置
//    │
//    │ [组合] 3 级加法树：5 → 1 + 偏置加法
//    │   Level 5: 5 → 3 (2 对 + 1 剩余)
//    │   Level 6: 3 → 2 (1 对 + 1 剩余)
//    │   Level 7: 2 → 1，加偏置
//    │
//   ─┤ Stage 3 寄存器：32-bit 最终结果（输出）
//
// 各级关键路径（相比无流水线版 1×乘法+7×加法）：
//   Stage 0→1: 1 个乘法
//   Stage 1→2: 4 级加法
//   Stage 2→3: 3 级加法 + 1 次偏置加法
//
// 位宽说明：
//   - 输入/权重: INT8 (8-bit signed)
//   - 乘积: 16-bit signed
//   - 加法树中间值: 符号扩展至 32-bit（综合工具可进一步优化实际位宽）
//   - 偏置: INT16 (16-bit signed, 规范要求)
//   - 输出: INT32 (32-bit signed)
// ============================================================================

module Conv1_MACUnit_Pipe (
    input  wire        clk,
    input  wire        rst_n,

    // ---------- 窗口数据输入 (11×7 = 77 个 INT8) ----------
    input  wire [615:0] window_data_i,  // 77 × 8 = 616 bits, packed
    // 排列: window_data_i[7:0]   = pixel(0,0)
    //       window_data_i[615:608] = pixel(10,6)

    // ---------- 权重输入 (11×7 = 77 个 INT8) ----------
    input  wire [615:0] weight_data_i,  // 77 × 8 = 616 bits, packed

    // ---------- 偏置输入 ----------
    input  wire [15:0]  bias_i,         // INT16 偏置（规范要求）

    // ---------- 累加输出 ----------
    output reg  [31:0]  acc_result_o    // INT32 累加结果（3 周期延迟）
);

    // ============================================================
    // Stage 0 [组合]：77 路 8×8 有符号乘法
    // ============================================================
    wire signed [15:0] prod [0:76];

    genvar g;
    generate
        for (g = 0; g < 77; g = g + 1) begin : gen_mult
            wire signed [7:0] a = window_data_i[g*8 +: 8];
            wire signed [7:0] b = weight_data_i[g*8 +: 8];
            assign prod[g] = a * b;
        end
    endgenerate

    // ============================================================
    // Stage 1 寄存器：77 个乘积 + 偏置流水
    // ============================================================
    reg signed [15:0] s1_prod [0:76];
    reg signed [15:0] s1_bias;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 77; i = i + 1)
                s1_prod[i] <= 16'sd0;
            s1_bias <= 16'sd0;
        end else begin
            for (i = 0; i < 77; i = i + 1)
                s1_prod[i] <= prod[i];
            s1_bias <= $signed(bias_i);
        end
    end

    // ============================================================
    // Stage 1→2 [组合]：4 级加法树 (77 → 5)
    // 所有中间值符号扩展至 32 位
    // ============================================================

    // ---- Level 1: 77 → 39 (38 对 + 1 剩余) ----
    // lv1[0..37]：每对 s1_prod[2k] + s1_prod[2k+1]
    // lv1[38]：s1_prod[76] 直通（剩余元素）
    wire signed [31:0] lv1 [0:38];

    genvar k1;
    generate
        for (k1 = 0; k1 < 38; k1 = k1 + 1) begin : gen_lv1
            assign lv1[k1] = {{16{s1_prod[k1*2][15]}},   s1_prod[k1*2]}
                            + {{16{s1_prod[k1*2+1][15]}}, s1_prod[k1*2+1]};
        end
    endgenerate
    assign lv1[38] = {{16{s1_prod[76][15]}}, s1_prod[76]};

    // ---- Level 2: 39 → 20 (19 对 + 1 剩余) ----
    // lv2[0..18]：每对 lv1[2k] + lv1[2k+1]
    // lv2[19]：lv1[38] 直通
    wire signed [31:0] lv2 [0:19];

    genvar k2;
    generate
        for (k2 = 0; k2 < 19; k2 = k2 + 1) begin : gen_lv2
            assign lv2[k2] = lv1[k2*2] + lv1[k2*2+1];
        end
    endgenerate
    assign lv2[19] = lv1[38];

    // ---- Level 3: 20 → 10 ----
    // lv3[0..9]：每对 lv2[2k] + lv2[2k+1]
    wire signed [31:0] lv3 [0:9];

    genvar k3;
    generate
        for (k3 = 0; k3 < 10; k3 = k3 + 1) begin : gen_lv3
            assign lv3[k3] = lv2[k3*2] + lv2[k3*2+1];
        end
    endgenerate

    // ---- Level 4: 10 → 5 ----
    // lv4[0..4]：每对 lv3[2k] + lv3[2k+1]
    wire signed [31:0] lv4 [0:4];

    genvar k4;
    generate
        for (k4 = 0; k4 < 5; k4 = k4 + 1) begin : gen_lv4
            assign lv4[k4] = lv3[k4*2] + lv3[k4*2+1];
        end
    endgenerate

    // ============================================================
    // Stage 2 寄存器：5 个中间累加和 + 偏置流水
    // ============================================================
    reg signed [31:0] s2_psum [0:4];
    reg signed [15:0] s2_bias;

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < 5; j = j + 1)
                s2_psum[j] <= 32'sd0;
            s2_bias <= 16'sd0;
        end else begin
            for (j = 0; j < 5; j = j + 1)
                s2_psum[j] <= lv4[j];
            s2_bias <= s1_bias;
        end
    end

    // ============================================================
    // Stage 2→3 [组合]：3 级加法树 (5 → 1) + 偏置加法
    // ============================================================

    // ---- Level 5: 5 → 3 (2 对 + 1 剩余) ----
    wire signed [31:0] lv5_0 = s2_psum[0] + s2_psum[1];  // pair (0,1)
    wire signed [31:0] lv5_1 = s2_psum[2] + s2_psum[3];  // pair (2,3)
    wire signed [31:0] lv5_2 = s2_psum[4];                // 剩余

    // ---- Level 6: 3 → 2 (1 对 + 1 剩余) ----
    wire signed [31:0] lv6_0 = lv5_0 + lv5_1;
    wire signed [31:0] lv6_1 = lv5_2;                     // 直通

    // ---- Level 7: 2 → 1 ----
    wire signed [31:0] lv7 = lv6_0 + lv6_1;

    // ---- 加偏置：INT16 偏置符号扩展至 32 位后相加 ----
    wire signed [31:0] final_sum = lv7 + {{16{s2_bias[15]}}, s2_bias};

    // ============================================================
    // Stage 3 寄存器：最终结果（输出）
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc_result_o <= 32'sd0;
        else
            acc_result_o <= final_sum;
    end

endmodule
