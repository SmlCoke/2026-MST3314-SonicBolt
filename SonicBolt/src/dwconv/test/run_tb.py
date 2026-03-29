#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_conv_tb

统一调度 Conv testbench 的单样本验证流程：
1. 预处理 `SonicBolt/data/Test/` 中的一组测试数据
2. 编译当前 conv + dwconv RTL 与 testbench
3. 运行一次仿真
4. 解析 TILE 输出并与 golden tile 对比
5. 输出 summary.json 和 mismatch_report.txt
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import textwrap
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Dict, List, Tuple

# 设置关键路径全局变量
# ROOT 代表 SonicBolt 仓库根目录
ROOT_DIR = Path(__file__).resolve().parents[4]
CONV_DIR = ROOT_DIR / "SonicBolt" / "src" / "conv"
DWCONV_DIR = ROOT_DIR / "SonicBolt" / "src" / "dwconv"
DATA_DIR = ROOT_DIR / "SonicBolt" / "data"
TEST_DIR = DWCONV_DIR / "test"
PREP_DIR = DATA_DIR / "prepared_test"
RESULTS_DIR = TEST_DIR / "results"
PREP_SCRIPT = DATA_DIR / "prepare_test_data.py"

# 当前只保留单样本流程，因此 sample id 固定为 0。
POS_COUNT = 9
GROUP_COUNT = 8
TOKEN_COUNT = POS_COUNT * GROUP_COUNT
TILE_HEX_LEN = 32 # 4(ch) x 2(row) x 2(col) x 2(hex per byte) = 128
TILE_RE = re.compile(
    r"^TILE pos=(?P<pos>\d+) group=(?P<group>\d+) data=(?P<data>[0-9a-fA-FxXzZ]+)$"
)


def parse_args() -> argparse.Namespace:
    """解析当前仍然保留的命令行参数。"""
    parser = argparse.ArgumentParser(description="Run the Conv subsystem testbench on the single Test sample")
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
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    if not keep_build:
        for path in RESULTS_DIR.iterdir():
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)


def preprocess_data() -> None:
    """加载并调用预处理脚本，生成单样本 mem 文件。"""
    # 将 SonicBolt/data/prepare_conv_test_data.py 作为模块导入
    spec = importlib.util.spec_from_file_location("prepare_test_data", PREP_SCRIPT)

    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {PREP_SCRIPT}")

    # 创建模块对象
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    # 预处理脚本的输出也统一写入 results 目录，方便排查问题。
    stdout_path = RESULTS_DIR / "prepare_stdout.log"
    stderr_path = RESULTS_DIR / "prepare_stderr.log"
    with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr_handle:
        try:
            # 预处理脚本的输出也统一写入 results 目录，方便排查问题。
            with redirect_stdout(stdout_handle), redirect_stderr(stderr_handle):
                # 执行模块中的 prepare_single_sample 函数，生成预处理数据
                module.prepare_single_sample()
        except Exception:
            with redirect_stderr(stderr_handle):
                traceback.print_exc()
            raise RuntimeError("Data preparation failed, check prepare_stderr.log") from None


def compile_testbench() -> Path:
    """编译 conv RTL 和 conv_dwconv_tb，返回生成的 vvp 路径。"""
    vvp_path = RESULTS_DIR / "conv_dwconv_tb.vvp"
    compile_log = RESULTS_DIR / "compile.log"
    compile_err = RESULTS_DIR / "compile_stderr.log"

    # 收集 conv 目录下所有 RTL，再追加 testbench 顶层文件。
    source_files = sorted(str(path) for path in CONV_DIR.glob("*.v"))
    source_files += sorted(str(path) for path in DWCONV_DIR.glob("*.v"))
    source_files.append(str(TEST_DIR / "conv_dwconv_tb.v"))

    # 利用 iverilog 工具，编译所有 RTL 模块以及 Testbench，生成 vvp 可执行文件。
    cmd = ["iverilog", "-g2012", "-s", "conv_dwconv_tb", "-o", str(vvp_path), *source_files]
    # 编译日志分别在 compile.log 和 compile_stderr.log
    result = run_cmd(cmd, cwd=ROOT_DIR, stdout_path=compile_log, stderr_path=compile_err)
    if result.returncode != 0:
        raise RuntimeError(f"iverilog compile failed, check {compile_log} / {compile_err}")
    return vvp_path


def load_golden_tiles() -> Dict[Tuple[int, int], str]:
    """读取单样本的 golden tile 文件。"""
    golden_path = PREP_DIR / "samples" / "sample_dwconv_tiles.mem"
    golden: Dict[Tuple[int, int], str] = {}
    with golden_path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            # line 的形式是：“<pos> <group> <tile_hex>”
            pos_text, group_text, tile_hex = line.split()
            golden[(int(pos_text), int(group_text))] = tile_hex.lower().zfill(TILE_HEX_LEN)
    return golden


def parse_sim_tiles(log_path: Path) -> Dict[Tuple[int, int], str]:
    """从仿真日志中提取 testbench 打印出的 TILE 行。"""
    parsed: Dict[Tuple[int, int], str] = {}
    with log_path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            # 正则匹配解析 TILE 行，提取 pos、group 和 data 字段
            match = TILE_RE.match(line)
            if not match:
                continue
            pos = int(match.group("pos"))
            group = int(match.group("group"))
            # zfill(x) 在字符串左侧填充 0 ，直到长度达到 x位
            # 这样做的原因：在硬件仿真（比如 Verilog 的 $display 打印 %h）时，如果高位是 0，有些仿真器会自动省略前面的前导0。
            data = match.group("data").lower().zfill(TILE_HEX_LEN)
            parsed[(pos, group)] = data
    return parsed


def tile_has_unknown(tile_hex: str) -> bool:
    """检查 tile 中是否含有 x/z。"""
    lowered = tile_hex.lower()
    return ("x" in lowered) or ("z" in lowered)


def run_single_sample(vvp_path: Path, enable_wave: bool) -> Tuple[Path, Dict[Tuple[int, int], str]]:
    """运行唯一的 sample，并返回日志路径和解析后的 tile。"""
    stdout_log = RESULTS_DIR / "simulation.log"
    stderr_log = RESULTS_DIR / "simulation_stderr.log"
    wave_file = RESULTS_DIR / "conv_dwconv_tb.vcd"

    # testbench 仍然通过 plusargs 接收路径和 sample id，但这里 sample id 固定为 0。
    cmd = [
        "vvp",
        str(vvp_path.resolve()),
        f"+PREP_DIR={PREP_DIR.resolve()}",
        f"+WAVE_FILE={wave_file.resolve()}",
        "+TIMEOUT_CYCLES=4000",
        f"+WAVE={1 if enable_wave else 0}",
    ]

    # 利用 vvp 工具运行仿真，日志分别在 simulation.log 和 simulation_stderr.log
    result = run_cmd(cmd, cwd=TEST_DIR, stdout_path=stdout_log, stderr_path=stderr_log)
    if result.returncode != 0:
        raise RuntimeError(
            f"Simulation for sample failed, check {stdout_log.name} / {stderr_log.name}"
        )
    return stdout_log, parse_sim_tiles(stdout_log)


def compare_sample(sim_tiles: Dict[Tuple[int, int], str]) -> List[str]:
    """把仿真输出和 golden tile 逐 token 对比，返回 mismatch 列表。"""
    # 加载正确数据
    golden_tiles = load_golden_tiles()
    # 存储不匹配数据的列表
    mismatches: List[str] = []

    if len(sim_tiles) != TOKEN_COUNT:
        mismatches.append(f"tile count got {len(sim_tiles)}, expected {TOKEN_COUNT}")

    # 72 个 token = 9 个 pos x 8 个 group。
    for pos in range(POS_COUNT):
        for group in range(GROUP_COUNT):
            key = (pos, group)
            sim_value = sim_tiles.get(key)
            golden_value = golden_tiles.get(key)
            if sim_value is None:
                mismatches.append(f"missing tile pos={pos} group={group}")
            elif golden_value is None:
                mismatches.append(f"golden missing pos={pos} group={group}")
            elif tile_has_unknown(sim_value):
                mismatches.append(
                    f"Unknown tile pos={pos} group={group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )
                # Python 特性：隐式字符串字面量拼接，即如果多个字符串面值（包括 f-string）相邻放置，中间只有空格、换行或缩进，Python 解析器会自动将它们合并成一个完整的长字符串。
            elif sim_value != golden_value:
                mismatches.append(
                    f"Mismatch pos={pos} group={group}\n"
                    f"  sim   = {sim_value}\n"
                    f"  golden= {golden_value}"
                )
    return mismatches


def write_reports(summary: dict, mismatches: List[str]) -> None:
    """写出 summary.json 和 mismatch_report.txt。"""
    (RESULTS_DIR / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    report_text = "all samples matched\n" if not mismatches else "\n\n".join(mismatches) + "\n"
    (RESULTS_DIR / "mismatch_report.txt").write_text(report_text, encoding="utf-8")
 

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
    # 1. 加载命令行参数
    args = parse_args()
    # 2. 准备 results 目录
    ensure_results_dir(args.keep_build)
    # 3. 预处理数据，生成 mem 文件（只有一个测试样本）
    preprocess_data()
    # 4. 利用 iverilog 工具编译，得到 vvp 可执行文件
    vvp_path = compile_testbench()
    # 5. 利用 vvp 工具运行仿真，得到标准输出日志以及解析后的输出数据（字典）
    stdout_log, sim_tiles = run_single_sample(vvp_path, args.wave)
    # 如果仿真成功，stdout_log 就是输出数据

    # 6. 对比仿真结果与标准结果，存放到列表 mismatches 中
    mismatches = compare_sample(sim_tiles)
    # 7. 如果仿真结果全部正确，mismatches 列表应该是空的
    matched = len(mismatches) == 0

    # 8. 汇总仿真结果
    summary = {
        "sample_count": 1,
        "wave_enabled": args.wave,
        "prepared_dir": str(PREP_DIR.resolve()),
        "vvp_path": str(vvp_path.resolve()),
        "samples": [
            {
                "tile_count": len(sim_tiles),
                "log": stdout_log.name,
                "matched count": len(sim_tiles) - len(mismatches),
                "matched": matched,
            }
        ],
        "mismatch_count": len(mismatches),
    }
    # 9. 整理报告：仿真结果，不匹配列表
    write_reports(summary, mismatches)

    if mismatches:
        print_summary_box(
            "T_T  Conv testbench result: FAILED",
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
        "^_^  Conv testbench result: PASSED",
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
