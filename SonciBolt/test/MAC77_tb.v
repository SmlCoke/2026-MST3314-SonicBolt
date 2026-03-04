`timescale 1ns / 1ps

module MAC77_tb;

    reg                 clk;
    reg                 rst_n;
    reg                 valid_in;
    reg  [615:0]        act_flat_in;
    reg  [615:0]        wgt_flat_in;
    reg  signed [15:0]  bias_in;

    wire                valid_out;
    wire signed [31:0]  mac_out;

    integer i;
    integer out_seen;

    MAC77 dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_in   (valid_in),
        .act_flat_in(act_flat_in),
        .wgt_flat_in(wgt_flat_in),
        .bias_in    (bias_in),
        .valid_out  (valid_out),
        .mac_out    (mac_out)
    );

    // 10ns周期
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n       = 1'b0;
        valid_in    = 1'b0;
        act_flat_in = 616'd0;
        wgt_flat_in = 616'd0;
        bias_in     = -16'sd5;
        out_seen    = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // 单次输入：77个act=1，77个wgt=2
        @(negedge clk);
        for (i = 0; i < 77; i = i + 1) begin
            act_flat_in[i*8 +: 8] = 8'sd1;
            wgt_flat_in[i*8 +: 8] = 8'sd2;
        end
        valid_in = 1'b1;

        // 只打一拍
        @(negedge clk);
        valid_in = 1'b0;
        act_flat_in = 616'd0;
        wgt_flat_in = 616'd0;

        // 等待输出并自动检查
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
