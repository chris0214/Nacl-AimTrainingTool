extends SceneTree

const AIM = preload("res://scripts/actors/bot_aim.gd")
const PREFS = preload("res://scripts/input/trainer_settings.gd")
const STEP := 1.0 / 120.0
const LEVELS := [0, 20, 40, 60, 80, 95, 99, 100]
var checks := 0
var failures := 0
var cap := 60
var game: Node3D
var rows: Array = []
var trace: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cap="):
			cap = int(argument.trim_prefix("--cap="))
	_test_profiles()
	_test_migration()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	Engine.max_fps = 0
	_test_ui()
	await _test_hard_lock()
	await _test_live_combat()
	await _test_skill_matrix()
	var output := FileAccess.open("res://artifacts/unified-aim-%d.json" % cap, FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows, "trace": trace}))
	output.close()
	game.queue_free()
	await process_frame
	print("UNIFIED_AIM_RESULT cap=%d checks=%d failures=%d" % [cap, checks, failures])
	quit(1 if failures else 0)


func _test_profiles() -> void:
	var monotone := true
	for index in range(1, 10001):
		var current := index * 0.01
		var previous := current - 0.01
		monotone = monotone and AIM.delay_for_level(current) <= AIM.delay_for_level(previous) \
			and AIM.correction_time(current) <= AIM.correction_time(previous) \
			and AIM.error_scale(current) <= AIM.error_scale(previous)
	check(monotone, "all profile components monotonically approach hard lock")
	check(AIM.delay_for_level(100) == 0 and AIM.correction_time(100) == 0 and AIM.error_scale(100) == 0,
		"hard lock endpoint has no artificial weakness")
	check(AIM.delay_for_level(99.99) < 0.1 and AIM.correction_time(99.99) < 0.00001
		and AIM.error_scale(99.99) < 0.0001, "continuous limit approaching 100")
	var last_recovery := 10000
	for level in [20, 40, 60, 80, 95, 99, 100]:
		var model := AIM.new()
		var random := RandomNumberGenerator.new()
		random.seed = 4238
		model.reset(random)
		var point := Vector3(-6, 1, 0)
		for tick in 120:
			point.x += 6 * STEP
			model.step(Vector3(0, 1, -10), point, 0.34, level, STEP, random)
		var last_outside := -1
		for tick in 120:
			point.x -= 6 * STEP
			model.step(Vector3(0, 1, -10), point, 0.34, level, STEP, random)
			if model.tracked_point.distance_to(point) > 0.34:
				last_outside = tick
		check(last_outside <= last_recovery, "higher level reacquires no later %d" % level)
		check(model.tracked_point.distance_to(point) < 0.01, "steady motion recovers %d" % level)
		last_recovery = last_outside
		print("RECOVERY level=", level, " last_outside_ms=", (last_outside + 1) * STEP * 1000)
	var model := AIM.new()
	var random := RandomNumberGenerator.new()
	random.seed = 712
	model.reset(random)
	var exact := true
	for tick in 500:
		var point := Vector3(sin(tick * 0.19) * 5, cos(tick * 0.11) * 2, 3)
		var origin := Vector3(cos(tick * 0.07), 1, -4)
		exact = exact and model.step(origin, point, 0.34, 100, STEP, random).is_equal_approx((point - origin).normalized())
	check(exact and model.observations.is_empty(), "hard lock exact on first tick and every arbitrary movement")


func _test_migration() -> void:
	var path := "res://artifacts/aim-migration-%d.cfg" % cap
	var legacy := ConfigFile.new()
	legacy.set_value("training", "accuracy", 100.0)
	legacy.set_value("training", "aim_delay", 65.0)
	legacy.set_value("training", "move_speed", 6.0)
	legacy.set_value("training", "cm360", 42.123456)
	legacy.set_value("training", "flank_chance", 70.0)
	legacy.set_value("bindings", "jump", KEY_J)
	legacy.save(path)
	var original := FileAccess.get_file_as_bytes(path)
	var settings := PREFS.new()
	settings.path = path
	settings.load_settings()
	check(settings.values.aim_level == 100, "legacy 100 maps to hard lock regardless of old delay")
	check(not settings.values.has("aim_delay") and not settings.values.has("accuracy"), "legacy keys no longer active")
	check(settings.values.move_speed == 6 and settings.values.flank_chance == 70
		and absf(settings.values.cm360 - 42.123456) < 0.0000001 and settings.bindings.jump == KEY_J,
		"migration preserves unrelated values and bindings")
	check(FileAccess.get_file_as_bytes(path) == original, "loading migration does not write")
	settings.writable = false
	settings.save_settings()
	check(FileAccess.get_file_as_bytes(path) == original, "read-only probe cannot migrate disk")
	settings.writable = true
	check(settings.save_settings() == OK, "migrated save succeeds")
	check(FileAccess.get_file_as_bytes(path + ".v1-backup") == original, "backup preserves original bytes")
	var current := ConfigFile.new()
	current.load(path)
	check(current.get_value("meta", "format_version") == 2 and not current.has_section_key("training", "aim_delay"),
		"versioned file excludes obsolete settings")
	settings.put("aim_level", 60)
	settings.save_settings()
	check(FileAccess.get_file_as_bytes(path + ".v1-backup") == original, "subsequent saves preserve backup")
	var loaded := PREFS.new()
	loaded.path = path
	loaded.load_settings()
	check(loaded.values.aim_level == 60, "new level survives reload")
	legacy.set_value("training", "accuracy", 40.0)
	legacy.save(path)
	loaded = PREFS.new()
	loaded.path = path
	loaded.load_settings()
	check(loaded.values.aim_level == 40, "ordinary legacy level maps numerically")
	legacy.set_value("training", "aim_level", 80.0)
	legacy.save(path)
	loaded.load_settings()
	check(loaded.values.aim_level == 80, "explicit new key takes precedence")
	current.set_value("meta", "format_version", 999)
	current.save(path)
	loaded.load_settings()
	check(loaded.save_settings() == ERR_UNAVAILABLE, "future config version is not overwritten")


func _test_ui() -> void:
	check(game.hud.bot_controls.has("aim_level") and not game.hud.bot_controls.has("aim_delay"),
		"single skill slider replaces independent delay")
	game.hud.bot_controls.aim_level.value = 100
	check(game.target.settings.aim_level == 100 and game.preferences.values.aim_level == 100,
		"UI reaches actor and preferences")
	check(game.hud.aim_profile_label.text.contains("绝对锁定"), "hard lock UI status")
	game.hud.bot_controls.aim_level.value = 60
	check(game.hud.aim_profile_label.text.contains("160 ms"), "derived delay readout")
	game.target.aim_step(game.player, STEP, true)
	game._set_preference("reaction_delay", 600)
	check(game.target.settings.aim_level == 60 and not game.target.aim_model.observations.is_empty(),
		"tactical delay does not change aim or its history")
	game.hud.bot_controls.aim_level.value = 100
	check(game.target.aim_model.observations.is_empty(), "level changes clear tracking history")
	game.reset_training()
	check(game.target.settings.aim_level == 100, "restart preserves hard lock level")


func _ray() -> Dictionary:
	var bot: Node3D = game.target
	game.player.force_update_transform()
	var excluded: Array[RID] = [bot.get_rid(), bot.hit_area.get_rid()]
	return game.bot_weapon.trace(game.get_world_3d().direct_space_state,
		bot.muzzle_position(), bot.aim_direction, excluded)


func _test_hard_lock() -> void:
	var bot: Node3D = game.target
	bot.configure("aim_level", 100)
	bot.configure("move_speed", 0)
	for distance in [1.4, 3.0, 10.0, 18.0]:
		bot.reset_at(Vector3(0, 0, -distance * 0.5), 4123)
		var all_hit := true
		var max_axis_error := 0.0
		for tick in 180:
			game.player.position = Vector3(sin(tick * 0.07) * 0.6, maxf(0, sin(tick * 0.05)) * 1.5, distance * 0.5)
			bot.position.y = maxf(0, cos(tick * 0.08)) * 1.5
			await physics_frame
			bot.aim_step(game.player, STEP, true)
			var to_point: Vector3 = game.player.position + Vector3.UP - bot.muzzle_position()
			max_axis_error = maxf(max_axis_error, to_point.cross(bot.aim_direction).length())
			all_hit = all_hit and _ray().get("collider") == game.player
		check(all_hit, "real muzzle hits all close/far/jumping targets %s" % distance)
		check(max_axis_error < 0.0001, "bore alignment remains exact %s" % distance)
	bot.reset_at(Vector3(0, 0, -5), 4123)
	game.player.position = Vector3(0, 0, 5)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 0.5)
	collision.shape = box
	wall.add_child(collision)
	game.add_child(wall)
	wall.position = Vector3(0, 1, 0)
	await physics_frame
	bot.aim_step(game.player, STEP, true)
	check(_ray().get("collider") == wall, "hard lock cannot shoot through obstruction")
	wall.queue_free()
	await physics_frame
	game.player.position = Vector3(0, 0, 30)
	await physics_frame
	bot.aim_step(game.player, STEP, true)
	check(not bot.fire and _ray().get("collider") != game.player, "hard lock respects range")
	bot.attack_enabled = false
	game.player.position = Vector3(0, 0, 5)
	await physics_frame
	bot.aim_step(game.player, STEP, true)
	check(not bot.fire, "hard lock respects attack toggle")
	bot.attack_enabled = true


func _point(tick: int, mode: String, distance: float) -> Vector3:
	var time := tick * STEP
	var x := 0.0
	var y := 0.0
	if mode == "smooth":
		x = sin(time * 2.0) * 2.0
	elif mode == "ad":
		x = (absf(fmod(time * 6.0, 6.0) - 3.0) - 1.5)
	elif mode == "jump":
		x = sin(time * 2.5) * 2.0
		y = maxf(0.0, sin(time * 4.0)) * 1.0
	return Vector3(x, y, distance * 0.5)


func _test_live_combat() -> void:
	game._set_preference("aim_level", 100)
	game._set_preference("instant_movement", true)
	game._set_preference("move_speed", 6)
	game.change_mode(true)
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -10), 41837)
	game.target.health = 500
	game.ready_to_start = false
	for tick in 480:
		game.input.held[game.input.bindings.right] = tick % 48 < 24
		game.input.held[game.input.bindings.left] = tick % 48 >= 24
		if tick % 120 <= 1:
			var jump := InputEventKey.new()
			jump.physical_keycode = game.input.bindings.jump
			jump.pressed = tick % 120 == 0
			game.input.ingest(jump, 0)
		await physics_frame
		game.clock.rebase(Time.get_ticks_usec())
		game._physics_process(STEP)
		trace.append(["combat", tick, game.target.position.x, game.target.position.y, game.target.position.z,
			game.bot_weapon.shots, game.bot_weapon.hits, game.player_health, game.target.health])
	check(game.bot_weapon.shots == 80 and game.bot_weapon.hits == 80,
		"moving jumping bot hard locks instantaneous AD in actual combat")
	check(game.player_health == 600 and game.target.health == 900, "100 DPS and equal lifesteal unchanged")
	game.pause_training()
	game.target.configure("move_speed", 0)


func _test_skill_matrix() -> void:
	var bot: Node3D = game.target
	var totals: Dictionary = {}
	for level in LEVELS:
		totals[level] = 0
	for seed_value in [18431, 75193, 90217]:
		for distance in [3.0, 10.0, 18.0]:
			for mode in ["static", "smooth", "ad", "jump"]:
				for level in LEVELS:
					bot.configure("aim_level", level)
					bot.reset_at(Vector3(0, 0, -distance * 0.5), seed_value)
					game.player.position = _point(0, mode, distance)
					await physics_frame
					var hits := 0
					var shots := 0
					for tick in 720:
						game.player.position = _point(tick, mode, distance)
						game.player.force_update_transform()
						await physics_frame
						bot.aim_step(game.player, STEP, true)
						if tick >= 120 and tick % 6 == 0:
							var hit: bool = _ray().get("collider") == game.player
							hits += int(hit)
							shots += 1
							if seed_value == 18431 and distance == 10:
								trace.append([mode, level, tick, bot.aim_direction.x, bot.aim_direction.y, bot.aim_direction.z, int(hit)])
					totals[level] += hits
					rows.append({"seed": seed_value, "distance": distance, "mode": mode, "level": level, "hits": hits, "shots": shots})
					if level == 100:
						check(hits == shots, "hard lock matrix %d %s %s" % [seed_value, distance, mode])
	var previous := -1
	for level in LEVELS:
		print("SKILL_TOTAL level=", level, " hits=", totals[level], " shots=3600")
		check(totals[level] >= previous, "aggregate real-ray hits nondecreasing %d" % level)
		previous = totals[level]
	for mode in ["static", "smooth", "ad", "jump"]:
		previous = -1
		for level in LEVELS:
			var hits := 0
			for row in rows:
				if row.mode == mode and row.level == level:
					hits += row.hits
			check(hits >= previous, "per-motion skill trend %s %d" % [mode, level])
			previous = hits
