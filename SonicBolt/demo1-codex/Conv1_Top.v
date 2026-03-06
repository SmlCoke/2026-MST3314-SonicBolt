`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 模块名: Conv1_Top
// 功能  : Conv1 顶层（11x7，32 输出通道并行）
// 架构  : LineBuffer + 32xMAC_Tree_77 + Requant/ReLU
// 状态机: IDLE -> LOAD_WEIGHT -> FILL_LB -> CALC_RUN -> DRAIN -> DONE
// -----------------------------------------------------------------------------
module Conv1_Top (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    output reg          busy,
    output reg          done,

    output reg          in_row_req,
    output reg  [4:0]   in_row_addr,
    input  wire [79:0]  in_row_data,
    input  wire         in_row_valid,

    output reg          wgt_req,
    output reg  [5:0]   wgt_addr,
    input  wire [615:0] wgt_data,
    input  wire [15:0]  bias_data,
    input  wire         wgt_valid,

    output wire         out_valid,
    output wire [255:0] out_data
);
    localparam [2:0] S_IDLE        = 3'd0;
    localparam [2:0] S_LOAD_WEIGHT = 3'd1;
    localparam [2:0] S_FILL_LB     = 3'd2;
    localparam [2:0] S_CALC_RUN    = 3'd3;
    localparam [2:0] S_DRAIN       = 3'd4;
    localparam [2:0] S_DONE        = 3'd5;

    reg [2:0] state;

    // 权重与偏置寄存阵列（每个输出通道一组）
    reg [615:0]       weight_bank [0:31];
    reg signed [15:0] bias_bank   [0:31];

    // 控制与计数
    reg [5:0] wgt_load_idx;         // 0~31
    reg [4:0] fill_row_idx;         // 0~10
    reg [4:0] row_cnt;              // 0~19
    reg [1:0] col_cnt;              // 0~3
    reg [4:0] next_row_addr_needed; // row_cnt + 11
    reg       wait_next_row;
    reg [6:0] out_count;            // out_valid 计数，目标 80

    // LineBuffer 写入脉冲
    reg        push_row;
    reg [79:0] push_row_data;

    // MAC 输入 valid
    reg mac_valid_in;

    // LineBuffer 与窗口数据
    wire [879:0] line_flat;
    wire [615:0] act_window_flat;

    // 32 路 MAC 输出
    wire [31:0]   mac_valid_vec;
    wire [1023:0] mac_out_flat;
    wire          mac_valid_mid;

    integer i;
    genvar g;

    conv1_line_buffer u_line_buffer (
        .clk      (clk),
        .rst_n    (rst_n),
        .push_row (push_row),
        .row_in   (push_row_data),
        .line_flat(line_flat)
    );

    conv1_window_extract u_window_extract (
        .line_flat(line_flat),
        .col_cnt  (col_cnt),
        .win_flat (act_window_flat)
    );

    generate
        for (g = 0; g < 32; g = g + 1) begin : GEN_MAC_ARRAY
            MAC_Tree_77 u_mac_tree_77 (
                .clk        (clk),
                .rst_n      (rst_n),
                .valid_in   (mac_valid_in),
                .act_flat_in(act_window_flat),
                .wgt_flat_in(weight_bank[g]),
                .bias_in    (bias_bank[g]),
                .valid_out  (mac_valid_vec[g]),
                .mac_out    (mac_out_flat[g*32 +: 32])
            );
        end
    endgenerate

    assign mac_valid_mid = mac_valid_vec[0];

    requant_relu_vec32 #(
        .M0(16'sd356),
        .N (16)
    ) u_requant_relu_vec32 (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (mac_valid_mid),
        .in_data_flat(mac_out_flat),
        .valid_out  (out_valid),
        .out_data_flat(out_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_IDLE;
            busy                <= 1'b0;
            done                <= 1'b0;
            in_row_req          <= 1'b0;
            in_row_addr         <= 5'd0;
            wgt_req             <= 1'b0;
            wgt_addr            <= 6'd0;
            wgt_load_idx        <= 6'd0;
            fill_row_idx        <= 5'd0;
            row_cnt             <= 5'd0;
            col_cnt             <= 2'd0;
            next_row_addr_needed<= 5'd0;
            wait_next_row       <= 1'b0;
            out_count           <= 7'd0;
            push_row            <= 1'b0;
            push_row_data       <= 80'd0;
            mac_valid_in        <= 1'b0;
            for (i = 0; i < 32; i = i + 1) begin
                weight_bank[i] <= 616'd0;
                bias_bank[i]   <= 16'sd0;
            end
        end else begin
            // 默认信号
            done         <= 1'b0;
            push_row     <= 1'b0;
            push_row_data<= 80'd0;
            mac_valid_in <= 1'b0;

            if (out_valid) begin
                out_count <= out_count + 7'd1;
            end

            case (state)
                S_IDLE: begin
                    busy       <= 1'b0;
                    in_row_req <= 1'b0;
                    wgt_req    <= 1'b0;
                    if (start) begin
                        busy         <= 1'b1;
                        state        <= S_LOAD_WEIGHT;
                        wgt_load_idx <= 6'd0;
                        wgt_req      <= 1'b1;
                        wgt_addr     <= 6'd0;
                        out_count    <= 7'd0;
                    end
                end

                S_LOAD_WEIGHT: begin
                    busy       <= 1'b1;
                    in_row_req <= 1'b0;
                    wgt_req    <= 1'b1;
                    wgt_addr   <= wgt_load_idx;
                    if (wgt_valid) begin
                        weight_bank[wgt_load_idx] <= wgt_data;
                        bias_bank[wgt_load_idx]   <= $signed(bias_data);
                        if (wgt_load_idx == 6'd31) begin
                            state        <= S_FILL_LB;
                            wgt_req      <= 1'b0;
                            fill_row_idx <= 5'd0;
                            in_row_req   <= 1'b1;
                            in_row_addr  <= 5'd0;
                        end else begin
                            wgt_load_idx <= wgt_load_idx + 6'd1;
                        end
                    end
                end

                S_FILL_LB: begin
                    busy       <= 1'b1;
                    wgt_req    <= 1'b0;
                    in_row_req <= 1'b1;
                    in_row_addr<= fill_row_idx;
                    if (in_row_valid) begin
                        push_row      <= 1'b1;
                        push_row_data <= in_row_data;
                        if (fill_row_idx == 5'd10) begin
                            state         <= S_CALC_RUN;
                            in_row_req    <= 1'b0;
                            row_cnt       <= 5'd0;
                            col_cnt       <= 2'd0;
                            wait_next_row <= 1'b0;
                            out_count     <= 7'd0;
                        end else begin
                            fill_row_idx <= fill_row_idx + 5'd1;
                        end
                    end
                end

                S_CALC_RUN: begin
                    busy    <= 1'b1;
                    wgt_req <= 1'b0;

                    if (wait_next_row) begin
                        in_row_req  <= 1'b1;
                        in_row_addr <= next_row_addr_needed;
                        if (in_row_valid) begin
                            push_row      <= 1'b1;
                            push_row_data <= in_row_data;
                            in_row_req    <= 1'b0;
                            wait_next_row <= 1'b0;
                            row_cnt       <= row_cnt + 5'd1;
                            col_cnt       <= 2'd0;
                        end
                    end else begin
                        in_row_req  <= 1'b0;
                        mac_valid_in<= 1'b1;

                        if (col_cnt == 2'd3) begin
                            if (row_cnt == 5'd19) begin
                                state <= S_DRAIN;
                            end else begin
                                wait_next_row        <= 1'b1;
                                next_row_addr_needed <= row_cnt + 5'd11;
                            end
                        end else begin
                            col_cnt <= col_cnt + 2'd1;
                        end
                    end
                end

                S_DRAIN: begin
                    busy       <= 1'b1;
                    in_row_req <= 1'b0;
                    wgt_req    <= 1'b0;
                    if (out_count == 7'd80) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    busy       <= 1'b0;
                    done       <= 1'b1;
                    in_row_req <= 1'b0;
                    wgt_req    <= 1'b0;
                    state      <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

