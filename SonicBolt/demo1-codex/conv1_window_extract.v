`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: conv1_window_extract
// 功能  : 从 11x80bit 行缓冲中，按 col_cnt 组合截取 11x7 的窗口
// 输出  : win_flat，77 个 INT8，按 kh-major + kw-minor 展平
//         即 win_flat[(kh*7+kw)*8 +: 8] 对应窗口元素 (kh, kw)
// -----------------------------------------------------------------------------
module conv1_window_extract (
    input  wire [879:0] line_flat,
    input  wire [1:0]   col_cnt,    // 0~3
    output wire [615:0] win_flat
);
    wire [79:0] row_data [0:10];
    genvar r;
    genvar c;

    generate
        for (r = 0; r < 11; r = r + 1) begin : GEN_ROW_UNPACK
            assign row_data[r] = line_flat[r*80 +: 80];
        end
    endgenerate

    generate
        for (r = 0; r < 11; r = r + 1) begin : GEN_WIN_ROW
            for (c = 0; c < 7; c = c + 1) begin : GEN_WIN_COL
                assign win_flat[(r*7 + c)*8 +: 8] = row_data[r][((col_cnt + c)*8) +: 8];
            end
        end
    endgenerate

endmodule

