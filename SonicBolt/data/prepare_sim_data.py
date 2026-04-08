#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prepare_sim_data

面向 `SonicBolt/data/In/` 与 `SonicBolt/data/Out/` 中的多样本数据，
生成连续仿真所需的共享参数文件与按样本编号划分的输入 / golden 文件。

目录布局:
    prepared_sim/
      |- conv_weights/
      |- conv_bias/
      |- dwconv_weights/
      |- dwconv_bias/
      |- pwconv_weights/
      |- pwconv_bias/
      |- fc_weights/
      |- fc_bias/
      |- sigmoid_lut/
      `- samples/
           |- <id>_input_rows.mem
           `- <id>_sigmoid_golden.txt

说明:
    与单样本 `prepare_test_data.py` 共用同一套参数预处理逻辑，
    这里只额外负责样本范围选择、输入样本展开以及最终输出黄金结果整理。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import List


ROOT_DIR = Path(__file__).resolve().parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import prepare_data_common as common


PARAM_DIR = common.PARAM_DIR
PREP_DIR = ROOT_DIR / "prepared_sim"
IN_DIR = ROOT_DIR / "In"
OUT_DIR = ROOT_DIR / "Out"
SCALE_FILE = common.SCALE_FILE


def parse_args() -> argparse.Namespace:
    """解析多样本连续仿真预处理参数。"""
    parser = argparse.ArgumentParser(description="Prepare multi-sample continuous simulation data")
    parser.add_argument("--start-sample", type=int, default=None, help="Start dataset sample id")
    parser.add_argument("--sample-count", type=int, default=None, help="How many samples to prepare")
    return parser.parse_args()


def collect_available_sample_ids() -> List[int]:
    """扫描 data/In 下所有可用的数字样本编号。"""
    sample_ids = sorted(
        int(path.stem)
        for path in IN_DIR.glob("*.txt")
        if path.stem.isdigit()
    )
    if not sample_ids:
        raise FileNotFoundError(f"No numeric sample files found in {IN_DIR}")
    return sample_ids


def resolve_sample_ids(start_sample: int | None, sample_count: int | None) -> List[int]:
    """根据命令行参数解析本次需要处理的样本编号范围。"""
    available_ids = collect_available_sample_ids()

    if start_sample is None:
        selected_ids = available_ids
    else:
        selected_ids = [sample_id for sample_id in available_ids if sample_id >= start_sample]
        if not selected_ids:
            raise ValueError(f"Unable to find samples starting from id {start_sample}")

    if sample_count is not None:
        if sample_count <= 0:
            raise ValueError("--sample-count must be >= 1")
        selected_ids = selected_ids[:sample_count]

    if not selected_ids:
        raise ValueError("No samples selected for simulation preparation")
    return selected_ids


def prepare_shared_parameters() -> dict:
    """生成所有样本共享的参数 / 偏置 / LUT 文件。"""
    # 1. 解析 weight 参数文件
    conv_weights = common.parse_weights(PARAM_DIR / "Param_Conv_Weight.txt", 11, 7)
    dwconv_weights = common.parse_weights(PARAM_DIR / "Param_DWConv_Weight.txt", 3, 3)

    # 2. 解析 bias 参数文件
    conv_bias = common.parse_bias(PARAM_DIR / "Param_Conv_Bias.txt", "conv")
    dwconv_bias = common.parse_bias(PARAM_DIR / "Param_DWConv_Bias.txt", "dwconv")
    pwconv_bias = common.parse_bias(PARAM_DIR / "Param_PWConv_Bias.txt", "pwconv")
    fc_bias = common.parse_bias(PARAM_DIR / "Param_Linear_Bias.txt", "fc")

    # 3. 生成权重 / 偏置 / LUT mem
    return {
        "conv_weights": common.generate_weight_files(conv_weights, 11, 7, "conv"),
        "conv_bias": common.generate_bias_files(conv_bias, "conv"),
        "dwconv_weights": common.generate_weight_files(dwconv_weights, 3, 3, "dwconv"),
        "dwconv_bias": common.generate_bias_files(dwconv_bias, "dwconv"),
        "pwconv_weights": common.process_pwconv_weights(PARAM_DIR / "Param_PWConv_Weight.txt"),
        "pwconv_bias": common.generate_bias_files(pwconv_bias, "pwconv"),
        "fc_weights": common.generate_fc_weights(PARAM_DIR / "Param_Linear_Weight.txt"),
        "fc_bias": common.generate_bias_files(fc_bias, "fc"),
        "sigmoid_lut_file": f"sigmoid_lut/{common.generate_sigmoid_lut(SCALE_FILE)}",
    }


def prepare_sim_samples(start_sample: int | None = None, sample_count: int | None = None) -> List[int]:
    """生成多样本连续仿真所需的全部预处理结果。"""
    common.set_prep_dir(PREP_DIR)
    common.ensure_dirs()

    required_paths = [
        PARAM_DIR / "Param_Conv_Weight.txt",
        PARAM_DIR / "Param_Conv_Bias.txt",
        PARAM_DIR / "Param_DWConv_Weight.txt",
        PARAM_DIR / "Param_DWConv_Bias.txt",
        PARAM_DIR / "Param_PWConv_Weight.txt",
        PARAM_DIR / "Param_PWConv_Bias.txt",
        PARAM_DIR / "Param_Linear_Weight.txt",
        PARAM_DIR / "Param_Linear_Bias.txt",
        SCALE_FILE,
        IN_DIR,
        OUT_DIR,
    ]
    missing = [str(path) for path in required_paths if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing reference data files: {missing}")

    sample_ids = resolve_sample_ids(start_sample, sample_count)
    shared_info = prepare_shared_parameters()

    sample_manifest = []
    for sample_id in sample_ids:
        input_path = IN_DIR / f"{sample_id}.txt"
        output_path = OUT_DIR / f"{sample_id}.txt"
        if not input_path.exists() or not output_path.exists():
            raise FileNotFoundError(f"Missing input/output pair for sample {sample_id}")

        sample_rows = common.parse_input_sample(input_path)
        sigmoid_values = common.parse_sigmoid_output(output_path)

        input_filename = common.generate_input_rows_file(sample_rows, f"{sample_id}_input_rows.mem")
        sigmoid_filename = common.generate_sigmoid_golden_file(sigmoid_values, f"{sample_id}_sigmoid_golden.txt")

        sample_manifest.append(
            {
                "sample_id": sample_id,
                "input_rows_file": f"samples/{input_filename}",
                "sigmoid_golden_file": f"samples/{sigmoid_filename}",
            }
        )

    manifest = {
        "input_shape": [1, common.INPUT_ROWS, common.INPUT_COLS],
        "token_count_per_sample": common.POS_COUNT * common.GROUP_COUNT,
        "sample_ids": sample_ids,
        "sample_count": len(sample_ids),
        "shared_files": {
            "conv_weights": "conv_weights/weight_words.mem",
            "conv_bias": "conv_bias/bias_words.mem",
            "dwconv_weights": "dwconv_weights/weight_words.mem",
            "dwconv_bias": "dwconv_bias/bias_words.mem",
            "pwconv_weights": "pwconv_weights/weight_words.mem",
            "pwconv_bias": "pwconv_bias/bias_words.mem",
            "fc_weights": "fc_weights/weight_words.mem",
            "fc_bias": "fc_bias/bias_words.mem",
            "sigmoid_lut": shared_info["sigmoid_lut_file"],
        },
        "sample_file_pattern": {
            "input_rows": "samples/<id>_input_rows.mem",
            "sigmoid_golden": "samples/<id>_sigmoid_golden.txt",
        },
        "samples": sample_manifest,
        "stats": {
            "conv_weights": shared_info["conv_weights"],
            "conv_bias": shared_info["conv_bias"],
            "dwconv_weights": shared_info["dwconv_weights"],
            "dwconv_bias": shared_info["dwconv_bias"],
            "pwconv_weights": shared_info["pwconv_weights"],
            "pwconv_bias": shared_info["pwconv_bias"],
            "fc_weights": shared_info["fc_weights"],
            "fc_bias": shared_info["fc_bias"],
        },
    }
    common.write_text_if_changed(
        PREP_DIR / "manifest.json",
        json.dumps(manifest, ensure_ascii=False, indent=2),
    )

    common.print_summary_box(
        "^_^ Simulation data is prepared successfully!",
        [
            ("Start sample", str(sample_ids[0])),
            ("Sample count", str(len(sample_ids))),
            ("Output directory", str(PREP_DIR.resolve())),
        ],
    )
    return sample_ids


def main() -> None:
    """脚本入口。"""
    args = parse_args()
    prepare_sim_samples(args.start_sample, args.sample_count)


if __name__ == "__main__":
    main()
