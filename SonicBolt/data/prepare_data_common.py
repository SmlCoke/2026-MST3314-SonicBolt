#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prepare_data_common

提取 `prepare_test_data.py` 中单样本测试与多样本连续仿真都能复用的
解析 / 打包 / `.mem` 生成工具函数。

设计原则:
    1. 尽量保留原函数接口与注释语义，减少旧脚本迁移成本
    2. 通过 `set_prep_dir()` 切换输出目录，避免复制整份实现
    3. 单样本 `prepared_test/` 与多样本 `prepare_sim/` 共用同一套参数文件生成逻辑
"""

from __future__ import annotations

import math
import re
import struct
import textwrap
from pathlib import Path
from typing import Iterable, List, Tuple


ROOT_DIR = Path(__file__).resolve().parent
PARAM_DIR = ROOT_DIR / "Param"
TEST_DIR = ROOT_DIR / "Test"
PREP_DIR = ROOT_DIR / "prepared_test"
SCALE_FILE = ROOT_DIR / "Scale" / "Scale.txt"

# 当前 CNN / testbench 使用到的固定几何参数。
INPUT_ROWS = 30
INPUT_COLS = 10
POS_COUNT = 9
GROUP_COUNT = 8
CHANNELS_PER_GROUP = 4
BIAS_BANK_COUNT = 1


def set_prep_dir(path: Path) -> None:
    """切换当前预处理输出目录。"""
    global PREP_DIR
    PREP_DIR = path


# 将数据限制为 uint8
def to_u8(value: int) -> int:
    return value & 0xFF


# 将数据限制为 uint16
def to_u16(value: int) -> int:
    return value & 0xFFFF


def pack_values(values: Iterable[int], width: int) -> int:
    """按低位在前的顺序把一串定宽整数打包成一个大整数。"""
    packed = 0
    shift = 0
    # 每个 value 都是 width 位宽整数，按照小索引位于低位构筑
    for value in values:
        # (1 << width) - 1 是一个 width 位全 1 的掩码，value & 掩码 可以确保只保留 value 的低 width 位
        # 每个 value 都被放置在 packed 中对应的位置，shift 变量记录当前应该放置的位数偏移
        packed |= (value & ((1 << width) - 1)) << shift
        shift += width
    return packed


def parse_input_sample(path: Path) -> List[List[int]]:
    """
    读取输入样本文件，并重排成 30x10 的二维输入矩阵。
    输入数据允许以一行或多行形式给出，但最终都被视为 300 个 int8 值，按行优先顺序排列。
    """
    flat_values: List[int] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            flat_values.extend(int(token) for token in line.split())

    expected = INPUT_ROWS * INPUT_COLS
    # 如果输入值数量不是 300 个，强制报错退出
    if len(flat_values) != expected:
        raise ValueError(f"{path} contains {len(flat_values)} input values, expected {expected}")

    # 返回时将数据整理为 30 rows x 10 cols 的二维列表，方便后续按行生成输入行文件。
    return [
        flat_values[row_idx * INPUT_COLS : (row_idx + 1) * INPUT_COLS]
        for row_idx in range(INPUT_ROWS)
    ]


def parse_sigmoid_output(path: Path) -> List[float]:
    """读取最终 sigmoid 输出文件，返回长度为 2 的浮点向量。"""
    values: List[float] = []
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            values.extend(float(token) for token in line.split())
    if len(values) != 2:
        raise ValueError(f"{path} contains {len(values)} values, expected 2")
    return values


# 解析 Conv 以及 DWConv 层的权重参数
def parse_weights(weight_path: Path, kernel_h: int, kernel_w: int) -> List[List[List[int]]]:
    """解析 Conv/DWConv 权重文件，返回 weights[out_ch][ky][kx]。"""
    # 所有卷积核
    kernels: List[List[List[int]]] = []
    # 当前卷积核
    current_kernel: List[List[int]] = []
    with weight_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            # 如果遇到空行，说明当前卷积核填充结束了，加入 kernels 列表，并准备解析下一个卷积核。
            if not line:
                if current_kernel:
                    kernels.append(current_kernel)
                    current_kernel = []
                continue
            # 解析该行的所有权重值
            values = [int(token) for token in line.split()]
            # 每行应该恰好包含 kernel_w 个权重值，否则强制报错退出。
            if len(values) != kernel_w:
                raise ValueError(f"{weight_path} contains a non-{kernel_w}-column weight row: {line}")
            current_kernel.append(values)

    # 加入最后一个卷积核（如果文件末尾没有空行）
    if current_kernel:
        kernels.append(current_kernel)

    if len(kernels) != 32:
        raise ValueError(f"{weight_path} contains {len(kernels)} kernels, expected 32")
    for kernel in kernels:
        # 每个卷积核应该恰好包含 kernel_h 行，否则强制报错退出。
        if len(kernel) != kernel_h:
            raise ValueError(f"{weight_path} contains a kernel with {len(kernel)} rows, expected {kernel_h}")
    return kernels


# 解析 Conv, DWConv, PWConv, FC 层的偏置参数
def parse_bias(bias_path: Path, layer_name: str) -> List[int]:
    """解析 Conv/DWConv/PWConv/FC bias 文件，返回对应长度的 bias 列表。"""
    values: List[int] = []
    with bias_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            values.extend(int(token) for token in line.split())
    if layer_name in ["conv", "dwconv", "pwconv"] and len(values) != 32:
        raise ValueError(f"{bias_path} contains {len(values)} bias values, expected 32")
    elif layer_name == "fc" and len(values) != 2:
        raise ValueError(f"{bias_path} contains {len(values)} bias values, expected 2")
    return values


def parse_test_layer_output(output_path: Path, output_h: int, output_w: int) -> List[List[List[int]]]:
    """
    解析 Test/Out_Conv.txt, Test/Out_DWConv.txt, Test/Out_PWConv.txt，
    返回 conv_out[out_ch][out_row][out_col] / dwconv_out[out_ch][out_row][out_col] / pwc_out[out_ch][out_row][out_col]
    注意，这里的数据是没有经过 ReLU，但是经过了 SATURATE 的输出。
    """
    channels: List[List[List[int]]] = []
    current_channel: List[List[int]] = []
    with output_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            # 如果遇到空行，说明当前通道的 Feature Map 填充结束了
            if not line:
                if current_channel:
                    channels.append(current_channel)
                    current_channel = []
                continue
            # 解析该行的所有输出数据
            values = [int(token) for token in line.split()]
            if len(values) != output_w:
                raise ValueError(f"{output_path} contains a non-{output_w}-column output row: {line}")
            current_channel.append(values)

    # 添加最后一个输出通道（如果文件末尾没有空行）
    if current_channel:
        channels.append(current_channel)

    if len(channels) != 32:
        raise ValueError(f"{output_path} contains {len(channels)} output channels, expected 32")
    for channel in channels:
        if len(channel) != output_h:
            raise ValueError(f"{output_path} contains an output channel with {len(channel)} rows, expected {output_h}")
    return channels


def parse_flat_vector(path: Path, expected_count: int, value_type: type[int] | type[float]) -> List[int] | List[float]:
    """解析单行向量类文件，返回指定长度的数值列表。"""
    values: List[int] | List[float] = []
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            values.extend(value_type(token) for token in line.split())
    if len(values) != expected_count:
        raise ValueError(f"{path} contains {len(values)} values, expected {expected_count}")
    return values


def parse_named_float(scale_path: Path, field_name: str) -> float:
    """从 Scale.txt 中提取指定名称的浮点参数。"""
    pattern = re.compile(rf"{re.escape(field_name)}\s*=\s*([-+eE0-9\.]+)")
    with scale_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            match = pattern.search(line)
            if match:
                return float(match.group(1))
    raise ValueError(f"Unable to find {field_name} in {scale_path}")


def float_to_u32(value: float) -> int:
    """把 Python float 转成 IEEE754 FP32 对应的 32bit 无符号整数。"""
    return struct.unpack("<I", struct.pack("<f", value))[0]


def ensure_dirs() -> None:
    """确保当前 PREP_DIR 下的输出目录存在。"""
    (PREP_DIR / "conv_weights").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "conv_bias").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "dwconv_weights").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "dwconv_bias").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "pwconv_weights").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "pwconv_bias").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "fc_weights").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "fc_bias").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "sigmoid_lut").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "samples").mkdir(parents=True, exist_ok=True)


def write_text_if_changed(path: Path, content: str) -> None:
    """仅在内容变化时写文件，避免无意义覆盖。"""
    if path.exists():
        try:
            if path.read_text(encoding="utf-8") == content:
                return
        except OSError:
            pass
    path.write_text(content, encoding="utf-8")


def write_lines(path: Path, lines: Iterable[str]) -> None:
    """把字符串序列按行写入文件。"""
    write_text_if_changed(path, "\n".join(lines) + "\n")


def generate_weight_files(weights: List[List[List[int]]], kernel_h: int, kernel_w: int, layer_name: str) -> dict:
    """生成 Conv/DWConv 权重 bank 文件和线性展开的 weight_words.mem。"""
    # Kernel 行数 = Bank， 每个 Bank depth = GROUP_COUNT，共存储 4 个通道的权重数据
    weight_bank_words: List[List[int]] = [[0 for _ in range(GROUP_COUNT)] for _ in range(kernel_h)]

    # 逐 group 填充数据
    for group in range(GROUP_COUNT):
        # 每个 group 4个通道
        # base_channel = 当前 group 第一个 channel 的编号
        base_channel = group * CHANNELS_PER_GROUP
        # 分发到 kernel_h 个 Bank 行
        for ky in range(kernel_h):
            channel_words = []
            # 每个 bank 的每个字包含 CHANNELS_PER_GROUP 个通道的数据
            for local_ch in range(CHANNELS_PER_GROUP):
                # 当前通道
                out_ch = base_channel + local_ch
                # 当前通道当前行的 kernel_w 个权重值
                row_weights = [to_u8(value) for value in weights[out_ch][ky]]
                # 添加当前通道的大整数表示
                channel_words.append(pack_values(row_weights, 8))

            # 一个 word 依次打包 4 个输出通道、每个通道 kernel_w 个 int8 权重。
            word = 0
            for idx, channel_word in enumerate(channel_words):
                word |= channel_word << (kernel_w * 8 * idx)
            weight_bank_words[ky][group] = word

    # 写入每个 Bank 的 .mem 文件
    for bank_idx, rows in enumerate(weight_bank_words):
        bank_path = PREP_DIR / f"{layer_name}_weights" / f"weight_bank_{bank_idx:02d}.mem"
        write_lines(bank_path, (f"{row:0{kernel_w * 8}x}" for row in rows))

    # 写入一个整体大 bank
    weight_words_lines: List[str] = []
    for bank_idx in range(kernel_h):
        for group in range(GROUP_COUNT):
            weight_words_lines.append(f"{weight_bank_words[bank_idx][group]:0{kernel_w * 8}x}")
    write_lines(PREP_DIR / f"{layer_name}_weights" / "weight_words.mem", weight_words_lines)

    return {
        "bank_count": kernel_h,
        "depth_per_bank": GROUP_COUNT,
        "combined_word_count": len(weight_words_lines),
    }


# 单独处理 PWConv 层的权重参数
def process_pwconv_weights(weight_path: Path) -> dict:
    """解析 PWConv 权重文件。"""
    pwconv_word_hex_width = 32  # 128-bit word => 32 hex chars
    # 所有卷积核
    kernels: List[List[int]] = []
    # 当前卷积核
    current_kernel: List[int] = []
    with weight_path.open("r", encoding="utf-8") as fh:
        for index, raw_line in enumerate(fh):
            line = raw_line.strip()
            if line:
                current_kernel = [int(value) for value in line.split()]
            if len(current_kernel) != 32:
                raise ValueError(f"line {index} should have 32 values, but now {len(current_kernel)}")
            kernels.append(current_kernel)
    if len(kernels) != 32:
        raise ValueError(f"{weight_path} should have 32 kernels")

    pwconv_weight_mem = [[0 for _ in range(8)] for _ in range(8)]
    # 每一行地址 4 个卷积核, 对应 4 个输出通道
    for out_group in range(GROUP_COUNT):
        # 每一个卷积核被划分为 8 组，每组 4 个通道，对应输入的某四个通道
        for in_group in range(8):
            # 提取出第 out_group 个输出通道组的4个卷积核各自的第 in_group 部分的 4 个 INT8
            bank_kernel_0 = kernels[out_group * 4 + 0][in_group * 4 : in_group * 4 + 4]
            bank_kernel_1 = kernels[out_group * 4 + 1][in_group * 4 : in_group * 4 + 4]
            bank_kernel_2 = kernels[out_group * 4 + 2][in_group * 4 : in_group * 4 + 4]
            bank_kernel_3 = kernels[out_group * 4 + 3][in_group * 4 : in_group * 4 + 4]

            # 转换为大整数形式
            bank_kernel_0_row = pack_values([to_u8(value) for value in bank_kernel_0], 8)
            bank_kernel_1_row = pack_values([to_u8(value) for value in bank_kernel_1], 8)
            bank_kernel_2_row = pack_values([to_u8(value) for value in bank_kernel_2], 8)
            bank_kernel_3_row = pack_values([to_u8(value) for value in bank_kernel_3], 8)

            word = 0

            # 拼接出一个完整的字
            word |= bank_kernel_0_row << 0
            word |= bank_kernel_1_row << 32
            word |= bank_kernel_2_row << 64
            word |= bank_kernel_3_row << 96

            pwconv_weight_mem[in_group][out_group] = word

    # 写入各个 bank 的 .mem 文件
    for bank_idx in range(8):
        bank_path = PREP_DIR / "pwconv_weights" / f"weight_bank_{bank_idx:02d}.mem"
        write_lines(bank_path, (f"{row:0{pwconv_word_hex_width}x}" for row in pwconv_weight_mem[bank_idx]))

    # 写入一个整体大 bank
    weight_words_lines: List[str] = []
    for bank_idx in range(8):
        for out_group in range(GROUP_COUNT):
            weight_words_lines.append(f"{pwconv_weight_mem[bank_idx][out_group]:0{pwconv_word_hex_width}x}")
    write_lines(PREP_DIR / "pwconv_weights" / "weight_words.mem", weight_words_lines)

    return {
        "bank_count": 8,
        "depth_per_bank": GROUP_COUNT,
        "combined_word_count": len(weight_words_lines),
    }


# 单独处理 FC 的权重参数
def generate_fc_weights(weight_path: Path) -> dict:
    """解析 FC 权重文件，生成对应的 .mem 文件。"""
    fc_word_hex_width = 16  # 每个 word 包含 8 个 INT8 权重，共 64bit = 16 个 hex char

    fc_weights = []
    current_weights = []
    with weight_path.open("r", encoding="utf-8") as fh:
        for index, raw_line in enumerate(fh):
            line = raw_line.strip()
            if line:
                current_weights = [int(value) for value in line.split()]
            if len(current_weights) != 288:
                raise ValueError(f"line {index} should have 288 values, but now {len(current_weights)}")
            fc_weights.append(current_weights)
    if len(fc_weights) != 2:
        raise ValueError(f"{weight_path} should have 2 rows of weights")

    weight_words_lines = []
    for weight_addr in range(72):
        pos = weight_addr // 8
        group = weight_addr % 8

        # FC RTL 中 flatten 索引定义为 idx = ch * 9 + pos
        # 其中 ch = group * 4 + lane，lane=0..3
        ch0_idx = (group * 4 + 0) * 9 + pos
        ch1_idx = (group * 4 + 1) * 9 + pos
        ch2_idx = (group * 4 + 2) * 9 + pos
        ch3_idx = (group * 4 + 3) * 9 + pos

        w1_ch0 = fc_weights[0][ch0_idx]
        w1_ch1 = fc_weights[0][ch1_idx]
        w1_ch2 = fc_weights[0][ch2_idx]
        w1_ch3 = fc_weights[0][ch3_idx]
        w2_ch0 = fc_weights[1][ch0_idx]
        w2_ch1 = fc_weights[1][ch1_idx]
        w2_ch2 = fc_weights[1][ch2_idx]
        w2_ch3 = fc_weights[1][ch3_idx]

        # 低 32bit 放 class0 的 4 路权重，高 32bit 放 class1 的 4 路权重
        bank_row = [w1_ch0, w1_ch1, w1_ch2, w1_ch3, w2_ch0, w2_ch1, w2_ch2, w2_ch3]

        word = pack_values((to_u8(value) for value in bank_row), 8)
        weight_words_lines.append(f"{word:0{fc_word_hex_width}x}")

    write_lines(PREP_DIR / "fc_weights" / "weight_words.mem", weight_words_lines)

    return {
        "bank_count": 1,
        "depth_per_bank": 72,
        "combined_word_count": len(weight_words_lines),
    }


def generate_bias_files(bias: List[int], layer_name: str) -> dict:
    """生成 Conv/DWConv/PWConv/FC bias bank 文件。"""
    # 处理全连接层偏置
    if layer_name == "fc":
        if len(bias) != 2:
            raise ValueError(f"FC bias should have 2 values, but got {len(bias)}")
        values = [to_u16(value) for value in bias]
        word = pack_values(values, 16)
        write_lines(PREP_DIR / "fc_bias" / "bias_words.mem", [f"{word:08x}"])
        return {
            "bank_count": 1,
            "depth_per_bank": 1,
            "combined_word_count": 1,
        }

    # 处理 Conv/DWConv/PWConv 层偏置
    bias_bank_words: List[int] = [0 for _ in range(GROUP_COUNT)]
    # bias mem 只有一个 bank
    # 逐 group 填充数据
    for group in range(GROUP_COUNT):
        # group channel 基地址
        base_channel = group * CHANNELS_PER_GROUP
        # 获取当前 group 的 4 个 bias 值
        values = [to_u16(bias[base_channel + local_ch]) for local_ch in range(CHANNELS_PER_GROUP)]
        # 转换为 uint16 后打包成一个 64bit 的 bank word
        bias_bank_words[group] = pack_values(values, 16)

    write_lines(PREP_DIR / f"{layer_name}_bias" / "bias_bank_0.mem", (f"{row:016x}" for row in bias_bank_words))
    write_lines(PREP_DIR / f"{layer_name}_bias" / "bias_words.mem", (f"{row:016x}" for row in bias_bank_words))

    return {
        "bank_count": BIAS_BANK_COUNT,
        "depth_per_bank": GROUP_COUNT,
        "combined_word_count": len(bias_bank_words),
    }


def generate_input_rows_file(sample_rows: List[List[int]], filename: str = "sample_input_rows.mem") -> str:
    """生成 testbench 加载的输入行文件。"""
    row_lines = []
    # 逐行填充数据
    for row in sample_rows:
        # 每行 10 个 INT8 打包为一个 80bit 大整数
        row_value = pack_values((to_u8(value) for value in row), 8)
        row_lines.append(f"{row_value:020x}")
    write_lines(PREP_DIR / "samples" / filename, row_lines)
    return filename


def generate_sigmoid_golden_file(sigmoid_values: List[float], filename: str) -> str:
    """把最终 sigmoid 浮点黄金结果写成可复用文本文件。"""
    write_lines(PREP_DIR / "samples" / filename, [" ".join(f"{value:.9f}" for value in sigmoid_values)])
    return filename


def relu(value: int) -> int:
    """Test/Out_Conv.txt 还未过 ReLU，这里补上与硬件一致的 ReLU。"""
    if value <= 0:
        return 0
    if value > 127:
        return 127
    return value


def generate_tile_file(output: List[List[List[int]]], tile_h: int, tile_w: int, layer_name: str) -> str:
    """根据 Test/Out_Conv.txt / Test/Out_DWConv.txt 生成 sample 的 golden tile 文件。"""
    lines = []
    # 先按 pos 索引
    for pos in range(POS_COUNT):
        # 再按 group 索引
        for group in range(GROUP_COUNT):
            tile_value = 0
            # group 基地址
            base_channel = group * CHANNELS_PER_GROUP
            for local_ch in range(CHANNELS_PER_GROUP):
                # 当前通道的地址
                out_ch = base_channel + local_ch
                for oy in range(tile_h):
                    for ox in range(tile_w):
                        # 当前 tile 由 4 个输出通道、每通道 tile_h x tile_w 的窗口组成。
                        # 无论是 Conv 还是 DWConv, 这里 pos 都是 x 2
                        out_row = pos * 2 + oy
                        out_col = ox
                        value = output[out_ch][out_row][out_col]
                        relu_value = relu(value)
                        out_idx = local_ch * tile_h * tile_w + oy * tile_w + ox
                        tile_value |= to_u8(relu_value) << (8 * out_idx)
            lines.append(f"{pos} {group} {tile_value:0{4 * tile_h * tile_w * 2}x}")
    filename = f"sample_{layer_name}_tiles.mem"
    write_lines(PREP_DIR / "samples" / filename, lines)
    return filename


# 单独处理池化层输出（用展平层输出表示）
def generate_flatten_file(output_path: Path, layer_name: str) -> str:
    """解析 FC 权重文件，生成对应的 .mem 文件。"""
    word_hex_width = 8  # 每个 token 包含 4 个 INT8，合计 32bit = 8 个 hex char

    with output_path.open("r", encoding="utf-8") as fh:
        for index, raw_line in enumerate(fh):
            line = raw_line.strip()
            outputs = [int(value) for value in line.split()]
            if len(outputs) != 288:
                raise ValueError(f"line {index} should have 288 values, but now {len(outputs)}")

    lines = []
    for tile_addr in range(72):
        pos = tile_addr // 8
        group = tile_addr % 8

        # Maxpool/Flatten 结果同样按 idx = ch * 9 + pos 排列
        res_ch0 = outputs[(group * 4 + 0) * 9 + pos]
        res_ch1 = outputs[(group * 4 + 1) * 9 + pos]
        res_ch2 = outputs[(group * 4 + 2) * 9 + pos]
        res_ch3 = outputs[(group * 4 + 3) * 9 + pos]

        # Maxpool RTL 输出顺序为低位到高位依次是 ch0, ch1, ch2, ch3
        bank_row = [res_ch0, res_ch1, res_ch2, res_ch3]

        word = pack_values((to_u8(value) for value in bank_row), 8)
        lines.append(f"{pos} {group} {word:0{word_hex_width}x}")

    filename = f"sample_{layer_name}_tiles.mem"
    write_lines(PREP_DIR / "samples" / filename, lines)
    return filename


def generate_fc_output_file(output_path: Path) -> str:
    """根据 Test/Out_Linear.txt 生成 FC 阶段黄金输出文件。"""
    outputs = parse_flat_vector(output_path, 2, int)

    # FC RTL 输出格式：低 8bit 为 class0，高 8bit 为 class1
    packed_word = pack_values((to_u8(value) for value in outputs), 8)

    filename = "sample_fc_outputs.mem"
    write_lines(PREP_DIR / "samples" / filename, [f"{packed_word:04x}"])
    return filename


# 这里是在根据 FC 输出的 INT8 结果结合 Linear_Out_Scale 计算 Sigmoid 激活值，并生成对应的 LUT 文件
def generate_sigmoid_lut(scale_path: Path) -> str:
    """根据 Linear_Out_Scale 生成 Sigmoid LUT 初始化文件。"""
    linear_out_scale = parse_named_float(scale_path, "Linear_Out_Scale")
    lut_lines: List[str] = []

    for raw_value in range(256):
        # LUT 地址直接使用 FC 输出的 8bit 二进制补码
        # 注意，这里实在把补码转换为真实的 signed int8 值，才能正确计算 Sigmoid 输出
        signed_value = raw_value if raw_value < 128 else raw_value - 256
        real_value = signed_value * linear_out_scale
        sigmoid_value = 1.0 / (1.0 + math.exp(-real_value))
        lut_lines.append(f"{float_to_u32(sigmoid_value):08x}")

    filename = "lut_words.mem"
    write_lines(PREP_DIR / "sigmoid_lut" / filename, lut_lines)
    return filename


def add_box_field(lines: List[str], label: str, value: str, wrap_width: int = 54) -> None:
    """给终端摘要框追加一个自动换行的字段。"""
    prefix = f"{label:<12}: "
    wrapped = textwrap.wrap(value, width=wrap_width) or ["None"]
    lines.append(prefix + wrapped[0])
    lines.extend((" " * len(prefix)) + item for item in wrapped[1:])


def print_summary_box(title: str, fields: List[Tuple[str, str]]) -> None:
    """打印最终通过/失败摘要框。"""
    lines: List[str] = [title, ""]
    for label, value in fields:
        add_box_field(lines, label, value)

    inner_width = max(len(line) for line in lines)
    border = "+" + ("-" * (inner_width + 2)) + "+"
    print(border)
    for line in lines:
        print(f"| {line.ljust(inner_width)} |")
    print(border)
