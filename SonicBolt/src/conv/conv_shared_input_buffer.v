`timescale 1ns / 1ps
/*
 * 模块名称: conv_shared_input_buffer
 * 作者: SonicBolt 团队
 * 日期: 2026-04-08
 * 版本: v2.3
 *
 * 功能概述:
 *   Conv1 输入前端，使用单口 SRAM 保存整帧输入图，并用 14 行工作集缓存当前 pos。
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
 *
 * 版本定位:
 *   - 相比 v2.0 取消了双 Bank 和 双 Cache 缓存设计
 *   - 只保留了一个 Bank 和一个 Cache，这是建立在目前 1 token/cycle 的高新能前提上的。
 *   - v2.2 引入了 Memory Compiler 生成的 SRAM 模块，重构了读写控制逻辑。
 *   - v2.3 增加了输入双帧 Ping-Pong 缓存机制
 */
module conv_shared_input_buffer (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位

    // ---------- 输入图写入接口 ----------
    input  wire          img_wr_en,        // 输入图逐行写使能，高电平表示当前拍写入一行
    input  wire [4:0]    img_wr_addr,      // 写入行地址，输入图共 30 行，因此 5bit 足够表示 0~29
    input  wire [79:0]   img_wr_row_word,  // 一行 10 个像素，10 x 8bit = 80bit
    input  wire          img_wr_commit,    // 表示当前写入 Bank 的30行已经写完，可以被消费
    output wire          img_wr_ready,     // 输出给外部，表示当前存在可写 bank    

    // ---------- 消费启动接口 ----------
    input  wire          start_consume,    // 启动消费当前 SRAM 中的一张新图，并清空上一轮工作集状态
    input  wire          consume_bank_sel, // 本次 start_consume 要切换到哪个 bank
    output reg  [1:0]    ready_bank_mask,  // 输出给 conv_subsystem, 指示哪几个 bank 已经 ready，可以开始启动消费

    // ---------- pos 窗口请求 / 返回接口 ----------
    input  wire          pos_req_valid,    // 下游请求一个新的 pos 窗口
    input  wire [3:0]    pos_req_pos,      // 请求的 pos 编号，范围 0~8，因此使用 4bit
    output reg           pos_window_valid, // 输出窗口有效，当前实现用于标记 pos=0 工作集已装载完成
    input  wire          consume_tick,     // 当前 token 被真正消费，用于驱动后台预取下一 pos 所需新行
    output reg  [14*80-1:0] pos_window_data
);

    localparam integer ROW_WORD_W   = 80;
    localparam integer WORKSET_ROWS = 14;

    reg         write_bank;        // 控制当前写入的 bank，0 = ping, 1 = pong
    reg         active_bank;       // 当前处于消费状态的工作 bank, 是哪个完全取决于当前顶层系统的选择
    reg         write_inflight;    // 当前是否处于一张图的连续写入会话中

    // shadow_cache 只镜像输入图前 14 行。
    // 1. start 之后请求 pos=0 时，不需要先从 SRAM 连续读 14 拍才能开算。
    reg  [79:0] shadow_cache_ping [0:13];
    reg  [79:0] shadow_cache_pong [0:13];

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

    wire [79:0] frame_rdata_ping;   // Ping SRAM 的同步读返回
    wire [79:0] frame_rdata_pong;   // Pong SRAM 的同步读返回
    wire [79:0] frame_rdata;        // 当前处于消费状态的 SRAM 的读总线

    wire        frame_wr_en_ping;   // Ping SRAM 写使能
    wire        frame_wr_en_pong;   // Pong SRAM 写使能

    wire        frame_rd_en_ping;   // Ping SRAM 读使能
    wire        frame_rd_en_pong;   // Pong SRAM 读使能

    wire        frame_en_ping;      // Ping SRAM 总使能，写输入或发起预取时拉高
    wire        frame_en_pong;      // Pong SRAM 总使能，写输入或发起预取时拉高

    wire [4:0]  frame_addr_ping;    // Ping SRAM 地址
    wire [4:0]  frame_addr_pong;    // Pong SRAM 地址

    wire        selected_write_bank;// 本拍实际写入选择的 bank
    wire        start_write_session;// 一张新图写入会话的起点
    wire        write_data_fire;    // 这一拍的输入写数据是否真的应该被 buffer 接收并写入 SRAM

    integer idx;

    // 允许写入的两个情况：
    // (1) 当前已经处于一张图的连续写入会话中
    // (2) 当前不在写入流中，且 non-active bank 还没有装好一张“待消费”的完整输入图
    assign img_wr_ready         = write_inflight || !ready_bank_mask[~active_bank];
    // 写入 bank 选择逻辑：
    // (1) 如果已经在写一张图，则后续各行必须继续写同一个 write_bank
    // (2) 如果当前没在写，则新图的第一行默认落到 non-active bank
    assign selected_write_bank  = write_inflight ? write_bank : ~active_bank;
    // 新图写入起点：当前拍是 addr=0，且当前不在写入流中，并且输入端允许开启一张新图的写入
    assign start_write_session  = img_wr_en && !write_inflight && (img_wr_addr == 5'd0) && img_wr_ready;
    

    // 这一拍的输入写数据是否真的应该被 buffer 接收并写入 SRAM
    // 两种情况: 
    // (1) 当前拍要么已经处于一张图的连续写入过程中
    // (2) 要么这一拍就是一张新图写入的起点
    // 该信号是写使能信号的本质，可以避免外部乱写
    assign write_data_fire      = img_wr_en && (write_inflight || start_write_session);

    // SRAM 写使能信号: 应该写并且选中当前 bank
    assign frame_wr_en_ping = write_data_fire && ~selected_write_bank;

    // SRAM 写使能信号: 应该写并且选中当前 bank
    assign frame_wr_en_pong = write_data_fire &&  selected_write_bank;

    // SRAM 读使能信号: 应该读并且当前 Bank 就是 active bank
    assign frame_rd_en_ping = frame_rd_en_reg && ~active_bank;
    assign frame_rd_en_pong = frame_rd_en_reg &&  active_bank;

    // Ping-Pong SRAM 的使能信号：(1) 写, 且写入本 bank (2) 读, 且读取当前 active bank
    assign frame_en_ping    = frame_wr_en_ping || frame_rd_en_ping;
    assign frame_en_pong    = frame_wr_en_pong || frame_rd_en_pong;

    // SRAM 地址信号: 写地址来自外部输入，读地址来自内部状态机
    assign frame_addr_ping  = frame_wr_en_ping ? img_wr_addr : frame_rd_addr_reg;
    assign frame_addr_pong  = frame_wr_en_pong ? img_wr_addr : frame_rd_addr_reg;

    // 根据当前活动的 Bank 筛选读出总线
    assign frame_rdata     = (active_bank == 1'b0) ? frame_rdata_ping : frame_rdata_pong;

    // 单口输入 SRAM。
    // Ping-Pong 缓存机制
    S018V3EBCDSP_X8Y4D80_PR u_frame_store_ping (
        .CLK(clk),
        .CEN(~frame_en_ping),
        .WEN(~frame_wr_en_ping),
        .A(frame_addr_ping),
        .D(img_wr_row_word),
        .Q(frame_rdata_ping)
    );

    S018V3EBCDSP_X8Y4D80_PR u_frame_store_pong (
        .CLK(clk),
        .CEN(~frame_en_pong),
        .WEN(~frame_wr_en_pong),
        .A(frame_addr_pong),
        .D(img_wr_row_word),
        .Q(frame_rdata_pong)
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
            ready_bank_mask    <= 2'b00;
            for (idx = 0; idx < WORKSET_ROWS; idx = idx + 1) begin
                shadow_cache_ping[idx] <= 80'd0;
                shadow_cache_pong[idx] <= 80'd0;
                pos_window_data[idx*ROW_WORD_W +: ROW_WORD_W] <= 80'd0;
            end
            prefetched_rows[0] <= 80'd0;
            prefetched_rows[1] <= 80'd0;

            // 复位后将 active_bank 置为 pong，
            // 这样第一张新图开始写入时会默认落到 ping bank
            write_bank         <= 1'b0;
            active_bank        <= 1'b1;
            write_inflight     <= 1'b0;
        end else begin
            // 默认每拍把 SRAM 读使能拉低；
            // 只有进入预取发起分支时，才会把 active_rd_en_reg 拉高一个周期。
            frame_rd_en_reg <= 1'b0;

            // -----------------------------------------------------------------
            // Ping-Pong 状态更新逻辑
            // (1) 进入新图写入会话时，write_inflight 置高，锁定后续写入必须继续写同一 bank
            // (2)一张图写完并且写入流信号有效(防止外部乱发信号)时, 把当前 write_bank 标记为“待消费 ready”，同时更新 write_bank 并且关闭写入流信号
            // -----------------------------------------------------------------
            if (start_write_session && !write_inflight) begin
                write_inflight <= 1'b1;
            end

            if (img_wr_commit && write_inflight) begin
                ready_bank_mask[write_bank] <= 1'b1;
                write_inflight <= 1'b0;
                write_bank <= ~write_bank;
            end

            // -----------------------------------------------------------------
            // 写入路径：
            // 外部总是按“整行”写 SRAM。
            // 另外，如果写入的是前 14 行，就顺便更新 shadow cache，
            // 让未来的 pos=0 能直接从寄存器快照中拿到首个工作集。
            // -----------------------------------------------------------------
            if (write_data_fire && (img_wr_addr < 5'd14)) begin
                if (selected_write_bank == 1'b0) begin
                    shadow_cache_ping[img_wr_addr] <= img_wr_row_word;
                end else begin 
                    shadow_cache_pong[img_wr_addr] <= img_wr_row_word;
                end
            end

            // -----------------------------------------------------------------
            // start_consume：切换 active bank，并清空当前图相关的工作状态
            // -----------------------------------------------------------------
            // 注意这里不会立刻去装 14 行工作集，而是等待 core 通过 pos_req_valid
            // 明确请求 pos=0。这样输入 buffer 仍然保持“被请求才提供数据”的接口语义。
            // -----------------------------------------------------------------
            if (start_consume) begin
                // 当前 active bank 完全取决于顶层系统的选择
                active_bank        <= consume_bank_sel;
                // 当前 bank 已被选中进入消费流，不再属于“待启动消费”的 ready bank
                ready_bank_mask[consume_bank_sel] <= 1'b0;
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
                    // 根据状态 active_bank 选择哪个bank
                    for (idx = 0; idx < WORKSET_ROWS; idx = idx + 1) begin
                        pos_window_data[idx*ROW_WORD_W +: ROW_WORD_W] <= 
                        (active_bank == 1'b0) ? shadow_cache_ping[idx] :  shadow_cache_pong[idx];
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
