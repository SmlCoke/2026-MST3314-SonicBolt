"""
run_inference.py
================
单样本推理入口脚本。

使用方法：
  cd PyRTL-CNN
  python run_inference.py               # 默认使用金标准输入（Test/Input.txt）
  python run_inference.py --input 0     # 使用 In/0.txt（第 0 号样本）
  python run_inference.py --input 42    # 使用 In/42.txt（第 42 号样本）
  python run_inference.py --all         # 批量推理全部 496 个样本并统计

输出内容：
  - 每层的输入/输出尺寸和数据类型
  - FC 层 INT8 输出
  - Sigmoid FP32 输出
  - 预测类别（class 0 / class 1）
  - 累计 MAC 操作数（近似估算所需计算量）
"""

import os
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from top_module import TopModule
from load_params import load_golden_input, load_input


def parse_args():
    parser = argparse.ArgumentParser(
        description='CNN 行为级模型推理脚本（PyRTL-CNN）'
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        '--input', type=int, default=None, metavar='N',
        help='指定输入样本编号（In/N.txt），范围 0~495'
    )
    group.add_argument(
        '--golden', action='store_true', default=False,
        help='使用金标准测试输入（Test/Input.txt）（默认）'
    )
    group.add_argument(
        '--all', action='store_true', default=False,
        help='批量推理全部 496 个样本'
    )
    return parser.parse_args()


def run_single(top: TopModule, sample_id=None, input_2d=None, display_id='golden'):
    """运行单次推理，返回结果字典。"""
    if input_2d is not None:
        result = top.forward(input_2d=input_2d)
    else:
        result = top.forward(sample_id=sample_id)
    return result


def main():
    args = parse_args()

    print("╔══════════════════════════════════════════════╗")
    print("║  PyRTL-CNN  行为级 CNN 加速器仿真推理工具    ║")
    print("╚══════════════════════════════════════════════╝")
    print()

    if args.all:
        # ── 批量推理模式，不打印每层详情 ─────────────────────────────────────
        print("批量推理模式：共 496 个样本\n")
        top = TopModule(verbose=False)
        top.load_all_weights()

        class0_count = 0
        class1_count = 0
        total_mac    = 0

        for i in range(496):
            try:
                input_2d = load_input(i)
                top.reset_cycle_count()
                result = top.forward(input_2d=input_2d)
                pred = result['predicted_class']
                if pred == 0:
                    class0_count += 1
                else:
                    class1_count += 1
                total_mac += result['cycle_count']
                if (i + 1) % 50 == 0:
                    print(f"  已处理 {i+1:>3}/496 个样本…")
            except FileNotFoundError:
                print(f"  样本 {i} 文件不存在，跳过。")

        print()
        print("=== 批量推理结果统计 ===")
        print(f"  class 0（负类）预测数：{class0_count}")
        print(f"  class 1（正类）预测数：{class1_count}")
        print(f"  单样本平均 MAC 操作数：{total_mac // 496:,}")
        print()

    else:
        # ── 单样本推理模式 ────────────────────────────────────────────────────
        top = TopModule(verbose=True)
        top.load_all_weights()

        if args.input is not None:
            # 指定编号样本
            sample_id = args.input
            if not (0 <= sample_id <= 495):
                print(f"错误：样本编号 {sample_id} 超出范围 [0, 495]")
                sys.exit(1)
            print(f"使用样本：In/{sample_id}.txt\n")
            result = top.forward(sample_id=sample_id)
        else:
            # 默认使用金标准输入
            print("使用金标准输入：Test/Input.txt\n")
            golden_input = load_golden_input()
            result = top.forward(input_2d=golden_input)

        # 打印最终结果摘要
        out = result['sigmoid_out']
        pred = result['predicted_class']
        mac  = result['cycle_count']

        print("┌─────────────────────────────────┐")
        print("│          推理结果摘要            │")
        print("├─────────────────────────────────┤")
        print(f"│  class 0 概率：{out[0]:.6f}        │")
        print(f"│  class 1 概率：{out[1]:.6f}        │")
        print(f"│  预测类别    ：class {pred}           │")
        print(f"│  MAC 操作数  ：{mac:>10,} 次    │")
        print("└─────────────────────────────────┘")
        print()
        print("注：MAC 操作数为串行执行的估算值，")
        print("    真实 RTL 中并行 MAC 阵列可大幅降低实际运行时钟周期数。")


if __name__ == '__main__':
    main()
