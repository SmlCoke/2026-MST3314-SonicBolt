// ===========================================================================
// 文件名: conv1_line_buffer.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   环形行缓冲器（Circular Line Buffer），用于 Conv1 的 11×7 卷积窗口。
//   内部维护 11 行 × 80-bit（10个INT8）的寄存器文件，
//   通过写指针循环控制新行插入，避免移位操作以降低功耗。
//
// 设计要点:
//   - 写指针 wr_ptr 在 0~10 之间循环（条件判断，不使用取模运算）
//   - 逻辑行 i 的物理地址 = (wr_ptr + i) % 11
//   - 通过 MUX 实现物理地址到逻辑行的映射
//   - push_en=1 时，新行数据写入 line_buf[wr_ptr]，写指针递增
//   - 组合逻辑输出：11 × 80-bit 逻辑行数据
//
// 性能优势:
//   每次 push 仅翻转 1 行寄存器（80 个 DFF），
//   相比移位方案（翻转 11×80 = 880 个 DFF）节省约 90% 动态功耗。
// ---------------------------------------------------------------------------
// 端口说明:
//   clk       — 系统时钟
//   rst_n     — 异步低电平复位
//   push_en   — 行推入使能
//   push_data — 新行数据（10×INT8 = 80-bit）
//   row_data  — 11 × 80-bit 逻辑行输出（展平为 880-bit）
//              row_data[i*80 +: 80] = 逻辑第 i 行（i=0 是最旧的行）
// ===========================================================================

module conv1_line_buffer (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               push_en,
    input  wire [79:0]        push_data,
    output wire [880-1:0]     row_data     // 11 × 80-bit
);

    // ------------------------------------------------------------------
    // 内部存储：11 行 × 80-bit 寄存器
    // ------------------------------------------------------------------
    reg [79:0] line_buf [0:10];

    // ------------------------------------------------------------------
    // 写指针：0 ~ 10 循环
    // ------------------------------------------------------------------
    reg [3:0] wr_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_ptr <= 4'd0;
        else if (push_en)
            wr_ptr <= (wr_ptr == 4'd10) ? 4'd0 : wr_ptr + 4'd1;
    end

    // ------------------------------------------------------------------
    // push 操作：将新行写入 wr_ptr 指向的物理位置
    // ------------------------------------------------------------------
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 11; k = k + 1)
                line_buf[k] <= 80'd0;
        end else if (push_en) begin
            line_buf[wr_ptr] <= push_data;
        end
    end

    // ------------------------------------------------------------------
    // 逻辑行映射：逻辑行 i = 物理行 (wr_ptr + i) % 11
    // wr_ptr 指向下一个要写入的位置，也就是最旧的数据
    // 因此逻辑行 0（最旧）= 物理行 wr_ptr
    //       逻辑行 10（最新）= 物理行 (wr_ptr + 10) % 11 = wr_ptr - 1
    // ------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 11; i = i + 1) begin : gen_row_mux
            // 计算物理索引：(wr_ptr + i) % 11
            // 由于 wr_ptr ∈ [0,10]，i ∈ [0,10]，和的范围是 [0,20]
            // 如果 >= 11 则减 11
            wire [4:0] phys_idx_raw = {1'b0, wr_ptr} + i[4:0];
            wire [3:0] phys_idx = (phys_idx_raw >= 5'd11) ?
                                  phys_idx_raw[3:0] - 4'd11 :
                                  phys_idx_raw[3:0];

            // MUX 选择对应物理行
            reg [79:0] mux_out;
            always @(*) begin
                case (phys_idx)
                    4'd0:  mux_out = line_buf[0];
                    4'd1:  mux_out = line_buf[1];
                    4'd2:  mux_out = line_buf[2];
                    4'd3:  mux_out = line_buf[3];
                    4'd4:  mux_out = line_buf[4];
                    4'd5:  mux_out = line_buf[5];
                    4'd6:  mux_out = line_buf[6];
                    4'd7:  mux_out = line_buf[7];
                    4'd8:  mux_out = line_buf[8];
                    4'd9:  mux_out = line_buf[9];
                    4'd10: mux_out = line_buf[10];
                    default: mux_out = 80'd0;
                endcase
            end

            assign row_data[i*80 +: 80] = mux_out;
        end
    endgenerate

endmodule
