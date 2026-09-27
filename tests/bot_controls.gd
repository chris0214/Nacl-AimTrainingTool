extends Node

var game: Node3D
var bot: Node3D
var steps := 0
var checks := 0
var failures := 0
var cap := 60
var slow_frames := 0
var max_slow_frames := 0
var never_stopped_firing := true
var max_offset := 0.0
var max_speed := 0.0
var low_hits := 0
var high_hits := 0
var slow_distance := 0.0
var fast_distance := 0.0
var pause_position := Vector3.ZERO
var pause_animation := 0.0
var trace: Array = []
var started := 0
var max_height := 0.0
var air_reversals := 0
var last_air_velocity := 0.0
var air_firing := true


func _ready() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.set_physics_process(false)
	bot = game.target
	game._set_preference("roaming", false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cap="):
			cap = int(arg.trim_prefix("--cap="))
	Engine.max_fps = cap
	started = Time.get_ticks_usec()
	game.pause_training()
	for key in {"aim_level": 72.0, "move_speed": 6.0, "turn_frequency": 3.0, "strafe_extent": 1.2}:
		var value: float = {"aim_level": 72.0, "move_speed": 6.0, "turn_frequency": 3.0, "strafe_extent": 1.2}[key]
		game.hud.bot_controls[key].value = value
		check(is_equal_approx(float(bot.settings.get(key)), value), "UI connects " + key)
	game.hud.attack_toggle.button_pressed = false
	check(not bot.attack_enabled, "attack toggle connects")
	game.reset_training()
	check(bot.settings.aim_level == 72.0 and bot.settings.move_speed == 6.0, "restart preserves tuning")
	check(not bot.attack_enabled, "restart preserves attack toggle")
	game.hud.attack_toggle.button_pressed = true
	check(bot.attack_enabled, "attack re-enabled")
	game.hud._reset_bot_controls()
	check(is_equal_approx(bot.settings.move_speed, 4.5) and is_equal_approx(bot.settings.strafe_extent, 2.0),
		"defaults restore model and controls")
	check(game.preferences.values.roaming and bot.roaming_enabled, "full Bot reset restores roaming mode")
	# The following displacement assertions exercise fixed-lane movement, not roaming.
	game._set_preference("roaming", false)
	bot.configure("aim_level", 500.0)
	check(bot.settings.aim_level == 100.0, "aim level bounded")
	bot.configure("aim_level", NAN)
	check(bot.settings.aim_level == 100.0, "nonfinite values rejected")
	bot.configure("aim_level", 65.0)
	game.player.position = Vector3(0, 0, 7)
	_reset_bot(4.5, 2.5, 2.0, 65)


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", description)


func _reset_bot(speed: float, frequency: float, extent: float, accuracy: float) -> void:
	bot.reset_at(Vector3(0, 0, -4), 18431)
	bot.configure("move_speed", speed)
	bot.configure("turn_frequency", frequency)
	bot.configure("strafe_extent", extent)
	bot.configure("aim_level", accuracy)
	max_offset = 0.0
	max_speed = 0.0


func _physics_process(delta: float) -> void:
	steps += 1
	if steps <= 240 or steps > 270:
		bot.bot_step(game.player, delta, steps > 1470)
		var speed := Vector2(bot.velocity.x, bot.velocity.z).length()
		max_speed = maxf(max_speed, speed)
		max_offset = maxf(max_offset, absf((bot.position - bot.lane_center).dot(bot.lane_axis)))
		if steps <= 240:
			never_stopped_firing = never_stopped_firing and bot.fire
			slow_frames = slow_frames + 1 if speed < 0.2 else 0
			max_slow_frames = maxi(max_slow_frames, slow_frames)
		if steps > 300 and steps <= 510 and steps % 6 == 0:
			low_hits += int(_ray_hit())
		if steps > 540 and steps <= 750 and steps % 6 == 0:
			high_hits += int(_ray_hit())
		if steps > 1470:
			max_height = maxf(max_height, bot.position.y)
			air_firing = air_firing and bot.fire
			var along: float = bot.velocity.dot(bot.lane_axis)
			if bot.airborne and absf(along) > 0.1:
				if along * last_air_velocity < 0.0:
					air_reversals += 1
				last_air_velocity = along
			elif not bot.airborne:
				last_air_velocity = 0.0
		trace.append([steps, bot.position.x, bot.position.z, bot.aim_direction.x,
			bot.aim_direction.y, bot.aim_direction.z, bot.turn_count, bot.position.y, bot.jumps])
	match steps:
		240:
			check(never_stopped_firing, "continuous attack through direction changes")
			check(max_slow_frames < 12, "no random stop intervals")
			check(max_speed <= 4.51, "configured speed limit honored")
			check(max_offset <= 2.10, "lane extent honored")
			check(bot.turn_count >= 4, "turn frequency active")
			var arm: int = bot.skeleton.find_bone("upperarm_r")
			var expected: Transform3D = bot.upper_pose[arm]
			check(bot.skeleton.get_bone_pose(arm).is_equal_approx(expected), "upper body holds rifle pose while strafing")
			game.pause_training()
			pause_position = bot.position
			pause_animation = bot.animator.current_animation_position
		270:
			check(bot.position == pause_position and bot.animator.current_animation_position == pause_animation,
				"pause freezes motion and aim animation")
			game.resume_training()
			_reset_bot(0, 2.5, 2, 0)
		510:
			check(max_speed == 0.0 and bot.fire, "zero speed remains aiming and firing")
			_reset_bot(0, 2.5, 2, 100)
		750:
			check(high_hits > low_hits, "higher accuracy produces more actual ray hits")
			check(high_hits >= 33, "maximum aim reliably tracks a stationary player")
			_reset_bot(2, 0.5, 5, 65)
		990:
			slow_distance = max_offset
			_reset_bot(8, 0.5, 5, 65)
		1230:
			fast_distance = max_offset
			check(fast_distance > slow_distance + 0.5, "speed increases travel distance")
			_reset_bot(4, 6, 0.4, 65)
		1470:
			check(max_offset <= 0.50, "small extent limits displacement")
			check(bot.turn_count >= 10, "high frequency creates short strafes")
			check(bot.rotation.is_zero_approx(), "collision is never tilted by animation")
			game.reset_training()
			game.hud.update_duel_state(game.player_health, bot.health, "", false, 0.0, game.bot_weapon)
			check(game.hud.player_health_value.text == "1000" and game.hud.target_health_value.text == "1000",
				"numeric HUD and health agree after reset")
			_reset_bot(4.5, 4.0, 2.0, 65)
		2190:
			check(bot.jumps >= 3 and max_height > 0.8, "advanced mode produces repeated physical jumps")
			check(air_reversals >= 2, "advanced mode reverses velocity while airborne")
			check(air_firing, "advanced bot maintains fire through jumps")
			bot.configure("air_control", 0.0)
		2310:
			game.change_mode(false)
			check(bot.position.y == 0.0 and not bot.airborne and bot.jumps == 0,
				"normal mode resets airborne state")
			_finish()


func _ray_hit() -> bool:
	var excluded: Array[RID] = [bot.get_rid(), bot.hit_area.get_rid()]
	var result: Dictionary = game.bot_weapon.trace(game.get_world_3d().direct_space_state,
		bot.muzzle_position(), bot.aim_direction, excluded)
	return result.get("collider") == game.player


func _finish() -> void:
	var file := FileAccess.open("res://artifacts/bot-controls-%d.json" % cap, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"cap": cap, "checks": checks, "failures": failures, "low_hits": low_hits,
		"high_hits": high_hits, "sample_shots": 35, "slow_distance": slow_distance,
		"fast_distance": fast_distance, "max_idle_ticks": max_slow_frames,
		"wall_seconds": (Time.get_ticks_usec() - started) / 1000000.0, "trace": trace
	}))
	file.close()
	print("BOT_CONTROLS_RESULT cap=%d checks=%d failures=%d low=%d high=%d" % [
		cap, checks, failures, low_hits, high_hits])
	get_tree().quit(1 if failures else 0)
