extends SceneTree

const STYLE = preload("res://scripts/ui/reticle_style.gd")
const PREFS = preload("res://scripts/input/trainer_settings.gd")
var checks := 0
var failures := 0
var game: Node3D


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	_geometry()
	_settings()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.pause_training()
	game.hud.tabs.current_tab = 5
	check(game.hud.preview_box.visible, "preview shown only in visual editor")
	var history: int = game.clock.tick
	game.hud.visual_sliders.crosshair_length_x.value = 12
	game.hud.visual_sliders.crosshair_length_y.value = 3
	check(game.preferences.values.crosshair_length_x == 12 and game.preferences.values.crosshair_length_y == 3,
		"sliders immediately apply independent lengths")
	check(game.hud.reticle_preview.values.crosshair_length_x == 12 \
		and game.hud.reticle_values.crosshair_length_x == 12, "same state reaches live and preview")
	game.hud.preference_controls.crosshair_color.color_changed.emit(Color("#ff277f"))
	check(game.hud.reticle_preview.values.crosshair_color == Color("#ff277f"), "color updates preview instantly")
	var field: SpinBox = game.hud.preference_controls.crosshair_gap
	field.set_meta("draft", "7.5")
	check(game.hud._commit_editor(field) and game.preferences.values.crosshair_gap == 7.5 \
		and game.hud.visual_sliders.crosshair_gap.value == 7.5, "numeric commit updates slider and preview")
	field.set_meta("draft", "invalid")
	check(not game.hud._commit_editor(field) and game.preferences.values.crosshair_gap == 7.5, "invalid draft does not corrupt preview")
	game.hud._apply_reticle_preset(2)
	check(not field.has_meta("draft") and STYLE.commands(game.hud.reticle_values).size() == 1,
		"preset clears stale drafts and applies pure dot")
	game._set_preference("scope_mask", 35)
	game._set_preference("bot_tracer", false)
	for index in 5:
		game.hud._apply_reticle_preset(index)
		check(game.preferences.values.scope_mask == 35 and not game.preferences.values.bot_tracer,
			"presets preserve scope and tracer choices")
		check(STYLE.commands(game.hud.reticle_preview.values) == STYLE.commands(game.hud.reticle_values),
			"preset geometry equal in preview and live")
	check(game.clock.tick == history and not game.review.mixed_settings, "visual editing does not restart or taint score")
	game.hud.tabs.current_tab = 0
	check(not game.hud.preview_box.visible, "leaving visual tab restores panel space")
	game.hud.tabs.current_tab = 5
	await _render_checks()
	game.queue_free()
	await process_frame
	print("RETICLE_EDITOR_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _geometry() -> void:
	var values := STYLE.DEFAULTS.duplicate()
	check(STYLE.commands(values).size() == 5, "default inner cross plus dot")
	values.crosshair_t = true
	check(STYLE.commands(values).size() == 4, "T shape removes only upper arm")
	values.crosshair_t = false
	values.crosshair_length_x = 10
	values.crosshair_length_y = 3
	var cmds := STYLE.commands(values)
	check(cmds[0].a.distance_to(cmds[0].b) == 10 and cmds[2].a.distance_to(cmds[2].b) == 3,
		"geometry respects independent axis lengths")
	values.crosshair_outer = true
	check(STYLE.commands(values).size() == 9, "outer lines independently added")
	values.crosshair_inner = false
	check(STYLE.commands(values).size() == 5, "inner lines independently removed")
	values.outer_opacity = 0
	check(STYLE.commands(values).size() == 1, "zero-opacity outer lines including outline fully hidden")
	values.dot_opacity = 0
	check(STYLE.commands(values).is_empty(), "zero-opacity center including outline fully hidden")
	values.dot_opacity = 40
	values.dot_square = true
	values.crosshair_outline = false
	cmds = STYLE.commands(values)
	check(cmds[0].kind == "square" and cmds[0].outline == 0 and is_equal_approx(cmds[0].color.a, 0.4),
		"square dot opacity and outline flag")
	values.crosshair_dot_enabled = false
	check(STYLE.commands(values).is_empty(), "dot disabled without losing size")
	check(STYLE.preset(4).crosshair_outer and STYLE.preset(3).crosshair_t, "preset semantics")


func _settings() -> void:
	var prefs := PREFS.new()
	prefs.path = "res://artifacts/reticle-settings.cfg"
	for key in STYLE.RANGES:
		var limits: Vector3 = STYLE.RANGES[key]
		prefs.put(key, limits.y)
		check(prefs.values[key] == limits.y, "max allowed " + key)
		for invalid in [NAN, INF, "5", true]:
			prefs.put(key, invalid)
			check(prefs.values[key] == limits.y, "invalid rejected " + key)
		prefs.put(key, limits.x - 50)
		check(prefs.values[key] == limits.x, "lower bound clamped " + key)
		prefs.put(key, limits.y + 50)
	for key in STYLE.FLAGS:
		prefs.put(key, not STYLE.DEFAULTS[key])
	prefs.put("outline_color", Color("#ed125f"))
	check(prefs.save_settings() == OK, "reticle settings save")
	var copy := PREFS.new()
	copy.path = prefs.path
	copy.load_settings()
	for key in STYLE.KEYS:
		check(copy.values[key] == prefs.values[key], "reticle persisted " + key)
	var old := ConfigFile.new()
	old.set_value("meta", "format_version", 2)
	old.set_value("training", "crosshair_width", 4)
	old.set_value("training", "crosshair_dot", 0)
	old.set_value("training", "scope_mask", 23)
	old.save("res://artifacts/reticle-legacy.cfg")
	copy = PREFS.new()
	copy.path = "res://artifacts/reticle-legacy.cfg"
	copy.load_settings()
	check(copy.values.crosshair_width == 4 and copy.values.crosshair_dot == 0 and copy.values.scope_mask == 23,
		"existing visuals preserved")
	check(copy.values.crosshair_inner and not copy.values.crosshair_outer and copy.values.crosshair_gap == 5,
		"new visual fields get compatible defaults")


func _capture(name: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + name + ".png")


func _render_checks() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		game.hud._apply_reticle_preset(1)
		game._set_preference("crosshair_length_x", 9)
		game._set_preference("crosshair_length_y", 4)
		await _capture("reticle-editor-%d" % size.x)
		var before: Vector2 = game.hud.reticle_preview.get_global_rect().position
		game.hud.tabs.get_child(5).scroll_vertical = 190
		await _capture("reticle-editor-sliders-%d" % size.x)
		game.hud.tabs.get_child(5).scroll_vertical = 10000
		await _capture("reticle-editor-scrolled-%d" % size.x)
		check(game.hud.reticle_preview.get_global_rect().position == before, "preview pinned while scrolling")
		check(game.hud.panel.get_global_rect().end.y <= game.hud.root.size.y + 1, "panel fits viewport")
		game.hud.tabs.get_child(5).scroll_vertical = 0
	# Same-size offscreen renders compare actual preview drawing with live geometry.
	var viewports: Array[SubViewport] = []
	var controls: Array[Control] = []
	for index in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(256, 160)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var control := Control.new()
		control.size = viewport.size
		viewport.add_child(control)
		viewports.append(viewport)
		controls.append(control)
	var preview = game.hud.reticle_preview
	preview.background = 0
	controls[0].draw.connect(func(): preview._draw_tile(controls[0], 0))
	controls[1].draw.connect(func():
		controls[1].draw_rect(Rect2(Vector2.ZERO, controls[1].size), Color("#182329"))
		STYLE.draw_crosshair(controls[1], controls[1].size / 2, game.hud.reticle_values)
		controls[1].draw_rect(Rect2(Vector2.ZERO, controls[1].size), Color(Color("#e1eee9"), 0.3), false, 1))
	for index in 5:
		game.hud._apply_reticle_preset(index)
		for control in controls:
			control.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		check(viewports[0].get_texture().get_image().get_data() == viewports[1].get_texture().get_image().get_data(),
			"pixel-identical 1x preview and live drawing for preset")
	for viewport in viewports:
		viewport.queue_free()
	var picker: ColorPickerButton = game.hud.preference_controls.crosshair_color
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = picker.get_global_transform_with_canvas() * (picker.size / 2)
		root.push_input(event, true)
		await process_frame
	check(picker.get_popup().visible, "real GUI click opens color picker")
	await _capture("reticle-color-picker")
	picker.get_popup().hide()
