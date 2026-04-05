#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_cnn_tb

统一调度 CNN testbench 的单样本验证流程：
1. 预处理 `SonicBolt/data/Test/` 中的单组测试数据
2. 编译当前 SonicBolt RTL 与 `cnn_tb`
3. 运行一次全链路仿真
4. 解析 Conv / DWConv / PWConv / Maxpool / FC / Sigmoid 各层输出
5. 与 `SonicBolt/data/Test/` 提供的黄金结果逐层对比
6. 输出 `summary.json` 与 `mismatch_report.txt`
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import struct
import subprocess
import sys
import textwrap
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Dict, List, Tuple

# 设置关键路径全局变量
ROOT_DIR = Path(__file__).resolve().parents[2]
SRC_DIR = ROOT_DIR / "SonicBolt" / "src"
CONV_DIR = SRC_DIR / "conv"
DWCONV_DIR = SRC_DIR / "dwconv"
PWCONV_DIR = SRC_DIR / "pwconv"
POST_PROCESS_DIR = SRC_DIR / "post_process"
UTILS_DIR = SRC_DIR / "utils"
DATA_DIR = ROOT_DIR / "SonicBolt" / "data"
TEST_DATA_DIR = DATA_DIR / "Test"
PREP_DIR = DATA_DIR / "prepared_test"
PREP_SCRIPT = DATA_DIR / "prepare_test_data.py"
RESULT_DIR = ROOT_DIR / "SonicBolt" / "results"
TEST_DIR = RESULT_DIR / "test"

# 当前只保留单样本流程，因此 sample id 固定为 0
POS_COUNT = 9
GROUP_COUNT = 8
TOKEN_COUNT = POS_COUNT * GROUP_COUNT

CONV_HEX_LEN = 128
DWC_HEX_LEN = 32
PWC_HEX_LEN = 32
MAXPOOL_HEX_LEN = 8
FC_HEX_LEN = 4
SIGMOID_HEX_LEN = 16
SIGMOID_TOL = 1e-4

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
FC_RE = re.compile(
    r"^FC-Out-Stream: data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)
SIGMOID_RE = re.compile(
    r"^Sigmoid-Out-Stream: data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(description="Run the full CNN testbench on the single Test sample")
    parser.add_argument("--wave", action="store_true", help="Enable VCD dump")
    parser.add_argument("--keep-build", action="store_true", help="Keep existing files in results/")
    return parser.parse_args()


def run_cmd(
    cmd: List[str],
    cwd: Path,
    stdout_path: Path | None = None,
    stderr_path: Path | None = None,
) -> subprocess.CompletedProcess:
    """执行外部命令，并按需把 stdout/stderr 落盘。"""
    stdout_handle = stdout_path.open("w", encoding="utf-8") if stdout_path else subprocess.PIPE
    stderr_handle = stderr_path.open("w", encoding="utf-8") if stderr_path else subprocess.PIPE
    try:
        result = subprocess.run(
            cmd,
            cwd=str(cwd),
            text=True,
            stdout=stdout_handle,
            stderr=stderr_handle,
            close_fds=True,
            check=False,
        )
    finally:
        if stdout_path:
            stdout_handle.close()
        if stderr_path:
            stderr_handle.close()
    return result


def ensure_results_dir(keep_build: bool) -> None:
    """准备 results 目录；默认清理旧结果。"""
    TEST_DIR.mkdir(parents=True, exist_ok=True)
    if not keep_build:
        for path in TEST_DIR.iterdir():
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)


def preprocess_data() -> None:
    """调用预处理脚本，生成 testbench 所需的 mem 文件。"""
    spec = importlib.util.spec_from_file_location("prepare_test_data", PREP_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {PREP_SCRIPT}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    stdout_path = TEST_DIR / "prepare_stdout.log"
    stderr_path = TEST_DIR / "prepare_stderr.log"
    with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr_handle:
        try:
            with redirect_stdout(stdout_handle), redirect_stderr(stderr_handle):
                module.prepare_single_sample()
        except Exception:
            with redirect_stderr(stderr_handle):
                traceback.print_exc()
            raise RuntimeError("Data preparation failed, check prepare_stderr.log") from None


def compile_testbench() -> Path:
    """编译 CNN 全链路 RTL 与 testbench，返回生成的 vvp 路径。"""
    vvp_path = TEST_DIR / "cnn_tb.vvp"
    compile_log = TEST_DIR / "compile.log"
    compile_err = TEST_DIR / "compile_stderr.log"

    source_files = sorted(str(path) for path in CONV_DIR.glob("*.v"))
    source_files += sorted(str(path) for path in DWCONV_DIR.glob("*.v"))
    source_files += sorted(str(path) for path in PWCONV_DIR.glob("*.v"))
    source_files += sorted(str(path) for path in POST_PROCESS_DIR.glob("*.v"))
    source_files += sorted(str(path) for path in UTILS_DIR.glob("*.v"))
    source_files.append(str(SRC_DIR / "cnn.v"))
    source_files.append(str(SRC_DIR / "cnn_tb.v"))

    cmd = ["iverilog", "-g2012", "-s", "cnn_tb", "-o", str(vvp_path), *source_files]
    result = run_cmd(cmd, cwd=ROOT_DIR, stdout_path=compile_log, stderr_path=compile_err)
    if result.returncode != 0:
        raise RuntimeError(f"iverilog compile failed, check {compile_log} / {compile_err}")
    return vvp_path


def load_stage_tile_file(path: Path, data_hex_len: int) -> Dict[Tuple[int, int], str]:
    """读取按 pos/group 编排的 tile 黄金文件。"""
    tiles: Dict[Tuple[int, int], str] = {}
    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            pos_text, group_text, tile_hex = line.split()
            tiles[(int(pos_text), int(group_text))] = tile_hex.lower().zfill(data_hex_len)
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


def load_sigmoid_golden(path: Path) -> List[float]:
    """读取最终 Sigmoid 的黄金浮点结果。"""
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


def load_golden_results() -> dict:
    """加载各层黄金结果。"""
    return {
        "conv": load_stage_tile_file(PREP_DIR / "samples" / "sample_conv_tiles.mem", CONV_HEX_LEN),
        "dwconv": load_stage_tile_file(PREP_DIR / "samples" / "sample_dwconv_tiles.mem", DWC_HEX_LEN),
        "pwc": load_stage_tile_file(PREP_DIR / "samples" / "sample_pwconv_tiles.mem", PWC_HEX_LEN),
        "maxpool": load_stage_tile_file(PREP_DIR / "samples" / "sample_maxpool_tiles.mem", MAXPOOL_HEX_LEN),
        "fc": load_single_word_file(PREP_DIR / "samples" / "sample_fc_outputs.mem", FC_HEX_LEN),
        "sigmoid": load_sigmoid_golden(TEST_DATA_DIR / "Out.txt"),
    }


def parse_sim_output(log_path: Path) -> dict:
    """从仿真日志中提取各层输出。"""
    parsed = {
        "conv": {},
        "dwconv": {},
        "pwc": {},
        "maxpool": {},
        "fc": [],
        "sigmoid": [],
    }

    with log_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if match := CONV_RE.match(line):
                parsed["conv"][(int(match.group("pos")), int(match.group("group")))] = match.group("data").lower().zfill(CONV_HEX_LEN)
            elif match := DWC_RE.match(line):
                parsed["dwconv"][(int(match.group("pos")), int(match.group("group")))] = match.group("data").lower().zfill(DWC_HEX_LEN)
            elif match := PWC_RE.match(line):
                parsed["pwc"][(int(match.group("pos")), int(match.group("group")))] = match.group("data").lower().zfill(PWC_HEX_LEN)
            elif match := MAXPOOL_RE.match(line):
                parsed["maxpool"][(int(match.group("pos")), int(match.group("group")))] = match.group("data").lower().zfill(MAXPOOL_HEX_LEN)
            elif match := FC_RE.match(line):
                parsed["fc"].append(match.group("data").lower().zfill(FC_HEX_LEN))
            elif match := SIGMOID_RE.match(line):
                parsed["sigmoid"].append(match.group("data").lower().zfill(SIGMOID_HEX_LEN))

    return parsed


def tile_has_unknown(tile_hex: str) -> bool:
    """检查十六进制串中是否包含 x/z。"""
    lowered = tile_hex.lower()
    return ("x" in lowered) or ("z" in lowered)


def decode_fp32_word(word_hex: str) -> float:
    """把 8 个 hex char 解码为一个 IEEE754 FP32 浮点数。"""
    return struct.unpack("<f", struct.pack("<I", int(word_hex, 16)))[0]


def run_single_sample(vvp_path: Path, enable_wave: bool) -> Tuple[Path, dict]:
    """运行单样本仿真，并返回日志路径与解析结果。"""
    stdout_log = TEST_DIR / "simulation.log"
    stderr_log = TEST_DIR / "simulation_stderr.log"
    wave_file = TEST_DIR / "cnn_tb.vcd"

    cmd = [
        "vvp",
        str(vvp_path.resolve()),
        f"+PREP_DIR={PREP_DIR.resolve()}",
        f"+WAVE_FILE={wave_file.resolve()}",
        "+TIMEOUT_CYCLES=4000",
        f"+WAVE={1 if enable_wave else 0}",
    ]

    result = run_cmd(cmd, cwd=TEST_DIR, stdout_path=stdout_log, stderr_path=stderr_log)
    if result.returncode != 0:
        raise RuntimeError(
            f"Simulation failed, check {stdout_log.name} / {stderr_log.name}"
        )
    return stdout_log, parse_sim_output(stdout_log)


def compare_stage_tiles(
    stage_name: str,
    sim_tiles: Dict[Tuple[int, int], str],
    golden_tiles: Dict[Tuple[int, int], str],
) -> List[str]:
    """对比带 pos/group 的中间层输出。"""
    mismatches: List[str] = []
    if len(sim_tiles) != TOKEN_COUNT:
        mismatches.append(
            f"{stage_name} tile count got {len(sim_tiles)}, expected {TOKEN_COUNT}"
        )

    for pos in range(POS_COUNT):
        for group in range(GROUP_COUNT):
            key = (pos, group)
            sim_value = sim_tiles.get(key)
            golden_value = golden_tiles.get(key)
            if sim_value is None:
                mismatches.append(f"{stage_name} missing tile pos={pos} group={group}")
            elif golden_value is None:
                mismatches.append(f"{stage_name} golden missing pos={pos} group={group}")
            elif tile_has_unknown(sim_value):
                mismatches.append(
                    f"{stage_name} out unknown tile pos={pos} group={group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )
            elif sim_value != golden_value:
                mismatches.append(
                    f"{stage_name} out mismatch pos={pos} group={group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )

    return mismatches


def compare_fc_outputs(sim_words: List[str], golden_words: List[str]) -> List[str]:
    """对比 FC 阶段输出。"""
    mismatches: List[str] = []
    if len(sim_words) != len(golden_words):
        mismatches.append(f"fc output count got {len(sim_words)}, expected {len(golden_words)}")

    for idx, golden_word in enumerate(golden_words):
        if idx >= len(sim_words):
            mismatches.append(f"fc missing output index={idx}")
            continue
        sim_word = sim_words[idx]
        # print(f"Comparing FC output index={idx} sim={sim_word} golden={golden_word}")
        if tile_has_unknown(sim_word):
            mismatches.append(
                f"fc out unknown index={idx}\n"
                f"  sim   = {sim_word}\n"
                f"  golden= {golden_word}"
            )
        elif sim_word != golden_word:
            mismatches.append(
                f"fc out mismatch index={idx}\n"
                f"  sim   = {sim_word}\n"
                f"  golden= {golden_word}"
            )

    return mismatches


def compare_sigmoid_outputs(sim_words: List[str], golden_values: List[float]) -> List[str]:
    """对比 Sigmoid 阶段输出。"""
    mismatches: List[str] = []
    if len(sim_words) != 1:
        mismatches.append(f"sigmoid output count got {len(sim_words)}, expected 1")
        return mismatches

    # print(f"Comparing Sigmoid output sim={sim_words[0]} golden={golden_values}")
    # sim_words 中只有一个序列，拼接起来的两个FP32
    sim_word = sim_words[0]
    if tile_has_unknown(sim_word):
        mismatches.append(f"sigmoid out unknown word={sim_word}")
        return mismatches

    # 提取第一个分类结果
    sim_cls0 = decode_fp32_word(sim_word[8:16])
    # 提取第二个分类结果
    sim_cls1 = decode_fp32_word(sim_word[0:8])
    sim_values = [sim_cls0, sim_cls1]

    for idx, golden_value in enumerate(golden_values):
        sim_value = sim_values[idx]
        if abs(sim_value - golden_value) > SIGMOID_TOL:
            mismatches.append(
                f"sigmoid out mismatch class={idx}\n"
                f"  sim   = {sim_value:.9f}\n"
                f"  golden= {golden_value:.9f}\n"
                f"  absdiff={abs(sim_value - golden_value):.9f}"
            )

    return mismatches


def compare_sample(sim_results: dict) -> List[str]:
    """逐层比较仿真结果与黄金数据。"""
    golden_results = load_golden_results()
    mismatches: List[str] = []

    mismatches.extend(compare_stage_tiles("conv", sim_results["conv"], golden_results["conv"]))
    mismatches.extend(compare_stage_tiles("dwconv", sim_results["dwconv"], golden_results["dwconv"]))
    mismatches.extend(compare_stage_tiles("pwconv", sim_results["pwc"], golden_results["pwc"]))
    mismatches.extend(compare_stage_tiles("maxpool", sim_results["maxpool"], golden_results["maxpool"]))
    mismatches.extend(compare_fc_outputs(sim_results["fc"], golden_results["fc"]))
    mismatches.extend(compare_sigmoid_outputs(sim_results["sigmoid"], golden_results["sigmoid"]))

    return mismatches


def write_reports(summary: dict, mismatches: List[str]) -> None:
    """写出 summary.json 和 mismatch_report.txt。"""
    (TEST_DIR / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    report_text = "all outputs matched\n" if not mismatches else "\n\n".join(mismatches) + "\n"
    (TEST_DIR / "mismatch_report.txt").write_text(report_text, encoding="utf-8")


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


def main() -> int:
    """单样本测试主流程。"""
    # 1. 解析命令行参数
    args = parse_args()
    # 2. 清理旧结果，然后准备 results 目录
    ensure_results_dir(args.keep_build)
    # 3. 调用数据预处理脚本，生成参数mem文件以及标准输出结果文件
    preprocess_data()
    # 4. 调用 Icarus Verilog 工具编译全部 RTL 与 testbench，生成 vvp 可执行文件
    vvp_path = compile_testbench()
    # 5. 调用 vvp 运行仿真，生成仿真日志
    stdout_log, sim_results = run_single_sample(vvp_path, args.wave)
    # 6. 对比仿真结果与黄金数据，生成 mismatch 列表
    mismatches = compare_sample(sim_results)
    matched = len(mismatches) == 0

    summary = {
        "sample_count": 1,
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
        },
        "samples": [
            {
                "log": stdout_log.name,
                "matched": matched,
            }
        ],
        "mismatch_count": len(mismatches),
    }
    write_reports(summary, mismatches)

    if mismatches:
        print_summary_box(
            "T_T  CNN testbench result: FAILED",
            [
                ("Total tests", "1"),
                ("Passed count", "0"),
                ("Passed IDs", "None"),
                ("Failed count", "1"),
                ("Full report", "mismatch_report.txt"),
            ],
        )
        return 1

    print_summary_box(
        "^_^  CNN testbench result: PASSED",
        [
            ("Total tests", "1"),
            ("Passed count", "1"),
            ("Failed count", "0"),
            ("Failed IDs", "None"),
        ],
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
