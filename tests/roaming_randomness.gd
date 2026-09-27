extends Node

const CASE_TICKS := 1920
var game: Node3D
var bot: Node3D
var cap := 60
var checks := 0
var failures := 0
var cases: Array[Dictionary] = []
var case_index := 0
var tick := 0
var sample: Dictionary
var samples: Array = []
var trace: Array = []
var last_tangent_sign := 0.0
var last_radial_sign := 0.0
var angular_run := 0.0
var last_position := Vector2.ZERO
var idle_ticks := 0
var last_turn_tick := 0
var last_air_sign := 0.0
var ray_excluded: Array[RID] = []


func _ready() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	bot = game.target
	ray_excluded = [bot.get_rid(), bot.hit_area.get_rid()]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cap="):
			cap = int(arg.trim_prefix("--cap="))
	Engine.max_fps = cap
	for replay_seed in [41837, 75193, 90217]:
		for profile in ["default", "max", "max_air"]:
			cases.append({"profile": profile, "seed": replay_seed})
	cases.append({"profile": "slow_frequency", "seed": 41837})
	cases.append({"profile": "stationary", "seed": 41837})
	cases.append({"profile": "no_speed_variation", "seed": 41837})
	_start_case()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", cases[case_index], " ", description)


func _start_case() -> void:
	var profile: String = cases[case_index].profile
	for key in bot.settings.DEFAULTS:
		game.hud.bot_controls[key].value = bot.settings.DEFAULTS[key]
	if profile != "default":
		for key in bot.settings.LIMITS:
			game.hud.bot_controls[key].value = bot.settings.LIMITS[key].y
		for key in bot.settings.LIMITS:
			check(bot.settings.get(key) == bot.settings.LIMITS[key].y,
				"maximum slider applies: " + key)
	if profile == "slow_frequency":
		game.hud.bot_controls.turn_frequency.value = 0.5
	elif profile == "stationary":
		game.hud.bot_controls.move_speed.value = 0.0
	elif profile == "no_speed_variation":
		game.hud.bot_controls.randomness.value = 0.0
	game.player.reset_at(Vector3.ZERO)
	bot.reset_at(Vector3(0, 0, -11), cases[case_index].seed)
	last_position = Vector2(bot.position.x, bot.position.z)
	tick = 0
	last_turn_tick = 0
	last_tangent_sign = 0.0
	last_radial_sign = 0.0
	last_air_sign = 0.0
	angular_run = 0.0
	idle_ticks = 0
	sample = {
		"profile": profile, "seed": cases[case_index].seed,
		"tangent_reversals": 0, "radial_reversals": 0, "air_reversals": 0,
		"min_distance": INF, "max_distance": 0.0, "max_speed": 0.0,
		"slow_ticks": 0, "fast_ticks": 0, "max_idle_ticks": 0,
		"max_same_direction_degrees": 0.0, "max_height": 0.0,
		"min_x": INF, "max_x": -INF, "min_z": INF, "max_z": -INF,
		"escaped": false, "tactics": {}, "turn_intervals": [],
		"lateral_ticks": 0, "moving_ticks": 0, "straight_ticks": 0, "max_straight_ticks": 0
	}


func _physics_process(delta: float) -> void:
	tick += 1
	game.player.simulate(Vector2.ZERO, 0, false, delta)
	var advanced: bool = cases[case_index].profile == "max_air"
	bot.bot_step(game.player, delta, advanced)
	var position_2d := Vector2(bot.position.x, bot.position.z)
	var distance := position_2d.length()
	var radial := -position_2d.normalized()
	var tangent := Vector2(-radial.y, radial.x)
	var actual_velocity := (position_2d - last_position) / delta
	var speed := actual_velocity.length()
	var lateral := actual_velocity.dot(tangent)
	var closing := actual_velocity.dot(radial)
	if speed > 0.8:
		sample.moving_ticks += 1
		sample.lateral_ticks += int(absf(lateral) >= absf(closing) * 0.9)
		sample.straight_ticks = sample.straight_ticks + 1 if absf(lateral) < absf(closing) * 0.25 else 0
		sample.max_straight_ticks = maxi(sample.max_straight_ticks, sample.straight_ticks)
	else:
		sample.straight_ticks = 0
	var angle := last_position.angle_to(position_2d)
	if absf(lateral) > 0.8:
		var direction := signf(lateral)
		if last_tangent_sign != 0.0 and direction != last_tangent_sign:
			sample.tangent_reversals += 1
			sample.turn_intervals.append(tick - last_turn_tick)
			last_turn_tick = tick
			angular_run = 0.0
		last_tangent_sign = direction
	angular_run += angle
	sample.max_same_direction_degrees = maxf(sample.max_same_direction_degrees, absf(rad_to_deg(angular_run)))
	if absf(closing) > 0.8:
		var direction := signf(closing)
		if last_radial_sign != 0.0 and direction != last_radial_sign:
			sample.radial_reversals += 1
		last_radial_sign = direction
	if advanced and bot.airborne and absf(lateral) > 0.8:
		var direction := signf(lateral)
		sample.air_reversals += int(last_air_sign != 0.0 and direction != last_air_sign)
		last_air_sign = direction
	elif not bot.airborne:
		last_air_sign = 0.0
	sample.min_distance = minf(sample.min_distance, distance)
	sample.max_distance = maxf(sample.max_distance, distance)
	sample.min_x = minf(sample.min_x, bot.position.x)
	sample.max_x = maxf(sample.max_x, bot.position.x)
	sample.min_z = minf(sample.min_z, bot.position.z)
	sample.max_z = maxf(sample.max_z, bot.position.z)
	sample.max_speed = maxf(sample.max_speed, speed)
	sample.max_height = maxf(sample.max_height, bot.position.y)
	sample.slow_ticks += int(speed < bot.settings.move_speed * 0.5)
	sample.fast_ticks += int(speed > bot.settings.move_speed * 0.8)
	idle_ticks = idle_ticks + 1 if speed < 0.2 else 0
	sample.max_idle_ticks = maxi(sample.max_idle_ticks, idle_ticks)
	sample.escaped = sample.escaped or absf(bot.position.x) > 17.8 or absf(bot.position.z) > 15.8 or bot.position.y < -0.1
	sample.tactics[bot.tactic] = true
	last_position = position_2d
	var shot_hit := -1
	if tick % 6 == 0:
		var ray: Dictionary = game.bot_weapon.trace(game.get_world_3d().direct_space_state,
			bot.muzzle_position(), bot.aim_direction, ray_excluded)
		shot_hit = int(ray.get("collider") == game.player)
	trace.append([case_index, tick, bot.position.x, bot.position.y, bot.position.z,
		bot.velocity.x, bot.velocity.y, bot.velocity.z, bot.roam_speed_factor,
		bot.preferred_distance, bot.strafe_direction, bot.jumps,
		bot.aim_direction.x, bot.aim_direction.y, bot.aim_direction.z, shot_hit])
	if tick == CASE_TICKS:
		_finish_case()


func _finish_case() -> void:
	var profile: String = cases[case_index].profile
	check(not sample.escaped, "stays inside arena")
	check(sample.min_distance > 0.5, "does not pass through player")
	check(sample.max_speed <= bot.settings.move_speed + 0.01, "actual speed respects scalar cap")
	if profile == "stationary":
		check(sample.max_speed < 0.001 and bot.fire, "zero speed holds position and aim")
	else:
		check(sample.max_same_direction_degrees < 180, "no uninterrupted half/full circles")
		check(sample.max_idle_ticks < 24, "no prolonged stop")
		check(sample.tactics.size() >= (2 if profile == "slow_frequency" else 3),
			"orbit at maximum does not starve other tactics")
		# Lateral-first combat deliberately spends less time on radial excursions.
		# Stand-off defaults deliberately narrow the inward excursion.
		var excursion_floor := 1.5 if profile == "default" else 2.0
		check(sample.max_distance - sample.min_distance > excursion_floor, "near/far variation survives lateral priority")
		check(sample.radial_reversals >= (1 if profile == "slow_frequency" else 2),
			"actual closing/backing reversals")
		check(sample.lateral_ticks > sample.moving_ticks * 0.7, "lateral component dominates actual movement")
		check(sample.max_straight_ticks < 24, "no sustained straight charge through reversals")
		var required := 25 if profile in ["max", "max_air"] else 8
		check(sample.tangent_reversals >= required, "frequent physical lateral reversals")
		if profile != "no_speed_variation":
			check(sample.slow_ticks > CASE_TICKS * 0.1 and sample.fast_ticks > CASE_TICKS * 0.1,
				"both slow and fast speed bands occur")
		else:
			check(is_equal_approx(bot.roam_speed_factor, 1.0), "zero randomness removes pace modulation")
		if profile == "max_air":
			check(bot.jumps >= 2 and sample.max_height > 0.8 and sample.air_reversals >= 3,
				"all-max retains real jumps and midair reversals")
		if profile != "no_speed_variation":
			var intervals: Array = sample.turn_intervals
			check(intervals.size() >= 2 and intervals.max() > intervals.min() * 2,
				"reversal timings are not periodic")
	samples.append(sample)
	print("RANDOMNESS_CASE ", JSON.stringify(sample))
	case_index += 1
	if case_index < cases.size():
		_start_case()
	else:
		case_index -= 1
		check(samples[1].tangent_reversals > samples[9].tangent_reversals * 1.8,
			"frequency slider substantially increases actual reversals at maximum orbit")
		var file := FileAccess.open("res://artifacts/randomness-%d.json" % cap, FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures,
			"cap": cap, "samples": samples, "trace": trace}))
		file.close()
		print("RANDOMNESS_RESULT cap=%d checks=%d failures=%d" % [cap, checks, failures])
		get_tree().quit(1 if failures else 0)
