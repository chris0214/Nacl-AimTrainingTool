# 开发与验证

推荐Godot 4.7.2 stable，Compatibility/OpenGL。引擎与导出模板版本应一致。
源码主要使用Godot4通用API，但未承诺更早版本全部可用。

`tools/godot.ps1`提供play/editor/test/export，参数`-Godot`或环境变量`GODOT`
指向引擎console程序。不安装软件、不修改注册表或全局环境变量。

```powershell
.\tools\godot.ps1 -Task test -Tests bot_appearance,player_features,sniper_duel
```

也可从引擎命令行逐项运行：

```text
godot --headless --editor --path . --quit
godot --headless --path . --script tests/run_tests.gd -- --integration
godot --path . --script tests/bot_appearance.gd -- --integration
```

手动运行前创建`artifacts/`，原生窗口测试会写截图。
大部分`tests/*.gd`继承SceneTree，用`--script`启动；
`integration.gd`、`bot_controls.gd`、`roaming.gd`、`roaming_randomness.gd`
是场景脚本，应运行同名`.tscn`。测试退出码与日志中的`failures`都应检查，
Godot某些脚本错误可能仍返回0。

## 主要回归

- 基础：run_tests、trainer_settings、simulation_scoring。
- Bot：bot_appearance、player_features、bot_reaction、unified_aim、training_options、
  pressure_movement、spacing_flank、shared_speed_spacing。
- 战斗：armor_mode、combat_atmosphere、sniper_duel、sniper_scope。
- 外观：reticle_editor、shot_review_visuals、scope_optics；shader和像素对比需原生窗口。
- 地图：map_roundtrip、map_editor、editor_faces、editor_solid_workflow、
  editor_usability、smooth_stairs、stair_regression。

测试手动推进模拟，不能用它的FPS读数当性能结论。
`--integration`不加载个人配置，默认关闭真实偏好写入。
测试文件与截图不会随游戏导出；诊断入口位于`scripts/debug/`，默认关闭。

`tools/export-probe.gd`用于检查实际导出包。用相同版本的console引擎，
从源码目录之外运行 `--main-pack <导出EXE绝对路径> --script <此脚本绝对路径> -- --integration`。
它检查模型、许可、内置地图、导入图标、镜片和地图编辑器；不让测试回退到源码文件。
发布模板可能不支持`--script`，不能把直接给EXE传此参数当成验证通过。
另外单独运行EXE验证正常启动。

## 贡献

提交行为变化时说明复现步骤、预期结果、覆盖测试和未测试边界。
保持固定模拟步、确定性随机流、配置格式兼容和地图文件校验。
新增第三方代码或资源必须提供来源与完整许可，不提交本机数据、
编辑器缓存、密钥、导出模板或未知授权素材。
项目逻辑MIT；图标等第三方资源不能用项目LICENSE覆盖原作者声明。
