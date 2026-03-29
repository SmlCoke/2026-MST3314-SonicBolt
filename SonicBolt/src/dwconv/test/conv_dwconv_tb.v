`timescale 1ns / 1ps

/*
 * 模块名称: conv_dwconv_tb
 * 作者: SonicBolt 团队
 * 日期: 2026-03-29
 * 版本: v1.0
 *
 * 功能概述:
 *   面向当前 conv_subsystem + dwconv_subsystem的自检 testbench。
 *   这份 testbench 负责：
 *   1. 从预处理后的 mem 文件中加载单样本输入、整层权重和偏置
 *   2. 通过 conv_subsystem 顶层写口依次装载参数与输入图
 *   3. 启动一次 Conv + DWConv 计算，并捕获输出 TILE 日志
 *   4. 检查输出 token 数以及输出流是否出现中断
 *
 * 当前版本说明:
 *   - 当前 Conv 采用 `9 个 pos x 8 个 group = 72 个 token`
 *   - 每个 token 对应一个 `4ch x 4x4 x 8bit = 512bit` 输出 tile
 *   - 当前 testbench 采用单帧缓存流程：先装载完整输入图，再启动计算
 *
 * 日志格式:
 *   - 每个有效 tile 输出一行：
 *   - 一个样本结束后输出：
 *       SAMPLE_DONE sample=<n> cycles=<c>
 */

module conv_dwconv_tb #(
    parameter integer ENABLE_WAVE = 0
) ();

    // 基本仿真参数。
    localparam integer CLK_HALF_PERIOD   = 5;
    localparam integer INPUT_ROW_COUNT   = 30;

    // Conv层权重/偏置 mem depth
    localparam integer CONV_WEIGHT_WORD_COUNT = 88;
    localparam integer CONV_BIAS_WORD_COUNT   = 8;
    
    // DWConv 层权重/偏置 mem depth
    localparam integer DWCONV_WEIGHT_WORD_COUNT = 24;
    localparam integer DWCONV_BIAS_WORD_COUNT   = 8;

    // Token 计数
    localparam integer TOKEN_COUNT       = 72;

    // DUT 顶层控制与状态信号。
    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;

    // 输入图写口：逐行写入 30x10 输入图，每行 80bit。
    reg img_wr_en;
    reg [4:0] img_wr_addr;
    reg [39:0] img_wr_data_lo;
    reg [39:0] img_wr_data_hi;

    // Conv权重写口：11 个 bank x 8 个 group = 88 个 224bit word。
    reg conv_weight_wr_en;
    reg [4:0] conv_weight_wr_bank;
    reg [2:0] conv_weight_wr_addr;
    reg [223:0] conv_weight_wr_data;

    // Conv偏置写口：1 个 bank x 8 个 group = 8 个 64bit word。
    reg conv_bias_wr_en;
    reg conv_bias_wr_bank;
    reg [2:0] conv_bias_wr_addr;
    reg [63:0] conv_bias_wr_data;

    // DWConv权重写口：3 个 bank x 8 个 group = 24 个 96bit word。
    reg dwconv_weight_wr_en;
    reg [1:0] dwconv_weight_wr_bank;
    reg [2:0] dwconv_weight_wr_addr;
    reg [95:0] dwconv_weight_wr_data;

    // DWConv偏置写口：1 个 bank x 8 个 group = 8 个 64bit word。
    reg dwconv_bias_wr_en;
    reg dwconv_bias_wr_bank;
    reg [2:0] dwconv_bias_wr_addr;
    reg [63:0] dwconv_bias_wr_data;

    // Conv输出流接口：每拍最多输出一个 512bit tile。
    wire conv_out_stream_valid;
    wire conv_out_stream_last;
    wire conv_out_stream_fire;
    wire [3:0] conv_out_stream_pos;
    wire [2:0] conv_out_stream_group;
    wire [511:0] conv_out_stream_data;

    // DWConv输出流接口：每拍最多输出一个 128bit tile。
    wire dwconv_out_stream_valid;
    wire dwconv_out_stream_last;
    wire dwconv_out_stream_fire;
    wire [3:0] dwconv_out_stream_pos;
    wire [2:0] dwconv_out_stream_group;
    wire [127:0] dwconv_out_stream_data;

    // 本地测试数据缓存数组。
    reg [79:0]  input_rows_mem        [0:INPUT_ROW_COUNT-1];
    // Conv 层权重
    reg [223:0] conv_weight_words_mem [0:CONV_WEIGHT_WORD_COUNT-1];
    // Conv 层偏置
    reg [63:0]  conv_bias_words_mem   [0:CONV_BIAS_WORD_COUNT-1];

    // DWConv 层权重
    reg [95:0] dwconv_weight_words_mem [0:DWCONV_WEIGHT_WORD_COUNT-1];
    // DWConv 层偏置
    reg [63:0]  dwconv_bias_words_mem   [0:DWCONV_BIAS_WORD_COUNT-1];

    // 仿真流程控制变量。
    integer timeout_cycles;
    integer cycle_counter;
    integer tile_counter;
    integer row_idx;
    integer conv_weight_idx;
    integer conv_bias_idx;
    integer dwconv_weight_idx;
    integer dwconv_bias_idx;
    integer runtime_wave_enable;

    reg seen_first_tile;
    reg stream_gap_error;

    // 文件路径相关字符串，由 plusargs 拼出。
    string prep_dir;
    string input_mem_path;
    string conv_weight_mem_path;
    string conv_bias_mem_path;
    string dwconv_weight_mem_path;
    string dwconv_bias_mem_path;
    string wave_file_path;

    // Conv 实例
    conv_subsystem conv (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_data_lo(img_wr_data_lo),
        .img_wr_data_hi(img_wr_data_hi),
        .weight_wr_en(conv_weight_wr_en),
        .weight_wr_bank(conv_weight_wr_bank),
        .weight_wr_addr(conv_weight_wr_addr),
        .weight_wr_data(conv_weight_wr_data),
        .bias_wr_en(conv_bias_wr_en),
        .bias_wr_bank(conv_bias_wr_bank),
        .bias_wr_addr(conv_bias_wr_addr),
        .bias_wr_data(conv_bias_wr_data),
        .out_stream_valid(conv_out_stream_valid),
        .out_stream_last(conv_out_stream_last),
        .out_stream_pos(conv_out_stream_pos),
        .out_stream_group(conv_out_stream_group),
        .out_stream_fire(conv_out_stream_fire),
        .out_stream_data(conv_out_stream_data)
    );

    // Conv 实例。
    dwconv_subsystem dwconv (
        .clk(clk),
        .rst_n(rst_n),

        .in_stream_valid(conv_out_stream_valid),
        .in_stream_last(conv_out_stream_last),
        .in_stream_pos(conv_out_stream_pos),
        .in_stream_group(conv_out_stream_group),
        .in_stream_fire(conv_out_stream_fire),
        .in_stream_data(conv_out_stream_data),
        
        .weight_wr_en(dwconv_weight_wr_en),
        .weight_wr_bank(dwconv_weight_wr_bank),
        .weight_wr_addr(dwconv_weight_wr_addr),
        .weight_wr_data(dwconv_weight_wr_data),
        .bias_wr_en(dwconv_bias_wr_en),
        .bias_wr_bank(dwconv_bias_wr_bank),
        .bias_wr_addr(dwconv_bias_wr_addr),
        .bias_wr_data(dwconv_bias_wr_data),
        .out_stream_valid(dwconv_out_stream_valid),
        .out_stream_last(dwconv_out_stream_last),
        .out_stream_pos(dwconv_out_stream_pos),
        .out_stream_group(dwconv_out_stream_group),
        .out_stream_data(dwconv_out_stream_data)
    );

    // 生成时钟，默认 10ns 一个周期。
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // 初始化所有驱动信号和统计变量。
    task automatic init_signals;
        begin
            clk = 1'b0;
            rst_n = 1'b0;
            start = 1'b0;
            img_wr_en = 1'b0;
            img_wr_addr = 5'd0;
            img_wr_data_lo = 40'd0;
            img_wr_data_hi = 40'd0;

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

            cycle_counter = 0;
            tile_counter = 0;
            seen_first_tile = 1'b0;
            stream_gap_error = 1'b0;
        end
    endtask

    // 解析 plusargs，生成本次仿真使用的 mem 文件路径。
    task automatic parse_plusargs;
        begin
            prep_dir = "";
            wave_file_path = "";
            timeout_cycles = 4000;
            runtime_wave_enable = ENABLE_WAVE;

            if (!$value$plusargs("PREP_DIR=%s", prep_dir)) begin
                $display("TB_ERROR missing +PREP_DIR");
                $finish_and_return(2);
            end
            if ($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles)) begin
            end
            if ($test$plusargs("WAVE")) begin
                runtime_wave_enable = 1;
            end
            if ($value$plusargs("WAVE=%d", runtime_wave_enable)) begin
            end
            if (!$value$plusargs("WAVE_FILE=%s", wave_file_path)) begin
                wave_file_path = "conv_subsystem_tb.vcd";
            end

            input_mem_path         = $sformatf("%0s/samples/sample_input_rows.mem", prep_dir);
            conv_weight_mem_path   = $sformatf("%0s/conv_weights/weight_words.mem", prep_dir);
            conv_bias_mem_path     = $sformatf("%0s/conv_bias/bias_words.mem", prep_dir);
            dwconv_weight_mem_path = $sformatf("%0s/dwconv_weights/weight_words.mem", prep_dir);
            dwconv_bias_mem_path   = $sformatf("%0s/dwconv_bias/bias_words.mem", prep_dir);

        end
    endtask

    // 从预处理目录读取输入、权重和偏置 mem 文件。
    task automatic load_memories;
        begin
            $readmemh(input_mem_path, input_rows_mem);
            $readmemh(conv_weight_mem_path, conv_weight_words_mem);
            $readmemh(conv_bias_mem_path, conv_bias_words_mem);
            $readmemh(dwconv_weight_mem_path, dwconv_weight_words_mem);
            $readmemh(dwconv_bias_mem_path, dwconv_bias_words_mem);
        end
    endtask

    // 对电路施加同步释放的低有效复位。
    task automatic apply_reset;
        begin
            repeat (4) @(posedge clk);
            rst_n <= 1'b1;
            @(posedge clk);
        end
    endtask

    // 逐 word 装载 Conv 整层权重。
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
        end
    endtask

    // 逐 word 装载 Conv 整层偏置。
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
        end
    endtask

    // 把当前样本的 30 行输入图完整写入单帧 SRAM。
    task automatic load_input_sample;
        reg [79:0] row_word;
        begin
            for (row_idx = 0; row_idx < INPUT_ROW_COUNT; row_idx = row_idx + 1) begin
                row_word = input_rows_mem[row_idx];
                @(posedge clk);
                img_wr_en <= 1'b1;
                img_wr_addr <= row_idx[4:0];
                img_wr_data_lo <= row_word[39:0];
                img_wr_data_hi <= row_word[79:40];
            end
            @(posedge clk);
            img_wr_en <= 1'b0;
            img_wr_addr <= 5'd0;
            img_wr_data_lo <= 40'd0;
            img_wr_data_hi <= 40'd0;
        end
    endtask

    // 拉高 start 一个时钟周期，启动一次新图计算。
    task automatic start_run;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    // 等待 DUT 完成，或者在超时后报错退出。
    task automatic wait_done_or_timeout;
        begin
            while (!done) begin
                @(posedge clk);
                if (cycle_counter > timeout_cycles) begin
                    $display("TB_ERROR timeout  cycles=%0d", cycle_counter);
                    $finish_and_return(3);
                end
            end
            @(posedge clk);
        end
    endtask

    // 统计输出 token，并检查输出流中途是否出现断流。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 0;
            tile_counter <= 0;
            seen_first_tile <= 1'b0;
            stream_gap_error <= 1'b0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            if (dwconv_out_stream_valid) begin
                tile_counter <= tile_counter + 1;
                seen_first_tile <= 1'b1;
                $display("TILE pos=%0d group=%0d data=%032x", dwconv_out_stream_pos, dwconv_out_stream_group, dwconv_out_stream_data);
            end else if (seen_first_tile && (tile_counter < TOKEN_COUNT) && !done) begin
                stream_gap_error <= 1'b1;
            end
        end
    end

    // 主测试流程：
    // 1. 解析仿真 plusargs
    // 2. 从 mem 文件加载样本
    // 3. 复位 DUT
    // 4. 装载权重 / 偏置 / 输入图
    // 5. 启动计算
    // 6. 等待完成
    // 7. 检查 tile 数和 stream gap
    initial begin
        init_signals();
        parse_plusargs();

        if (runtime_wave_enable != 0) begin
            $dumpfile(wave_file_path);
            $dumpvars(0, conv_dwconv_tb);
        end

        load_memories();
        apply_reset();
        load_weights();
        load_bias();
        load_input_sample();
        start_run();
        wait_done_or_timeout();

        if (tile_counter !== TOKEN_COUNT) begin
            $display("TB_ERROR tile_count got=%0d expected=%0d", tile_counter, TOKEN_COUNT);
            $finish_and_return(4);
        end

        if (stream_gap_error) begin
            $display("TB_ERROR stream_gap");
            $finish_and_return(5);
        end

        $display("SAMPLE_DONE cycles=%0d", cycle_counter);
        $finish_and_return(0);
    end

endmodule
