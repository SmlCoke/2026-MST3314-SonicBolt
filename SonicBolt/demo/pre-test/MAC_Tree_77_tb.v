`timescale 1ns / 1ps

module MAC_Tree_77_tb;

    reg                 clk;
    reg                 rst_n;
    reg                 valid_in;
    reg  [615:0]        act_flat_in;
    reg  [615:0]        wgt_flat_in;
    reg  signed [15:0]  bias_in;

    wire                valid_out;
    wire signed [31:0]  mac_out;

    MAC_Tree_77 dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .act_flat_in(act_flat_in),
        .wgt_flat_in(wgt_flat_in),
        .bias_in    (bias_in),
        .valid_out  (valid_out),
        .mac_out    (mac_out)
    );

    integer i;
    integer out_seen;

    // 100MHz 时钟（仅用于仿真）
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    initial begin
        // 初始化
        rst_n       = 1'b0;
        valid_in    = 1'b0;
        act_flat_in = 616'd0;
        wgt_flat_in = 616'd0;
        bias_in     = -16'sd5;
        out_seen    = 0;

        // 复位
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // 固定输入：77个act全部=1，77个wgt全部=2
        @(negedge clk);
        for (i = 0; i < 77; i = i + 1) begin
            act_flat_in[i*8 +: 8] = 8'sd1;
            wgt_flat_in[i*8 +: 8] = 8'sd2;
        end
        valid_in = 1'b1;

        // 仅打一拍输入
        @(negedge clk);
        valid_in = 1'b0;
        act_flat_in = 616'd0;
        wgt_flat_in = 616'd0;

        // 等待输出并检查：77*2-5 = 149
        repeat (20) begin
            @(posedge clk);
            if (valid_out) begin
                out_seen = out_seen + 1;
                if (mac_out === 32'sd149) begin
                    $display("[TB] PASS: mac_out=%0d (expected 149)", mac_out);
                    $finish;
                end else begin
                    $display("[TB] FAIL: mac_out=%0d (expected 149)", mac_out);
                    $fatal;
                end
            end
        end

        if (out_seen == 0) begin
            $display("[TB] FAIL: timeout, valid_out 未拉高");
            $fatal;
        end
    end

endmodule
