extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	for dpi in [400.0, 800.0, 1600.0, 3200.0]:
		for cm in [20.0, 40.0, 80.0]:
			var input := PlayerInput.new()
			input.sensitivity = PlayerInput.sensitivity_from_cm(dpi, cm)
			var motion := InputEventMouseMotion.new()
			motion.screen_relative = Vector2(dpi * cm / 2.54, 0)
			motion.relative = Vector2(123, 0)
			input.ingest(motion, 0)
			input.consume(0)
			check(absf(rad_to_deg(input.yaw) + 360) < 0.001, "cm360 uses unscaled sensor count")
	var input := PlayerInput.new()
	input.bind_action("forward", KEY_D)
	check(input.bindings.right == KEY_W and input.bindings.forward == KEY_D, "duplicate bindings swap")
	check(not input.bind_action("fire", KEY_ESCAPE), "Escape remains reserved")
	check(not input.bind_action("fire", -MOUSE_BUTTON_WHEEL_UP), "wheel cannot hold continuous fire")
	input.bind_action("fire", KEY_F)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	input.ingest(key, 0)
	var command := input.consume(0)
	check(command.fire and command.fire_pressed, "keyboard firing works")
	key.pressed = false
	input.ingest(key, 1)
	check(not input.consume(1).fire, "keyboard release stops firing")
	input.bind_action("fire", -MOUSE_BUTTON_XBUTTON1)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	mouse.pressed = true
	input.ingest(mouse, 2)
	check(input.consume(2).fire_pressed, "side mouse button fires")
	input.clear(true)
	input.invert_y = true
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(0, 10)
	input.ingest(motion, 0)
	input.consume(0)
	check(input.pitch > 0 and input.pitch == input.preview_pitch, "Y inversion matches preview and simulation")
	var settings := PREFS.new()
	settings.path = "res://artifacts/test-settings.cfg"
	settings.put("dpi", 1600)
	settings.put("cm360", 42.5)
	settings.put("resolution", Vector2i(1280, 720))
	settings.put("randomness", 99)
	settings.bindings = input.bindings.duplicate()
	check(settings.save_settings() == OK, "settings save")
	var loaded := PREFS.new()
	loaded.path = settings.path
	loaded.load_settings()
	check(loaded.values == settings.values and loaded.bindings == settings.bindings, "settings round trip")
	loaded.put("dpi", NAN)
	loaded.put("cm360", "invalid")
	loaded.put("resolution", Vector2i(1, 1))
	check(loaded.values.dpi == 1600 and loaded.values.cm360 == 42.5
		and loaded.values.resolution == Vector2i(1280, 720), "invalid settings rejected")
	loaded.put("air_control", 999)
	check(loaded.values.air_control == 90, "settings numeric clamp")
	var game := preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.pause_training()
	check(not game.preferences.writable, "tests cannot overwrite user settings")
	game.hud.preference_controls.dpi.value = 1600
	game.hud.preference_controls.cm360.value = 40
	check(is_equal_approx(game.input.sensitivity, 914.4 / 64000.0), "DPI and cm360 controls connect")
	game.hud.preference_controls.invert_y.button_pressed = true
	check(game.input.invert_y, "invert control connects")
	game.hud._capture_binding("jump")
	var bind := InputEventKey.new()
	bind.physical_keycode = KEY_J
	bind.pressed = true
	game.hud._input(bind)
	check(game.input.bindings.jump == KEY_J and game.hud.binding_target == "", "panel captures physical key")
	game.hud._capture_binding("jump")
	bind.physical_keycode = KEY_ESCAPE
	game.hud._input(bind)
	check(game.paused and game.input.bindings.jump == KEY_J and game.hud.binding_target == "", "Escape cancels capture without resuming")
	var bot: Node = game.target
	bot.roaming_enabled = false
	bot.reset_at(Vector3(0, 0, -4), 1834)
	bot.configure("randomness", 100)
	var shortest := INF
	var longest := 0.0
	var continuations := 0
	var durations: Array[float] = []
	for index in 1000:
		var before: float = bot.strafe_direction
		bot._choose_action()
		shortest = minf(shortest, bot.action_duration)
		longest = maxf(longest, bot.action_duration)
		continuations += int(before == bot.strafe_direction)
		durations.append(bot.action_duration)
	var expected_short_action: float = 0.18 / bot.settings.turn_frequency
	check(longest > shortest * 6 and shortest < expected_short_action * 1.15,
		"mixed micro and long strafe intervals")
	check(continuations > 150 and continuations < 330, "not strictly alternating directions")
	bot.reset_at(Vector3(0, 0, -4), 1834)
	var exact := true
	for expected in durations:
		bot._choose_action()
		exact = exact and expected == bot.action_duration
	check(exact, "explicit seed replays exact decisions")
	bot.reset_at(Vector3(0, 0, -4))
	var first_seed: int = bot.rng.seed
	bot.reset_at(Vector3(0, 0, -4))
	check(bot.rng.seed != first_seed, "human rounds use fresh randomness")
	bot.roaming_enabled = true
	check(game.beam.get_child_count() == 2, "no endpoint hit sphere")
	game.bot_beam.show_segment(game.camera.global_position + Vector3.FORWARD * 5,
		game.camera.global_position, true)
	var core: MeshInstance3D = game.bot_beam.beam
	var visible_end := core.global_position + core.global_basis.y * 0.5
	check(visible_end.distance_to(game.camera.global_position) < 0.001,
		"miss endpoint is not clipped in front of camera")
	game.bot_beam.show_segment(game.camera.global_position + Vector3.FORWARD * 5,
		game.camera.global_position, true, true)
	visible_end = core.global_position + core.global_basis.y * 0.5
	check(absf(visible_end.distance_to(game.camera.global_position) - 2.0) < 0.001
		and not core.mesh.cap_top and not core.mesh.cap_bottom,
		"confirmed player hit continues through screen without end cap")
	var color: Color = game.hud.player_health_value.modulate
	game.hud.update_duel_state(950, 1000, "", true, 1, game.bot_weapon)
	check(game.hud.player_health_value.modulate == color, "health changes without hit flash")
	await _test_precision(game)
	if DisplayServer.get_name() != "headless":
		await _test_display(game)
	game.queue_free()
	await process_frame
	print("TRAINER_SETTINGS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_display(game: Node) -> void:
	var original := DisplayServer.window_get_size()
	game.hud.display_requested.emit(false, Vector2i(1280, 720))
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_size() == Vector2i(1280, 720), "resolution applies to real window")
	var native_image := root.get_texture().get_image()
	game._refresh_runtime_info()
	check(native_image.get_size() == Vector2i(1280, 720)
		and game.hud.live_display.text.contains("渲染 1280 × 720"),
		"windowed render report matches actual framebuffer pixels")
	check(not game.pending_display.is_empty(), "display confirmation pending")
	game.hud.display_reverted.emit()
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_size() == original and game.pending_display.is_empty(), "manual display rollback")
	game.hud.display_requested.emit(false, Vector2i(1280, 720))
	game.display_deadline = Time.get_ticks_msec() - 1
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_size() == original and game.pending_display.is_empty(), "display timeout restores previous window")
	game.hud.display_requested.emit(false, Vector2i(1280, 720))
	game.hud.display_confirmed.emit()
	check(game.preferences.values.resolution == Vector2i(1280, 720)
		and game.pending_display.is_empty(), "only confirmation stores resolution")
	game.hud.tabs.current_tab = 2
	game.hud.window_mode.select(1)
	game.hud.window_mode.item_selected.emit(1)
	game.hud.resolution_select.select(PREFS.RESOLUTIONS.find(Vector2i(1280, 720)))
	game.hud.display_apply.pressed.emit()
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "borderless fullscreen applies")
	check(root.get_texture().get_image().get_size() == Vector2i(1280, 720),
		"fullscreen really renders selected resolution")
	game._refresh_runtime_info()
	var scroll: ScrollContainer = game.hud.tabs.get_child(2)
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/fullscreen-resolution.png")
	game.hud.display_reverted.emit()
	await create_timer(0.2).timeout
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "fullscreen rolls back to window")
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
		"rollback restores native window rendering")
	game.hud.window_mode.select(1)
	game.hud.window_mode.item_selected.emit(1)
	check(not game.hud.resolution_select.disabled, "fullscreen resolution remains selectable")
	game._set_preference("fps", 333)
	game._set_preference("vsync", true)
	await process_frame
	check(Engine.max_fps == 333 and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED,
		"custom FPS and VSync reach actual engine settings")
	game._set_preference("vsync", false)
	game._apply_display(false, original)


func _draft(number: SpinBox, text: String) -> void:
	var edit := number.get_line_edit()
	edit.grab_focus()
	edit.text = text
	edit.text_changed.emit(text)


func _test_precision(game: Node) -> void:
	game.pause_training()
	game.hud.tabs.current_tab = 1
	await process_frame
	_draft(game.hud.preference_controls.dpi, "833")
	_draft(game.hud.preference_controls.cm360, "47.123456")
	game.hud.resumed.emit()
	check(not game.paused and game.preferences.values.dpi == 833, "typed DPI is not rounded to 50")
	check(absf(game.preferences.values.cm360 - 47.123456) < 0.0000001
		and absf(game.input.sensitivity - 914.4 / (833 * 47.123456)) < 0.0000000001,
		"resume commits precise cm360 text to simulation")
	game.pause_training()
	_draft(game.hud.preference_controls.cm360, "invalid")
	game.hud.resumed.emit()
	check(game.paused and not game.hud.setting_status.text.is_empty(), "invalid text blocks resume with error")
	game.hud.preference_controls.fov_mode.select(1)
	game.hud.preference_controls.fov_mode.item_selected.emit(1)
	check(game.hud.preference_controls.fov_mode.get_selected_id() == game.preferences.values.fov_mode,
		"rejected FOV change restores selector instead of showing unapplied value")
	_draft(game.hud.preference_controls.cm360, "38.765432")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	game.hud._input(escape)
	check(not game.paused and absf(game.preferences.values.cm360 - 38.765432) < 0.0000001,
		"Escape commits active numeric edit before resuming")
	game.pause_training()
	game._set_preference("fov", 75)
	game._set_preference("fov_mode", 1)
	check(absf(game.camera.fov - 75.0) < 0.01, "switching FOV convention preserves view")
	check(game.hud.preference_controls.fov_mode.get_selected_id() == 1,
		"FOV selector stays synchronized with actual convention")
	game._set_preference("fov", 110)
	check(absf(PlayerInput.horizontal_fov(game.camera.fov, 16.0 / 9.0) - 110) < 0.0001,
		"horizontal reference FOV converts accurately")
	var old_action_time: float = game.target.action_time
	game._set_preference("dpi", 817)
	check(game.target.action_time == old_action_time, "mouse edit does not reset bot decision timer")
	var input := PlayerInput.new()
	input.sensitivity = 0.017432145
	var single := InputEventMouseMotion.new()
	single.screen_relative = Vector2(1, 0)
	for index in 10000:
		input.ingest(single, index)
	input.consume(10000)
	check(absf(input.yaw + deg_to_rad(input.sensitivity) * 10000) < 0.000000001,
		"many mouse packets accumulate with double precision")
	game.hud.tabs.current_tab = 1
	await process_frame
	var edit: LineEdit = game.hud.preference_controls.dpi.get_line_edit()
	edit.grab_focus()
	edit.select_all()
	await process_frame
	for character in "829":
		var event := InputEventKey.new()
		event.keycode = character.unicode_at(0)
		event.physical_keycode = event.keycode
		event.unicode = event.keycode
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await process_frame
	check(game.preferences.values.dpi == 829, "dispatched keyboard events edit and submit actual SpinBox")
