// ============================================================================
// Testbench: tb_Conv1
// Description: Conv1_Top 仿真验证平台
//
// 功能概述：
//   1. 使用 $readmemh 从 input.txt, weight.txt, bias.txt 加载测试数据
//   2. 通过 FSM 接口驱动 Conv1_Top 完成一次完整推理
//   3. 将输出结果保存到 hw_output.txt (每行 32 个 hex 值，空格分隔)
//   4. 与 golden_output.txt 金标准进行自动比对
//
// 文件格式：
//   input.txt         — 300 行，每行 1 个 2 位 hex (INT8 输入)
//   weight.txt        — 2464 行，每行 1 个 2 位 hex (INT8 权重)
//   bias.txt          — 32 行，每行 1 个 4 位 hex (INT16 偏置)
//   golden_output.txt — 80 行，每行 32 个 2 位 hex (INT8 输出)
//   hw_output.txt     — 仿真输出文件
//
// 使用方法：
//   1. 运行 gen_testvec.py 生成测试向量到 sim/ 目录
//   2. 使用 iverilog/vcs/modelsim 等仿真器运行此 testbench
// ============================================================================

`timescale 1ns / 1ps

module tb_Conv1;

    // ======================== 时钟参数 ========================
    parameter CLK_PERIOD = 10;      // 100 MHz
    parameter HALF_CLK   = CLK_PERIOD / 2;

    // ======================== 信号声明 ========================
    reg         clk;
    reg         rst_n;
    reg         start;

    // 权重加载
    reg  [7:0]  wt_data;
    reg         wt_valid;

    // 偏置加载
    reg  [15:0] bias_data;
    reg         bias_valid;

    // 输入 SRAM 接口
    wire [4:0]  input_row_addr;
    wire        input_rd_en;
    reg  [79:0] input_row_data;

    // 输出接口
    wire [255:0] output_data;
    wire        output_valid;
    wire [4:0]  output_row;
    wire [1:0]  output_col;
    wire        busy;
    wire        done;

    // ======================== 测试数据存储 ========================
    reg [7:0]  input_mem  [0:299];    // 300 个 INT8 输入值
    reg [7:0]  weight_mem [0:2463];   // 2464 个 INT8 权重
    reg [15:0] bias_mem   [0:31];     // 32 个 INT16 偏置
    reg [7:0]  golden_mem [0:2559];   // 32×80 个 INT8 金标准输出

    // ======================== 输入 SRAM ========================
    // 将 300 个 INT8 值组织为 30 行 × 10 列
    // 每行 80 bits = 10 × INT8
    reg [79:0] input_sram [0:29];

    // ======================== 输出文件句柄 ========================
    integer fd_out;

    // ======================== 验证计数器 ========================
    integer pass_cnt;
    integer fail_cnt;
    integer total_cnt;
    integer golden_idx;

    // ======================== 循环变量 ========================
    integer i, j, row_i, col_i, ch_i;

    // ================================================================
    //                        DUT 实例化
    // ================================================================
    Conv1_Top dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .busy           (busy),
        .done           (done),
        .wt_data_i      (wt_data),
        .wt_valid_i     (wt_valid),
        .bias_data_i    (bias_data),
        .bias_valid_i   (bias_valid),
        .input_row_addr (input_row_addr),
        .input_rd_en    (input_rd_en),
        .input_row_data (input_row_data),
        .output_data    (output_data),
        .output_valid   (output_valid),
        .output_row     (output_row),
        .output_col     (output_col)
    );

    // ================================================================
    //                       时钟生成
    // ================================================================
    initial begin
        clk = 1'b0;
        forever #HALF_CLK clk = ~clk;
    end

    // ================================================================
    //                    输入 SRAM 组合读取
    // ================================================================
    // 模拟外部 SRAM：地址有效后，同周期输出数据（组合逻辑）
    always @(*) begin
        if (input_rd_en)
            input_row_data = input_sram[input_row_addr];
        else
            input_row_data = 80'd0;
    end

    // ================================================================
    //                      主仿真流程
    // ================================================================
    initial begin
        // ==================== 初始化 ====================
        rst_n     = 1'b0;
        start     = 1'b0;
        wt_data   = 8'd0;
        wt_valid  = 1'b0;
        bias_data = 16'd0;
        bias_valid = 1'b0;
        pass_cnt  = 0;
        fail_cnt  = 0;
        total_cnt = 0;
        golden_idx = 0;

        // ==================== 加载测试数据 ====================
        $display("========================================");
        $display(" Conv1 RTL Testbench");
        $display("========================================");
        $display("[INFO] Loading test vectors...");

        $readmemh("input.txt",  input_mem);
        $readmemh("weight.txt", weight_mem);
        $readmemh("bias.txt",   bias_mem);

        // 尝试加载金标准输出（用于比对）
        // golden_output.txt 中每行 32 个 hex 值，共 80 行
        // 需要先转换为一维数组
        load_golden_output();

        // ---------- 将输入数据重组为 SRAM 格式 ----------
        // 每行 10 个 INT8 → 80 bits, pixel[0] 在 [7:0], pixel[9] 在 [79:72]
        for (row_i = 0; row_i < 30; row_i = row_i + 1) begin
            input_sram[row_i] = {
                input_mem[row_i * 10 + 9],
                input_mem[row_i * 10 + 8],
                input_mem[row_i * 10 + 7],
                input_mem[row_i * 10 + 6],
                input_mem[row_i * 10 + 5],
                input_mem[row_i * 10 + 4],
                input_mem[row_i * 10 + 3],
                input_mem[row_i * 10 + 2],
                input_mem[row_i * 10 + 1],
                input_mem[row_i * 10 + 0]
            };
        end
        $display("[INFO] Input SRAM loaded: 30 rows x 10 pixels");

        // ==================== 打开输出文件 ====================
        fd_out = $fopen("hw_output.txt", "w");
        if (fd_out == 0) begin
            $display("[ERROR] Cannot open hw_output.txt for writing!");
            $finish;
        end

        // ==================== 复位释放 ====================
        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // ==================== 启动 ====================
        // 注意: 使用 @(negedge clk) 来设置输入信号
        // 确保信号在下一个上升沿之前稳定，避免 setup time 竞争
        $display("[INFO] Starting Conv1...");
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // ==================== 加载权重 ====================
        $display("[INFO] Loading weights (2464 cycles)...");
        for (i = 0; i < 2464; i = i + 1) begin
            @(negedge clk);
            wt_data  = weight_mem[i];
            wt_valid = 1'b1;
        end
        @(negedge clk);
        wt_valid = 1'b0;
        $display("[INFO] Weights loaded.");

        // ==================== 加载偏置 ====================
        $display("[INFO] Loading biases (32 cycles)...");
        for (i = 0; i < 32; i = i + 1) begin
            @(negedge clk);
            bias_data  = bias_mem[i];
            bias_valid = 1'b1;
        end
        @(negedge clk);
        bias_valid = 1'b0;
        $display("[INFO] Biases loaded.");

        // ==================== 等待计算完成 ====================
        $display("[INFO] Waiting for computation...");
        wait(done == 1'b1);
        @(posedge clk);

        // ==================== 关闭文件并报告 ====================
        $fclose(fd_out);

        $display("========================================");
        $display(" Verification Results");
        $display("========================================");
        $display("  Total outputs : %0d", total_cnt);
        $display("  PASS          : %0d", pass_cnt);
        $display("  FAIL          : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL TESTS PASSED! <<<");
        else
            $display("  >>> SOME TESTS FAILED! <<<");
        $display("========================================");

        #(CLK_PERIOD * 10);
        $finish;
    end

    // ================================================================
    //                  输出捕获与验证
    // ================================================================
    // 在 output_valid 有效时：
    //   1. 将 32 个通道值写入 hw_output.txt
    //   2. 与 golden 比对

    always @(posedge clk) begin
        if (output_valid) begin
            // ---------- 写入 hw_output.txt ----------
            // 格式: 32 个 2 位 hex，空格分隔
            write_output_line();

            // ---------- 与金标准比对 ----------
            verify_output();

            total_cnt = total_cnt + 1;
        end
    end

    // ================================================================
    //                      辅助任务
    // ================================================================

    // ---------- 加载金标准输出 ----------
    // golden_output.txt: 80 行, 每行 32 个 hex 值
    // 转为 golden_mem[line*32 + ch]
    task load_golden_output;
        reg [7:0] golden_line [0:31];
        integer line_i, ch_j;
    begin
        // 使用 $readmemh 无法直接处理空格分隔的多值行
        // 因此使用 $fopen / $fscanf 逐行读取
        begin : load_golden_block
            integer fd_golden;
            integer scan_ret;
            reg [7:0] val;

            fd_golden = $fopen("golden_output.txt", "r");
            if (fd_golden == 0) begin
                $display("[WARN] golden_output.txt not found, skipping verification.");
                disable load_golden_block;
            end

            for (line_i = 0; line_i < 80; line_i = line_i + 1) begin
                for (ch_j = 0; ch_j < 32; ch_j = ch_j + 1) begin
                    scan_ret = $fscanf(fd_golden, "%h", val);
                    golden_mem[line_i * 32 + ch_j] = val;
                end
            end

            $fclose(fd_golden);
            $display("[INFO] Golden output loaded: 80 x 32 values");
        end
    end
    endtask

    // ---------- 写入输出文件 ----------
    task write_output_line;
        integer ch_k;
        reg [7:0] out_val;
    begin
        for (ch_k = 0; ch_k < 32; ch_k = ch_k + 1) begin
            out_val = output_data[ch_k * 8 +: 8];
            if (ch_k == 0)
                $fwrite(fd_out, "%02h", out_val);
            else
                $fwrite(fd_out, " %02h", out_val);
        end
        $fwrite(fd_out, "\n");
    end
    endtask

    // ---------- 验证输出 ----------
    task verify_output;
        integer ch_k;
        reg [7:0] hw_val;
        reg [7:0] gd_val;
        reg line_pass;
    begin
        line_pass = 1'b1;
        for (ch_k = 0; ch_k < 32; ch_k = ch_k + 1) begin
            hw_val = output_data[ch_k * 8 +: 8];
            gd_val = golden_mem[golden_idx * 32 + ch_k];
            if (hw_val !== gd_val) begin
                line_pass = 1'b0;
                $display("[FAIL] Row=%0d, Col=%0d, Ch=%0d: expected=%02h, got=%02h",
                         output_row, output_col, ch_k, gd_val, hw_val);
            end
        end

        if (line_pass) begin
            pass_cnt = pass_cnt + 1;
        end else begin
            fail_cnt = fail_cnt + 1;
        end

        golden_idx = golden_idx + 1;
    end
    endtask

    // ================================================================
    //                     波形 dump
    // ================================================================
    initial begin
        $dumpfile("tb_Conv1.vcd");
        $dumpvars(0, tb_Conv1);
    end

    // ================================================================
    //                     超时保护
    // ================================================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
