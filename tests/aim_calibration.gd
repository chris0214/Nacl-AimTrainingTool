extends SceneTree

const STEP := 1.0 / 120.0
var game: Node3D
var rows: Array = []
var suffix := "unified"
var checks := 0
var failures := 0
var replay_seed := 18431


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suffix="):
			suffix = arg.trim_prefix("--suffix=")
		if arg.begins_with("--seed="):
			replay_seed = int(arg.trim_prefix("--seed="))
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	Engine.max_fps = 0
	var bot: Node3D = game.target
	assert(is_equal_approx(game.player.get_node("CollisionShape3D").shape.radius, 0.34))
	var excluded: Array[RID] = [bot.get_rid(), bot.hit_area.get_rid()]
	bot.configure("move_speed", 0.0)
	for moving in [false, true]:
		for distance in [3.0, 6.0, 11.0, 18.0]:
			for level in [0, 20, 40, 60, 80, 100]:
				bot.reset_at(Vector3(0, 0, -distance * 0.5), replay_seed)
				bot.configure("aim_level", level)
				game.player.position = Vector3(0, 0, distance * 0.5)
				await physics_frame
				var hits := 0
				var shots := 0
				for tick in 2520:
					game.player.position.x = sin(tick * STEP * 2.0) * 2.0 if moving else 0.0
					# Advance the physics broadphase for every manually simulated tick.
					game.player.force_update_transform()
					await physics_frame
					bot.aim_step(game.player, STEP, true)
					if tick >= 120 and tick % 6 == 0:
						var ray: Dictionary = game.bot_weapon.trace(game.get_world_3d().direct_space_state,
							bot.muzzle_position(), bot.aim_direction, excluded)
						hits += int(ray.get("collider") == game.player)
						shots += 1
					if tick % 120 == 0:
						await process_frame
				rows.append({"seed": replay_seed, "moving": moving, "distance": distance, "level": level,
					"actual": 100.0 * hits / shots, "hits": hits, "shots": shots})
				print("CALIBRATION ", rows.back())
				# Level is a skill index now, not a promised hit percentage.
				if level == 100:
					checks += 1
					if hits != shots:
						failures += 1
						printerr("FAIL hard lock missed: ", rows.back())
	var file := FileAccess.open("res://artifacts/aim-calibration-%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	file.close()
	game.queue_free()
	await process_frame
	print("AIM_CALIBRATION_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
