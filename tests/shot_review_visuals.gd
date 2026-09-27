extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
const MATCH = preload("res://scripts/combat/sniper_match.gd")
var game: Node3D
var checks := 0
var failures := 0
var saved_report: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	_settings_and_capacity()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game._set_preference("attack", false)
	game._set_preference("move_speed", 0)
	game._set_preference("hit_sound", false)
	game.preferences.put("sniper_volume", 0)
	for hz in [120, 240, 360]:
		await _live(hz)
	await _tracer_rules()
	await _visual_controls()
	await _screenshots()
	game.queue_free()
	await process_frame
	print("SHOT_REVIEW_VISUALS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _settings_and_capacity() -> void:
	var prefs := PREFS.new()
	prefs.path = "res://artifacts/shot-visual-settings.cfg"
	prefs.put("crosshair_color", Color("#fa26c1"))
	prefs.put("scope_color", Color("#35d498"))
	prefs.put("crosshair_width", 4)
	prefs.put("scope_width", 2.5)
	prefs.put("crosshair_dot", 0)
	prefs.put("scope_dot", 0)
	prefs.put("scope_mask", 0)
	prefs.put("player_tracer", false)
	prefs.put("bot_tracer", false)
	check(prefs.save_settings() == OK, "visual preferences saved")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	for key in PREFS.VISUAL_KEYS:
		check(loaded.values[key] == prefs.values[key], "visual persistence " + key)
	for key in ["crosshair_color", "scope_color"]:
		var before: Color = loaded.values[key]
		for invalid in [Color(NAN, 0, 0), Color(0, INF, 0), Color(0, 0, 0, NAN), "pink", 5]:
			loaded.put(key, invalid)
			check(loaded.values[key] == before, "invalid color ignored")
		loaded.put(key, Color(2, -1, 0.5, 0))
		check(loaded.values[key] == Color(1, 0, 0.5, 1), "RGB clamped and opaque")
	for key in ["crosshair_width", "scope_width", "crosshair_dot", "scope_dot", "scope_mask"]:
		var before: float = loaded.values[key]
		loaded.put(key, NAN)
		check(loaded.values[key] == before, "nonfinite geometry ignored")
	var match_state := MATCH.new()
	match_state.reset(25, 10, 4)
	for index in 520:
		match_state.add_snapshot({"number": index + 1, "nested": {"x": index}})
	check(match_state.shot_snapshots.size() == 512 and match_state.dropped_snapshots == 8 \
		and match_state.shot_snapshots[0].number == 9, "per-round history bounded to recent 512")
	var report := match_state.report("", LgWeapon.new(), LgWeapon.new(), false)
	report.shot_snapshots[0].nested.x = -500
	check(match_state.shot_snapshots[0].nested.x == 8, "report deep-copy immutable snapshots")
	match_state.discontinuity()
	check(match_state.shot_snapshots.size() == 512, "pause retains shots")
	match_state.reset(25, 10, 4)
	check(match_state.shot_snapshots.is_empty() and match_state.dropped_snapshots == 0, "restart clears shots")


func _setup(hz: int, sniper: bool = true) -> void:
	game.preferences.put("simulation_hz", hz)
	game.preferences.put("weapon_mode", int(sniper))
	game.preferences.put("score_limit", 50)
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -10), 12)
	_aim(0, 0)


func _aim(right_degrees: float, up_degrees: float) -> void:
	var offset: Vector3 = game.target.position + Vector3.UP * 0.91 - game.player.eye_position()
	game.input.correct_view(atan2(-offset.x, -offset.z) - deg_to_rad(right_degrees),
		atan2(offset.y, Vector2(offset.x, offset.z).length()) + deg_to_rad(up_degrees))


func _event(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	game.input.ingest(event, 0)


func _step() -> void:
	await physics_frame
	game.clock.rebase(Time.get_ticks_usec())
	game._physics_process(1.0 / game.clock.hz)
	game._process(0)


func _fire() -> void:
	# Skip only the wait, never actual ray or score evaluation.
	game.clock.tick = maxi(game.clock.tick, game.weapon.next_shot_tick)
	_event(MOUSE_BUTTON_LEFT, false)
	_event(MOUSE_BUTTON_LEFT, true)
	await _step()


func _live(hz: int) -> void:
	_setup(hz)
	await _fire()
	var row: Dictionary = game.sniper_match.shot_snapshots[0]
	check(row.hit and absf(row.horizontal) < 0.01 and absf(row.vertical) < 0.01, "centered hit snapshot")
	check(row.number == 1 and row.time == 0 and row.distance > 9, "shot number time distance")
	_aim(8, 6)
	await _fire()
	row = game.sniper_match.shot_snapshots[1]
	check(not row.hit and absf(row.horizontal - 8) < 0.05 and absf(row.vertical - 6) < 0.05,
		"right/up signed errors")
	_aim(-7, -5)
	await _fire()
	row = game.sniper_match.shot_snapshots[2]
	check(not row.hit and absf(row.horizontal + 7) < 0.05 and absf(row.vertical + 5) < 0.05,
		"left/down signed errors")
	var saved := row.duplicate(true)
	_aim(0, 0)
	game.player.instant_movement = true
	game.input.held[KEY_D] = true
	game.input.held[KEY_W] = true
	_event(MOUSE_BUTTON_RIGHT, true)
	await _fire()
	row = game.sniper_match.shot_snapshots[3]
	check(row.scoped and row.zoom == 2 and row.input_move.x > 0 and row.input_move.y < 0, "scope and diagonal input snapshot")
	check(row.lateral_speed > 1 and row.forward_speed > 1, "actual view-relative movement snapshot")
	check(game.sniper_match.shot_snapshots[2] == saved, "later movement does not change history")
	var count: int = game.sniper_match.shot_snapshots.size()
	_event(MOUSE_BUTTON_LEFT, false)
	_event(MOUSE_BUTTON_LEFT, true)
	await _step()
	check(game.sniper_match.shot_snapshots.size() == count, "cooldown clicks excluded")
	game.input.held.clear()
	_event(MOUSE_BUTTON_RIGHT, false)
	_aim(0, 0)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 0.5)
	collision.shape = box
	wall.add_child(collision)
	game.add_child(wall)
	wall.position = Vector3(0, 2, -5)
	await _fire()
	row = game.sniper_match.shot_snapshots.back()
	check(not row.hit and row.center_blocked and row.trace == "击中场景" and row.ray_distance < row.distance,
		"blocked shot classified from real rays")
	wall.queue_free()
	await physics_frame
	game._manual_review()
	saved_report = game.last_review.duplicate(true)
	var panel: Control = game.hud.review_panel.shot_review
	check(panel.rows.size() == 5 and panel.selected.number == 1, "review contains all real shots")
	panel.next.pressed.emit()
	check(panel.selected.number == 2 and panel.detail.text.contains("偏右"), "next shot navigation")
	panel.previous.pressed.emit()
	check(panel.selected.number == 1, "previous shot navigation")
	panel.misses.button_pressed = true
	check(not panel.selected.hit and panel.filtered.size() >= 3, "miss-only filter")
	panel._show(panel.filtered.size() - 1)
	check(panel.detail.text.contains("视线被挡"), "blocked explanation")
	check(panel.next.disabled, "end navigation disabled")
	var copy_count: int = game.last_review.shot_snapshots.size()
	game.reset_training()
	check(saved_report.shot_snapshots.size() == copy_count and game.sniper_match.shot_snapshots.is_empty(), "review snapshot survives new round copy")


func _tracer_rules() -> void:
	for sniper in [false, true]:
		var totals: Array = []
		for show in [true, false]:
			_setup(120, sniper)
			game._set_preference("attack", true)
			game._set_preference("aim_level", 100)
			game._set_preference("player_tracer", show)
			game._set_preference("bot_tracer", show)
			await _fire()
			check(game.beam.visible == show and game.bot_beam.visible == show, "tracer visibility both modes")
			check(game.get_node("Camera/WeaponModel").flash.visible, "hidden tracer preserves muzzle flash")
			totals.append([game.weapon.hits, game.bot_weapon.hits, game.player_health, game.target.health,
				game.sniper_match.player_points, game.sniper_match.bot_points])
			var tick: int = game.clock.tick
			game._set_preference("crosshair_width", 3)
			check(game.clock.tick == tick and not game.review.mixed_settings, "cosmetics do not restart or invalidate scoring")
			game._set_preference("player_tracer", true)
			game._set_preference("bot_tracer", false)
			game._process(0)
			check(game.beam.visible and not game.bot_beam.visible, "independent tracer switches")
		check(totals[0] == totals[1], "tracers never affect hits or score")
	game._set_preference("attack", false)


func _visual_controls() -> void:
	_setup(120)
	game.pause_training()
	game.hud.preference_controls.crosshair_color.color_changed.emit(Color("#fa26c1"))
	game.hud.preference_controls.scope_color.color_changed.emit(Color("#35d498"))
	game.hud.preference_controls.crosshair_width.value = 4
	game.hud.preference_controls.scope_width.value = 3
	game.hud.preference_controls.crosshair_dot.value = 0
	game.hud.preference_controls.scope_dot.value = 0
	game.hud.preference_controls.scope_mask.value = 0
	check(game.hud.crosshair_color == Color("#fa26c1") and game.hud.crosshair_width == 4 \
		and game.hud.crosshair_dot == 0, "crosshair controls apply")
	check(game.hud.scope_overlay.line_color == Color("#35d498") and game.hud.scope_overlay.line_width == 3 \
		and game.hud.scope_overlay.dot_radius == 0 and game.hud.scope_overlay.mask_strength == 0, "scope controls apply")
	game.hud.preference_controls.scope_mask.value = 100
	check(game.hud.scope_overlay.mask_strength == 1, "full mask works")
	game.hud.sync_preferences(game.preferences.values, game.input.bindings)
	check(game.hud.preference_controls.crosshair_color.color == Color("#fa26c1"), "color controls sync")
	var panel := preload("res://scripts/ui/shot_review.gd").new()
	root.add_child(panel)
	panel.load_shots([], 0)
	check(panel.select.disabled and panel.previous.disabled and panel.next.disabled, "empty shot history navigation safe")
	var hit: Dictionary = saved_report.shot_snapshots[0]
	panel.load_shots([hit], 0)
	panel.misses.button_pressed = true
	check(panel.selected.is_empty() and panel.detail.text.contains("没有未命中"), "all-hit miss filter empty state")
	panel.misses.button_pressed = false
	check(panel.selected.number == hit.number, "clear filter recovers shot")
	panel.queue_free()


func _capture(path: String) -> void:
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/" + path + ".png")


func _screenshots() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		game.pause_training()
		game.hud.show_review(saved_report)
		game.hud.review_panel.shot_review._show(1)
		await _capture("shot-review-%d" % size.x)
		game.hud.hide_review()
		game.hud.set_paused(true)
		game.hud.tabs.current_tab = 5
		await _capture("shot-visual-settings-%d" % size.x)
		game.hud.tabs.get_child(5).scroll_vertical = 10000
		await _capture("shot-tracer-settings-%d" % size.x)
		game.hud.tabs.get_child(5).scroll_vertical = 0
	game.resume_training()
	_event(MOUSE_BUTTON_RIGHT, true)
	await _step()
	game.hud.preference_controls.scope_mask.value = 0
	await _capture("scope-custom-transparent")
	game.hud.preference_controls.scope_mask.value = 100
	await _capture("scope-custom-opaque")
