extends SceneTree

const ASSIST = preload("res://scripts/input/aim_assist.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node3D
var bot: Node3D
var cap := 60
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
	_test_movement()
	_test_assist_math()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	# Fast headless combat has no audio clock; sound is covered by the atmosphere suite.
	if DisplayServer.get_name() == "headless":
		game._set_preference("hit_sound", false)
	bot = game.target
	Engine.max_fps = cap
	_test_controls()
	await _test_facing_and_width()
	await _test_reactions()
	await _test_assist_world()
	await _test_assisted_combat()
	var file := FileAccess.open("res://artifacts/player-features-%d.json" % cap, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "trace": trace}))
	file.close()
	game.queue_free()
	await process_frame
	print("PLAYER_FEATURES_RESULT cap=%d checks=%d failures=%d" % [cap, checks, failures])
	quit(1 if failures else 0)


func _test_movement() -> void:
	var rules: MovementProfile = preload("res://resources/movement/normal.tres")
	var advanced: MovementProfile = preload("res://resources/movement/advanced.tres")
	var v := ArenaActor.integrate_velocity(Vector3.ZERO, Vector3.RIGHT, true, false, rules, STEP, true)
	check(is_equal_approx(v.x, rules.ground_speed), "instant first grounded tick is full speed")
	v = ArenaActor.integrate_velocity(v, Vector3.LEFT, true, false, rules, STEP, true)
	check(is_equal_approx(v.x, -rules.ground_speed), "instant AD reversal reaches opposite full speed")
	v = ArenaActor.integrate_velocity(v, Vector3.ZERO, true, false, rules, STEP, true)
	check(Vector2(v.x, v.z).is_zero_approx(), "instant release stops on ground")
	v = ArenaActor.integrate_velocity(v, Vector3(1, 0, 1), true, false, rules, STEP, true)
	check(is_equal_approx(Vector2(v.x, v.z).length(), rules.ground_speed), "instant diagonals are normalized")
	v = ArenaActor.integrate_velocity(Vector3.ZERO, Vector3.RIGHT, true, false, rules, STEP)
	check(v.x > 0 and v.x < rules.ground_speed, "acceleration mode retains acceleration")
	var air := Vector3(8, 3, 0)
	check(ArenaActor.integrate_velocity(air, Vector3.LEFT, false, false, advanced, STEP, true).is_equal_approx(
		ArenaActor.integrate_velocity(air, Vector3.LEFT, false, false, advanced, STEP, false)),
		"instant ground mode does not overwrite advanced air inertia")
	v = ArenaActor.integrate_velocity(Vector3.ZERO, Vector3.RIGHT, true, true, advanced, STEP, true)
	check(is_equal_approx(v.y, advanced.jump_speed) and is_equal_approx(v.x, advanced.ground_speed),
		"instant jump keeps launch speed")


func _test_assist_math() -> void:
	for mode in [1, 2]:
		var reference := Vector2.ZERO
		for fps in [20, 60, 240]:
			var input := PlayerInput.new()
			for tick in fps:
				ASSIST.step(input, Vector3.ZERO, Vector3(-5, 1, -5), 1.0 / fps, mode,
					1440 if mode == 1 else 30, 3)
			var result := Vector2(input.yaw, input.pitch)
			if fps == 20:
				reference = result
			check(result.distance_to(reference) < 0.0001, "assist trajectory independent of frame interval mode %d" % mode)
		var input := PlayerInput.new()
		var previous_error := PI
		var decreasing := true
		for tick in 300:
			ASSIST.step(input, Vector3.ZERO, Vector3(-5, 0, -5), STEP, mode, 720, 12)
			var error := absf(PI * 0.25 - input.yaw)
			decreasing = decreasing and error <= previous_error + 0.000001
			previous_error = error
		check(decreasing and previous_error < 0.001, "assist converges without overshoot mode %d" % mode)
	var input := PlayerInput.new()
	input.yaw = deg_to_rad(179)
	var point := Basis(Vector3.UP, deg_to_rad(-179)) * Vector3.FORWARD * 10
	ASSIST.step(input, Vector3.ZERO, point, STEP, 2, 120, 12)
	check(input.yaw > deg_to_rad(179), "linear assist crosses wrap by shortest yaw path")
	input.clear(true)
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(37, -14)
	input.ingest(event, 999999)
	ASSIST.step(input, Vector3.ZERO, Vector3(-5, 0, -5), STEP, 2, 120, 12)
	var preview := Vector2(input.preview_yaw, input.preview_pitch)
	check(input.queue.size() == 1, "assist does not discard pending raw mouse input")
	input.consume(999999)
	check(Vector2(input.yaw, input.pitch).distance_to(preview) < 0.000001, "assist preview consumes mouse exactly once")
	var before := input.yaw
	ASSIST.step(input, Vector3.ZERO, Vector3.RIGHT, STEP, 0, 720, 12)
	check(input.yaw == before, "disabled assist leaves aim unchanged")


func _test_controls() -> void:
	check(game.preferences.values.assist_mode == 0, "assist defaults off")
	for width in [1.6, 1.25, 1.0]:
		game.hud.body_width_buttons[width].pressed.emit()
		check(is_equal_approx(bot.settings.body_width, width), "body preset updates model %.2f" % width)
		check(game.hud.body_width_buttons[width].button_pressed, "body preset stays selected")
	game.hud.bot_controls.body_width.value = 1.37
	var any_selected := false
	for button in game.hud.body_width_buttons.values():
		any_selected = any_selected or button.button_pressed
	check(not any_selected, "custom width does not falsely select a preset")
	game.hud.preference_controls.instant_movement.item_selected.emit(1)
	check(game.player.instant_movement, "player movement menu applies instant mode")
	game.hud.preference_controls.assist_mode.item_selected.emit(1)
	check(game.preferences.values.assist_mode == 1 and game.non_scoring, "assist menu marks entertainment non-scoring")
	game._set_preference("assist_mode", 0)
	check(game.non_scoring, "turning assist off does not clear round non-scoring flag")
	game.reset_training()
	check(not game.non_scoring, "new unassisted round can score again")
	game.pause_training()
	game.hud.update_player_tuning(8.5, 8.5, true)
	check(game.hud.speed_label.text.contains("8.50") and game.hud.player_speed_readout.text.contains("瞬时满速"),
		"HUD and bot speed panel display player speed")
	var prefs := preload("res://scripts/input/trainer_settings.gd").new()
	prefs.path = "res://artifacts/player-features-settings.cfg"
	for item in {"body_width": 1.6, "instant_movement": true, "reactive_bot": false,
		"reaction_delay": 231.0, "assist_mode": 2, "assist_speed": 357.0, "assist_response": 7.3}:
		prefs.put(item, {"body_width": 1.6, "instant_movement": true, "reactive_bot": false,
			"reaction_delay": 231.0, "assist_mode": 2, "assist_speed": 357.0, "assist_response": 7.3}[item])
	check(prefs.save_settings() == OK, "new preferences save")
	var loaded := preload("res://scripts/input/trainer_settings.gd").new()
	loaded.path = prefs.path
	loaded.load_settings()
	var round_trip := true
	for key in prefs.values:
		if prefs.values[key] is float:
			round_trip = round_trip and absf(loaded.values[key] - prefs.values[key]) < 0.000001
		else:
			round_trip = round_trip and loaded.values[key] == prefs.values[key]
	check(round_trip, "new preferences round-trip within stored precision")
	loaded.put("assist_mode", 1.8)
	loaded.put("body_width", NAN)
	check(loaded.values.assist_mode == 2 and loaded.values.body_width == 1.6, "invalid new preferences rejected")


func _test_facing_and_width() -> void:
	# This suite checks the robot's hand socket, not the default capsule's fixed muzzle.
	game._set_preference("bot_model", 0)
	game.player.reset_at(Vector3.ZERO)
	bot.reset_at(Vector3(0, 0, -5), 41837)
	for width in [0.75, 1.0, 1.25, 1.6, 2.0]:
		bot.configure("body_width", width)
		var facing := true
		var anchored := true
		for index in 24:
			var angle := index * TAU / 24.0
			game.player.position = bot.position + Vector3(sin(angle), 0, cos(angle)) * 5.0
			bot.velocity = Vector3(4, 0, -3) if index % 2 == 0 else Vector3(-4, 0, 3)
			bot.aim_step(game.player, STEP, true)
			var wanted: Vector3 = (game.player.position - bot.position).normalized()
			facing = facing and bot._shoulder_forward().dot(wanted) > 0.999
			anchored = anchored and bot.skeleton.get_bone_pose(bot.pelvis_index).is_equal_approx(bot.pelvis_pose)
			var hand: Transform3D = bot.skeleton.get_bone_global_pose(bot.skeleton.find_bone("hand_r"))
			anchored = anchored and bot.weapon_pivot.global_position.distance_to(bot.skeleton.global_transform * hand.origin) < 0.0001
		check(facing, "torso faces player through 360 degrees width %.2f" % width)
		check(anchored, "pelvis steady and rifle anchored width %.2f" % width)
		check(bot.scale.is_equal_approx(Vector3.ONE) and bot.hit_collision.scale.is_equal_approx(Vector3.ONE)
			and bot.collision.shape is CapsuleShape3D,
			"physics body never receives nonuniform scale")
		game.player.position = Vector3.ZERO
		bot.aim_step(game.player, STEP, false)
		await physics_frame
		await physics_frame
		var ray := LgWeapon.new()
		var hit := ray.trace(game.get_world_3d().direct_space_state, Vector3(width * 0.3 * 0.94, 0.91, 0),
			Vector3.FORWARD, [game.player.get_rid()])
		var miss := ray.trace(game.get_world_3d().direct_space_state, Vector3(width * 0.3 * 1.12, 0.91, 0),
			Vector3.FORWARD, [game.player.get_rid()])
		check(hit.get("collider", null) == bot and miss.get("collider", null) != bot,
			"real ray hits inside stretched width and misses outside %.2f" % width)
	bot.configure("body_width", 1.25)


func _test_reactions() -> void:
	var paths: Array = []
	for enabled in [false, true]:
		bot.reactive_enabled = enabled
		bot.configure("reaction_delay", 200)
		bot.configure("reaction_strength", 100)
		bot.reset_at(Vector3(0, 0, -8), 41837)
		game.player.reset_at(Vector3.ZERO)
		bot.observe_player_command(Vector2.RIGHT, 0, true)
		var path: Array = []
		for tick in 480:
			await physics_frame
			game.player.simulate(Vector2.ZERO, 0, false, STEP)
			if tick % 60 == 0:
				bot.observe_player_command(Vector2.RIGHT if tick % 120 == 0 else Vector2.LEFT, 0, true)
			bot.bot_step(game.player, STEP, false)
			path.append(bot.position)
			trace.append([int(enabled), tick, bot.position.x, bot.position.y, bot.position.z,
				bot.velocity.x, bot.velocity.z, bot.reaction_count])
			if tick == 20:
				check(bot.reaction_count == 0, "input response never precedes configured delay")
		check(bot.reaction_queue.size() < 80, "input observation queue remains bounded")
		check(bot.reaction_count > 1 if enabled else bot.reaction_count == 0, "reaction toggle gates responses")
		paths.append(path)
	check(paths[0][20].distance_to(paths[1][20]) < 0.001, "identical motion before delayed input becomes eligible")
	check(paths[0][479].distance_to(paths[1][479]) > 0.2, "delayed observations change actual movement")
	bot.observe_player_command(Vector2.UP, 0, false)
	game.pause_training()
	check(bot.reaction_queue.is_empty(), "pause clears delayed observations")
	bot.reset_at(Vector3(0, 0, -5), 41837)
	check(bot.reaction_queue.is_empty() and bot.reaction_count == 0, "round reset clears reaction state")
	bot.reactive_enabled = false


func _test_assist_world() -> void:
	game.player.reset_at(Vector3.ZERO)
	bot.reset_at(Vector3(0, 0, -5), 41837)
	await physics_frame
	await physics_frame
	game._set_preference("assist_mode", 2)
	game.paused = false
	game.input.clear(true)
	game.input.correct_view(0.5, 0)
	for index in 60:
		game._apply_player_assist(true, STEP)
	check(absf(game.input.yaw) < 0.001, "player assist follows real visible target")
	check(game.weapon.shots == 0, "assist itself never auto-fires")
	var block := StaticBody3D.new()
	block.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.3)
	shape.shape = box
	block.add_child(shape)
	game.add_child(block)
	block.position = Vector3(0, 1, -2.5)
	await physics_frame
	await physics_frame
	game.input.correct_view(0.5, 0)
	game._apply_player_assist(true, STEP)
	check(is_equal_approx(game.input.yaw, 0.5), "assist does not track through walls")
	block.queue_free()
	await physics_frame
	await physics_frame
	game._apply_player_assist(false, STEP)
	check(is_equal_approx(game.input.yaw, 0.5), "assist requires held fire")
	game.paused = true
	game._apply_player_assist(true, STEP)
	check(is_equal_approx(game.input.yaw, 0.5), "assist disabled while paused")
	game.paused = false
	bot.dead = true
	game._apply_player_assist(true, STEP)
	check(is_equal_approx(game.input.yaw, 0.5), "assist ignores dead target")
	bot.dead = false
	bot.position.z = -30
	await physics_frame
	game._apply_player_assist(true, STEP)
	check(is_equal_approx(game.input.yaw, 0.5), "assist respects weapon range")
	game._set_preference("assist_mode", 0)
	game.pause_training()


func _test_assisted_combat() -> void:
	game._set_preference("assist_mode", 2)
	game._set_preference("instant_movement", true)
	game._set_preference("attack", false)
	game._set_preference("move_speed", 0.0)
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	bot.reset_at(Vector3(0, 0, -5), 41837)
	game.ready_to_start = false
	game.input.firing = true
	game.input.held[game.input.bindings.right] = true
	game.input.correct_view(0.5, 0)
	var full_speed := true
	for tick in 240:
		await physics_frame
		# Isolate deterministic combat from wall-clock overload protection in this test.
		game.clock.rebase(Time.get_ticks_usec())
		game._physics_process(STEP)
		if tick > 4:
			full_speed = full_speed and absf(Vector2(game.player.velocity.x, game.player.velocity.z).length()
				- game.player.profile.ground_speed) < 0.002
		trace.append([2, tick, game.input.yaw, game.input.pitch,
			game.weapon.shots, game.weapon.hits, bot.health, game.player_health])
	check(full_speed, "real consumed AD command reaches instant speed during assisted combat")
	check(game.weapon.shots == 40 and game.weapon.hits >= 32, "linear assistance works through main fixed-tick shooting")
	check(bot.health == 1000 - game.weapon.damage, "assisted damage is still real fixed-tick ray damage")
	var wins: int = game.player_wins
	bot.health = 5
	await physics_frame
	game.clock.rebase(Time.get_ticks_usec())
	game._physics_process(STEP)
	check(bot.dead and game.player_wins == wins and game.non_scoring, "assisted victory never increments session wins")
	game._set_preference("assist_mode", 0)
	game.pause_training()
