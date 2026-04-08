`timescale 1ns / 1ps
/*
 * 模块名称: conv_shared_input_buffer
 * 作者: SonicBolt 团队
 * 日期: 2026-04-08
 * 版本: v2.4
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
 *   - v2.4 将杂糅状态更新逻辑重塑为三段式有限状态机
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
    reg         frame_rd_en_reg;    // 发给单口 SRAM 的同步读使能
    reg  [4:0]  frame_rd_addr_reg;  // 发给单口 SRAM 的同步读地址

    // 预取控制状态机（仅负责两条新增行的发起与捕获时序）。
    localparam [2:0] PREFETCH_IDLE      = 3'd0;   // 等待发起预取请求
    localparam [2:0] PREFETCH_WAIT_R0   = 3'd1;   // 已发起第一条预取请求，等待同步读返回窗口
    localparam [2:0] PREFETCH_CAP_R0    = 3'd2;   // 捕获第一条预取返回数据
    localparam [2:0] PREFETCH_WAIT_REQ1 = 3'd3;   // 第一条预取已完成，等待下一个 consume_tick 发第二条预取请求
    localparam [2:0] PREFETCH_WAIT_R1   = 3'd4;   // 已发起第二条预取请求，等待同步读返回窗口
    localparam [2:0] PREFETCH_CAP_R1    = 3'd5;   // 捕获第二条预取返回数据
    localparam [2:0] PREFETCH_READY     = 3'd6;   // 预取完成，可以开始消费

    reg [2:0] current_state;
    reg [2:0] next_state;

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

    wire        load_pos0_req;      // 首次工作集请求（pos=0）
    wire        roll_pos_req;       // 工作集滚动请求（current_pos+1 且预取已完成）
    wire        issue_prefetch_req; // 当前拍允许发起预取请求

    integer idx_shadow;
    integer idx_window;

    // 允许写入的两个情况：
    // （首先要注意一个大前提：允许我们写的，只可能是 non-active bank，而且不是说 non-active bank 任何时候都可以写）
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

    assign load_pos0_req      = pos_req_valid && !workset_loaded && (pos_req_pos == 4'd0);
    assign roll_pos_req       = pos_req_valid && workset_loaded &&
                                (pos_req_pos == (current_pos + 4'd1)) && prefetched_valid;
    assign issue_prefetch_req = consume_tick && workset_loaded && (current_pos < 4'd8);

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

    // 三段式状态机第一段：状态更新逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= PREFETCH_IDLE;
        end else if (start_consume) begin
            current_state <= PREFETCH_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // 三段式状态机第二段：下一个状态计算逻辑
    always @(*) begin
        // 这一行必须存在，否则某些分支中当前没有给next_state赋值会引发错误
        next_state = current_state;
        case (current_state)
            PREFETCH_IDLE: begin
                // 只有当前 pos 已经装载完成，并且 MAC 发出 consume_tick 表示消费了当前 pos，才允许发起预取请求
                if (issue_prefetch_req) begin
                    next_state = PREFETCH_WAIT_R0;
                end
            end
            PREFETCH_WAIT_R0: begin
                next_state = PREFETCH_CAP_R0;
            end
            PREFETCH_CAP_R0: begin
                next_state = PREFETCH_WAIT_REQ1;
            end
            // 第一条预取完成后，必须等到下一个 consume_tick 来临时才能发起第二条预取请求。
            PREFETCH_WAIT_REQ1: begin
                if (issue_prefetch_req) begin
                    next_state = PREFETCH_WAIT_R1;
                end
            end
            PREFETCH_WAIT_R1: begin
                next_state = PREFETCH_CAP_R1;
            end
            PREFETCH_CAP_R1: begin
                next_state = PREFETCH_READY;
            end
            PREFETCH_READY: begin
                // 预取完成后，继续待在 PREFETCH_READY 状态，直到下游请求 pos 滚动到 current_pos+1，此时工作集需要滚动更新
                if (roll_pos_req) begin
                    next_state = PREFETCH_IDLE;
                end
            end
            default: begin
                next_state = PREFETCH_IDLE;
            end
        endcase
    end

    // -----------------------------------------------------------------
    // Ping-Pong 状态更新逻辑
    // (1) 进入新图写入会话时，write_inflight 置高，锁定后续写入必须继续写同一 bank
    // (2)一张图写完并且写入流信号有效(防止外部乱发信号)时, 把当前 write_bank 标记为“待消费 ready”，同时更新 write_bank 并且关闭写入流信号
    // -----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_bank_mask <= 2'b00;
            // 复位后将 active_bank 置为 pong，
            // 这样第一张新图开始写入时会默认落到 ping bank
            write_bank      <= 1'b0;
            active_bank     <= 1'b1;
            write_inflight  <= 1'b0;
        end else begin
            // (1) 进入新图写入会话时，write_inflight 置高，锁定后续写入必须继续写同一 bank
            if (start_write_session && !write_inflight) begin
                // 只有在 non-active bank 还没准备好被消费时才允许写，start_write_seesion 才能为高
                write_inflight <= 1'b1;
                write_bank     <= ~active_bank;
            // (2)一张图写完并且写入流信号有效(防止外部乱发信号)时, 把当前 write_bank 标记为“待消费 ready”，同时更新 write_bank 并且关闭写入流信号
            // 这里用 else if，否则 write_inflight 可能在同一拍被置高又被置低，导致状态混乱
            end else if (img_wr_commit && write_inflight) begin
                ready_bank_mask[write_bank] <= 1'b1;
                write_inflight <= 1'b0;
            end

            // -----------------------------------------------------------------
            // start_consume：切换 active bank，并清空当前图相关的工作状态
            // -----------------------------------------------------------------
            // 注意这里不会立刻去装 14 行工作集，而是等待 core 通过 pos_req_valid
            // 明确请求 pos=0。这样输入 buffer 仍然保持“被请求才提供数据”的接口语义。
            // 这里用的是 else if，因为 start_consume 信号绝不可能与 img_wr_commit 同时有效，这是因为 start_consume 是前一张图写完（img_wr_commit=1）后的一个瞬间置高的，下一个周期进入这个分支，后面那张图根本不可能写完！
            // -----------------------------------------------------------------
            else if (start_consume) begin
                // 当前 active bank 完全取决于顶层系统的选择
                active_bank <= consume_bank_sel;
                // 当前 bank 已被选中进入消费流，不再属于“待启动消费”的 ready bank
                ready_bank_mask[consume_bank_sel] <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------------------
    // 写入路径：
    // 外部总是按“整行”写 SRAM。
    // 另外，如果写入的是前 14 行，就顺便更新 shadow cache，
    // 让未来的 pos=0 能直接从寄存器快照中拿到首个工作集。
    // 该 reg 只会在初始十四行发挥作用，后续真正输送给 core 的数据来源于预取行以及工作集寄存器
    // ---------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx_shadow = 0; idx_shadow < WORKSET_ROWS; idx_shadow = idx_shadow + 1) begin
                shadow_cache_ping[idx_shadow] <= 80'd0;
                shadow_cache_pong[idx_shadow] <= 80'd0;
            end
            // write_data_fire 为写使能信号的本质
        end else if (write_data_fire && (img_wr_addr < 5'd14)) begin
            if (selected_write_bank == 1'b0) begin
                shadow_cache_ping[img_wr_addr] <= img_wr_row_word;
            end else begin
                shadow_cache_pong[img_wr_addr] <= img_wr_row_word;
            end
        end
    end

    // 工作集数据通路寄存器更新逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位后不假定任何工作集有效，必须等 start_consume 和 pos=0 请求重新建立状态。
            pos_window_valid <= 1'b0;
            current_pos      <= 4'd0;
            workset_loaded   <= 1'b0;
            for (idx_window = 0; idx_window < WORKSET_ROWS; idx_window = idx_window + 1) begin
                pos_window_data[idx_window*ROW_WORD_W +: ROW_WORD_W] <= 80'd0;
            end
        end else if (start_consume) begin
            pos_window_valid <= 1'b0;
            current_pos      <= 4'd0;
            workset_loaded   <= 1'b0;
        end else begin
            // -----------------------------------------------------------------
            // pos 请求处理
            // -----------------------------------------------------------------
            // 共有两种合法请求：
            // 1. 第一次请求 pos=0：从 shadow cache 装入完整 14 行工作集
            // 2. 请求 current_pos+1：把工作集上移 2 行，并接上两条预取行
            // 任何其它请求都视为调度异常，当前实现中仅忽略该请求，不更新工作集。
            // -----------------------------------------------------------------
            if (load_pos0_req) begin
                // 首次建工作集：直接从对应 bank 的 shadow cache 中一次性装 14 行。
                // 根据状态 active_bank 选择哪个bank
                for (idx_window = 0; idx_window < WORKSET_ROWS; idx_window = idx_window + 1) begin
                    pos_window_data[idx_window*ROW_WORD_W +: ROW_WORD_W] <=
                        (active_bank == 1'b0) ? shadow_cache_ping[idx_window] : shadow_cache_pong[idx_window];
                end
                current_pos      <= 4'd0;
                workset_loaded   <= 1'b1;
                pos_window_valid <= 1'b1;
            end else if (roll_pos_req) begin
                // 工作集滚动：
                // 老的 [2:13] 移到新的 [0:11]
                // 预取好的两条新行放到 [12:13]
                for (idx_window = 0; idx_window < 12; idx_window = idx_window + 1) begin
                    pos_window_data[idx_window*80 +: 80] <= pos_window_data[(idx_window + 2)*80 +: 80];
                end
                pos_window_data[12*80 +: 80] <= prefetched_rows[0];
                pos_window_data[13*80 +: 80] <= prefetched_rows[1];
                current_pos <= pos_req_pos;
            end
        end
    end

    // 三段式状态机第三段：状态输出 + 数据通路寄存器更新逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prefetched_valid  <= 1'b0;
            frame_rd_en_reg   <= 1'b0;
            frame_rd_addr_reg <= 5'd0;
            prefetched_rows[0] <= 80'd0;
            prefetched_rows[1] <= 80'd0;
        end else begin
            // 默认每拍把 SRAM 读使能拉低；
            // 只有进入预取发起分支时，才会把 active_rd_en_reg 拉高一个周期。
            frame_rd_en_reg <= 1'b0;

            if (start_consume) begin
                prefetched_valid  <= 1'b0;
                frame_rd_addr_reg <= 5'd0;
            end else begin
                if (load_pos0_req || roll_pos_req) begin
                    prefetched_valid <= 1'b0;
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
                // prefetch_state 的含义：
                //   PREFETCH_IDLE      : 还没发第一条
                //   PREFETCH_WAIT_R0   : 第一条地址已发，等待同步读返回窗口
                //   PREFETCH_CAP_R0    : 捕获第一条返回数据
                //   PREFETCH_WAIT_REQ1 : 第一条已完成，等待下一个 consume_tick 发第二条
                //   PREFETCH_WAIT_R1   : 第二条地址已发，等待同步读返回窗口
                //   PREFETCH_CAP_R1    : 捕获第二条返回数据
                //   PREFETCH_READY     : 两条都齐了，等待 pos 切换消费
                // -----------------------------------------------------------------
                // -----------------------------------------------------------------
                // 同步 SRAM 预取返回时序
                // -----------------------------------------------------------------
                // sram_sp 是同步读：
                // - 第 1 拍：拉高 active_rd_en_reg，送出地址
                // - 第 2 拍：rdata 更新，此时把返回值捕获到 prefetched_rows
                // -----------------------------------------------------------------
                case (current_state)
                    PREFETCH_IDLE: begin
                        if (issue_prefetch_req) begin
                            frame_rd_en_reg   <= 1'b1;
                            frame_rd_addr_reg <= ({1'b0, current_pos} << 1) + 5'd14;
                        end
                    end
                    PREFETCH_WAIT_REQ1: begin
                        if (issue_prefetch_req) begin
                            frame_rd_en_reg   <= 1'b1;
                            frame_rd_addr_reg <= ({1'b0, current_pos} << 1) + 5'd15;
                        end
                    end
                    PREFETCH_CAP_R0: begin
                        prefetched_rows[0] <= frame_rdata;
                    end
                    PREFETCH_CAP_R1: begin
                        prefetched_rows[1] <= frame_rdata;
                        // 约定 slot=0 放“下一窗口的倒数第二行新增行”
                        //     slot=1 放“下一窗口的最后一行新增行”
                        // 当 slot=1 也完成时，说明两行都已经预取完毕，可以允许 pos 切换。
                        prefetched_valid <= 1'b1;
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
