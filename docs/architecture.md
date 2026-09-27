# 代码结构

项目使用 GDScript、Godot场景和少量shader，不引入第三方运行时库。
本次整理优先分离资源依赖、运行工具和发布配置，未重写已验收的Bot算法。

| 目录/入口 | 职责 |
| --- | --- |
| `scenes/main.tscn`、`scripts/main.gd` | 训练场景、输入消费、固定模拟步、伤害/积分、设置联动 |
| `scripts/simulation/` | 120/240/360Hz时钟、积压与暂停保护 |
| `scripts/input/` | 原始鼠标增量、DPI换算、输入队列、配置校验与保存 |
| `scripts/actors/` | 玩家运动、Bot瞄准/步法/策略/预测；`static_target.gd`是Bot协调器 |
| `scripts/combat/` | 射线、伤害、护甲、积分、复盘、程序模型与合成音效 |
| `scripts/ui/` | HUD、参数帮助、复盘、准星绘制、镜片渲染与许可面板 |
| `scripts/maps/` | `.lgmap`校验、生成、碰撞、导航、文件管理 |
| `scripts/editor/` | 白盒编辑交互、六面推拉、选择描边 |
| `scripts/debug/` | 显式 `--probe`/`--benchmark` 启用的诊断，普通运行不采样 |
| `assets/materials/` | 项目材质shader |
| `assets/editor/icons/` | Lucide SVG及原许可证 |
| `resources/` | 移动规则与内置白盒示例 |
| `tests/`、`tools/` | 自动测试、可移植开发/导出脚本；不打入游戏 |

## 模型接口

`training_models.gd`暴露`create_robot()`、`create_rifle()`和`MUZZLE`。
角色骨架使用通用关节名，包含`pelvis`、`spine_01`、`head`、
双侧`clavicle/upperarm/hand/thigh/shin`，全部坐标在代码中定义。
步行动画使用手动推进的 AnimationPlayer，身体朝向与手部枪口位置由Bot协调器更新。
上身保持持枪姿态，腿部动画不驱动物理位移。

更换模型时应保留或适配这些接口，同时运行 `bot_appearance`、`player_features`、
`bot_controls`，验证面向、枪口、横向拉伸和确定性运动。
命中形状与外观独立，不能用视觉改变暗中扩大命中范围。

## 稳定性约束

- 鼠标位移不乘帧时间；开镜倍率在输入事件到达时影响灵敏度。
- 模拟与渲染分离；命中和积分使用同一固定模拟步的射线结果。
- 准星/曳光/镜片外观不重开回合，也不修改伤害。
- 地图导入只接受经过校验的几何数据，不执行地图中的脚本。
- 暂停/失焦清理持续输入与开镜状态。

`main.gd`、`trainer_hud.gd`与Bot协调器仍较大。后续可按设置绑定、HUD分页和
模型适配层逐步拆分；避免在首次开源整理时同时改动训练手感与大规模结构。
