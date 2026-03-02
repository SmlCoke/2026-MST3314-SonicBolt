一、总体要求：

1. 不允许使用 PyTorch、TensorFlow、NumPy 等任何深度学习或向量化库
2. 所有计算必须使用纯 Python for 循环实现
3. 代码结构风格必须接近 RTL 可综合风格
4. 明确区分：

   * feature SRAM
   * weight SRAM
   * line buffer
   * MAC 单元
   * Requant 单元
   * 控制模块
5. 所有数据必须显式标注位宽：

   * 输入：INT8
   * 权重：INT8
   * 偏置：INT16
   * 累加过程：INT32
   * 输出：INT8
6. 不考虑物理设计与时序，只实现功能行为模型

二、网络结构必须严格实现如下结构：

Input (1,30,10)
→ Conv (32,1,11,7)
→ ReLU
→ Depthwise Conv (32,1,3,3)
→ ReLU
→ Pointwise Conv (32,32,1,1)
→ ReLU
→ Maxpool (2x2 stride 2)
→ Flatten (288)
→ FC (2,288)
→ Sigmoid

三、重量化实现方式：

使用如下公式：

$M = M_0 \times 2^{-n}$

要求：

* M0 为 INT16
* n 为整数
* 通过移位实现
* 不允许使用浮点乘法
* 每层使用独立的 (M0, n)

四、参数加载方式：
网络模型参数和输入特征图都从仓库 MiniCNN/sim/文件夹下读取，由于该文件夹下文件非常多，所以你需要首先实现一个参数加载脚本，同时最好生成一个参数的说明文档，说明MiniCNN/sim/文件夹每个参数文件的内容和格式。

五、架构风格要求：

1. 每一层必须封装为一个类
2. 每个类包含：

   * load_weight()
   * compute()
   * requant()
3. 设计一个 TopModule 类

   * 包含所有 layer
   * 顺序调用
4. 可选：

   * 增加 cycle 计数器
   * 模拟流水线推进
   * 每个 stage 明确输入输出 buffer

六、代码目标：

代码应具备以下作用：

* 可直接用于 RTL 结构映射
* 可作为 Testbench golden model
* 结构清晰
* 数据流清晰
* 每一层输入输出尺寸必须打印验证

