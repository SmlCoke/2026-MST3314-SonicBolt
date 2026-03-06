// ============================================================================
// Module: Conv1_RequantUnit
// Description: 重量化 + ReLU 单元 (Requantization with ReLU)
//
// 功能概述：
//   将 INT32 累加结果通过定点乘法和移位转换为 INT8 输出，并应用 ReLU 激活。
//   这是深度学习量化推理的标准做法。
//
// 运算公式：
//   shifted = (acc_in × M0) >>> n      (算术右移)
//   output  = clamp(shifted, 0, 127)   (ReLU: 负值归零, 正值截断到 127)
//
// Conv1 层参数：
//   M0 = 111 (8-bit signed, 实际为正数)
//   n  = 14
//   等效浮点乘数 M = 111 / 2^14 ≈ 0.006775
//
// 位宽分析：
//   - acc_in: 32 bit signed
//   - acc_in × M0: 32 × 8 = 40 bit signed (保守), 实际用 40 bit
//   - 右移 14 位后: 26 bit signed
//   - clamp 到 [0, 127]: 8 bit unsigned (ReLU 后无负值)
//
// 流水线：
//   纯组合逻辑，外部流水寄存器在 Conv1_Top 中
// ============================================================================

module Conv1_RequantUnit (
    // ---------- 输入 ----------
    input  wire [31:0] acc_i,      // INT32 累加结果

    // ---------- 输出 ----------
    output wire [7:0]  quant_o     // INT8 量化输出 (经过 ReLU)
);

    // ======================== 参数定义 ========================
    // M0 和 n 作为 localparam 固定，不同层可实例化不同参数
    localparam signed [7:0] M0 = 8'sd111;   // 重量化乘数
    localparam        [4:0] N_SHIFT = 5'd14; // 右移位数

    // ======================== 乘法 ========================
    // INT32 × INT8 → INT40 (取 40 位保证无溢出)
    wire signed [39:0] mult_result;
    assign mult_result = $signed(acc_i) * M0;

    // ======================== 算术右移 ========================
    // 算术右移 N_SHIFT 位（保持符号位）
    wire signed [39:0] shifted;
    assign shifted = mult_result >>> N_SHIFT;

    // ======================== Clamp + ReLU ========================
    // ReLU: 负值 → 0
    // 上界截断: > 127 → 127
    // 组合起来: clamp(shifted, 0, 127)
    reg [7:0] clamped;
    always @(*) begin
        if (shifted < 0) begin
            clamped = 8'd0;             // ReLU: 负值归零
        end else if (shifted > 127) begin
            clamped = 8'd127;           // 饱和到 127
        end else begin
            clamped = shifted[7:0];     // 正常范围
        end
    end

    assign quant_o = clamped;

endmodule
