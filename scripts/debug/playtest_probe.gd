extends Node

var enabled: bool = false
var frames: int = 0
var captured: bool = false
var running: bool = false
var benchmark: bool = false
var cap: int = 240
var mode: String = "normal"
var rows: Array = []
var started_usec: int = 0
var frame_times: Array[float] = []
var max_height: float = 0.0
var warm_steps: int = 0
var result_written: bool = false
var tick_limit: int = 7200
var stall_ms: int = 0
var injected: bool = false
var static_sequence: bool = false
var capture_suffix := ""
var probe_width := -1.0
var probe_assist := 0
var probe_no_reaction := false
var probe_sky := 0
var probe_aim := -1.0


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	enabled = "--probe" in arguments
	benchmark = "--benchmark" in arguments
	for argument in arguments:
		if argument.begins_with("--probe-size="):
			var dimensions := argument.trim_prefix("--probe-size=").split("x")
			get_window().size = Vector2i(int(dimensions[0]), int(dimensions[1]))
			capture_suffix = "-" + argument.trim_prefix("--probe-size=")
		if argument.begins_with("--probe-width="):
			probe_width = float(argument.trim_prefix("--probe-width="))
		if argument.begins_with("--probe-assist="):
			probe_assist = int(argument.trim_prefix("--probe-assist="))
		if argument.begins_with("--probe-suffix="):
			capture_suffix = argument.trim_prefix("--probe-suffix=")
		if argument == "--probe-no-reaction":
			probe_no_reaction = true
		if argument.begins_with("--probe-sky="):
			probe_sky = int(argument.trim_prefix("--probe-sky="))
		if argument.begins_with("--probe-aim="):
			probe_aim = float(argument.trim_prefix("--probe-aim="))
		if argument.begins_with("--cap="):
			cap = int(argument.trim_prefix("--cap="))
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		if argument.begins_with("--ticks="):
			tick_limit = int(argument.trim_prefix("--ticks="))
		if argument.begins_with("--stall="):
			stall_ms = int(argument.trim_prefix("--stall="))
		if argument == "--static":
			static_sequence = true
	if benchmark:
		call_deferred("_prepare_benchmark")
	if enabled:
		call_deferred("_prepare_features")
	set_process(enabled or benchmark)


func _process(_delta: float) -> void:
	if enabled and _delta > 0.1:
		print("PROBE_SLOW_FRAME delta=", _delta, " frames=", frames,
			" tick=", get_parent().clock.tick, " reaction=", get_parent().target.reaction_count)
	if benchmark:
		if running:
			frame_times.append(_delta)
			if get_parent().paused and not result_written:
				_finish(true)
			elif stall_ms > 0 and not injected and get_parent().clock.tick >= 120:
				injected = true
				OS.delay_msec(stall_ms)
		return
	frames += 1
	if frames == 300 and not captured:
		captured = true
		_capture()


func _prepare_features() -> void:
	if probe_aim >= 0:
		get_parent()._set_preference("aim_level", probe_aim)
	get_parent()._set_preference("sky_style", probe_sky)
	if probe_width > 0.0:
		get_parent()._set_preference("body_width", probe_width)
	if probe_no_reaction:
		get_parent()._set_preference("reactive_bot", false)
	get_parent()._set_preference("assist_mode", probe_assist)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var image := get_viewport().get_texture().get_image()
	print("VIEWPORT_CHECK window=", get_window().size, " visible=", get_viewport().get_visible_rect().size,
		" texture=", get_viewport().get_texture().get_size(), " image=", image.get_size(),
		" mode=", get_window().content_scale_mode, " factor=", get_window().content_scale_factor)
	image.save_png("res://artifacts/playtest-arena%s.png" % capture_suffix)
	get_parent().pause_training()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	image.save_png("res://artifacts/playtest-settings%s.png" % capture_suffix)
	if probe_aim >= 0:
		var hud = get_parent().hud
		var scroll: ScrollContainer = hud.aim_profile_label.get_parent().get_parent().get_parent()
		scroll.ensure_control_visible(hud.aim_profile_label)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/playtest-aim%s.png" % capture_suffix)
	for index in [1, 2, 3, 4]:
		get_parent().hud.tabs.current_tab = index
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"res://artifacts/playtest-tab-%d%s.png" % [index, capture_suffix])
	get_parent().hud.tabs.current_tab = 0
	get_parent().hud.hide()
	for preset in 3:
		get_parent()._set_preference("sky_style", preset)
		get_parent()._set_preference("arena_style", preset)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"res://artifacts/playtest-scene-%d%s.png" % [preset, capture_suffix])
	get_parent()._set_preference("sky_style", probe_sky)
	get_parent()._set_preference("arena_style", 0)
	get_parent().hud.show()
	get_parent().resume_training()
	get_parent().reset_training()
	get_parent().ready_to_start = false
	get_parent().clock.reset(Time.get_ticks_usec())
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	fire.pressed = true
	get_parent().input.ingest(fire, Time.get_ticks_usec())
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	image.save_png("res://artifacts/playtest-firing%s.png" % capture_suffix)
	print("PROBE_HITS ", get_parent().weapon.hits,
		" PLAYER_HEALTH ", get_parent().player_health,
		" BOT_HEALTH ", get_parent().target.health,
		" BOT_SHOTS ", get_parent().bot_weapon.shots,
		" PAUSED ", get_parent().paused,
		" TICKS ", get_parent().clock.tick,
		" MAX_GAP_US ", get_parent().clock.max_gap_usec,
		" BACKLOG_US ", get_parent().clock.backlog_usec)
	if get_parent().paused or get_parent().clock.tick < 60:
		printerr("PROBE_FAILED: training did not advance normally")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/playtest-motion%s.png" % capture_suffix)
	get_parent().change_mode(true)
	get_parent().ready_to_start = false
	get_parent().clock.reset(Time.get_ticks_usec())
	get_parent().target.jump_time = 0.01
	await get_tree().create_timer(0.28).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/playtest-air%s.png" % capture_suffix)
	if get_parent().target.position.y < 0.5:
		printerr("PROBE_FAILED: advanced bot did not jump")
		get_tree().quit(1)
		return
	get_parent().pause_training()
	get_parent().hud.hide()
	get_parent().get_node("Camera/WeaponModel").hide()
	get_parent().camera.global_position = get_parent().target.global_position + Vector3(2, 1.6, 3)
	get_parent().camera.look_at(get_parent().target.global_position + Vector3.UP, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/playtest-robot-detail%s.png" % capture_suffix)
	print("PROBE_COMPLETE")
	get_tree().quit()


func _prepare_benchmark() -> void:
	get_parent().change_mode(mode == "advanced")
	get_parent()._set_preference("sky_style", probe_sky)
	Engine.max_fps = cap


func command_for_tick(tick: int) -> Dictionary:
	if static_sequence:
		return {"move": Vector2.ZERO, "jump": false, "fire": true, "fire_pressed": tick == 0}
	var phase := tick % 1200
	var move := Vector2.ZERO
	if phase >= 240 and phase < 480:
		move = Vector2.RIGHT
	elif phase >= 480 and phase < 720:
		move = Vector2.LEFT
	elif phase >= 720 and phase < 960:
		move = Vector2(0, -1)
	elif phase >= 960:
		move = Vector2(0, 1)
	return {"move": move, "jump": tick % 180 == 60, "fire": true, "fire_pressed": tick == 0}


func after_step() -> void:
	var game := get_parent()
	if not running:
		warm_steps += 1
		if warm_steps >= 120:
			game.ready_to_start = false
			game.clock.reset(Time.get_ticks_usec())
			started_usec = Time.get_ticks_usec()
			running = true
		return
	var p: Vector3 = game.player.position
	var v: Vector3 = game.player.velocity
	max_height = maxf(max_height, p.y)
	rows.append([game.clock.tick, p.x, p.y, p.z, v.x, v.y, v.z,
		game.weapon.shots, game.weapon.hits, game.weapon.damage, game.player.jumps])
	if game.clock.tick >= tick_limit and not result_written:
		_finish(false)


func _finish(overloaded: bool) -> void:
	result_written = true
	running = false
	var game := get_parent()
	game.paused = true
	frame_times.sort()
	var elapsed := (Time.get_ticks_usec() - started_usec) / 1000000.0
	var average: float = 0.0
	for value in frame_times:
		average += value
	average /= maxf(1, frame_times.size())
	var result := {
		"mode": mode, "requested_cap": cap, "ticks": game.clock.tick,
		"wall_seconds": elapsed, "simulation_seconds": game.clock.tick / 120.0,
		"mean_fps": 1.0 / maxf(0.000001, average),
		"p95_frame_ms": frame_times[int((frame_times.size() - 1) * 0.95)] * 1000 if not frame_times.is_empty() else 0,
		"shots": game.weapon.shots, "hits": game.weapon.hits, "damage": game.weapon.damage,
		"jumps": game.player.jumps, "max_height": max_height,
		"backlog_usec": game.clock.backlog_usec, "max_gap_usec": game.clock.max_gap_usec,
		"stall_ms": stall_ms, "static_sequence": static_sequence,
		"overloaded": overloaded, "trace": rows,
		"sky_style": game.preferences.values.sky_style, "audio_events": game.hit_audio.played_events
	}
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var path := "res://artifacts/benchmark-%s-%d.json" % [mode, cap]
	if stall_ms > 0:
		path = "res://artifacts/stall-%d.json" % stall_ms
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("BENCHMARK_COMPLETE ", path, " wall=", elapsed, " ticks=", game.clock.tick, " overloaded=", overloaded)
	get_tree().quit(1 if overloaded else 0)
