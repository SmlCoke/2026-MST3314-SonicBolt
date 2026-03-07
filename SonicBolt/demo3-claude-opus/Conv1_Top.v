// ===========================================================================
// 文件名: Conv1_Top.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   Conv1 顶层模块 — 第一层标准卷积的完整硬件实现
//   包含 FSM 控制逻辑、数据通路集成。
//
//   卷积规格:
//     输入: (1, 30, 10) INT8
//     权重: (32, 1, 11, 7) INT8
//     偏置: (32) INT16
//     输出: (32, 20, 4) INT8（仅重量化，保留 pre-ReLU 结果）
//     stride=1, padding=0
//
//   数据通路:
//     [Line Buffer] → [Window Extract] → 广播 → [32× MAC_Tree_77]
//       → [requant_relu_vec32] → out_data
//
//   FSM 状态:
//     S_IDLE → S_LOAD_PARAM (32 cyc) → S_FILL_LB (11 cyc)
//       → S_CALC (80+ cyc) → S_DRAIN (5 cyc) → S_DONE
//
//   性能: 11 + 80 + 5 = 96 周期/帧 → @100MHz = 1042K FPS
//
// ---------------------------------------------------------------------------
// 接口说明:
//   控制接口:
//     start         — 启动信号（单周期脉冲）
//     busy          — 正在工作中
//     done          — 完成信号（单周期脉冲）
//
//   输入特征图 SRAM 接口:
//     in_row_addr   — 行地址 (0~29)
//     in_row_data   — 行数据 (10×INT8 = 80-bit)
//     in_row_valid  — 行数据有效
//
//   权重/偏置 SRAM 接口:
//     wgt_addr      — 通道地址 (0~31)
//     wgt_data      — 完整权重 (77×INT8 = 616-bit)
//     bias_data     — 偏置 (INT16)
//     wgt_valid     — 权重数据有效
//
//   输出接口:
//     out_valid     — 输出有效（每次携带一个空间位置的 32 通道数据）
//     out_data      — 32×INT8 输出 (256-bit, ch[0]在低位)
// ===========================================================================

module Conv1_Top (
    input  wire               clk,
    input  wire               rst_n,

    // 控制接口
    input  wire               start,
    output reg                busy,
    output reg                done,

    // 输入特征图 SRAM 接口
    output reg  [4:0]         in_row_addr,
    input  wire [79:0]        in_row_data,
    input  wire               in_row_valid,

    // 权重/偏置 SRAM 接口
    output reg  [4:0]         wgt_addr,
    input  wire [615:0]       wgt_data,  // 77 个 INT8
    input  wire [15:0]        bias_data,
    input  wire               wgt_valid,

    // 输出接口
    output wire               out_valid,
    output wire [255:0]       out_data
);

    // ==================================================================
    // 参数定义
    // ==================================================================
    localparam KH          = 11;        // 卷积核高度
    localparam KW          = 7;         // 卷积核宽度
    localparam IH          = 30;        // 输入特征图高度
    localparam IW          = 10;        // 输入特征图宽度
    localparam OH          = 20;        // 输出特征图高度 = IH - KH + 1
    localparam OW          = 4;         // 输出特征图宽度 = IW - KW + 1
    localparam OC          = 32;        // 输出通道数
    localparam PIPE_DEPTH  = 5;         // MAC(3) + requant(2) 流水线深度

    // FSM 状态编码
    localparam S_IDLE       = 3'd0;
    localparam S_LOAD_PARAM = 3'd1;
    localparam S_FILL_LB    = 3'd2;
    localparam S_CALC       = 3'd3;
    localparam S_DRAIN      = 3'd4;
    localparam S_DONE       = 3'd5;

    // ==================================================================
    // FSM 状态寄存器
    // ==================================================================
    reg [2:0] state, state_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // ==================================================================
    // 片上寄存器文件：存储 32 通道的权重和偏置
    // ==================================================================
    reg [615:0] weight_reg [0:31];  // 32 × 616-bit 权重
    reg [15:0]  bias_reg   [0:31];  // 32 × 16-bit 偏置

    // ==================================================================
    // 计数器
    // ==================================================================
    reg [4:0] load_cnt;     // 参数加载计数 (0~31)
    reg [3:0] fill_cnt;     // 已完成填充的行数计数 (0~11)
    reg [4:0] row_cnt;      // 输出行计数 (0~19)
    reg [1:0] col_cnt;      // 输出列计数 (0~3)
    reg [2:0] drain_cnt;    // 排空计数 (0~PIPE_DEPTH-1)
    reg [4:0] next_row_addr; // 下一行要读的地址

    // 行缓冲中最旧行在输入特征图中的起始行号
    // 在 FILL_LB 结束后 = 0，每次 push 新行后递增
    reg [4:0] lb_start_row;

    // ==================================================================
    // 行缓冲器实例
    // ==================================================================
    wire       lb_push_en;
    wire [79:0] lb_push_data;
    wire [879:0] lb_row_data;

    assign lb_push_en = in_row_valid &&
                        ((state == S_FILL_LB) || (state == S_CALC && wait_row));
    assign lb_push_data = in_row_data;

    conv1_line_buffer u_line_buffer (
        .clk       (clk),
        .rst_n     (rst_n),
        .push_en   (lb_push_en),
        .push_data (lb_push_data),
        .row_data  (lb_row_data)
    );

    // ==================================================================
    // 窗口提取器实例（纯组合逻辑）
    // ==================================================================
    wire [615:0] win_flat;

    conv1_window_extract u_window_ext (
        .row_data  (lb_row_data),
        .col_cnt   (col_cnt),
        .win_flat  (win_flat)
    );

    // ==================================================================
    // 32 通道 MAC 树 + 重量化
    // ==================================================================
    // MAC 输出汇总（32 × INT32 = 1024-bit）
    wire [1023:0] mac_out_flat;
    wire          mac_valid_out;

    // 每个 MAC 树输入：共享窗口数据 win_flat，各使用自己的 weight_reg/bias_reg
    wire         mac_valid_in;

    assign mac_valid_in = (state == S_CALC) && !wait_row;

    genvar ch;
    generate
        for (ch = 0; ch < OC; ch = ch + 1) begin : gen_mac
            wire signed [31:0] mac_result;
            wire               mac_v_out;

            MAC_Tree_77 u_mac (
                .clk       (clk),
                .rst_n     (rst_n),
                .valid_in  (mac_valid_in),
                .act_flat  (win_flat),
                .wgt_flat  (weight_reg[ch]),
                .bias_in   (bias_reg[ch]),
                .valid_out (mac_v_out),
                .mac_out   (mac_result)
            );

            assign mac_out_flat[ch*32 +: 32] = mac_result;

            // 取 ch==0 的 valid 作为代表
            if (ch == 0) begin : gen_valid
                assign mac_valid_out = mac_v_out;
            end
        end
    endgenerate

    // Conv1 golden 为 pre-ReLU 输出，因此此处仅做 requant，不做 ReLU
    requant_relu_vec32 #(
        .M0       (16'sd111),
        .N        (14),
        .USE_RELU (0)
    ) u_requant (
        .clk           (clk),
        .rst_n         (rst_n),
        .valid_in      (mac_valid_out),
        .in_data_flat  (mac_out_flat),
        .valid_out     (out_valid),
        .out_data_flat (out_data)
    );

    // ==================================================================
    // 等待输入行数据的控制信号
    // ==================================================================
    reg wait_row;           // 正在等待新行数据
    reg row_req_sent;       // 已发送行请求

    // ==================================================================
    // FSM 状态转移逻辑
    // ==================================================================
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: begin
                if (start)
                    state_next = S_LOAD_PARAM;
            end

            S_LOAD_PARAM: begin
                if (wgt_valid && load_cnt == 5'd31)
                    state_next = S_FILL_LB;
            end

            S_FILL_LB: begin
                if (fill_cnt == 4'd11 && !row_req_sent && !in_row_valid)
                    state_next = S_CALC;
            end

            S_CALC: begin
                // 所有 80 个输出位置已发射到流水线
                if (row_cnt == 5'd19 && col_cnt == 2'd3)
                    state_next = S_DRAIN;
            end

            S_DRAIN: begin
                if (drain_cnt == PIPE_DEPTH[2:0] - 3'd1)
                    state_next = S_DONE;
            end

            S_DONE: begin
                state_next = S_IDLE;
            end

            default: state_next = S_IDLE;
        endcase
    end

    // ==================================================================
    // FSM 输出与数据通路控制
    // ==================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy          <= 1'b0;
            done          <= 1'b0;
            load_cnt      <= 5'd0;
            fill_cnt      <= 4'd0;
            row_cnt       <= 5'd0;
            col_cnt       <= 2'd0;
            drain_cnt     <= 3'd0;
            in_row_addr   <= 5'd0;
            wgt_addr      <= 5'd0;
            lb_start_row  <= 5'd0;
            next_row_addr <= 5'd0;
            wait_row      <= 1'b0;
            row_req_sent  <= 1'b0;
        end else begin
            // 默认值
            done         <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                // S_IDLE: 等待启动
                // ----------------------------------------------------------
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy          <= 1'b1;
                        load_cnt      <= 5'd0;
                        wgt_addr      <= 5'd0;
                        fill_cnt      <= 4'd0;
                        row_cnt       <= 5'd0;
                        col_cnt       <= 2'd0;
                        drain_cnt     <= 3'd0;
                        lb_start_row  <= 5'd0;
                        next_row_addr <= 5'd0;
                        wait_row      <= 1'b0;
                        row_req_sent  <= 1'b0;
                    end
                end

                // ----------------------------------------------------------
                // S_LOAD_PARAM: 逐周期从外部 SRAM 读取权重和偏置
                //   每周期请求一个通道的 weight + bias
                //   当 wgt_valid 来时存入寄存器并递增计数器
                // ----------------------------------------------------------
                S_LOAD_PARAM: begin
                    if (wgt_valid) begin
                        weight_reg[load_cnt] <= wgt_data;
                        bias_reg[load_cnt]   <= bias_data;
                        if (load_cnt < 5'd31) begin
                            load_cnt <= load_cnt + 5'd1;
                            wgt_addr <= load_cnt + 5'd1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // S_FILL_LB: 逐周期读取前 11 行输入，填充行缓冲
                // ----------------------------------------------------------
                S_FILL_LB: begin
                    if (state != state_next) begin
                        // 即将离开此状态时不再发请求
                    end else if (!row_req_sent) begin
                            in_row_addr  <= {1'b0, fill_cnt};
                        row_req_sent <= 1'b1;
                    end

                    if (in_row_valid) begin
                        row_req_sent <= 1'b0;

                        if (fill_cnt < 4'd11) begin
                            fill_cnt <= fill_cnt + 4'd1;
                        end
                    end
                end

                // ----------------------------------------------------------
                // S_CALC: 核心计算阶段
                //   遍历 20×4 = 80 个输出位置
                //   每周期提取一个窗口，广播到 32 个 MAC 树
                //
                //   行切换逻辑:
                //     col_cnt 从 0 到 3 递增
                //     col_cnt==3 完成后：
                //       - 如果 row_cnt < 19，push 新行（地址 = row_cnt + 11）
                //       - row_cnt 递增，col_cnt 归零
                //       - 等待新行到来后继续计算
                // ----------------------------------------------------------
                S_CALC: begin
                    if (!wait_row) begin
                        if (col_cnt < 2'd3) begin
                            col_cnt <= col_cnt + 2'd1;
                        end else begin
                            // col_cnt == 3，本行最后一个位置
                            col_cnt <= 2'd0;

                            if (row_cnt < 5'd19) begin
                                // 还有下一行要处理
                                row_cnt       <= row_cnt + 5'd1;
                                next_row_addr <= lb_start_row + KH[4:0];
                                wait_row      <= 1'b1;
                                row_req_sent  <= 1'b0;
                            end
                            // row_cnt == 19 时不需要新行，FSM 会转到 S_DRAIN
                        end
                    end else begin
                        // 等待新行到来
                        if (!row_req_sent) begin
                            in_row_addr  <= next_row_addr;
                            row_req_sent <= 1'b1;
                        end

                        if (in_row_valid) begin
                            lb_start_row  <= lb_start_row + 5'd1;
                            wait_row      <= 1'b0;
                            row_req_sent  <= 1'b0;
                        end
                    end
                end

                // ----------------------------------------------------------
                // S_DRAIN: 等待流水线排空
                // ----------------------------------------------------------
                S_DRAIN: begin
                    drain_cnt <= drain_cnt + 3'd1;
                end

                // ----------------------------------------------------------
                // S_DONE: 输出完成信号
                // ----------------------------------------------------------
                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end

                default: ;
            endcase
        end
    end

endmodule
