extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
const DOC = preload("res://scripts/maps/map_document.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0

class InwardRoute:
	extends Node3D
	var navigation_ready := true
	var toward := Vector3.BACK

	func path_between(at: Vector3, _destination: Vector3) -> PackedVector3Array:
		return PackedVector3Array([at + toward * 3.0])


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", description)


func _run() -> void:
	_test_preferences()
	var game := preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	_test_speed(game)
	await _screenshots(game)
	game.queue_free()
	await process_frame
	await _test_spacing()
	print("SHARED_SPEED_SPACING_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_preferences() -> void:
	var prefs := PREFS.new()
	check(prefs.values.base_speed == 10, "fresh shared speed defaults to ten")
	prefs.put("move_speed", 8)
	prefs.set_base_speed(15)
	check(prefs.values.move_speed == 12 and prefs.values.base_speed == 15, "shared speed scales bot actual speed")
	prefs.set_base_speed(10)
	check(prefs.values.move_speed == 8, "round trip base changes preserve bot ratio")
	prefs.set_base_speed(NAN)
	prefs.set_base_speed("invalid")
	check(prefs.values.move_speed == 8 and prefs.values.base_speed == 10, "invalid base leaves both values unchanged")
	prefs.put("move_speed", 0)
	prefs.set_base_speed(20)
	check(prefs.values.move_speed == 0, "stationary bot remains stationary")
	prefs.put("move_speed", 20)
	prefs.set_base_speed(2)
	prefs.set_base_speed(20)
	check(prefs.values.move_speed == 20, "speed cap remains twenty")
	prefs.path = "res://artifacts/shared-speed-settings.cfg"
	check(prefs.save_settings() == OK, "new speed preferences save")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	check(loaded.values.base_speed == 20 and loaded.values.move_speed == 20, "loading does not multiply saved speed again")
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "format_version", 2)
	legacy.set_value("training", "move_speed", 7.3)
	legacy.set_value("training", "engagement_distance", 11)
	legacy.save(prefs.path)
	loaded = PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	check(loaded.values.base_speed == 10 and loaded.values.move_speed == 7.3
		and loaded.values.engagement_distance == 11, "old config retains explicit bot tuning")


func _test_speed(game: Node3D) -> void:
	for advanced in [false, true]:
		game.change_mode(advanced)
		game.pause_training()
		for speed in [2.0, 8.5, 10.0, 20.0]:
			game.hud.preference_controls.base_speed.value = speed
			var rules: MovementProfile = game.player.profile
			check(is_equal_approx(rules.ground_speed, speed), "base control applies to player")
			check(is_equal_approx(game.target.settings.move_speed, game.preferences.values.move_speed),
				"base control applies to bot and preferences")
			for hz in [20, 60, 120, 240]:
				for instant in [false, true]:
					for wish in [Vector3.RIGHT, Vector3(1, 0, 1).normalized()]:
						var velocity := Vector3.ZERO
						for tick in hz * 2:
							velocity = ArenaActor.integrate_velocity(velocity, wish, true, false, rules, 1.0 / hz, instant)
						check(absf(Vector2(velocity.x, velocity.z).length() - speed) < 0.001,
							"steady speed matches requested speed including diagonal and acceleration")
						for tick in hz * 2:
							velocity = ArenaActor.integrate_velocity(velocity, -wish, true, false, rules, 1.0 / hz, instant)
						check(velocity.dot(-wish) > speed - 0.001, "AD reversal reaches opposite target speed")
						for tick in hz:
							velocity = ArenaActor.integrate_velocity(velocity, Vector3.ZERO, true, false, rules, 1.0 / hz, instant)
						check(Vector2(velocity.x, velocity.z).length() < 0.001, "release still brakes to stop")
			check(is_equal_approx(rules.jump_speed, game.ADVANCED.jump_speed), "base speed does not scale jump height")
			game.reset_training()
			game.pause_training()
			check(is_equal_approx(game.player.profile.ground_speed, speed), "reset retains selected base")
	check(game.NORMAL.ground_speed == 8.5 and game.ADVANCED.ground_speed == 8.5,
		"preloaded profile templates stay immutable")
	game.change_mode(false)
	game.pause_training()
	game._set_preference("base_speed", 10)
	var first := ArenaActor.integrate_velocity(Vector3.ZERO, Vector3.RIGHT, true, false, game.player.profile, STEP)
	check(first.x > 0 and first.x < 10, "acceleration mode still has startup ramp")
	game._set_preference("move_speed", 10)
	game._set_preference("base_speed", 12)
	check(game.hud.bot_controls.move_speed.value == 12 and game.hud.bot_sliders.move_speed.value == 12,
		"numeric and slider both show scaled bot speed")
	game._set_preference("base_speed", 10)


func _screenshots(game: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		game.hud.tabs.current_tab = game.hud.tabs.get_children().find(game.hud.tabs.get_node("玩家"))
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var box: SpinBox = game.hud.preference_controls.base_speed
		check(root.get_visible_rect().encloses(box.get_global_rect()), "shared speed control fits viewport")
		root.get_texture().get_image().save_png("res://artifacts/shared-speed-%dx%d.png" % [size.x, size.y])


func _test_spacing() -> void:
	var arena := preload("res://scenes/arena/flat_arena.tscn").instantiate()
	arena.set_script(preload("res://scripts/maps/custom_arena.gd"))
	arena.map_data = DOC.template()
	root.add_child(arena)
	var start := Time.get_ticks_msec()
	while arena.loading and Time.get_ticks_msec() - start < 15000:
		await physics_frame
	check(arena.navigation_ready, "infinite arena ready for dynamic spacing")
	var bot := CharacterBody3D.new()
	bot.set_script(preload("res://scripts/actors/static_target.gd"))
	root.add_child(bot)
	bot.terrain.arena = arena
	bot.floor_snap_length = 0.35
	bot.attack_enabled = false
	bot.reactive_enabled = false
	bot.pressure_enabled = false
	var player := preload("res://scenes/actors/arena_actor.tscn").instantiate()
	root.add_child(player)
	player.profile = preload("res://resources/movement/normal.tres").duplicate()
	player.profile.ground_speed = 3
	player.instant_movement = true
	for seed_value in [17, 18431, 829]:
		player.reset_at(Vector3(0, 0.02, 0))
		bot.reset_at(Vector3(0, 0.02, -11), seed_value)
		var minimum := INF
		var max_speed := 0.0
		var total := 0.0
		for tick in 960:
			await physics_frame
			var offset: Vector3 = bot.position - player.position
			var yaw := atan2(-offset.x, -offset.z)
			player.simulate(Vector2(0, -1), yaw, false, STEP)
			bot.bot_step(player, STEP, false)
			var distance := Vector2(bot.position.x - player.position.x, bot.position.z - player.position.z).length()
			minimum = minf(minimum, distance)
			total += distance
			max_speed = maxf(max_speed, Vector2(bot.velocity.x, bot.velocity.z).length())
		print("PURSUIT seed=%d min=%.3f mean=%.3f max_speed=%.3f" % [seed_value, minimum, total / 960, max_speed])
		check(minimum > 9.0, "slower pursuing player does not cause face hugging")
		check(max_speed <= bot.settings.move_speed + 0.001, "retreat never boosts beyond bot setting")
	bot.player = player
	player.reset_at(Vector3.ZERO)
	bot.reset_at(Vector3(0, 0.02, -2), 17)
	bot._roaming_velocity(STEP)
	var desired: Vector3 = bot._roaming_velocity(STEP)
	check(bot.spacing_out and desired.z < -bot.settings.move_speed * 0.85, "close spawn retreats with dominant radial motion")
	var destination: Vector3 = bot._navigation_destination(desired)
	check(destination.distance_to(player.position) > bot.position.distance_to(player.position),
		"retreat route destination is away from player")
	var mock := InwardRoute.new()
	root.add_child(mock)
	bot.terrain.arena = mock
	bot.terrain.clear()
	bot.terrain.blocked_time = 1
	var safe: Vector3 = bot.terrain.steer(bot, desired, destination, STEP, player.position)
	check(safe.z <= 0 and safe.length() <= desired.length() + 0.001,
		"adversarial inward navigation route cannot override retreat")
	bot.terrain.arena = arena
	bot.configure("move_speed", 0)
	bot.bot_step(player, STEP, false)
	check(Vector2(bot.velocity.x, bot.velocity.z).is_zero_approx(), "spacing preserves stationary bot mode")
	bot.queue_free()
	player.queue_free()
	mock.queue_free()
	arena.queue_free()
	await process_frame
