# Conv1 代码阅读指南（新手版）

## 1. 先看什么
按下面顺序看最容易理解：

1. `Conv1_Top.v`
2. `conv1_line_buffer.v`
3. `conv1_window_extract.v`
4. `MAC_Tree_77.v` + `MAC77_*.v`
5. `requant_relu_unit.v` + `requant_relu_vec32.v`
6. `tb_Conv1.v`

---

## 2. 顶层接口怎么理解
`Conv1_Top.v` 的端口分四组：

1. 控制：`start / busy / done`
2. 输入行 SRAM：`in_row_req / in_row_addr / in_row_data / in_row_valid`
3. 权重接口：`wgt_req / wgt_addr / wgt_data / bias_data / wgt_valid`
4. 输出：`out_valid / out_data`

其中 `out_data` 是 256bit，等于 32 个通道的 INT8：

- `out_data[7:0]` 是通道 0
- `out_data[255:248]` 是通道 31

---

## 3. 状态机在做什么
`Conv1_Top.v` 的 FSM 顺序固定：

1. `IDLE`：等待 `start`
2. `LOAD_WEIGHT`：读 32 组权重和偏置
3. `FILL_LB`：读 11 行输入，灌满行缓冲
4. `CALC_RUN`：做 20x4 个窗口计算
5. `DRAIN`：等待流水线最后几拍输出完
6. `DONE`：`done` 拉高 1 拍

---

## 4. 一次窗口计算的数据流
每个窗口（11x7）走下面这条链路：

1. `conv1_window_extract` 从行缓冲截取 77 个 INT8
2. 广播给 32 个 `MAC_Tree_77`
3. 每个 `MAC_Tree_77` 用自己的权重 + 偏置，输出 1 个 INT32
4. `requant_relu_vec32` 把 32 个 INT32 变成 32 个 INT8
5. `out_valid` 拉高时输出 1 个空间点的 32 通道结果

---

## 5. MAC 为什么分 3 级流水
在 `MAC77_Mult.v / MAC77_AddTree_s1.v / MAC77_AddTree_s2.v` 中：

1. 第 1 拍：77 路乘法
2. 第 2 拍：分组加法（10 组局部和）
3. 第 3 拍：总和 + bias

这样是为了减轻单拍组合路径，便于时序收敛。

---

## 6. TB 怎么跑
`tb_Conv1.v` 会：

1. 用 `$readmemh` 读 `input.txt / weight.txt / bias.txt`
2. 按 `req/valid` 协议喂给 DUT（带 0~2 拍随机延迟）
3. 在 `out_valid` 时把 32 通道输出写到 `hw_output.txt`

如果你要和 Python 对比，直接比 `hw_output.txt` 即可。

