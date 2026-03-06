`timescale 1ns / 1ps

module tb_Conv1;
    reg clk;
    reg rst_n;
    reg start;

    wire        busy;
    wire        done;
    wire        in_row_req;
    wire [4:0]  in_row_addr;
    reg  [79:0] in_row_data;
    reg         in_row_valid;

    wire        wgt_req;
    wire [5:0]  wgt_addr;
    reg  [615:0] wgt_data;
    reg  [15:0]  bias_data;
    reg          wgt_valid;

    wire        out_valid;
    wire [255:0] out_data;

    reg [79:0]   input_mem  [0:29];
    reg [615:0]  weight_mem [0:31];
    reg [15:0]   bias_mem   [0:31];

    integer fout;
    integer out_cnt;
    integer cycle_cnt;
    integer ch;

    reg       in_pending;
    reg [4:0] in_pending_addr;
    reg [1:0] in_pending_delay;

    reg       wgt_pending;
    reg [5:0] wgt_pending_addr;
    reg [1:0] wgt_pending_delay;

    function [1:0] rand_0_2;
        integer r;
        begin
            r = $random;
            if (r < 0) r = -r;
            rand_0_2 = r % 3;
        end
    endfunction

    Conv1_Top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .busy       (busy),
        .done       (done),

        .in_row_req (in_row_req),
        .in_row_addr(in_row_addr),
        .in_row_data(in_row_data),
        .in_row_valid(in_row_valid),

        .wgt_req    (wgt_req),
        .wgt_addr   (wgt_addr),
        .wgt_data   (wgt_data),
        .bias_data  (bias_data),
        .wgt_valid  (wgt_valid),

        .out_valid  (out_valid),
        .out_data   (out_data)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("conv1.vcd");
        $dumpvars(0, tb_Conv1);
    end

    initial begin
        $readmemh("input.txt",  input_mem);
        $readmemh("weight.txt", weight_mem);
        $readmemh("bias.txt",   bias_mem);

        fout = $fopen("hw_output.txt", "w");
        if (fout == 0) begin
            $display("[TB] ERROR: hw_output.txt 打开失败");
            $fatal;
        end
    end

    // 输入行接口：根据 in_row_req 回传，附加 0~2 拍随机等待
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_row_valid       <= 1'b0;
            in_row_data        <= 80'd0;
            in_pending         <= 1'b0;
            in_pending_addr    <= 5'd0;
            in_pending_delay   <= 2'd0;
        end else begin
            in_row_valid <= 1'b0;

            if (in_pending) begin
                if (in_pending_delay == 2'd0) begin
                    in_row_data      <= input_mem[in_pending_addr];
                    in_row_valid     <= 1'b1;
                    in_pending       <= 1'b0;
                end else begin
                    in_pending_delay <= in_pending_delay - 2'd1;
                end
            end else if (in_row_req) begin
                in_pending       <= 1'b1;
                in_pending_addr  <= in_row_addr;
                in_pending_delay <= rand_0_2();
            end
        end
    end

    // 权重接口：根据 wgt_req 回传，附加 0~2 拍随机等待
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgt_valid         <= 1'b0;
            wgt_data          <= 616'd0;
            bias_data         <= 16'd0;
            wgt_pending       <= 1'b0;
            wgt_pending_addr  <= 6'd0;
            wgt_pending_delay <= 2'd0;
        end else begin
            wgt_valid <= 1'b0;

            if (wgt_pending) begin
                if (wgt_pending_delay == 2'd0) begin
                    wgt_data    <= weight_mem[wgt_pending_addr];
                    bias_data   <= bias_mem[wgt_pending_addr];
                    wgt_valid   <= 1'b1;
                    wgt_pending <= 1'b0;
                end else begin
                    wgt_pending_delay <= wgt_pending_delay - 2'd1;
                end
            end else if (wgt_req) begin
                wgt_pending       <= 1'b1;
                wgt_pending_addr  <= wgt_addr;
                wgt_pending_delay <= rand_0_2();
            end
        end
    end

    // 输出日志 + 基本检查
    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            out_cnt = out_cnt + 1;

            for (ch = 0; ch < 32; ch = ch + 1) begin
                if (out_data[ch*8 + 7] == 1'b1) begin
                    $display("[TB] ERROR: 输出超出 0~127，ch=%0d, val=%02x", ch, out_data[ch*8 +: 8]);
                    $fatal;
                end
            end

            for (ch = 0; ch < 32; ch = ch + 1) begin
                if (ch == 31) begin
                    $fwrite(fout, "%02x", out_data[ch*8 +: 8]);
                end else begin
                    $fwrite(fout, "%02x ", out_data[ch*8 +: 8]);
                end
            end
            $fwrite(fout, "\n");
        end
    end

    initial begin
        rst_n     = 1'b0;
        start     = 1'b0;
        out_cnt   = 0;
        cycle_cnt = 0;

        repeat (6) @(posedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        while ((cycle_cnt < 5000) && (done == 1'b0)) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
        end

        if (done == 1'b0) begin
            $display("[TB] ERROR: 超时，未等到 done");
            $fatal;
        end

        repeat (8) @(posedge clk);
        $fclose(fout);

        if (out_cnt != 80) begin
            $display("[TB] ERROR: out_valid 次数错误，实际=%0d, 期望=80", out_cnt);
            $fatal;
        end

        $display("[TB] PASS: done 到达，out_valid=%0d，输出文件已写入 hw_output.txt", out_cnt);
        $finish;
    end

endmodule

