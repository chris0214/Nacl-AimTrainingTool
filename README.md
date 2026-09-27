# Nacl Aim Training Tool

基于 Godot 的离线瞄准训练器，包含可调 Bot、连续跟枪、单发积分对练和白盒地图编辑器。

作者：**bilibili：克里斯提亚娜**（chris0214）。使用 AI 编程辅助开发。
源码与项目原创资源按 [MIT](LICENSE) 提供，第三方图标另见[来源与许可](THIRD_PARTY_NOTICES.md)。

## 功能

- 连续跟枪：300/600/1000血量、独立护甲模式、命中吸血与命中音效。
- 单发对练：25/50分结算，双方独立冷却；按住/切换开镜，镜内放大、边缘畸变和暗角。
- Bot：反应延迟、精度、步法预设、长短变向、斜向进退、绕侧、避墙及输入应对。
- 普通横移与进阶跳跃/空中控制；可调基础移速、加速或瞬时满速。
- DPI + cm/360、改键、分辨率、帧率/VSync、120/240/360Hz固定模拟。
- 准星与镜内分划自定义、实时预览、曳光开关、逐枪复盘和走位奖励。
- 白盒编辑器：Box、楼梯、斜坡、阻挡体积、六面推拉、吸附、撤销、保存及导入导出 `.lgmap`。

开源版提供**程序生成的训练机器人、黑色胶囊和青色胶囊**。
普通能量枪和单发狙击枪也是程序生成模型，不需要UE、FBX转换工具或外部素材下载。
默认使用黑色胶囊；在 Esc → Bot → 瞄准与体型切换外观。

## 开始使用

1. 安装 Godot **4.7.2 stable** 标准版；无需 .NET，使用 Compatibility 渲染器。
2. 克隆本仓库，在 Godot 项目管理器导入根目录 `project.godot`。
3. 等待首次导入完成，按 F5 运行项目（入口是 `scenes/main.tscn`）。

Windows 是当前验证平台。其他平台可以尝试运行源码，但输入、字体、窗口设置未全面验证。
运行不需要账号、网络服务或 MCP。

| 操作 | 默认按键 |
| --- | --- |
| 移动/开火 | WASD / 鼠标左键 |
| 单发模式开镜 | 鼠标右键 |
| 进阶跳跃 | 空格 |
| 设置/暂停 | Esc |
| 重开 | R |

Esc → 玩家 → 训练项目可以切换连续跟枪/单发积分对练。
更多操作见[使用说明](docs/user-guide.md)。

## 开发与测试

使用 Godot **console** 可执行文件。PowerShell 脚本接受任意安装位置，不依赖作者本机盘符：

```powershell
$env:GODOT = 'D:\Applications\Godot\Godot_console.exe' # 替换成自己的路径
.\tools\godot.ps1 -Task test
.\tools\godot.ps1 -Task editor
.\tools\godot.ps1 -Task play
```

若已将 `godot` 或 `godot4` 加入 PATH，可省略环境变量。
也可直接执行 `godot --editor --path .`。首次运行命令行测试前需要导入项目，
`-Task test` 会自动完成导入。

测试使用 `--integration`，不读写用户真实偏好；日志/截图写入忽略的 `artifacts/`。
默认脚本运行代表性回归集，其余专项测试可用 `-Tests` 指定，详见[开发说明](docs/development.md)。
自动测试通过不代表所有机器帧率或人类手感已验收。

## 导出 Windows

先安装与引擎版本一致的官方导出模板，然后：

```powershell
.\tools\godot.ps1 -Task export
```

输出 `build/NaclAimTrainingTool.exe`，资源内嵌，不需要旁边另放PCK。
**分发时请同时保留**生成的 `LICENSE`、`THIRD_PARTY_NOTICES.md`、
`LUCIDE_LICENSE.txt`、`GODOT_LICENSES.txt`。许可也可以从游戏内
Esc → 场景与声音 → 关于与许可查看。

源码不包含引擎、导出模板、缓存、下载目录、旧EXE、用户数据或历史开发截图。
提交代码前运行 `.\tools\audit-source.ps1` 检查当前待提交文件集。
发布前步骤见[发布检查](docs/releasing.md)。

## 数据与已知限制

开源版使用独立目录，Windows 默认在
`%APPDATA%\Nacl Aim Training Tool` 保存配置与 `maps/` 地图。
旧本地原型的配置不会自动迁移；可通过地图面板导入旧 `.lgmap`。

- 机器人四肢为视觉模型，命中范围是横向可拉伸的胶囊近似体，不是逐肢体命中盒。
- 镜内独立放大会增加开镜时渲染开销；可降低镜内渲染比例或恢复整幅放大。
- 暂未集成 NVIDIA Reflex；120/240/360Hz指模拟频率，不是显示器刷新率。
- 本地娱乐自瞄只作用于本训练器，不连接其他游戏，也不会计入正式训练胜局。
- 输入应对只能使用已经发生的本地输入，不能读取未来按键。
- 地图编辑器以静态白盒为主；不支持任意模型导入、布尔建模或复杂跳跃寻路。
- 复盘是统计与开火快照，不是录像，也不替代专业能力评估。

目录与模块职责见[架构说明](docs/architecture.md)。
