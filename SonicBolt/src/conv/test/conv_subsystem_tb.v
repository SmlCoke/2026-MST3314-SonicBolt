`timescale 1ns / 1ps
/*
 * 模块名称: conv_subsystem_tb
 *
 * 功能概述:
 *   面向当前 pos-major `conv_subsystem` 的自检 testbench。
 *   这份 testbench 只做三件事：
 *   1. 从预处理后的 mem 文件中读取 Conv1 整层参数和单个样本输入
 *   2. 通过 `conv_subsystem` 的顶层写口依次装载参数与输入图
 *   3. 捕获 `out_stream_*` 输出，并打印机器可解析的 TILE 结果行
 *
 * 当前版本说明:
 *   - 当前 Conv1 采用 `4 通道 / group`，因此每个样本应输出 `72` 个 tile
 *   - 每个 tile 的数据宽度为 `512bit = 4ch x 4x4 x 8bit`
 *   - 调试缓存逻辑已经从 `conv_subsystem` 中移除
 *   - 如果需要把 tile 暂存、重排或按 bank 回看，应由 testbench 自己完成
 *
 * 日志格式:
 *   - 每个有效 tile 输出一行：
 *       TILE sample=<n> pos=<p> group=<g> data=<128hex>
 *   - 一个样本结束后输出：
 *       SAMPLE_DONE sample=<n> cycles=<c>
 *
 * 波形控制:
 *   - 参数 `ENABLE_WAVE=0` 时默认不写波形
 *   - 也可以通过 plusargs `+WAVE` 或 `+WAVE=1` 在运行时开启
 */
module conv_subsystem_tb #(
    parameter integer ENABLE_WAVE = 0
) ();

    // ---------------------------------------------------------------------
    // 基本仿真参数
    // ---------------------------------------------------------------------
    localparam integer CLK_HALF_PERIOD = 5;   // 半周期 5ns，对应 100MHz 时钟
    localparam integer INPUT_ROW_COUNT = 30;  // 输入图一共 30 行
    localparam integer WEIGHT_WORD_COUNT = 88;// 11 个 weight bank x 8 个 group = 88 个权重 word
    localparam integer BIAS_WORD_COUNT = 8;   // 1 个 bias bank x 8 个 group = 8 个偏置 word
    localparam integer TOKEN_COUNT = 72;      // 9 个 pos x 8 个 group = 72 个输出 token

    // ---------------------------------------------------------------------
    // DUT 顶层控制信号
    // ---------------------------------------------------------------------
    reg clk;                // 测试时钟
    reg rst_n;              // 低有效复位
    reg start;              // 启动一次样本计算
    reg start_buf_sel;      // 选择本次使用哪个输入 buffer
    wire busy;              // DUT 正在处理当前样本
    wire done;              // DUT 对当前样本发出的完成脉冲

    // ---------------------------------------------------------------------
    // 输入图写口
    // DUT 通过这个接口逐行接收一张 30x10 的输入图
    // 一行 10 个 INT8，共 80bit，拆成低 40bit 和高 40bit 两段写入
    // ---------------------------------------------------------------------
    reg img_wr_en;          // 输入图写使能
    reg img_wr_buf_sel;     // 写入哪个输入 buffer
    reg [4:0] img_wr_addr;  // 输入图行地址，0..29 用 5bit 表示
    reg [39:0] img_wr_data_lo; // 当前行前 5 个像素，5 x 8bit = 40bit
    reg [39:0] img_wr_data_hi; // 当前行后 5 个像素，5 x 8bit = 40bit

    // ---------------------------------------------------------------------
    // 权重写口
    // 当前 Conv1 参数组织为：
    //   - 11 个 weight bank
    //   - 每个 bank 深度 8，对应 group=0..7
    //   - 每个 word 宽度 224bit = 4ch x 7 x 8bit
    // ---------------------------------------------------------------------
    reg weight_wr_en;          // 权重写使能
    reg [4:0] weight_wr_bank;  // 写入哪个权重 bank，当前有效范围 0..10
    reg [2:0] weight_wr_addr;  // 写入哪个 group 地址，0..7 用 3bit 表示
    reg [223:0] weight_wr_data;// 1 个权重 word，宽度 224bit

    // ---------------------------------------------------------------------
    // 偏置写口
    // 当前 Conv1 偏置组织为：
    //   - 1 个 bias bank
    //   - 深度 8，对应 group=0..7
    //   - 每个 word 宽度 64bit = 4 x INT16
    // ---------------------------------------------------------------------
    reg bias_wr_en;         // 偏置写使能
    reg bias_wr_bank;       // 偏置 bank 选择，当前始终写 0
    reg [2:0] bias_wr_addr; // 偏置 group 地址，0..7
    reg [63:0] bias_wr_data;// 1 个偏置 word，宽度 64bit

    // ---------------------------------------------------------------------
    // 主输出流接口
    // testbench 通过这组信号直接验证 DUT 主路径
    // 每个 token 对应一个 {pos, group} 的完整 4ch x 4x4 tile
    // ---------------------------------------------------------------------
    reg out_stream_ready;       // 下游 ready，当前测试默认始终拉高
    wire out_stream_valid;      // 输出 tile 有效
    wire [3:0] out_stream_pos;  // 输出 tile 所属的 pos，范围 0..8
    wire [2:0] out_stream_group;// 输出 tile 所属的 group，范围 0..7
    wire [511:0] out_stream_data;// 输出 tile 数据，宽度 512bit

    // ---------------------------------------------------------------------
    // 本地内存数组
    // 这些数组只存在于 testbench 中，用来缓存从 mem 文件读入的测试数据
    // ---------------------------------------------------------------------
    reg [79:0] input_rows_mem [0:INPUT_ROW_COUNT-1];     // 30 行输入，每行 80bit
    reg [223:0] weight_words_mem [0:WEIGHT_WORD_COUNT-1];// 88 个权重 word
    reg [63:0] bias_words_mem [0:BIAS_WORD_COUNT-1];     // 8 个偏置 word

    // ---------------------------------------------------------------------
    // 仿真流程控制变量
    // ---------------------------------------------------------------------
    integer sample_id;           // 当前运行的样本编号
    integer timeout_cycles;      // 单样本最大允许周期数，超时则报错退出
    integer cycle_counter;       // 样本运行期间的周期计数器
    integer tile_counter;        // 当前样本已输出的 tile 数量
    integer row_idx;             // 输入图逐行写入时的循环索引
    integer weight_idx;          // 权重逐 word 写入时的循环索引
    integer bias_idx;            // 偏置逐 word 写入时的循环索引
    integer runtime_wave_enable; // 运行时是否开启波形

    // ---------------------------------------------------------------------
    // 文件路径字符串
    // 由 plusargs 拼出本次样本对应的输入/参数文件路径
    // ---------------------------------------------------------------------
    string prep_dir;        // 预处理数据根目录，例如 prepared_conv_test
    string input_mem_path;  // 当前样本输入文件路径
    string weight_mem_path; // 权重文件路径
    string bias_mem_path;   // 偏置文件路径
    string wave_file_path;  // VCD 波形输出文件路径

    // ---------------------------------------------------------------------
    // DUT 实例
    // 当前 testbench 只连接综合主通路会真实存在的接口
    // 不再连接任何调试 SRAM 旁路
    // ---------------------------------------------------------------------
    conv_subsystem dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .start_buf_sel(start_buf_sel),
        .busy(busy),
        .done(done),
        .img_wr_en(img_wr_en),
        .img_wr_buf_sel(img_wr_buf_sel),
        .img_wr_addr(img_wr_addr),
        .img_wr_data_lo(img_wr_data_lo),
        .img_wr_data_hi(img_wr_data_hi),
        .weight_wr_en(weight_wr_en),
        .weight_wr_bank(weight_wr_bank),
        .weight_wr_addr(weight_wr_addr),
        .weight_wr_data(weight_wr_data),
        .bias_wr_en(bias_wr_en),
        .bias_wr_bank(bias_wr_bank),
        .bias_wr_addr(bias_wr_addr),
        .bias_wr_data(bias_wr_data),
        .out_stream_ready(out_stream_ready),
        .out_stream_valid(out_stream_valid),
        .out_stream_pos(out_stream_pos),
        .out_stream_group(out_stream_group),
        .out_stream_data(out_stream_data)
    );

    // 时钟翻转逻辑：每隔半周期翻转一次
    always #(CLK_HALF_PERIOD) clk = ~clk;

    // ---------------------------------------------------------------------
    // 初始化全部驱动信号和计数器
    // 这个 task 只做 testbench 本地初始化，不与 DUT 交互
    // ---------------------------------------------------------------------
    task automatic init_signals;
        begin
            clk = 1'b0;
            rst_n = 1'b0;
            start = 1'b0;
            start_buf_sel = 1'b0;
            img_wr_en = 1'b0;
            img_wr_buf_sel = 1'b0;
            img_wr_addr = 5'd0;
            img_wr_data_lo = 40'd0;
            img_wr_data_hi = 40'd0;
            weight_wr_en = 1'b0;
            weight_wr_bank = 5'd0;
            weight_wr_addr = 3'd0;
            weight_wr_data = 224'd0;
            bias_wr_en = 1'b0;
            bias_wr_bank = 1'b0;
            bias_wr_addr = 3'd0;
            bias_wr_data = 64'd0;
            out_stream_ready = 1'b1;
            cycle_counter = 0;
            tile_counter = 0;
        end
    endtask

    // ---------------------------------------------------------------------
    // 解析命令行 plusargs
    // 必填:
    //   +PREP_DIR=<预处理目录>
    // 可选:
    //   +SAMPLE_ID=<样本编号>
    //   +TIMEOUT_CYCLES=<超时周期数>
    //   +WAVE 或 +WAVE=1
    //   +WAVE_FILE=<波形文件路径>
    // ---------------------------------------------------------------------
    task automatic parse_plusargs;
        begin
            prep_dir = "";
            wave_file_path = "";
            sample_id = 0;
            timeout_cycles = 4000;
            runtime_wave_enable = ENABLE_WAVE;

            if (!$value$plusargs("PREP_DIR=%s", prep_dir)) begin
                $display("TB_ERROR missing +PREP_DIR");
                $finish_and_return(2);
            end
            if (!$value$plusargs("SAMPLE_ID=%d", sample_id)) begin
                sample_id = 0;
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

            // 预处理脚本已经把输入、权重和偏置整理成固定目录结构
            input_mem_path = $sformatf("%0s/samples/sample_%03d_input_rows.mem", prep_dir, sample_id);
            weight_mem_path = $sformatf("%0s/weights/weight_words.mem", prep_dir);
            bias_mem_path = $sformatf("%0s/bias/bias_words.mem", prep_dir);
        end
    endtask

    // ---------------------------------------------------------------------
    // 从 mem 文件把当前样本要用的数据读到 testbench 本地数组
    // 这里只是读文件，不会立刻驱动 DUT
    // ---------------------------------------------------------------------
    task automatic load_memories;
        begin
            $readmemh(input_mem_path, input_rows_mem);
            $readmemh(weight_mem_path, weight_words_mem);
            $readmemh(bias_mem_path, bias_words_mem);
        end
    endtask

    // ---------------------------------------------------------------------
    // 施加复位
    // 先保持若干拍低复位，再在时钟沿释放
    // ---------------------------------------------------------------------
    task automatic apply_reset;
        begin
            repeat (4) @(posedge clk);
            rst_n <= 1'b1;
            @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------------------
    // 逐 word 装载 Conv1 整层权重
    // 映射规则:
    //   weight_idx / 8 -> bank 编号
    //   weight_idx % 8 -> group 地址
    // 因为每个 weight bank 深度 8，对应 8 个 group
    // ---------------------------------------------------------------------
    task automatic load_weights;
        begin
            for (weight_idx = 0; weight_idx < WEIGHT_WORD_COUNT; weight_idx = weight_idx + 1) begin
                @(posedge clk);
                weight_wr_en <= 1'b1;
                weight_wr_bank <= weight_idx / 8;
                weight_wr_addr <= weight_idx % 8;
                weight_wr_data <= weight_words_mem[weight_idx];
            end
            @(posedge clk);
            weight_wr_en <= 1'b0;
            weight_wr_bank <= 5'd0;
            weight_wr_addr <= 3'd0;
            weight_wr_data <= 224'd0;
        end
    endtask

    // ---------------------------------------------------------------------
    // 逐 word 装载 Conv1 整层偏置
    // 当前只有 1 个 bias bank，因此 bank 始终写 0
    // ---------------------------------------------------------------------
    task automatic load_bias;
        begin
            for (bias_idx = 0; bias_idx < BIAS_WORD_COUNT; bias_idx = bias_idx + 1) begin
                @(posedge clk);
                bias_wr_en <= 1'b1;
                bias_wr_bank <= 1'b0;
                bias_wr_addr <= bias_idx % 8;
                bias_wr_data <= bias_words_mem[bias_idx];
            end
            @(posedge clk);
            bias_wr_en <= 1'b0;
            bias_wr_bank <= 1'b0;
            bias_wr_addr <= 3'd0;
            bias_wr_data <= 64'd0;
        end
    endtask

    // ---------------------------------------------------------------------
    // 逐行写入当前样本输入图
    // 每一拍写入 1 行，共 30 行
    // row_word[39:0]   -> 低半部分 5 个像素
    // row_word[79:40]  -> 高半部分 5 个像素
    // ---------------------------------------------------------------------
    task automatic load_input_sample;
        reg [79:0] row_word;
        begin
            for (row_idx = 0; row_idx < INPUT_ROW_COUNT; row_idx = row_idx + 1) begin
                row_word = input_rows_mem[row_idx];
                @(posedge clk);
                img_wr_en <= 1'b1;
                img_wr_buf_sel <= 1'b0;
                img_wr_addr <= row_idx[4:0];
                img_wr_data_lo <= row_word[39:0];
                img_wr_data_hi <= row_word[79:40];
            end
            @(posedge clk);
            img_wr_en <= 1'b0;
            img_wr_buf_sel <= 1'b0;
            img_wr_addr <= 5'd0;
            img_wr_data_lo <= 40'd0;
            img_wr_data_hi <= 40'd0;
        end
    endtask

    // ---------------------------------------------------------------------
    // 发起一次运行
    // `start` 拉高 1 拍，`start_buf_sel=0` 表示本次消费 buffer0
    // ---------------------------------------------------------------------
    task automatic start_run;
        begin
            @(posedge clk);
            start <= 1'b1;
            start_buf_sel <= 1'b0;
            @(posedge clk);
            start <= 1'b0;
        end
    endtask

    // ---------------------------------------------------------------------
    // 等待 DUT 完成，或在超时后报错退出
    // ---------------------------------------------------------------------
    task automatic wait_done_or_timeout;
        begin
            while (!done) begin
                @(posedge clk);
                if (cycle_counter > timeout_cycles) begin
                    $display("TB_ERROR timeout sample=%0d cycles=%0d", sample_id, cycle_counter);
                    $finish_and_return(3);
                end
            end
            @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------------------
    // 在线统计输出 token 数，并把每个 tile 按固定格式打印到 stdout
    // Python 脚本会解析这里的 TILE 行并与黄金结果逐项比较
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 0;
            tile_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            if (out_stream_valid) begin
                tile_counter <= tile_counter + 1;
                $display("TILE sample=%0d pos=%0d group=%0d data=%0128x",
                    sample_id, out_stream_pos, out_stream_group, out_stream_data);
            end
        end
    end

    // ---------------------------------------------------------------------
    // 主测试流程
    // 顺序固定为：
    //   1. 初始化信号
    //   2. 解析 plusargs
    //   3. 可选开启波形
    //   4. 读取 mem 文件
    //   5. 复位 DUT
    //   6. 装载权重
    //   7. 装载偏置
    //   8. 装载输入
    //   9. 启动运行
    //  10. 等待 done
    //  11. 检查 tile 数是否等于 72
    // ---------------------------------------------------------------------
    initial begin
        init_signals();
        parse_plusargs();

        if (runtime_wave_enable != 0) begin
            $dumpfile(wave_file_path);
            $dumpvars(0, conv_subsystem_tb);
        end

        load_memories();
        apply_reset();
        load_weights();
        load_bias();
        load_input_sample();
        start_run();
        wait_done_or_timeout();

        if (tile_counter !== TOKEN_COUNT) begin
            $display("TB_ERROR tile_count sample=%0d got=%0d expected=%0d", sample_id, tile_counter, TOKEN_COUNT);
            $finish_and_return(4);
        end

        $display("SAMPLE_DONE sample=%0d cycles=%0d", sample_id, cycle_counter);
        $finish_and_return(0);
    end

endmodule
