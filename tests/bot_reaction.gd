extends SceneTree

const AIM = preload("res://scripts/actors/bot_aim.gd")
const PREFS = preload("res://scripts/input/trainer_settings.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node3D
var cap := 60
var trace: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cap="):
			cap = int(argument.trim_prefix("--cap="))
	for level in [20.0, 60.0, 95.0, 100.0]:
		_test_delay(level)
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	Engine.max_fps = cap
	await _test_ground_and_air()
	await _test_real_reversal()
	_test_settings()
	var file := FileAccess.open("res://artifacts/reaction-aim-%d.json" % cap, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "trace": trace}))
	file.close()
	game.queue_free()
	await process_frame
	print("BOT_REACTION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_delay(level: float) -> void:
	var delay_ms: float = AIM.delay_for_level(level)
	var a := AIM.new()
	var b := AIM.new()
	var random_a := RandomNumberGenerator.new()
	var random_b := RandomNumberGenerator.new()
	random_a.seed = 1801
	random_b.seed = 1801
	a.reset(random_a)
	b.reset(random_b)
	var origin := Vector3(0, 1, -10)
	var point := Vector3(0, 1, 0)
	for tick in 180:
		point.x += 4.0 * STEP
		a.step(origin, point, 0.34, level, STEP, random_a)
		b.step(origin, point, 0.34, level, STEP, random_b)
	var reverse_point := point
	var unchanged_until_delay := true
	var first_difference := -1
	var old_direction_observed := false
	for tick in 120:
		point.x += 4.0 * STEP
		reverse_point.x -= 4.0 * STEP
		var aim_a: Vector3 = a.step(origin, point, 0.34, level, STEP, random_a)
		var aim_b: Vector3 = b.step(origin, reverse_point, 0.34, level, STEP, random_b)
		if tick * STEP < delay_ms / 1000.0 - 0.000001:
			unchanged_until_delay = unchanged_until_delay and aim_a.is_equal_approx(aim_b)
			old_direction_observed = old_direction_observed or b.perceived_velocity.x > 3.9
		if first_difference < 0 and not aim_a.is_equal_approx(aim_b):
			first_difference = tick
	check(unchanged_until_delay, "future reversal hidden until delay %s" % delay_ms)
	check(first_difference >= 0 and absf(first_difference * STEP * 1000.0 - delay_ms) <= 9.0,
		"correction begins at delay within one physics tick %s" % delay_ms)
	check(delay_ms == 0 or old_direction_observed, "old movement prediction survives reversal %s" % delay_ms)
	check((level == 100 or b.perceived_velocity.x < -3.9) and b.tracked_point.distance_to(reverse_point) < 0.25,
		"eventually reacquires reversed target %s" % delay_ms)
	check(b.observations.size() <= 50, "visual history bounded %s" % delay_ms)
	b.clear_history()
	check(b.observations.is_empty() and not b.initialized and not b.observing, "clear history %s" % delay_ms)
	var new_point := Vector3(-5, 1, 0)
	b.step(origin, new_point, 0.34, level, STEP, random_b)
	check(b.tracked_point == new_point and b.perceived_velocity == Vector3.ZERO, "restart has no stale velocity %s" % delay_ms)


func _test_ground_and_air() -> void:
	var bot: Node3D = game.target
	game._set_preference("roaming", false)
	game._set_preference("reactive_bot", false)
	bot.configure("randomness", 0)
	bot.configure("move_speed", 6)
	bot.configure("strafe_extent", 5)
	bot.reset_at(Vector3(0, 0, -4), 18431)
	await physics_frame
	bot.bot_step(game.player, STEP, false)
	check(is_equal_approx(Vector2(bot.velocity.x, bot.velocity.z).length(), 6), "first ground tick full speed")
	var before: Vector3 = bot.velocity
	bot.strafe_direction = -bot.strafe_direction
	bot.action_time = 1
	await physics_frame
	bot.bot_step(game.player, STEP, false)
	var after: Vector3 = bot.velocity
	before.y = 0
	after.y = 0
	check(after.is_equal_approx(-before), "ground reversal changes full velocity in one tick")
	bot.configure("move_speed", 2)
	await physics_frame
	bot.bot_step(game.player, STEP, false)
	check(is_equal_approx(Vector2(bot.velocity.x, bot.velocity.z).length(), 2), "ground pace change has no easing")
	bot.configure("move_speed", 0)
	await physics_frame
	bot.bot_step(game.player, STEP, false)
	check(Vector2(bot.velocity.x, bot.velocity.z).length() == 0, "zero speed stops on ground")
	bot.configure("move_speed", 6)
	bot.configure("air_control", 0)
	bot.reset_at(Vector3(0, 2, -4), 18431)
	await physics_frame
	# move_and_slide refreshes the floor flag cached before this test teleported the actor.
	bot.bot_step(game.player, STEP, true)
	bot.velocity = Vector3(4, 0, 0)
	bot.bot_step(game.player, STEP, true)
	check(is_equal_approx(bot.velocity.x, 4) and absf(bot.velocity.z) < 0.001, "zero air control preserves inertia")
	bot.configure("air_control", 12)
	bot.strafe_direction = -1
	bot.lane_axis = Vector3.RIGHT
	bot.action_time = 1
	var previous := Vector2(bot.velocity.x, bot.velocity.z)
	await physics_frame
	bot.bot_step(game.player, STEP, true)
	check(previous.distance_to(Vector2(bot.velocity.x, bot.velocity.z)) <= 12 * STEP + 0.001,
		"advanced air acceleration remains bounded")


func _test_real_reversal() -> void:
	var bot: Node3D = game.target
	var excluded: Array[RID] = [bot.get_rid(), bot.hit_area.get_rid()]
	var samples: Array = []
	for level in [100.0, 80.0]:
		var delay_ms: float = AIM.delay_for_level(level)
		bot.configure("move_speed", 0)
		bot.configure("aim_level", level)
		bot.reset_at(Vector3(0, 0, -6), 18431)
		game.player.reset_at(Vector3(-4, 0, 4))
		var early_hits := 0
		var late_hits := 0
		for tick in 240:
			var speed := 6.0 if tick < 120 else -6.0
			game.player.position.x += speed * STEP
			await physics_frame
			bot.aim_step(game.player, STEP, true)
			if tick >= 120:
				var ray: Dictionary = game.bot_weapon.trace(game.get_world_3d().direct_space_state,
					bot.muzzle_position(), bot.aim_direction, excluded)
				trace.append([delay_ms, tick, bot.aim_direction.x, bot.aim_direction.y,
					bot.aim_direction.z, int(ray.get("collider") == game.player)])
				if tick < 144:
					early_hits += int(ray.get("collider") == game.player)
				elif tick >= 216:
					late_hits += int(ray.get("collider") == game.player)
		samples.append({"delay": delay_ms, "early_hits": early_hits, "late_hits": late_hits})
	check(samples[0].early_hits >= 22, "no-delay reference can track immediate reversal")
	check(samples[1].early_hits < samples[0].early_hits - 6, "visual delay actually loses real ray hits after AD reversal")
	check(samples[1].late_hits > samples[1].early_hits, "human tracker recovers after reversal")
	print("REVERSAL_RAY_SAMPLES ", samples)
	game.pause_training()
	check(bot.aim_model.observations.is_empty(), "pause flushes visual history")


func _test_settings() -> void:
	game.hud.bot_controls.aim_level.value = 60
	check(game.target.settings.aim_level == 60 and game.preferences.values.aim_level == 60,
		"unified aim control reaches actor and preferences")
	check(game.target.aim_model.observations.is_empty(), "delay change clears stale observations")
	game.target.aim_step(game.player, STEP, true)
	var pending: int = game.target.aim_model.observations.size()
	game._set_preference("reactive_bot", false)
	game._set_preference("reaction_delay", 300)
	check(game.target.settings.aim_level == 60 and game.target.aim_model.observations.size() == pending,
		"locomotion reaction settings do not reset visual reaction history")
	var settings := PREFS.new()
	settings.path = "res://artifacts/reaction-settings.cfg"
	settings.put("aim_level", 60)
	settings.save_settings()
	var loaded := PREFS.new()
	loaded.path = settings.path
	loaded.load_settings()
	check(loaded.values.aim_level == 60, "aim level persists")
	loaded.put("aim_level", 900)
	check(loaded.values.aim_level == 100, "aim level upper bound")
	loaded.put("aim_level", NAN)
	check(loaded.values.aim_level == 100, "invalid aim level rejected")
