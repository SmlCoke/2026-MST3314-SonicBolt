`timescale 1ns / 1ps
/*
 * 模块名称: conv_core
 * 作者: SonicBolt 团队
 * 日期: 2026-04-13
 * 版本: v2.4
 *
 * 功能概述:
 *   Conv 调度与主计算核心。
 *
 * 设计定位:
 *   - 本模块只负责 token 调度、输入工作集切换时机、参数读时机以及后级计算模块拼接。
 *   - Conv1 整层参数保存在独立的 conv_param_store_rom 中。
 *   - 输入特征图的整帧缓存和工作集维护保存在 conv_shared_input_buffer 中。
 *
 * 当前数据流:
 *   - 同一 pos 的 8 个 group 复用同一份 14 行工作集
 *   - 只有在 pos 边界时才向输入缓存请求切换工作集
 *   - 权重和偏置仍然按 group 每拍读取
 *   - `consume_tick` 与 MAC 真正消费当前 token 的时刻对齐，供输入缓存后台预取下一 pos 的两行新数据
 *
 * 位宽说明:
 *   - pos_window_data     : 14 x 80bit = 1120bit，对应当前 pos 的 14 行工作集
 *   - weight row ROM data  : 11 x 224bit local data in conv_tile_mac
 *   - bias_data_bus       : 4 x 16bit = 64bit
 *   - out_stream_data     : 4 x 4 x 4 x 8bit = 512bit
 *
 * 调度语义:
 *   - 一张图共有 9 个 pos，每个 pos 对应 8 个 group。
 *   - 我们将一个 {pos, group} 组合称为一个 token，因此每张图共有 72 个 token。
 *   - token 发射顺序固定为:
 *       pos=0, group=0..7; pos=1, group=0..7; ...; pos=8, group=0..7
 *
 * 版本定位:
 *   - v2.0 相比 v1.0 `pos_req_valid` 不再每拍都请求窗口，而是只在初始化和 pos 边界请求，
 *     这样可以减少动态功耗, `consume_tick` 改为与 stage0_valid 对齐，用来驱动输入缓存预取。
 *   - v2.1 相比 v2.0 增加了第二层启动信号 out_stream_fire，当该信号为高时，告诉第二层 SRAM: 
 *     "马上开始准备参数, 下一个周期就要开始计算了"
 *   - v2.2 将所有公共子模块提取到 utils/ 目录下
 *   - v2.3 将杂糅状态更新逻辑重塑为三段式有限状态机
 *   - v2.4 为了将乘法器数量从 4928 降低为 2464 ，避免重复运算，减少面积开销，将 MAC 的输入改为半窗 2x4，并在 *      conv_core 内部增加半窗缓存和拼接逻辑。内部计算 token 改为 10 个 pos(0~9) x 8 个 group = 80 个 
 *      token。每个 token 只计算 4ch x 2x4 的半窗结果。使用 2x4x32 的寄存器阵列缓存上一 pos 的量化半窗，
 *      在下一次同 group 到来时拼成完整 4x4 tile 再对外输出。
 */
module conv_core #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,                    // 启动一次新图计算
    output reg           busy,                     // 高电平表示当前 80 个计算 token 尚未发完
    output reg           done,                     // 单拍完成脉冲，表示当前帧最后一个输出 tile 已流出
    output wire          issue_done,               // 单拍完成脉冲，表示当前帧 80 个计算 token 已全部发完

    // ---------- 输入图像交互接口 ----------
    output wire          pos_req_valid,            // 向输入缓存请求一个新的 pos 窗口
    output wire [3:0]    pos_req_pos,              // 请求的 pos 编号，范围 0~9
    output wire          consume_tick,
    input  wire          pos_window_valid,         // 输出窗口有效
    input  wire [14*80-1:0] pos_window_data,       // 返回的 14x10 窗口
    // v2.4 版本中，仍保持 14x10 窗口不变，为了不大改 shared_input_buffer 的 RTL Code 

    // ---------- 权重/偏置交互接口 ----------
    output wire          bias_rd_en,               // Conv 偏置 SRAM 读使能
    output wire [2:0]    bias_rd_group,            // 读取哪个 group 的偏置
    input  wire [63:0]   bias_data_bus,            // 偏置 SRAM 读出数据总线

    // ---------- 输出数据流接口 ----------
    output wire          out_stream_valid,         // 输出元数据：有效
    output wire          out_stream_last,          // 输出元数据：最后一个 token
    output wire [3:0]    out_stream_pos,           // 输出元数据：位置
    output wire [2:0]    out_stream_group,         // 输出元数据：通道组
    output wire          out_stream_fire,          // 输出元数据：第二层启动信号
    output wire [511:0]  out_stream_data           // 输出数据：量化后的 4x4 tile(来自两个半窗拼接)
);
    parameter IDLE = 1'b0;
    parameter BUSY = 1'b1;

    localparam integer POS_COUNT       = 10;            // pos = 0 是为了预先建立工作集，真正计算的 pos 是 1~9，共 9 个有效 pos
    localparam integer TOKEN_COUNT     = POS_COUNT * 8;
    localparam integer HALF_TILE_BITS  = 4 * 2 * 4 * 8;  // 4ch x 2row x 4col x 8bit = 256bit
    localparam integer FULL_TILE_BITS  = 4 * 4 * 4 * 8;  // 4ch x 4row x 4col x 8bit = 512bit

    reg current_state;
    reg next_state;

    // issue_* 记录下一个待发射 token 的坐标。
    reg  [3:0] issue_pos;
    reg  [2:0] issue_group;
    reg  [6:0] issue_count;

    // stage0_* 是送入 conv_tile_mac 的输入元数据寄存器。
    reg        stage0_valid;
    reg        stage0_last;
    reg  [3:0] stage0_pos;
    reg  [2:0] stage0_group;

    // 2x4 半窗缓存：每个 group 保存上一 pos 的量化结果，供下一次复用。
    reg  [HALF_TILE_BITS-1:0] half_tile_cache [0:7];

    wire       issue_fire;
    wire       issue_last_fire;
    wire [6:0] next_issue_count;
    wire       req_init_pos;
    wire       req_next_pos;
    wire       weight_rd_en;
    wire [2:0] weight_rd_group;

    // MAC 运算单元输出元数据与数据
    wire                tile_valid;
    wire                tile_last;
    wire [3:0]          tile_pos;
    wire [2:0]          tile_group;
    wire                tile_fire;
    wire [4*2*4*32-1:0] tile_accum_bus;

    // 重量化单元输出元数据与数据
    wire                      quant_valid;
    wire                      quant_last;
    wire [3:0]                quant_pos;
    wire [2:0]                quant_group;
    wire                      quant_fire;
    wire [HALF_TILE_BITS-1:0] quant_data;

    // 输出拼接相关信号
    // capture 代表捕获到正确输出，即元数据 valid = 1 且 pos 不为 0
    wire                      stream_capture;
    // frame 代表本帧计算结束，即元数据 valid = 1 且 last = 1
    wire                      stream_frame_done;

    // 输出数据/元数据寄存器
    reg                       stream_valid_reg;
    reg                       stream_last_reg;
    reg  [3:0]                stream_pos_reg;
    reg  [2:0]                stream_group_reg;
    reg  [FULL_TILE_BITS-1:0] stream_data_reg;

    integer idx_group;
    integer idx_ch;

    // 只有当当前工作集已经有效，且本图还有 token 未发完时，才能真正发射一个 token。 
    assign issue_fire       = busy && pos_window_valid && (issue_count < TOKEN_COUNT);
    
    // 最后一个 token 的发送信号
    assign issue_last_fire  = issue_fire && (issue_count == TOKEN_COUNT - 1);
    assign next_issue_count = issue_count + 7'd1;
    // 
    assign issue_done       = issue_last_fire;

    // 第一个 token 之前，输入缓存内部还没有建立工作集，因此需要显式请求 pos=0。
    assign req_init_pos = busy && !pos_window_valid && (issue_count == 7'd0);

    // 只在 pos 边界切换工作集，这里要支持滚动到内部计算的 pos=9。v2.3版本及之前都是 < 4'd8
    assign req_next_pos = stage0_valid && (stage0_group == 3'd7) && (stage0_pos < 4'd9);
    // 请求只有可能在第一次 token 发出和 pos 边界时发出，因此不会频繁切换，能够节省动态功耗。
    assign pos_req_valid = req_init_pos || req_next_pos;
    assign pos_req_pos   = req_next_pos ? (stage0_pos + 4'd1) : issue_pos;

    // consume_tick 与内部 80 个计算 token 对齐，继续驱动输入缓存的后台预取。
    assign consume_tick = stage0_valid;
    // 权重 / 偏置仍然按 token 粒度、按 group 发读请求。
    assign weight_rd_en    = issue_fire;
    assign weight_rd_group = issue_group;
    assign bias_rd_en      = issue_fire;
    assign bias_rd_group   = issue_group;

    // quant_valid 对应“当前半窗已经量化完成”。
    // 当 quant_pos > 0 时，说明已经拿到了当前 group 的上一半窗缓存，
    // 可以把“上一 pos 的 2x4”与“当前 pos 的 2x4”拼成完整 4x4 tile。
    assign stream_capture    = quant_valid && (quant_pos > 4'd0);   
    // ↑ capture 就是下一层启动信号，比其余四大元数据提前一拍，因为其余四个元数据为了等拼接4x4窗口，要显示打拍

    // 帧级结束信号：当前 token 是有效的，并且是当前 pos 的最后一个 group。
    assign stream_frame_done = stream_valid_reg && stream_last_reg;

    // 三段式状态机第一段：状态更新
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // 三段式状态机第二段：下一状态逻辑
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (start) begin
                    next_state = BUSY;
                end
            end

            BUSY: begin
                // 一旦最后一个计算 token 成功发射，前端 issue 侧即可立刻回到 IDLE，
                // 允许下一帧开始建立 pos=0 工作集；尾部输出仍由独立流水自然流完。
                if (issue_last_fire) begin
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // 三段式状态机第三段：调度寄存器更新
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            done         <= 1'b0;
            issue_pos    <= 4'd0;
            issue_group  <= 3'd0;
            issue_count  <= 7'd0;
            stage0_valid <= 1'b0;
            stage0_last  <= 1'b0;
            stage0_pos   <= 4'd0;
            stage0_group <= 3'd0;
        end else begin
            // done 继续保留“最后一个输出 tile 已流出”的旧语义；
            // 这样对观察输出尾拍的上层逻辑保持兼容。
            done <= stream_frame_done;

            case (current_state)
                IDLE: begin
                    busy         <= 1'b0;
                    stage0_valid <= 1'b0;
                    stage0_last  <= 1'b0;
                    stage0_pos   <= 4'd0;
                    stage0_group <= 3'd0;
                    if (start) begin
                        busy        <= 1'b1;
                        issue_pos   <= 4'd0;
                        issue_group <= 3'd0;
                        issue_count <= 7'd0;
                    end
                end

                BUSY: begin
                    // 最后一个 token 发出后，busy = 0, 此时最后一个 token 已经送进流水线
                    // 在此前，busy 一直为高
                    busy         <= !issue_last_fire;

                    // 元数据核心更新逻辑
                    stage0_valid <= issue_fire;
                    stage0_last  <= issue_last_fire;
                    stage0_pos   <= issue_pos;
                    stage0_group <= issue_group;
                    
                    // pos-group 调度核正常更新，发射 token 的坐标
                    if (issue_fire) begin
                        issue_count <= next_issue_count;
                        if (issue_group == 3'd7) begin
                            issue_group <= 3'd0;
                            issue_pos   <= issue_pos + 4'd1;
                        end else begin
                            issue_group <= issue_group + 3'd1;
                        end
                    end

                end

                default: begin
                    busy         <= 1'b0;
                    stage0_valid <= 1'b0;
                    stage0_last  <= 1'b0;
                end
            endcase
        end
    end

    // 半窗缓存寄存器更新，只保留上一 pos 的 2x4 结果，完整 4x4 通过组合拼接直接导出。
    // 注意：这里不能在新帧 start 时立即清零，因为上一帧尾部输出还可能在流水线中，仍然要读取旧缓存完成拼接。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx_group = 0; idx_group < 8; idx_group = idx_group + 1) begin
                half_tile_cache[idx_group] <= {HALF_TILE_BITS{1'b0}};
            end
        end else begin
            if (quant_valid) begin
                // 先把当前 2x4 半窗写回缓存，供下一次相邻 pos 复用。
                // 不需要显式做“帧间清零”：
                // 新帧同一 group 的 pos=0 半窗一定会先到，再覆盖掉旧帧残留值。
                half_tile_cache[quant_group] <= quant_data;
            end
        end
    end

    // 输出拼接寄存级：
    // - pos=0 只写 half_tile_cache，不对外输出
    // - pos=1~9 时，把上一 pos 的半窗和当前半窗拼成完整 4x4 tile
    // - 这里显式打一拍，继续保持 out_stream_fire 比 out_stream_valid 早一拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stream_valid_reg <= 1'b0;
            stream_last_reg  <= 1'b0;
            stream_pos_reg   <= 4'd0;
            stream_group_reg <= 3'd0;
            stream_data_reg  <= {FULL_TILE_BITS{1'b0}};
        end else begin

            // 只有 pos > 0 , stream_capture 才能为 1 , 目的就是不影响下层以及 testbench
            stream_valid_reg <= stream_capture;
            stream_last_reg  <= quant_last && (quant_pos > 4'd0);

            // 这里的减 4'd1 是为了不影响下级流水做出的重要操作，下级的 pos=0 仍然为第一个有效 pos 的语义
            stream_pos_reg   <= quant_pos - 4'd1;
            stream_group_reg <= quant_group;
            if (stream_capture) begin
                for (idx_ch = 0; idx_ch < 4; idx_ch = idx_ch + 1) begin
                    // 每个通道 128bit：
                    //   低 64bit  = 上半 2x4（上一 pos 缓存）
                    //   高 64bit  = 下半 2x4（当前 pos 新算结果）
                    stream_data_reg[idx_ch*128 +: 64]      <= half_tile_cache[quant_group][idx_ch*64 +: 64];
                    stream_data_reg[idx_ch*128 + 64 +: 64] <= quant_data[idx_ch*64 +: 64];
                end
            end
        end
    end


    // MAC 现在输出 4ch x 2x4 的 INT32 半窗。
    conv_tile_mac u_conv_tile_mac (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入元数据 ----------
        .in_valid(stage0_valid),      // in: 输入元数据: 有效
        .in_last(stage0_last),        // in: 输入元数据: 最后一个 token
        .in_pos(stage0_pos),          // in: 输入元数据: pos 编号(0~9, 0为预热建立工作集)
        .in_group(stage0_group),      // in: 输入元数据: group 编号
        .in_fire(issue_fire),         // in: 输入元数据: 夏优启动信号

        // ---------- 输入数据 ----------
        .pos_window_data(pos_window_data), // in: 输入数据: 当前 pos 的 14 行工作集

        // ---------- 权重和偏置 ----------
        .weight_rd_en(weight_rd_en),       // in: 权重读使能
        .weight_rd_group(weight_rd_group), // in: 权重 group
        .bias_data_bus(bias_data_bus),     // in: 偏置数据总线: 当前 group 的 4 条 bias

        // ---------- 输出半窗数据和元数据 ----------
        .out_valid(tile_valid),         // out: 输出元数据: 有效
        .out_last(tile_last),           // out: 输出元数据: 最后一个半窗
        .out_pos(tile_pos),             // out: 输出元数据: pos 编号
        .out_group(tile_group),         // out: 输出元数据: group 编号
        .out_fire(tile_fire),           // out: 输出元数据: 第二层启动信号
        .out_accum_bus(tile_accum_bus)  // out: 输出数据: 4ch x 2row x 4col 的 INT32 半窗累加结果
    );

    // 量化阶段也改成半窗 2x4。
    rescale_relu #(
        .M0(M0),
        .SHIFT_N(SHIFT_N),
        .TILE_H(2),
        .TILE_W(4)
    ) u_conv_rescale_relu (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入半窗数据和元数据 ----------
        .in_valid(tile_valid),         // in: 输入元数据: 有效 
        .in_last(tile_last),           // in: 输入元数据: 最后一个半窗
        .in_pos(tile_pos),             // in: 输入元数据: pos 编号，0~9, 0为预热建立工作集
        .in_group(tile_group),         // in: 输入元数据: group 编号
        .in_fire(tile_fire),           // in: 输入元数据: 第二层启动信号
        .in_data_bus(tile_accum_bus),  // in: 输入数据总线: 4ch x 2row x 4col 的 INT32 半窗累加结果

        // ---------- 输出半窗数据和元数据 ----------
        .out_valid(quant_valid),       // out: 输出元数据: 有效
        .out_last(quant_last),         // out: 输出元数据: 最后一个半窗
        .out_pos(quant_pos),           // out: 输出元数据: pos 编号，0~9, 0为预热建立工作集
        .out_group(quant_group),       // out: 输出元数据: group 编号
        .out_fire(quant_fire),         // out: 输出元数据: 第二维启动信号
        .out_data_bus(quant_data)      // out: 输出数据总线: 4ch x 2row x 4col 的 8bit 量化半窗结果
    );

    assign out_stream_valid = stream_valid_reg;
    assign out_stream_last  = stream_last_reg;
    assign out_stream_pos   = stream_pos_reg;
    assign out_stream_group = stream_group_reg;
    assign out_stream_fire  = stream_capture;
    assign out_stream_data  = stream_data_reg;

endmodule
