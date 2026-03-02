"""
load_params.py
==============
参数加载模块：从 MiniCNN/sim/samples/ 读取所有网络参数、重量化参数、
Sigmoid 查找表及输入/金标准数据。

对应硬件概念：
  - Weight SRAM 的初始化数据来源
  - Scale/Rescale 参数寄存器
  - Sigmoid LUT ROM 的初始化内容
"""

import os
import struct
import re

# ─────────────────────────────────────────────────────────────────────────────
# 路径配置
# ─────────────────────────────────────────────────────────────────────────────
_THIS_DIR  = os.path.dirname(os.path.abspath(__file__))
_BASE_DIR  = os.path.normpath(os.path.join(_THIS_DIR, '..', 'MiniCNN', 'sim', 'samples'))
_PARAM_DIR = os.path.join(_BASE_DIR, 'Param')
_SCALE_DIR = os.path.join(_BASE_DIR, 'Scale')
_IN_DIR    = os.path.join(_BASE_DIR, 'In')
_TEST_DIR  = os.path.join(_BASE_DIR, 'Test')


# ─────────────────────────────────────────────────────────────────────────────
# 位宽辅助：显式截断至 INT8（有符号）
# ─────────────────────────────────────────────────────────────────────────────
def _to_int8(x):
    """将 Python int 截断至 INT8 有符号范围 [-128, 127]。"""
    x = int(x) & 0xFF
    return x - 256 if x >= 128 else x

def _to_int16(x):
    """将 Python int 截断至 INT16 有符号范围 [-32768, 32767]。"""
    x = int(x) & 0xFFFF
    return x - 65536 if x >= 32768 else x


# ─────────────────────────────────────────────────────────────────────────────
# 参数加载函数
# ─────────────────────────────────────────────────────────────────────────────

def load_conv_weight():
    """
    加载 Conv 层权重。
    文件：Param/Param_Conv_Weight.txt
    格式：32 个 (11,7) INT8 矩阵，矩阵间以空行分隔，元素间空格分隔。
    返回：list[list[list[int]]]，形状 (32, 11, 7)，数据类型 INT8。
    """
    path = os.path.join(_PARAM_DIR, 'Param_Conv_Weight.txt')
    weights = []  # shape: (32, 11, 7)
    kernel = []   # shape: (11, 7)
    with open(path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped == '':
                if kernel:
                    weights.append(kernel)
                    kernel = []
            else:
                row = [_to_int8(int(v)) for v in stripped.split()]
                kernel.append(row)
    if kernel:
        weights.append(kernel)
    assert len(weights) == 32, f"Conv weight: expected 32 kernels, got {len(weights)}"
    return weights   # INT8, shape (32, 11, 7)


def load_conv_bias():
    """
    加载 Conv 层偏置。
    文件：Param/Param_Conv_Bias.txt
    格式：一维向量，32 个 INT32 整数（空格或换行分隔）。
    返回：list[int]，形状 (32,)，数据类型 INT16（实际存储为 INT32 以容纳偏置）。
    """
    path = os.path.join(_PARAM_DIR, 'Param_Conv_Bias.txt')
    values = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                values.append(_to_int16(int(v)))
    assert len(values) == 32, f"Conv bias: expected 32, got {len(values)}"
    return values   # INT16, shape (32,)


def load_dwconv_weight():
    """
    加载 DWConv 层权重。
    文件：Param/Param_DWConv_Weight.txt
    格式：32 个 (3,3) INT8 矩阵，矩阵间以空行分隔。
    返回：list[list[list[int]]]，形状 (32, 3, 3)，数据类型 INT8。
    """
    path = os.path.join(_PARAM_DIR, 'Param_DWConv_Weight.txt')
    weights = []
    kernel = []
    with open(path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped == '':
                if kernel:
                    weights.append(kernel)
                    kernel = []
            else:
                row = [_to_int8(int(v)) for v in stripped.split()]
                kernel.append(row)
    if kernel:
        weights.append(kernel)
    assert len(weights) == 32, f"DWConv weight: expected 32 kernels, got {len(weights)}"
    return weights   # INT8, shape (32, 3, 3)


def load_dwconv_bias():
    """
    加载 DWConv 层偏置。
    文件：Param/Param_DWConv_Bias.txt
    格式：一维向量，32 个整数。
    返回：list[int]，形状 (32,)，数据类型 INT16。
    """
    path = os.path.join(_PARAM_DIR, 'Param_DWConv_Bias.txt')
    values = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                values.append(_to_int16(int(v)))
    assert len(values) == 32, f"DWConv bias: expected 32, got {len(values)}"
    return values   # INT16, shape (32,)


def load_pwconv_weight():
    """
    加载 PWConv 层权重。
    文件：Param/Param_PWConv_Weight.txt
    格式：(32,32) 矩阵，每行 32 个 INT8 整数，共 32 行。
    返回：list[list[int]]，形状 (32, 32)，数据类型 INT8。
         weights[out_ch][in_ch] 对应输出通道 out_ch 对输入通道 in_ch 的权重。
    """
    path = os.path.join(_PARAM_DIR, 'Param_PWConv_Weight.txt')
    weights = []
    with open(path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                row = [_to_int8(int(v)) for v in stripped.split()]
                weights.append(row)
    assert len(weights) == 32, f"PWConv weight: expected 32 rows, got {len(weights)}"
    return weights   # INT8, shape (32, 32)


def load_pwconv_bias():
    """
    加载 PWConv 层偏置。
    文件：Param/Param_PWConv_Bias.txt
    格式：一维向量，32 个整数。
    返回：list[int]，形状 (32,)，数据类型 INT16。
    """
    path = os.path.join(_PARAM_DIR, 'Param_PWConv_Bias.txt')
    values = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                values.append(_to_int16(int(v)))
    assert len(values) == 32, f"PWConv bias: expected 32, got {len(values)}"
    return values   # INT16, shape (32,)


def load_linear_weight():
    """
    加载 FC 全连接层权重。
    文件：Param/Param_Linear_Weight.txt
    格式：(2,288) 矩阵，每行 288 个 INT8 整数，共 2 行。
    返回：list[list[int]]，形状 (2, 288)，数据类型 INT8。
    """
    path = os.path.join(_PARAM_DIR, 'Param_Linear_Weight.txt')
    weights = []
    with open(path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                row = [_to_int8(int(v)) for v in stripped.split()]
                weights.append(row)
    assert len(weights) == 2, f"Linear weight: expected 2 rows, got {len(weights)}"
    assert len(weights[0]) == 288, f"Linear weight: expected 288 cols, got {len(weights[0])}"
    return weights   # INT8, shape (2, 288)


def load_linear_bias():
    """
    加载 FC 全连接层偏置。
    文件：Param/Param_Linear_Bias.txt
    格式：一维向量，2 个整数。
    返回：list[int]，形状 (2,)，数据类型 INT16。
    """
    path = os.path.join(_PARAM_DIR, 'Param_Linear_Bias.txt')
    values = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                values.append(_to_int16(int(v)))
    assert len(values) == 2, f"Linear bias: expected 2, got {len(values)}"
    return values   # INT16, shape (2,)


def load_rescale_params():
    """
    加载各层重量化参数 (M0, n)。
    文件：Scale/Rescale.txt
    格式：以 C 风格注释和赋值语句描述，解析关键字段。
    返回：dict，结构如下：
      {
        'Conv':    {'M0': 111, 'n': 14},
        'DWConv':  {'M0': 59,  'n': 11},
        'PWConv':  {'M0': 69,  'n': 13},
        'Linear':  {'M0': 11,  'n': 15},
      }
    注：重量化公式为 output_int8 = clamp(input_int32 * M0 >> n, -128, 127)
    """
    path = os.path.join(_SCALE_DIR, 'Rescale.txt')
    params = {}
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if line.startswith('//') or not line:
                continue
            # 匹配: int Conv_M0 = 111;
            m = re.match(r'int\s+(\w+)_M0\s*=\s*(-?\d+)', line)
            if m:
                layer = m.group(1)
                if layer not in params:
                    params[layer] = {}
                params[layer]['M0'] = int(m.group(2))
                continue
            m = re.match(r'int\s+(\w+)_n\s*=\s*(-?\d+)', line)
            if m:
                layer = m.group(1)
                if layer not in params:
                    params[layer] = {}
                params[layer]['n'] = int(m.group(2))
    return params


def load_linear_out_scale():
    """
    加载全连接层输出的量化 Scale 值。
    文件：Scale/Scale.txt
    用途：Sigmoid 层使用，公式：fp32 = int8 * Linear_Out_Scale，然后计算 sigmoid。
    返回：float，Linear_Out_Scale 的值。
    """
    path = os.path.join(_SCALE_DIR, 'Scale.txt')
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if line.startswith('//') or not line:
                continue
            m = re.match(r'float\s+Linear_Out_Scale\s*=\s*([0-9.eE+\-]+)', line)
            if m:
                return float(m.group(1))
    raise ValueError("Linear_Out_Scale not found in Scale.txt")


def load_sigmoid_lut():
    """
    加载 Sigmoid 查找表（LUT）。
    文件：sigmoid_lookup_table.txt（位于 samples/ 根目录）
    格式：每行为 IEEE 754 单精度浮点的 8 位十六进制字符串。
          排序方式：index = int8 & 0xFF，即 0x00 对应 int8=-128，0xFF 对应 int8=127。
    返回：list[float]，长度 256。
          访问方式：lut[x & 0xFF]，其中 x 为 INT8 输入。
    """
    path = os.path.join(_BASE_DIR, 'sigmoid_lookup_table.txt')
    lut = []
    with open(path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                # 将 8 位十六进制解析为 IEEE 754 单精度浮点
                bits = int(stripped, 16)
                fp_val = struct.unpack('>f', struct.pack('>I', bits))[0]
                lut.append(fp_val)
    assert len(lut) == 256, f"Sigmoid LUT: expected 256 entries, got {len(lut)}"
    return lut   # list[float], length 256


def load_input(sample_id):
    """
    加载指定编号的输入 MFCC 特征图。
    文件：In/{sample_id}.txt
    格式：30 行，每行 10 个 INT8 整数，空格分隔。
    参数：sample_id (int)，取值范围 0~495。
    返回：list[list[list[int]]]，形状 (1, 30, 10)，数据类型 INT8。
         （第一维度为通道数=1，与网络输入格式一致）
    """
    path = os.path.join(_IN_DIR, f'{sample_id}.txt')
    feature_map = []  # shape: (30, 10)
    with open(path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                row = [_to_int8(int(v)) for v in stripped.split()]
                feature_map.append(row)
    assert len(feature_map) == 30, f"Input: expected 30 rows, got {len(feature_map)}"
    return feature_map  # shape (30, 10), dtype INT8


def load_golden_input():
    """
    加载 Test/Input.txt 金标准输入，用于验证。
    格式：可能为 1 行 300 个值（展平格式）或 30 行 × 10 列（正常格式）。
    返回：list[list[int]]，形状 (30, 10)，数据类型 INT8。
    """
    path = os.path.join(_TEST_DIR, 'Input.txt')
    flat = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                flat.append(_to_int8(int(v)))
    assert len(flat) == 300, f"Golden input: expected 300 values, got {len(flat)}"
    # reshape to (30, 10)
    rows = [flat[j*10:(j+1)*10] for j in range(30)]
    return rows  # shape (30, 10)


def _load_matrix_txt(path, expected_channels=None):
    """
    通用矩阵 txt 加载器。
    格式：多个 2D 矩阵，矩阵间以空行分隔。
    返回：list of list[list[int]]，即 [channel][row][col]。
    """
    matrices = []
    matrix = []
    with open(path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped == '':
                if matrix:
                    matrices.append(matrix)
                    matrix = []
            else:
                row = [int(v) for v in stripped.split()]
                matrix.append(row)
    if matrix:
        matrices.append(matrix)
    if expected_channels is not None:
        assert len(matrices) == expected_channels, \
            f"{path}: expected {expected_channels} matrices, got {len(matrices)}"
    return matrices


def load_golden_conv():
    """
    加载 Conv 层金标准输出。
    文件：Test/Out_Conv.txt
    格式：32 个 (20,4) INT8 矩阵，矩阵间空行分隔。
    返回：list[list[list[int]]]，形状 (32, 20, 4)，数据类型 INT8。
    """
    path = os.path.join(_TEST_DIR, 'Out_Conv.txt')
    return _load_matrix_txt(path, expected_channels=32)


def load_golden_dwconv():
    """
    加载 DWConv 层金标准输出。
    文件：Test/Out_DWConv.txt
    格式：32 个 (18,2) INT8 矩阵，矩阵间空行分隔。
    返回：list[list[list[int]]]，形状 (32, 18, 2)，数据类型 INT8。
    """
    path = os.path.join(_TEST_DIR, 'Out_DWConv.txt')
    return _load_matrix_txt(path, expected_channels=32)


def load_golden_pwconv():
    """
    加载 PWConv 层金标准输出。
    文件：Test/Out_PWConv.txt
    格式：32 个 (18,2) INT8 矩阵，矩阵间空行分隔。
    返回：list[list[list[int]]]，形状 (32, 18, 2)，数据类型 INT8。
    """
    path = os.path.join(_TEST_DIR, 'Out_PWConv.txt')
    return _load_matrix_txt(path, expected_channels=32)


def load_golden_flatten():
    """
    加载 Flatten 层金标准输出。
    文件：Test/Out_Flatten.txt
    格式：单行或多行，共 288 个 INT8 整数。
    返回：list[int]，形状 (288,)，数据类型 INT8。
    """
    path = os.path.join(_TEST_DIR, 'Out_Flatten.txt')
    values = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                values.append(int(v))
    assert len(values) == 288, f"Flatten golden: expected 288, got {len(values)}"
    return values


def load_golden_linear():
    """
    加载 FC 层金标准输出。
    文件：Test/Out_Linear.txt
    格式：2 个 INT8 整数。
    返回：list[int]，形状 (2,)，数据类型 INT8。
    """
    path = os.path.join(_TEST_DIR, 'Out_Linear.txt')
    values = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                values.append(int(v))
    assert len(values) == 2, f"Linear golden: expected 2, got {len(values)}"
    return values


def load_golden_sigmoid():
    """
    加载 Sigmoid 层（最终输出）金标准。
    文件：Test/Out.txt
    格式：2 个 FP32 浮点数。
    返回：list[float]，形状 (2,)。
    """
    path = os.path.join(_TEST_DIR, 'Out.txt')
    values = []
    with open(path, 'r') as f:
        for line in f:
            for v in line.split():
                values.append(float(v))
    assert len(values) == 2, f"Sigmoid golden: expected 2, got {len(values)}"
    return values


# ─────────────────────────────────────────────────────────────────────────────
# 快速自检
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    print("=== load_params.py self-test ===\n")

    w = load_conv_weight()
    print(f"Conv weight shape    : ({len(w)}, {len(w[0])}, {len(w[0][0])})  dtype=INT8")

    b = load_conv_bias()
    print(f"Conv bias shape      : ({len(b)},)  dtype=INT16")

    dw = load_dwconv_weight()
    print(f"DWConv weight shape  : ({len(dw)}, {len(dw[0])}, {len(dw[0][0])})  dtype=INT8")

    db = load_dwconv_bias()
    print(f"DWConv bias shape    : ({len(db)},)  dtype=INT16")

    pw = load_pwconv_weight()
    print(f"PWConv weight shape  : ({len(pw)}, {len(pw[0])})  dtype=INT8")

    pb = load_pwconv_bias()
    print(f"PWConv bias shape    : ({len(pb)},)  dtype=INT16")

    lw = load_linear_weight()
    print(f"Linear weight shape  : ({len(lw)}, {len(lw[0])})  dtype=INT8")

    lb = load_linear_bias()
    print(f"Linear bias shape    : ({len(lb)},)  dtype=INT16")

    rp = load_rescale_params()
    print(f"\nRescale params:")
    for layer, p in rp.items():
        print(f"  {layer:8s}: M0={p['M0']}, n={p['n']}")

    sc = load_linear_out_scale()
    print(f"\nLinear_Out_Scale     : {sc}")

    lut = load_sigmoid_lut()
    print(f"Sigmoid LUT length   : {len(lut)}")
    print(f"  LUT[0x00] (x=-128) : {lut[0]:.6f}")
    print(f"  LUT[0x80] (x=0)    : {lut[0x80]:.6f}")
    print(f"  LUT[0xFF] (x=127)  : {lut[0xFF]:.6f}")

    inp = load_golden_input()
    print(f"Golden input shape   : ({len(inp)}, {len(inp[0])})  expected: (30, 10)")
    print(f"  First row (10 val) : {inp[0]}")

    print("\n=== All params loaded successfully ===")
