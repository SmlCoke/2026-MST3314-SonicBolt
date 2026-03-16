`timescale 1ns / 1ps
/*
 * 模块名称: conv_shared_input_buffer
 * 作者: SonicBolt 团队
 * 日期: 2026-03-15
 * 版本: v1.0
 *
 * 功能概述:
 *   这是当前 Conv 子系统的输入前端。
 *   它负责把外部按“整帧逐行写入”的输入图，转换成主通路按 `pos` 请求的 14x10 输入窗口。
 *
 * 输入图与窗口位宽:
 *   - 一整行输入 = 10 个像素 x 8bit = 80bit
 *   - 一整帧输入 = 30 行 x 10 列 x 8bit = 2400bit
 *   - 一个 pos 窗口 = 14 行 x 10 列 x 8bit = 1120bit
 *
 * 工作方式分三步:
 *   1. 外部通过 img_wr_* 接口，逐行把一张输入图写入 frame_cache0 或 frame_cache1
 *   2. start_consume 拉高时，用 start_buf_sel 指定当前哪一份 cache 成为 active buffer
 *   3. 当下游发来 pos_req_valid + pos_req_pos 时，本模块下一拍输出该 pos 对应的 14x10 窗口
 *
 * pos 映射关系:
 *   - pos = 0  -> 输入行 0  ~ 13
 *   - pos = 1  -> 输入行 2  ~ 15
 *   - ...
 *   - pos = 8  -> 输入行 16 ~ 29
 *   - 相邻 pos 之间只前进 2 行
 */
module conv_shared_input_buffer (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位

    // ---------- 输入图写入接口 ----------
    input  wire          img_wr_en,        // 输入图逐行写使能，高电平表示当前拍写入一行
    input  wire          img_wr_buf_sel,   // 写入哪一份双缓冲：0 写 frame_cache0，1 写 frame_cache1
    input  wire [4:0]    img_wr_addr,      // 写入行地址，输入图共 30 行，因此 5bit 足够表示 0~29
    input  wire [39:0]   img_wr_data_lo,   // 一行前 5 个像素，5 x 8bit = 40bit
    input  wire [39:0]   img_wr_data_hi,   // 一行后 5 个像素，5 x 8bit = 40bit

    // ---------- 当前活动输入图选择 ----------
    input  wire          start_consume,    // 启动消费一张新图，同时更新 active buffer 选择
    input  wire          start_buf_sel,    // 这次计算要消费哪一份输入图：0 选 frame_cache0，1 选 frame_cache1
    output reg           active_buf_sel,   // 当前正在被主通路消费的输入图编号

    // ---------- pos 窗口请求 / 返回接口 ----------
    input  wire          pos_req_valid,    // 下游请求一个新的 pos 窗口
    input  wire [3:0]    pos_req_pos,      // 请求的 pos 编号，范围 0~8，因此使用 4bit
    output reg           pos_window_valid, // 输出窗口有效，当前实现为“请求后一拍返回”
    output reg  [14*10*8-1:0] pos_window_data   // 返回的 14x10 窗口，14 x 10 x 8bit = 1120bit
);

    // 双缓冲整帧 cache。
    // 每个元素是一整行 80bit，等价于 10 个 INT8 像素。
    reg  [10*8-1:0] frame_cache0 [0:30-1];
    reg  [10*8-1:0] frame_cache1 [0:30-1];

    // 把两份按“行”组织的 cache 展平成整帧总线，便于窗口发生器按位切片。
    wire [30*10*8-1:0] frame_bus0;       // frame_cache0 展平后得到的整帧 2400bit 总线
    wire [30*10*8-1:0] frame_bus1;       // frame_cache1 展平后得到的整帧 2400bit 总线
    wire [30*10*8-1:0] active_frame_bus; // 当前活动输入图对应的整帧总线

    // 组合逻辑实时切出来的窗口结果。
    // 注意它不是最终输出寄存器；最终输出要在 pos_req_valid 到来后一拍寄存到 pos_window_data。
    wire [14*10*8-1:0] pos_window_now;

    integer idx;

    // 根据 active_buf_sel 选择当前哪一帧参与主通路计算。
    assign active_frame_bus = active_buf_sel ? frame_bus1 : frame_bus0;

    // 初始化双缓冲 cache 和输出寄存器。
    initial begin
        for (idx = 0; idx < 30; idx = idx + 1) begin
            frame_cache0[idx] = 80'd0;
            frame_cache1[idx] = 80'd0;
        end
        active_buf_sel   = 1'b0;
        pos_window_valid = 1'b0;
        pos_window_data  = 1120'd0;
    end

    // 时序行为分成三类：
    // 1. start_consume=1 时，切换当前活动输入图
    // 2. img_wr_en=1 时，向选中的双缓冲 cache 写入一整行
    // 3. pos_req_valid=1 时，在下一拍锁存组合窗口结果并拉高 pos_window_valid
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < 30; idx = idx + 1) begin
                frame_cache0[idx] = 80'd0;
                frame_cache1[idx] = 80'd0;
            end
            active_buf_sel   <= 1'b0;
            pos_window_valid <= 1'b0;
            pos_window_data  <= 1120'd0;
        end else begin
            // 更新当前被消费的输入图。
            // 这使得系统可以在计算当前图的同时，把下一张图写到另一份 cache 里。
            if (start_consume) begin
                active_buf_sel <= start_buf_sel;
            end

            // 外部逐行写入输入图。
            // 每一行由两个 40bit 半行拼成一个完整 80bit 行缓存。
            if (img_wr_en) begin
                if (img_wr_buf_sel) begin
                    frame_cache1[img_wr_addr] <= {img_wr_data_hi, img_wr_data_lo};
                end else begin
                    frame_cache0[img_wr_addr] <= {img_wr_data_hi, img_wr_data_lo};
                end
            end

            // 窗口接口采用“请求后一拍返回”的简单时序。
            // 当前拍看到 pos_req_valid，下一拍输出 pos_window_valid=1 和对应窗口。
            pos_window_valid <= pos_req_valid;
            if (pos_req_valid) begin
                pos_window_data <= pos_window_now;
            end
        end
    end

    // 把按行组织的 cache 展平成整帧总线。
    // 行编号越大，映射到 frame_bus 中的高位段越后；每行固定占 80bit。
    generate
        genvar g_row;
        for (g_row = 0; g_row < 30; g_row = g_row + 1) begin : g_pack_frame_bus
            assign frame_bus0[g_row*80 +: 80] = frame_cache0[g_row];
            assign frame_bus1[g_row*80 +: 80] = frame_cache1[g_row];
        end
    endgenerate

    // 组合窗口发生器：
    // 从当前 active_frame_bus 中，根据 pos_req_pos 组合切出对应的 14x10 输入窗口。
    conv_pos_window_gen u_conv_pos_window_gen (
        .frame_data(active_frame_bus), // in: 完整输入图总线
        .pos_idx(pos_req_pos),         // in: 请求的 pos 编号经过内部封装的组合逻辑得到 window_data
        .window_data(pos_window_now)   // out: 切出的 14x10 输入窗口，供下一拍寄存到 pos_window_data
    );

endmodule
