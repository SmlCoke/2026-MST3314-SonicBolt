"""
test_golden.py
==============
金标准对比验证脚本（Testbench Golden Model）。

功能：
  1. 使用 Test/Input.txt 作为输入，运行完整前向推理
  2. 将每层输出与 Test/ 目录下的金标准文件逐元素对比
  3. 打印每层的：匹配率、最大绝对误差、通过/失败状态

对应 RTL 验证：
  此脚本等价于 Testbench 中的 golden model 对比逻辑。
  在 RTL 仿真中，将硬件输出与此脚本生成的参考输出对比，
  可验证 Verilog 实现的数值正确性。

验证标准：
  - 整数层（Conv / DWConv / PWConv / Flatten / FC）：逐元素完全匹配（误差 = 0）
  - Sigmoid 层（FP32）：绝对误差 < 1e-5（由于 LUT 精度与浮点实现的微小差异）
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from top_module import TopModule
from load_params import (
    load_golden_input,
    load_golden_conv,
    load_golden_dwconv,
    load_golden_pwconv,
    load_golden_flatten,
    load_golden_linear,
    load_golden_sigmoid,
)


# ANSI 颜色码（可选，增强可读性）
GREEN = "\033[92m"
RED   = "\033[91m"
RESET = "\033[0m"
BOLD  = "\033[1m"


def _fmt_pass(ok: bool) -> str:
    if ok:
        return f"{GREEN}{BOLD}[ PASS ]{RESET}"
    else:
        return f"{RED}{BOLD}[ FAIL ]{RESET}"


def compare_int_layers(name, computed, golden_flat, shape):
    """
    对比整数层输出（INT8）。
    computed    : 嵌套 list，形状由 shape 决定
    golden_flat : 嵌套 list（与 computed 形状相同）或一维 list
    shape       : 用于打印的维度信息字符串
    返回：(match_count, total, max_err, passed)
    """
    # 将 computed 和 golden 都展平为一维列表
    def flatten(data):
        if isinstance(data, (list, tuple)):
            result = []
            for x in data:
                result.extend(flatten(x))
            return result
        else:
            return [data]

    computed_flat = flatten(computed)
    golden_1d     = flatten(golden_flat)

    total = len(computed_flat)
    assert len(golden_1d) == total, \
        f"{name}: 元素数量不匹配！computed={total}, golden={len(golden_1d)}"

    max_err    = 0
    match_count = 0
    mismatch_examples = []

    for i in range(total):
        c = int(computed_flat[i])
        g = int(golden_1d[i])
        err = abs(c - g)
        if err > max_err:
            max_err = err
        if err == 0:
            match_count += 1
        elif len(mismatch_examples) < 3:
            mismatch_examples.append((i, c, g, err))

    passed = (match_count == total)
    return match_count, total, max_err, passed, mismatch_examples


def compare_fp32_layer(name, computed, golden, threshold=1e-5):
    """
    对比浮点层输出（FP32）。
    返回：(max_err, passed)
    """
    assert len(computed) == len(golden), \
        f"{name}: 元素数量不匹配！"

    max_err = 0.0
    for c, g in zip(computed, golden):
        err = abs(float(c) - float(g))
        if err > max_err:
            max_err = err

    passed = (max_err < threshold)
    return max_err, passed


def main():
    print()
    print("╔══════════════════════════════════════════════════════╗")
    print("║  PyRTL-CNN  Golden Model 验证（Testbench 金标准对比）║")
    print("╚══════════════════════════════════════════════════════╝")
    print()

    # ── 初始化并加载参数 ──────────────────────────────────────────────────────
    print("正在初始化 TopModule 并加载权重…")
    top = TopModule(verbose=False)
    top.load_all_weights()
    print("权重加载完成。\n")

    # ── 加载金标准输入并运行推理 ──────────────────────────────────────────────
    print("使用金标准输入：Test/Input.txt")
    golden_input = load_golden_input()
    result = top.forward(input_2d=golden_input)
    intermediates = top.get_intermediate_outputs()
    print()

    # ── 加载金标准参考输出 ────────────────────────────────────────────────────
    print("加载金标准参考输出…")
    golden_conv    = load_golden_conv()        # (32, 20, 4)
    golden_dwconv  = load_golden_dwconv()      # (32, 18, 2)
    golden_pwconv  = load_golden_pwconv()      # (32, 18, 2)
    golden_flatten = load_golden_flatten()     # (288,)
    golden_linear  = load_golden_linear()      # (2,)
    golden_sigmoid = load_golden_sigmoid()     # (2,) FP32
    print("金标准参考输出加载完成。\n")

    # ── 逐层对比 ──────────────────────────────────────────────────────────────
    print("=" * 62)
    print(f"{'层名称':<20} {'形状':<16} {'匹配率':<18} {'最大误差':<12} {'状态'}")
    print("=" * 62)

    all_passed = True

    # --- Conv 层 ---
    m, t, e, ok, mmx = compare_int_layers(
        'Conv', intermediates['conv_out'], golden_conv, '(32,20,4)'
    )
    all_passed = all_passed and ok
    print(f"{'Conv+ReLU':<20} {'(32,20,4)':<16} {m}/{t} ({100*m/t:.1f}%)    {e:<12} {_fmt_pass(ok)}")
    if mmx:
        for idx, c, g, err in mmx:
            print(f"  → 不匹配示例 [idx={idx}]: computed={c}, golden={g}, err={err}")

    # --- DWConv 层 ---
    m, t, e, ok, mmx = compare_int_layers(
        'DWConv', intermediates['dwconv_out'], golden_dwconv, '(32,18,2)'
    )
    all_passed = all_passed and ok
    print(f"{'DWConv+ReLU':<20} {'(32,18,2)':<16} {m}/{t} ({100*m/t:.1f}%)     {e:<12} {_fmt_pass(ok)}")
    if mmx:
        for idx, c, g, err in mmx:
            print(f"  → 不匹配示例 [idx={idx}]: computed={c}, golden={g}, err={err}")

    # --- PWConv 层 ---
    m, t, e, ok, mmx = compare_int_layers(
        'PWConv', intermediates['pwconv_out'], golden_pwconv, '(32,18,2)'
    )
    all_passed = all_passed and ok
    print(f"{'PWConv+ReLU':<20} {'(32,18,2)':<16} {m}/{t} ({100*m/t:.1f}%)     {e:<12} {_fmt_pass(ok)}")
    if mmx:
        for idx, c, g, err in mmx:
            print(f"  → 不匹配示例 [idx={idx}]: computed={c}, golden={g}, err={err}")

    # --- Flatten 层 ---
    m, t, e, ok, mmx = compare_int_layers(
        'Flatten', intermediates['flatten_out'], golden_flatten, '(288,)'
    )
    all_passed = all_passed and ok
    print(f"{'Flatten':<20} {'(288,)':<16} {m}/{t} ({100*m/t:.1f}%)   {e:<12} {_fmt_pass(ok)}")
    if mmx:
        for idx, c, g, err in mmx:
            print(f"  → 不匹配示例 [idx={idx}]: computed={c}, golden={g}, err={err}")

    # --- FC 层 ---
    m, t, e, ok, mmx = compare_int_layers(
        'FC', intermediates['fc_out'], golden_linear, '(2,)'
    )
    all_passed = all_passed and ok
    print(f"{'FC':<20} {'(2,)':<16} {m}/{t} ({100*m/t:.1f}%)       {e:<12} {_fmt_pass(ok)}")
    if mmx:
        for idx, c, g, err in mmx:
            print(f"  → 不匹配示例 [idx={idx}]: computed={c}, golden={g}, err={err}")

    # --- Sigmoid 层（FP32 容许误差）---
    max_fp_err, ok = compare_fp32_layer(
        'Sigmoid', result['sigmoid_out'], golden_sigmoid, threshold=1e-5
    )
    all_passed = all_passed and ok
    sigmoid_c = result['sigmoid_out']
    print(f"{'Sigmoid LUT':<20} {'(2,)':<16} FP32 误差   {max_fp_err:<12.2e} {_fmt_pass(ok)}")
    print(f"  computed=[{sigmoid_c[0]:.6f}, {sigmoid_c[1]:.6f}]  "
          f"golden=[{golden_sigmoid[0]:.6f}, {golden_sigmoid[1]:.6f}]")

    # ── 总结 ──────────────────────────────────────────────────────────────────
    print("=" * 62)
    print()
    if all_passed:
        print(f"{GREEN}{BOLD}✓ 全部层验证通过！模型输出与金标准完全一致。{RESET}")
    else:
        print(f"{RED}{BOLD}✗ 存在不匹配层，请检查上方详细信息。{RESET}")
    print()

    # ── MAC 操作数统计 ─────────────────────────────────────────────────────────
    total_mac = result['cycle_count']
    print(f"总 MAC 操作数（串行估算）：{total_mac:,}")
    print()
    print("说明：")
    print("  - 整数层（INT8）误差为 0 时表示定点计算完全正确")
    print("  - Sigmoid 层 FP32 误差阈值为 1e-5（LUT 精度限制）")
    print("  - 此脚本可直接用作 RTL Testbench 的 golden reference 生成工具")
    print()


if __name__ == '__main__':
    main()
