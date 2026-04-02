`timescale 1ns / 1ps
/*
 * 模块名称: pwconv_input_buffer
 * 作者: SonicBolt 团队
 * 日期: 2026-04-03
 * 版本: v1.1
 *
 * 功能概述:
 *   逐点卷积输入侧的双缓冲 tile 缓存。
 *
 * module接口：
 *   - 输入为上游 DW 流输出的 token ，通过 in_data 输入，包含 pos/group 元数据
 *
 * 设计约定:
 *   - 上游输入顺序固定为 pos-major, group-minor，即pos=0..8，每个 pos 下 group=0..7
 *   - 偶数 pos 写入 even buffer，奇数 pos 写入 odd buffer
 *   - 每个 pos 对应一个完整 32ch x 2 x 2 INT8 tile，共 1024bit
 *   - 每个输入 token 对应其中一个 4ch x 2 x 2 INT8 group，共 128bit
 *
 * 版本定位:
 *   - v1.1 修复 bug, 更改 buf 清零的条件：只在第一个 token 到来的上一个周期（启动信号）时清理，防止buf反复清零
 */
module pwconv_input_buffer (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          capture_en,
    input  wire          in_fire,         // 启动信号
    input  wire [3:0]    in_pos,
    input  wire [2:0]    in_group,        //8组，每组4ch
    input  wire [127:0]  in_data,
    output wire [1023:0] even_pos_data,
    output wire [1023:0] odd_pos_data
);
    //buffer过渡
    reg [1023:0] even_buf;
    reg [1023:0] odd_buf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            even_buf <= 1024'd0;
            odd_buf  <= 1024'd0;
        end else begin
            // 启动信号到来，则清空缓存区，准备等待第一个tile输入
            if (in_fire && (in_pos == 4'd0) && (in_group == 3'd0)) begin
                even_buf <= 1024'd0;
                odd_buf  <= 1024'd0;
            end

            // capture_en 本质是 in_stream_valid，每一个tile有效时，要下一个时钟周期才能被buf读取
            if (capture_en) begin
                if (in_pos[0]) begin
                    odd_buf[in_group*128 +: 128] <= in_data;
                end else begin
                    even_buf[in_group*128 +: 128] <= in_data;
                end
            end
        end
    end

    assign even_pos_data = even_buf;
    assign odd_pos_data  = odd_buf;

endmodule
