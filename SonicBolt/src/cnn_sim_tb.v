`timescale 1ns / 1ps
/*
 * 模块名称: cnn_sim_tb
 * 作者: SonicBolt Team
 * 日期: 2026-04-08
 * 版本: v1.1
 *
 * 总结:
 *   简化的多样本连续仿真测试平台。
 *   该测试平台只保留当前顶层需要的输入提交流程，
 *   但只打印两种类型的日志:
 *     - SIM_OUTPUT sample=<dataset_id> data=<16hex>
 *     - SAMPLE_DONE sample=<dataset_id> cycles=<cycle>
 *
 * 说明:
 *   1. START_SAMPLE / SAMPLE_COUNT 通过 plusargs 传递。
 *   2. 按样本加载输入行文件:
 *      <PREP_DIR>/samples/<id>_input_rows.mem
 *   3. 权重 / 偏置 / Sigmoid LUT 已由 RTL 内部 ROM 固化。
 */

module cnn_sim_tb #(
    parameter integer ENABLE_WAVE = 0
) ();

    // 基本仿真参数。
    localparam integer CLK_HALF_PERIOD   = 5;
    localparam integer INPUT_ROW_COUNT   = 30;

    // DUT 顶层控制和状态信号。
    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;

    // 输入帧写入接口。
    reg [4:0]  img_wr_addr;
    reg        img_wr_en;
    reg [79:0] img_wr_row_word;
    reg        img_wr_commit;
    wire       img_wr_ready;

    // CNN 输出流。
    wire         out_stream_valid;
    wire [63:0]  out_stream_data;

    // 本地存储数组。
    reg [79:0]   input_rows_mem          [0:INPUT_ROW_COUNT-1];

    // 运行时控制。
    integer timeout_cycles;
    integer cycle_counter;
    integer runtime_wave_enable;
    integer runtime_sample_count;
    integer runtime_start_sample;
    integer sample_done_counter;
    integer sample_output_counter;

    integer row_idx;
    integer sample_idx;
    integer current_dataset_sample_id;

    // 路径字符串。
    string prep_dir;
    string input_mem_path;
    string wave_file_path;

    // DUT 实例化。
    cnn #(
        .CONV_M0(111),
        .CONV_SHIFT_N(14),
        .DWCONV_M0(59),
        .DWCONV_SHIFT_N(11),
        .PWCONV_M0(69),
        .PWCONV_SHIFT_N(13),
        .FC_M0(11),
        .FC_SHIFT_N(15)
    ) cnn_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_row_data(img_wr_row_word),
        .img_wr_commit(img_wr_commit),
        .img_wr_ready(img_wr_ready),
        .out_stream_valid(out_stream_valid),
        .out_stream_data(out_stream_data)
    );

    // 10ns 周期时钟。
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // 初始化所有驱动信号和计数器。
    task automatic init_signals;
        begin
            clk = 1'b0;
            rst_n = 1'b0;
            start = 1'b0;
            img_wr_en = 1'b0;
            img_wr_addr = 5'd0;
            img_wr_row_word = 80'd0;
            img_wr_commit = 1'b0;

            timeout_cycles = 4000;
            runtime_wave_enable = ENABLE_WAVE;
            runtime_sample_count = 5;
            runtime_start_sample = 0;

            cycle_counter = 0;
            sample_done_counter = 0;
            sample_output_counter = 0;
        end
    endtask

    // 解析 plusargs 并构建输入文件路径前缀。
    task automatic parse_plusargs;
        begin
            prep_dir = "";
            wave_file_path = "";

            if (!$value$plusargs("PREP_DIR=%s", prep_dir)) begin
                $display("TB_ERROR missing +PREP_DIR");
                $finish_and_return(2);
            end
            if ($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles)) begin
            end
            if ($value$plusargs("SAMPLE_COUNT=%d", runtime_sample_count)) begin
            end
            if ($value$plusargs("START_SAMPLE=%d", runtime_start_sample)) begin
            end
            if ($test$plusargs("WAVE")) begin
                runtime_wave_enable = 1;
            end
            if ($value$plusargs("WAVE=%d", runtime_wave_enable)) begin
            end
            if (!$value$plusargs("WAVE_FILE=%s", wave_file_path)) begin
                wave_file_path = "cnn_sim_tb.vcd";
            end
        end
    endtask

    // 轮询循环中的统一超时保护。
    task automatic check_timeout;
        begin
            if (cycle_counter > timeout_cycles) begin
                $display("TB_ERROR timeout cycles=%0d", cycle_counter);
                $finish_and_return(3);
            end
        end
    endtask

    // 根据数据集 id 加载一个样本的输入行文件。
    task automatic load_input_rows_by_sample_id(input integer dataset_sample_id);
        begin
            input_mem_path = $sformatf("%0s/samples/%0d_input_rows.mem", prep_dir, dataset_sample_id);
            $readmemh(input_mem_path, input_rows_mem);
        end
    endtask

    // 应用同步释放的低有效复位。
    task automatic apply_reset;
        begin
            repeat (4) @(posedge clk);
            rst_n <= 1'b1;
            @(posedge clk);
        end
    endtask

    // 仅当 DUT 明确允许时才写入下一帧。
    task automatic wait_img_wr_ready;
        begin
            while (!img_wr_ready) begin
                @(posedge clk);
                check_timeout();
            end
        end
    endtask

    // 写入一个完整的 30 行输入帧，然后提交。
    task automatic load_input_sample_and_commit(input integer sample_id);
        begin
            load_input_rows_by_sample_id(sample_id);

            for (row_idx = 0; row_idx < INPUT_ROW_COUNT; row_idx = row_idx + 1) begin
                @(posedge clk);
                img_wr_en <= 1'b1;
                img_wr_addr <= row_idx[4:0];
                img_wr_row_word <= input_rows_mem[row_idx];
            end

            @(posedge clk);
            img_wr_en <= 1'b0;
            img_wr_addr <= 5'd0;
            img_wr_row_word <= 80'd0;

            @(posedge clk);
            img_wr_commit <= 1'b1;

            @(posedge clk);
            img_wr_commit <= 1'b0;
        end
    endtask

    // 第一帧使用 start 脉冲进入连续模式。
    task automatic start_run;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    // 等待所有样本完成或超时。
    task automatic wait_samples_done_or_timeout(input integer expected_done_count);
        begin
            while (sample_done_counter < expected_done_count) begin
                @(posedge clk);
                check_timeout();
            end
            @(posedge clk);
        end
    endtask

    // 全局周期计数器。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end

    // 仅打印每个样本的最终 CNN 输出。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_output_counter <= 0;
        end else if (out_stream_valid) begin
            $display(
                "SIM_OUTPUT sample=%0d data=%016x",
                runtime_start_sample + sample_output_counter,
                out_stream_data
            );
            sample_output_counter <= sample_output_counter + 1;
        end
    end

    // 打印每个样本的 done 事件。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_done_counter <= 0;
        end else if (done) begin
            $display(
                "SAMPLE_DONE sample=%0d cycles=%0d",
                runtime_start_sample + sample_done_counter,
                cycle_counter
            );
            sample_done_counter <= sample_done_counter + 1;
        end
    end

    // 主要测试流程:
    // - 初始化并解析 plusargs
    // - 加载共享参数
    // - 连续提交 N 个样本帧
    // - 等待所有样本完成并检查最终计数
    initial begin
        init_signals();
        parse_plusargs();

        if (runtime_wave_enable != 0) begin
            $dumpfile(wave_file_path);
            $dumpvars(0, cnn_sim_tb);
        end

        apply_reset();

        for (sample_idx = 0; sample_idx < runtime_sample_count; sample_idx = sample_idx + 1) begin
            // 保持最多两帧已提交但尚未完成的帧在运行。
            // 这与 Ping-Pong 深度匹配，并避免了输入端队列溢出。
            if (sample_idx >= 2) begin
                while (sample_done_counter < (sample_idx - 1)) begin
                    @(posedge clk);
                    check_timeout();
                end
            end

            wait_img_wr_ready();
            current_dataset_sample_id = runtime_start_sample + sample_idx;
            load_input_sample_and_commit(current_dataset_sample_id);
            if (sample_idx == 0) begin
                start_run();
            end
        end

        wait_samples_done_or_timeout(runtime_sample_count);

        if (sample_output_counter !== runtime_sample_count) begin
            $display("TB_ERROR output_count got=%0d expected=%0d", sample_output_counter, runtime_sample_count);
            $finish_and_return(4);
        end
        if (sample_done_counter !== runtime_sample_count) begin
            $display("TB_ERROR sample_done_count got=%0d expected=%0d", sample_done_counter, runtime_sample_count);
            $finish_and_return(4);
        end

        $display("TB_PASS samples=%0d cycles=%0d", runtime_sample_count, cycle_counter);
        $finish_and_return(0);
    end

endmodule
