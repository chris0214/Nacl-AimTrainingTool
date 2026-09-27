extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
var checks := 0
var failures := 0
var game: Node3D


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", title)


func _mouse(button: int, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _motion(x: float, y: float = 0) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(x, y)
	event.relative = Vector2(1000, 1000)
	return event


func _run() -> void:
	_test_input()
	_test_toggle_input()
	_test_settings()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.preferences.put("sniper_volume", 0)
	game._set_preference("hit_sound", false)
	game._set_preference("move_speed", 0)
	game._set_preference("reactive_bot", false)
	game._set_preference("weapon_mode", 1)
	await process_frame
	for hz in [120, 240, 360]:
		await _scope_live(hz)
		await _toggle_live(hz)
		var idle: Array[int] = await _cadence(hz, false)
		var clicking: Array[int] = await _cadence(hz, true)
		check(idle == clicking, "Bot shot ticks independent of player clicks hz=%d" % hz)
	await _ui_and_reset()
	await _screenshots()
	game.queue_free()
	await process_frame
	print("SNIPER_SCOPE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_input() -> void:
	for zoom in [1.5, 2.0, 4.0, 8.0]:
		for fov in [30.0, 75.0, 120.0, 150.0]:
			var scoped := PlayerInput.scoped_fov(fov, zoom)
			check(absf(tan(deg_to_rad(fov) / 2) / tan(deg_to_rad(scoped) / 2) - zoom) < 0.000001,
				"projection ratio equals requested magnification")
	var input := PlayerInput.new()
	input.sensitivity = 0.02
	input.configure_scope(true, 4, 125)
	input.ingest(_motion(10), 1)
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 2)
	input.ingest(_motion(80, 40), 3)
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 4)
	input.ingest(_motion(10), 5)
	check(not input.preview_scoped, "render preview sees latest scope edge")
	var expected := -deg_to_rad(0.02) * (20 + 80 * 0.3125)
	check(absf(input.preview_yaw - expected) < 0.000000001, "queued mixed input uses event-order scaling")
	var command := input.consume(3)
	check(command.scope and command.scope_pressed and not command.fire, "scope input distinct from fire")
	check(not input.preview_scoped, "consuming old scoped input never rewinds preview")
	command = input.consume(5)
	check(not command.scope and not command.scope_pressed, "scope release reaches simulation")
	check(absf(input.yaw - expected) < 0.000000001 and input.yaw == input.preview_yaw,
		"simulation and preview consume same scaled raw counts")
	check(absf(input.pitch + deg_to_rad(0.02) * 40 * 0.3125) < 0.000000001, "vertical counts scaled equally")
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 6)
	input.ingest(_motion(12), 7)
	var correction := 0.8
	input.correct_view(correction, 0)
	check(absf(input.preview_yaw - (correction - deg_to_rad(0.02) * 12 * 0.3125)) < 0.000000001,
		"view correction rebuilds already scaled queued input once")
	input.clear()
	check(not input.preview_scoped and input.queue.is_empty() and not input.consume(10).scope, "clear removes scope and queued edges")
	input.bind_action("scope", KEY_C)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	input.ingest(key, 11)
	check(input.preview_scoped and input.consume(11).scope_pressed, "rebound physical key activates scope")
	input.clear(true)
	input.configure_scope(false, 4, 125)
	input.ingest(key, 12)
	input.ingest(_motion(80), 13)
	command = input.consume(13)
	check(not input.preview_scoped and not command.scope and not command.scope_pressed, "LG disables scope")
	check(absf(input.yaw + deg_to_rad(0.02) * 80) < 0.000000001, "LG mouse counts never get scope scaling")


func _test_settings() -> void:
	var settings := PREFS.new()
	settings.path = "res://artifacts/scope-settings.cfg"
	settings.put("scope_zoom", 3.5)
	settings.put("scope_sensitivity", 140)
	settings.put("scope_mode", 1)
	settings.put("bot_sniper_cooldown", 0.45)
	settings.bindings.scope = KEY_C
	check(settings.save_settings() == OK, "new scope settings save")
	var loaded := PREFS.new()
	loaded.path = settings.path
	loaded.load_settings()
	check(loaded.values.scope_mode == 1 and loaded.values.scope_zoom == 3.5 and loaded.values.scope_sensitivity == 140 \
		and is_equal_approx(loaded.values.bot_sniper_cooldown, 0.45) and loaded.bindings.scope == KEY_C, "scope settings reload")
	for key in ["scope_zoom", "scope_sensitivity", "bot_sniper_cooldown"]:
		var before: float = loaded.values[key]
		for invalid in [NAN, INF, "2", true]:
			loaded.put(key, invalid)
			check(loaded.values[key] == before, "invalid scope setting rejected")
	for invalid in [-1, 2, 0.5, NAN, "1", true]:
		loaded.put("scope_mode", invalid)
		check(loaded.values.scope_mode == 1, "invalid scope mode rejected")
	loaded.put("scope_zoom", 999)
	loaded.put("scope_sensitivity", -1)
	loaded.put("bot_sniper_cooldown", -1)
	check(loaded.values.scope_zoom == 8 and loaded.values.scope_sensitivity == 10 \
		and is_equal_approx(loaded.values.bot_sniper_cooldown, 0.3), "new setting limits")
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "format_version", 2)
	legacy.set_value("training", "cm360", 42.125)
	for action in PlayerInput.DEFAULT_BINDINGS:
		if action != "scope":
			legacy.set_value("bindings", action, PlayerInput.DEFAULT_BINDINGS[action])
	legacy.set_value("bindings", "fire", -MOUSE_BUTTON_RIGHT)
	legacy.set_value("bindings", "jump", KEY_J)
	legacy.save("res://artifacts/scope-legacy.cfg")
	loaded = PREFS.new()
	loaded.path = "res://artifacts/scope-legacy.cfg"
	loaded.load_settings()
	check(loaded.bindings.fire == -MOUSE_BUTTON_RIGHT and loaded.bindings.jump == KEY_J \
		and loaded.values.cm360 == 42.125, "old right-click fire config preserved")
	check(loaded.bindings.scope != loaded.bindings.fire and loaded.bindings.size() == PlayerInput.DEFAULT_BINDINGS.size(),
		"new scope action assigned a free key")
	check(loaded.values.scope_mode == 0, "old config defaults to hold scope")
	var keys: Array = []
	for key in loaded.bindings.values():
		check(key not in keys, "migration leaves no duplicate keys")
		keys.append(key)


func _setup(hz: int) -> void:
	game.preferences.put("simulation_hz", hz)
	game.preferences.put("weapon_mode", 1)
	game.preferences.put("score_limit", 50)
	game.preferences.put("scope_zoom", 2)
	game.preferences.put("scope_sensitivity", 100)
	game.preferences.put("scope_mode", 0)
	# Exercise the original full-screen projection; scope_optics covers the new lens path.
	game._set_preference("scope_lens", false)
	game.preferences.put("sniper_cooldown", 0.9)
	game.preferences.put("bot_sniper_cooldown", 0.75)
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -10), 12)
	game.input.correct_view(0, atan2(0.91 - ArenaActor.EYE_HEIGHT, 10))


func _step() -> void:
	await physics_frame
	game.clock.rebase(Time.get_ticks_usec())
	game._physics_process(1.0 / game.clock.hz)
	game._process(0.0)


func _scope_live(hz: int) -> void:
	_setup(hz)
	game._set_preference("attack", false)
	var base: float = game.preferences.vertical_fov()
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	await _step()
	check(not game.ready_to_start and game.weapon.shots == 0, "scope starts without shooting hz=%d" % hz)
	check(game.hud.scope_overlay.visible and not game.hud.crosshair.visible \
		and not game.get_node("Camera/WeaponModel").visible, "scope has reticle with no duplicate weapon/crosshair")
	check(absf(game.camera.fov - PlayerInput.scoped_fov(base, 2)) < 0.00001, "live scoped FOV")
	var aim_before: Vector2 = Vector2(game.input.yaw, game.input.pitch)
	game.input.ingest(_mouse(MOUSE_BUTTON_LEFT, true), 0)
	await _step()
	check(game.weapon.hits == 1 and game.sniper_match.player_points == 1, "scoped ray still hits target")
	check(aim_before == Vector2(game.input.yaw, game.input.pitch), "scope and shot do not displace aim")
	for tick in 15:
		await _step()
	check(game.hud.scope_overlay.visible and game.weapon.next_shot_tick > game.clock.tick, "scope stays through bolt cooldown")
	check(game.weapon.shots == 1, "scope does not enable automatic fire")
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 0)
	await _step()
	check(not game.hud.scope_overlay.visible and game.hud.crosshair.visible \
		and game.get_node("Camera/WeaponModel").visible and absf(game.camera.fov - base) < 0.00001, "release restores FOV and model")
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	await _step()
	game.pause_training()
	check(not game.input.preview_scoped and not game.hud.scope_overlay.visible \
		and absf(game.camera.fov - base) < 0.00001, "pause clears scope immediately")
	game.resume_training()
	await _step()
	check(not game.hud.scope_overlay.visible and game.weapon.shots == 1, "resume requires fresh scope and fire inputs")
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	await _step()
	game._manual_review()
	check(game.hud.review_panel.visible and not game.hud.scope_overlay.visible, "review clears scope")
	game.hud.hide_review()


func _test_toggle_input() -> void:
	var input := PlayerInput.new()
	input.configure_scope(true, 2, 100, 1)
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 1)
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 2)
	check(input.preview_scoped, "duplicate press does not double-toggle")
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 3)
	input.ingest(_motion(20), 4)
	check(input.preview_scoped, "release retains toggle scope")
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 5)
	input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 6)
	input.ingest(_motion(20), 7)
	check(not input.preview_scoped, "second click exits toggle scope")
	var command := input.consume(4)
	check(command.scope and not input.preview_scoped, "partial consumption preserves distinct simulation and preview scope")
	command = input.consume(7)
	check(not command.scope and absf(input.yaw + deg_to_rad(input.sensitivity) * 30) < 0.000000001,
		"toggle event-order raw counts use correct sensitivity")
	input.bind_action("scope", KEY_C)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	input.ingest(key, 8)
	key.echo = true
	input.ingest(key, 9)
	check(input.preview_scoped and input.consume(9).scope, "keyboard repeat never toggles again")
	input.clear()
	check(not input.preview_scoped and not input.scoped and not input.preview_scope_down, "clear resets all toggle state")
	key.echo = false
	input.ingest(key, 10)
	input.configure_scope(true, 2, 100, 0)
	check(not input.preview_scoped and not input.consume(20).scope, "mode change discards pending toggle edges")
	input.configure_scope(true, 2, 100, 1)
	input.ingest(key, 21)
	input.bind_action("scope", KEY_V)
	check(not input.preview_scoped and not input.consume(22).scope, "rebinding clears toggled scope")


func _toggle_live(hz: int) -> void:
	_setup(hz)
	game._set_preference("attack", false)
	game.pause_training()
	game.hud.preference_controls.scope_mode.item_selected.emit(1)
	check(game.input.scope_mode == 1 and game.preferences.values.scope_mode == 1 \
		and game.hud.scope_readout.text.contains("再点退镜"), "toggle selector reaches input and helper text")
	game.resume_training()
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 0)
	await _step()
	check(game.hud.scope_overlay.visible and game.input.scoped and not game.ready_to_start, "full click opens scope and starts duel")
	game.input.ingest(_mouse(MOUSE_BUTTON_LEFT, true), 0)
	await _step()
	check(game.weapon.hits == 1 and game.hud.scope_overlay.visible, "toggle scope remains while shooting")
	for tick in 12:
		await _step()
	check(game.hud.scope_overlay.visible, "toggle remains during bolt")
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 0)
	await _step()
	check(not game.hud.scope_overlay.visible and game.hud.crosshair.visible, "next click restores hip view")
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 0)
	await _step()
	# Exercise the actual focus-loss route without injecting any desktop event.
	game.probe_mode = false
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.probe_mode = true
	check(game.paused and not game.input.preview_scoped and not game.hud.scope_overlay.visible, "focus loss exits toggle scope")
	game.resume_training()
	await _step()
	check(not game.hud.scope_overlay.visible, "resume does not reopen toggle")
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 0)
	await _step()
	game.reset_training()
	check(not game.hud.scope_overlay.visible and not game.input.scoped, "reset exits toggle scope")
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, false), 0)
	await _step()
	game._manual_review()
	check(game.hud.review_panel.visible and not game.hud.scope_overlay.visible, "toggle clears on settlement")
	game.hud.hide_review()
	game._set_preference("weapon_mode", 0)
	await process_frame
	check(not game.input.scope_enabled and not game.input.preview_scoped, "LG switch clears toggle mode state")


func _cadence(hz: int, player_clicks: bool) -> Array[int]:
	_setup(hz)
	game.preferences.put("sniper_cooldown", 2)
	game.preferences.put("bot_sniper_cooldown", 0.6)
	game._apply_simulation_rate()
	game._set_preference("attack", true)
	game._set_preference("aim_level", 100)
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	var shot_ticks: Array[int] = []
	for tick in hz * 5:
		if player_clicks:
			# Irregular presses including discarded cooldown clicks.
			if tick % (hz * 2) == hz / 3 or tick % (hz * 2) == hz / 2:
				game.input.ingest(_mouse(MOUSE_BUTTON_LEFT, true), 0)
			else:
				game.input.ingest(_mouse(MOUSE_BUTTON_LEFT, false), 0)
		var before: int = game.bot_weapon.shots
		await _step()
		if game.bot_weapon.shots > before:
			shot_ticks.append(tick)
	check(shot_ticks.size() == 9 and game.bot_weapon.hits == 9, "Bot fires autonomous cooldown in real scene")
	check(game.weapon.shots == (3 if player_clicks else 0), "player shots remain independently scheduled")
	for index in range(1, shot_ticks.size()):
		check(shot_ticks[index] - shot_ticks[index - 1] >= ceili(0.6 * hz - 0.000001), "Bot never exceeds own fire rate")
	check(game.bot_weapon.shots > game.weapon.shots, "Bot can shoot repeatedly while player waits")
	print("SCOPE_CADENCE hz=%d clicking=%s player=%d bot=%d ticks=%s" % [
		hz, player_clicks, game.weapon.shots, game.bot_weapon.shots, shot_ticks])
	return shot_ticks


func _ui_and_reset() -> void:
	_setup(120)
	game.pause_training()
	game.hud.preference_controls.bot_sniper_cooldown.value = 0.4
	await process_frame
	check(game.paused and game.weapon.interval_ticks == 108 and game.bot_weapon.interval_ticks == 48, "Bot slider changes only Bot and restarts paused")
	game.hud.preference_controls.scope_zoom.value = 4
	game.hud.preference_controls.scope_sensitivity.value = 125
	check(game.input.scope_zoom == 4 and game.input.scope_sensitivity == 125, "scope controls reach input")
	check(game.hud.scope_readout.text.contains("%.3f" % (game.preferences.values.cm360 * 3.2)), "scope cm360 readout")
	game.hud._capture_binding("scope")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	game.hud._input(key)
	check(game.input.bindings.scope == KEY_C and game.hud.binding_target == "", "UI supports rebinding scope")
	game._set_preference("attack", false)
	game.resume_training()
	game.input.ingest(key, 0)
	await _step()
	check(game.hud.scope_overlay.visible, "rebound scope works in live scene")
	game.reset_training()
	check(not game.input.preview_scoped and not game.hud.scope_overlay.visible, "restart clears scope")
	game.input.ingest(key, 0)
	await _step()
	game._set_preference("weapon_mode", 0)
	await process_frame
	check(not game.sniper_mode and not game.input.scope_enabled and not game.hud.scope_overlay.visible, "switch to LG clears scope")
	check(absf(game.camera.fov - game.preferences.vertical_fov()) < 0.00001, "LG FOV restored")
	game.input.bind_action("scope", -MOUSE_BUTTON_RIGHT)
	game.preferences.bindings = game.input.bindings.duplicate()


func _screenshots() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_setup(120)
	game._set_preference("attack", false)
	game.input.ingest(_mouse(MOUSE_BUTTON_RIGHT, true), 0)
	await _step()
	for size in [Vector2i(1440, 900), Vector2i(960, 600), Vector2i(1920, 800)]:
		root.size = size
		for frame in 8:
			await process_frame
		game._update_camera()
		await RenderingServer.frame_post_draw
		var lens: Control = game.hud.scope_overlay
		var expected: Vector2 = game.hud.root.size / 2
		var ray: Vector3 = game.camera.project_ray_normal(expected)
		check(ray.distance_to(-game.camera.global_basis.z) < 0.00001, "lens center aligns with camera ray at every aspect")
		check(lens.size == game.hud.root.size, "scope overlay resizes with viewport")
		root.get_texture().get_image().save_png("res://artifacts/scope-%dx%d.png" % [size.x, size.y])
	root.size = Vector2i(960, 600)
	game.pause_training()
	game.hud.tabs.current_tab = 3
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/scope-settings.png")
	game.hud.tabs.current_tab = 1
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/scope-bindings.png")
