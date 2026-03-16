`timescale 1ns / 1ps
/*
 * 模块名称: conv_sram_sp
 * 功能概述: 通用同步单端口 SRAM 行为模型，供当前 Conv 子系统的输入缓存、
 *          参数缓存和调试输出缓存统一复用。
 * 作者: SonicBolt Team
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 当前角色:
 *   - 主通路公共基础模块
 *   - 不带任何 CNN 语义，只负责提供可参数化的单端口存储行为
 *
 * 行为约定:
 *   - 同步读：rdata 在时钟上升沿更新
 *   - 同步写：wr_en=1 时在时钟上升沿写入
 *   - read-first：同拍同址读写时，rdata 返回写入前旧值
 *
 * 参数说明:
 *   - DATA_W : 单个 word 的位宽
 *   - DEPTH  : 存储深度，即一共有多少个 word
 *   - ADDR_W : 地址位宽，通常满足 2^ADDR_W >= DEPTH
 */
module conv_sram_sp #(
    parameter integer DATA_W = 32,
    parameter integer DEPTH  = 16,
    parameter integer ADDR_W = 4
) (
    input  wire                  clk,    // 时钟信号，所有读写都在上升沿发生
    input  wire                  rst_n,  // 低有效复位，仅复位读口寄存器，不清空整个存储阵列
    input  wire                  en,     // 存储访问使能，高电平表示本拍发生一次读或写访问
    input  wire                  wr_en,  // 写使能，高电平表示本拍执行写，低电平表示只读
    input  wire [ADDR_W-1:0]     addr,   // 访问地址，位宽由 ADDR_W 参数决定
    input  wire [DATA_W-1:0]     wdata,  // 写入数据，位宽等于一个 SRAM word 的宽度 DATA_W
    output reg  [DATA_W-1:0]     rdata   // 读出数据，位宽同样为 DATA_W
);

    reg [DATA_W-1:0] mem [0:DEPTH-1];  // 存储阵列，深度 DEPTH、单 word 位宽 DATA_W
    integer idx;
    reg [DATA_W-1:0] old_word;         // 暂存旧值，用于实现 read-first 语义

    initial begin
        for (idx = 0; idx < DEPTH; idx = idx + 1) begin
            mem[idx] = {DATA_W{1'b0}};
        end
        rdata = {DATA_W{1'b0}};
    end

    // 同步单端口读写逻辑：
    // 1. 若 en=1，先读取旧值返回到 rdata
    // 2. 若 wr_en=1，再把 wdata 写入当前 addr
    // 因此同拍同址读写时，rdata 看到的是旧值
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdata <= {DATA_W{1'b0}};
        end else if (en) begin
            // 借助中间变量 old_word 可以实现一个时钟上升沿读出一个值（该值是上一个时钟上升沿传入的地址对应的数据）
            // !!!!! 注意，这里是阻塞赋值！想想这意味着什么。
            old_word = mem[addr];
            rdata <= old_word;
            if (wr_en) begin
                mem[addr] <= wdata;
            end
        end
    end

endmodule
