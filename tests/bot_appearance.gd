extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node3D


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	var prefs := PREFS.new()
	check(prefs.values.bot_model == 1, "new default is black capsule")
	prefs.path = "res://artifacts/appearance-settings.cfg"
	prefs.put("bot_model", 2)
	prefs.put("bot_animation", false)
	check(prefs.save_settings() == OK, "appearance saves")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	check(loaded.values.bot_model == 2 and not loaded.values.bot_animation, "appearance reloads")
	for invalid in [-1, 3, 0.5, NAN, "1", true]:
		loaded.put("bot_model", invalid)
		check(loaded.values.bot_model == 2, "invalid style rejected")
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pause_training()
	game._set_preference("hit_sound", false)
	game._set_preference("armor_sound", false)
	game._set_preference("reactive_bot", false)
	game._set_preference("aim_level", 100)
	var target: Node3D = game.target
	var excluded_bot: Array[RID] = [target.get_rid(), target.hit_area.get_rid()]
	var excluded_player: Array[RID] = [game.player.get_rid()]
	var reference: Array[Vector3] = []
	for style in [0, 1, 2]:
		game._set_preference("bot_model", style)
		check(target.model.visible == (style == 0), "humanoid visibility")
		check(target.capsule_visual.visible == (style != 0), "capsule visibility")
		check(game.hud.preference_controls.bot_animation.disabled == (style != 0), "animation control availability")
		check(game.hud.preference_controls.bot_model.selected == style, "selection synchronized")
		game.player.reset_at(Vector3.ZERO)
		target.reset_at(Vector3(0, 0, -10), 1234)
		var positions_match := true
		var hits := 0
		for tick in 180:
			await physics_frame
			target.bot_step(game.player, STEP, false)
			if style == 0:
				reference.append(target.position)
			else:
				positions_match = positions_match and target.position.is_equal_approx(reference[tick])
			var result: Dictionary = game.bot_weapon.trace(game.get_world_3d().direct_space_state,
				target.muzzle_position(), target.aim_direction, excluded_bot)
			hits += int(result.get("collider") == game.player)
		check(positions_match, "style preserves deterministic movement")
		check(hits == 180 and target.fire, "hard lock and enemy beam origin preserved")
		for width in [0.75, 1.0, 1.6, 2.0]:
			game._set_preference("body_width", width)
			target.reset_at(Vector3(0, 0, -8), 1234)
			target.aim_step(game.player, STEP, true)
			await physics_frame
			check(is_equal_approx(target.capsule_visual.scale.x, width), "capsule follows hit width")
			check(target.capsule_visual.mesh.height == target.collision.shape.height, "capsule matches collision height")
			var ray: Dictionary = game.weapon.trace(game.get_world_3d().direct_space_state,
				Vector3(0.3 * width * 0.95, 0.91, 0), Vector3.FORWARD, excluded_player)
			check(ray.get("collider") == target, "inside capsule silhouette hits")
			ray = game.weapon.trace(game.get_world_3d().direct_space_state,
				Vector3(0.3 * width + 0.04, 0.91, 0), Vector3.FORWARD, excluded_player)
			check(ray.get("collider") != target, "outside silhouette misses")
		game._set_preference("body_width", 1.25)
	game._set_preference("bot_model", 0)
	game._set_preference("bot_animation", false)
	target.reset_at(Vector3(0, 0, -8), 1234)
	var leg: int = target.skeleton.find_bone("thigh_l")
	var pose: Transform3D = target.skeleton.get_bone_pose(leg)
	for tick in 30:
		await physics_frame
		target.bot_step(game.player, STEP, true)
	check(target.skeleton.get_bone_pose(leg).is_equal_approx(pose), "disabled animation holds pose")
	game._set_preference("bot_animation", true)
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		if DisplayServer.get_name() == "headless":
			break
		root.size = size
		game.player.reset_at(Vector3.ZERO)
		target.reset_at(Vector3(0, 0, -7), 1234)
		game._update_camera()
		for style in [1, 2, 0]:
			game._set_preference("bot_model", style)
			target.aim_step(game.player, STEP, true)
			game.hud.set_paused(false)
			for frame in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/appearance-%d-%dx%d.png" % [style, size.x, size.y])
		game.hud.set_paused(true)
		game.hud.bot_section_buttons.aim.button_pressed = true
		game.hud._reveal_bot_section("aim")
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/appearance-settings-%dx%d.png" % [size.x, size.y])
	game.queue_free()
	await process_frame
	print("BOT_APPEARANCE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
