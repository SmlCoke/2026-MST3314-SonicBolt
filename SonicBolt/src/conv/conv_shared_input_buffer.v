`timescale 1ns / 1ps
/*
 * 模块名称: conv_shared_input_buffer
 * 作者: SonicBolt 团队
 * 日期: 2026-03-30
 * 版本: v2.1
 *
 * 功能概述:
 *   Conv1 输入前端，使用单口 SRAM 保存整帧输入图，并用 14 行工作集缓存当前 pos。
 *
 * 版本定位:
 *   - 相比 v2.0 取消了双 Bank 和 双 Cache 缓存设计
 *   - 只保留了一个 Bank 和一个 Cache，这是建立在目前 1 token/cycle 的高新能前提上的。
 *
 * 设计要点:
 *   - 整帧 30x10x8bit 输入图保存到一组 30x80 SRAM，而不是 整帧 FF 缓存
 *   - 工作集只保存当前 pos 需要的 14 行
 *   - 同一 pos 的 8 个 group 复用同一份工作集
 *   - 在消费当前 pos 的同时，预取下一 pos 需要新增的 2 行
 *
 * 输入图与窗口位宽:
 *   - 一整行输入 = 10 个像素 x 8bit = 80bit
 *   - 一整帧输入 = 30 行 x 10 列 x 8bit = 2400bit
 *   - 一个 pos 窗口 = 14 行 x 10 列 x 8bit = 1120bit
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
    input  wire [4:0]    img_wr_addr,      // 写入行地址，输入图共 30 行，因此 5bit 足够表示 0~29
    input  wire [79:0]   img_wr_row_word,   // 一行 10 个像素，10 x 8bit = 80bit

    // ---------- 消费启动接口 ----------
    input  wire          start_consume,    // 启动消费当前 SRAM 中的一张新图，并清空上一轮工作集状态

    // ---------- pos 窗口请求 / 返回接口 ----------
    input  wire          pos_req_valid,    // 下游请求一个新的 pos 窗口
    input  wire [3:0]    pos_req_pos,      // 请求的 pos 编号，范围 0~8，因此使用 4bit
    output reg           pos_window_valid, // 输出窗口有效，当前实现用于标记 pos=0 工作集已装载完成
    input  wire          consume_tick,     // 当前 token 被真正消费，用于驱动后台预取下一 pos 所需新行
    output reg  [14*80-1:0] pos_window_data
);

    localparam integer ROW_WORD_W   = 80;
    localparam integer WORKSET_ROWS = 14;

    // shadow_cache 只镜像输入图前 14 行。
    // 1. start 之后请求 pos=0 时，不需要先从 SRAM 连续读 14 拍才能开算。
    reg  [79:0] shadow_cache [0:13];

    // 当前工作集从 pos=p 切到 pos=p+1 时，只需要补入两行新数据：
    //   行号 = 2*p+14 和 2*p+15
    reg  [79:0] prefetched_rows [0:1];

    reg  [3:0]  current_pos;        // 当前 pos_window_data 这份 14 行工作集对应哪个 pos     
    reg         workset_loaded;     // 当前工作集是否已经有效装载        
    reg         prefetched_valid;   // 两条预取行是否都已准备好          
    reg  [1:0]  prefetch_step;      // 两条预取请求的微状态       
    reg         rd_wait_pending;    // SRAM 已经发出读请求，正在等待同步读返回         
    reg         rd_capture_pending; // 当前拍应该把 frame_rdata 捕获到 prefetched_rows           
    reg         rd_capture_slot;    // 本次捕获写到 prefetched_rows[0] 还是 [1]         
    reg         frame_rd_en_reg;    // 发给单口 SRAM 的同步读使能
    reg  [4:0]  frame_rd_addr_reg;  // 发给单口 SRAM 的同步读地址

    wire [79:0] frame_rdata;        // 单口 SRAM 的同步读返回
    wire        frame_en;           // 单口 SRAM 总使能，写输入或发起预取时拉高
    wire [4:0]  frame_addr;         // 单口 SRAM 地址，写入和预取共用同一个地址口

    integer idx;

    assign frame_en        = img_wr_en || frame_rd_en_reg;
    assign frame_addr      = img_wr_en ? img_wr_addr : frame_rd_addr_reg;

    // 单口输入 SRAM。
    // 当前版本不再保留双 bank ping-pong，而是采用“先整帧写入，再启动计算”的使用方式。
    S018V3EBCDSP_X8Y4D80_PR u_frame_store (
        .CLK(clk),
        .CEN(~frame_en),
        .WEN(~img_wr_en),
        .A(frame_addr),
        .D(img_wr_row_word),
        .Q(frame_rdata)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位后不假定任何工作集有效，必须等 start_consume 和 pos=0 请求重新建立状态。
            pos_window_valid   <= 1'b0;
            current_pos        <= 4'd0;
            workset_loaded     <= 1'b0;
            prefetched_valid   <= 1'b0;
            prefetch_step      <= 2'd0;
            rd_wait_pending    <= 1'b0;
            rd_capture_pending <= 1'b0;
            rd_capture_slot    <= 1'b0;
            frame_rd_en_reg    <= 1'b0;
            frame_rd_addr_reg  <= 5'd0;
            for (idx = 0; idx < WORKSET_ROWS; idx = idx + 1) begin
                shadow_cache[idx] <= 80'd0;
                pos_window_data[idx*ROW_WORD_W +: ROW_WORD_W] <= 80'd0;
            end
            prefetched_rows[0] <= 80'd0;
            prefetched_rows[1] <= 80'd0;
        end else begin
            // 默认每拍把 SRAM 读使能拉低；
            // 只有进入预取发起分支时，才会把 active_rd_en_reg 拉高一个周期。
            frame_rd_en_reg <= 1'b0;

            // -----------------------------------------------------------------
            // 写入路径：
            // 外部总是按“整行”写 SRAM。
            // 另外，如果写入的是前 14 行，就顺便更新 shadow cache，
            // 让未来的 pos=0 能直接从寄存器快照中拿到首个工作集。
            // -----------------------------------------------------------------
            if (img_wr_en && (img_wr_addr < 5'd14)) begin
                shadow_cache[img_wr_addr] <= img_wr_row_word;
            end

            // -----------------------------------------------------------------
            // start_consume：切换 active bank，并清空当前图相关的工作状态
            // -----------------------------------------------------------------
            // 注意这里不会立刻去装 14 行工作集，而是等待 core 通过 pos_req_valid
            // 明确请求 pos=0。这样输入 buffer 仍然保持“被请求才提供数据”的接口语义。
            // -----------------------------------------------------------------
            if (start_consume) begin
                pos_window_valid   <= 1'b0;
                current_pos        <= 4'd0;
                workset_loaded     <= 1'b0;
                prefetched_valid   <= 1'b0;
                prefetch_step      <= 2'd0;
                rd_wait_pending    <= 1'b0;
                rd_capture_pending <= 1'b0;
                rd_capture_slot    <= 1'b0;
            end

            // -----------------------------------------------------------------
            // pos 请求处理
            // -----------------------------------------------------------------
            // 共有两种合法请求：
            // 1. 第一次请求 pos=0：从 shadow cache 装入完整 14 行工作集
            // 2. 请求 current_pos+1：把工作集上移 2 行，并接上两条预取行
            // 任何其它请求都视为调度异常，当前实现中仅忽略该请求，不更新工作集。
            // -----------------------------------------------------------------
            if (pos_req_valid) begin
                if (!workset_loaded && (pos_req_pos == 4'd0)) begin
                    // 首次建工作集：直接从对应 bank 的 shadow cache 中一次性装 14 行。
                    for (idx = 0; idx < WORKSET_ROWS; idx = idx + 1) begin
                        pos_window_data[idx*ROW_WORD_W +: ROW_WORD_W] <= shadow_cache[idx];
                    end
                    current_pos      <= 4'd0;
                    workset_loaded   <= 1'b1;
                    pos_window_valid <= 1'b1;
                    prefetched_valid <= 1'b0;
                    prefetch_step    <= 2'd0;
                end else if (workset_loaded &&
                             (pos_req_pos == (current_pos + 4'd1)) &&
                             prefetched_valid) begin
                    // 工作集滚动：
                    // 老的 [2:13] 移到新的 [0:11]
                    // 预取好的两条新行放到 [12:13]
                    for (idx = 0; idx < 12; idx = idx + 1) begin
                        pos_window_data[idx*80 +: 80] <= pos_window_data[(idx + 2)*80 +: 80];
                    end
                    pos_window_data[12*80 +: 80] <= prefetched_rows[0];
                    pos_window_data[13*80 +: 80] <= prefetched_rows[1];
                    current_pos      <= pos_req_pos;
                    prefetched_valid <= 1'b0;
                    prefetch_step    <= 2'd0;
                end
            end

            // -----------------------------------------------------------------
            // 预取发起逻辑
            // -----------------------------------------------------------------
            // consume_tick 表示 MAC 这一拍真正消费了当前工作集。
            // 只要当前工作集已经有效，且还没到最后一个 pos，就在后台逐步发起两次单行读：
            //
            // current_pos = p 时，需要为 pos=p+1 预取
            //   row = 2*p+14  -> prefetched_rows[0]
            //   row = 2*p+15  -> prefetched_rows[1]
            //
            // prefetch_step 的含义：
            //   0 : 还没发第一条
            //   1 : 第一条已发，准备发第二条
            //   2 : 第二条已发，等待 capture 完成
            //   3 : 两条都齐了，等待 pos 切换消费
            // -----------------------------------------------------------------
            if (consume_tick && workset_loaded && (current_pos < 4'd8)) begin
                case (prefetch_step)
                    2'd0: if (!rd_wait_pending && !rd_capture_pending) begin
                        frame_rd_en_reg   <= 1'b1;
                        frame_rd_addr_reg <= ({1'b0, current_pos} << 1) + 5'd14;
                        rd_wait_pending   <= 1'b1;
                        rd_capture_slot   <= 1'b0;
                        prefetch_step     <= 2'd1;
                    end
                    2'd1: if (!rd_wait_pending && !rd_capture_pending) begin
                        frame_rd_en_reg   <= 1'b1;
                        frame_rd_addr_reg <= ({1'b0, current_pos} << 1) + 5'd15;
                        rd_wait_pending   <= 1'b1;
                        rd_capture_slot   <= 1'b1;
                        prefetch_step     <= 2'd2;
                    end
                    default: ;
                endcase
            end

            // -----------------------------------------------------------------
            // 同步 SRAM 预取返回时序
            // -----------------------------------------------------------------
            // sram_sp 是同步读：
            // - 第 1 拍：拉高 active_rd_en_reg，送出地址
            // - 第 2 拍：rdata 更新，此时把返回值捕获到 prefetched_rows
            //
            // rd_wait_pending 表示“上一拍刚发出读请求，当前拍等返回”
            // rd_capture_pending 表示“当前拍要真正把 active_rdata 收进寄存器”
            // -----------------------------------------------------------------
            if (rd_wait_pending) begin
                rd_wait_pending    <= 1'b0;
                rd_capture_pending <= 1'b1;
            end else if (rd_capture_pending) begin
                prefetched_rows[rd_capture_slot] <= frame_rdata;
                rd_capture_pending <= 1'b0;
                // 约定 slot=0 放“下一窗口的倒数第二行新增行”
                //     slot=1 放“下一窗口的最后一行新增行”
                // 当 slot=1 也完成时，说明两行都已经预取完毕，可以允许 pos 切换。
                if (rd_capture_slot) begin
                    prefetched_valid <= 1'b1;
                    prefetch_step    <= 2'd3;
                end
            end
        end
    end

endmodule
