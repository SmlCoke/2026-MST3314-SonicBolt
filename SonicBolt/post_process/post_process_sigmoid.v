`timescale 1ns / 1ps
/*
 * 模块名称: post_process_sigmoid
 * 作者: SonicBolt 团队
 * 日期: 2026-04-02
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对 2 路 INT8 FC 输出执行 Sigmoid LUT 查表
 *   - LUT 深度 256，每项 32bit（IEEE754 FP32 位模式）
 *   - 输出 2 路 FP32（64bit 总线）
 *
 * 设计说明:
 *   - x=-128 对应 8'h80，x=0 对应 8'h00，x=127 对应 8'h7f
 *   - LUT 通过在线写端口加载到 256x32 单端口 SRAM
 *   - 单端口 SRAM 读口一次只读一个地址：先读低 8 位地址，再读高 8 位地址
 */
module post_process_sigmoid (
    input  wire        clk,
    input  wire        rst_n,

    // ---------- 输入 metadata ----------
    input  wire        in_valid,
    input  wire        in_last,
    input  wire [3:0]  in_pos,
    input  wire [2:0]  in_group,
    input  wire        in_fire,

    // ---------- 输入数据 ----------
    input  wire [15:0] in_data_bus,

    // ---------- LUT 写接口 ----------
    input  wire        lut_wr_en,
    input  wire [7:0]  lut_wr_addr,
    input  wire [31:0] lut_wr_data,

    // ---------- 输出 metadata ----------
    output wire        out_valid,
    output wire        out_last,
    output wire [3:0]  out_pos,
    output wire [2:0]  out_group,
    output wire        out_fire,

    // ---------- 输出数据 ----------
    output wire [63:0] out_data_bus
);

    localparam [1:0] RD_IDLE  = 2'd0;// 等待读地址
    localparam [1:0] RD_WAIT0 = 2'd1;// 已读第 1 个地址，等待第 2 个地址
    localparam [1:0] RD_WAIT1 = 2'd2;// 已读第 2 个地址，等待数据有效

    reg [1:0] rd_state;

    reg [7:0] req_addr1;
    reg [31:0] first_lut_word;
    reg        req_last;
    reg [3:0]  req_pos;
    reg [2:0]  req_group;
    reg        req_fire;

    wire       lut_sram_en;
    wire       lut_sram_wr_en;
    wire [7:0] lut_sram_addr;
    wire [31:0] lut_sram_wdata;
    wire [31:0] lut_sram_rdata;

    wire lut_write_cmd;// 写 LUT 的命令信号
    wire lut_read0_cmd;// 读 LUT 的第 1 个地址的命令信号
    wire lut_read1_cmd;// 读 LUT 的第 2 个地址的命令信号

    reg [63:0] stage0_data_bus;// 从 LUT 读出的两拍数据组合成的完整 FP32 输出数据

    reg        stage0_valid;
    reg        stage0_last;
    reg [3:0]  stage0_pos;
    reg [2:0]  stage0_group;
    reg        stage0_fire;

    assign lut_write_cmd = (rd_state == RD_IDLE) && lut_wr_en;
    assign lut_read0_cmd = (rd_state == RD_IDLE) && in_valid && !lut_wr_en;//读使能
    assign lut_read1_cmd = (rd_state == RD_WAIT0);

    assign lut_sram_en    = lut_write_cmd || lut_read0_cmd || lut_read1_cmd;
    assign lut_sram_wr_en = lut_write_cmd;
    assign lut_sram_addr  = lut_write_cmd ? lut_wr_addr :
                            (lut_read0_cmd ? in_data_bus[7:0] :
                            (lut_read1_cmd ? req_addr1 : 8'd0));
    assign lut_sram_wdata = lut_wr_data;

    sram_sp #(
        .DATA_W(32),
        .DEPTH(256),
        .ADDR_W(8)
    ) u_sigmoid_lut_sram (
        .clk(clk),
        .rst_n(rst_n),
        .en(lut_sram_en),
        .wr_en(lut_sram_wr_en),
        .addr(lut_sram_addr),
        .wdata(lut_sram_wdata),
        .rdata(lut_sram_rdata)
    );

    // LUT 单端口 SRAM：先读 addr0，再读 addr1，两拍组包后进入 stage0
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;

            req_addr1      <= 8'd0;
            first_lut_word <= 32'd0;
            req_last       <= 1'b0;
            req_pos        <= 4'd0;
            req_group      <= 3'd0;
            req_fire       <= 1'b0;

            stage0_data_bus <= 64'd0;

            stage0_valid <= 1'b0;
            stage0_last  <= 1'b0;
            stage0_pos   <= 4'd0;
            stage0_group <= 3'd0;
            stage0_fire  <= 1'b0;
        end else begin
            // stage0 只有在完成两次 SRAM 读后才置有效
            stage0_valid <= 1'b0;
            stage0_last  <= 1'b0;
            stage0_pos   <= 4'd0;
            stage0_group <= 3'd0;
            stage0_fire  <= 1'b0;
            stage0_data_bus <= 64'd0;

            case (rd_state)
                RD_IDLE: begin
                    if (lut_read0_cmd) begin
                        // 记录第 2 次读地址与 metadata，并在同拍发起第 1 次读（低 8 位地址）
                        //第一次读地址直接来自输入总线低 8 位，并且在 RD_IDLE 当拍就发起读命令；只有第二次读地址需要“跨拍保存”
                        req_addr1 <= in_data_bus[15:8];
                        req_last  <= in_last;
                        req_pos   <= in_pos;
                        req_group <= in_group;
                        req_fire  <= in_fire;
                        rd_state <= RD_WAIT0;
                    end
                end

                RD_WAIT0: begin
                    // 读取第 1 次结果（低 8 位地址），同拍发起第 2 次读（高 8 位地址）
                    first_lut_word <= lut_sram_rdata;//第一次读出的数据先暂存，等待第二次读出的数据组合成完整的输出
                    rd_state <= RD_WAIT1;
                end

                RD_WAIT1: begin
                    // 读取第 2 次结果并组包后送入 stage0
                    stage0_data_bus <= {lut_sram_rdata, first_lut_word};//将两次读出的数据组合成完整的 FP32 输出数据
                    stage0_valid <= 1'b1;
                    stage0_last  <= req_last;
                    stage0_pos   <= req_pos;
                    stage0_group <= req_group;
                    stage0_fire  <= req_fire;
                    rd_state <= RD_IDLE;
                end

                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

    assign out_valid    = stage0_valid;
    assign out_last     = stage0_last;
    assign out_pos      = stage0_pos;
    assign out_group    = stage0_group;
    assign out_fire     = stage0_fire;
    assign out_data_bus = stage0_data_bus;

endmodule
