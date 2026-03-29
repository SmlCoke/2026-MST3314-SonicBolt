#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prepare_conv_test_data

将 `SonicBolt/data/Test/` 下提供的测试数据整理成
当前 testbench(包括conv以及conv_dwconv) 可直接加载的 `.mem` 文件。

- 固定生成 1 组样本，名字为 `sample`
- 权重、偏置、输入行数据和 golden tile 都直接围绕这一组测试数据生成
"""

from __future__ import annotations

import argparse
import json
import textwrap
from pathlib import Path
from typing import Iterable, List, Tuple


ROOT_DIR = Path(__file__).resolve().parent
PARAM_DIR = ROOT_DIR / "Param"
TEST_DIR = ROOT_DIR / "Test"
PREP_DIR = ROOT_DIR / "prepared_test"

# 当前 CNN / testbench 使用到的固定几何参数。
INPUT_ROWS = 30
INPUT_COLS = 10
POS_COUNT = 9
GROUP_COUNT = 8
CHANNELS_PER_GROUP = 4
BIAS_BANK_COUNT = 1


def parse_args() -> argparse.Namespace:
    """保留 argparse 入口，当前无额外命令行参数。"""
    parser = argparse.ArgumentParser(
        description="Prepare Conv testbench data from the single sample in SonicBolt/data/Test"
    )
    return parser.parse_args()

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
    # 每个 value 都 width 位宽整数，按照小索引位于低位构筑
    for value in values:
        # (1 << width) - 1 是一个 width 位全 1 的掩码，value & 掩码 可以确保只保留 value 的低 width 位
        # 每个 value 都被放置在 packed 中对应的位置，shift 变量记录当前应该放置的位数偏移
        packed |= (value & ((1 << width) - 1)) << shift
        shift += width
    return packed


def parse_input_sample(path: Path) -> List[List[int]]:
    """
    读取 Test/Input.txt，并重排为 30x10 的二维输入矩阵。
    输入数据只有一行，存放了 300 个 int8 输入值，按行优先顺序排列。
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

# 解析 Conv 以及 DWConv 层的权重参数
def parse_weights(weight_path: Path,
                  kernel_h: int,
                  kernel_w: int) -> List[List[List[int]]]:
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

# 解析 Conv, DWConv, PWConv 层的偏置参数
def parse_conv_bias(bias_path: Path) -> List[int]:
    """解析 Conv/DWConv bias 文件，返回长度为 32 的 bias 列表。"""
    values: List[int] = []
    with bias_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            values.extend(int(token) for token in line.split())
    if len(values) != 32:
        raise ValueError(f"{bias_path} contains {len(values)} bias values, expected 32")
    return values


def parse_test_layer_output(output_path: Path,
                            output_h: int,
                            output_w: int,) -> List[List[List[int]]]:
    """
    解析 Test/Out_Conv.txt 以及 Test/Out_DWConv.txt，
    返回 conv_out[out_ch][out_row][out_col] / dwconv_out[out_ch][out_row][out_col]
    注意，这里的数据是没有经过 ReLU，但是经过了 SATURATE 的输出
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


def ensure_dirs() -> None:
    """确保 prepared_test 下的输出目录存在。"""
    (PREP_DIR / "conv_weights").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "conv_bias").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "dwconv_weights").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "dwconv_bias").mkdir(parents=True, exist_ok=True)
    (PREP_DIR / "samples").mkdir(parents=True, exist_ok=True)


def write_text_if_changed(path: Path, content: str) -> None:
    """仅在内容变化时写文件，避免无意义覆写。"""
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


def generate_weight_files(weights: List[List[List[int]]],
                          kernel_h: int,
                          kernel_w: int,
                          layer_name: str) -> dict:
    """生成 Conv/DWConv 权重 bank 文件和线性展开的 weight_words.mem。"""
    # Kernel 行数 个 Bank，每个 Banke depth = GROUP_COUNT, 共存储 4 个通道的权重数据
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

        write_lines(bank_path, (f"{row:0{kernel_w*8}x}" for row in rows))

    # 写入一个整体大 bank
    weight_words_lines: List[str] = []
    for bank_idx in range(kernel_h):
        for group in range(GROUP_COUNT):
            weight_words_lines.append(f"{weight_bank_words[bank_idx][group]:0{kernel_w*8}x}")
    write_lines(PREP_DIR / f"{layer_name}_weights" / "weight_words.mem", weight_words_lines)

    return {
        "bank_count": kernel_h,
        "depth_per_bank": GROUP_COUNT,
        "combined_word_count": len(weight_words_lines),
    }


def generate_bias_files(bias: List[int],
                        layer_name: str) -> dict:
    """生成 Conv/DWConv bias bank 文件。"""
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


def generate_input_rows_file(sample_rows: List[List[int]]) -> str:
    """生成 testbench 加载的单样本输入行文件。"""
    row_lines = []
    # 逐行填充数据
    for row in sample_rows:
        # 每行 10 个 INT8 打包为一个 80bit 大整数 
        row_value = pack_values((to_u8(value) for value in row), 8)
        row_lines.append(f"{row_value:020x}")
    filename = "sample_input_rows.mem"
    write_lines(PREP_DIR / "samples" / filename, row_lines)
    return filename


def relu(value: int) -> int:
    """Test/Out_Conv.txt 还未过 ReLU，这里补上与硬件一致的 ReLU。"""
    if value <= 0:
        return 0
    if value > 127:
        return 127
    return value


def generate_tile_file(output: List[List[List[int]]],
                       tile_h: int,
                       tile_w: int,
                       layer_name: str) -> str:
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
                        # 当前 tile 由 4 个输出通道、每通道 tile_h x output_w 的窗口组成。
                        # 无论是 Conv 还是 DWConv, 这里 pos 都是 x 2
                        out_row = pos * 2 + oy 
                        out_col = ox
                        value = output[out_ch][out_row][out_col]
                        relu_value = relu(value)
                        out_idx = local_ch * tile_h * tile_w + oy * tile_w + ox
                        tile_value |= to_u8(relu_value) << (8 * out_idx)
            lines.append(f"{pos} {group} {tile_value:0{4*tile_h*tile_w*2}x}")
    filename = f"sample_{layer_name}_tiles.mem"
    write_lines(PREP_DIR / "samples" / filename, lines)
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

def prepare_single_sample() -> None:
    """围绕 Test 目录中的唯一一组数据，生成单样本预处理结果。"""
    # 1. 创建预处理结果目录
    ensure_dirs()
    
    # 2. 验证 Test 目录下的输入数据/参数文件是否存在
    test_input_path = TEST_DIR / "Input.txt"
    test_out_conv_path = TEST_DIR / "Out_Conv.txt"
    test_out_dwconv_path = TEST_DIR / "Out_DWConv.txt"
    required_paths = [
        test_input_path,
        test_out_conv_path,
        test_out_dwconv_path,
        PARAM_DIR / "Param_Conv_Weight.txt",
        PARAM_DIR / "Param_Conv_Bias.txt",
    ]
    missing = [str(path) for path in required_paths if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing reference data files: {missing}")

    # 3. 解析 weight 参数文件
    conv_weights = parse_weights(PARAM_DIR / "Param_Conv_Weight.txt", 11, 7)
    dwconv_weights = parse_weights(PARAM_DIR / "Param_DWConv_Weight.txt", 3, 3)  
    
    # 4. 解析 bias 参数文件
    conv_bias = parse_conv_bias(PARAM_DIR / "Param_Conv_Bias.txt")
    dwconv_bias = parse_conv_bias(PARAM_DIR / "Param_DWConv_Bias.txt")
    
    # 5. 解析输入样本
    test_input_rows = parse_input_sample(test_input_path)
    
    # 6. 解析正确输出结果
    test_conv_out   = parse_test_layer_output(test_out_conv_path, 20, 4)
    test_dwconv_out = parse_test_layer_output(test_out_dwconv_path, 18, 2)

    # 7. 生成 weight 预处理文件
    conv_weight_info   = generate_weight_files(conv_weights, 11, 7, "conv")
    dwconv_weight_info = generate_weight_files(dwconv_weights, 3, 3, "dwconv")
    
    # 8. 生成 bias 预处理文件
    conv_bias_info   = generate_bias_files(conv_bias, "conv")
    dwconv_bias_info = generate_bias_files(dwconv_bias, "dwconv")
    
    # 9. 生成输入行文件
    input_filename = generate_input_rows_file(test_input_rows)
    
    # 10. 生成正确输出文件
    conv_out_filename   = generate_tile_file(test_conv_out, 4, 4, "conv")
    dwconv_out_filename = generate_tile_file(test_dwconv_out, 2, 2, "dwconv")

    # 11. 生成 manifest 文件，保留样本信息
    manifest = {
        "input_shape": [1, INPUT_ROWS, INPUT_COLS],
        "output_conv_shape": [CHANNELS_PER_GROUP, 20, 4],
        "output_dwconv_shape": [CHANNELS_PER_GROUP, 18, 2],
        "token_count_per_sample": POS_COUNT * GROUP_COUNT,
        "golden_source": {
            "input_file": "Test/Input.txt",
            "conv_output_file": "Test/Out_Conv.txt",
            "dwconv_output_file": "Test/Out_DWConv.txt",
            "note": "Out_Conv/Out_DWConv is already saturated/truncated but still needs ReLU during tile generation",
        },
        "conv_weights": conv_weight_info,
        "conv_bias": conv_bias_info,
        "dwconv_weights": dwconv_weight_info,
        "dwconv_bias": dwconv_bias_info,
        "input_rows_file": f"samples/{input_filename}",
        "conv_out_file": f"samples/{conv_out_filename}",
        "dwconv_out_file": f"samples/{dwconv_out_filename}",
    }
    write_text_if_changed(
        PREP_DIR / "manifest.json",
        json.dumps(manifest, ensure_ascii=False, indent=2),
    )

    print_summary_box(
        "^_^ Data is prepared successfully!",
        [
            ("Prepared sample index", "0"),
            ("Output directory", "PREP_DIR"),

        ],
    )

def main() -> None:
    """脚本入口。"""
    parse_args()
    prepare_single_sample()


if __name__ == "__main__":
    main()
