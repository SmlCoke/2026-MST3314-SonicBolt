#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prepare_conv_test_data

将 `SonicBolt/data/Test/` 下提供的测试数据整理成
当前 testbench 可直接加载的 `.mem` 文件。

- 固定生成 1 组样本，名字为 `sample`
- 权重、偏置、输入行数据和 golden tile 都直接围绕这一组测试数据生成

说明:
    为了减少总代码量，通用的解析 / 打包 / `.mem` 生成逻辑已经抽取到
    `prepare_data_common.py`。本脚本仅保留单样本测试链路的组织逻辑。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import prepare_data_common as common


PARAM_DIR = common.PARAM_DIR
TEST_DIR = common.TEST_DIR
PREP_DIR = ROOT_DIR / "prepared_test"
SCALE_FILE = common.SCALE_FILE


def parse_args() -> argparse.Namespace:
    """保留 argparse 入口，当前无额外命令行参数。"""
    parser = argparse.ArgumentParser(
        description="Prepare Conv testbench data from the single sample in SonicBolt/data/Test"
    )
    return parser.parse_args()


def prepare_single_sample() -> None:
    """围绕 Test 目录中的唯一一组数据，生成单样本预处理结果。"""
    common.set_prep_dir(PREP_DIR)

    # 1. 创建预处理结果目录
    common.ensure_dirs()

    # 2. 验证 Test 目录下的输入数据 / 参数文件是否存在
    test_input_path = TEST_DIR / "Input.txt"
    test_out_conv_path = TEST_DIR / "Out_Conv.txt"
    test_out_dwconv_path = TEST_DIR / "Out_DWConv.txt"
    test_out_pwconv_path = TEST_DIR / "Out_PWConv.txt"
    test_out_maxpool_path = TEST_DIR / "Out_Flatten.txt"
    test_out_fc_path = TEST_DIR / "Out_Linear.txt"
    test_out_sigmoid_path = TEST_DIR / "Out.txt"
    required_paths = [
        test_input_path,
        test_out_conv_path,
        test_out_dwconv_path,
        test_out_pwconv_path,
        test_out_maxpool_path,
        test_out_fc_path,
        test_out_sigmoid_path,
        PARAM_DIR / "Param_Conv_Weight.txt",
        PARAM_DIR / "Param_Conv_Bias.txt",
        PARAM_DIR / "Param_DWConv_Weight.txt",
        PARAM_DIR / "Param_DWConv_Bias.txt",
        PARAM_DIR / "Param_PWConv_Weight.txt",
        PARAM_DIR / "Param_PWConv_Bias.txt",
        PARAM_DIR / "Param_Linear_Weight.txt",
        PARAM_DIR / "Param_Linear_Bias.txt",
        SCALE_FILE,
    ]
    missing = [str(path) for path in required_paths if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing reference data files: {missing}")

    # 3. 解析 weight 参数文件
    conv_weights = common.parse_weights(PARAM_DIR / "Param_Conv_Weight.txt", 11, 7)
    dwconv_weights = common.parse_weights(PARAM_DIR / "Param_DWConv_Weight.txt", 3, 3)

    # 4. 解析 bias 参数文件
    conv_bias = common.parse_bias(PARAM_DIR / "Param_Conv_Bias.txt", "conv")
    dwconv_bias = common.parse_bias(PARAM_DIR / "Param_DWConv_Bias.txt", "dwconv")
    pwconv_bias = common.parse_bias(PARAM_DIR / "Param_PWConv_Bias.txt", "pwconv")
    fc_bias = common.parse_bias(PARAM_DIR / "Param_Linear_Bias.txt", "fc")

    # 5. 解析输入样本
    test_input_rows = common.parse_input_sample(test_input_path)

    # 6. 解析正确输出结果
    test_conv_out = common.parse_test_layer_output(test_out_conv_path, 20, 4)
    test_dwconv_out = common.parse_test_layer_output(test_out_dwconv_path, 18, 2)
    test_pwconv_out = common.parse_test_layer_output(test_out_pwconv_path, 18, 2)

    # 7. 生成 weight 预处理文件
    conv_weight_info = common.generate_weight_files(conv_weights, 11, 7, "conv")
    dwconv_weight_info = common.generate_weight_files(dwconv_weights, 3, 3, "dwconv")

    # 单独处理 pwconv 层
    pwconv_weight_info = common.process_pwconv_weights(PARAM_DIR / "Param_PWConv_Weight.txt")
    # 单独处理 fc 层
    fc_weight_info = common.generate_fc_weights(PARAM_DIR / "Param_Linear_Weight.txt")

    # 8. 生成 bias 预处理文件
    conv_bias_info = common.generate_bias_files(conv_bias, "conv")
    dwconv_bias_info = common.generate_bias_files(dwconv_bias, "dwconv")
    pwconv_bias_info = common.generate_bias_files(pwconv_bias, "pwconv")
    fc_bias_info = common.generate_bias_files(fc_bias, "fc")

    # 9. 生成输入行文件
    input_filename = common.generate_input_rows_file(test_input_rows)

    # 10. 生成正确输出文件
    conv_out_filename = common.generate_tile_file(test_conv_out, 4, 4, "conv")
    dwconv_out_filename = common.generate_tile_file(test_dwconv_out, 2, 2, "dwconv")
    pwconv_out_filename = common.generate_tile_file(test_pwconv_out, 2, 2, "pwconv")

    # 单独处理 Maxpool 输出（用展平层输出表示）
    maxpool_out_filename = common.generate_flatten_file(test_out_maxpool_path, "maxpool")
    fc_out_filename = common.generate_fc_output_file(test_out_fc_path)
    sigmoid_lut_filename = common.generate_sigmoid_lut(SCALE_FILE)

    # 11. 生成 manifest 文件，保留样本信息
    manifest = {
        "input_shape": [1, common.INPUT_ROWS, common.INPUT_COLS],
        "output_conv_shape": [common.CHANNELS_PER_GROUP, 20, 4],
        "output_dwconv_shape": [common.CHANNELS_PER_GROUP, 18, 2],
        "token_count_per_sample": common.POS_COUNT * common.GROUP_COUNT,
        "golden_source": {
            "input_file": "Test/Input.txt",
            "conv_output_file": "Test/Out_Conv.txt",
            "dwconv_output_file": "Test/Out_DWConv.txt",
            "pwconv_output_file": "Test/Out_PWConv.txt",
            "maxpool_output_file": "Test/Out_Flatten.txt",
            "fc_output_file": "Test/Out_Linear.txt",
            "sigmoid_output_file": "Test/Out.txt",
            "note": "Out_Conv/Out_DWConv is already saturated/truncated but still needs ReLU during tile generation",
        },
        "conv_weights": conv_weight_info,
        "conv_bias": conv_bias_info,
        "dwconv_weights": dwconv_weight_info,
        "dwconv_bias": dwconv_bias_info,
        "pwconv_weights": pwconv_weight_info,
        "pwconv_bias": pwconv_bias_info,
        "fc_weights": fc_weight_info,
        "fc_bias": fc_bias_info,
        "input_rows_file": f"samples/{input_filename}",
        "conv_out_file": f"samples/{conv_out_filename}",
        "dwconv_out_file": f"samples/{dwconv_out_filename}",
        "pwconv_out_file": f"samples/{pwconv_out_filename}",
        "maxpool_out_file": f"samples/{maxpool_out_filename}",
        "fc_out_file": f"samples/{fc_out_filename}",
        "sigmoid_lut_file": f"sigmoid_lut/{sigmoid_lut_filename}",
    }
    common.write_text_if_changed(
        PREP_DIR / "manifest.json",
        json.dumps(manifest, ensure_ascii=False, indent=2),
    )

    common.print_summary_box(
        "^_^ Data is prepared successfully!",
        [
            ("Prepared sample index", "0"),
            ("Output directory", str(PREP_DIR.resolve())),
        ],
    )


def main() -> None:
    """脚本入口。"""
    parse_args()
    prepare_single_sample()


if __name__ == "__main__":
    main()
