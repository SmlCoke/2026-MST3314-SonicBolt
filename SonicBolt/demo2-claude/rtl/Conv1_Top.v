// ============================================================================
// Module: Conv1_Top
// Description: 第一层标准卷积 (Conv1) 顶层模块
//
// 功能概述：
//   实现 (1,30,10) → Conv(32,11×7) → Requant → (32,20,4) 的完整卷积运算。
//   采用 32 通道全并行架构，每个时钟周期输出一个空间位置的 32 个通道值。
//
// 架构特点：
//   - 32 个并行 MAC 单元 (每个 77 路乘累加)
//   - 32 个并行重量化单元
//   - 11 行循环行缓冲器
//   - FSM 控制: IDLE → LOAD_WEIGHT → LOAD_BIAS → FILL_LB → CALC_RUN → DONE
//   - 2 级流水线: MAC (组合) → Requant (组合) → 寄存输出
//
// 性能指标：
//   - LOAD_WEIGHT: 2464 周期 (32 个 filter × 77 个权重)
//   - LOAD_BIAS:   32 周期
//   - FILL_LB:     11 周期 (填充 11 行)
//   - CALC_RUN:    80 周期 (20 行 × 4 列)
//   - 总共:        ~2587 周期 (权重加载仅需一次)
//   - 推理部分:    91 周期 (FILL_LB + CALC_RUN)
//
// 乘法器总数: 32 × 77 = 2464 (INT8×INT8 乘法器)
// ============================================================================

module Conv1_Top (
    input  wire        clk,
    input  wire        rst_n,

    // ==================== 控制接口 ====================
    input  wire        start,           // 启动信号 (上升沿触发)
    output reg         busy,            // 正在计算
    output reg         done,            // 计算完成 (脉冲)

    // ==================== 权重加载接口 ====================
    // 在 LOAD_WEIGHT 状态下，外部逐周期送入权重
    // 顺序: filter[0] 的 77 个权重, filter[1] 的 77 个权重, ..., filter[31] 的 77 个权重
    input  wire [7:0]  wt_data_i,       // INT8 权重数据
    input  wire        wt_valid_i,      // 权重数据有效

    // ==================== 偏置加载接口 ====================
    // 在 LOAD_BIAS 状态下，外部逐周期送入偏置
    // 顺序: bias[0], bias[1], ..., bias[31]
    input  wire [15:0] bias_data_i,     // INT16 偏置数据（规范要求）
    input  wire        bias_valid_i,    // 偏置数据有效

    // ==================== 输入 SRAM 接口 ====================
    // 假设外部 SRAM 组合读取（地址给出后同周期数据有效）
    output reg  [4:0]  input_row_addr,  // 读取行地址 (0~29)
    output reg         input_rd_en,     // 读取使能
    input  wire [79:0] input_row_data,  // 一行数据 (10 × INT8 = 80 bits)

    // ==================== 输出接口 ====================
    output reg  [255:0] output_data,    // 32 × INT8 = 256 bits (寄存输出)
    output reg         output_valid,    // 输出数据有效
    output reg  [4:0]  output_row,      // 输出行坐标 (0~19)
    output reg  [1:0]  output_col       // 输出列坐标 (0~3)
);

    // ================================================================
    //                         参数定义
    // ================================================================
    localparam NUM_FILTERS  = 32;    // 输出通道数
    localparam KERNEL_H     = 11;    // 卷积核高度
    localparam KERNEL_W     = 7;     // 卷积核宽度
    localparam KERNEL_SIZE  = 77;    // 11 × 7
    localparam INPUT_H      = 30;    // 输入高度
    localparam INPUT_W      = 10;    // 输入宽度
    localparam OUTPUT_H     = 20;    // 输出高度 = 30 - 11 + 1
    localparam OUTPUT_W     = 4;     // 输出宽度 = 10 - 7 + 1

    // ================================================================
    //                     FSM 状态定义
    // ================================================================
    localparam S_IDLE        = 3'd0;  // 空闲，等待 start
    localparam S_LOAD_WEIGHT = 3'd1;  // 加载权重
    localparam S_LOAD_BIAS   = 3'd2;  // 加载偏置
    localparam S_FILL_LB     = 3'd3;  // 填充行缓冲
    localparam S_CALC_RUN    = 3'd4;  // 计算
    localparam S_DONE        = 3'd5;  // 完成

    reg [2:0] state, next_state;

    // ================================================================
    //                     内部计数器
    // ================================================================
    reg [11:0] wt_load_cnt;     // 权重加载计数 (0~2463)
    reg [4:0]  bias_load_cnt;   // 偏置加载计数 (0~31)
    reg [3:0]  fill_cnt;        // 行填充计数 (0~10)
    reg [4:0]  row_cnt;         // 输出行计数 (0~19)
    reg [1:0]  col_cnt;         // 输出列计数 (0~3)

    // ================================================================
    //                   权重与偏置存储
    // ================================================================
    // 32 个 filter × 77 个 INT8 权重 = 2464 个权重
    // 使用一维数组存储: weight_mem[filter_id * 77 + pos]
    reg [7:0] weight_mem [0:2463];

    // 32 个 INT16 偏置（规范要求）
    reg [15:0] bias_mem [0:31];

    // ================================================================
    //                   行缓冲器实例化
    // ================================================================
    wire        lb_load_en;
    wire [79:0] lb_row_data;
    wire [79:0] lb_line [0:10]; // 逻辑顺序输出的 11 行

    Conv1_LineBuffer u_linebuf (
        .clk        (clk),
        .rst_n      (rst_n),
        .load_en    (lb_load_en),
        .row_data_i (lb_row_data),
        .line_out_0 (lb_line[0]),
        .line_out_1 (lb_line[1]),
        .line_out_2 (lb_line[2]),
        .line_out_3 (lb_line[3]),
        .line_out_4 (lb_line[4]),
        .line_out_5 (lb_line[5]),
        .line_out_6 (lb_line[6]),
        .line_out_7 (lb_line[7]),
        .line_out_8 (lb_line[8]),
        .line_out_9 (lb_line[9]),
        .line_out_10(lb_line[10])
    );

    // 行缓冲器写入控制
    // FILL_LB 阶段: 从 SRAM 读取数据写入
    // CALC_RUN 阶段: col_cnt==3 时读取下一行写入（最后一行除外）
    assign lb_load_en  = (state == S_FILL_LB) ||
                         (state == S_CALC_RUN && col_cnt == 2'd3 && row_cnt < OUTPUT_H - 1);
    assign lb_row_data = input_row_data;

    // ================================================================
    //             窗口数据提取 (Window Extraction)
    // ================================================================
    // 从 11 行 × 10 列中，根据 col_cnt 提取 11×7 的窗口
    // col_cnt=c 时: 从每行取第 c ~ c+6 列 (7 个 INT8 = 56 bits)
    //
    // 窗口排列: window_flat[7:0]   = line[0]的第col_cnt个像素
    //           window_flat[15:8]  = line[0]的第col_cnt+1个像素
    //           ...
    //           window_flat[55:48] = line[0]的第col_cnt+6个像素
    //           window_flat[63:56] = line[1]的第col_cnt个像素
    //           ...
    //           window_flat[615:608] = line[10]的第col_cnt+6个像素

    reg [615:0] window_flat;  // 77 × 8 = 616 bits

    integer r, c;
    always @(*) begin
        // window_flat = 616'd0; 
        // 由于每个位置都被赋值，理论上不需要初始化为 0，避免无意义的翻转
        // fj0307: 这里会有616个4:1 MUX
        for (r = 0; r < KERNEL_H; r = r + 1) begin
            for (c = 0; c < KERNEL_W; c = c + 1) begin
                // 从行缓冲第 r 行中提取第 (col_cnt + c) 个像素
                // 像素位置: [(col_cnt+c)*8 +: 8]
                // 目标位置: [(r*7+c)*8 +: 8]
                window_flat[(r * KERNEL_W + c) * 8 +: 8] =
                    lb_line[r][(col_cnt + c[2:0]) * 8 +: 8];
            end
        end
    end

    // ================================================================
    //            32 个 MAC 单元 + 32 个 Requant 单元
    // ================================================================

    // 组装各 filter 的权重为 packed 格式
    wire [615:0] weight_packed [0:31]; // 32 个 filter 的 packed 权重
    wire [15:0]  bias_packed   [0:31]; // 32 个偏置（INT16）

    // MAC 输出 (组合逻辑)
    wire [31:0]  mac_result [0:31];

    // Requant 输出 (组合逻辑)
    wire [7:0]   quant_result [0:31];

    genvar f, p;
    generate // 这段 generate 逻辑在综合时会展开成 32 个并行的 MAC + Requant 实例
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin : gen_filter
            // 32 个 Filter 全部并行计算
            // ---------- 权重打包 ----------
            // 从 weight_mem 中取出 filter f 的 77 个权重，打包为 616-bit
            // weight_packed[f] = {weight_mem[f*77+76], ..., weight_mem[f*77+1], weight_mem[f*77+0]}
            wire [615:0] w_pack;
            // w_pack 存放第 f 个卷积核的全部77个权重
            for (p = 0; p < KERNEL_SIZE; p = p + 1) begin : gen_wt_pack
                assign w_pack[p*8 +: 8] = weight_mem[f * KERNEL_SIZE + p];
            end
            assign weight_packed[f] = w_pack;

            // ---------- 偏置 ----------
            assign bias_packed[f] = bias_mem[f];

            // ---------- MAC 单元实例化 ----------
            Conv1_MACUnit u_mac (
                .window_data_i (window_flat),
                .weight_data_i (weight_packed[f]),
                .bias_i        (bias_packed[f]),
                .acc_result_o  (mac_result[f])
            );

            // ---------- 重量化单元实例化 ----------
            Conv1_RequantUnit u_requant (
                .acc_i   (mac_result[f]),
                .quant_o (quant_result[f])
            );
        end
    endgenerate

    // ================================================================
    //                    输出数据打包 (组合逻辑)
    // ================================================================
    // 将 32 个 INT8 输出打包为 256-bit
    // output_data_comb[7:0]   = channel 0
    // output_data_comb[15:8]  = channel 1
    // ...
    // output_data_comb[255:248] = channel 31
    wire [255:0] output_data_comb;

    genvar ch;
    generate
        for (ch = 0; ch < NUM_FILTERS; ch = ch + 1) begin : gen_out_pack
            assign output_data_comb[ch*8 +: 8] = quant_result[ch];
        end
    endgenerate

    // ================================================================
    //                     FSM 状态转移
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_LOAD_WEIGHT;
            end

            S_LOAD_WEIGHT: begin
                // 所有 2464 个权重加载完成后转移
                if (wt_valid_i && wt_load_cnt == 2463)
                    next_state = S_LOAD_BIAS;
            end

            S_LOAD_BIAS: begin
                // 所有 32 个偏置加载完成后转移
                if (bias_valid_i && bias_load_cnt == 31)
                    next_state = S_FILL_LB;
            end

            S_FILL_LB: begin
                // 11 行填充完成后转移
                if (fill_cnt == 4'd10)
                    next_state = S_CALC_RUN;
            end

            S_CALC_RUN: begin
                // 所有 20×4 个输出位置计算完成后转移
                if (row_cnt == OUTPUT_H - 1 && col_cnt == OUTPUT_W - 1)
                    next_state = S_DONE;
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ================================================================
    //                    权重加载逻辑
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wt_load_cnt <= 12'd0;
        end else if (state == S_IDLE) begin
            wt_load_cnt <= 12'd0;
        end else if (state == S_LOAD_WEIGHT && wt_valid_i) begin
            weight_mem[wt_load_cnt] <= wt_data_i;
            wt_load_cnt <= wt_load_cnt + 12'd1;
        end
    end

    // ================================================================
    //                    偏置加载逻辑
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bias_load_cnt <= 5'd0;
        end else if (state == S_LOAD_WEIGHT) begin
            bias_load_cnt <= 5'd0;
        end else if (state == S_LOAD_BIAS && bias_valid_i) begin
            bias_mem[bias_load_cnt] <= bias_data_i;
            bias_load_cnt <= bias_load_cnt + 5'd1;
        end
    end

    // ================================================================
    //                    行填充逻辑
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_cnt <= 4'd0;
        end else if (state == S_LOAD_BIAS) begin
            fill_cnt <= 4'd0;
        end else if (state == S_FILL_LB) begin
            fill_cnt <= fill_cnt + 4'd1;
        end
    end
    // 每个周期在 FILL_LB 阶段读取一行数据写入行缓冲，直到填满 11 行

    // ================================================================
    //                   计算阶段计数器
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_cnt <= 5'd0;
            col_cnt <= 2'd0;
        end else if (state == S_FILL_LB) begin
            row_cnt <= 5'd0;
            col_cnt <= 2'd0;
        end else if (state == S_CALC_RUN) begin
            if (col_cnt == OUTPUT_W - 1) begin
                col_cnt <= 2'd0;
                row_cnt <= row_cnt + 5'd1;
            end else begin
                col_cnt <= col_cnt + 2'd1;
            end
        end
    end

    // ================================================================
    //                  SRAM 读取地址控制
    // ================================================================
    // FILL_LB: 读取行 0~10
    // CALC_RUN: col_cnt==3 时读取行 row_cnt+11 (为下一行组准备)
    always @(*) begin
        input_rd_en = 1'b0;
        input_row_addr = 5'd0;

        case (state)
            S_FILL_LB: begin
                input_rd_en = 1'b1;
                input_row_addr = {1'b0, fill_cnt};
            end

            S_CALC_RUN: begin
                if (col_cnt == 2'd3 && row_cnt < OUTPUT_H - 1) begin
                    input_rd_en = 1'b1;
                    input_row_addr = row_cnt + 5'd11;
                end
            end

            default: begin
                input_rd_en = 1'b0;
                input_row_addr = 5'd0;
            end
        endcase
    end

    // ================================================================
    //                    输出流水寄存器
    // ================================================================
    // MAC + Requant 都是组合逻辑，输出在 CALC_RUN 同周期就绑定了
    // 为了时序收敛，在输出端添加 1 拍寄存器延迟
    // output_data / output_valid / output_row / output_col 全部寄存，保证对齐

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_data  <= 256'd0;
            output_valid <= 1'b0;
            output_row   <= 5'd0;
            output_col   <= 2'd0;
        end else begin
            output_data  <= output_data_comb;
            output_valid <= (state == S_CALC_RUN);
            output_row   <= row_cnt;
            output_col   <= col_cnt;
        end
    end

    // ================================================================
    //                    busy / done 信号
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            busy <= (state != S_IDLE && state != S_DONE);
            done <= (state == S_DONE);
        end
    end

endmodule
