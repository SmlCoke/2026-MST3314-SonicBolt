`timescale 1ns / 1ps
/*
 * 模块名称: post_process_sigmoid
 * 作者: SonicBolt 团队
 * 日期: 2026-04-05
 * 版本: v1.0
 *
 * 功能概述:
 *   - 对 2 路 INT8 FC 输出执行 Sigmoid LUT 查表
 *   - LUT 深度 256，每项 32bit（IEEE754 FP32 格式）
 *   - 输出 2 路 FP32，64bit 总线
 *
 * 设计说明:
 *   - x=-128 对应 8'h80，x=0 对应 8'h00，x=127 对应 8'h7f
 *   - LUT 通过在线写端口加载到 256x32 单端口 SRAM
 *   - 单端口 SRAM 读口一次只读一个地址：先读低 8 位地址，再读高 8 位地址
 */
module post_process_sigmoid (
    input  wire        clk,
    input  wire        rst_n,

    // ---------- 输入 valid ----------
    input  wire        in_valid,

    // ---------- 输入数据 ----------
    input  wire [15:0] in_data_bus,

    // ---------- LUT 写接口 ----------
    input  wire        lut_wr_en,
    input  wire [7:0]  lut_wr_addr,
    input  wire [31:0] lut_wr_data,

    // ---------- 输出 valid ----------
    output wire        out_valid,

    // ---------- 输出数据 ----------
    output wire [63:0] out_data_bus
);

    localparam [1:0] RD_IDLE  = 2'd0; // 等待读地址
    localparam [1:0] RD_WAIT0 = 2'd1; // 已读第 1 个地址，等待第 2 个地址
    localparam [1:0] RD_WAIT1 = 2'd2; // 已读第 2 个地址，等待数据有效

    
    reg [1:0]  rd_state;         // 状态寄存器
    reg [7:0]  req_addr1;        // 第二个 LUT 地址寄存器
    reg [31:0] first_lut_word;   // 第一个 LUT 读出的数据寄存器

    // Sigmoid LUT 读写控制信号
    wire        lut_sram_en;
    wire        lut_sram_wr_en;
    wire [7:0]  lut_sram_addr;
    wire [31:0] lut_sram_wdata;
    wire [31:0] lut_sram_rdata;

    wire lut_write_cmd; // 写 LUT 命令
    wire lut_read0_cmd; // 读 LUT 的第 1 个地址
    wire lut_read1_cmd; // 读 LUT 的第 2 个地址

    reg [63:0] stage0_data_bus; // 将两次 LUT 读出的数据拼成完整的 FP32 输出
    reg        stage0_valid;

    // 仅在 IDLE 状态且 lut_wr_en 有效时发出写命令；
    assign lut_write_cmd = (rd_state == RD_IDLE) && lut_wr_en;
    // 仅在 IDLE 状态且 in_valid 有效时发出第 1 个读命令；
    assign lut_read0_cmd = (rd_state == RD_IDLE) && in_valid && !lut_wr_en;
    // 仅在 WAIT0 状态时发出第 2 个读命令；
    assign lut_read1_cmd = (rd_state == RD_WAIT0);

    assign lut_sram_en    = lut_write_cmd || lut_read0_cmd || lut_read1_cmd;
    assign lut_sram_wr_en = lut_write_cmd;

    // LUT SRAM 地址构造：写命令时用 lut_wr_addr，读命令时先读低地址再读高地址。
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

    // LUT 单端口 SRAM：先读 addr0，再读 addr1，最后拼包成两路 FP32 输出。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state        <= RD_IDLE;
            req_addr1       <= 8'd0;
            first_lut_word  <= 32'd0;
            stage0_data_bus <= 64'd0;
            stage0_valid    <= 1'b0;
        end else begin
            stage0_valid    <= 1'b0;
            stage0_data_bus <= 64'd0;

            case (rd_state)
                RD_IDLE: begin
                    // 如果 in valid 
                    if (lut_read0_cmd) begin
                        // in valid 到来，读信号已经发出，下一个周期拿到数据
                        // Sigmoid 阶段不再保存多余 metadata，只跨拍保存第二个 LUT 地址。
                        req_addr1 <= in_data_bus[15:8];
                        rd_state  <= RD_WAIT0;
                    end
                end

                RD_WAIT0: begin
                    // 拿到第一个 LUT 数据，继续读第二个 LUT 数据
                    first_lut_word <= lut_sram_rdata;
                    rd_state       <= RD_WAIT1;
                end

                RD_WAIT1: begin
                    // 拿到第二个 LUT 数据，拼包输出，元数据 valid 置高
                    stage0_data_bus <= {lut_sram_rdata, first_lut_word};
                    stage0_valid    <= 1'b1;
                    rd_state        <= RD_IDLE;
                end

                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

    assign out_valid    = stage0_valid;
    assign out_data_bus = stage0_data_bus;

endmodule
