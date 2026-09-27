extends CanvasLayer

signal resumed
signal restarted
signal mode_changed(advanced: bool)
signal sensitivity_changed(value: float)
signal fov_changed(value: float)
signal frame_limit_changed(value: int)
signal quit_requested
signal bot_setting_changed(key: String, value: float)
signal bot_attack_changed(enabled: bool)
signal preference_changed(key: String, value: Variant)
signal binding_changed(action: String, code: int)
signal display_requested(fullscreen: bool, resolution: Vector2i)
signal display_confirmed
signal display_reverted
signal hit_sound_preview
signal armor_sound_preview(own: bool)
signal maps_requested
signal map_editor_requested
signal review_requested

const SETTINGS = preload("res://scripts/actors/bot_settings.gd")
const PREFS = preload("res://scripts/input/trainer_settings.gd")
const CYAN := Color("#79e8e2")
const CORAL := Color("#ff958b")
const GOLD := Color("#d4ba72")
const AUTHOR_CREDIT := "作者：bilibili：克里斯提亚娜"
var root: Control
var panel: PanelContainer
var dimmer: ColorRect
var crosshair: Control
var mode_label: Label
var phase_label: Label
var stats_label: Label
var training_score_label: Label
var performance_label: Label
var bot_state_label: Label
var player_health_value: Label
var target_health_value: Label
var timer_label: Label
var round_result_label: Label
var pause_title: Label
var mode_normal: Button
var mode_advanced: Button
var bot_controls: Dictionary = {}
var bot_sliders: Dictionary = {}
var attack_toggle: CheckButton
var bot_accuracy_label: Label
var aim_profile_label: Label
var bot_behavior_label: Label
var number_font: SystemFont
var advanced := false
var tabs: TabContainer
var preference_controls: Dictionary = {}
var binding_buttons: Dictionary = {}
var binding_target := ""
var score_labels: Array[Label] = []
var resolution_select: OptionButton
var window_mode: OptionButton
var display_apply: Button
var display_keep: Button
var display_back: Button
var display_status: Label
var setting_status: Label
var mouse_readout: Label
var live_display: Label
var live_fov: Label
var roaming_toggle: CheckButton
var editor_callbacks: Dictionary = {}
var window_limit := Vector2i(10000, 10000)
var resolution_label: Label
var speed_label: Label
var player_speed_readout: Label
var body_width_buttons: Dictionary = {}
var review_panel: PanelContainer
var help_markers: Dictionary = {}
var bot_sections: Dictionary = {}
var bot_section_buttons: Dictionary = {}
var setting_rows: Dictionary = {}
var armor_numbers: Array[Label] = []
var armor_bars: Array[ProgressBar] = []
var armor_active := false
var health_block: HBoxContainer
var armor_overlay: Control
var armor_controls: VBoxContainer
var weapon_title: Label
var ammo_label: Label
var single_shot := false
var health_captions: Array[Label] = []
var scope_overlay: Control
var scope_readout: Label
var crosshair_color := Color("#f6fff8")
var crosshair_width := 2.0
var crosshair_dot := 1.5
const RETICLE = preload("res://scripts/ui/reticle_style.gd")
var reticle_values := RETICLE.DEFAULTS.duplicate()
var preview_box: VBoxContainer
var reticle_preview: Control
var visual_sliders: Dictionary = {}


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("#eceeed"))
	root.theme = theme
	number_font = SystemFont.new()
	number_font.font_names = PackedStringArray(["Bahnschrift", "Consolas"])
	number_font.font_weight = 700
	armor_overlay = preload("res://scripts/ui/armor_overlay.gd").new()
	root.add_child(armor_overlay)
	scope_overlay = preload("res://scripts/ui/scope_overlay.gd").new()
	root.add_child(scope_overlay)
	_build_hud()
	_build_panel()
	review_panel = preload("res://scripts/ui/round_review_panel.gd").new()
	root.add_child(review_panel)
	review_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	review_panel.offset_left = -420
	review_panel.offset_right = 420
	review_panel.offset_top = -320
	review_panel.offset_bottom = 320
	review_panel.next_round.connect(func(): restarted.emit())
	review_panel.settings_requested.connect(func():
		hide_review()
		set_paused(true))
	get_viewport().size_changed.connect(func(): call_deferred("_fit_panel"))
	call_deferred("_fit_panel")


func _fit_panel() -> void:
	var viewport_size := root.get_rect().size
	panel.pivot_offset = panel.size * 0.5
	var canvas_scale := float(get_window().size.y) / maxf(1.0, viewport_size.y)
	var fit := minf((viewport_size.x - 28.0) / panel.size.x, (viewport_size.y - 28.0) / panel.size.y)
	panel.scale = Vector2.ONE * minf(fit, clampf(1.0 / maxf(canvas_scale, 0.01), 1.0, 1.4))
	if is_instance_valid(review_panel):
		review_panel.pivot_offset = review_panel.size * 0.5
		review_panel.scale = panel.scale


func _build_hud() -> void:
	var scores := VBoxContainer.new()
	scores.position = Vector2(28, 24)
	scores.add_theme_constant_override("separation", 3)
	root.add_child(scores)
	for index in 2:
		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.04, 0.045, 0.80)
		style.border_color = CYAN if index == 0 else GOLD
		style.border_width_left = 3
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		row.add_theme_stylebox_override("panel", style)
		scores.add_child(row)
		var line := HBoxContainer.new()
		row.add_child(line)
		var name_label := _label("PLAYER" if index == 0 else "BOT", 19)
		name_label.custom_minimum_size.x = 170
		line.add_child(name_label)
		var score := _label("0", 22)
		score.custom_minimum_size.x = 54
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score.add_theme_font_override("font", number_font)
		line.add_child(score)
		score_labels.append(score)
	timer_label = _label("00:00", 28)
	timer_label.add_theme_font_override("font", number_font)
	_outline(timer_label)
	scores.add_child(timer_label)
	mode_label = _label("训练 / 普通", 13)
	_outline(mode_label)
	scores.add_child(mode_label)
	phase_label = _label("准备", 14)
	phase_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	phase_label.offset_left = -300
	phase_label.offset_right = -28
	phase_label.offset_top = 56
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_outline(phase_label)
	root.add_child(phase_label)
	performance_label = _label("", 20)
	performance_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	performance_label.offset_left = -300
	performance_label.offset_right = -28
	performance_label.offset_top = 24
	performance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_outline(performance_label)
	root.add_child(performance_label)
	var health := HBoxContainer.new()
	health_block = health
	health.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	health.offset_left = -310
	health.offset_right = 310
	health.offset_top = -136
	health.offset_bottom = -24
	health.add_theme_constant_override("separation", 22)
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(health)
	player_health_value = _health_number(health, "PLAYER  +", CYAN)
	var weapon := VBoxContainer.new()
	weapon.custom_minimum_size.x = 144
	weapon.alignment = BoxContainer.ALIGNMENT_CENTER
	health.add_child(weapon)
	weapon_title = _label("LIGHTNING", 12)
	weapon_title.modulate = GOLD
	weapon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(weapon_title)
	weapon.add_child(weapon_title)
	var ammo := _label("∞", 46)
	ammo_label = ammo
	ammo.modulate = GOLD
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(ammo)
	weapon.add_child(ammo)
	target_health_value = _health_number(health, "BOT  +", GOLD)
	speed_label = _label("PLAYER  0.00 m/s", 17)
	speed_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	speed_label.offset_left = -180
	speed_label.offset_right = 180
	speed_label.offset_top = -166
	speed_label.offset_bottom = -140
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_override("font", number_font)
	_outline(speed_label)
	root.add_child(speed_label)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_left = 28
	bottom.offset_top = -81
	bottom.offset_bottom = -24
	root.add_child(bottom)
	stats_label = _label("", 14)
	_outline(stats_label)
	bottom.add_child(stats_label)
	training_score_label = _label("", 14)
	_outline(training_score_label)
	bottom.add_child(training_score_label)
	bot_state_label = _label("", 13)
	_outline(bot_state_label)
	bottom.add_child(bot_state_label)
	crosshair = Control.new()
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)
	round_result_label = _label("", 30)
	round_result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	round_result_label.offset_left = -220
	round_result_label.offset_right = 220
	round_result_label.offset_top = -90
	round_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(round_result_label)
	root.add_child(round_result_label)


func _health_number(parent: HBoxContainer, title: String, color: Color) -> Label:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 216
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	var caption := _label(title, 13)
	health_captions.append(caption)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.modulate = color
	_outline(caption)
	box.add_child(caption)
	var number := _label("1000", 62)
	number.custom_minimum_size = Vector2(216, 78)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", number_font)
	_outline(number, 6)
	box.add_child(number)
	var armor := _label("SHIELD  200", 20)
	armor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	armor.add_theme_font_override("font", number_font)
	armor.modulate = Color("#a8dbff")
	_outline(armor)
	box.add_child(armor)
	armor.hide()
	armor_numbers.append(armor)
	var armor_bar := ProgressBar.new()
	armor_bar.custom_minimum_size = Vector2(216, 4)
	armor_bar.show_percentage = false
	var armor_fill := StyleBoxFlat.new()
	armor_fill.bg_color = Color("#83cfff")
	var armor_back := StyleBoxFlat.new()
	armor_back.bg_color = Color(0.05, 0.07, 0.09, 0.8)
	armor_bar.add_theme_stylebox_override("fill", armor_fill)
	armor_bar.add_theme_stylebox_override("background", armor_back)
	box.add_child(armor_bar)
	armor_bar.hide()
	armor_bars.append(armor_bar)
	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 3
	rule.color = color
	box.add_child(rule)
	return number


func _build_panel() -> void:
	dimmer = ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.015, 0.02, 0.025, 0.65)
	root.add_child(dimmer)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -420
	panel.offset_right = 420
	panel.offset_top = -320
	panel.offset_bottom = 320
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202322")
	style.border_color = Color("#535955")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)
	pause_title = _label("训练设置", 24)
	layout.add_child(pause_title)
	tabs = TabContainer.new()
	preview_box = VBoxContainer.new()
	preview_box.add_theme_constant_override("separation", 2)
	layout.add_child(preview_box)
	var preview_toolbar := HBoxContainer.new()
	preview_box.add_child(preview_toolbar)
	preview_toolbar.add_child(_label("实时预览", 16))
	var preview_background := OptionButton.new()
	for title in ["深色背景", "浅色背景", "场景示意"]:
		preview_background.add_item(title)
	preview_toolbar.add_child(preview_background)
	reticle_preview = preload("res://scripts/ui/reticle_preview.gd").new()
	preview_box.add_child(reticle_preview)
	preview_background.item_selected.connect(func(index: int):
		reticle_preview.background = index
		reticle_preview.configure(reticle_values))
	preview_box.hide()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)
	tabs.tab_changed.connect(func(index: int):
		_cancel_binding()
		preview_box.visible = index == 5
		call_deferred("_fit_panel"))
	var bot := _tab("Bot")
	var heading := HBoxContainer.new()
	bot.add_child(heading)
	mode_normal = _button("普通", func(): mode_changed.emit(false))
	mode_advanced = _button("进阶", func(): mode_changed.emit(true))
	var group := ButtonGroup.new()
	for button in [mode_normal, mode_advanced]:
		button.toggle_mode = true
		button.button_group = group
		heading.add_child(button)
	mode_normal.set_pressed_no_signal(true)
	attack_toggle = CheckButton.new()
	attack_toggle.text = "主动开火"
	attack_toggle.button_pressed = true
	attack_toggle.toggled.connect(func(value: bool): bot_attack_changed.emit(value))
	heading.add_child(attack_toggle)
	_preference_choice(bot, "movement_preset", "步法预设", PREFS.FOOTWORK.LABELS)
	for index in PREFS.FOOTWORK.LABELS.size():
		preference_controls.movement_preset.set_item_tooltip(index, PREFS.FOOTWORK.EXPLANATIONS[index])
	preference_controls.movement_preset.tooltip_text = PREFS.FOOTWORK.EXPLANATIONS[0]
	_bot_control(bot, "aim_level", "瞄准水平", "/ 100", 1, "统一调整精度、反应和修正速度；不是实际命中百分比。100 为无延迟硬锁，仍遵守射程与遮挡。")
	_bot_control(bot, "move_speed", "移动速度", "m/s", 0.1, "实际速度上限；共同基础移速改变时按比例调整，最高20 m/s。0 原地瞄准；进阶空中保留空控。")
	_bot_control(bot, "engagement_distance", "交战距离基准", "m", 0.1, "动态施压用它与远近幅度生成进退范围，不会一直退回这个距离。保持距离风格则围绕它拉开。固定横移时不生效。")
	player_speed_readout = _label("", 13)
	player_speed_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_speed_readout.modulate = CYAN
	bot.add_child(player_speed_readout)
	var aiming := _bot_section(bot, "aim", "瞄准与体型")
	var moving := _bot_section(bot, "movement", "游走与跳跃")
	var footwork := _bot_section(bot, "footwork", "步法细调")
	var reacting := _bot_section(bot, "input", "输入应对")
	_preference_choice(aiming, "bot_model", "目标外观", ["训练机器人", "黑色胶囊", "青色胶囊"])
	preference_controls.bot_model.tooltip_text = "只切换外观，不改变步法、体宽、伤害或瞄准水平。胶囊与命中体同尺寸，保留敌方光束。"
	_preference_toggle(aiming, "bot_animation", "人形步行动画")
	preference_controls.bot_animation.tooltip_text = "关闭后保持持枪姿态；只影响外观，不改变实际移动。"
	roaming_toggle = CheckButton.new()
	roaming_toggle.text = "游走对练"
	roaming_toggle.button_pressed = true
	roaming_toggle.toggled.connect(func(value: bool): preference_changed.emit("roaming", value))
	moving.add_child(roaming_toggle)
	_preference_choice(moving, "roam_style", "游走风格", ["保持距离", "动态施压"])
	preference_controls.roam_style.tooltip_text = "动态施压交替斜向压近、侧绕与拉远，真正贴脸才脱离。保持距离保留旧逻辑。不会更改瞄准、步法预设或移速。"
	var widths := HBoxContainer.new()
	var width_group := ButtonGroup.new()
	width_group.allow_unpress = true
	for preset in [["简单", 1.6], ["一般", 1.25], ["困难", 1.0]]:
		var width: float = preset[1]
		var button := _button(preset[0], func():
			if commit_edits():
				bot_controls.body_width.value = width
			else:
				sync_body_width(bot_controls.body_width.value))
		button.toggle_mode = true
		button.button_group = width_group
		button.tooltip_text = "体宽 %.2f×；只改变体型与命中宽度，不改变移动和瞄准参数。" % width
		widths.add_child(button)
		body_width_buttons[width] = button
	_setting_row(aiming, "体型难度", widths)
	_bot_control(aiming, "body_width", "横向体宽", "×", 0.01, "模型与命中范围同步横向拉伸；高度和前后厚度不变。")
	_bot_control(moving, "aggression", "进攻倾向", "%", 1, "更高时更常压近玩家；不改变瞄准水平。")
	_bot_control(moving, "flank_chance", "绕背倾向", "%", 1, "延迟观察玩家朝向，有侧身空当才尝试绕后。0 关闭；每次最多 3 秒，成功、被盯住或受阻就结束并冷却。")
	_bot_control(moving, "distance_variation", "远近变化幅度", "m", 0.1, "动态施压时越大越允许压近并拉远；受场地、玩家移动和阶段时长影响，不保证每段走满。")
	_bot_control(moving, "orbit_chance", "横移倾向", "%", 1, "横移始终为主；提高 AD 对枪占比，进退仍保持 WA/WD 或 SA/SD 斜向移动。")
	_bot_control(aiming, "aim_turn_rate", "转身速度上限", "°/s", 1, "非满档的水平/垂直合成角速度预算，实际值随瞄准水平派生；角加速度同步派生。100 硬锁不受限制。")
	aim_profile_label = _label("", 13)
	aim_profile_label.modulate = CYAN
	aiming.add_child(aim_profile_label)
	update_aim_profile(SETTINGS.DEFAULTS.aim_level)
	_preference_toggle(aiming, "bot_perception", "视野与遮挡感知")
	preference_controls.bot_perception.tooltip_text = "非100档只跟踪220度水平视野内、躯干中心无遮挡的目标；丢失后短暂记忆并搜索。100档仍硬锁但不穿墙。"
	_preference_toggle(aiming, "bot_motion_aim", "移动瞄准扰动")
	preference_controls.bot_motion_aim.tooltip_text = "自身急转和落地短暂增大非100档的偏差；不改变伤害。"
	_bot_control(moving, "turn_frequency", "游走变向节奏", "Hz", 0.1, "原有步法的变向节奏，以及游走进退周期。选用新步法后，左右步长由步法细调独立控制。")
	_bot_control(moving, "strafe_extent", "固定横移 / 半幅", "m", 0.1, "关闭游走对练后生效；游走模式使用整个场地。")
	_bot_control(moving, "randomness", "游走随机性", "%", 1, "原有步法的长短与快慢变化，以及游走策略的随机程度；新步法的长短和变速使用独立参数。")
	_bot_control(moving, "jump_interval", "进阶 / 跳跃间隔", "s", 0.1, "随机起跳间隔的基准。只在进阶模式生效。")
	_bot_control(moving, "air_control", "进阶 / 空中加速度", "m/s²", 1, "0 保留起跳时横向惯性；更高值允许更急的空中变向。")
	_preference_toggle(reacting, "reactive_bot", "启用输入应对")
	_preference_toggle(reacting, "bot_adaptation", "短期战术适应")
	preference_controls.bot_adaptation.tooltip_text = "在输入应对开启时，记忆最近约3秒的延迟输入与伤害反馈；改变动作权重和进退倾向，重开清空。"
	preference_controls.reactive_bot.tooltip_text = "开启所选输入模型。只读取已经发生的本地输入；关闭不影响基础瞄准、避墙和保持距离。"
	_build_footwork_controls(footwork, reacting)
	_bot_control(reacting, "reaction_strength", "输入应对强度", "%", 1, "触发走位应对的概率强度；0不触发走位应对，但不关闭预测对瞄准的影响。完全关闭请关闭启用输入应对。")
	_bot_control(reacting, "reaction_delay", "战术反应延迟", "ms", 1, "用于移动输入和绕背朝向感知。即时模式跳过输入等待，但绕背仍使用此延迟；预测实验会间接影响瞄准补偿。")
	bot_accuracy_label = _label("BOT 实际命中  --", 14)
	aiming.add_child(bot_accuracy_label)
	bot_behavior_label = _label("", 13)
	aiming.add_child(bot_behavior_label)
	bot.add_child(_button("恢复 Bot 默认值", _reset_bot_controls))
	var mouse := _tab("键鼠")
	_preference_number(mouse, "dpi", "鼠标 DPI", 50, 64000, 1, 800)
	_preference_number(mouse, "cm360", "转身距离 / cm/360", 1, 500, 0.000001, PREFS.DEFAULTS.cm360)
	mouse_readout = _label("", 14)
	mouse.add_child(mouse_readout)
	_preference_toggle(mouse, "invert_y", "反转 Y 轴")
	var raw := CheckButton.new()
	raw.text = "原始鼠标输入 / 捕获模式"
	raw.button_pressed = true
	raw.disabled = true
	raw.tooltip_text = "Windows 捕获模式使用原始位移；screen_relative 不随分辨率缩放。DPI 请填写鼠标驱动中的实际值。"
	mouse.add_child(raw)
	var keys := GridContainer.new()
	keys.columns = 4
	keys.add_theme_constant_override("h_separation", 18)
	keys.add_theme_constant_override("v_separation", 6)
	mouse.add_child(keys)
	var titles := {"forward": "前进", "back": "后退", "left": "向左", "right": "向右",
		"jump": "跳跃", "fire": "开火", "restart": "重开练习", "scope": "开镜"}
	for action in PlayerInput.DEFAULT_BINDINGS:
		keys.add_child(_label(titles[action], 14))
		var button := _button("", func(): _capture_binding(action))
		button.custom_minimum_size.x = 200
		button.tooltip_text = "按下要绑定的键或鼠标侧键；重复绑定会交换。Escape 取消。"
		keys.add_child(button)
		binding_buttons[action] = button
	mouse.add_child(_button("恢复键鼠默认值", func():
		preference_controls.dpi.value = PREFS.DEFAULTS.dpi
		preference_controls.cm360.value = PREFS.DEFAULTS.cm360
		preference_controls.invert_y.button_pressed = false
		for action in PlayerInput.DEFAULT_BINDINGS:
			binding_changed.emit(action, PlayerInput.DEFAULT_BINDINGS[action])))
	var display := _tab("显示")
	display.add_theme_constant_override("separation", 8)
	var fov_mode := OptionButton.new()
	fov_mode.add_item("垂直")
	fov_mode.add_item("水平 / 16:9 基准")
	fov_mode.item_selected.connect(func(index: int):
		if commit_edits():
			preference_changed.emit("fov_mode", index)
		else:
			fov_mode.select(int(fov_mode.get_meta("applied", 0))))
	preference_controls.fov_mode = fov_mode
	_setting_row(display, "FOV 基准", fov_mode)
	_preference_number(display, "fov", "FOV / 度", 30, 150, 0.01, 75)
	live_fov = _label("", 13)
	display.add_child(live_fov)
	_preference_number(display, "fps", "帧率上限 / 0 为不限", 0, 1000, 1, 240)
	preference_controls.fps.tooltip_text = "允许 0 或 20–1000 FPS；与物理模拟频率独立。"
	_preference_choice(display, "simulation_hz", "模拟频率", ["120 Hz", "240 Hz", "360 Hz"], [120, 240, 360])
	preference_controls.simulation_hz.tooltip_text = "每秒物理更新次数，不是显示器刷新率。越高CPU开销越大；切换后重开本轮，射速和伤害不随频率增加。"
	_preference_toggle(display, "vsync", "垂直同步")
	window_mode = OptionButton.new()
	window_mode.add_item("窗口")
	window_mode.add_item("无边框全屏")
	window_mode.item_selected.connect(func(_index: int): _refresh_resolution_options())
	_setting_row(display, "显示模式", window_mode)
	resolution_select = OptionButton.new()
	for size in PREFS.RESOLUTIONS:
		resolution_select.add_item("%d × %d" % [size.x, size.y])
	resolution_select.select(2)
	resolution_label = _setting_row(display, "窗口分辨率", resolution_select)
	var buttons := HBoxContainer.new()
	display.add_child(buttons)
	display_apply = _button("应用显示设置", func():
		if commit_edits():
			display_requested.emit(window_mode.selected == 1, PREFS.RESOLUTIONS[resolution_select.selected]))
	buttons.add_child(display_apply)
	display_keep = _button("保留", func(): display_confirmed.emit())
	buttons.add_child(display_keep)
	display_back = _button("还原", func(): display_reverted.emit())
	buttons.add_child(display_back)
	display_keep.hide()
	display_back.hide()
	display_status = _label("", 14)
	display.add_child(display_status)
	live_display = _label("", 13)
	live_display.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	display.add_child(live_display)
	live_display.tooltip_text = "独立低延迟功能尚未集成；VSync 与帧率上限仍可单独设置。"
	var player_tab := _tab("玩家")
	_preference_choice(player_tab, "weapon_mode", "训练项目", ["连续跟枪", "单发积分对练"])
	preference_controls.weapon_mode.tooltip_text = "单发：开火或开镜开始对练，命中1分，无血量和吸血。双方独立出枪；你不开枪，Bot也会继续攻击。切换后重开。"
	_preference_choice(player_tab, "score_limit", "单发目标分数", ["25分", "50分"], [25, 50])
	preference_controls.score_limit.tooltip_text = "任一方先到目标分数结算；同一模拟步同时达标算平局。走位奖励不计入胜负比分。修改后重开。"
	_preference_number(player_tab, "sniper_cooldown", "玩家拉栓时间 / s", 0.3, 2.5, 0.05, 0.9)
	preference_controls.sniper_cooldown.tooltip_text = "仅控制玩家两枪最短间隔。需松开再点击；冷却时点击不缓存，拉栓不强制退镜。修改后重开。"
	_preference_number(player_tab, "bot_sniper_cooldown", "Bot 拉栓时间 / s", 0.3, 2.5, 0.05, 0.75)
	preference_controls.bot_sniper_cooldown.tooltip_text = "仅控制Bot两枪最短间隔；另受其瞄准和决策等待影响。不会等待玩家开火或与玩家轮流射击。修改后重开。"
	_preference_choice(player_tab, "scope_mode", "开镜方式", ["按住开镜", "点击切换"])
	preference_controls.scope_mode.tooltip_text = "按住：按下开镜、松开退镜。切换：点击开镜，再点退镜。默认右键，可在键鼠页改键。暂停、重开、结算或切换方式都会退镜。"
	_preference_number(player_tab, "scope_zoom", "开镜倍率", 1.5, 8.0, 0.5, 2.0)
	preference_controls.scope_zoom.tooltip_text = "默认右键开镜。倍率表示屏幕中心的真实放大比例；准星与射线方向不变。准星与曳光页可选择仅镜内放大、边缘畸变与镜内清晰度。"
	_preference_number(player_tab, "scope_sensitivity", "开镜灵敏度 / %", 10, 300, 1, 100)
	preference_controls.scope_sensitivity.tooltip_text = "先按倍率降低角度灵敏度，再乘此百分比。100%近似保持屏幕中心的小幅移动速度；并非保持原cm/360。下方显示实际镜内cm/360。"
	scope_readout = _label("", 13)
	scope_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_tab.add_child(scope_readout)
	_preference_number(player_tab, "sniper_volume", "单发枪声与拉栓 / %", 0, 100, 1, 45)
	preference_controls.sniper_volume.tooltip_text = "独立控制双方枪声和拉栓声；0静音。命中确认音沿用场景与声音页设置。"
	_preference_choice(player_tab, "combat_mode", "对练规则", ["纯血量", "护甲"])
	preference_controls.combat_mode.tooltip_text = "两种独立模式，分别记住耐久档位；切换后重开。护甲先承伤，溢出伤害扣生命；命中吸血只回复生命。"
	_preference_choice(player_tab, "health_pool", "双方生命", ["300", "600", "1000"], [300, 600, 1000])
	preference_controls.health_pool.tooltip_text = "纯血量模式的双方出生和吸血上限。修改后重开，不改变伤害和射速。"
	_preference_choice(player_tab, "armor_pool", "护甲总耐久",
		["300  /  100生命 + 200护甲", "600  /  200生命 + 400护甲", "1000  /  400生命 + 600护甲"], [300, 600, 1000])
	preference_controls.armor_pool.tooltip_text = "生命与护甲相加的总耐久。双方一致；护甲不自动恢复，吸血也不回甲。修改后重开。"
	armor_controls = VBoxContainer.new()
	armor_controls.add_theme_constant_override("separation", 8)
	player_tab.add_child(armor_controls)
	_preference_toggle(armor_controls, "armor_sound", "碎甲音效")
	preference_controls.armor_sound.tooltip_text = "敌方碎甲偏清脆，自身碎甲偏低沉；只在护甲从有到无时响一次。"
	_preference_number(armor_controls, "armor_volume", "碎甲音量 / %", 0, 100, 1, 55)
	preference_controls.armor_volume.tooltip_text = "独立于普通命中音量；0为静音，不影响碎甲判定。"
	_preference_toggle(armor_controls, "armor_effect", "第一人称护甲反馈")
	preference_controls.armor_effect.tooltip_text = "自身护甲受击时显示外围光片，碎甲时短暂裂纹；不覆盖屏幕中心、不震动镜头。"
	_preference_number(armor_controls, "armor_effect_strength", "护甲反馈强度 / %", 0, 100, 1, 50)
	preference_controls.armor_effect_strength.tooltip_text = "只影响第一人称外围效果透明度；0隐藏，不改变伤害。"
	var armor_preview := HBoxContainer.new()
	armor_controls.add_child(armor_preview)
	for own in [false, true]:
		armor_preview.add_child(_button("试听自身碎甲" if own else "试听敌方碎甲", func():
			if commit_edits():
				armor_sound_preview.emit(own)))
	_preference_toggle(player_tab, "round_review", "回合结束复盘")
	_preference_number(player_tab, "ad_bonus_weight", "走位加分上限 / %", 0, 20, 1, 10)
	preference_controls.ad_bonus_weight.tooltip_text = "命中时按实际横移速度奖励，最高为基础命中分的此百分比。单段前0.2米不加分；空走、撞墙、抖键不加分。0关闭；调整后重开。"
	preference_controls.round_review.tooltip_text = "结束后暂停并查看移动、瞄准和配合数据；不足样本不判断，开过自瞄不评价鼠标能力。"
	_preference_number(player_tab, "base_speed", "共同基础移速 / m/s", 2, 20, 0.1, 10)
	preference_controls.base_speed.tooltip_text = "玩家地面满速；修改时按比例调整Bot速度。保留加速时间和空中水平运动比例，不改变跳高、重力、反应延迟或伤害。"
	_preference_choice(player_tab, "instant_movement", "地面移动", ["加速度", "瞬时满速"])
	preference_controls.instant_movement.tooltip_text = "瞬时模式地面按键即满速，松键即停；进阶空中仍受惯性和空中加速度控制。"
	_preference_choice(player_tab, "assist_mode", "娱乐自瞄", ["关闭", "平滑", "线性"])
	preference_controls.assist_mode.tooltip_text = "按住开火时跟随视线可达、射程内的 Bot；不自动开枪、不穿墙，开启后的回合不计胜局。"
	_preference_number(player_tab, "assist_speed", "自瞄转向上限 / °/s", 30, 1440, 1, 720)
	_preference_number(player_tab, "assist_response", "平滑响应", 2, 40, 0.1, 12)
	preference_controls.assist_response.tooltip_text = "仅平滑模式生效；越大越快贴近目标。线性模式按固定角速度接近。"
	var atmosphere := _tab("场景与声音")
	var maps := HBoxContainer.new()
	atmosphere.add_child(maps)
	maps.add_child(_button("选择地图", func(): maps_requested.emit()))
	maps.add_child(_button("地图编辑器 / 返回编辑", func(): map_editor_requested.emit()))
	atmosphere.add_child(HSeparator.new())
	_preference_choice(atmosphere, "sky_style", "天空", ["摄影棚", "晴空", "暮色"])
	_preference_choice(atmosphere, "arena_style", "场地配色", ["浅灰", "深灰", "冷白"])
	_preference_toggle(atmosphere, "floor_grid", "地面网格")
	_preference_number(atmosphere, "scene_brightness", "场景亮度 / %", 50, 150, 1, 100)
	atmosphere.add_child(HSeparator.new())
	_preference_toggle(atmosphere, "hit_sound", "命中音效")
	_preference_choice(atmosphere, "hit_sound_style", "音色", ["轻敲", "金属", "电子"])
	_preference_number(atmosphere, "hit_volume", "命中音量 / %", 0, 100, 1, 45)
	atmosphere.add_child(_button("试听", func():
		if commit_edits():
			hit_sound_preview.emit()))
	var visuals := _tab("准星与曳光")
	_build_reticle_controls(visuals)
	atmosphere.add_child(HSeparator.new())
	atmosphere.add_child(_button("关于与许可", func():
		var dialog := preload("res://scripts/ui/license_panel.gd").new()
		root.add_child(dialog)
		dialog.popup_centered(Vector2i(700, 460))))
	_install_preference_help()
	setting_status = _label("", 13)
	layout.add_child(setting_status)
	layout.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	layout.add_child(footer)
	footer.add_child(_button("退出", func(): quit_requested.emit()))
	footer.add_child(_button("结束并复盘", func(): review_requested.emit()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var author := _label(AUTHOR_CREDIT, 12)
	author.modulate = Color(0.72, 0.76, 0.78, 0.82)
	author.tooltip_text = "本训练器作者"
	footer.add_child(author)
	footer.add_child(_button("重开练习", func(): restarted.emit()))
	var resume := _button("继续练习", func(): resumed.emit())
	resume.custom_minimum_size.x = 154
	resume.add_theme_color_override("font_color", CYAN)
	footer.add_child(resume)
	panel.hide()
	dimmer.hide()


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	return content


func _bot_section(parent: VBoxContainer, key: String, title: String) -> VBoxContainer:
	var button := Button.new()
	button.flat = true
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 34
	button.text = "▸ " + title
	button.set_meta("title", title)
	button.tooltip_text = "展开或收起此组参数"
	parent.add_child(button)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	parent.add_child(content)
	content.hide()
	bot_sections[key] = content
	bot_section_buttons[key] = button
	button.toggled.connect(func(expanded: bool):
		if not expanded and not commit_edits():
			button.set_pressed_no_signal(true)
			return
		content.visible = expanded
		button.text = ("▾ " if expanded else "▸ ") + str(button.get_meta("title"))
		if expanded:
			_reveal_bot_section(key)
		elif not bot_sections.values().any(func(section: VBoxContainer): return section.visible):
			tabs.get_child(0).set_deferred("scroll_vertical", 0))
	return content


func _reveal_bot_section(key: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if bot_sections[key].visible and panel.visible and tabs.current_tab == 0:
		tabs.get_child(0).scroll_vertical = roundi(bot_section_buttons[key].position.y)


func _setting_row(parent: VBoxContainer, title: String, control: Control) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var label := _label(title, 15)
	label.custom_minimum_size.x = 196
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 34
	row.add_child(control)
	return label


func _bot_control(parent: VBoxContainer, key: String, title: String, unit: String,
	step: float, explanation: String) -> void:
	var row := HBoxContainer.new()
	var slider := HSlider.new()
	var limits: Vector2 = SETTINGS.LIMITS[key]
	slider.min_value = limits.x
	slider.max_value = limits.y
	slider.step = step
	slider.value = SETTINGS.DEFAULTS[key]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 140
	slider.tooltip_text = explanation
	row.add_child(slider)
	var number := SpinBox.new()
	number.min_value = limits.x
	number.max_value = limits.y
	number.step = step
	number.value = SETTINGS.DEFAULTS[key]
	number.suffix = unit
	number.custom_minimum_size.x = 142
	number.tooltip_text = explanation
	row.add_child(number)
	var help := _help(explanation)
	row.add_child(help)
	help_markers[key] = help
	_setting_row(parent, title, row)
	bot_controls[key] = number
	bot_sliders[key] = slider
	setting_rows[key] = row.get_parent()
	slider.value_changed.connect(func(value: float): number.value = value)
	_track_editor(number, title, func(value: float):
		slider.set_value_no_signal(value)
		bot_setting_changed.emit(key, value))


func _preference_number(parent: VBoxContainer, key: String, title: String,
	low: float, high: float, step: float, initial: float) -> void:
	var number := SpinBox.new()
	number.min_value = low
	number.max_value = high
	number.step = step
	number.value = initial
	_track_editor(number, title, func(value: float): preference_changed.emit(key, value))
	preference_controls[key] = number
	_setting_row(parent, title, number)
	setting_rows[key] = number.get_parent()


func _preference_toggle(parent: VBoxContainer, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var toggle := CheckButton.new()
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.text = title
	toggle.toggled.connect(func(value: bool): preference_changed.emit(key, value))
	preference_controls[key] = toggle
	row.add_child(toggle)
	setting_rows[key] = row


func _preference_choice(parent: VBoxContainer, key: String, title: String, options: Array, ids: Array = []) -> void:
	var choice := OptionButton.new()
	for index in options.size():
		choice.add_item(options[index], int(ids[index]) if not ids.is_empty() else index)
	choice.item_selected.connect(func(index: int):
		if commit_edits():
			preference_changed.emit(key, bool(index) if key == "instant_movement" else choice.get_item_id(index))
		else:
			choice.select(choice.get_item_index(int(choice.get_meta("applied", choice.get_item_id(0))))))
	preference_controls[key] = choice
	_setting_row(parent, title, choice)
	setting_rows[key] = choice.get_parent()


func sync_preferences(values: Dictionary, bindings: Dictionary) -> void:
	for key in preference_controls:
		var control: Control = preference_controls[key]
		if control is ColorPickerButton:
			control.color = values[key]
		elif control is SpinBox:
			control.set_value_no_signal(values[key])
		elif control is CheckButton:
			control.set_pressed_no_signal(values[key])
		elif control is OptionButton:
			control.select(control.get_item_index(int(values[key])))
			control.set_meta("applied", values[key])
	for key in bot_controls:
		bot_controls[key].value = values[key]
	attack_toggle.set_pressed_no_signal(values.attack)
	roaming_toggle.set_pressed_no_signal(values.roaming)
	advanced = values.advanced
	mode_normal.set_pressed_no_signal(not advanced)
	mode_advanced.set_pressed_no_signal(advanced)
	sync_bindings(bindings)
	sync_display(values.fullscreen, values.resolution)
	update_mouse_readout(values.dpi, values.cm360)
	sync_body_width(values.body_width)
	update_aim_profile(values.aim_level)
	sync_training_options(values)


func update_aim_profile(level: float) -> void:
	var aim = preload("res://scripts/actors/bot_aim.gd")
	var immediate: bool = preference_controls.has("input_mode") and preference_controls.input_mode.selected == 1 \
		and preference_controls.reactive_bot.button_pressed
	aim_profile_label.text = "绝对锁定  /  0 ms" if level >= 100.0 else (
		"%s  /  感知 %.0f ms  /  修正 %.1f ms" % [
			"即时读键" if immediate else "延迟感知",
			0 if immediate else aim.delay_for_level(level), aim.correction_time(level) * 1000.0])


func sync_body_width(width: float) -> void:
	for preset in body_width_buttons:
		body_width_buttons[preset].set_pressed_no_signal(is_equal_approx(width, preset))


func update_player_tuning(speed: float, maximum: float, instant: bool) -> void:
	speed_label.text = "PLAYER  %.2f m/s" % speed
	player_speed_readout.text = "玩家速度  %.2f m/s  /  地面上限 %.2f m/s  /  %s" % [
		speed, maximum, "瞬时满速" if instant else "加速度"]


func sync_display(fullscreen: bool, resolution: Vector2i) -> void:
	window_mode.select(int(fullscreen))
	resolution_select.select(maxi(0, PREFS.RESOLUTIONS.find(resolution)))
	_refresh_resolution_options()


func update_mouse_readout(dpi: float, cm360: float) -> void:
	mouse_readout.text = "已生效  %d DPI  /  %.6f cm/360  /  %.9f °/count" % [
		roundi(dpi), cm360, PlayerInput.sensitivity_from_cm(dpi, cm360)]


func sync_bindings(bindings: Dictionary) -> void:
	for action in binding_buttons:
		var code: int = bindings[action]
		binding_buttons[action].text = OS.get_keycode_string(code) if code > 0 else (
			{-1: "鼠标左键", -2: "鼠标右键", -3: "鼠标中键", -8: "鼠标侧键 1", -9: "鼠标侧键 2"}.get(code, "鼠标"))


func _capture_binding(action: String) -> void:
	_cancel_binding()
	binding_target = action
	binding_buttons[action].text = "..."


func _cancel_binding() -> void:
	if binding_target != "":
		binding_target = ""
		binding_changed.emit("", 0)


func _input(event: InputEvent) -> void:
	if is_instance_valid(review_panel) and review_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			hide_review()
			set_paused(true)
		return
	if not panel.visible:
		return
	if binding_target == "":
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if commit_edits():
				resumed.emit()
		return
	var code := 0
	if event is InputEventKey and event.pressed and not event.echo:
		code = event.physical_keycode
	elif event is InputEventMouseButton and event.pressed:
		code = -event.button_index
	else:
		return
	get_viewport().set_input_as_handled()
	if code == KEY_ESCAPE:
		_cancel_binding()
	elif PlayerInput.valid_binding(code):
		var action := binding_target
		binding_target = ""
		binding_changed.emit(action, code)


func display_pending(seconds: float) -> void:
	var pending := seconds > 0.0
	display_keep.visible = pending
	display_back.visible = pending
	display_apply.disabled = pending
	window_mode.disabled = pending
	resolution_select.disabled = pending
	display_status.text = "保留当前显示设置？%d 秒后自动还原" % ceili(seconds) if pending else ""


func _reset_bot_controls() -> void:
	for key in bot_controls:
		bot_controls[key].remove_meta("draft")
		bot_controls[key].value = SETTINGS.DEFAULTS[key]
	for key in PREFS.FOOTWORK.DEFAULTS:
		preference_controls[key].remove_meta("draft")
	for key in ["prediction_horizon", "prediction_strength"]:
		preference_controls[key].remove_meta("draft")
	preference_changed.emit("movement_preset", 0)
	for key in ["reactive_bot", "bot_adaptation", "bot_perception", "bot_motion_aim",
		"input_mode", "prediction_horizon", "prediction_strength", "roaming", "roam_style", "attack", "bot_model", "bot_animation"]:
		preference_changed.emit(key, PREFS.DEFAULTS[key])


func _track_editor(number: SpinBox, title: String, callback: Callable) -> void:
	editor_callbacks[number] = callback
	number.set_meta("title", title)
	number.value_changed.connect(func(value: float):
		if not number.has_meta("draft"):
			callback.call(value))
	var edit := number.get_line_edit()
	edit.text_changed.connect(func(text: String): number.set_meta("draft", text))
	edit.text_submitted.connect(func(_text: String): _commit_editor(number))
	edit.focus_exited.connect(func(): _commit_editor(number))


func _commit_editor(number: SpinBox) -> bool:
	if not number.has_meta("draft"):
		return true
	var text: String = str(number.get_meta("draft")).strip_edges()
	if not number.suffix.is_empty():
		text = text.trim_suffix(number.suffix).strip_edges()
	if not text.is_valid_float() or not is_finite(text.to_float()):
		setting_status.text = "%s：请输入有效数值" % number.get_meta("title")
		number.get_line_edit().text = str(number.get_meta("draft"))
		return false
	var value := text.to_float()
	if value < number.min_value or value > number.max_value:
		setting_status.text = "%s：允许 %s–%s" % [number.get_meta("title"), number.min_value, number.max_value]
		number.get_line_edit().text = str(number.get_meta("draft"))
		return false
	number.remove_meta("draft")
	number.set_value_no_signal(value)
	editor_callbacks[number].call(number.value)
	return true


func commit_edits() -> bool:
	var valid := true
	var error := ""
	for number in editor_callbacks:
		if not _commit_editor(number):
			valid = false
			error = setting_status.text
	if not valid:
		setting_status.text = error
	return valid


func update_window_limit(limit: Vector2i) -> void:
	window_limit = limit
	_refresh_resolution_options()


func _refresh_resolution_options() -> void:
	if not is_instance_valid(resolution_select):
		return
	var fullscreen := window_mode.selected == 1
	if is_instance_valid(resolution_label):
		resolution_label.text = "全屏渲染分辨率" if fullscreen else "窗口分辨率"
	for index in PREFS.RESOLUTIONS.size():
		var size: Vector2i = PREFS.RESOLUTIONS[index]
		var unavailable := not fullscreen and (size.x > window_limit.x or size.y > window_limit.y)
		resolution_select.set_item_disabled(index, unavailable)
		resolution_select.set_item_tooltip(index, "超过当前屏幕的可用窗口区域；全屏模式仍可选" if unavailable else "")
	if resolution_select.is_item_disabled(resolution_select.selected):
		for index in range(PREFS.RESOLUTIONS.size() - 1, -1, -1):
			if not resolution_select.is_item_disabled(index):
				resolution_select.select(index)
				break


func update_runtime_display(window_size: Vector2i, render_size: Vector2i, vertical: float,
	horizontal: float, vsync: bool, cap: int) -> void:
	live_display.text = "窗口 %d × %d  /  渲染 %d × %d\nVSync %s  /  上限 %s  /  低延迟功能未集成" % [
		window_size.x, window_size.y, render_size.x, render_size.y,
		"开启" if vsync else "关闭", "不限" if cap == 0 else str(cap) + " FPS"]
	live_fov.text = "实际视角  V %.2f°  /  H %.2f°" % [vertical, horizontal]


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(92, 36)
	button.pressed.connect(callback)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#303633")
	normal.border_color = Color("#505952")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(7)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#424d46")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#31544d")
	pressed.border_color = CYAN
	button.add_theme_stylebox_override("pressed", pressed)
	return button


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _outline(label: Label, width: int = 4) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.025, 0.85))
	label.add_theme_constant_override("outline_size", width)


func _draw_crosshair() -> void:
	RETICLE.draw_crosshair(crosshair, Vector2.ZERO, reticle_values)


func configure_visuals(values: Dictionary) -> void:
	reticle_values = values.duplicate()
	crosshair_color = values.crosshair_color
	crosshair_width = values.crosshair_width
	crosshair_dot = values.crosshair_dot
	crosshair.queue_redraw()
	scope_overlay.configure(values)
	reticle_preview.configure(values)
	for key in PREFS.VISUAL_KEYS:
		if not preference_controls.has(key):
			continue
		var control: Control = preference_controls[key]
		if control.has_meta("draft"):
			continue
		if control is SpinBox:
			control.set_value_no_signal(values[key])
		elif control is ColorPickerButton:
			control.color = values[key]
		elif control is CheckButton:
			control.set_pressed_no_signal(values[key])
		if visual_sliders.has(key):
			visual_sliders[key].set_value_no_signal(values[key])
	for key in ["scope_distortion", "scope_edge_shade", "scope_quality"]:
		preference_controls[key].editable = values.scope_lens
		visual_sliders[key].editable = values.scope_lens
		setting_rows[key].modulate.a = 1.0 if values.scope_lens else 0.45


func _preference_color(parent: VBoxContainer, key: String, title: String) -> void:
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.edit_intensity = false
	picker.custom_minimum_size = Vector2(120, 30)
	picker.color = RETICLE.DEFAULTS[key]
	picker.color_changed.connect(func(value: Color): preference_changed.emit(key, value))
	preference_controls[key] = picker
	_setting_row(parent, title, picker)
	setting_rows[key] = picker.get_parent()


func _build_reticle_controls(parent: VBoxContainer) -> void:
	var presets := HFlowContainer.new()
	parent.add_child(presets)
	for index in RETICLE.PRESET_NAMES.size():
		presets.add_child(_button(RETICLE.PRESET_NAMES[index], func(): _apply_reticle_preset(index)))
	var note := _label("滑块/颜色即时生效并保存；数值输入回车确认。预设只改变普通准星。", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)
	var inner := _visual_section(parent, "普通准星 · 颜色与内线", true)
	_preference_color(inner, "crosshair_color", "准星颜色 / HEX")
	_preference_toggle(inner, "crosshair_inner", "显示内线")
	_preference_toggle(inner, "crosshair_t", "T形（隐藏上方线）")
	for field in [["crosshair_length_x", "水平长度"], ["crosshair_length_y", "垂直长度"],
		["crosshair_gap", "中心间距"], ["crosshair_width", "内线粗细"], ["crosshair_opacity", "内线不透明度 / %"]]:
		_visual_number(inner, field[0], field[1])
	var outer := _visual_section(parent, "外线", false)
	_preference_toggle(outer, "crosshair_outer", "显示外线")
	for field in [["outer_length_x", "外线水平长度"], ["outer_length_y", "外线垂直长度"],
		["outer_gap", "外线距中心"], ["outer_width", "外线粗细"], ["outer_opacity", "外线不透明度 / %"]]:
		_visual_number(outer, field[0], field[1])
	var dot := _visual_section(parent, "中心点与描边", false)
	_preference_toggle(dot, "crosshair_dot_enabled", "显示中心点")
	_preference_toggle(dot, "dot_square", "方形中心点")
	_visual_number(dot, "crosshair_dot", "中心点半径 / 半边长")
	_visual_number(dot, "dot_opacity", "中心点不透明度 / %")
	_preference_toggle(dot, "crosshair_outline", "显示描边")
	_preference_color(dot, "outline_color", "描边颜色 / HEX")
	_visual_number(dot, "outline_width", "描边厚度")
	_visual_number(dot, "outline_opacity", "描边不透明度 / %")
	var optics := _visual_section(parent, "镜片放大与边缘效果", false)
	_preference_toggle(optics, "scope_lens", "仅镜内放大")
	_visual_number(optics, "scope_distortion", "镜片边缘畸变 / %")
	_visual_number(optics, "scope_edge_shade", "镜片边缘暗角 / %")
	_visual_number(optics, "scope_quality", "镜内渲染比例 / %")
	var optics_note := _label("倍率在「玩家」页调整。上方预览只展示分划；镜片效果请在单发模式开镜查看。", 13)
	optics_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	optics.add_child(optics_note)
	var scope := _visual_section(parent, "镜内分划与遮罩", false)
	_preference_color(scope, "scope_color", "分划颜色 / HEX")
	_preference_toggle(scope, "scope_lines", "显示镜内十字")
	_preference_toggle(scope, "scope_ticks", "显示分划刻度")
	for field in [["scope_width", "分划粗细"], ["scope_gap", "镜内中心间距"],
		["scope_length", "线长 / 镜片半径 %"], ["scope_opacity", "分划不透明度 / %"],
		["scope_dot", "中心点半径（0关闭）"], ["scope_dot_opacity", "中心点不透明度 / %"]]:
		_visual_number(scope, field[0], field[1])
	_preference_toggle(scope, "scope_outline", "显示镜内描边")
	_visual_number(scope, "scope_outline_width", "镜内描边厚度")
	_visual_number(scope, "scope_outline_opacity", "镜内描边不透明度 / %")
	_visual_number(scope, "scope_mask", "外围遮罩强度 / %")
	var tracer := _visual_section(parent, "曳光线", false)
	_preference_toggle(tracer, "player_tracer", "显示玩家曳光线")
	_preference_toggle(tracer, "bot_tracer", "显示 Bot 曳光线")
	for key in RETICLE.KEYS:
		var control: Control = preference_controls[key]
		if key in RETICLE.COLORS:
			control.tooltip_text = "点击色块选颜色，也可在拾色器中输入HEX。颜色即时应用到上方预览和游戏。"
		elif key in RETICLE.RANGES:
			control.tooltip_text = "拖动滑块实时预览；可用数值框精确调整，回车确认。尺寸单位为UI像素（百分比项除外），不改变射线判定。"
		else:
			control.tooltip_text = "切换后上方预览实时更新；设置自动保存。仅改变显示，不影响武器判定。"
	preference_controls.scope_mask.tooltip_text = "0透明、100全黑；只改变镜片外围遮罩。镜内预览是缩略示意，不是实际放大倍率。"
	preference_controls.scope_lens.tooltip_text = "开启：镜片内独立放大，镜外保持原视野；关闭：恢复整幅视野放大。镜片需额外渲染一次场景，开镜时会增加GPU负担。"
	preference_controls.scope_distortion.tooltip_text = "仅镜内放大时生效。0关闭；越高边缘弯曲越明显。中心55%半径不变，准星与射线不偏移。"
	preference_controls.scope_edge_shade.tooltip_text = "镜片内缘逐渐变暗，0关闭。仅镜内放大时生效；镜外亮度由外围遮罩控制。"
	preference_controls.scope_quality.tooltip_text = "50/75/100%，控制镜内渲染尺寸。降低可减少像素开销，但更模糊；不改变倍率、灵敏度或命中方向。退镜后停止额外渲染。"
	parent.add_child(_button("恢复准星与曳光默认值", func():
		for key in RETICLE.KEYS:
			var control: Control = preference_controls[key]
			if control.has_meta("draft"):
				control.remove_meta("draft")
			preference_changed.emit(key, RETICLE.DEFAULTS[key])))


func _visual_section(parent: VBoxContainer, title: String, expanded: bool) -> VBoxContainer:
	var button := Button.new()
	button.text = ("▾ " if expanded else "▸ ") + title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 32
	button.toggle_mode = true
	button.button_pressed = expanded
	parent.add_child(button)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.visible = expanded
	parent.add_child(content)
	button.toggled.connect(func(open: bool):
		content.visible = open
		button.text = ("▾ " if open else "▸ ") + title)
	return content


func _visual_number(parent: VBoxContainer, key: String, title: String) -> void:
	var limits: Vector3 = RETICLE.RANGES[key]
	var row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = limits.x
	slider.max_value = limits.y
	slider.step = limits.z
	slider.value = RETICLE.DEFAULTS[key]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var number := SpinBox.new()
	number.min_value = limits.x
	number.max_value = limits.y
	number.step = limits.z
	number.value = RETICLE.DEFAULTS[key]
	number.custom_minimum_size.x = 95
	row.add_child(number)
	_track_editor(number, title, func(value: float): preference_changed.emit(key, value))
	slider.value_changed.connect(func(value: float):
		if number.has_meta("draft"):
			number.remove_meta("draft")
		number.set_value_no_signal(value)
		preference_changed.emit(key, value))
	preference_controls[key] = number
	visual_sliders[key] = slider
	_setting_row(parent, title, row)
	setting_rows[key] = row.get_parent()


func _apply_reticle_preset(index: int) -> void:
	var config := RETICLE.preset(index)
	for key in config:
		if preference_controls[key].has_meta("draft"):
			preference_controls[key].remove_meta("draft")
		preference_changed.emit(key, config[key])


func update_state(is_advanced: bool, phase: String, _tick: int, weapon: LgWeapon,
	_speed: float, _hit_now: bool, _lag_ms: float) -> void:
	advanced = is_advanced
	mode_label.text = "训练 / " + ("进阶" if advanced else "普通") + (" / 护甲" if armor_active else "")
	phase_label.text = phase
	var accuracy := "--" if weapon.shots == 0 else "%.1f%%" % (100.0 * weapon.hits / weapon.shots)
	stats_label.text = "命中 %s  /  伤害 %d" % [accuracy, weapon.damage]
	performance_label.text = "%d FPS  /  %d Hz" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second]


func update_duel_state(player_health: int, target_health: int, _bot_state: String,
	_firing: bool, elapsed: float, bot_weapon: LgWeapon) -> void:
	player_health_value.text = str(player_health)
	target_health_value.text = str(target_health)
	timer_label.text = "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	var actual := "--" if bot_weapon.shots == 0 else "%.1f%%" % (100.0 * bot_weapon.hits / bot_weapon.shots)
	bot_state_label.text = "BOT 命中 " + actual
	bot_accuracy_label.text = "BOT 实际命中  " + actual


func update_armor_state(active: bool, own: int, enemy: int, maximum: int) -> void:
	armor_active = active
	health_block.offset_top = -172 if active else -136
	speed_label.offset_top = -202 if active else -166
	speed_label.offset_bottom = -176 if active else -140
	for side in 2:
		var value := own if side == 0 else enemy
		armor_numbers[side].visible = active
		armor_bars[side].visible = active
		armor_numbers[side].text = "SHIELD  %d" % value if value > 0 else "SHIELD  0"
		armor_numbers[side].modulate = Color("#a8dbff") if value > 0 else CORAL
		armor_bars[side].max_value = maxi(maximum, 1)
		armor_bars[side].value = value


func update_scores(player_wins: int, bot_wins: int) -> void:
	score_labels[0].text = str(player_wins)
	score_labels[1].text = str(bot_wins)


func update_training_score(value: Dictionary) -> void:
	training_score_label.text = "积分 %.1f  /  走位 +%.1f" % [value.total, value.bonus] if value.valid else "积分 — 非计分"


func set_weapon_mode(enabled: bool) -> void:
	single_shot = enabled
	weapon_title.text = "单发 · 命中得分" if enabled else "LIGHTNING"
	for side in health_captions.size():
		health_captions[side].text = ("PLAYER" if side == 0 else "BOT") + (" 得分" if enabled else "  +")
	if not enabled:
		ammo_label.text = "∞"
		ammo_label.modulate = GOLD
		ammo_label.add_theme_font_size_override("font_size", 46)


func set_scope(active: bool, zoom: float) -> void:
	scope_overlay.set_scope(active, zoom)
	crosshair.visible = not active and not panel.visible and not review_panel.visible


func update_sniper(match_state: RefCounted, remaining: float, enemy_remaining: float,
	gun: LgWeapon, invalid: bool) -> void:
	update_scores(match_state.player_points, match_state.bot_points)
	player_health_value.text = str(match_state.player_points)
	target_health_value.text = str(match_state.bot_points)
	mode_label.text = "单发 / %d分制 / %s" % [match_state.limit, "进阶" if advanced else "普通"]
	if phase_label.text == "准备":
		phase_label.text = "开镜或开火开始"
	ammo_label.add_theme_font_size_override("font_size", 22)
	ammo_label.text = "拉栓 %.2fs" % remaining if remaining > 0 else "就绪 · 点击"
	ammo_label.modulate = CORAL if remaining > 0 else CYAN
	weapon_title.text = "先到 %d 分" % match_state.limit
	var accuracy := "--" if gun.shots == 0 else "%.1f%%" % (100.0 * gun.hits / gun.shots)
	stats_label.text = "单发命中 %s  /  %d发  /  射程60m" % [accuracy, gun.shots]
	training_score_label.text = "走位奖励 +%.2f（不影响胜负）" % match_state.bonus if not invalid else "娱乐 / 非计分"
	bot_state_label.text += "  /  " + ("拉栓 %.2fs" % enemy_remaining if enemy_remaining > 0 else "待出枪")


func update_bot_behavior(state: String, action: String) -> void:
	var states := {"hard_lock": "绝对锁定", "acquiring": "捕获目标", "tracking": "跟踪",
		"stable": "稳定跟踪", "reacquiring": "修正变向", "searching": "搜索目标"}
	var actions := {"micro": "短横移", "strafe": "横移", "burst": "长步", "feint": "变速虚晃"}
	bot_behavior_label.text = "%s  /  %s" % [states.get(state, state), actions.get(action, action)]


func set_round_result(result: String) -> void:
	round_result_label.text = result


func set_paused(value: bool, overloaded: bool = false) -> void:
	if not value:
		_cancel_binding()
	panel.visible = value
	dimmer.visible = value
	crosshair.visible = not value
	pause_title.text = "性能保护 / 非计分" if overloaded else "训练设置"
	mode_normal.set_pressed_no_signal(not advanced)
	mode_advanced.set_pressed_no_signal(advanced)


func show_review(value: Dictionary) -> void:
	_cancel_binding()
	panel.hide()
	dimmer.show()
	crosshair.hide()
	review_panel.display(value)
	call_deferred("_fit_panel")


func hide_review() -> void:
	if is_instance_valid(review_panel):
		review_panel.hide()


func _help(explanation: String) -> Label:
	var marker := preload("res://scripts/ui/parameter_help.gd").new()
	marker.text = "?"
	marker.add_theme_font_size_override("font_size", 15)
	marker.mouse_filter = Control.MOUSE_FILTER_STOP
	marker.custom_minimum_size = Vector2(24, 28)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.modulate = CYAN
	marker.tooltip_text = explanation
	return marker


func _install_preference_help() -> void:
	var explanations := {
		"dpi": "填写鼠标驱动中实际使用的DPI；填写错误会使实际转身距离不符。",
		"cm360": "鼠标在桌面移动多少厘米转一圈。数值越大越慢；不会随分辨率改变。",
		"invert_y": "反转鼠标上下方向，不改变左右。",
		"fov": "视野角度；只改变画面和目标角大小，不改变鼠标每厘米转动的角度。",
		"fov_mode": "选择垂直角度或16:9基准的水平角度；切换时保持当前视野。",
		"vsync": "与显示器刷新同步，可能减少撕裂但增加等待；独立低延迟功能未集成。",
		"assist_speed": "自瞄每秒最大转动角度；越高越快追上目标。",
		"hit_sound": "命中目标后播放确认音；不改变命中判定。",
		"hit_volume": "命中确认音量；0为静音。",
		"hit_sound_style": "只改变命中音色，不改变伤害。",
		"sky_style": "切换背景天空，不改变地图碰撞。",
		"arena_style": "切换场地配色，不改变地图形状。",
		"floor_grid": "显示或隐藏地面网格，不改变地面碰撞。",
		"scene_brightness": "调整场景照明强度，不改变Bot轮廓或判定。"
	}
	for key in preference_controls:
		var control: Control = preference_controls[key]
		if control.tooltip_text.is_empty():
			control.tooltip_text = explanations.get(key, "调整此项并保存到本机训练设置。")
		var help := _help(control.tooltip_text)
		control.get_parent().add_child(help)
		help_markers[key] = help


func _build_footwork_controls(movement: VBoxContainer, experiment: VBoxContainer) -> void:
	_preference_choice(movement, "step_mode", "步法驱动", ["原有逻辑", "时间", "距离"])
	preference_controls.step_mode.tooltip_text = "时间型按秒换动作；距离型按实际水平位移换动作。原有逻辑下其他高级步法参数不生效。"
	var fields := [
		["step_min", "最短步长", 0.1, "米；一次动作的水平位移下限。不是固定横移场地半幅，遇墙可能提前结束。"],
		["step_max", "最长步长", 0.1, "米；一次动作的水平位移上限。距离模式生效，提高移速会更快走完。"],
		["step_time_min", "最短动作时间", 0.01, "秒；时间模式生效。步法先选择长短类型，再从对应时间段抽样。"],
		["step_time_max", "最长动作时间", 0.01, "秒；时间模式生效。更长的动作更容易保持同向，避墙仍可打断。"],
		["pace_floor", "最低速度比例 / %", 1, "实际速度在Bot上限的此比例到100%之间抽样。100为不主动变速；后撤仍优先满速。"],
		["pace_min", "最短变速间隔 / s", 0.01, "两次随机变速之间的最短时间；与左右变向分开计时。"],
		["pace_max", "最长变速间隔 / s", 0.01, "两次随机变速之间的最长时间；越长越容易出现持续快步或慢步。"],
		["micro_weight", "短步权重", 1, "短步选范围中较短的一段。权重越大越常出现；权重不必相加等于100。"],
		["strafe_weight", "普通步权重", 1, "普通步选范围中间一段。全部权重为0时会回到普通步，不会卡死。"],
		["burst_weight", "长步权重", 1, "长步选范围中较长的一段。只有一种非零权重时，使用完整步长或时间范围。"],
		["feint_weight", "假动作权重", 1, "较短动作并降低速度，但不低于最低速度比例；不是瞬移或假动画。"],
		["repeat_gap", "动作防重复间隔", 1, "同类动作尽量隔几次选择再出现。仅一种动作可选时允许重复，避免无动作。"],
		["continue_chance", "方向延续概率 / %", 1, "换动作时继续原方向的概率。0每次反向；高值也受防转圈和地图边界保护。"],
		["pause_chance", "短停概率 / %", 1, "动作开始前暂停的概率。0始终连续移动；贴近玩家时后撤优先，不强制站着挨打。"],
		["pause_min", "最短停顿 / s", 0.01, "短停发生时至少停多久；进阶空中仍保留惯性。"],
		["pause_max", "最长停顿 / s", 0.01, "短停发生时最多停多久。不会暂停瞄准和开火。"]
	]
	for item in fields:
		var key: String = item[0]
		var limit: Vector2 = PREFS.FOOTWORK.LIMITS[key]
		_preference_number(movement, key, item[1], limit.x, limit.y, item[2], PREFS.FOOTWORK.DEFAULTS[key])
		preference_controls[key].tooltip_text = item[3]
	_preference_choice(experiment, "input_mode", "应对模型", ["延迟应对", "即时读键", "概率预测", "运动预判"])
	preference_controls.input_mode.tooltip_text = "延迟应对保留原逻辑；即时读键取消感知等待但保留枪法误差；概率预测学习本轮变向节奏；运动预判按已观察速度变化估计。所有模式都不能读取未来输入。"
	_preference_number(experiment, "prediction_horizon", "预测窗口 / ms", 50, 250, 10, 150)
	preference_controls.prediction_horizon.tooltip_text = "预测模式估计未来多长时间的趋势，不是LG子弹飞行时间。窗口越大越激进，也越可能猜错。"
	_preference_number(experiment, "prediction_strength", "预测影响 / %", 0, 100, 1, 50)
	preference_controls.prediction_strength.tooltip_text = "预测对走位应对与延迟补偿的影响。0不使用预测；概率样本不足时自动回退。100档瞄准仍直接硬锁，不受预测干扰。"


func sync_training_options(values: Dictionary) -> void:
	var keys: Array = PREFS.FOOTWORK.DEFAULTS.keys()
	keys.append_array(["movement_preset", "health_pool", "input_mode", "prediction_horizon", "prediction_strength", "round_review",
		"combat_mode", "armor_pool", "armor_sound", "armor_volume", "armor_effect", "armor_effect_strength", "roam_style",
		"bot_model", "bot_animation", "simulation_hz", "ad_bonus_weight",
		"weapon_mode", "score_limit", "sniper_cooldown", "sniper_volume",
		"bot_sniper_cooldown", "scope_zoom", "scope_sensitivity", "scope_mode"])
	for key in keys:
		if not preference_controls.has(key):
			continue
		var control: Control = preference_controls[key]
		if control.has_meta("draft"):
			continue
		if control is SpinBox:
			control.set_value_no_signal(values[key])
		elif control is OptionButton:
			control.select(control.get_item_index(int(values[key])))
			control.set_meta("applied", values[key])
		elif control is CheckButton:
			control.set_pressed_no_signal(values[key])
	for key in PREFS.FOOTWORK.DEFAULTS:
		if key == "step_mode":
			continue
		var enabled := int(values.step_mode) != 0
		if key in ["step_min", "step_max"]:
			enabled = int(values.step_mode) == 2
		if key in ["step_time_min", "step_time_max"]:
			enabled = int(values.step_mode) == 1
		preference_controls[key].editable = enabled
		preference_controls[key].modulate.a = 1.0 if enabled else 0.4
	for key in ["prediction_horizon", "prediction_strength"]:
		var enabled: bool = values.reactive_bot and int(values.input_mode) >= 2
		preference_controls[key].editable = enabled
		preference_controls[key].modulate.a = 1.0 if enabled else 0.4
	var explanation: String = PREFS.FOOTWORK.EXPLANATIONS[int(values.movement_preset)]
	preference_controls.movement_preset.tooltip_text = explanation
	if help_markers.has("movement_preset"):
		help_markers.movement_preset.tooltip_text = explanation
	advanced = values.advanced
	mode_normal.set_pressed_no_signal(not advanced)
	mode_advanced.set_pressed_no_signal(advanced)
	preference_controls.input_mode.disabled = not values.reactive_bot
	preference_controls.roam_style.disabled = not values.roaming
	preference_controls.bot_animation.disabled = int(values.bot_model) != 0
	preference_controls.bot_adaptation.disabled = not values.reactive_bot
	for key in ["engagement_distance", "aggression", "flank_chance", "distance_variation", "orbit_chance"]:
		_enable_bot_control(key, values.roaming)
	_enable_bot_control("strafe_extent", not values.roaming)
	_enable_bot_control("aim_turn_rate", values.aim_level < 100)
	_enable_bot_control("reaction_strength", values.reactive_bot)
	_enable_bot_control("reaction_delay", (values.reactive_bot and int(values.input_mode) != 1) \
		or (values.roaming and values.flank_chance > 0))
	_enable_bot_control("turn_frequency", values.roaming or int(values.step_mode) == 0)
	_enable_bot_control("randomness", values.roaming or int(values.step_mode) == 0)
	for key in ["jump_interval", "air_control"]:
		_enable_bot_control(key, values.advanced)
	var input_title: String = "输入应对 · " + (["延迟应对", "即时读键", "概率预测", "运动预判"][int(values.input_mode)] \
		if values.reactive_bot else "已关闭")
	bot_section_buttons.input.set_meta("title", input_title)
	bot_section_buttons.input.text = ("▾ " if bot_sections.input.visible else "▸ ") + input_title
	var sniper := int(values.weapon_mode) == 1
	for key in ["score_limit", "sniper_cooldown", "sniper_volume", "bot_sniper_cooldown", "scope_zoom", "scope_sensitivity", "scope_mode"]:
		setting_rows[key].visible = sniper
	scope_readout.visible = sniper
	scope_readout.text = "镜内 %.3f cm/360  /  %s" % [
		values.cm360 * values.scope_zoom * 100.0 / values.scope_sensitivity,
		"按住开镜，松开退镜" if int(values.scope_mode) == 0 else "点击开镜，再点退镜"]
	setting_rows.combat_mode.visible = not sniper
	setting_rows.health_pool.visible = not sniper and int(values.combat_mode) == 0
	setting_rows.armor_pool.visible = not sniper and int(values.combat_mode) == 1
	armor_controls.visible = not sniper and int(values.combat_mode) == 1
	preference_controls.round_review.disabled = sniper
	preference_controls.ad_bonus_weight.tooltip_text = (
		"单发命中时回看最近0.4秒的有效横移，奖励最高为命中分的此比例；单段前0.2米、撞墙和抖键不奖励。不影响25/50分胜负。调整后重开。"
		if sniper else "命中时按实际横移速度奖励，最高为基础命中分的此百分比。单段前0.2米不加分；空走、撞墙、抖键不加分。0关闭；调整后重开。")
	if help_markers.has("ad_bonus_weight"):
		help_markers.ad_bonus_weight.tooltip_text = preference_controls.ad_bonus_weight.tooltip_text
	preference_controls.armor_volume.editable = values.armor_sound
	preference_controls.armor_effect_strength.editable = values.armor_effect
	update_aim_profile(values.aim_level)


func _enable_bot_control(key: String, enabled: bool) -> void:
	bot_controls[key].editable = enabled
	bot_sliders[key].editable = enabled
	setting_rows[key].modulate.a = 1.0 if enabled else 0.45
