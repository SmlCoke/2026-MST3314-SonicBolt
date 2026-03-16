#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
data_prepare.py  —  Conv1 Testbench 数据准备脚本
=================================================
读取 MiniCNN 参考项目的原始参数和测试数据，
生成 Verilog Testbench 可直接用 $readmemh 加载的 hex 文件。

生成文件清单：
  conv1_input.hex   — 30行，每行20 hex字符（10×INT8，pixel[0]在低位）
  conv1_weight.hex  — 32行，每行154 hex字符（77×INT8，elem[0]在低位）
    conv1_bias.hex    — 32行，每行4 hex字符（INT16 偏置）
  conv1_golden.hex  — 80行，每行64 hex字符（32×INT8 输出，ch[0]在低位）

使用方法：
  python data_prepare.py
"""

import os
import sys

# ============================================================
# 路径配置
# ============================================================
SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
SAMPLES_DIR  = os.path.join(SCRIPT_DIR, '..', '..', 'MiniCNN', 'sim', 'samples')

PARAM_DIR    = os.path.join(SAMPLES_DIR, 'Param')
TEST_DIR     = os.path.join(SAMPLES_DIR, 'Test')
INPUT_DIR    = os.path.join(SAMPLES_DIR, 'In')

OUT_DIR      = SCRIPT_DIR  # 输出到当前目录


# ============================================================
# 工具函数
# ============================================================
def int8_to_hex(val):
    """将有符号 INT8 (-128~127) 转为 2 位 hex 字符串（补码）"""
    return format(val & 0xFF, '02x')

def int16_to_hex(val):
    """将有符号 INT16 转为 4 位 hex 字符串（补码）"""
    return format(val & 0xFFFF, '04x')


# ============================================================
# 1. 生成 conv1_input.hex
#    格式：30行，每行 10 个 INT8 打包为 80-bit hex（pixel[0]在LSB）
#    $readmemh 加载到 reg [79:0] input_mem [0:29]
# ============================================================
def gen_input_hex():
    """读取 Test/Input.txt 并生成 conv1_input.hex"""
    filepath = os.path.join(TEST_DIR, 'Input.txt')
    with open(filepath, 'r') as f:
        raw = f.read().split()

    vals = [int(x) for x in raw]
    assert len(vals) == 300, f"期望 300 个输入值，实际 {len(vals)}"

    lines = []
    for row in range(30):
        # 每行 10 个 INT8，pixel[0] 在 LSB（低位）
        hex_str = ''
        for col in reversed(range(10)):  # 从高位到低位写（$readmemh 从左到右是高位到低位）
            hex_str += int8_to_hex(vals[row * 10 + col])
        lines.append(hex_str)

    out_path = os.path.join(OUT_DIR, 'conv1_input.hex')
    with open(out_path, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    print(f"[OK] conv1_input.hex: {len(lines)} lines")


# ============================================================
# 2. 生成 conv1_weight.hex
#    格式：32行，每行 77 个 INT8 打包为 616-bit hex（elem[0]在LSB）
#    $readmemh 加载到 reg [615:0] weight_mem [0:31]
# ============================================================
def gen_weight_hex():
    """读取 Param/Param_Conv_Weight.txt 并生成 conv1_weight.hex"""
    filepath = os.path.join(PARAM_DIR, 'Param_Conv_Weight.txt')
    with open(filepath, 'r') as f:
        content = f.readlines()

    # 解析 32 个 11×7 的卷积核
    weights = []
    kernel = []
    for line in content:
        stripped = line.strip()
        if stripped == '':
            if kernel:
                weights.append(kernel)
                kernel = []
        else:
            kernel.append([int(x) for x in stripped.split()])
    if kernel:
        weights.append(kernel)

    assert len(weights) == 32, f"期望 32 个卷积核，实际 {len(weights)}"

    lines = []
    for k in range(32):
        # 展平为 77 元素（行主序）：kernel[row][col], row=0..10, col=0..6
        flat = []
        for row in range(11):
            for col in range(7):
                flat.append(weights[k][row][col])
        assert len(flat) == 77

        # elem[0] 在 LSB，$readmemh 从左到右是高位到低位
        hex_str = ''
        for i in reversed(range(77)):
            hex_str += int8_to_hex(flat[i])
        lines.append(hex_str)

    out_path = os.path.join(OUT_DIR, 'conv1_weight.hex')
    with open(out_path, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    print(f"[OK] conv1_weight.hex: {len(lines)} lines")


# ============================================================
# 3. 生成 conv1_bias.hex
#    格式：32行，每行 4 hex字符（INT16 偏置）
#    $readmemh 加载到 reg [15:0] bias_mem [0:31]
# ============================================================
def gen_bias_hex():
    """读取 Param/Param_Conv_Bias.txt 并生成 conv1_bias.hex"""
    filepath = os.path.join(PARAM_DIR, 'Param_Conv_Bias.txt')
    with open(filepath, 'r') as f:
        raw = f.read().split()

    vals = [int(x) for x in raw]
    assert len(vals) == 32, f"期望 32 个偏置值，实际 {len(vals)}"

    lines = []
    for v in vals:
        lines.append(int16_to_hex(v))

    out_path = os.path.join(OUT_DIR, 'conv1_bias.hex')
    with open(out_path, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    print(f"[OK] conv1_bias.hex: {len(lines)} lines")


# ============================================================
# 4. 生成 conv1_golden.hex
#    格式：80行（输出空间 20row × 4col），每行 32 个 INT8 打包为 256-bit hex
#    遍历顺序：row_out=0..19, col_out=0..3（与硬件 FSM 遍历顺序一致）
#    $readmemh 加载到 reg [255:0] golden_mem [0:79]
# ============================================================
def gen_golden_hex():
    """读取 Test/Out_Conv.txt 并生成 conv1_golden.hex"""
    filepath = os.path.join(TEST_DIR, 'Out_Conv.txt')
    with open(filepath, 'r') as f:
        content = f.readlines()

    # 解析 32 个 (20,4) 矩阵，空行分隔
    channels = []  # channels[ch][row][col]
    matrix = []
    for line in content:
        stripped = line.strip()
        if stripped == '':
            if matrix:
                channels.append(matrix)
                matrix = []
        else:
            matrix.append([int(x) for x in stripped.split()])
    if matrix:
        channels.append(matrix)

    assert len(channels) == 32, f"期望 32 个通道，实际 {len(channels)}"
    for ch in range(32):
        assert len(channels[ch]) == 20, f"通道{ch} 期望 20 行，实际 {len(channels[ch])}"
        for row in range(20):
            assert len(channels[ch][row]) == 4, f"通道{ch} 行{row} 期望 4 列，实际 {len(channels[ch][row])}"

    # 按硬件输出顺序生成：row_out=0..19, col_out=0..3
    lines = []
    for row_out in range(20):
        for col_out in range(4):
            # 32 通道在同一像素位置的值，ch[0] 在 LSB
            hex_str = ''
            for ch in reversed(range(32)):
                hex_str += int8_to_hex(channels[ch][row_out][col_out])
            lines.append(hex_str)

    assert len(lines) == 80, f"期望 80 行输出，实际 {len(lines)}"

    out_path = os.path.join(OUT_DIR, 'conv1_golden.hex')
    with open(out_path, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    print(f"[OK] conv1_golden.hex: {len(lines)} lines")


# ============================================================
# 主函数
# ============================================================
def main():
    print("=" * 60)
    print("Conv1 Testbench 数据准备脚本")
    print("=" * 60)
    print(f"参数目录: {os.path.abspath(PARAM_DIR)}")
    print(f"测试目录: {os.path.abspath(TEST_DIR)}")
    print(f"输出目录: {os.path.abspath(OUT_DIR)}")
    print()

    gen_input_hex()
    gen_weight_hex()
    gen_bias_hex()
    gen_golden_hex()

    print()
    print("所有数据文件已生成！")


if __name__ == '__main__':
    main()
