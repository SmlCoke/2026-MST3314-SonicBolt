// ============================================================================
// Module: Conv1_MACUnit
// Description: 单通道 77 路乘累加单元 (Multiply-Accumulate Unit)
//
// 功能概述：
//   对 11×7 = 77 个 INT8 输入与 77 个 INT8 权重进行逐元素乘法，
//   将 77 个乘积求和后加偏置，输出 INT32 累加结果。
//   全组合逻辑实现（乘法器+加法树），外部流水线寄存器在 Conv1_Top 中。
//
// 运算公式：
//   result = bias + Σ(input[i] × weight[i]), i = 0..76
//
// 位宽分析：
//   - 输入/权重各 8 bit signed → 乘积 16 bit signed
//   - 77 个 16-bit 乘积求和 → 最大需要 16 + ceil(log2(77)) = 16+7 = 23 bit
//   - 加上 INT16 偏置（符号扩展到 32 bit）→ 32 bit 足够
//
// 注意：
//   该模块是纯组合逻辑，无时钟。32 个实例并行使用同一组输入数据，
//   但各自持有不同的权重和偏置。
// ============================================================================

module Conv1_MACUnit (
    // ---------- 窗口数据输入 (11×7 = 77 个 INT8) ----------
    input  wire [615:0] window_data_i,  // 77 × 8 = 616 bits, packed
    // 排列: window_data_i[7:0]   = pixel(0,0)
    //       window_data_i[15:8]  = pixel(0,1)
    //       ...
    //       window_data_i[615:608] = pixel(10,6)

    // ---------- 权重输入 (11×7 = 77 个 INT8) ----------
    input  wire [615:0] weight_data_i,  // 77 × 8 = 616 bits, packed
    // 排列方式与窗口数据一致

    // ---------- 偏置输入 ----------
    input  wire [15:0]  bias_i,         // INT16 偏置（规范要求）

    // ---------- 累加输出 ----------
    output wire [31:0]  acc_result_o    // INT32 累加结果
);

    // ======================== 乘法器阵列 ========================
    // 77 个 8×8 signed 乘法器，输出 16-bit 有符号乘积
    wire signed [15:0] prod [0:76];

    genvar g;
    generate
        for (g = 0; g < 77; g = g + 1) begin : gen_mult
            wire signed [7:0] a = window_data_i[g*8 +: 8];  // 输入像素
            wire signed [7:0] b = weight_data_i[g*8 +: 8];  // 权重
            assign prod[g] = a * b;
        end
    endgenerate

    // ======================== 加法树 ========================
    // 将 77 个 16-bit 乘积求和，结果扩展为 32 bits
    // 使用行为级 for 循环描述，综合工具会自动推导加法树
    //
    // 手动展开加法树级数分析：
    //   Level 1: 77 → 39 (38 对 + 1 剩余)
    //   Level 2: 39 → 20 (19 对 + 1 剩余)
    //   Level 3: 20 → 10
    //   Level 4: 10 → 5
    //   Level 5: 5 → 3 (2 对 + 1 剩余)
    //   Level 6: 3 → 2 (1 对 + 1 剩余)
    //   Level 7: 2 → 1
    //   共 7 级加法 → 关键路径 = 1 个乘法 + 7 个加法

    // 行为级求和（综合工具友好）
    reg signed [31:0] sum;
    integer j;
    always @(*) begin
        sum = {{16{bias_i[15]}}, bias_i};  // 初始值 = 偏置（INT16 符号扩展至 32 位）
        for (j = 0; j < 77; j = j + 1) begin
            sum = sum + {{16{prod[j][15]}}, prod[j]};  // 符号扩展到 32 位后累加
        end
    end

    assign acc_result_o = sum;

endmodule
