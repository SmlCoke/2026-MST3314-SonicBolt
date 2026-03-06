#!/usr/bin/env python3
"""
gen_testvec.py — 为 Conv1 RTL 仿真生成测试向量
从 MiniCNN/sim/samples/ 读取原始参数，生成 $readmemh 兼容的 hex 文件。

生成文件：
  sim/input.txt         — 300 个 INT8 输入值 (hex, 每行一个值)
  sim/weight.txt        — 2464 个 INT8 权重 (hex, 每行一个值)
  sim/bias.txt          — 32 个 INT32 偏置值 (hex, 每行一个值)
  sim/golden_output.txt — 2560 个 INT8 金标准输出 (hex, 每行 32 个值空格分隔)

用法: python gen_testvec.py
"""

import os
import sys

# ==================== 路径配置 ====================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
PARAM_DIR = os.path.join(PROJECT_ROOT, "MiniCNN", "sim", "samples", "Param")
TEST_DIR = os.path.join(PROJECT_ROOT, "MiniCNN", "sim", "samples", "Test")
SIM_DIR = os.path.join(SCRIPT_DIR, "..", "sim")

# ==================== 辅助函数 ====================
def int8_to_hex(val):
    """将 signed INT8 值转为 2 位十六进制字符串（二进制补码）"""
    if val < 0:
        val = val + 256
    return f"{val:02x}"

def int32_to_hex(val):
    """将 signed INT32 值转为 8 位十六进制字符串（二进制补码）"""
    if val < 0:
        val = val + (1 << 32)
    return f"{val:08x}"

# ==================== 读取参数文件 ====================
def read_conv_weights(param_dir):
    """
    读取 Param_Conv_Weight.txt
    格式: 32 个 filter，每个 filter 11 行，每行 7 个 signed int，空行分隔
    返回: 一维列表，长度 32*77=2464，顺序: filter[0]的77个值, filter[1]的77个值, ...
    """
    filepath = os.path.join(param_dir, "Param_Conv_Weight.txt")
    weights = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            vals = [int(x) for x in line.split()]
            weights.extend(vals)

    assert len(weights) == 32 * 77, f"Expected 2464 weights, got {len(weights)}"
    return weights

def read_conv_bias(param_dir):
    """
    读取 Param_Conv_Bias.txt
    格式: 一行，32 个 signed int 空格分隔
    返回: 长度为 32 的列表
    """
    filepath = os.path.join(param_dir, "Param_Conv_Bias.txt")
    with open(filepath, "r") as f:
        line = f.read().strip()
    biases = [int(x) for x in line.split()]
    assert len(biases) == 32, f"Expected 32 biases, got {len(biases)}"
    return biases

def read_input(test_dir):
    """
    读取 Test/Input.txt
    格式: 一行，300 个 signed int 空格分隔 (1*30*10 = 300)
    返回: 长度为 300 的列表
    """
    filepath = os.path.join(test_dir, "Input.txt")
    with open(filepath, "r") as f:
        line = f.read().strip()
    inputs = [int(x) for x in line.split()]
    assert len(inputs) == 300, f"Expected 300 inputs, got {len(inputs)}"
    return inputs

def read_golden_output(test_dir):
    """
    读取 Test/Out_Conv.txt
    格式: 32 个 channel，每个 channel 20 行，每行 4 个 signed int，空行分隔
    顺序: channel 0 的 20*4=80 个值, channel 1 的 80 个值, ...
    返回: 二维列表 [channel][h*4+w], shape (32, 80)
    """
    filepath = os.path.join(test_dir, "Out_Conv.txt")
    channels = []
    current_channel = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                if current_channel:
                    channels.append(current_channel)
                    current_channel = []
                continue
            vals = [int(x) for x in line.split()]
            current_channel.extend(vals)
    if current_channel:
        channels.append(current_channel)

    assert len(channels) == 32, f"Expected 32 channels, got {len(channels)}"
    for i, ch in enumerate(channels):
        assert len(ch) == 80, f"Channel {i}: expected 80 values, got {len(ch)}"
    return channels

# ==================== 生成测试向量文件 ====================
def gen_input_hex(inputs, out_path):
    """
    生成 input.txt: 300 行，每行一个 2 位 hex (INT8)
    地址映射: addr = h * 10 + w (行主序)
    """
    with open(out_path, "w") as f:
        for val in inputs:
            f.write(int8_to_hex(val) + "\n")
    print(f"  [OK] input.txt: {len(inputs)} values")

def gen_weight_hex(weights, out_path):
    """
    生成 weight.txt: 2464 行，每行一个 2 位 hex (INT8)
    地址映射: addr = filter_id * 77 + row * 7 + col
    """
    with open(out_path, "w") as f:
        for val in weights:
            f.write(int8_to_hex(val) + "\n")
    print(f"  [OK] weight.txt: {len(weights)} values")

def gen_bias_hex(biases, out_path):
    """
    生成 bias.txt: 32 行，每行一个 8 位 hex (INT32，保留精度)
    """
    with open(out_path, "w") as f:
        for val in biases:
            f.write(int32_to_hex(val) + "\n")
    print(f"  [OK] bias.txt: {len(biases)} values")

def gen_golden_hex(channels, out_path):
    """
    生成 golden_output.txt: 80 行 (20 行 × 4 列)
    每行 32 个 hex 值空格分隔 (对应 32 个 channel 在同一空间位置的输出)
    行顺序: (h=0,w=0), (h=0,w=1), ..., (h=0,w=3), (h=1,w=0), ..., (h=19,w=3)

    这个顺序与 RTL 输出顺序一致：每个时钟周期输出所有 32 个通道在同一个 (h,w) 位置的值
    """
    with open(out_path, "w") as f:
        for h in range(20):
            for w in range(4):
                # 取 32 个 channel 在 (h, w) 处的值
                vals = []
                for ch in range(32):
                    val = channels[ch][h * 4 + w]
                    vals.append(int8_to_hex(val))
                f.write(" ".join(vals) + "\n")
    print(f"  [OK] golden_output.txt: 80 lines × 32 channels")

# ==================== 主函数 ====================
def main():
    os.makedirs(SIM_DIR, exist_ok=True)

    print("=" * 60)
    print("Conv1 测试向量生成器")
    print("=" * 60)
    print(f"  参数目录: {PARAM_DIR}")
    print(f"  金标准目录: {TEST_DIR}")
    print(f"  输出目录: {SIM_DIR}")
    print()

    # 读取参数
    print("[1/4] 读取卷积权重...")
    weights = read_conv_weights(PARAM_DIR)

    print("[2/4] 读取偏置...")
    biases = read_conv_bias(PARAM_DIR)

    print("[3/4] 读取输入特征图...")
    inputs = read_input(TEST_DIR)

    print("[4/4] 读取金标准输出...")
    golden = read_golden_output(TEST_DIR)

    print()
    print("生成 hex 文件:")
    gen_input_hex(inputs, os.path.join(SIM_DIR, "input.txt"))
    gen_weight_hex(weights, os.path.join(SIM_DIR, "weight.txt"))
    gen_bias_hex(biases, os.path.join(SIM_DIR, "bias.txt"))
    gen_golden_hex(golden, os.path.join(SIM_DIR, "golden_output.txt"))

    print()
    print("=" * 60)
    print("全部完成！可在仿真中使用 $readmemh 加载上述文件。")
    print("=" * 60)

if __name__ == "__main__":
    main()
