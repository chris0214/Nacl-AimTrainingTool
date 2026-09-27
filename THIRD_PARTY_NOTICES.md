# 来源与许可

## 本项目

项目代码、程序生成的训练机器人/能量枪/狙击枪、合成声音、白盒几何与材质：
Copyright (c) 2026 chris0214，按根目录 `LICENSE`（MIT）提供。
作者：bilibili：克里斯提亚娜。开发过程使用了 AI 编程辅助。

模型由 `scripts/combat/training_models.gd` 和 `sniper_model.gd` 生成。
机器人骨架的关节位置、简单几何和正弦步行动画在代码中定义。
它不是从其他游戏模型减面、导出或修改而来。

## Lucide 图标

位置：`assets/editor/icons/*.svg`。
来源：https://lucide.dev/ ，https://github.com/lucide-icons/lucide 。
作者：Lucide contributors；部分图标源自 Cole Bemis 的 Feather。
许可：ISC，部分 Feather 图标 MIT；完整声明保留在
`assets/editor/icons/LICENSE`。本项目只将图标描边颜色改为浅灰。
源码保留SVG，运行时通过Godot资源加载器读取导入纹理，支持独立导出包。

## Godot Engine

引擎按 MIT 提供，其第三方组件遵守各自许可。
源码仓库不附带引擎可执行文件、导出模板或引擎缓存。
导出游戏时随包提供 `GODOT_LICENSES.txt`，由实际运行导出的引擎
通过 `Engine.get_license_text()`、`get_copyright_info()` 和
`get_license_info()` 生成；也可在游戏设置中打开「关于与许可」查看。
官方许可与组件清单：https://godotengine.org/license/ 。

## 系统字体

界面调用操作系统已有字体及 Godot 字体回退机制。
仓库不附带 Microsoft YaHei、Bahnschrift 或 Consolas 字体文件。
非Windows系统的字形、布局和中文可用性取决于所装字体，目前主要验证Windows。

## 不包含的资源与参考边界

此源码树不包含旧本地原型中的 UE 角色、步枪、动画、贴图、导出脚本，
也不包含之前下载但未使用的 Kenney 或 Quaternius 资产。
不会从相邻旧工程自动加载这些文件。

Bot设计讨论曾参考 Quake III Arena 和 FpsAimForge 的反应延迟、
加权动作选择、时间/距离驱动步法等思路；本目录为GDScript实现，
未随本次整理复制这两个项目的源码。不能把本MIT许可解释为给第三方代码重新授权。
引入新的外部代码或素材时，应单独记录原作者、原始URL、固定版本和原许可。
