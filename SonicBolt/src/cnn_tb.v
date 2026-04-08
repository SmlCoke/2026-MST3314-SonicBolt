`timescale 1ns / 1ps
/*
 * 模块名称: cnn_tb
 * 作者: SonicBolt 团队
 * 日期: 2026-04-08
 * 版本: v1.3
 *
 * 功能概述:
 *   面向整个 SonicBolt 系统的 testbench。
 *   这份 testbench 负责：
 *   1. 从预处理后的 mem 文件中加载单样本输入、整层权重和偏置
 *   2. 通过顶层写口依次装载参数与输入图
 *   3. 启动一次 feature map 计算，并捕获输出 TILE 日志
 *   4. 检查输出 token 数以及输出流是否出现中断
 *
 * 日志格式:
 *   - 每个有效 tile 输出一行：
 *   - 一个样本结束后输出：
 *       SAMPLE_DONE sample=<n> cycles=<c>
 *
 * 版本定位:
 *   - 当前架构采用 `9 个 pos x 8 个 group = 72 个 token`
 *   - 当前 testbench 采用单帧缓存流程：先装载完整输入图，再启动计算
 *   - v1.1 级联了 PWConv
 *   - v1.2 级联了整个系统，仿真测试通过
 *   - v1.3 优化了输入Ping-Pong缓冲和启动机制
 */

module cnn_tb #(
    parameter integer ENABLE_WAVE = 0
) ();

    // 基本仿真参数。
    localparam integer CLK_HALF_PERIOD   = 5;
    localparam integer INPUT_ROW_COUNT   = 30;

    // Conv 层权重 / 偏置 mem depth
    localparam integer CONV_WEIGHT_WORD_COUNT   = 88;
    localparam integer CONV_BIAS_WORD_COUNT     = 8;

    // DWConv 层权重 / 偏置 mem depth
    localparam integer DWCONV_WEIGHT_WORD_COUNT = 24;
    localparam integer DWCONV_BIAS_WORD_COUNT   = 8;

    // PWConv 层权重 / 偏置 mem depth
    localparam integer PWCONV_WEIGHT_WORD_COUNT = 64;
    localparam integer PWCONV_BIAS_WORD_COUNT   = 8;

    // FC / Sigmoid 参数 mem depth
    localparam integer FC_WEIGHT_WORD_COUNT     = 72;
    localparam integer FC_BIAS_WORD_COUNT       = 1;
    localparam integer SIGMOID_LUT_WORD_COUNT   = 256;

    // Token 计数
    localparam integer TOKEN_COUNT              = 72;

    // DUT 顶层控制与状态信号。
    reg clk;
    reg rst_n;
    reg start;
    wire busy;
    wire done;

    // 输入图写口：逐行写入 30x10 输入图，每行 80bit。
    reg [4:0]  img_wr_addr;
    reg        img_wr_en;
    reg [79:0] img_wr_row_word;
    reg        img_wr_commit;
    wire       img_wr_ready;

    // Conv 权重写口：11 个 bank x 8 个 group = 88 个 224bit word。
    reg         conv_weight_wr_en;
    reg [4:0]   conv_weight_wr_bank;
    reg [2:0]   conv_weight_wr_addr;
    reg [223:0] conv_weight_wr_data;

    // Conv 偏置写口：1 个 bank x 8 个 group = 8 个 64bit word。
    reg        conv_bias_wr_en;
    reg        conv_bias_wr_bank;
    reg [2:0]  conv_bias_wr_addr;
    reg [63:0] conv_bias_wr_data;

    // DWConv 权重写口：3 个 bank x 8 个 group = 24 个 96bit word。
    reg        dwconv_weight_wr_en;
    reg [1:0]  dwconv_weight_wr_bank;
    reg [2:0]  dwconv_weight_wr_addr;
    reg [95:0] dwconv_weight_wr_data;

    // DWConv 偏置写口：1 个 bank x 8 个 group = 8 个 64bit word。
    reg        dwconv_bias_wr_en;
    reg        dwconv_bias_wr_bank;
    reg [2:0]  dwconv_bias_wr_addr;
    reg [63:0] dwconv_bias_wr_data;

    // PWConv 权重写口：8 个 bank x 8 个 group = 64 个 128bit word。
    reg         pwconv_weight_wr_en;
    reg [2:0]   pwconv_weight_wr_bank;
    reg [2:0]   pwconv_weight_wr_addr;
    reg [127:0] pwconv_weight_wr_data;

    // PWConv 偏置写口：1 个 bank x 8 个 group = 8 个 64bit word。
    reg        pwconv_bias_wr_en;
    reg        pwconv_bias_wr_bank;
    reg [2:0]  pwconv_bias_wr_addr;
    reg [63:0] pwconv_bias_wr_data;

    // FC / Sigmoid 参数写口。
    reg        fc_weight_wr_en;
    reg [6:0]  fc_weight_wr_addr;
    reg [63:0] fc_weight_wr_data;
    reg        fc_bias_wr_en;
    reg [31:0] fc_bias_wr_data;
    reg        sigmoid_lut_wr_en;
    reg [7:0]  sigmoid_lut_wr_addr;
    reg [31:0] sigmoid_lut_wr_data;

    // Conv 输出流接口：每拍最多输出一个 512bit tile。
    wire         conv_out_stream_valid;
    wire         conv_out_stream_last;
    wire         conv_out_stream_fire;
    wire [3:0]   conv_out_stream_pos;
    wire [2:0]   conv_out_stream_group;
    wire [511:0] conv_out_stream_data;

    // DWConv 输出流接口：每拍最多输出一个 128bit tile。
    wire         dwconv_out_stream_valid;
    wire         dwconv_out_stream_last;
    wire         dwconv_out_stream_fire;
    wire [3:0]   dwconv_out_stream_pos;
    wire [2:0]   dwconv_out_stream_group;
    wire [127:0] dwconv_out_stream_data;

    // PWConv 输出流接口：每拍最多输出一个 128bit tile。
    wire         pwconv_out_stream_valid;
    wire         pwconv_out_stream_last;
    wire         pwconv_out_stream_fire;
    wire [3:0]   pwconv_out_stream_pos;
    wire [2:0]   pwconv_out_stream_group;
    wire [127:0] pwconv_out_stream_data;

    // Maxpool 输出流接口：每拍最多输出一个 32bit token。
    wire         maxpool_out_stream_valid;
    wire         maxpool_out_stream_last;
    wire         maxpool_out_stream_fire;
    wire [3:0]   maxpool_out_stream_pos;
    wire [2:0]   maxpool_out_stream_group;
    wire [31:0]  maxpool_out_stream_data;

    // FC 输出流接口：每次样本输出一个 16bit 结果。
    wire         fc_out_stream_valid;
    wire [15:0]  fc_out_stream_data;
    // Sigmoid 输出流接口：每次样本输出一个 64bit 结果。
    wire         sigmoid_out_stream_valid;
    wire [63:0]  sigmoid_out_stream_data;

    // CNN 输出流接口
    wire         out_stream_valid;
    wire [63:0]  out_stream_data;

    // 本地测试数据缓存数组。
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

    // 仿真流程控制变量。
    integer timeout_cycles;
    integer cycle_counter;
    integer runtime_wave_enable;
    integer runtime_sample_count;
    integer sample_done_counter;

    integer conv_tile_counter;
    integer dwconv_tile_counter;
    integer pwconv_tile_counter;
    integer maxpool_tile_counter;
    integer fc_tile_counter;
    integer sigmoid_tile_counter;

    integer conv_frame_token_count;
    integer dwconv_frame_token_count;
    integer pwconv_frame_token_count;
    integer maxpool_frame_token_count;

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

    // 用于检查各层 token 流是否出现中断。
    reg conv_in_frame;
    reg dwconv_in_frame;
    reg pwconv_in_frame;
    reg maxpool_in_frame;
    reg conv_stream_gap_error;
    reg dwconv_stream_gap_error;
    reg pwconv_stream_gap_error;
    reg maxpool_stream_gap_error;

    // 文件路径相关字符串，由 plusargs 拼出。
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

    // cnn 实例
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
        .conv_weight_wr_en(conv_weight_wr_en),
        .conv_weight_wr_bank(conv_weight_wr_bank),
        .conv_weight_wr_addr(conv_weight_wr_addr),
        .conv_weight_wr_data(conv_weight_wr_data),
        .dwconv_weight_wr_en(dwconv_weight_wr_en),
        .dwconv_weight_wr_bank(dwconv_weight_wr_bank),
        .dwconv_weight_wr_addr(dwconv_weight_wr_addr),
        .dwconv_weight_wr_data(dwconv_weight_wr_data),
        .pwconv_weight_wr_en(pwconv_weight_wr_en),
        .pwconv_weight_wr_bank(pwconv_weight_wr_bank),
        .pwconv_weight_wr_addr(pwconv_weight_wr_addr),
        .pwconv_weight_wr_data(pwconv_weight_wr_data),
        .conv_bias_wr_en(conv_bias_wr_en),
        .conv_bias_wr_bank(conv_bias_wr_bank),
        .conv_bias_wr_addr(conv_bias_wr_addr),
        .conv_bias_wr_data(conv_bias_wr_data),
        .dwconv_bias_wr_en(dwconv_bias_wr_en),
        .dwconv_bias_wr_bank(dwconv_bias_wr_bank),
        .dwconv_bias_wr_addr(dwconv_bias_wr_addr),
        .dwconv_bias_wr_data(dwconv_bias_wr_data),
        .pwconv_bias_wr_en(pwconv_bias_wr_en),
        .pwconv_bias_wr_bank(pwconv_bias_wr_bank),
        .pwconv_bias_wr_addr(pwconv_bias_wr_addr),
        .pwconv_bias_wr_data(pwconv_bias_wr_data),
        .fc_weight_wr_en(fc_weight_wr_en),
        .fc_weight_wr_addr(fc_weight_wr_addr),
        .fc_weight_wr_data(fc_weight_wr_data),
        .fc_bias_wr_en(fc_bias_wr_en),
        .fc_bias_wr_data(fc_bias_wr_data),
        .sigmoid_lut_wr_en(sigmoid_lut_wr_en),
        .sigmoid_lut_wr_addr(sigmoid_lut_wr_addr),
        .sigmoid_lut_wr_data(sigmoid_lut_wr_data),
        .out_stream_valid(out_stream_valid),
        .out_stream_data(out_stream_data)
    );

    // hook: testbench 强制访问 Conv 层输出
    assign conv_out_stream_valid = cnn_inst.conv_inst.out_stream_valid;
    assign conv_out_stream_fire  = cnn_inst.conv_inst.out_stream_fire;
    assign conv_out_stream_last  = cnn_inst.conv_inst.out_stream_last;
    assign conv_out_stream_pos   = cnn_inst.conv_inst.out_stream_pos;
    assign conv_out_stream_group = cnn_inst.conv_inst.out_stream_group;
    assign conv_out_stream_data  = cnn_inst.conv_inst.out_stream_data;

    // hook: testbench 强制访问 DWConv 层输出
    assign dwconv_out_stream_valid = cnn_inst.dwconv_inst.out_stream_valid;
    assign dwconv_out_stream_fire  = cnn_inst.dwconv_inst.out_stream_fire;
    assign dwconv_out_stream_last  = cnn_inst.dwconv_inst.out_stream_last;
    assign dwconv_out_stream_pos   = cnn_inst.dwconv_inst.out_stream_pos;
    assign dwconv_out_stream_group = cnn_inst.dwconv_inst.out_stream_group;
    assign dwconv_out_stream_data  = cnn_inst.dwconv_inst.out_stream_data;

    // hook: testbench 强制访问 PWConv 层输出
    assign pwconv_out_stream_valid = cnn_inst.pwconv_inst.out_stream_valid;
    assign pwconv_out_stream_fire  = cnn_inst.pwconv_inst.out_stream_fire;
    assign pwconv_out_stream_last  = cnn_inst.pwconv_inst.out_stream_last;
    assign pwconv_out_stream_pos   = cnn_inst.pwconv_inst.out_stream_pos;
    assign pwconv_out_stream_group = cnn_inst.pwconv_inst.out_stream_group;
    assign pwconv_out_stream_data  = cnn_inst.pwconv_inst.out_stream_data;

    // hook: testbench 强制访问 Post-Process 内部 Maxpool / FC / Sigmoid 输出
    assign maxpool_out_stream_valid = cnn_inst.post_process_inst.u_maxpool.out_valid;
    assign maxpool_out_stream_last  = cnn_inst.post_process_inst.u_maxpool.out_last;
    assign maxpool_out_stream_fire  = cnn_inst.post_process_inst.u_maxpool.out_fire;
    assign maxpool_out_stream_pos   = cnn_inst.post_process_inst.u_maxpool.out_pos;
    assign maxpool_out_stream_group = cnn_inst.post_process_inst.u_maxpool.out_group;
    assign maxpool_out_stream_data  = cnn_inst.post_process_inst.u_maxpool.out_data_bus;

    assign fc_out_stream_valid      = cnn_inst.post_process_inst.u_fc.out_valid;
    assign fc_out_stream_data       = cnn_inst.post_process_inst.u_fc.out_data_bus;
    assign sigmoid_out_stream_valid = cnn_inst.post_process_inst.out_stream_valid;
    assign sigmoid_out_stream_data  = cnn_inst.post_process_inst.out_stream_data;

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
            runtime_sample_count = 3;

            cycle_counter = 0;
            sample_done_counter = 0;
            conv_tile_counter = 0;
            dwconv_tile_counter = 0;
            pwconv_tile_counter = 0;
            maxpool_tile_counter = 0;
            fc_tile_counter = 0;
            sigmoid_tile_counter = 0;

            conv_frame_token_count = 0;
            dwconv_frame_token_count = 0;
            pwconv_frame_token_count = 0;
            maxpool_frame_token_count = 0;

            conv_in_frame = 1'b0;
            dwconv_in_frame = 1'b0;
            pwconv_in_frame = 1'b0;
            maxpool_in_frame = 1'b0;
            conv_stream_gap_error = 1'b0;
            dwconv_stream_gap_error = 1'b0;
            pwconv_stream_gap_error = 1'b0;
            maxpool_stream_gap_error = 1'b0;
        end
    endtask

    // 解析 plusargs，生成本次仿真使用的 mem 文件路径。
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
            if ($test$plusargs("WAVE")) begin
                runtime_wave_enable = 1;
            end
            if ($value$plusargs("WAVE=%d", runtime_wave_enable)) begin
            end
            if (!$value$plusargs("WAVE_FILE=%s", wave_file_path)) begin
                wave_file_path = "cnn_tb.vcd";
            end

            input_mem_path         = $sformatf("%0s/samples/sample_input_rows.mem", prep_dir);
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

    // 在循环等待场景下统一做超时保护。
    task automatic check_timeout;
        begin
            if (cycle_counter > timeout_cycles) begin
                $display("TB_ERROR timeout cycles=%0d", cycle_counter);
                $finish_and_return(3);
            end
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
            $readmemh(pwconv_weight_mem_path, pwconv_weight_words_mem);
            $readmemh(pwconv_bias_mem_path, pwconv_bias_words_mem);
            $readmemh(fc_weight_mem_path, fc_weight_words_mem);
            $readmemh(fc_bias_mem_path, fc_bias_words_mem);
            $readmemh(sigmoid_lut_mem_path, sigmoid_lut_words_mem);
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

    // 逐 word 装载各层权重。
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

    // 逐 word 装载各层偏置。
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

    // 装载 Sigmoid LUT。
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

    // 只有在 DUT 明确允许时，才开始写下一帧输入。
    task automatic wait_img_wr_ready;
        begin
            while (!img_wr_ready) begin
                @(posedge clk);
                check_timeout();
            end
        end
    endtask

    // 连续写入 30 行输入图，随后用 img_wr_commit 提交整帧。
    task automatic load_input_sample_and_commit(input integer sample_id);
        begin
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

            @(posedge clk);
            $display("INPUT_COMMIT sample=%0d cycle=%0d", sample_id, cycle_counter);
        end
    endtask

    // 首帧通过 start 让顶层进入连续运行模式。
    task automatic start_run;
        begin
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            $display("RUN_ENABLE cycle=%0d", cycle_counter);
        end
    endtask

    // 等待所有重复输入样本都得到最终 done。
    task automatic wait_samples_done_or_timeout(input integer expected_done_count);
        begin
            while (sample_done_counter < expected_done_count) begin
                @(posedge clk);
                check_timeout();
            end
            @(posedge clk);
        end
    endtask

    // 全局周期计数。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end

    // 统计整网输出完成次数，每个 done 对应一帧推理完成。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_done_counter <= 0;
        end else if (done) begin
            $display("SAMPLE_DONE sample=%0d cycles=%0d", sample_done_counter, cycle_counter);
            sample_done_counter <= sample_done_counter + 1;
        end
    end

    // Conv 输出统计与断流检测。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            conv_tile_counter <= 0;
            conv_frame_token_count <= 0;
            conv_in_frame <= 1'b0;
            conv_stream_gap_error <= 1'b0;
        end else begin
            if (conv_out_stream_valid) begin
                conv_tile_counter <= conv_tile_counter + 1;
                conv_frame_token_count <= conv_frame_token_count + 1;
                conv_in_frame <= 1'b1;
                $display("Conv-Out-Stream: pos=%0d group=%0d data=%0128x", conv_out_stream_pos, conv_out_stream_group, conv_out_stream_data);
                if (conv_out_stream_last) begin
                    if ((conv_frame_token_count + 1) != TOKEN_COUNT) begin
                        conv_stream_gap_error <= 1'b1;
                    end
                    conv_frame_token_count <= 0;
                    conv_in_frame <= 1'b0;
                end
            end else if (conv_in_frame) begin
                conv_stream_gap_error <= 1'b1;
            end
        end
    end

    // DWConv 输出统计与断流检测。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dwconv_tile_counter <= 0;
            dwconv_frame_token_count <= 0;
            dwconv_in_frame <= 1'b0;
            dwconv_stream_gap_error <= 1'b0;
        end else begin
            if (dwconv_out_stream_valid) begin
                dwconv_tile_counter <= dwconv_tile_counter + 1;
                dwconv_frame_token_count <= dwconv_frame_token_count + 1;
                dwconv_in_frame <= 1'b1;
                $display("DWConv-Out-Stream: pos=%0d group=%0d data=%032x", dwconv_out_stream_pos, dwconv_out_stream_group, dwconv_out_stream_data);
                if (dwconv_out_stream_last) begin
                    if ((dwconv_frame_token_count + 1) != TOKEN_COUNT) begin
                        dwconv_stream_gap_error <= 1'b1;
                    end
                    dwconv_frame_token_count <= 0;
                    dwconv_in_frame <= 1'b0;
                end
            end else if (dwconv_in_frame) begin
                dwconv_stream_gap_error <= 1'b1;
            end
        end
    end

    // PWConv 输出统计与断流检测。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwconv_tile_counter <= 0;
            pwconv_frame_token_count <= 0;
            pwconv_in_frame <= 1'b0;
            pwconv_stream_gap_error <= 1'b0;
        end else begin
            if (pwconv_out_stream_valid) begin
                pwconv_tile_counter <= pwconv_tile_counter + 1;
                pwconv_frame_token_count <= pwconv_frame_token_count + 1;
                pwconv_in_frame <= 1'b1;
                $display("PWConv-Out-Stream: pos=%0d group=%0d data=%032x", pwconv_out_stream_pos, pwconv_out_stream_group, pwconv_out_stream_data);
                if (pwconv_out_stream_last) begin
                    if ((pwconv_frame_token_count + 1) != TOKEN_COUNT) begin
                        pwconv_stream_gap_error <= 1'b1;
                    end
                    pwconv_frame_token_count <= 0;
                    pwconv_in_frame <= 1'b0;
                end
            end else if (pwconv_in_frame) begin
                pwconv_stream_gap_error <= 1'b1;
            end
        end
    end

    // Maxpool 输出统计与断流检测。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            maxpool_tile_counter <= 0;
            maxpool_frame_token_count <= 0;
            maxpool_in_frame <= 1'b0;
            maxpool_stream_gap_error <= 1'b0;
        end else begin
            if (maxpool_out_stream_valid) begin
                maxpool_tile_counter <= maxpool_tile_counter + 1;
                maxpool_frame_token_count <= maxpool_frame_token_count + 1;
                maxpool_in_frame <= 1'b1;
                $display("Maxpool-Out-Stream: pos=%0d group=%0d data=%08x", maxpool_out_stream_pos, maxpool_out_stream_group, maxpool_out_stream_data);
                if (maxpool_out_stream_last) begin
                    if ((maxpool_frame_token_count + 1) != TOKEN_COUNT) begin
                        maxpool_stream_gap_error <= 1'b1;
                    end
                    maxpool_frame_token_count <= 0;
                    maxpool_in_frame <= 1'b0;
                end
            end else if (maxpool_in_frame) begin
                maxpool_stream_gap_error <= 1'b1;
            end
        end
    end

    // FC 输出统计。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_tile_counter <= 0;
        end else if (fc_out_stream_valid) begin
            fc_tile_counter <= fc_tile_counter + 1;
            $display("FC-Out-Stream: data=%04x", fc_out_stream_data);
        end
    end

    // Sigmoid 输出统计。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sigmoid_tile_counter <= 0;
        end else if (sigmoid_out_stream_valid) begin
            sigmoid_tile_counter <= sigmoid_tile_counter + 1;
            $display("Sigmoid-Out-Stream: data=%016x", sigmoid_out_stream_data);
        end
    end

    // 主测试流程：
    // - 初始化与读入数据
    // - 依次写参数
    // - 连续提交多帧输入
    // - 等待全部帧完成并做基本自检
    initial begin
        init_signals();
        parse_plusargs();

        if (runtime_wave_enable != 0) begin
            $dumpfile(wave_file_path);
            $dumpvars(0, cnn_tb);
        end

        load_memories();
        apply_reset();
        load_weights();
        load_bias();
        load_sigmoid_lut();

        for (sample_idx = 0; sample_idx < runtime_sample_count; sample_idx = sample_idx + 1) begin
            wait_img_wr_ready();
            load_input_sample_and_commit(sample_idx);
            if (sample_idx == 0) begin
                start_run();
            end
        end

        wait_samples_done_or_timeout(runtime_sample_count);

        if (conv_tile_counter !== (runtime_sample_count * TOKEN_COUNT)) begin
            $display("TB_ERROR conv_tile_count got=%0d expected=%0d", conv_tile_counter, runtime_sample_count * TOKEN_COUNT);
            $finish_and_return(4);
        end
        if (dwconv_tile_counter !== (runtime_sample_count * TOKEN_COUNT)) begin
            $display("TB_ERROR dwconv_tile_count got=%0d expected=%0d", dwconv_tile_counter, runtime_sample_count * TOKEN_COUNT);
            $finish_and_return(4);
        end
        if (pwconv_tile_counter !== (runtime_sample_count * TOKEN_COUNT)) begin
            $display("TB_ERROR pwconv_tile_count got=%0d expected=%0d", pwconv_tile_counter, runtime_sample_count * TOKEN_COUNT);
            $finish_and_return(4);
        end
        if (maxpool_tile_counter !== (runtime_sample_count * TOKEN_COUNT)) begin
            $display("TB_ERROR maxpool_tile_count got=%0d expected=%0d", maxpool_tile_counter, runtime_sample_count * TOKEN_COUNT);
            $finish_and_return(4);
        end
        if (fc_tile_counter !== runtime_sample_count) begin
            $display("TB_ERROR fc_tile_count got=%0d expected=%0d", fc_tile_counter, runtime_sample_count);
            $finish_and_return(4);
        end
        if (sigmoid_tile_counter !== runtime_sample_count) begin
            $display("TB_ERROR sigmoid_tile_count got=%0d expected=%0d", sigmoid_tile_counter, runtime_sample_count);
            $finish_and_return(4);
        end

        if (conv_stream_gap_error || dwconv_stream_gap_error || pwconv_stream_gap_error || maxpool_stream_gap_error) begin
            $display(
                "TB_ERROR stream_gap conv=%0d dwconv=%0d pwconv=%0d maxpool=%0d",
                conv_stream_gap_error,
                dwconv_stream_gap_error,
                pwconv_stream_gap_error,
                maxpool_stream_gap_error
            );
            $finish_and_return(5);
        end

        $display("TB_PASS samples=%0d cycles=%0d", runtime_sample_count, cycle_counter);
        $finish_and_return(0);
    end

endmodule
