extends SceneTree

const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var trace: Array = []
var game: Node3D


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pause_training()
	game._set_preference("hit_sound", false)
	game._set_preference("armor_sound", false)
	game._set_preference("reactive_bot", false)
	check(game.target.pressure_enabled, "new default uses dynamic pressure")
	var prefs := preload("res://scripts/input/trainer_settings.gd").new()
	prefs.path = "res://artifacts/pressure-settings.cfg"
	prefs.put("roam_style", 0)
	check(prefs.save_settings() == OK, "style saves")
	var loaded := preload("res://scripts/input/trainer_settings.gd").new()
	loaded.path = prefs.path
	loaded.load_settings()
	check(loaded.values.roam_style == 0, "explicit distance style survives reload")
	loaded.put("roam_style", 0.5)
	check(loaded.values.roam_style == 0, "noninteger style rejected")
	for seed_value in [17, 18431, 829]:
		await _scenario(seed_value, false, false)
	await _scenario(17, true, false)
	await _scenario(17, false, true)
	game._set_preference("roam_style", 0)
	game.target.reset_at(Vector3(0, 0, -8), 19)
	await physics_frame
	game.target.bot_step(game.player, STEP, false)
	check(game.target.spacing_out, "old stand-off style remains selectable")
	game._set_preference("roam_style", 1)
	check(not game.target.spacing_out and game.target.pressure.remaining == 0, "style switch clears stale retreat")
	game.target.reset_at(Vector3(0, 0, -8), 19)
	await physics_frame
	game.target.bot_step(game.player, STEP, false)
	check(not game.target.spacing_out, "8m is no longer emergency retreat in pressure style")
	game.target.reset_at(Vector3(0, 0, -2), 19)
	for tick in 240:
		await physics_frame
		game.target.bot_step(game.player, STEP, false)
	check(game.target.position.distance_to(game.player.position) > 4.5, "point-blank start escapes without permanent stand-off")
	game._set_preference("roaming", false)
	check(game.hud.preference_controls.roam_style.disabled, "fixed lane disables roam style")
	if DisplayServer.get_name() != "headless":
		game._set_preference("roaming", true)
		game.pause_training()
		game._process(0)
		game.hud.bot_section_buttons.movement.button_pressed = true
		for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
			root.size = size
			game.hud._reveal_bot_section("movement")
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/pressure-settings-%dx%d.png" % [size.x, size.y])
	var cap := "120"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cap="):
			cap = arg.trim_prefix("--cap=").validate_filename()
	var file := FileAccess.open("res://artifacts/pressure-trace-%s.json" % cap, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "trace": trace}))
	file.close()
	game.queue_free()
	await process_frame
	print("PRESSURE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _scenario(seed_value: int, moving: bool, advanced: bool) -> void:
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -12), seed_value)
	var minimum := INF
	var maximum := 0.0
	var total := 0.0
	var close_ticks := 0
	var orbit_ticks := 0
	var toward_ticks := 0
	var away_ticks := 0
	var maximum_speed := 0.0
	var maximum_run := 0.0
	var run_angle := 0.0
	var last_sign := 0.0
	var reversals := 0
	var firing_ticks := 0
	var previous_offset: Vector3 = game.target.position - game.player.position
	for tick in 2400:
		await physics_frame
		var input_move := Vector2(1 if int(tick / 180) % 2 == 0 else -1, 0) * 0.3 if moving else Vector2.ZERO
		game.player.simulate(input_move, 0, false, STEP)
		game.target.observe_player_command(input_move, 0, true)
		game.target.bot_step(game.player, STEP, advanced)
		var offset: Vector3 = game.target.position - game.player.position
		offset.y = 0
		var distance := offset.length()
		var speed := Vector2(game.target.velocity.x, game.target.velocity.z).length()
		var radial_velocity: float = game.target.velocity.dot(-offset.normalized())
		var angle := Vector2(previous_offset.x, previous_offset.z).angle_to(Vector2(offset.x, offset.z))
		var sign_angle := signf(angle) if absf(angle) > 0.0001 else 0.0
		if sign_angle != 0:
			if sign_angle != last_sign:
				reversals += int(last_sign != 0)
				run_angle = 0
			run_angle += absf(angle)
			last_sign = sign_angle
		maximum_run = maxf(maximum_run, run_angle)
		previous_offset = offset
		minimum = minf(minimum, distance)
		maximum = maxf(maximum, distance)
		total += distance
		close_ticks += int(distance < 3.5)
		orbit_ticks += int(game.target.pressure.phase == "orbit")
		toward_ticks += int(radial_velocity > 0.5)
		away_ticks += int(radial_velocity < -0.5)
		firing_ticks += int(game.target.fire)
		maximum_speed = maxf(maximum_speed, speed)
		trace.append([seed_value, int(moving), int(advanced), tick, game.target.position.x, game.target.position.y,
			game.target.position.z, game.target.velocity.x, game.target.velocity.y, game.target.velocity.z])
	print("PRESSURE_CASE seed=%d moving=%s air=%s min=%.3f max=%.3f mean=%.3f close=%.2fs toward=%.2fs away=%.2fs orbit=%.2fs turns=%d arc=%.1f speed=%.3f" % [
		seed_value, moving, advanced, minimum, maximum, total / 2400, close_ticks * STEP, toward_ticks * STEP,
		away_ticks * STEP, orbit_ticks * STEP, reversals, rad_to_deg(maximum_run), maximum_speed])
	check(minimum < 9.5, "pressure actually closes inside old stand-off band")
	check(maximum - minimum > 3.0, "meaningful near and far variation")
	check(toward_ticks > 240 and away_ticks > 120 and orbit_ticks > 120, "approach retreat and orbit all occur")
	check(close_ticks < 240, "does not spend prolonged time point blank")
	check(reversals >= 10 and maximum_run < PI * 1.7, "orbit reverses instead of full same-direction circle")
	check(maximum_speed < 5.52, "pressure respects configured speed")
	check(firing_ticks > 2300, "continuous aim and fire through pressure episodes")
