// ===========================================================================
// 文件名: tb_Conv1.v
// 作者  : SonicBolt Team
// 日期  : 2026-03-07
// 版本  : v1.0
// ---------------------------------------------------------------------------
// 功能描述:
//   Conv1 顶层模块的 Testbench，用于验证第一层卷积的功能正确性。
//
//   测试流程:
//     1. 从 hex 文件加载输入特征图、权重、偏置、golden 输出
//     2. 模拟外部 SRAM 响应（1 拍读延迟）
//     3. 启动 Conv1_Top，等待计算完成
//     4. 逐周期比对 out_data 与 golden 数据
//     5. 将硬件输出写入 hw_output.txt 供离线对比
//
//   数据文件:
//     conv1_input.hex   — 30 × 80-bit  输入特征图
//     conv1_weight.hex  — 32 × 616-bit 权重
//     conv1_bias.hex    — 32 × 16-bit  偏置
//     conv1_golden.hex  — 80 × 256-bit golden 输出
// ===========================================================================

`timescale 1ns / 1ps

module tb_Conv1;

    // ==================================================================
    // 参数
    // ==================================================================
    localparam CLK_PERIOD = 10;         // 时钟周期 10ns = 100MHz
    localparam TIMEOUT    = 50000;      // 超时周期数

    // ==================================================================
    // 信号声明
    // ==================================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    wire        busy;
    wire        done;

    // 输入 SRAM 接口
    wire [4:0]  in_row_addr;
    reg  [79:0] in_row_data;
    reg         in_row_valid;

    // 权重 SRAM 接口
    wire [4:0]  wgt_addr;
    reg  [615:0] wgt_data;
    reg  [15:0] bias_data;
    reg         wgt_valid;

    // 输出接口
    wire        out_valid;
    wire [255:0] out_data;

    // ==================================================================
    // DUT 实例化
    // ==================================================================
    Conv1_Top u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .busy         (busy),
        .done         (done),
        .in_row_addr  (in_row_addr),
        .in_row_data  (in_row_data),
        .in_row_valid (in_row_valid),
        .wgt_addr     (wgt_addr),
        .wgt_data     (wgt_data),
        .bias_data    (bias_data),
        .wgt_valid    (wgt_valid),
        .out_valid    (out_valid),
        .out_data     (out_data)
    );

    // ==================================================================
    // 数据存储
    // ==================================================================
    reg [79:0]  input_mem  [0:29];     // 30 行输入
    reg [615:0] weight_mem [0:31];     // 32 通道权重
    reg [15:0]  bias_mem   [0:31];     // 32 通道偏置
    reg [255:0] golden_mem [0:79];     // 80 个golden输出

    // ==================================================================
    // 时钟生成
    // ==================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ==================================================================
    // 文件 I/O
    // ==================================================================
    integer fout;              // 输出文件句柄
    integer out_count;         // 输出计数
    integer error_count;       // 错误计数
    integer cycle_count;       // 周期计数

    // ==================================================================
    // 加载数据文件
    // ==================================================================
    initial begin
        $readmemh("conv1_input.hex",  input_mem);
        $readmemh("conv1_weight.hex", weight_mem);
        $readmemh("conv1_bias.hex",   bias_mem);
        $readmemh("conv1_golden.hex", golden_mem);
    end

    // ==================================================================
    // 模拟外部输入 SRAM（1 拍读延迟）
    // 当 DUT 输出 in_row_addr 时，下一个时钟沿返回数据
    // ==================================================================
    reg [4:0] in_row_addr_pending;
    reg       in_row_pending;
    wire      in_row_req;

    assign in_row_req = (u_dut.state == 3'd2 && u_dut.row_req_sent) ||
                        (u_dut.state == 3'd3 && u_dut.wait_row && u_dut.row_req_sent);

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_row_valid        <= 1'b0;
            in_row_data         <= 80'd0;
            in_row_addr_pending <= 5'd0;
            in_row_pending      <= 1'b0;
        end else if (in_row_pending) begin
            in_row_valid   <= 1'b1;
            in_row_data    <= input_mem[in_row_addr_pending];
            in_row_pending <= 1'b0;
        end else begin
            in_row_valid <= 1'b0;
            if (in_row_req) begin
                in_row_addr_pending <= in_row_addr;
                in_row_pending      <= 1'b1;
            end
        end
    end

    // ==================================================================
    // 模拟外部权重 SRAM（1 拍读延迟）
    // ==================================================================
    reg [4:0] wgt_addr_pending;
    reg       wgt_pending;
    wire      wgt_req;

    assign wgt_req = (u_dut.state == 3'd1); // S_LOAD_PARAM

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgt_valid        <= 1'b0;
            wgt_data         <= 616'd0;
            bias_data        <= 16'd0;
            wgt_addr_pending <= 5'd0;
            wgt_pending      <= 1'b0;
        end else if (wgt_pending) begin
            wgt_valid   <= 1'b1;
            wgt_data    <= weight_mem[wgt_addr_pending];
            bias_data   <= bias_mem[wgt_addr_pending];
            wgt_pending <= 1'b0;
        end else begin
            wgt_valid <= 1'b0;
            if (wgt_req) begin
                wgt_addr_pending <= wgt_addr;
                wgt_pending      <= 1'b1;
            end
        end
    end

    // ==================================================================
    // 输出验证与文件写入
    // ==================================================================
    integer ch_idx;
    reg [7:0] hw_byte;
    reg [7:0] gd_byte;

    always @(posedge clk) begin
        if (out_valid === 1'b1) begin
            // 写入输出文件：每行 32 个 hex 字节，空格分隔
            for (ch_idx = 0; ch_idx < 32; ch_idx = ch_idx + 1) begin
                hw_byte = out_data[ch_idx*8 +: 8];
                if (ch_idx < 31)
                    $fwrite(fout, "%02x ", hw_byte);
                else
                    $fwrite(fout, "%02x", hw_byte);
            end
            $fwrite(fout, "\n");

            // 逐通道比对
            for (ch_idx = 0; ch_idx < 32; ch_idx = ch_idx + 1) begin
                hw_byte = out_data[ch_idx*8 +: 8];
                gd_byte = golden_mem[out_count][ch_idx*8 +: 8];
                if (hw_byte !== gd_byte) begin
                    $display("[ERROR] out_idx=%0d ch=%0d: HW=0x%02x, Golden=0x%02x",
                             out_count, ch_idx, hw_byte, gd_byte);
                    error_count = error_count + 1;
                end
                else begin
                    $display("[INFO] out_idx=%0d ch=%0d: HW=0x%02x, Golden=0x%02x",
                             out_count, ch_idx, hw_byte, gd_byte);
                end
            end

            out_count = out_count + 1;
        end
    end

    // ==================================================================
    // 主测试流程
    // ==================================================================
    initial begin
        // 初始化
        rst_n       = 1'b0;
        start       = 1'b0;
        out_count   = 0;
        error_count = 0;
        cycle_count = 0;

        // 打开输出文件
        fout = $fopen("hw_output.txt", "w");
        if (fout == 0) begin
            $display("[FATAL] Cannot open hw_output.txt");
            $finish;
        end

        // 复位
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 启动
        $display("====================================================");
        $display("[INFO] Conv1 testbench started");
        $display("====================================================");
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // 等待完成
        while (!done && cycle_count < TIMEOUT) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        // 结果汇总
        $display("====================================================");
        if (cycle_count >= TIMEOUT) begin
            $display("[FATAL] Simulation timeout after %0d cycles", cycle_count);
        end else begin
            $display("[INFO] Conv1 finished in %0d cycles", cycle_count);
        end

        $display("[INFO] Output count: %0d (expected: 80)", out_count);

        if (out_count != 80) begin
            $display("[ERROR] Output count mismatch: expected 80, got %0d", out_count);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("[PASS] *** All tests passed! ***");
        else
            $display("[FAIL] *** Detected %0d errors ***", error_count);

        $display("====================================================");

        // 关闭文件
        $fclose(fout);

        // 结束仿真
        #100;
        $finish;
    end

    // ==================================================================
    // 波形输出（可选，用于调试）
    // ==================================================================
    initial begin
        $dumpfile("conv1_wave.vcd");
        $dumpvars(0, tb_Conv1);
    end

endmodule
