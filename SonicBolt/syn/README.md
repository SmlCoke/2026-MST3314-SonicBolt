# 各版本的逻辑综合记录


| 服务器上的版本号 | 对应 Git 仓库版本 |迭代周期 | 双帧缓存 | 半窗缓存 | 备注 | 是否已综合 |
| --- | --- | --- | --- | --- | --- | --- |
| syn/baseline | SonicBolt-v5.3 CNN_v1.2 | 94 | ✅️ | ❌️ | 作为后续对比的基线版本 | ✅️ |
| CNN-v1.3 | ❌️(中间态) | 103 | ✅️ | ✅️ | 该版本目前 fc 和 sigmoid 层的 SRAM 仍然是reg实现的行为模型 | ✅️ |
| CNN-v1.3_2 | SonicBolt-v5.4 CNN_v1.3 | 103 | ✅️ | ✅️ | 全 SRAM 实现 | ✅️  |
| CNN-v1.4 | ❌️(中间态) | 82 | ✅️ | ✅️ | 较为复杂的控制逻辑 | ❌️ 废除 |
| CNN-v1.4_2 | SonicBolt-v5.5 CNN_v1.4 | 89 | ✅️ | ✅️ | 更简单的控制逻辑 | ✅️ |
| CNN-PD-v1.0 | SonicBolt-PD-v1.0 CNN-PD-v1.0 | 89 | ✅️ | ✅️ | 删除权重/偏置SRAM写接口 | ✅️ |
| CNN-Lite-v1.0 | SonicBolt-Lite-v1.0 CNN-Lite-v1.0 | 89 | ✅️ | ✅️ | Preview, 删除权重/偏置SRAM，采用ROM实现 | ✅️ |


- baseline: 对应 SonicBolt v5.3, CNN-v1.2，作为后续对比的基线版本
- v1.3: 对应 SonicBolt v5.4, CNN-v1.3，在 SonicBolt v5.3 的基础上增加了半窗缓存机制，砍掉2464个乘法器，综合时间从14h缩短为7h，该版本目前 fc 和 sigmoid 层的 SRAM 仍然是reg实现的行为模型，下一个版本将替换为真实模型。（注意，此时虽然称作 SonicBolt v5.4, CNN-v1.3，但是 Git/GitHub 仓库上的对应版本是已经替换了 SRAM 的版本，后续做该版本回归综合时直接综合 Git/GitHub 的版本才能起到控制变量的效果）
- v1.3_2：GitHub 仓库的真正 SonicBolt v5.4 CNN-v1.3
- v1.4: 将 v1.3 的迭代周期由 103 逼近到 82，同时将 SRAM 行为级模型替换为真实的 SRAM，但是这一版控制逻辑较为复杂，可能最终不会采用
- v1.4_2: 对应 SonicBolt v5.5, CNN-v1.4，更简单的控制逻辑，迭代周期为89
- PD-v1.0: 在 SonicBolt v5.5 CNN-v1.4 的基础上删除权重/偏置SRAM写接口，采用ROM实现，迭代周期不变
- Lite-v1.0: 作为预览版本，删除权重/偏置SRAM，采用ROM实现，迭代周期不变