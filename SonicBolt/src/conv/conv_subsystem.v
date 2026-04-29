`timescale 1ns / 1ps
/*
 * 模块名称: conv_subsystem
 * 作者: SonicBolt 团队
 * 日期: 2026-04-29
 * 版本: v2.8
 *
 * 功能概述:
 *   Conv 子系统顶层，负责把输入图像缓存、卷积参数存储和 Conv 计算核心串接起来。
 *
 * 主数据流:
 *   输入图像 -> conv_shared_input_buffer -> conv_core -> out_stream_*
 *
 * 版本定位:
 *   - 当前只实现 Conv 层，但参数存储语义已经固定为“层内完整参数 SRAM”。
 *   - 本模块内部保存的是 Conv 整层的全部权重和全部偏置，不是“当前这次推理临时需要的参数”。
 *   - 当前版本输入侧改为单帧缓存，不再保留双 bank ping-pong 输入缓冲
 *   - 相比 v2.0 版本，当前顶层为“单 SRAM 缓存完整输入 + 单 reg 缓存 window + conv_core 控制预取”主通路。
 *   - v2.3 相比 v2.2 增加了第二层启动信号 out_stream_fire，当该信号为高时，告诉第二层 SRAM: 
 *     "马上开始准备参数, 下一个周期就要开始计算了"
 *   - v2.3 有 bug，fire/last 信号并没有实际作为输出端口，v2.4已修复
 *   - v2.5 中，将模块下所有公共子模块提取到 utils/ 目录下
 *   - v2.6 加入双帧缓存机制，实现连续计算，提升吞吐，start 不再直接驱动 conv_core，而是先与 ready bank 状态
 *      组合成 launch_start
 *   - v2.7 加入半窗缓存机制，将 MAC 单元 4928 个乘法器缩减为 2464，解决 14x10 窗口重复计算的问题
 *   - v2.8 输入数据立即打拍，解决 input2reg 路径过长问题
 *     
 */

module conv_subsystem #(
    parameter integer M0      = 111,
    parameter integer SHIFT_N = 14
) (
    input  wire          clk,              // 时钟
    input  wire          rst_n,            // 低有效复位
    input  wire          start,            // 启动一次新图计算
    output wire          busy,             // 高电平表示 Conv 前端 80 个计算 token 尚未发完
    output wire          done,             // 单拍完成脉冲，表示当前帧最后一个输出 tile 已流出
    output wire          issue_done,       // 单拍完成脉冲，表示当前帧 80 个计算 token 已全部发完

    // ------------ 输入图像写控制信号 ------------
    input  wire          img_wr_en,        // 输入图像写使能
    input  wire [4:0]    img_wr_addr,      // 输入图像行地址，30 行因此使用 5bit
    input  wire [79:0]   img_wr_row_data,  // 输入图像写数据，一行 10 个像素，10 x 8bit = 80bit
    input  wire          img_wr_commit,    // 当前帧 30 行均已写完，提交当前写 bank
    output wire          img_wr_ready,     // 当前允许开始写下一帧

    // ------------ 输出数据流接口 ------------
    output wire          out_stream_valid, // 输出 tile 有效
    output wire          out_stream_last,  // 输出 tile 是否是最后一个
    output wire [3:0]    out_stream_pos,   // 输出 tile 的 pos 编号
    output wire [2:0]    out_stream_group, // 输出 tile 的 group 编号
    output wire          out_stream_fire,  // 输出的第二层启动信号
    output wire [511:0]  out_stream_data   // 输出 tile 数据，4 x 4 x 4 x 8bit = 512bit
);

    wire          pos_req_valid;           // 下游请求一个新的 pos 窗口
    wire [3:0]    pos_req_pos;             // 请求的 pos 编号
    wire          pos_window_valid;        // 输入窗口有效
    wire          consume_tick;            // conv_core 告诉输入缓存“当前 token 已被真正消费”
    wire [14*80-1:0] pos_window_data;      // 返回的 14x10 工作集，按 14 个 80bit 行展平

    wire          weight_rd_en;            // 权重 SRAM 读使能    
    wire [2:0]    weight_rd_group;         // 权重 SRAM 读地址    

    wire          bias_rd_en;              // 偏置 SRAM 读使能 
    wire [2:0]    bias_rd_group;           // 偏置 SRAM 读地址    

    wire [11*224-1:0] weight_data_bus; // 11 条 kernel row，按 11 个 224bit 切片展平
    wire [63:0]   bias_data_bus;           // 偏置 SRAM 读出数据总线

    wire          tile_valid_int;          // Conv 输出元数据：有效  
    wire          tile_last_int;           // Conv 输出元数据：有效
    wire [3:0]    tile_pos_int;            // Conv 输出元数据：位置
    wire [2:0]    tile_group_int;          // Conv 输出元数据：通道组  
    wire          tile_fire_int;           // Conv 输出的第二层启动提示信号
    wire [511:0]  tile_data_int;           // Conv 输出数据：量化后的 tile 数据

    // ---------- 输入信号流水线寄存器 ----------
    // 解决 placement 阶段 input2reg 路径过长问题：
    // 将 img_wr_* 输入信号打一拍，使 PI 到第一个寄存器的组合逻辑路径最短化
    reg            img_wr_en_r;
    reg [4:0]      img_wr_addr_r;
    reg [79:0]     img_wr_row_data_r;
    reg            img_wr_commit_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            img_wr_en_r       <= 1'b0;
            img_wr_addr_r     <= 5'd0;
            img_wr_row_data_r <= 80'd0;
            img_wr_commit_r   <= 1'b0;
        end else begin
            img_wr_en_r       <= img_wr_en;
            img_wr_addr_r     <= img_wr_addr;
            img_wr_row_data_r <= img_wr_row_data;
            img_wr_commit_r   <= img_wr_commit;
        end
    end

    // ---------- Ping-Pong 输入缓存控制 ----------
    wire [1:0]       ready_bank_mask;      // 哪个输入 bank 已经装好完整待消费帧
    wire             img_wr_ready_int;     // 输入缓存内部生成的“可继续写下一帧”信号
    wire             consume_bank_sel;     // 本次启动时应消费的 ready bank
    wire             launch_start;         // 真正送给输入缓存和 conv_core 的启动脉冲

    // 当前策略下优先选择编号较小的 ready bank；
    // 由于 launch_start 已经要求 ready_bank_mask 非零，因此这里总能选出一个合法 bank。
    assign consume_bank_sel   = ready_bank_mask[0] ? 1'b0 : 1'b1;

    // 只有至少有一帧完整输入准备好时，外部 start 才会真正启动 Conv。
    assign launch_start       = start && (|ready_bank_mask);

    // 输入双帧缓存：
    // - 对外暴露逐行写接口
    // - 内部维护 Ping-Pong bank 的 ready / consume / write 状态
    // - 根据 conv_core 的 pos 请求返回 14x10 输入窗口
    conv_shared_input_buffer u_conv_shared_input_buffer (
        .clk(clk),
        .rst_n(rst_n),

        // ---------- 输入图写入接口 ----------
        .img_wr_en(img_wr_en_r),                    // in: 输入图逐行写使能（已打拍）
        .img_wr_addr(img_wr_addr_r),                // in: 写入行地址（已打拍）
        .img_wr_row_word(img_wr_row_data_r),        // in: 一行 10 个像素（已打拍）
        .img_wr_commit(img_wr_commit_r),            // in: 当前写入 Bank 的30行已经写完，可以被消费（已打拍）
        .img_wr_ready(img_wr_ready),          // out:当前存在可写 bank                       

        // ---------- 消费启动接口 ----------
        .start_consume(launch_start),             // in: 启动消费当前 SRAM 中的一张新图
        .consume_bank_sel(consume_bank_sel),      // in: 本次 start_consume 要切换到哪个 bank
        .ready_bank_mask(ready_bank_mask),        // out: 哪几个 bank 已经 ready，可以开始启动消费

        // ---------- pos 窗口请求 / 返回接口 ----------
        .pos_req_valid(pos_req_valid),            // in: conv_core 请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),                // in: 请求的 pos 编号
        .pos_window_valid(pos_window_valid),      // out: 输入窗口有效
        .consume_tick(consume_tick),              // out: conv_core 确认当前 token 已被真正消费
        .pos_window_data(pos_window_data)         // out: 返回的 14x10 工作窗口
    );

    // 参数存储模块：
    // - 保存 Conv1 整层 11 个 kernel row bank + 1 个 bias bank
    // - 运行时按 group 输出当前 token 所需参数切片
    conv_param_store u_conv_param_store (
        .clk(clk),
        .rst_n(rst_n),

        // ------------ 权重 SRAM 读控制信号 ------------
        .weight_rd_en(weight_rd_en),        // in: 权重读使能
        .weight_rd_group(weight_rd_group),  // in: 读取哪个 group 的权重，地址范围 0..7

        // ------------ 偏置 SRAM 读控制信号 ------------
        .bias_rd_en(bias_rd_en),            // in: 偏置读使能
        .bias_rd_group(bias_rd_group),      // in: 读取哪个 group 的偏置，地址范围 0..7

        // ------------ SRAM 读出数据总线 ------------
        .weight_data_bus(weight_data_bus),  // out: 11 条 kernel row，按 11 个 224bit 切片展平     
        .bias_data_bus(bias_data_bus)       // out: 偏置 SRAM 读出数据总线
    );

    // 计算核心模块：
    // -  pos/group token 调度
    // - 负责驱动 MAC 与MAC 与量化输出链
    conv_core #(
        .M0(M0),
        .SHIFT_N(SHIFT_N)
    ) u_conv_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(launch_start),                 // in: 启动一次新图计算
        .busy(busy),                 // out: 高电平表示当前仍在处理本张图
        .done(done),                 // out: 单拍完成脉冲
        .issue_done(issue_done),     // out: 单拍完成脉冲，表示当前帧 80 个 token 已发完

        // ---------- 输入输入窗口握手接口 ----------
        .pos_req_valid(pos_req_valid),        // out: 向输入缓存请求一个新的 pos 窗口
        .pos_req_pos(pos_req_pos),            // out: 请求的 pos 编号，范围 0~8，因此使用 4bit
        .consume_tick(consume_tick),          // out: 当前 token 是否真正发射进入流水线，告诉输入缓存可以更新窗口状态了
        .pos_window_valid(pos_window_valid),  // in: 输入窗口有效
        .pos_window_data(pos_window_data),    // in: 返回的 14x10 窗口，14 x 10 x 8bit = 1120bit

        // ---------- 权重/偏置交互接口 ----------
        .weight_rd_en(weight_rd_en),          // out: Conv 权重 SRAM 读使能
        .weight_rd_group(weight_rd_group),    // out: 读取哪个 group 的权重
        .bias_rd_en(bias_rd_en),              // out: Conv 偏置 SRAM 读使能
        .bias_rd_group(bias_rd_group),        // out: 读取哪个 group 的偏置
        .weight_data_bus(weight_data_bus),    // in: 权重 SRAM 读出数据总线
        .bias_data_bus(bias_data_bus),        // in: 偏置 SRAM 读出数据总线

        // ---------- 输出数据流接口 ----------
        .out_stream_valid(tile_valid_int),     // out: 输出元数据：有效
        .out_stream_last(tile_last_int),       // out: 输出元数据：最后
        .out_stream_pos(tile_pos_int),         // out: 输出元数据：位置
        .out_stream_group(tile_group_int),     // out: 输出元数据：通道组
        .out_stream_fire(tile_fire_int),       // out: 输出元数据：第二层启动信号
        .out_stream_data(tile_data_int)        // out: 输出数据：量化后的 tile 数据
    );

    assign out_stream_valid = tile_valid_int;  // 输出元数据: 有效
    assign out_stream_last  = tile_last_int;   // 输出元数据: last
    assign out_stream_pos   = tile_pos_int;    // 输出元数据: 位置编号
    assign out_stream_group = tile_group_int;  // 输出元数据: 通道组编号
    assign out_stream_fire  = tile_fire_int;   // 输出的第二层启动提示信号
    assign out_stream_data  = tile_data_int;   // 输出数据: 量化后的 tile 数据

endmodule
