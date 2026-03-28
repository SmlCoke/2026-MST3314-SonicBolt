#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
模块名称: run_conv_tb

功能概述:
    统一调度 Conv 子系统验证流程，按顺序完成：
    1. 调用数据预处理脚本，生成 testbench 可直接加载的 mem 文件
    2. 使用 iverilog 编译当前 conv RTL 和 testbench
    3. 用 vvp 逐样本运行仿真
    4. 解析 testbench 打印出的 TILE 行
    5. 与黄金 tile 文件逐项比对
    6. 输出 summary.json 和 mismatch_report.txt

默认行为:
    - 默认从样本 0 开始
    - 默认运行 5 个样本
    - 默认不开波形
    - 默认每个样本单独运行一次 vvp

执行方式:
    python run_conv_tb.py [--sample-count N] [--start-index M] [--wave] [--keep-build]
输出目录:
    所有日志、编译产物和比对结果统一写入:
        SonicBolt/src/conv/test/results/
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Dict, List, Tuple


# ---------------------------------------------------------------------------
# 目录常量
# ROOT_DIR 回到整个 CNN-Accelerator 仓库根目录
# 后续路径都基于这个根目录拼出来
# ---------------------------------------------------------------------------
ROOT_DIR = Path(__file__).resolve().parents[4]
CONV_DIR = ROOT_DIR / "SonicBolt" / "src" / "conv"
DATA_DIR = ROOT_DIR / "SonicBolt" / "data"
TEST_DIR = CONV_DIR / "test"
PREP_DIR = DATA_DIR / "prepared_conv_test"
RESULTS_DIR = TEST_DIR / "results"

# ---------------------------------------------------------------------------
# 当前架构固定参数
# ---------------------------------------------------------------------------
TOKEN_COUNT = 72     # 每个样本固定输出 72 个 tile = 9 pos x 8 groups
GROUP_COUNT = 8      # group 范围 0..7
TILE_HEX_LEN = 128   # 512bit tile 对应 128 个十六进制字符

# testbench 中每个 tile 的打印格式：
#   TILE sample=<n> pos=<p> group=<g> data=<hex>
TILE_RE = re.compile(
    r"^TILE sample=(?P<sample>\d+) pos=(?P<pos>\d+) group=(?P<group>\d+) data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)
# ^ 和 $ 确保整行完全匹配，避免误匹配其他日志行
# (?P<name>...) 是命名捕获组，方便后续直接通过 groupdict() 获取 pos/group/data 等字段


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(description="运行 Conv 子系统 testbench")
    parser.add_argument("--sample-count", type=int, default=5, help="处理样本数，默认 5")
    parser.add_argument("--start-index", type=int, default=0, help="起始样本编号，默认 0")
    parser.add_argument("--wave", action="store_true", help="打开波形导出")
    parser.add_argument("--keep-build", action="store_true", help="保留已有 results 目录内容")
    return parser.parse_args()


def run_cmd(
    cmd: List[str],
    cwd: Path,
    stdout_path: Path | None = None,
    stderr_path: Path | None = None,
) -> subprocess.CompletedProcess:
    """
    运行一条外部命令。

    说明:
        - 若指定 stdout_path / stderr_path，则把标准输出和标准错误分别落盘
        - 若未指定，则把输出保留在 CompletedProcess 中
    """
    stdout_handle = stdout_path.open("w", encoding="utf-8") if stdout_path else subprocess.PIPE
    stderr_handle = stderr_path.open("w", encoding="utf-8") if stderr_path else subprocess.PIPE
    try:
        result = subprocess.run(
            cmd,
            cwd=str(cwd),
            text=True,
            stdout=stdout_handle,
            stderr=stderr_handle,
            check=False,
        )
    finally:
        if stdout_path:
            stdout_handle.close()
        if stderr_path:
            stderr_handle.close()
    return result


def ensure_results_dir(keep_build: bool) -> None:
    """
    准备 results 目录。

    - 若目录不存在则创建
    - 若 keep_build=False，则清空旧的文件和子目录
    """
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    if not keep_build:
        for path in RESULTS_DIR.iterdir():
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)


def preprocess_data(start_index: int, sample_count: int) -> None:
    """
    调用 data/prepare_conv_test_data.py 数据预处理脚本，生成:
    - 权重 mem (11*bank, depth=8, word_width = 4*7*8, 大编号通道在前，右侧权重在前)
    - 偏置 mem (1*bank, depth=8, word_width = 4*8, 大编号通道在前)
    - 输入行 mem (按 pos/group 索引，每组4*4*4 bit，大编号通道在前，右侧数据在前)
    - 黄金 tile mem (格式完全同输入行 mem)
    """
    cmd = [
        sys.executable,
        str(DATA_DIR / "prepare_conv_test_data.py"),
        "--start-index",
        str(start_index),
        "--sample-count",
        str(sample_count),
    ]
    result = run_cmd(
        cmd,
        cwd=ROOT_DIR,
        stdout_path=RESULTS_DIR / "prepare_stdout.log",
        stderr_path=RESULTS_DIR / "prepare_stderr.log",
    )
    if result.returncode != 0:
        raise RuntimeError("数据预处理失败，请检查 prepare_stderr.log")


def compile_testbench() -> Path:
    """
    编译 conv RTL 和 testbench。

    返回值:
        生成的 vvp 可执行文件路径
    """
    vvp_path = RESULTS_DIR / "conv_subsystem_tb.vvp"
    compile_log = RESULTS_DIR / "compile.log"
    compile_err = RESULTS_DIR / "compile_stderr.log"

    # 显式收集当前 conv 目录下的所有 RTL，再加上 testbench 顶层
    source_files = sorted(str(path) for path in CONV_DIR.glob("*.v"))
    source_files.append(str(TEST_DIR / "conv_subsystem_tb.v"))

    cmd = ["iverilog", "-g2012", "-s", "conv_subsystem_tb", "-o", str(vvp_path), *source_files]
    result = run_cmd(cmd, cwd=ROOT_DIR, stdout_path=compile_log, stderr_path=compile_err)
    if result.returncode != 0:
        raise RuntimeError("iverilog 编译失败，请检查 compile.log / compile_stderr.log")
    return vvp_path


def load_golden_tiles(sample_id: int) -> Dict[Tuple[int, int], str]:
    """
    读取某个样本的黄金 tile 文件。
    黄金 tile 文件行格式：pos, group, tile_hex
    返回:
        key   = (pos, group)
        value = 128 位十六进制字符串
    """
    golden_path = PREP_DIR / "samples" / f"sample_{sample_id:03d}_tiles.mem"
    golden: Dict[Tuple[int, int], str] = {}
    with golden_path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            pos_text, group_text, tile_hex = line.split()
            golden[(int(pos_text), int(group_text))] = tile_hex.lower().zfill(TILE_HEX_LEN)
    return golden


def parse_sim_tiles(log_path: Path) -> Dict[Tuple[int, int], str]:
    """
    从单样本仿真日志中提取 testbench 打印的 TILE 行。
    返回格式："TILE sample=%0d pos=%0d group=%0d data=%0128x"
    返回格式与 load_golden_tiles 一致，便于直接比对。
    """
    parsed: Dict[Tuple[int, int], str] = {}
    with log_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            match = TILE_RE.match(line)
            if not match:
                continue
            pos = int(match.group("pos"))
            group = int(match.group("group"))
            data = match.group("data").lower().zfill(TILE_HEX_LEN)
            parsed[(pos, group)] = data
    return parsed


def tile_has_unknown(tile_hex: str) -> bool:
    """检查 tile 字符串是否仍包含 X/Z 未知态。"""
    lowered = tile_hex.lower()
    return ("x" in lowered) or ("z" in lowered)


def run_single_sample(vvp_path: Path, sample_id: int, enable_wave: bool) -> Tuple[Path, Dict[Tuple[int, int], str]]:
    """
    运行一个样本的仿真。

    返回:
        - 该样本的 stdout 日志路径
        - 从日志中解析得到的 tile 字典
    """
    stdout_log = RESULTS_DIR / f"simulation_sample_{sample_id:03d}.log"
    stderr_log = RESULTS_DIR / f"simulation_sample_{sample_id:03d}_stderr.log"
    wave_file = RESULTS_DIR / (
        "conv_subsystem_tb.vcd" if sample_id == 0 else f"conv_subsystem_tb_sample_{sample_id:03d}.vcd"
    )

    cmd = [
        "vvp",
        str(vvp_path.resolve()),
        # 以下是 testbench 需要的参数，全部通过 +var=value 形式传递
        f"+PREP_DIR={PREP_DIR.resolve()}",   # 预处理数据根目录，例如 prepared_conv_test
        f"+SAMPLE_ID={sample_id}",
        f"+WAVE_FILE={wave_file.resolve()}",
        "+TIMEOUT_CYCLES=4000",
        f"+WAVE={1 if enable_wave else 0}",
    ]

    result = run_cmd(cmd, cwd=TEST_DIR, stdout_path=stdout_log, stderr_path=stderr_log)
    if result.returncode != 0:
        raise RuntimeError(f"样本 {sample_id} 仿真失败，请检查 {stdout_log.name} / {stderr_log.name}")
    # stdout_log 为标准输出日志
    # parse_sim_tiles 会把 TILE 行解析成一个字典，key=(pos, group)，value=tile_hex_str
    return stdout_log, parse_sim_tiles(stdout_log)


def compare_sample(sample_id: int, sim_tiles: Dict[Tuple[int, int], str]) -> List[str]:
    """
    将仿真输出与黄金值逐 token 比较。

    返回:
        mismatch 字符串列表；为空表示该样本匹配成功
    """
    # 解析黄金 tile 文件，得到同样格式的字典，便于直接比对
    golden_tiles = load_golden_tiles(sample_id)

    mismatches: List[str] = []

    if len(sim_tiles) != TOKEN_COUNT:
        mismatches.append(f"sample {sample_id}: tile count got {len(sim_tiles)}, expected {TOKEN_COUNT}")

    for pos in range(9):
        for group in range(GROUP_COUNT):
            key = (pos, group) # 获取 token 唯一标识
            sim_value = sim_tiles.get(key) # 获取仿真值
            golden_value = golden_tiles.get(key) # 获取标准值
            if sim_value is None:
                mismatches.append(f"sample {sample_id}: missing tile pos={pos} group={group}")
            elif golden_value is None:
                mismatches.append(f"sample {sample_id}: golden missing pos={pos} group={group}")
            elif tile_has_unknown(sim_value):
                mismatches.append(
                    f"sample {sample_id}: unknown tile pos={pos} group={group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )
            elif sim_value != golden_value:
                mismatches.append(
                    f"sample {sample_id}: mismatch pos={pos} group={group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )
    return mismatches


def write_reports(summary: dict, mismatches: List[str]) -> None:
    """
    写出本次运行的总结和 mismatch 报告。
    """
    (RESULTS_DIR / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    report_text = "all samples matched\n" if not mismatches else "\n\n".join(mismatches) + "\n"
    (RESULTS_DIR / "mismatch_report.txt").write_text(report_text, encoding="utf-8")


def format_sample_ids(sample_ids: List[int]) -> str:
    """Format sample id list for terminal output."""
    return ", ".join(str(sample_id) for sample_id in sample_ids) if sample_ids else "None"


def add_box_field(lines: List[str], label: str, value: str, wrap_width: int = 54) -> None:
    """Append a wrapped key/value field into the terminal summary box."""
    prefix = f"{label:<12}: "
    wrapped = textwrap.wrap(value, width=wrap_width) or ["None"]
    lines.append(prefix + wrapped[0])
    lines.extend((" " * len(prefix)) + item for item in wrapped[1:])


def print_summary_box(title: str, fields: List[Tuple[str, str]]) -> None:
    """Print a dashed terminal box with aligned summary fields."""
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
    """
    主流程:
        1. 解析参数
        2. 准备 results 目录
        3. 预处理数据
        4. 编译 testbench
        5. 逐样本仿真
        6. 逐样本比对
        7. 输出总结
    """
    args = parse_args()

    # 建立 results 目录，并根据参数决定是否清理旧内容
    ensure_results_dir(args.keep_build)

    # 调用 data/prepare_conv_test_data.py 生成预处理数据
    preprocess_data(args.start_index, args.sample_count)
    
    # 利用 iverilog 工具编译 Source RTL and Testbench，生成 vvp 可执行文件
    vvp_path = compile_testbench()

    all_mismatches: List[str] = []
    sample_summaries = []
    for sample_id in range(args.start_index, args.start_index + args.sample_count):
        # 运行 vvp，得到该样本的仿真日志路径和解析出的 tile 字典(key = (pos, group)，value=tile_hex_str)
        stdout_log, sim_tiles = run_single_sample(vvp_path, sample_id, args.wave)
        # mimatches 是字符串列表，存储每个 token 的对比结果（如果不匹配才存储）
        mismatches = compare_sample(sample_id, sim_tiles)
        all_mismatches.extend(mismatches) # 如果完全匹配，这个列表就是空的
        sample_summaries.append(
            {
                "sample_id": sample_id,
                "tile_count": len(sim_tiles),
                "log": stdout_log.name,
                "matched": len(mismatches) == 0,
            }
        )

    summary = {
        "start_index": args.start_index,
        "sample_count": args.sample_count,
        "wave_enabled": args.wave,
        "prepared_dir": str(PREP_DIR.resolve()),
        "vvp_path": str(vvp_path.resolve()),
        "samples": sample_summaries,
        "mismatch_count": len(all_mismatches),
    }
    write_reports(summary, all_mismatches)

    total_samples = args.sample_count
    passed_sample_ids = [item["sample_id"] for item in sample_summaries if item["matched"]]
    failed_sample_ids = [item["sample_id"] for item in sample_summaries if not item["matched"]]

    if all_mismatches:
        print_summary_box(
            "T_T  Conv testbench result: FAILED",
            [
                ("Total tests", str(total_samples)),
                ("Passed count", str(len(passed_sample_ids))),
                ("Passed IDs", format_sample_ids(passed_sample_ids)),
                ("Failed count", str(len(failed_sample_ids))),
                ("Failed IDs", format_sample_ids(failed_sample_ids)),
                ("Full report", "mismatch_report.txt"),
            ],
        )
        return 1

    print_summary_box(
        "^_^  Conv testbench result: PASSED",
        [
            ("Total tests", str(total_samples)),
            ("Passed count", str(len(passed_sample_ids))),
            ("Passed IDs", format_sample_ids(passed_sample_ids)),
            ("Failed count", str(len(failed_sample_ids))),
            ("Failed IDs", format_sample_ids(failed_sample_ids)),
        ],
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
