// ============================================================================
// Module: Conv1_RequantUnit
// Description: 重量化单元 (Signed Requantization)
//
// 功能概述：
//   将 INT32 累加结果通过定点乘法和移位转换为 INT8 输出。
//   输出保留符号，做 INT8 饱和截断到 [-128, 127]。
//
// 运算公式：
//   shifted = (acc_in × M0) >>> n      (算术右移)
//   output  = clamp(shifted, -128, 127)
//
// Conv1 层参数：
//   M0 = 111 (16-bit signed, INT16，规范要求)
//   n  = 14
//   等效浮点乘数 M = 111 / 2^14 ≈ 0.006775
//
// 位宽分析：
//   - acc_in: 32 bit signed
//   - acc_in × M0: 32 × 16 = 48 bit signed (保守), 实际用 48 bit
//   - 右移 14 位后: 34 bit signed
//   - clamp 到 [-128, 127]: 8 bit signed
//
// 流水线：
//   纯组合逻辑，外部流水寄存器在 Conv1_Top 中
// ============================================================================

module Conv1_RequantUnit (
    // ---------- 输入 ----------
    input  wire [31:0] acc_i,      // INT32 累加结果

    // ---------- 输出 ----------
    output wire [7:0]  quant_o     // INT8 量化输出（保留符号）
);

    // ======================== 参数定义 ========================
    // M0 和 n 作为 localparam 固定，不同层可实例化不同参数
    localparam signed [15:0] M0 = 16'sd111;  // 重量化乘数（INT16，规范要求）
    localparam        [4:0] N_SHIFT = 5'd14; // 右移位数

    // ======================== 乘法 ========================
    // INT32 × INT16 → INT48 (取 48 位保证无溢出)
    wire signed [47:0] mult_result;
    assign mult_result = $signed(acc_i) * M0;

    // ======================== 算术右移 ========================
    // 算术右移 N_SHIFT 位（右侧补符号位）
    wire signed [47:0] shifted;
    assign shifted = mult_result >>> N_SHIFT;

    // fj0307: 注意：上述两个 assign 同时进行

    // ======================== Clamp ========================
    // 有符号饱和截断到 INT8 范围 [-128, 127]
    reg [7:0] clamped;
    always @(*) begin
        if (shifted < -128) begin
            clamped = 8'h80;            // 饱和到 -128
        end else if (shifted > 127) begin
            clamped = 8'd127;           // 饱和到 127
        end else begin
            clamped = shifted[7:0];     // 正常范围，按补码输出
        end
    end

    assign quant_o = clamped;

endmodule
