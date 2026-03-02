User: 我是一名微电子科学与工程系的大三学生，喜欢的专业方向是数字方向。我这学期选择了一门《数字集成电路设计课程设计》的课程，时长八周，课程内容就是一步一步设计一个神经网络加速器（这里的神经网络就是一个简化版本的MobileNet v2），涵盖了电路结构设计、Verilog HDL, 逻辑仿真，逻辑综合，时序分析与验证和物理设计等环节。
文档：Materials/introduction.md 是本门课程介绍
文档：Materials/Design_Specification.md 是这个电路的原理介绍以及设计要求。
文档：Materials/Skill-Plan.md 是 AI 给出的要做完这个课程设计，我们需要掌握的技能以及项目推进流程，不一定全对，你后续工作时不一定按照这个来
仓库：MiniCNN/ 是上一届课程的项目，应该包含了完整的设计和测试代码。两届课程的CNN架构相同，但是性能实现要求有区别，可以作为重要参考

我们的团队基本信息：
我们团队由两个人组成，均掌握 Verilog, C/C++, Python 等语言，同时对深度学习/计算机视觉/卷积神经网络也比较熟悉。准备选择的课题场景是：“高性能场景”。就完成这个课程设计所需要的技能来说，我们的技能树比较薄弱，对流水线架构、SRAM、片上存储、数据缓冲等概念都可以说是零基础。之前也没有接触过数字后端的设计流程，对测试向量、时序分析、物理设计也是零基础。这个课程项目是我们专业的同学第一次接触到这些东西。
首先，我们需要你帮助做的第一件事情是：

因为我们基础比较薄弱，所以我们准备获得一版完全由Python实现的卷积计算案例先看看效果，理解一下架构（例如重要的流水线、数据缓冲、片上存储）当然，不包含后续的时许分析物理设计那些，只实现逻辑功能即可。需要满足如下要求：Materials/PyCode-Specifications.md

将生成的Python代码和必要文档放置在 PyRTL-CNN/ 文件夹下


GitHub Copilot: Research CNN project docs

读取 [](file:///d%3A/Project/CNN-Accelerator/Materials/introduction.md)

读取 [](file:///d%3A/Project/CNN-Accelerator/Materials/Design_Specifications.md)

读取 [](file:///d%3A/Project/CNN-Accelerator/Materials/PyCode-Specifications.md)

读取 [](file:///d%3A/Project/CNN-Accelerator/Materials/Skill-Plan.md)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/testbenches)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/Conv_11_7_1)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/DWconv_3_3_1)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/PostProcess)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/PWconv_1_1_32)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/utils)

读取 [](file:///d%3A/Project/CNN-Accelerator/Materials/Design_Specifications.md)

读取 [](file:///d%3A/Project/CNN-Accelerator/Materials/PyCode-Specifications.md)

Now let me explore the MiniCNN sim data files and some key source files to understand the parameter formats and architecture: 

Research MiniCNN source and sim files

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/README.md)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Conv_Weight_arranged_0.txt#1-1)，行 1 到 20

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Conv_Bias_arranged.txt#1-1)，行 1 到 20

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Conv_weight_pack.py)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/DWConv_weight_pack.py)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/PWConv_weight_pack.py)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Linear_weight_pack.py)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Sigmoid_LUT.py)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/sigmoid_lookup_table.txt#1-1)，行 1 到 20

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/In/0.txt)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/In/0_hex.txt#1-1)，行 1 到 20

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Param)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Scale)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Test)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/CNN.v)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/utils)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/In)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/src/modules/utils/RescaleReLu.v)

读取 [](file:///c%3A/Users/21035/AppData/Roaming/Code/User/workspaceStorage/7957633e1b9cfaacfbc2e130b1ab4cd7/GitHub.copilot-chat/chat-session-resources/91e28d26-d206-4c4d-9b3e-1437dec9f5c7/toolu_bdrk_01CYg7zRUnivPfUMfVdyaD22__vscode-1772453681631/content.txt#1-1)，行 1 到 400

读取 [](file:///c%3A/Users/21035/AppData/Roaming/Code/User/workspaceStorage/7957633e1b9cfaacfbc2e130b1ab4cd7/GitHub.copilot-chat/chat-session-resources/91e28d26-d206-4c4d-9b3e-1437dec9f5c7/toolu_bdrk_01CYg7zRUnivPfUMfVdyaD22__vscode-1772453681631/content.txt#400-400)，行 400 到 712

Now let me also read the Scale parameters and one or two Param files to understand their format:  

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Scale/Rescale.txt)

读取 [](file:///d%3A/Project/CNN-Accelerator/MiniCNN/sim/samples/Scale/Scale.txt)

现在我已有足够信息来制定详细计划。以下是草案：

---

## Plan: Python RTL 风格 CNN 行为模型

**TL;DR**：在 `PyRTL-CNN/` 文件夹下实现一套纯 Python、RTL 映射风格的 CNN 行为模型。禁用 NumPy/PyTorch，所有计算用 for 循环实现，显式标注 INT8/INT16/INT32 位宽。代码结构对齐 RTL 模块划分（FeatureSRAM、WeightSRAM、LineBuffer、MACUnit、RequantUnit + 各层类），兼顾 RTL 映射参考和 Testbench 金标准两个目标。参数全部从 samples 下读取，重量化参数来自 Rescale.txt，Sigmoid 使用 `sigmoid_lookup_table.txt` 查找表。

---

**目录结构**
```
PyRTL-CNN/
├── README.md              # 项目总览 + 使用方法  
├── param_doc.md           # 自动生成的参数文件说明文档
├── load_params.py         # 参数加载脚本（读取 Param/ + Scale/ + Sigmoid LUT）
├── rtl_primitives.py      # 底层硬件原语类
├── layers.py              # 各层类（Conv/DWConv/PWConv/Maxpool/Flatten/FC/Sigmoid）
├── top_module.py          # TopModule 顶层类，顺序调用所有层
├── run_inference.py       # 单样本推理入口脚本，打印每层 I/O 尺寸
└── test_golden.py         # 对比 MiniCNN/sim/samples/Test/ 金标准验证脚本
```

---

**Steps**

1. **load_params.py** — 参数加载模块  
   - `load_conv_weight()` → 解析 32 个 (11,7) INT8 矩阵（空行分隔格式）  
   - `load_bias()` → 解析一维 INT16 向量  
   - `load_dwconv_weight()` → 解析 32 个 (3,3) INT8 矩阵  
   - `load_pwconv_weight()` → 解析 (32,32) INT8 矩阵  
   - `load_linear_weight()` → 解析 (2,288) INT8 矩阵  
   - `load_rescale_params()` → 从 Rescale.txt 提取各层 `(M0, n)` 字典  
   - `load_sigmoid_lut()` → 从 `sigmoid_lookup_table.txt` 读取 256 个 FP32 值（IEEE 754 hex → Python float）  
   - `load_input(path)` → 读取 `In/N.txt` 格式的 (30,10) INT8 输入  
   - `load_golden(layer_name)` → 读取 `Test/` 下对应层的金标准输出  
   - 同时生成 **param_doc.md**，说明每个参数文件的内容、形状、数据格式

2. **rtl_primitives.py** — 底层硬件抽象  
   - `clamp(x, bits, signed)` — 显式位宽截断函数（INT8/INT16/INT32 饱和截断）  
   - `FeatureSRAM` — 模拟片上特征图存储，`read(addr)` / `write(addr, data)`，数据为 INT8  
   - `WeightSRAM` — 模拟权重存储，按层初始化，`read(addr)`  
   - `LineBuffer` — 滑窗行缓冲，支持可配置窗口尺寸（用于 Conv 和 DWConv），`push(row)` / `get_window(col)` 返回当前卷积窗口的数据切片  
   - `MACUnit` — 乘累加单元，`accumulate(a_int8, b_int8) → INT32`，for 循环累加，显式 INT32 存储  
   - `RequantUnit` — 重量化单元，`requant(x_int32, M0, n) → INT8`，实现 `clamp(x * M0 >> n, 8, signed=True)`

3. **layers.py** — 各层封装类，每层包含 `load_weight()` / `compute()` / `requant()`  

   - **`ConvLayer`**（Conv 32,1,11,7）  
     - `load_weight()`：从 `WeightSRAM` 加载 weight `(32,1,11,7)` 和 bias `(32)` INT16  
     - `compute()`：从 `FeatureSRAM` 读 input `(1,30,10)` INT8，`LineBuffer` 管理行窗口；三重 for 循环（输出通道 i、输出行 j、输出列 k）调用 `MACUnit` 累加 `1×11×7=77` 次乘法，加 bias → INT32 结果，尺寸 `(32,20,4)`  
     - `requant()`：调用 `RequantUnit`，参数 `M0=111, n=14`，输出 INT8 + ReLU，写入输出 `FeatureSRAM`  

   - **`DWConvLayer`**（DWConv 32,1,3,3）  
     - 与 Conv 类似，但按通道独立计算（无跨通道累加），`LineBuffer` 每通道独立维护  
     - 输入 `(32,20,4)` INT8，输出 `(32,18,2)` INT32 → requant `M0=59, n=11` → INT8 + ReLU  

   - **`PWConvLayer`**（PWConv 32,32,1,1）  
     - 1×1 卷积等价于按空间位置的向量内积，for 循环：输出通道 i、空间位置 (j,k)，内积 32 次 MAC  
     - 输入 `(32,18,2)` INT8，输出 `(32,18,2)` INT32 → requant `M0=69, n=13` → INT8 + ReLU  

   - **`MaxpoolLayer`**（2×2 stride=2）  
     - 纯 for 循环找最大值，输入 `(32,18,2)` INT8 → 输出 `(32,9,1)` INT8  
     - 无需 load_weight/requant，compute() 即完整实现  

   - **`FlattenLayer`**  
     - `(32,9,1)` → `(288,)` 展平，按 `O[32*(i-1)+j] = I[i][j][0]` 顺序  

   - **`FCLayer`**（FC 2,288）  
     - `load_weight()`：权重 `(2,288)` INT8，bias `(2,)` INT16  
     - `compute()`：双重 for 循环，288 次 MAC × 2 输出，INT32 累加加 bias  
     - `requant()`：`M0=11, n=15`，输出 INT8（**不加 ReLU**）  

   - **`SigmoidLayer`**  
     - `load_weight()`：加载 256 entry 的 LUT（index = int8 无符号地址，值为 FP32）  
     - `compute()`：INT8 输入作为 LUT 索引（用 `x & 0xFF` 映射），输出 FP32  
     - 无 requant()

4. **top_module.py** — `TopModule` 类  
   - 构造函数实例化所有层和 SRAM，调用各层 `load_weight()`  
   - `forward(input_path)` 方法：  
     1. 读取输入 → 存入 feature SRAM  
     2. 顺序调用各层 `compute()` + `requant()`（有的层）  
     3. 每层调用后打印：层名、输入尺寸、输出尺寸、中间 SRAM 占用  
     4. 返回最终 FP32 输出 `[sigmoid_out0, sigmoid_out1]`  
   - 可选：`cycle_count` 计数器，统计总 MAC 操作次数，模拟流水线 stage 数

5. **run_inference.py** — 命令行推理入口  
   - 支持 `python run_inference.py --input 0`（使用第 N 号测试样本）  
   - 打印每层 I/O 尺寸 + 最终分类结果  

6. **test_golden.py** — 金标准对比验证  
   - 加载 Test 下所有中间层输出  
   - 逐层对比：Conv、DWConv、PWConv 输出，逐元素比较误差  
   - 打印每层：匹配元素数/总元素数、最大绝对误差、是否通过  

7. **README.md** — 文档  
   - 网络结构总览表（含每层的输入/输出尺寸、位宽、Rescale 参数）  
   - 代码模块说明 + 使用方法  
   - RTL 映射关系说明（Python 类 → Verilog 模块对应关系）

---

**Verification**

```bash
cd PyRTL-CNN
# 金标准验证（对比 MiniCNN/sim/samples/Test/ 每层输出）
python test_golden.py

# 单样本推理（打印每层 I/O 尺寸）
python run_inference.py --input 0
```
预期：每层输出与金标准完全匹配（INT8 整数层逐元素一致，Sigmoid FP32 误差 < 1e-5）

---

**Decisions**
- **Sigmoid 用 LUT 实现**（而非浮点 exp），与 RTL 设计 LUT 实现保持一致，`sigmoid_lookup_table.txt` 已提供 256 条目
- **LineBuffer 抽象**：虽然 Python 无需真正节省内存，但显式建模 LineBuffer 有助于后续 RTL 映射时直接对应数据缓冲结构
- **单文件 vs 多文件**：选择多文件分模块组织，与后续 RTL 文件结构保持对应
- **参数路径**：使用相对路径 `../MiniCNN/sim/samples/`，在 `PyRTL-CNN/` 目录下运行

---

以上是完整方案草案，请确认或提出修改意见。确认后可以开始实现。

User: Start implementation

GitHub Copilot: Created 8 todos

Starting: *创建 load_params.py* (1/8)

已创建 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/load_params.py)

Starting: *创建 rtl_primitives.py* (2/8)

已创建 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/rtl_primitives.py)

Now create `layers.py`: 

Starting: *创建 layers.py* (3/8)

已创建 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/layers.py)

Now create `top_module.py`: 

Starting: *创建 top_module.py* (4/8)

已创建 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/top_module.py)

Now create `run_inference.py` and `test_golden.py` in parallel: 

已创建 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/run_inference.py)

 

已创建 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/test_golden.py)

Now create `README.md`: 

Starting: *创建 README.md* (7/8)

已创建 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/README.md)

Now run the verification: 

Starting: *运行验证测试* (8/8)

Ran terminal command: cd "d:\Project\CNN-Accelerator\PyRTL-CNN"; python load_params.py
Completed with input: cd "d:\Project\CNN-Accelerator\PyRTL-CNN"; python load_params.py

文件编码问题，需要对 Rescale.txt 和 Scale.txt 的 open 调用指定编码： 

正在将 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/load_params.py) 中的 5 行替换为 5 行


```

```
Now let me run the primitives self-test and params self-test in parallel: 

Ran terminal command: python load_params.py

参数加载正常，但 `golden_input` 形状显示为 (1, 300)，说明 `Test/Input.txt` 格式是单行 300 万值。先看实际格式再修正： 

Ran terminal command: cd "d:\Project\CNN-Accelerator"; Get-Content "MiniCNN\sim\samples\Test\Input.txt" | Select-Object -First 5; Write-Host "---"; (Get-Content "MiniCNN\sim\samples\Test\Input.txt").Count

`Test/Input.txt` 是单行 300 个值，需要在 `load_golden_input()` 中展平后 reshape，同时 `load_input()` 需要验证样本文件格式：  

Ran terminal command: Get-Content "MiniCNN\sim\samples\In\0.txt" | Select-Object -First 5; Write-Host "---"; (Get-Content "MiniCNN\sim\samples\In\0.txt").Count

`In/N.txt` 是 30 行 × 10 列，但 `Test/Input.txt` 是 1 行 300 个值。修复 `load_golden_input()` 并同步修正 `load_input()` 的返回格式（确保返回 (30,10) 嵌套列表）：   

正在将 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/load_params.py) 中的 20 行替换为 20 行


```

```
Now run the full golden test:  

Ran terminal command: cd "d:\Project\CNN-Accelerator\PyRTL-CNN"; python load_params.py 2>&1 | Select-Object -Last 15

参数加载全部正常。现在运行金标准验证（这是核心验证，会需要一些时间因为纯 Python for 循环）：   

Ran terminal command: python test_golden.py

Ran terminal command: Set-Location "d:\Project\CNN-Accelerator\PyRTL-CNN"; python test_golden.py

Awaited terminal completion

分析结果：golden 文件中的 Conv/DWConv/PWConv 输出是**重量化后、ReLU 之前**的值（含负数），而 ReLU 是在内部存储和传递给下一层时分别施加的。需要将 ReLU 从 RequantUnit 中分离出来，改为在各接收层读取数据时施加： 

正在将 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/layers.py) 中的 51 行替换为 58 行


```

```


Ran terminal command: Set-Location "d:\Project\CNN-Accelerator\PyRTL-CNN"; python test_golden.py

是否继续迭代？
[object Object]

Made changes.

User: @agent 继续: "是否继续迭代？"

GitHub Copilot: Awaited terminal completion

让我先读一下 `layers.py` 确认修改是否正确保存：   

读取 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/layers.py#170-170)，行 170 到 240

读取 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/layers.py#260-260)，行 260 到 320

找到 bug！`rows_for_lb.append(row_data)` 和 `lb.load_rows(rows_for_lb)` 这两行在编辑时丢失了，导致行缓冲从未被加载。修复：   

正在将 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/layers.py) 中的 12 行替换为 14 行


```

```


Ran terminal command: Set-Location "d:\Project\CNN-Accelerator\PyRTL-CNN"; python test_golden.py

Awaited terminal completion

所有层 100% 通过！最后验证推理脚本：    

Ran terminal command: Set-Location "d:\Project\CNN-Accelerator\PyRTL-CNN"; python run_inference.py --input 0

Awaited terminal completion

Completed: *运行验证测试* (8/8)

全部完成，验证通过。以下是项目总结：

---

## 完成情况

PyRTL-CNN 目录已创建，包含以下文件：

| 文件 | 作用 | RTL 对应 |
|---|---|---|
| load_params.py | 参数加载（从 samples 读取） | Weight SRAM 初始化 |
| rtl_primitives.py | 底层原语：`FeatureSRAM` / `WeightSRAM` / `LineBuffer` / `MACUnit` / `RequantUnit` | 硬件功能单元 |
| layers.py | 7 个层类，含 `load_weight()` / `compute()` / `requant()` | Conv/DWconv/PWconv/PostProcess 等模块 |
| top_module.py | `TopModule`：串联所有层，管理数据流 | CNN.v 顶层 |
| run_inference.py | 推理入口：`--input N` / `--golden` / `--all` | — |
| test_golden.py | 逐层金标准对比（Testbench golden model） | — |
| README.md | 网络结构表、架构说明、使用方法 | — |

## 验证结果（全部 PASS）

```
Conv+ReLU      (32,20,4)   2560/2560  (100.0%)  误差=0  [ PASS ]
DWConv+ReLU    (32,18,2)   1152/1152  (100.0%)  误差=0  [ PASS ]
PWConv+ReLU    (32,18,2)   1152/1152  (100.0%)  误差=0  [ PASS ]
Flatten        (288,)       288/288   (100.0%)  误差=0  [ PASS ]
FC             (2,)           2/2     (100.0%)  误差=0  [ PASS ]
Sigmoid LUT    (2,)      FP32误差 3.54e-07       [ PASS ]
总 MAC 操作数：244,928 次
```

## 关键架构概念对应

- **ReLU 位置**：每层 Conv/DWConv/PWConv 的 `out_sram` 存储的是**重量化后、ReLU 前**的值（对应金标准文件内容），ReLU 在下一层**读取数据时**施加—— 对应 RTL 中 `RescaleReLu.v` 输出到 SRAM，再由下一模块的数据选择单元加 ReLU  
- **LineBuffer**：每个通道维护独立行缓冲，对应 RTL 中的多行寄存器堆  
- **重量化**：`(x × M0) >> n` 定点移位实现，对应 `RescaleReLu_Mult.v` + `RescaleReLu_ShifterReLu.v`

Made changes.

User: 如果我想通过这些python脚本学习掌握该CNN电路实现的架构原理，请问应该如何阅读？又如何运行脚本辅助学习？请将这些信息补充到README.md

GitHub Copilot: 正在将 [](file:///d%3A/Project/CNN-Accelerator/PyRTL-CNN/README.md) 中的 1 行替换为 164 行


```

```
已在 README.md 中补充了完整的学习指南，包含以下内容：

**推荐阅读顺序（7 步，循序渐进）：**

| 步骤 | 阅读内容 | 对应硬件概念 |
|---|---|---|
| 1 | `clamp_int8/16/32()` | 位宽截断/饱和 |
| 2 | `FeatureSRAM` / `WeightSRAM` | 片上 SRAM + 地址映射公式 |
| 3 | `LineBuffer` | 行缓冲 + 滑窗卷积实现原理 |
| 4 | `MACUnit` | reset/accumulate/get 乘累加流程 |
| 5 | `RequantUnit` | 定点化乘移位重量化 |
| 6 | `ConvLayer`（layers.py）| 三重 for 循环 = 完整卷积定义 |
| 7 | `TopModule.forward()`  | 全网络顺序数据流 + cycle_count 基准 |

**运行辅助学习的 4 种方式：**
1. `run_inference.py` — 观察每层特征图尺寸变化
2. `test_golden.py` — 修改参数后立即验证数值，建立计算直觉
3. `load_params.py` — 对照参数文件格式描述，理解权重组织方式
4. VS Code 断点调试 — 在 `forward()` 中暂停，交互式查询 SRAM 内容和 INT32 中间值

Made changes.