#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_cnn_sim_tb.py

用途:
    面向 `data/In` 的多样本连续输入仿真脚本。
    与 `run_cnn_test_tb.py` 不同，本脚本只关注：
      1. 样本编号顺序
      2. 最终 CNN 输出（2 x FP32）

流程:
    1. 调用 `prepare_sim_data.py` 生成 `prepared_sim/`
    2. 编译 `cnn_sim_tb.v`
    3. 运行连续仿真
    4. 解析 `SIM_OUTPUT / SAMPLE_DONE`
    5. 生成逐样本输出 CSV，并可选执行严格 golden 对比
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import run_cnn_tb_common as common


SRC_DIR = common.SRC_DIR
DATA_DIR = common.DATA_DIR
PREP_DIR = DATA_DIR / "prepared_sim"
PREP_SCRIPT = DATA_DIR / "prepare_sim_data.py"
SIM_DIR = common.RESULT_DIR / "sim"
SIGMOID_TOL = common.SIGMOID_TOL

SIM_OUTPUT_RE = re.compile(r"^SIM_OUTPUT sample=(?P<sample>\d+) data=(?P<data>[0-9a-fA-FxXzZ]+)$")
SAMPLE_DONE_RE = re.compile(r"^SAMPLE_DONE sample=(?P<sample>\d+) cycles=(?P<cycles>\d+)$")


def parse_args() -> argparse.Namespace:
    """解析多样本连续仿真命令行参数。"""
    parser = argparse.ArgumentParser(description="Run multi-sample continuous CNN simulation")
    parser.add_argument("--start-sample", type=int, default=0, help="Start sample id in data/In")
    parser.add_argument("--sample-count", type=int, default=5, help="How many samples to simulate")
    parser.add_argument("--wave", action="store_true", help="Enable VCD dump")
    parser.add_argument("--keep-build", action="store_true", help="Keep existing files in results/sim")
    parser.add_argument("--strict-golden", action="store_true", help="Fail when data/Out reference values differ")
    return parser.parse_args()


def preprocess_data(start_sample: int, sample_count: int) -> List[int]:
    """调用多样本预处理脚本，返回实际生成的 sample id 列表。"""
    result = common.run_prepare_function(
        PREP_SCRIPT,
        "prepare_sim_samples",
        SIM_DIR / "prepare_stdout.log",
        SIM_DIR / "prepare_stderr.log",
        start_sample,
        sample_count,
    )
    if not isinstance(result, list):
        raise RuntimeError("prepare_sim_data.py did not return sample id list")
    if len(result) != sample_count:
        raise RuntimeError(f"Prepared sample count mismatch: got {len(result)}, expected {sample_count}")
    return [int(sample_id) for sample_id in result]


def compile_testbench() -> Path:
    """编译 `cnn_sim_tb.v` 并返回 vvp 路径。"""
    return common.compile_testbench("cnn_sim_tb", SRC_DIR / "cnn_sim_tb.v", SIM_DIR)


def parse_sim_output(log_path: Path) -> Dict[str, List[Tuple[int, str]] | List[Tuple[int, int]]]:
    """解析仿真日志中的最终输出和 done 信息。"""
    parsed = {
        "sim_output": [],   # List[(sample_id, data_hex)]
        "sample_done": [],  # List[(sample_id, cycle)]
    }

    with log_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if match := SIM_OUTPUT_RE.match(line):
                parsed["sim_output"].append(
                    (int(match.group("sample")), match.group("data").lower().zfill(16))
                )
            elif match := SAMPLE_DONE_RE.match(line):
                parsed["sample_done"].append(
                    (int(match.group("sample")), int(match.group("cycles")))
                )
    return parsed


def run_testbench(vvp_path: Path, sample_ids: List[int], enable_wave: bool) -> Tuple[Path, dict]:
    """运行多样本 testbench，并返回日志路径与解析结果。"""
    start_sample = sample_ids[0]
    sample_count = len(sample_ids)
    timeout_cycles = sample_count * 6000 + 2000
    wave_file = SIM_DIR / "cnn_sim_tb.vcd"

    stdout_log = common.run_vvp(
        vvp_path,
        SIM_DIR,
        [
            f"+PREP_DIR={PREP_DIR.resolve()}",
            f"+START_SAMPLE={start_sample}",
            f"+SAMPLE_COUNT={sample_count}",
            f"+TIMEOUT_CYCLES={timeout_cycles}",
            f"+WAVE_FILE={wave_file.resolve()}",
            f"+WAVE={1 if enable_wave else 0}",
        ],
    )
    return stdout_log, parse_sim_output(stdout_log)


def validate_sim_output_sequence(
    sim_outputs: List[Tuple[int, str]],
    expected_sample_ids: List[int],
) -> List[str]:
    """检查 SIM_OUTPUT 的数量、顺序和未知值。"""
    mismatches: List[str] = []

    if len(sim_outputs) != len(expected_sample_ids):
        mismatches.append(f"sim_output count got {len(sim_outputs)}, expected {len(expected_sample_ids)}")

    for idx, sample_id in enumerate(expected_sample_ids):
        if idx >= len(sim_outputs):
            mismatches.append(f"sim_output missing sample={sample_id}")
            continue

        sim_sample, sim_word = sim_outputs[idx]
        if sim_sample != sample_id:
            mismatches.append(f"sim_output sample id mismatch index={idx} got={sim_sample} expected={sample_id}")
            continue

        if common.tile_has_unknown(sim_word):
            mismatches.append(f"sim_output unknown sample={sample_id} data={sim_word}")

    return mismatches


def compare_sigmoid_reference(
    sim_outputs: List[Tuple[int, str]],
    expected_sample_ids: List[int],
) -> List[str]:
    """比较仿真输出与 data/Out 参考值，默认仅作为报告信息。"""
    mismatches: List[str] = []
    sim_output_map = {sample_id: data_hex for sample_id, data_hex in sim_outputs}

    for sample_id in expected_sample_ids:
        sim_word = sim_output_map.get(sample_id)
        if not sim_word or common.tile_has_unknown(sim_word):
            continue

        golden_path = PREP_DIR / "samples" / f"{sample_id}_sigmoid_golden.txt"
        golden_values = common.load_sigmoid_golden(golden_path)

        sim_cls0 = common.decode_fp32_word(sim_word[8:16])
        sim_cls1 = common.decode_fp32_word(sim_word[0:8])
        sim_values = [sim_cls0, sim_cls1]

        for class_idx, golden_value in enumerate(golden_values):
            sim_value = sim_values[class_idx]
            if abs(sim_value - golden_value) > SIGMOID_TOL:
                mismatches.append(
                    f"sigmoid reference diff sample={sample_id} class={class_idx}\n"
                    f"  sim   = {sim_value:.9f}\n"
                    f"  ref   = {golden_value:.9f}\n"
                    f"  absdiff={abs(sim_value - golden_value):.9f}"
                )

    return mismatches


def compare_done_sequence(sample_done: List[Tuple[int, int]], expected_sample_ids: List[int]) -> List[str]:
    """比较 SAMPLE_DONE 样本编号顺序。"""
    mismatches: List[str] = []
    if len(sample_done) != len(expected_sample_ids):
        mismatches.append(f"sample_done count got {len(sample_done)}, expected {len(expected_sample_ids)}")

    for idx, sample_id in enumerate(expected_sample_ids):
        if idx >= len(sample_done):
            mismatches.append(f"sample_done missing sample={sample_id}")
            continue
        done_sample, _done_cycle = sample_done[idx]
        if done_sample != sample_id:
            mismatches.append(f"sample_done id mismatch index={idx} got={done_sample} expected={sample_id}")

    return mismatches


def write_sample_compare_csv(
    sim_outputs: List[Tuple[int, str]],
    expected_sample_ids: List[int],
    csv_path: Path,
) -> None:
    """
    导出逐样本对比 CSV：
      - 每个 sample 的两路仿真输出（class0/class1）
      - 对应参考值（data/Out）
      - 每路绝对误差与是否在容差内
    """
    sim_output_map = {sample_id: data_hex for sample_id, data_hex in sim_outputs}

    fieldnames = [
        "sample_id",
        "sim_hex",
        "sim_class0",
        "sim_class1",
        "golden_class0",
        "golden_class1",
        "absdiff_class0",
        "absdiff_class1",
        "class0_match",
        "class1_match",
        "row_status",
    ]

    with csv_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()

        for sample_id in expected_sample_ids:
            golden_path = PREP_DIR / "samples" / f"{sample_id}_sigmoid_golden.txt"
            # 从 Out/ 文件夹下读取参考浮点数输出，可能存在一定误差
            golden_values = common.load_sigmoid_golden(golden_path)
            golden_cls0, golden_cls1 = golden_values[0], golden_values[1]

            sim_word = sim_output_map.get(sample_id, "")
            row = {
                "sample_id": sample_id,
                "sim_hex": sim_word,
                "sim_class0": "",
                "sim_class1": "",
                "golden_class0": f"{golden_cls0:.9f}",
                "golden_class1": f"{golden_cls1:.9f}",
                "absdiff_class0": "",
                "absdiff_class1": "",
                "class0_match": "false",
                "class1_match": "false",
                "row_status": "missing",
            }

            if not sim_word:
                writer.writerow(row)
                continue

            if common.tile_has_unknown(sim_word):
                row["row_status"] = "unknown"
                writer.writerow(row)
                continue
            # 将 FP32 输出解码为浮点数，并计算与标准值的绝对误差以及是否匹配
            sim_cls0 = common.decode_fp32_word(sim_word[8:16])
            sim_cls1 = common.decode_fp32_word(sim_word[0:8])
            absdiff_cls0 = abs(sim_cls0 - golden_cls0)
            absdiff_cls1 = abs(sim_cls1 - golden_cls1)
            cls0_match = absdiff_cls0 <= SIGMOID_TOL
            cls1_match = absdiff_cls1 <= SIGMOID_TOL

            row["sim_class0"] = f"{sim_cls0:.9f}"
            row["sim_class1"] = f"{sim_cls1:.9f}"
            row["absdiff_class0"] = f"{absdiff_cls0:.9f}"
            row["absdiff_class1"] = f"{absdiff_cls1:.9f}"
            row["class0_match"] = "true" if cls0_match else "false"
            row["class1_match"] = "true" if cls1_match else "false"
            row["row_status"] = "ok" if (cls0_match and cls1_match) else "mismatch"
            writer.writerow(row)


def main() -> int:
    """主入口：准备数据、编译、仿真、比对、落盘报告。"""
    args = parse_args()
    if args.sample_count <= 0:
        raise SystemExit("--sample-count must be >= 1")
    if args.start_sample < 0:
        raise SystemExit("--start-sample must be >= 0")

    common.ensure_results_dir(SIM_DIR, args.keep_build)
    sample_ids = preprocess_data(args.start_sample, args.sample_count)
    vvp_path = compile_testbench()
    stdout_log, sim_results = run_testbench(vvp_path, sample_ids, args.wave)

    fatal_mismatches: List[str] = []
    reference_mismatches: List[str] = []
    fatal_mismatches.extend(validate_sim_output_sequence(sim_results["sim_output"], sample_ids))
    fatal_mismatches.extend(compare_done_sequence(sim_results["sample_done"], sample_ids))
    reference_mismatches.extend(compare_sigmoid_reference(sim_results["sim_output"], sample_ids))
    csv_report_path = SIM_DIR / "sample_output_compare.csv"
    write_sample_compare_csv(sim_results["sim_output"], sample_ids, csv_report_path)
    matched = len(fatal_mismatches) == 0 and (not args.strict_golden or len(reference_mismatches) == 0)
    report_items = fatal_mismatches + reference_mismatches

    summary = {
        "start_sample": sample_ids[0],
        "sample_count": len(sample_ids),
        "wave_enabled": args.wave,
        "strict_golden": args.strict_golden,
        "prepared_dir": str(PREP_DIR.resolve()),
        "vvp_path": str(vvp_path.resolve()),
        "log": stdout_log.name,
        "csv_report": csv_report_path.name,
        "stage_counts": {
            "sim_output": len(sim_results["sim_output"]),
            "sample_done": len(sim_results["sample_done"]),
        },
        "matched": matched,
        "mismatch_count": len(fatal_mismatches),
        "reference_mismatch_count": len(reference_mismatches),
    }
    common.write_reports(SIM_DIR, summary, report_items)

    if not matched:
        common.print_summary_box(
            "T_T  CNN sim testbench result: FAILED",
            [
                ("Start sample", str(sample_ids[0])),
                ("Samples", str(len(sample_ids))),
                ("Passed", "0"),
                ("Failed", str(len(sample_ids))),
                ("Strict", "on" if args.strict_golden else "off"),
                ("Ref diffs", str(len(reference_mismatches))),
                ("Report", "mismatch_report.txt"),
                ("CSV", csv_report_path.name),
            ],
        )
        return 1

    common.print_summary_box(
        "^_^  CNN sim testbench result: PASSED",
        [
            ("Start sample", str(sample_ids[0])),
            ("Samples", str(len(sample_ids))),
            ("Passed", str(len(sample_ids))),
            ("Failed", "0"),
            ("Strict", "on" if args.strict_golden else "off"),
            ("Ref diffs", str(len(reference_mismatches))),
            ("Report", "mismatch_report.txt"),
            ("CSV", csv_report_path.name),
        ],
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
