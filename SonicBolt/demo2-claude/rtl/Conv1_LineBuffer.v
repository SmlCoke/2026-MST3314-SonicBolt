// ============================================================================
// Module: Conv1_LineBuffer
// Description: 11 行循环行缓冲器 (Circular Line Buffer)
//
// 功能概述：
//   存储 11 行输入特征图数据，每行 10 个 INT8 像素 (80 bits)。
//   采用循环指针 (wr_ptr) 控制写入位置，避免数据搬移，省面积。
//   对外提供"逻辑顺序"的 11 行数据输出，通过 wr_ptr 映射物理→逻辑。
//
// 关键参数：
//   - LINE_WIDTH = 80 bits (10 × INT8)
//   - NUM_LINES  = 11
//
// 接口说明：
//   - load_en + row_data_i: 写入一行新数据到 wr_ptr 指向的位置
//   - line_out_0 ~ line_out_10: 逻辑顺序输出 (0 = 窗口最上行)
// ============================================================================

module Conv1_LineBuffer (
    input  wire        clk,
    input  wire        rst_n,

    // ---------- 写入接口 ----------
    input  wire        load_en,        // 写入使能
    input  wire [79:0] row_data_i,     // 一行输入数据 (10 × INT8 = 80 bits)

    // ---------- 逻辑顺序读出 ----------
    output wire [79:0] line_out_0,     // 窗口第 0 行（最旧的行）
    output wire [79:0] line_out_1,
    output wire [79:0] line_out_2,
    output wire [79:0] line_out_3,
    output wire [79:0] line_out_4,
    output wire [79:0] line_out_5,
    output wire [79:0] line_out_6,
    output wire [79:0] line_out_7,
    output wire [79:0] line_out_8,
    output wire [79:0] line_out_9,
    output wire [79:0] line_out_10     // 窗口第 10 行（最新的行）
);

    // ======================== 内部存储 ========================
    // 11 个 80-bit 寄存器，存储 11 行特征图数据
    reg [79:0] line_buf [0:10];

    // 写指针：指向下一个写入位置（即最旧数据的位置）
    reg [3:0] wr_ptr;    // 0~10

    // ======================== 写入逻辑 ========================
    // 当 load_en 有效时，将新行写入 wr_ptr 指向的位置
    // 并将 wr_ptr 推进到下一个位置（循环）
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 4'd0;
            for (k = 0; k < 11; k = k + 1)
                line_buf[k] <= 80'd0;
        end else if (load_en) begin
            line_buf[wr_ptr] <= row_data_i;
            wr_ptr <= (wr_ptr == 4'd10) ? 4'd0 : wr_ptr + 4'd1;
        end
    end

    // ======================== 逻辑→物理映射 ========================
    // 逻辑行 i 对应物理位置 (wr_ptr + i) % 11
    // wr_ptr 始终指向"下一个要被覆盖的位置" = 当前最旧的行 = 逻辑行 0
    //
    // 示例: 如果 wr_ptr=3，则：
    //   逻辑行 0 → 物理位置 3  (最旧)
    //   逻辑行 1 → 物理位置 4
    //   ...
    //   逻辑行 7 → 物理位置 10
    //   逻辑行 8 → 物理位置 0
    //   逻辑行 9 → 物理位置 1
    //   逻辑行 10→ 物理位置 2  (最新)

    // 为避免取模运算（不利于综合），使用查表方式实现映射
    // physical_idx = (wr_ptr + logical_idx) >= 11 ?
    //               (wr_ptr + logical_idx - 11) : (wr_ptr + logical_idx)
    wire [3:0] idx [0:10];

    genvar i;
    generate
        for (i = 0; i < 11; i = i + 1) begin : gen_idx
            wire [4:0] sum = wr_ptr + i[3:0]; // 5-bit 避免溢出
            assign idx[i] = (sum >= 5'd11) ? sum[3:0] - 4'd11 : sum[3:0];
        end
    endgenerate

    // 根据映射后的物理索引输出逻辑顺序的行数据
    assign line_out_0  = line_buf[idx[0]];
    assign line_out_1  = line_buf[idx[1]];
    assign line_out_2  = line_buf[idx[2]];
    assign line_out_3  = line_buf[idx[3]];
    assign line_out_4  = line_buf[idx[4]];
    assign line_out_5  = line_buf[idx[5]];
    assign line_out_6  = line_buf[idx[6]];
    assign line_out_7  = line_buf[idx[7]];
    assign line_out_8  = line_buf[idx[8]];
    assign line_out_9  = line_buf[idx[9]];
    assign line_out_10 = line_buf[idx[10]];

endmodule
