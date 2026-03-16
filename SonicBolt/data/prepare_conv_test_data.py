#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
模块名称: prepare_conv_test_data

功能概述:
    将 `SonicBolt/data` 下的原始 Conv1 参数与 `Test` 目录中的参考输入/参考 Conv 输出，
    预处理成当前 `conv_subsystem` testbench 可直接加载的 mem 文件。

生成内容:
    1. prepared_conv_test/weights/weight_bank_00.mem ~ weight_bank_10.mem
    2. prepared_conv_test/weights/weight_words.mem
    3. prepared_conv_test/bias/bias_bank_0.mem
    4. prepared_conv_test/bias/bias_words.mem
    5. prepared_conv_test/samples/sample_xxx_input_rows.mem
    6. prepared_conv_test/samples/sample_xxx_tiles.mem
    7. prepared_conv_test/manifest.json

当前架构约定:
    - 输入图尺寸: 30 x 10
    - 一张图共 9 个 pos
    - 每个 pos 再拆成 8 个 group
    - 每个 group 含 4 个输出通道
    - 每个输出 token 是一个完整的 4ch x 4x4 INT8 tile

当前版本说明:
    - 不再通过 Python 自己做 Conv1 卷积计算来生成黄金 tile
    - 黄金 tile 直接来自 `Test/Out_Conv.txt`
    - `Test/Out_Conv.txt` 是“已经饱和截断、但还没有经过 ReLU”的 Conv1 输出
    - 因此生成 tile 时只需要额外补上 ReLU：负数置 0，非负数保持原值
    - 由于 `Test` 目录只提供 1 组参考输入/输出，本脚本会把这 1 组参考样本
      复制到请求的样本编号范围中，便于沿用现有 testbench 调度流程
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List


# ---------------------------------------------------------------------------
# 数据目录
# ---------------------------------------------------------------------------
ROOT_DIR = Path(__file__).resolve().parent
IN_DIR = ROOT_DIR / "In"
PARAM_DIR = ROOT_DIR / "Param"
TEST_DIR = ROOT_DIR / "Test"
PREP_DIR = ROOT_DIR / "prepared_conv_test"

# ---------------------------------------------------------------------------
# 当前 Conv1 数学与量化参数
# 说明:
#   权重/偏置 mem 的组织方式仍然与当前 RTL 一致
#   这里只是不再用 Python 重新计算 Conv 输出，而是改用 Test/Out_Conv.txt 生成黄金 tile
# ---------------------------------------------------------------------------
M0 = 111
SHIFT_N = 14
INPUT_ROWS = 30
INPUT_COLS = 10
POS_COUNT = 9
GROUP_COUNT = 8
CHANNELS_PER_GROUP = 4
KERNEL_H = 11
KERNEL_W = 7
OUTPUT_H = 4
OUTPUT_W = 4
WEIGHT_BANK_COUNT = 11
BIAS_BANK_COUNT = 1


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(description="预处理 Conv1 testbench 数据")
    parser.add_argument("--start-index", type=int, default=0, help="起始样本编号，默认 0")
    parser.add_argument("--sample-count", type=int, default=5, help="处理样本数，默认 5")
    return parser.parse_args()


def to_u8(value: int) -> int:
    """把 Python 整数截断到 8bit 无符号表示。"""
    return value & 0xFF


def to_u16(value: int) -> int:
    """把 Python 整数截断到 16bit 无符号表示。"""
    return value & 0xFFFF


def pack_values(values: Iterable[int], width: int) -> int:
    """
    将一串定宽整数按“低位在前”的顺序打包成一个大整数。

    例子:
        values = [a, b, c], width = 8
        结果 = a 放在 [7:0], b 放在 [15:8], c 放在 [23:16]
    """
    packed = 0
    shift = 0
    for value in values:
        packed |= (value & ((1 << width) - 1)) << shift
        shift += width
    return packed


def parse_input_sample(path: Path) -> List[List[int]]:
    """
    读取输入样本文件，并整理成 30x10 二维数组。

    输入文件格式兼容两类:
        - `In/*.txt` 这种 30 行 x 10 列格式
        - `Test/Input.txt` 这种把 300 个数写在连续文本中的格式
    """
    flat_values: List[int] = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            flat_values.extend(int(token) for token in line.split())

    if len(flat_values) != INPUT_ROWS * INPUT_COLS:
        raise ValueError(f"{path} 中输入元素总数为 {len(flat_values)}，期望 {INPUT_ROWS * INPUT_COLS}")

    rows = [
        flat_values[row_idx * INPUT_COLS : (row_idx + 1) * INPUT_COLS]
        for row_idx in range(INPUT_ROWS)
    ]
    return rows


def parse_conv_weights(path: Path) -> List[List[List[int]]]:
    """
    解析 Conv1 权重文件。

    返回格式:
        weights[out_ch][ky][kx]
    """
    kernels: List[List[List[int]]] = []
    current_kernel: List[List[int]] = []
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                if current_kernel:
                    kernels.append(current_kernel)
                    current_kernel = []
                continue
            values = [int(token) for token in line.split()]
            if len(values) != KERNEL_W:
                raise ValueError(f"{path} 中存在非 7 列权重行: {line}")
            current_kernel.append(values)
    if current_kernel:
        kernels.append(current_kernel)

    if len(kernels) != 32:
        raise ValueError(f"{path} 共解析出 {len(kernels)} 个卷积核，期望 32 个")
    for kernel in kernels:
        if len(kernel) != KERNEL_H:
            raise ValueError(f"{path} 中存在非 11 行卷积核")
    return kernels


def parse_conv_bias(path: Path) -> List[int]:
    """
    解析 Conv1 偏置文件。

    返回:
        长度为 32 的 bias 列表
    """
    values: List[int] = []
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            values.extend(int(token) for token in line.split())
    if len(values) != 32:
        raise ValueError(f"{path} 中偏置数量为 {len(values)}，期望 32")
    return values


def parse_test_conv_output(path: Path) -> List[List[List[int]]]:
    """
    解析 `Test/Out_Conv.txt`。

    文件语义:
        - 一共 32 个输出通道
        - 每个输出通道是一个 20x4 矩阵
        - 通道之间用空行分隔

    返回格式:
        conv_out[out_ch][out_row][out_col]
    """
    channels: List[List[List[int]]] = []
    current_channel: List[List[int]] = []
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                if current_channel:
                    channels.append(current_channel)
                    current_channel = []
                continue
            values = [int(token) for token in line.split()]
            if len(values) != OUTPUT_W:
                raise ValueError(f"{path} 中存在非 4 列 Conv 输出行: {line}")
            current_channel.append(values)
    if current_channel:
        channels.append(current_channel)

    if len(channels) != 32:
        raise ValueError(f"{path} 共解析出 {len(channels)} 个输出通道，期望 32 个")
    for channel in channels:
        if len(channel) != 20:
            raise ValueError(f"{path} 中存在非 20 行的输出通道矩阵")
    return channels


def ensure_dirs() -> None:
    """确保预处理输出目录存在。"""
    (PREP_DIR / "weights").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "bias").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "samples").mkdir(parents=True, exist_ok=True)


def write_lines(path: Path, lines: Iterable[str]) -> None:
    """把一组字符串按行写到文件。"""
    content = "\n".join(lines) + "\n"
    path.write_text(content, encoding="utf-8")


def generate_weight_files(weights: List[List[List[int]]]) -> dict:
    """
    生成 Conv1 权重 mem 文件。

    当前 bank 组织:
        - 11 个 weight bank，对应 11 个 kernel_row
        - 每个 bank 深度 8，对应 group=0..7
        - 每个 word 宽 224bit = 4ch x 7 x 8bit
    """
    weight_bank_words: List[List[int]] = [[0 for _ in range(GROUP_COUNT)] for _ in range(WEIGHT_BANK_COUNT)]

    for group in range(GROUP_COUNT):
        base_channel = group * CHANNELS_PER_GROUP
        for ky in range(KERNEL_H):
            channel_words = []
            for local_ch in range(CHANNELS_PER_GROUP):
                # 根据起始通道和通道偏移计算真实输出通道编号
                out_ch = base_channel + local_ch
                # 取出该通道、该行的 7 个权重，并打包成一个 56bit channel_word
                row_weights = [to_u8(value) for value in weights[out_ch][ky]]
                channel_words.append(pack_values(row_weights, 8))

            # 一个 224bit word 内依次存放 4 个通道各自的 7 个 8bit 权重
            # 小编号通道在低位，大编号通道在高位
            word = 0
            for idx, channel_word in enumerate(channel_words):
                word |= channel_word << (56 * idx)
            weight_bank_words[ky][group] = word

    for bank_idx, rows in enumerate(weight_bank_words):
        bank_path = PREP_DIR / "weights" / f"weight_bank_{bank_idx:02d}.mem"
        write_lines(bank_path, (f"{row:056x}" for row in rows))

    # 再额外生成一个顺序展开的总文件，便于 testbench 线性读入
    weight_words_lines: List[str] = []
    for bank_idx in range(WEIGHT_BANK_COUNT):
        for group in range(GROUP_COUNT):
            weight_words_lines.append(f"{weight_bank_words[bank_idx][group]:056x}")
    write_lines(PREP_DIR / "weights" / "weight_words.mem", weight_words_lines)

    return {
        "bank_count": WEIGHT_BANK_COUNT,
        "depth_per_bank": GROUP_COUNT,
        "combined_word_count": len(weight_words_lines),
    }


def generate_bias_files(bias: List[int]) -> dict:
    """
    生成 Conv1 偏置 mem 文件。

    当前 bias 组织:
        - 1 个 bias bank
        - 深度 8，对应 group=0..7
        - 每个 word 宽 64bit = 4 x INT16
    """
    bias_bank_words: List[int] = [0 for _ in range(GROUP_COUNT)]

    for group in range(GROUP_COUNT):
        base_channel = group * CHANNELS_PER_GROUP
        values = [to_u16(bias[base_channel + local_ch]) for local_ch in range(CHANNELS_PER_GROUP)]
        bias_bank_words[group] = pack_values(values, 16)

    write_lines(PREP_DIR / "bias" / "bias_bank_0.mem", (f"{row:016x}" for row in bias_bank_words))
    write_lines(PREP_DIR / "bias" / "bias_words.mem", (f"{row:016x}" for row in bias_bank_words))

    return {
        "bank_count": BIAS_BANK_COUNT,
        "depth_per_bank": GROUP_COUNT,
        "combined_word_count": len(bias_bank_words),
    }


def generate_input_rows_file(sample_idx: int, sample_rows: List[List[int]]) -> str:
    """
    生成单样本输入行 mem 文件。

    文件格式:
        - 每行对应输入图的一行
        - 每行 80bit = 10 x INT8
        - 与 testbench 中 `{img_wr_data_hi, img_wr_data_lo}` 对应
    """
    row_lines = []
    for row in sample_rows:
        row_value = pack_values((to_u8(value) for value in row), 8)
        row_lines.append(f"{row_value:020x}")
    filename = f"sample_{sample_idx:03d}_input_rows.mem"
    write_lines(PREP_DIR / "samples" / filename, row_lines)
    return filename


def relu_from_test_conv_value(value: int) -> int:
    """
    把 `Test/Out_Conv.txt` 中的单个值转换成当前 testbench 需要的黄金输出值。

    注意:
        - `Out_Conv.txt` 已经做过饱和截断，因此范围应已落在 int8 内
        - 但它还没有经过 ReLU，因此这里还要补一个 ReLU
    """
    if value <= 0:
        return 0
    if value > 127:
        return 127
    return value


def generate_tile_file(sample_idx: int, conv_out: List[List[List[int]]]) -> str:
    """
    直接根据 `Test/Out_Conv.txt` 生成单样本黄金 tile 文件。

    文件格式:
        每行:
            pos group tile_hex

    行顺序:
        pos=0, group=0..7
        pos=1, group=0..7
        ...
        pos=8, group=0..7
    """
    lines = []
    for pos in range(POS_COUNT):
        for group in range(GROUP_COUNT):
            tile_value = 0
            base_channel = group * CHANNELS_PER_GROUP
            for local_ch in range(CHANNELS_PER_GROUP):
                out_ch = base_channel + local_ch
                for oy in range(OUTPUT_H):
                    for ox in range(OUTPUT_W):
                        out_row = pos * 2 + oy
                        out_col = ox
                        conv_value = conv_out[out_ch][out_row][out_col]
                        relu_value = relu_from_test_conv_value(conv_value)
                        out_idx = local_ch * 16 + oy * 4 + ox
                        tile_value |= to_u8(relu_value) << (8 * out_idx)
            lines.append(f"{pos} {group} {tile_value:0128x}")
    filename = f"sample_{sample_idx:03d}_tiles.mem"
    write_lines(PREP_DIR / "samples" / filename, lines)
    return filename


def main() -> None:
    """
    主流程:
        1. 解析参数
        2. 检查 `Test` 目录中的参考输入 / 参考 Conv 输出是否存在
        3. 读取原始权重 / 偏置
        4. 生成权重与偏置 mem
        5. 把同一组参考输入 / 输出复制到请求的样本编号范围
        6. 输出 manifest.json
    """
    args = parse_args()
    ensure_dirs()

    end_index = args.start_index + args.sample_count

    # 当前黄金模式只依赖 Test 目录中的单组参考输入和参考 Conv 输出
    test_input_path = TEST_DIR / "Input.txt"
    test_out_conv_path = TEST_DIR / "Out_Conv.txt"
    required_paths = [
        test_input_path,
        test_out_conv_path,
        PARAM_DIR / "Param_Conv_Weight.txt",
        PARAM_DIR / "Param_Conv_Bias.txt",
    ]
    missing = [str(path) for path in required_paths if not path.exists()]
    if missing:
        raise FileNotFoundError(f"缺少参考数据文件: {missing}")

    # 形状: weights[out_ch][ky][kx]
    weights = parse_conv_weights(PARAM_DIR / "Param_Conv_Weight.txt")
    # 形状: bias[out_ch]
    bias = parse_conv_bias(PARAM_DIR / "Param_Conv_Bias.txt")

    # 当前参考输入与参考 Conv 输出
    test_input_rows = parse_input_sample(test_input_path)
    test_conv_out = parse_test_conv_output(test_out_conv_path)

    # 生成 11 个权重 bank 文件
    # 每一行中，小编号通道在低位，大编号通道在高位
    weight_info = generate_weight_files(weights)
    # 生成偏置 bank 文件
    bias_info = generate_bias_files(bias)

    prepared_samples = []
    for sample_idx in range(args.start_index, end_index):
        # 当前 Test 目录只提供 1 组参考输入 / 输出，因此这里把同一组参考样本
        # 复制成请求编号范围内的 prepared 样本，便于沿用现有 testbench 流程。
        input_filename = generate_input_rows_file(sample_idx, test_input_rows)
        tile_filename = generate_tile_file(sample_idx, test_conv_out)
        prepared_samples.append(
            {
                "sample_id": sample_idx,
                "input_rows_file": f"samples/{input_filename}",
                "tile_file": f"samples/{tile_filename}",
            }
        )

    manifest = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "m0": M0,
        "shift_n": SHIFT_N,
        "input_shape": [1, INPUT_ROWS, INPUT_COLS],
        "output_tile_shape": [CHANNELS_PER_GROUP, OUTPUT_H, OUTPUT_W],
        "token_count_per_sample": POS_COUNT * GROUP_COUNT,
        "golden_source": {
            "input_file": "Test/Input.txt",
            "conv_output_file": "Test/Out_Conv.txt",
            "note": "Out_Conv 已饱和截断但未经过 ReLU；生成 tile 时额外补 ReLU",
        },
        "weights": weight_info,
        "bias": bias_info,
        "samples": prepared_samples,
    }
    (PREP_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"Prepared samples: {args.start_index}..{end_index - 1}")
    print(f"Output directory: {PREP_DIR}")


if __name__ == "__main__":
    main()
