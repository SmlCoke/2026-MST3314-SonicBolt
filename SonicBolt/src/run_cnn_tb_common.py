#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_cnn_tb_common

抽取单样本 `run_cnn_test_tb.py` 与多样本 `run_cnn_sim_tb.py`
都能复用的脚本工具函数。

公共内容主要包括:
    1. 路径常量
    2. 外部命令执行
    3. results 目录准备
    4. prepare-script 调用
    5. testbench 编译 / 仿真
    6. FP32 解码与 Sigmoid 容差比较基础能力
    7. 摘要框打印与报告落盘
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import struct
import subprocess
import textwrap
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any, List, Tuple


# 设置关键路径全局变量
ROOT_DIR = Path(__file__).resolve().parents[2]
SRC_DIR = ROOT_DIR / "SonicBolt" / "src"
CONV_DIR = SRC_DIR / "conv"
DWCONV_DIR = SRC_DIR / "dwconv"
PWCONV_DIR = SRC_DIR / "pwconv"
POST_PROCESS_DIR = SRC_DIR / "post_process"
UTILS_DIR = SRC_DIR / "utils"
DATA_DIR = ROOT_DIR / "SonicBolt" / "data"
RESULT_DIR = ROOT_DIR / "SonicBolt" / "results"

SIGMOID_TOL = 1e-4


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


def ensure_results_dir(result_dir: Path, keep_build: bool) -> None:
    """准备 results 目录；默认清理旧结果。"""
    result_dir.mkdir(parents=True, exist_ok=True)
    if not keep_build:
        for path in result_dir.iterdir():
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)


def load_python_module(module_path: Path):
    """按文件路径动态加载 Python 模块。"""
    spec = importlib.util.spec_from_file_location(module_path.stem, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {module_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_prepare_function(
    module_path: Path,
    function_name: str,
    stdout_path: Path,
    stderr_path: Path,
    *args: Any,
    **kwargs: Any,
) -> Any:
    """调用 prepare 脚本中的指定入口函数，并把日志重定向到文件。"""
    module = load_python_module(module_path)
    if not hasattr(module, function_name):
        raise RuntimeError(f"{module_path} does not define {function_name}()")

    function = getattr(module, function_name)
    with stdout_path.open("w", encoding="utf-8") as stdout_handle, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr_handle:
        try:
            with redirect_stdout(stdout_handle), redirect_stderr(stderr_handle):
                return function(*args, **kwargs)
        except Exception:
            with redirect_stderr(stderr_handle):
                traceback.print_exc()
            raise RuntimeError(f"Data preparation failed, check {stderr_path.name}") from None


def compile_testbench(tb_top: str, tb_file: Path, result_dir: Path) -> Path:
    """编译 CNN 全链路 RTL 与指定 testbench，返回生成的 vvp 路径。"""
    vvp_path = result_dir / f"{tb_top}.vvp"
    compile_log = result_dir / "compile.log"
    compile_err = result_dir / "compile_stderr.log"
    filelist_path = result_dir / "compile_filelist.f"

    source_paths = sorted(path.resolve() for path in CONV_DIR.glob("*.v"))
    source_paths += sorted(path.resolve() for path in DWCONV_DIR.glob("*.v"))
    source_paths += sorted(path.resolve() for path in PWCONV_DIR.glob("*.v"))
    source_paths += sorted(path.resolve() for path in POST_PROCESS_DIR.glob("*.v"))
    source_paths += sorted(path.resolve() for path in UTILS_DIR.glob("*.v"))
    source_paths.append((SRC_DIR / "cnn.v").resolve())
    source_paths.append(tb_file.resolve())

    # Use filelist mode to avoid long-argument instability on Windows.
    source_files = [path.as_posix() for path in source_paths]
    filelist_path.write_text("\n".join(source_files) + "\n", encoding="utf-8")
    cmd = ["iverilog", "-g2012", "-f", str(filelist_path), "-s", tb_top, "-o", str(vvp_path)]
    result = run_cmd(cmd, cwd=ROOT_DIR, stdout_path=compile_log, stderr_path=compile_err)
    if result.returncode != 0:
        raise RuntimeError(f"iverilog compile failed, check {compile_log} / {compile_err}")
    return vvp_path


def run_vvp(
    vvp_path: Path,
    result_dir: Path,
    plusargs: List[str],
    stdout_name: str = "simulation.log",
    stderr_name: str = "simulation_stderr.log",
) -> Path:
    """执行 vvp 仿真，并返回标准输出日志路径。"""
    stdout_log = result_dir / stdout_name
    stderr_log = result_dir / stderr_name

    cmd = ["vvp", str(vvp_path.resolve()), *plusargs]
    result = run_cmd(cmd, cwd=result_dir, stdout_path=stdout_log, stderr_path=stderr_log)
    if result.returncode != 0:
        raise RuntimeError(f"Simulation failed, check {stdout_log.name} / {stderr_log.name}")
    return stdout_log


def load_sigmoid_golden(path: Path) -> List[float]:
    """读取最终 sigmoid 浮点 golden 输出。"""
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


def tile_has_unknown(tile_hex: str) -> bool:
    """检查十六进制串中是否包含 x/z。"""
    lowered = tile_hex.lower()
    return ("x" in lowered) or ("z" in lowered)


def decode_fp32_word(word_hex: str) -> float:
    """把 8 个 hex char 解码为一个 IEEE754 FP32 浮点数。"""
    return struct.unpack("<f", struct.pack("<I", int(word_hex, 16)))[0]


def write_reports(result_dir: Path, summary: dict, mismatches: List[str]) -> None:
    """写出 summary.json 和 mismatch_report.txt。"""
    (result_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    report_text = "all outputs matched\n" if not mismatches else "\n\n".join(mismatches) + "\n"
    (result_dir / "mismatch_report.txt").write_text(report_text, encoding="utf-8")


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
