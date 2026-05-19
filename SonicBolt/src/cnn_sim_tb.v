`timescale 1ns / 1ps
/*
 * 模块名称: cnn_sim_tb
 * 作者: SonicBolt Team
 * 日期: 2026-04-08
 * 版本: v1.0
 *
 * 总结:
 *   简化的多样本连续仿真测试平台。
 *   该测试平台保持与 cnn_test_tb 相同的参数加载和输入提交流程，
 *   但只打印两种类型的日志:
 *     - SIM_OUTPUT sample=<dataset_id> data=<16hex>
 *     - SAMPLE_DONE sample=<dataset_id> cycles=<cycle>
 *
 * 说明:
 *   1. START_SAMPLE / SAMPLE_COUNT 通过 plusargs 传递。
 *   2. 按样本加载输入行文件:
 *      <PREP_DIR>/samples/<id>_input_rows.mem
 *   3. 共享参数文件从 PREP_DIR 仅加载一次。
 */

module cnn_sim_tb #(
    parameter integer ENABLE_WAVE = 0
) ();

    // 基本仿真参数。
    localparam integer CLK_HALF_PERIOD   = 5;
    localparam integer INPUT_ROW_COUNT   = 30;

    // Conv 权重 / 偏置存储深度。
    localparam integer CONV_WEIGHT_WORD_COUNT   = 88;
    localparam integer CONV_BIAS_WORD_COUNT     = 8;

    // DWConv 权重 / 偏置存储深度。
    localparam integer DWCONV_WEIGHT_WORD_COUNT = 24;
    localparam integer DWCONV_BIAS_WORD_COUNT   = 8;

    // PWConv 权重 / 偏置存储深度。
    localparam integer PWCONV_WEIGHT_WORD_COUNT = 64;
    localparam integer PWCONV_BIAS_WORD_COUNT   = 8;

    // FC / Sigmoid 存储深度。
    localparam integer FC_WEIGHT_WORD_COUNT     = 72;
    localparam integer FC_BIAS_WORD_COUNT       = 1;
    localparam integer SIGMOID_LUT_WORD_COUNT   = 256;

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

    // Conv 权重写入接口。
    reg         conv_weight_wr_en;
    reg [4:0]   conv_weight_wr_bank;
    reg [2:0]   conv_weight_wr_addr;
    reg [223:0] conv_weight_wr_data;

    // Conv 偏置写入接口。
    reg        conv_bias_wr_en;
    reg        conv_bias_wr_bank;
    reg [2:0]  conv_bias_wr_addr;
    reg [63:0] conv_bias_wr_data;

    // DWConv 权重写入接口。
    reg        dwconv_weight_wr_en;
    reg [1:0]  dwconv_weight_wr_bank;
    reg [2:0]  dwconv_weight_wr_addr;
    reg [95:0] dwconv_weight_wr_data;

    // DWConv 偏置写入接口。
    reg        dwconv_bias_wr_en;
    reg        dwconv_bias_wr_bank;
    reg [2:0]  dwconv_bias_wr_addr;
    reg [63:0] dwconv_bias_wr_data;

    // PWConv 权重写入接口。
    reg         pwconv_weight_wr_en;
    reg [2:0]   pwconv_weight_wr_bank;
    reg [2:0]   pwconv_weight_wr_addr;
    reg [127:0] pwconv_weight_wr_data;

    // PWConv 偏置写入接口。
    reg        pwconv_bias_wr_en;
    reg        pwconv_bias_wr_bank;
    reg [2:0]  pwconv_bias_wr_addr;
    reg [63:0] pwconv_bias_wr_data;

    // FC / Sigmoid 写入接口。
    reg        fc_weight_wr_en;
    reg [6:0]  fc_weight_wr_addr;
    reg [63:0] fc_weight_wr_data;
    reg        fc_bias_wr_en;
    reg [31:0] fc_bias_wr_data;
    reg        sigmoid_lut_wr_en;
    reg [7:0]  sigmoid_lut_wr_addr;
    reg [31:0] sigmoid_lut_wr_data;

    // CNN 输出流。
    wire         out_stream_valid;
    wire [63:0]  out_stream_data;

    // 本地存储数组。
    reg [79:0]   input_rows_mem          [0:INPUT_ROW_COUNT-1];
    reg [223:0]  conv_weight_words_mem   [0:CONV_WEIGHT_WORD_COUNT-1];
    reg [63:0]   conv_bias_words_mem     [0:CONV_BIAS_WORD_COUNT-1];
    reg [95:0]   dwconv_weight_words_mem [0:DWCONV_WEIGHT_WORD_COUNT-1];
    reg [63:0]   dwconv_bias_words_mem   [0:DWCONV_BIAS_WORD_COUNT-1];
    reg [127:0]  pwconv_weight_words_mem [0:PWCONV_WEIGHT_WORD_COUNT-1];
    reg [63:0]   pwconv_bias_words_mem   [0:PWCONV_BIAS_WORD_COUNT-1];
    reg [63:0]   fc_weight_words_mem     [0:FC_WEIGHT_WORD_COUNT-1];
    reg [31:0]   fc_bias_words_mem       [0:FC_BIAS_WORD_COUNT-1];
    reg [31:0]   sigmoid_lut_words_mem   [0:SIGMOID_LUT_WORD_COUNT-1];

    // 运行时控制。
    integer timeout_cycles;
    integer cycle_counter;
    integer runtime_wave_enable;
    integer runtime_sample_count;
    integer runtime_start_sample;
    integer sample_done_counter;
    integer sample_output_counter;

    integer row_idx;
    integer conv_weight_idx;
    integer conv_bias_idx;
    integer dwconv_weight_idx;
    integer dwconv_bias_idx;
    integer pwconv_weight_idx;
    integer pwconv_bias_idx;
    integer fc_weight_idx;
    integer fc_bias_idx;
    integer sigmoid_lut_idx;
    integer sample_idx;
    integer current_dataset_sample_id;
    integer sample_id_mem [0:1023];

    // 路径字符串。
    string prep_dir;
    string input_mem_path;
    string conv_weight_mem_path;
    string conv_bias_mem_path;
    string dwconv_weight_mem_path;
    string dwconv_bias_mem_path;
    string pwconv_weight_mem_path;
    string pwconv_bias_mem_path;
    string fc_weight_mem_path;
    string fc_bias_mem_path;
    string sigmoid_lut_mem_path;
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

            conv_weight_wr_en = 1'b0;
            conv_weight_wr_bank = 5'd0;
            conv_weight_wr_addr = 3'd0;
            conv_weight_wr_data = 224'd0;
            conv_bias_wr_en = 1'b0;
            conv_bias_wr_bank = 1'b0;
            conv_bias_wr_addr = 3'd0;
            conv_bias_wr_data = 64'd0;

            dwconv_weight_wr_en = 1'b0;
            dwconv_weight_wr_bank = 2'd0;
            dwconv_weight_wr_addr = 3'd0;
            dwconv_weight_wr_data = 96'd0;
            dwconv_bias_wr_en = 1'b0;
            dwconv_bias_wr_bank = 1'b0;
            dwconv_bias_wr_addr = 3'd0;
            dwconv_bias_wr_data = 64'd0;

            pwconv_weight_wr_en = 1'b0;
            pwconv_weight_wr_bank = 3'd0;
            pwconv_weight_wr_addr = 3'd0;
            pwconv_weight_wr_data = 128'd0;
            pwconv_bias_wr_en = 1'b0;
            pwconv_bias_wr_bank = 1'b0;
            pwconv_bias_wr_addr = 3'd0;
            pwconv_bias_wr_data = 64'd0;

            fc_weight_wr_en = 1'b0;
            fc_weight_wr_addr = 7'd0;
            fc_weight_wr_data = 64'd0;
            fc_bias_wr_en = 1'b0;
            fc_bias_wr_data = 32'd0;
            sigmoid_lut_wr_en = 1'b0;
            sigmoid_lut_wr_addr = 8'd0;
            sigmoid_lut_wr_data = 32'd0;

            timeout_cycles = 4000;
            runtime_wave_enable = ENABLE_WAVE;
            runtime_sample_count = 5;
            runtime_start_sample = 0;

            cycle_counter = 0;
            sample_done_counter = 0;
            sample_output_counter = 0;
        end
    endtask

    // 解析 plusargs 并构建共享内存路径。
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

            conv_weight_mem_path   = $sformatf("%0s/conv_weights/weight_words.mem", prep_dir);
            conv_bias_mem_path     = $sformatf("%0s/conv_bias/bias_words.mem", prep_dir);
            dwconv_weight_mem_path = $sformatf("%0s/dwconv_weights/weight_words.mem", prep_dir);
            dwconv_bias_mem_path   = $sformatf("%0s/dwconv_bias/bias_words.mem", prep_dir);
            pwconv_weight_mem_path = $sformatf("%0s/pwconv_weights/weight_words.mem", prep_dir);
            pwconv_bias_mem_path   = $sformatf("%0s/pwconv_bias/bias_words.mem", prep_dir);
            fc_weight_mem_path     = $sformatf("%0s/fc_weights/weight_words.mem", prep_dir);
            fc_bias_mem_path       = $sformatf("%0s/fc_bias/bias_words.mem", prep_dir);
            sigmoid_lut_mem_path   = $sformatf("%0s/sigmoid_lut/lut_words.mem", prep_dir);
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

    // 仅读取一次所有共享参数内存。
    task automatic load_shared_memories;
        begin
            $readmemh(conv_weight_mem_path, conv_weight_words_mem);
            $readmemh(conv_bias_mem_path, conv_bias_words_mem);
            $readmemh(dwconv_weight_mem_path, dwconv_weight_words_mem);
            $readmemh(dwconv_bias_mem_path, dwconv_bias_words_mem);
            $readmemh(pwconv_weight_mem_path, pwconv_weight_words_mem);
            $readmemh(pwconv_bias_mem_path, pwconv_bias_words_mem);
            $readmemh(fc_weight_mem_path, fc_weight_words_mem);
            $readmemh(fc_bias_mem_path, fc_bias_words_mem);
            $readmemh(sigmoid_lut_mem_path, sigmoid_lut_words_mem);
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

    // 逐字写入所有层的权重。
    task automatic load_weights;
        begin
            for (conv_weight_idx = 0; conv_weight_idx < CONV_WEIGHT_WORD_COUNT; conv_weight_idx = conv_weight_idx + 1) begin
                @(posedge clk);
                conv_weight_wr_en <= 1'b1;
                conv_weight_wr_bank <= conv_weight_idx / 8;
                conv_weight_wr_addr <= conv_weight_idx % 8;
                conv_weight_wr_data <= conv_weight_words_mem[conv_weight_idx];
            end
            @(posedge clk);
            conv_weight_wr_en <= 1'b0;
            conv_weight_wr_bank <= 5'd0;
            conv_weight_wr_addr <= 3'd0;
            conv_weight_wr_data <= 224'd0;

            for (dwconv_weight_idx = 0; dwconv_weight_idx < DWCONV_WEIGHT_WORD_COUNT; dwconv_weight_idx = dwconv_weight_idx + 1) begin
                @(posedge clk);
                dwconv_weight_wr_en <= 1'b1;
                dwconv_weight_wr_bank <= dwconv_weight_idx / 8;
                dwconv_weight_wr_addr <= dwconv_weight_idx % 8;
                dwconv_weight_wr_data <= dwconv_weight_words_mem[dwconv_weight_idx];
            end
            @(posedge clk);
            dwconv_weight_wr_en <= 1'b0;
            dwconv_weight_wr_bank <= 2'd0;
            dwconv_weight_wr_addr <= 3'd0;
            dwconv_weight_wr_data <= 96'd0;

            for (pwconv_weight_idx = 0; pwconv_weight_idx < PWCONV_WEIGHT_WORD_COUNT; pwconv_weight_idx = pwconv_weight_idx + 1) begin
                @(posedge clk);
                pwconv_weight_wr_en <= 1'b1;
                pwconv_weight_wr_bank <= pwconv_weight_idx / 8;
                pwconv_weight_wr_addr <= pwconv_weight_idx % 8;
                pwconv_weight_wr_data <= pwconv_weight_words_mem[pwconv_weight_idx];
            end
            @(posedge clk);
            pwconv_weight_wr_en <= 1'b0;
            pwconv_weight_wr_bank <= 3'd0;
            pwconv_weight_wr_addr <= 3'd0;
            pwconv_weight_wr_data <= 128'd0;

            for (fc_weight_idx = 0; fc_weight_idx < FC_WEIGHT_WORD_COUNT; fc_weight_idx = fc_weight_idx + 1) begin
                @(posedge clk);
                fc_weight_wr_en <= 1'b1;
                fc_weight_wr_addr <= fc_weight_idx[6:0];
                fc_weight_wr_data <= fc_weight_words_mem[fc_weight_idx];
            end
            @(posedge clk);
            fc_weight_wr_en <= 1'b0;
            fc_weight_wr_addr <= 7'd0;
            fc_weight_wr_data <= 64'd0;
        end
    endtask

    // 逐字写入所有层的偏置。
    task automatic load_bias;
        begin
            for (conv_bias_idx = 0; conv_bias_idx < CONV_BIAS_WORD_COUNT; conv_bias_idx = conv_bias_idx + 1) begin
                @(posedge clk);
                conv_bias_wr_en <= 1'b1;
                conv_bias_wr_bank <= 1'b0;
                conv_bias_wr_addr <= conv_bias_idx[2:0];
                conv_bias_wr_data <= conv_bias_words_mem[conv_bias_idx];
            end
            @(posedge clk);
            conv_bias_wr_en <= 1'b0;
            conv_bias_wr_bank <= 1'b0;
            conv_bias_wr_addr <= 3'd0;
            conv_bias_wr_data <= 64'd0;

            for (dwconv_bias_idx = 0; dwconv_bias_idx < DWCONV_BIAS_WORD_COUNT; dwconv_bias_idx = dwconv_bias_idx + 1) begin
                @(posedge clk);
                dwconv_bias_wr_en <= 1'b1;
                dwconv_bias_wr_bank <= 1'b0;
                dwconv_bias_wr_addr <= dwconv_bias_idx[2:0];
                dwconv_bias_wr_data <= dwconv_bias_words_mem[dwconv_bias_idx];
            end
            @(posedge clk);
            dwconv_bias_wr_en <= 1'b0;
            dwconv_bias_wr_bank <= 1'b0;
            dwconv_bias_wr_addr <= 3'd0;
            dwconv_bias_wr_data <= 64'd0;

            for (pwconv_bias_idx = 0; pwconv_bias_idx < PWCONV_BIAS_WORD_COUNT; pwconv_bias_idx = pwconv_bias_idx + 1) begin
                @(posedge clk);
                pwconv_bias_wr_en <= 1'b1;
                pwconv_bias_wr_bank <= 1'b0;
                pwconv_bias_wr_addr <= pwconv_bias_idx[2:0];
                pwconv_bias_wr_data <= pwconv_bias_words_mem[pwconv_bias_idx];
            end
            @(posedge clk);
            pwconv_bias_wr_en <= 1'b0;
            pwconv_bias_wr_bank <= 1'b0;
            pwconv_bias_wr_addr <= 3'd0;
            pwconv_bias_wr_data <= 64'd0;

            for (fc_bias_idx = 0; fc_bias_idx < FC_BIAS_WORD_COUNT; fc_bias_idx = fc_bias_idx + 1) begin
                @(posedge clk);
                fc_bias_wr_en <= 1'b1;
                fc_bias_wr_data <= fc_bias_words_mem[fc_bias_idx];
            end
            @(posedge clk);
            fc_bias_wr_en <= 1'b0;
            fc_bias_wr_data <= 32'd0;
        end
    endtask

    // 写入 Sigmoid LUT。
    task automatic load_sigmoid_lut;
        begin
            for (sigmoid_lut_idx = 0; sigmoid_lut_idx < SIGMOID_LUT_WORD_COUNT; sigmoid_lut_idx = sigmoid_lut_idx + 1) begin
                @(posedge clk);
                sigmoid_lut_wr_en <= 1'b1;
                sigmoid_lut_wr_addr <= sigmoid_lut_idx[7:0];
                sigmoid_lut_wr_data <= sigmoid_lut_words_mem[sigmoid_lut_idx];
            end
            @(posedge clk);
            sigmoid_lut_wr_en <= 1'b0;
            sigmoid_lut_wr_addr <= 8'd0;
            sigmoid_lut_wr_data <= 32'd0;
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
                sample_id_mem[sample_output_counter],
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
                sample_id_mem[sample_done_counter],
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

        load_shared_memories();
        apply_reset();
        load_weights();
        load_bias();
        load_sigmoid_lut();

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
            sample_id_mem[sample_idx] = current_dataset_sample_id;
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
