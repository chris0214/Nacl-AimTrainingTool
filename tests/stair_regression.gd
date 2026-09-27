extends SceneTree

const DOC = preload("res://scripts/maps/map_document.gd")
const MOTION = preload("res://scripts/maps/terrain_motion.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var arena: Node3D
var bot: CharacterBody3D
var player: CharacterBody3D


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	arena = preload("res://scenes/arena/flat_arena.tscn").instantiate()
	arena.set_script(preload("res://scripts/maps/custom_arena.gd"))
	var data := DOC.template()
	var stairs := DOC.object_data(1, "stairs", Vector3.ZERO, Vector3(3, 2, 3.2))
	stairs.auto_steps = true
	DOC.fit_stairs(stairs)
	data.objects = [stairs,
		DOC.object_data(2, "box", Vector3(0, 0, -3.6), Vector3(3, 2, 4)),
		DOC.object_data(3, "box", Vector3(1.75, 0, 0), Vector3(0.5, 5, 12))]
	data.player_spawn = [0.0, 0.02, 6.0]
	data.bot_spawn = [0.0, 2.02, -3.0]
	arena.map_data = data
	root.add_child(arena)
	var started := Time.get_ticks_msec()
	while arena.loading and Time.get_ticks_msec() - started < 15000:
		await physics_frame
	check(arena.navigation_ready and arena.validation_error.is_empty(), "stair map navigation loads")
	bot = CharacterBody3D.new()
	bot.set_script(preload("res://scripts/actors/static_target.gd"))
	root.add_child(bot)
	bot.terrain.arena = arena
	bot.floor_constant_speed = true
	bot.floor_snap_length = 0.35
	bot.floor_max_angle = deg_to_rad(44)
	bot.attack_enabled = false
	bot.reactive_enabled = false
	player = preload("res://scenes/actors/arena_actor.tscn").instantiate()
	root.add_child(player)
	player.position = Vector3(-8, 0.02, 6)
	for speed in [1.0, 4.5, 10.0]:
		for ascending in [true, false]:
			for routed in [false, true]:
				await _traverse(speed, ascending, routed)
	for speed in [4.5, 10.0]:
		for seed_value in [17, 18431, 829]:
			await _live_bot(seed_value, speed)
	await _test_support_edges()
	bot.queue_free()
	player.queue_free()
	arena.queue_free()
	await process_frame
	print("STAIR_REGRESSION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _traverse(speed: float, ascending: bool, routed: bool) -> void:
	var start := Vector3(0, 0.02, 3) if ascending else Vector3(0, 2.02, -3)
	var target := Vector3(0, 2.02, -3) if ascending else Vector3(0, 0.02, 3)
	bot.reset_at(start, 17)
	var desired := Vector3.FORWARD * speed if ascending else Vector3.BACK * speed
	for tick in int(9.0 / speed / STEP):
		await physics_frame
		var direction: Vector3 = bot.terrain.steer(bot, desired, target, STEP) if routed else desired
		bot.velocity = Vector3(direction.x, -0.5 if bot.is_on_floor() else bot.velocity.y - 18 * STEP, direction.z)
		MOTION.move(bot, STEP)
		if (bot.position.z < -2.3 if ascending else bot.position.z > 2.3):
			break
	if not ascending:
		for tick in 60:
			await physics_frame
			bot.velocity = Vector3(0, -0.5 if bot.is_on_floor() else bot.velocity.y - 18 * STEP, 0)
			MOTION.move(bot, STEP)
	var reached: bool = bot.position.z < -2.3 and bot.position.y > 1.9 if ascending else bot.position.z > 2.3 and bot.position.y < 0.1
	print("STAIR_CASE speed=", speed, " up=", ascending, " route=", routed, " at=", bot.position,
		" floor=", bot.is_on_floor(), " path=", bot.terrain.path, " index=", bot.terrain.path_index)
	check(reached, "stair traversal speed=%s up=%s route=%s" % [speed, ascending, routed])


func _live_bot(seed_value: int, speed: float) -> void:
	bot.reset_at(Vector3(0.8, 1.02, 0.2), seed_value)
	player.position = Vector3(0, 0.02, 6)
	bot.settings.move_speed = speed
	var best := 100.0
	var stuck := 0.0
	var longest := 0.0
	var anchor := bot.position
	for tick in 1200:
		await physics_frame
		bot.bot_step(player, STEP, false)
		best = minf(best, bot.position.y)
		if bot.position.distance_to(anchor) > 0.35:
			anchor = bot.position
			stuck = 0
		else:
			stuck += STEP
			longest = maxf(longest, stuck)
	print("LIVE_STAIR seed=", seed_value, " speed=", speed, " at=", bot.position, " lowest=", best, " stationary=", longest)
	check(best < 0.1, "live Bot leaves stairs seed=%s" % seed_value)
	check(longest < 2.0, "live Bot does not remain pinned seed=%s" % seed_value)


func _test_support_edges() -> void:
	bot.reset_at(Vector3(0, 2.001, -3.5))
	await physics_frame
	check(not bot.terrain._supported_path(bot, Vector3.LEFT, 2.0), "support lookahead rejects an unwalkable platform drop")
	check(not bot.terrain._supported_path(bot, Vector3.RIGHT, 2.0), "support lookahead rejects a tall wall")
	bot.position = Vector3(0, 1.001, 0.2)
	check(bot.terrain._supported_path(bot, Vector3.FORWARD, 1.6), "lookahead follows multiple ascending treads")
	check(bot.terrain._supported_path(bot, Vector3.BACK, 1.6), "lookahead follows multiple descending treads")
