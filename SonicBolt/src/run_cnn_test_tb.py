#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_cnn_tb.py

功能概述:
    一键执行全网络 CNN testbench，完成
    1. 生成 prepared_test 输入数据
    2. 编译 RTL + testbench
    3. 运行仿真
    4. 解析各层输出日志
    5. 与 golden 结果对比并生成报告

当前版本说明:
    - 支持通过 --sample-count 重复输入同一张测试图，用于验证输入双帧缓存
    - 公共的 prepare / 编译 / 仿真 / 报告能力已经抽取到 `run_cnn_tb_common.py`
    - 结果目录统一写到 SonicBolt/results/test
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import List, Tuple

import run_cnn_tb_common as common


SRC_DIR = common.SRC_DIR
DATA_DIR = common.DATA_DIR
TEST_DATA_DIR = DATA_DIR / "Test"
PREP_DIR = DATA_DIR / "prepared_test"
PREP_SCRIPT = DATA_DIR / "prepare_test_data.py"
TEST_DIR = common.RESULT_DIR / "test"

POS_COUNT = 9
GROUP_COUNT = 8
TOKEN_COUNT = POS_COUNT * GROUP_COUNT

CONV_HEX_LEN = 128
DWC_HEX_LEN = 32
PWC_HEX_LEN = 32
MAXPOOL_HEX_LEN = 8
FC_HEX_LEN = 4
SIGMOID_HEX_LEN = 16
SIGMOID_TOL = common.SIGMOID_TOL

StageEntry = Tuple[int, int, str]

# testbench 日志正则：
# 保持与 cnn_test_tb.v 中的 $display 文本一一对应，便于后处理。
CONV_RE = re.compile(
    r"^Conv-Out-Stream: pos=(?P<pos>\d+) group=(?P<group>\d+) data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)
DWC_RE = re.compile(
    r"^DWConv-Out-Stream: pos=(?P<pos>\d+) group=(?P<group>\d+) data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)
PWC_RE = re.compile(
    r"^PWConv-Out-Stream: pos=(?P<pos>\d+) group=(?P<group>\d+) data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)
MAXPOOL_RE = re.compile(
    r"^Maxpool-Out-Stream: pos=(?P<pos>\d+) group=(?P<group>\d+) data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)
FC_RE = re.compile(r"^FC-Out-Stream: data=(?P<data>[0-9a-fA-FxXzZ]+)$")
SIGMOID_RE = re.compile(r"^Sigmoid-Out-Stream: data=(?P<data>[0-9a-fA-FxXzZ]+)$")
SAMPLE_DONE_RE = re.compile(r"^SAMPLE_DONE sample=(?P<sample>\d+) cycles=(?P<cycles>\d+)$")


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(description="Run the full CNN testbench with repeated input frames")
    parser.add_argument("--sample-count", type=int, default=3, help="Repeat the single prepared test sample N times")
    parser.add_argument("--wave", action="store_true", help="Enable VCD dump")
    parser.add_argument("--keep-build", action="store_true", help="Keep existing files in results/")
    return parser.parse_args()


def preprocess_data() -> None:
    """调用预处理脚本，生成 testbench 所需的 mem 文件。"""
    common.run_prepare_function(
        PREP_SCRIPT,
        "prepare_single_sample",
        TEST_DIR / "prepare_stdout.log",
        TEST_DIR / "prepare_stderr.log",
    )


def compile_testbench() -> Path:
    """编译 CNN 全链路 RTL 与 testbench，返回生成的 vvp 路径。"""
    return common.compile_testbench("cnn_test_tb", SRC_DIR / "cnn_test_tb.v", TEST_DIR)


def load_stage_tile_sequence(path: Path, data_hex_len: int) -> List[StageEntry]:
    """读取带 pos/group 元信息的 stage tile golden 文件。"""
    tiles: List[StageEntry] = []
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            pos_text, group_text, tile_hex = line.split()
            tiles.append((int(pos_text), int(group_text), tile_hex.lower().zfill(data_hex_len)))
    tiles.sort(key=lambda item: (item[0], item[1]))
    return tiles


def load_single_word_file(path: Path, data_hex_len: int) -> List[str]:
    """读取单列十六进制黄金文件。"""
    words: List[str] = []
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            words.append(line.lower().zfill(data_hex_len))
    return words


def load_golden_results() -> dict:
    """统一装载各层 golden 结果。"""
    return {
        "conv": load_stage_tile_sequence(PREP_DIR / "samples" / "sample_conv_tiles.mem", CONV_HEX_LEN),
        "dwconv": load_stage_tile_sequence(PREP_DIR / "samples" / "sample_dwconv_tiles.mem", DWC_HEX_LEN),
        "pwc": load_stage_tile_sequence(PREP_DIR / "samples" / "sample_pwconv_tiles.mem", PWC_HEX_LEN),
        "maxpool": load_stage_tile_sequence(PREP_DIR / "samples" / "sample_maxpool_tiles.mem", MAXPOOL_HEX_LEN),
        "fc": load_single_word_file(PREP_DIR / "samples" / "sample_fc_outputs.mem", FC_HEX_LEN),
        "sigmoid": common.load_sigmoid_golden(TEST_DATA_DIR / "Out.txt"),
    }


def parse_sim_output(log_path: Path) -> dict:
    """解析仿真日志，提取各层输出序列与 sample_done 标记。"""
    parsed = {
        "conv": [],
        "dwconv": [],
        "pwc": [],
        "maxpool": [],
        "fc": [],
        "sigmoid": [],
        "sample_done": [],
    }

    with log_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if match := CONV_RE.match(line):
                parsed["conv"].append(
                    (int(match.group("pos")), int(match.group("group")), match.group("data").lower().zfill(CONV_HEX_LEN))
                )
            elif match := DWC_RE.match(line):
                parsed["dwconv"].append(
                    (int(match.group("pos")), int(match.group("group")), match.group("data").lower().zfill(DWC_HEX_LEN))
                )
            elif match := PWC_RE.match(line):
                parsed["pwc"].append(
                    (int(match.group("pos")), int(match.group("group")), match.group("data").lower().zfill(PWC_HEX_LEN))
                )
            elif match := MAXPOOL_RE.match(line):
                parsed["maxpool"].append(
                    (int(match.group("pos")), int(match.group("group")), match.group("data").lower().zfill(MAXPOOL_HEX_LEN))
                )
            elif match := FC_RE.match(line):
                parsed["fc"].append(match.group("data").lower().zfill(FC_HEX_LEN))
            elif match := SIGMOID_RE.match(line):
                parsed["sigmoid"].append(match.group("data").lower().zfill(SIGMOID_HEX_LEN))
            elif match := SAMPLE_DONE_RE.match(line):
                parsed["sample_done"].append((int(match.group("sample")), int(match.group("cycles"))))

    return parsed


def run_testbench(vvp_path: Path, enable_wave: bool, sample_count: int) -> Tuple[Path, dict]:
    """运行仿真并返回日志路径与解析结果。"""
    wave_file = TEST_DIR / "cnn_tb.vcd"
    timeout_cycles = sample_count * 5000 + 1000
    stdout_log = common.run_vvp(
        vvp_path,
        TEST_DIR,
        [
            f"+PREP_DIR={PREP_DIR.resolve()}",
            f"+WAVE_FILE={wave_file.resolve()}",
            f"+TIMEOUT_CYCLES={timeout_cycles}",
            f"+SAMPLE_COUNT={sample_count}",
            f"+WAVE={1 if enable_wave else 0}",
        ],
    )
    return stdout_log, parse_sim_output(stdout_log)


def compare_stage_tiles(
    stage_name: str,
    sim_tiles: List[StageEntry],
    golden_tiles: List[StageEntry],
    sample_count: int,
) -> List[str]:
    """比较 Conv / DWConv / PWConv / Maxpool 的 tile 序列。"""
    mismatches: List[str] = []
    expected_total = len(golden_tiles) * sample_count
    if len(sim_tiles) != expected_total:
        mismatches.append(f"{stage_name} tile count got {len(sim_tiles)}, expected {expected_total}")

    # 定位到每个 sample 内的 token 索引，逐一对比 pos/group 元信息和 tile 数据
    # 可以这样算是建立在每一层的 token 的输出顺序都是固定的
    for sample_idx in range(sample_count):
        for token_idx, golden_entry in enumerate(golden_tiles):
            sim_idx = sample_idx * len(golden_tiles) + token_idx
            if sim_idx >= len(sim_tiles):
                mismatches.append(f"{stage_name} missing tile sample={sample_idx} token={token_idx}")
                continue

            golden_pos, golden_group, golden_value = golden_entry
            sim_pos, sim_group, sim_value = sim_tiles[sim_idx]

            if (sim_pos, sim_group) != (golden_pos, golden_group):
                mismatches.append(
                    f"{stage_name} metadata mismatch sample={sample_idx} token={token_idx}\n"
                    f"  sim   = pos={sim_pos} group={sim_group}\n"
                    f"  golden= pos={golden_pos} group={golden_group}"
                )
            elif common.tile_has_unknown(sim_value):
                mismatches.append(
                    f"{stage_name} out unknown sample={sample_idx} pos={sim_pos} group={sim_group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )
            elif sim_value != golden_value:
                mismatches.append(
                    f"{stage_name} out mismatch sample={sample_idx} pos={sim_pos} group={sim_group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )

    return mismatches


def compare_fc_outputs(sim_words: List[str], golden_words: List[str], sample_count: int) -> List[str]:
    """比较 FC 输出，按 sample_count 重复同一份 golden。"""
    mismatches: List[str] = []
    expected_words = golden_words * sample_count
    if len(sim_words) != len(expected_words):
        mismatches.append(f"fc output count got {len(sim_words)}, expected {len(expected_words)}")

    for idx, golden_word in enumerate(expected_words):
        if idx >= len(sim_words):
            mismatches.append(f"fc missing output sample={idx // len(golden_words)} index={idx % len(golden_words)}")
            continue
        sim_word = sim_words[idx]
        if common.tile_has_unknown(sim_word):
            mismatches.append(
                f"fc out unknown sample={idx // len(golden_words)} index={idx % len(golden_words)}\n"
                f"  sim   = {sim_word}\n"
                f"  golden= {golden_word}"
            )
        elif sim_word != golden_word:
            mismatches.append(
                f"fc out mismatch sample={idx // len(golden_words)} index={idx % len(golden_words)}\n"
                f"  sim   = {sim_word}\n"
                f"  golden= {golden_word}"
            )

    return mismatches


def compare_sigmoid_outputs(sim_words: List[str], golden_values: List[float], sample_count: int) -> List[str]:
    """比较最终 sigmoid 输出，容忍少量浮点误差。"""
    mismatches: List[str] = []
    if len(sim_words) != sample_count:
        mismatches.append(f"sigmoid output count got {len(sim_words)}, expected {sample_count}")

    for sample_idx in range(sample_count):
        if sample_idx >= len(sim_words):
            mismatches.append(f"sigmoid missing output sample={sample_idx}")
            continue

        sim_word = sim_words[sample_idx]
        if common.tile_has_unknown(sim_word):
            mismatches.append(f"sigmoid out unknown sample={sample_idx} word={sim_word}")
            continue

        sim_cls0 = common.decode_fp32_word(sim_word[8:16])
        sim_cls1 = common.decode_fp32_word(sim_word[0:8])
        sim_values = [sim_cls0, sim_cls1]

        for class_idx, golden_value in enumerate(golden_values):
            sim_value = sim_values[class_idx]
            if abs(sim_value - golden_value) > SIGMOID_TOL:
                mismatches.append(
                    f"sigmoid out mismatch sample={sample_idx} class={class_idx}\n"
                    f"  sim   = {sim_value:.9f}\n"
                    f"  golden= {golden_value:.9f}\n"
                    f"  absdiff={abs(sim_value - golden_value):.9f}"
                )

    return mismatches


def compare_results(sim_results: dict, sample_count: int) -> List[str]:
    """汇总全部层级比较结果。"""
    golden_results = load_golden_results()
    mismatches: List[str] = []

    mismatches.extend(compare_stage_tiles("conv", sim_results["conv"], golden_results["conv"], sample_count))
    mismatches.extend(compare_stage_tiles("dwconv", sim_results["dwconv"], golden_results["dwconv"], sample_count))
    mismatches.extend(compare_stage_tiles("pwconv", sim_results["pwc"], golden_results["pwc"], sample_count))
    mismatches.extend(compare_stage_tiles("maxpool", sim_results["maxpool"], golden_results["maxpool"], sample_count))
    mismatches.extend(compare_fc_outputs(sim_results["fc"], golden_results["fc"], sample_count))
    mismatches.extend(compare_sigmoid_outputs(sim_results["sigmoid"], golden_results["sigmoid"], sample_count))

    if len(sim_results["sample_done"]) != sample_count:
        mismatches.append(f"sample_done count got {len(sim_results['sample_done'])}, expected {sample_count}")

    return mismatches


def main() -> int:
    """主入口：准备数据、编译、仿真、比对、落盘报告。"""
    # 1. 解析命令行参数
    args = parse_args()
    if args.sample_count <= 0:
        raise SystemExit("--sample-count must be >= 1")

    # 2. 清理旧结果，然后准备 results 目录
    common.ensure_results_dir(TEST_DIR, args.keep_build)
    # 3. 调用数据预处理脚本，生成参数 mem 文件以及标准输出结果文件
    preprocess_data()
    # 4. 调用 Icarus Verilog 工具编译全部 RTL 与 testbench，生成 vvp 可执行文件
    vvp_path = compile_testbench()
    # 5. 调用 vvp 运行仿真，生成仿真日志
    stdout_log, sim_results = run_testbench(vvp_path, args.wave, args.sample_count)

    # 6. 对比仿真结果与黄金数据，生成 mismatch 列表
    mismatches = compare_results(sim_results, args.sample_count)
    matched = len(mismatches) == 0

    summary = {
        "sample_count": args.sample_count,
        "wave_enabled": args.wave,
        "prepared_dir": str(PREP_DIR.resolve()),
        "vvp_path": str(vvp_path.resolve()),
        "stage_counts": {
            "conv": len(sim_results["conv"]),
            "dwconv": len(sim_results["dwconv"]),
            "pwconv": len(sim_results["pwc"]),
            "maxpool": len(sim_results["maxpool"]),
            "fc": len(sim_results["fc"]),
            "sigmoid": len(sim_results["sigmoid"]),
            "sample_done": len(sim_results["sample_done"]),
        },
        "log": stdout_log.name,
        "matched": matched,
        "mismatch_count": len(mismatches),
    }
    common.write_reports(TEST_DIR, summary, mismatches)

    if mismatches:
        common.print_summary_box(
            "T_T  CNN testbench result: FAILED",
            [
                ("Samples", str(args.sample_count)),
                ("Passed", "0"),
                ("Failed", str(args.sample_count)),
                ("Report", "mismatch_report.txt"),
            ],
        )
        return 1

    common.print_summary_box(
        "^_^  CNN testbench result: PASSED",
        [
            ("Samples", str(args.sample_count)),
            ("Passed", str(args.sample_count)),
            ("Failed", "0"),
            ("Report", "mismatch_report.txt"),
        ],
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
