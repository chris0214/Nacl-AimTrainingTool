extends SceneTree

const STEP := 1.0 / 120.0
const FLANK = preload("res://scripts/actors/flank_controller.gd")
const SETTINGS = preload("res://scripts/actors/bot_settings.gd")
var game: Node3D
var bot: Node3D
var checks := 0
var failures := 0
var cap := 60
var results: Array = []
var trace: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", description)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cap="):
			cap = int(arg.trim_prefix("--cap="))
	_test_controller()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	Engine.max_fps = cap
	bot = game.target
	for replay_seed in [41837, 75193, 90217]:
		var row: Dictionary = await _case("spacing", replay_seed, 10, Vector3(0, 0, -11), 7200)
		check(row.mean_distance > 8.0 and row.close_seconds == 0, "default long-run distance remains outside face range")
		check(row.attempts == 0, "does not attempt flanks against a continuously facing player")
	var close_row: Dictionary = await _case("spacing", 41837, 10, Vector3(0, 0, -2), 1440)
	check(close_row.close_seconds < 1.2 and close_row.final_distance > 7.0, "close spawn promptly recovers spacing")
	var near_row: Dictionary = await _case("spacing", 41837, 6, Vector3(0, 0, -11), 3600)
	var far_row: Dictionary = await _case("spacing", 41837, 14, Vector3(0, 0, -11), 3600)
	check(far_row.mean_distance > near_row.mean_distance + 3.0, "distance control changes measured average")
	for replay_seed in [41837, 75193, 90217]:
		var row: Dictionary = await _case("opening", replay_seed, 10, Vector3(0, 0, -9), 1200)
		check(row.attempts > 0 and row.behind_ticks > 0, "side opening creates real behind-player movement")
		check(row.successes > 0, "completed flank stops in the rear sector")
		check(row.max_flank_seconds <= 3.02, "flank commitment time bounded")
		check(row.close_seconds == 0, "flanking does not require hugging player")
	var disabled: Dictionary = await _case("disabled", 41837, 10, Vector3(0, 0, -9), 1200)
	check(disabled.attempts == 0, "zero flank setting disables opportunistic flanks")
	var normal_flank: Dictionary = await _case("default_opening", 41837, 10, Vector3(0, 0, -9), 1200)
	check(normal_flank.attempts > 0 and normal_flank.successes > 0, "default chance can exploit an opening")
	var wall: Dictionary = await _case("wall", 41837, 10, Vector3(16, 0, -2), 1200)
	check(wall.max_flank_seconds <= 3.02, "wall scenario cannot latch a flank indefinitely")
	bot.flank.active = true
	game.pause_training()
	check(not bot.flank.active and bot.flank.views.is_empty(), "pause clears flank and view history")
	game._set_preference("roaming", false)
	bot.observe_player_command(Vector2.ZERO, 1, false)
	check(bot.flank.views.is_empty() and not bot.flank.active, "fixed lane does not collect flank observations")
	game.hud.bot_controls.engagement_distance.value = 11
	game.hud.bot_controls.engagement_distance.value = 12
	game.hud.bot_controls.flank_chance.value = 25
	check(bot.settings.engagement_distance == 12 and bot.settings.flank_chance == 25
		and game.preferences.values.engagement_distance == 12, "new controls apply and enter preferences")
	var prefs := preload("res://scripts/input/trainer_settings.gd").new()
	prefs.path = "res://artifacts/spacing-settings.cfg"
	prefs.put("engagement_distance", 12)
	prefs.put("flank_chance", 25)
	prefs.save_settings()
	var loaded := preload("res://scripts/input/trainer_settings.gd").new()
	loaded.path = prefs.path
	loaded.load_settings()
	check(loaded.values.engagement_distance == 12 and loaded.values.flank_chance == 25, "settings round trip")
	var file := FileAccess.open("res://artifacts/spacing-flank-%d.json" % cap, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "results": results, "trace": trace}))
	file.close()
	game.queue_free()
	await process_frame
	print("SPACING_FLANK_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_controller() -> void:
	var controller := FLANK.new()
	controller.reset(41837)
	var settings := SETTINGS.new()
	settings.flank_chance = 100
	var radial := Vector3.BACK
	for tick in 120:
		controller.observe(0, 0.18)
		controller.step(radial, 9, settings, false, STEP)
	check(controller.attempts == 0, "frontal tracking is not a flank opportunity")
	var early := false
	for tick in 60:
		controller.observe(deg_to_rad(65), 0.18)
		controller.step(radial, 9, settings, false, STEP)
		if tick < 20:
			early = early or controller.active
	check(not early and controller.active, "flank uses delayed view and waits for sustained opportunity")
	check(controller.side < 0, "flank chooses the side leading away from player view")
	for tick in 60:
		controller.observe(0, 0.18)
		controller.step(radial, 9, settings, false, STEP)
	check(not controller.active and controller.last_end == "faced" and controller.cooldown > 0,
		"turning to face bot aborts flank with cooldown")
	var attempts := controller.attempts
	for tick in 120:
		controller.observe(deg_to_rad(65), 0.18)
		controller.step(radial, 9, settings, false, STEP)
	check(controller.attempts == attempts, "cooldown prevents immediate repeated flanks")
	controller.active = true
	controller.step(radial, 3, settings, true, STEP)
	check(not controller.active and controller.last_end == "spacing", "spacing has priority over flank")
	controller.clear()
	check(not controller.has_view and controller.views.is_empty(), "clear discards perceived facing")
	controller.reset(41837)
	controller.has_view = true
	controller.perceived_forward = Basis(Vector3.UP, deg_to_rad(65)) * Vector3.FORWARD
	controller.active = true
	controller.remaining = 0.01
	controller.step(radial, 9, settings, false, 0.02)
	check(not controller.active and controller.last_end == "timeout", "flank has hard timeout")


func _case(mode: String, replay_seed: int, distance: float, spawn: Vector3, ticks: int) -> Dictionary:
	for key in bot.settings.DEFAULTS:
		bot.configure(key, bot.settings.DEFAULTS[key])
	bot.configure("engagement_distance", distance)
	bot.configure("flank_chance", 0 if mode == "disabled" else (40 if mode == "default_opening" else 100))
	bot.reactive_enabled = false
	bot.roaming_enabled = true
	bot.pressure_enabled = false
	game.player.reset_at(Vector3(8, 0, 2) if mode == "wall" else Vector3.ZERO)
	bot.reset_at(spawn, replay_seed)
	await physics_frame
	var row := {"mode": mode, "seed": replay_seed, "setting": distance,
		"mean_distance": 0.0, "min_distance": INF, "close_seconds": 0.0, "final_distance": 0.0,
		"attempts": 0, "successes": 0, "behind_ticks": 0, "max_flank_seconds": 0.0, "max_arc": 0.0}
	var active_time := 0.0
	var valid := true
	var arc := 0.0
	var direction := 0.0
	for tick in ticks:
		await physics_frame
		var relative: Vector3 = bot.position - game.player.position
		var yaw := atan2(-relative.x, -relative.z) if mode == "spacing" else deg_to_rad(65)
		bot.observe_player_command(Vector2.ZERO, yaw, true)
		var before := Vector2(relative.x, relative.z)
		bot.bot_step(game.player, STEP, false)
		relative = bot.position - game.player.position
		var angle := before.angle_to(Vector2(relative.x, relative.z))
		if absf(angle) > 0.00001:
			if signf(angle) != direction:
				arc = 0.0
				direction = signf(angle)
			arc += absf(angle)
		row.max_arc = maxf(row.max_arc, rad_to_deg(arc))
		var current_distance := Vector2(relative.x, relative.z).length()
		row.mean_distance += current_distance / ticks
		row.min_distance = minf(row.min_distance, current_distance)
		row.close_seconds += STEP if current_distance < 4 else 0.0
		row.final_distance = current_distance
		row.behind_ticks += int((Basis(Vector3.UP, yaw) * Vector3.FORWARD).dot(relative.normalized()) < -0.55)
		active_time = active_time + STEP if bot.flank.active else 0.0
		row.max_flank_seconds = maxf(row.max_flank_seconds, active_time)
		valid = valid and absf(bot.position.x) < 17.8 and absf(bot.position.z) < 15.8 \
			and Vector2(bot.velocity.x, bot.velocity.z).length() <= bot.settings.move_speed + 0.001
		if mode != "spacing":
			trace.append([results.size(), tick, bot.position.x, bot.position.z,
				bot.aim_direction.x, bot.aim_direction.y, bot.aim_direction.z, int(bot.flank.active), bot.flank.attempts])
	row.attempts = bot.flank.attempts
	row.successes = bot.flank.successes
	check(valid, "physical bounds and speed: " + mode)
	check(row.max_arc < 180.0, "flank retains anti-full-circle bound: " + mode)
	print("SPACING_CASE ", row)
	results.append(row)
	return row
