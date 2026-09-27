extends SceneTree

const DOC = preload("res://scripts/maps/map_document.gd")
const GEOMETRY = preload("res://scripts/maps/map_geometry.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var arena: Node3D
var editor: Control
var native := false
var trace: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	native = DisplayServer.get_name() != "headless"
	_test_document()
	await _test_editor()
	await _test_arena()
	await _test_movement()
	await _test_bot_navigation()
	await _test_game()
	var suffix := "native" if native else "headless"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trace-id="):
			suffix = argument.trim_prefix("--trace-id=").validate_filename()
	var file := FileAccess.open("res://artifacts/map-motion-%s.json" % suffix, FileAccess.WRITE)
	file.store_string(JSON.stringify(trace))
	file.close()
	print("MAP_EDITOR_RESULT native=%s checks=%d failures=%d" % [native, checks, failures])
	quit(1 if failures else 0)


func _test_document() -> void:
	var value := DOC.enclosed_template()
	check(DOC.validate(value).is_empty(), "default map validates")
	for kind in DOC.KINDS:
		var item := DOC.object_data(6, kind, Vector3(-5, 0, 0), Vector3(4, 1.6, 6.4))
		var candidate := value.duplicate(true)
		candidate.objects.append(item)
		check(DOC.validate(candidate).is_empty(), "primitive validates: " + kind)
		var body := GEOMETRY.build_object(item)
		check(body.collision_layer == (64 if kind == "stairs" else 1) and body.get_meta("map_id") == 6, "collision and selection metadata")
		check(body.get_child_count() == (17 if kind == "stairs" else 2), "primitive part count")
		if kind == "ramp":
			var normal: Vector3 = body.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL][0]
			check(normal.y > 0.5, "ramp visible top normal faces upward")
		body.free()
	for patch in [{"version": 99}, {"script": "evil.gd"}, {"objects": []},
		{"bounds": [1, 1, 0, 0]}, {"player_spawn": [100, 0, 100]},
		{"kill_y": 0}, {"name": ""}, {"bot_spawn": [0, 0, 7]}]:
		var invalid := value.duplicate(true)
		invalid.merge(patch, true)
		check(not DOC.validate(invalid).is_empty(), "invalid document rejected: " + str(patch.keys()))
	for patch in [{"id": 2}, {"size": [0, 1, 1]}, {"size": [NAN, 1, 1]},
		{"position": [0, INF, 0]}, {"kind": "script"}, {"steps": 1.5}, {"color": 20},
		{"yaw": 1000}, {"script": "res://x.gd"}]:
		var invalid := value.duplicate(true)
		invalid.objects[0].merge(patch, true)
		check(not DOC.validate(invalid).is_empty(), "invalid primitive rejected: " + str(patch.keys()))
	var many := value.duplicate(true)
	for id in 260:
		many.objects.append(DOC.object_data(10 + id, "box", Vector3.ZERO, Vector3.ONE))
	check(not DOC.validate(many).is_empty(), "object budget enforced")
	var file_path := "res://artifacts/map-roundtrip.lgmap"
	check(DOC.write_map(file_path, value).is_empty(), "save map")
	var read := DOC.read_map(file_path)
	check(read.has("data") and read.data == JSON.parse_string(JSON.stringify(value)), "map roundtrip")
	value.name = "Replacement"
	check(DOC.write_map(file_path, value).is_empty() and DOC.read_map(file_path).data.name == "Replacement",
		"atomic overwrite existing map")
	var invalid := value.duplicate(true)
	invalid.objects[0].size[0] = -1
	check(not DOC.write_map(file_path, invalid).is_empty() and DOC.read_map(file_path).data.name == "Replacement",
		"invalid save preserves valid destination")
	var broken := FileAccess.open("res://artifacts/map-broken.lgmap", FileAccess.WRITE)
	broken.store_string("{")
	broken.close()
	check(DOC.read_map("res://artifacts/map-broken.lgmap").has("error"), "malformed JSON rejected")
	var big := FileAccess.open("res://artifacts/map-too-large.lgmap", FileAccess.WRITE)
	big.store_buffer(" ".repeat(DOC.MAX_BYTES + 1).to_utf8_buffer())
	big.close()
	check(DOC.read_map("res://artifacts/map-too-large.lgmap").has("error"), "oversize import rejected")
	var document := DOC.new()
	document.mark_saved()
	document.checkpoint()
	document.data.name = "Edited"
	check(document.changed(), "dirty state")
	check(document.undo() and not document.changed(), "undo to saved state")
	check(document.redo() and document.data.name == "Edited", "redo preserves edit")
	for index in 70:
		document.checkpoint()
		document.data.name = str(index)
	check(document.undo_stack.size() == 64, "bounded undo history")


func _test_editor() -> void:
	root.get_node("MapWorkspace").document.data = DOC.enclosed_template()
	editor = preload("res://scenes/editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	await physics_frame
	check(editor.document.data.objects.size() == 5, "editor displays template")
	editor.select_id(2)
	editor.duplicate_selected()
	check(editor.document.data.objects.size() == 6 and editor.document.selected == 6, "duplicate object")
	editor.rotate_selected()
	check(editor.document.object_by_id(6).yaw == 90, "rotate object")
	editor._edit_field("size:0", 8, false)
	check(editor.document.object_by_id(6).size[0] == 8, "dimension input updates shared document")
	editor.undo()
	check(editor.document.object_by_id(6).size[0] == 36, "dimension edit undo")
	editor.redo()
	check(editor.document.object_by_id(6).size[0] == 8, "dimension edit redo")
	editor.delete_selected()
	check(editor.document.data.objects.size() == 5, "delete")
	editor.undo()
	check(editor.document.data.objects.size() == 6 and editor.document.selected == 6, "undo restores selection")
	editor.delete_selected()
	editor.toggle_view()
	await process_frame
	await physics_frame
	editor.set_tool("box")
	var begin: Vector2 = editor.camera.unproject_position(Vector3(-6, 0, 4))
	var end: Vector2 = editor.camera.unproject_position(Vector3(-3, 0, 7))
	editor._pointer_down(begin)
	editor._pointer_motion(end)
	editor._pointer_up(end)
	check(editor.raising and not editor.drawing, "drag footprint enters height stage")
	editor._pointer_motion(end - Vector2(0, 40))
	check(editor.draft.size[0] == 3 and editor.draft.size[2] == 3 and editor.draft.size[1] == 1,
		"drag dimensions and height")
	check(editor.commit_draft() and editor.document.data.objects.size() == 6, "commit whitebox")
	editor.set_tool("move")
	var old: Vector3 = DOC.vector3(editor.document.object_by_id(6).position)
	await physics_frame
	var center: Vector2 = editor.camera.unproject_position(editor.selection.position + Vector3.RIGHT * 1.4)
	editor._pointer_down(center)
	editor._pointer_motion(center + Vector2(32, 0))
	editor._pointer_up(center + Vector2(32, 0))
	check(DOC.vector3(editor.document.object_by_id(6).position).distance_to(old) > 0.1, "viewport move")
	check(editor.drag_checkpoint, "move creates an undo checkpoint")
	if editor.drag_checkpoint:
		editor.undo()
		check(DOC.vector3(editor.document.object_by_id(6).position).is_equal_approx(old), "drag is single undo action")
	editor.set_tool("stairs")
	await physics_frame
	var stair_at: Vector2 = editor.camera.unproject_position(Vector3(-12, 0, 0))
	editor._pointer_down(stair_at)
	editor._pointer_up(stair_at)
	check(editor.document.object_by_id(7).is_empty() and editor.drawing,
		"single click only starts a staircase footprint")
	var stair_end: Vector2 = editor.camera.unproject_position(Vector3(-8, 0, 6))
	editor._pointer_motion(stair_end)
	editor._pointer_down(stair_end)
	editor._pointer_up(stair_end)
	editor._pointer_motion(stair_end - Vector2(0, 40))
	editor._pointer_down(stair_end - Vector2(0, 40))
	editor._pointer_up(stair_end - Vector2(0, 40))
	check(editor.document.object_by_id(7).kind == "stairs" and editor.tool == "select",
		"footprint and height confirmation create stairs and return to selection")
	editor.undo()
	editor.draft = DOC.object_data(7, "stairs", Vector3(-6, 0, -2), Vector3(4, 1.6, 6.4))
	check(editor.commit_draft(), "stairs creation")
	editor.draft = DOC.object_data(8, "ramp", Vector3(6, 0, 0), Vector3(4, 1.6, 6.4))
	check(editor.commit_draft(), "ramp creation")
	editor._edit_field("steps", 8, false)
	var snapshot: String = JSON.stringify(editor.document.data)
	var history: int = editor.document.undo_stack.size()
	check(editor._save_to("res://artifacts/editor-workflow.lgmap", false), "editor save")
	check(not editor.document.changed(), "editor save clears dirty")
	check(editor._save_to("res://artifacts/editor-export.lgmap", true)
		and editor.document.path.ends_with("editor-workflow.lgmap"), "export does not replace document path")
	check(not editor.load_document("res://artifacts/map-broken.lgmap")
		and JSON.stringify(editor.document.data) == snapshot, "bad open preserves document")
	editor._commit_fields()
	check(editor.document.undo_stack.size() == history, "committing unchanged fields does not add edits")
	editor._store_view()
	editor.queue_free()
	await process_frame
	editor = preload("res://scenes/editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	check(JSON.stringify(editor.document.data) == snapshot and editor.document.undo_stack.size() == history,
		"editor recreation preserves document and undo")
	for dimensions in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = dimensions
		await process_frame
		await process_frame
		check(editor.viewport_panel.size.x >= 240, "viewport width at " + str(dimensions))
		check(editor.inspector.get_parent().get_global_rect().end.x <= dimensions.x + 1,
			"inspector fits window at " + str(dimensions))
		if native:
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png("res://artifacts/map-editor-%dx%d.png" % [dimensions.x, dimensions.y])
			check(image.get_width() == dimensions.x, "native capture dimensions")
			var scene_image: Image = editor.viewport.get_texture().get_image()
			var colors := {}
			for y in range(0, scene_image.get_height(), 4):
				for x in range(0, scene_image.get_width(), 4):
					colors[scene_image.get_pixel(x, y).to_html()] = true
			print("MAP_VIEW_COLORS size=", dimensions, " colors=", colors.size())
			check(colors.size() > 24, "native 3D viewport is not blank")
			editor.toggle_view()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/map-editor-perspective-%dx%d.png" % [dimensions.x, dimensions.y])
			editor.toggle_view()
	editor.queue_free()
	await process_frame


func _test_arena() -> void:
	arena = preload("res://scenes/arena/flat_arena.tscn").instantiate()
	arena.set_script(preload("res://scripts/maps/custom_arena.gd"))
	var data := DOC.enclosed_template()
	data.objects.append(DOC.object_data(6, "stairs", Vector3(-6, 0, 0), Vector3(4, 1.6, 6.4)))
	data.objects.append(DOC.object_data(7, "ramp", Vector3(6, 0, 0), Vector3(4, 1.6, 6.4)))
	data.objects.append(DOC.object_data(8, "box", Vector3(0, 0, -5.2), Vector3(16, 1.6, 4)))
	data.objects.append(DOC.object_data(9, "box", Vector3(0, 0, 0), Vector3(2, 3, 4)))
	data.bot_spawn = [6.0, 1.62, -5.0]
	data.name = "Whitebox Test"
	arena.map_data = data
	root.add_child(arena)
	var start := Time.get_ticks_msec()
	while arena.loading and Time.get_ticks_msec() - start < 15000:
		await physics_frame
	check(not arena.loading, "navigation completes within timeout")
	check(arena.validation_error.is_empty(), "walkable spawns: " + arena.validation_error)
	check(arena.navigation_ready, "navigation ready")
	print("MAP_NAV polygons=", arena.navigation.navigation_mesh.get_polygon_count())
	check(arena.geometry.get_child_count() == 9, "shared runtime geometry")
	check(arena.find_children("*", "Label3D", true, false).is_empty(), "no map text in game")
	var space := arena.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 7), Vector3(0, 1, -4), 1)
	var hit := space.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider.name == "Object_9", "whitebox blocks weapon ray")
	for x in [-6.0, 6.0]:
		var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 5, 2.8), Vector3(x, -1, 2.8), 1))
		var high := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 5, -2.8), Vector3(x, -1, -2.8), 1))
		check(not low.is_empty() and not high.is_empty() and high.position.y > low.position.y + 1,
			"stair/ramp physical heights at " + str(x))
	var route: PackedVector3Array = arena.path_between(Vector3(0, 0.02, 7), Vector3(6, 1.62, -5))
	check(route.size() >= 3 and route[route.size() - 1].y > 1.3, "navigation reaches elevated platform")
	check(not arena.has_support(Vector3(30, 0, 0)), "unsupported edge detected")
	check(not arena.contains_point(Vector3(30, 0, 0)), "activity bounds")
	var previous: Vector3 = arena.get_node("PlayerSpawn").position
	arena.get_node("PlayerSpawn").position = Vector3(0, 0.02, 0)
	check(not arena.validate_spawns().is_empty(), "spawn inside obstruction rejected")
	arena.get_node("PlayerSpawn").position = Vector3(10, 8, 8)
	check(not arena.validate_spawns().is_empty(), "unsupported spawn rejected")
	arena.get_node("PlayerSpawn").position = previous
	check(DOC.write_map("res://artifacts/whitebox-demo.lgmap", data).is_empty(), "demo map export")


func _test_movement() -> void:
	var player := preload("res://scenes/actors/arena_actor.tscn").instantiate()
	root.add_child(player)
	player.profile = preload("res://resources/movement/normal.tres")
	player.terrain_enabled = true
	player.floor_constant_speed = true
	player.floor_snap_length = 0.35
	player.floor_max_angle = deg_to_rad(44)
	for x in [-6.0, 6.0]:
		player.reset_at(Vector3(x, 0.02, 5))
		var max_y := 0.0
		for tick in 210:
			await physics_frame
			player.simulate(Vector2(0, -1), 0, false, STEP)
			trace.append(["player", x, tick, player.position.x, player.position.y, player.position.z])
			max_y = maxf(max_y, player.position.y)
			if player.position.z < -4.8 and player.is_on_floor():
				break
		check(max_y > 1.5 and player.position.z < -4.5, "player ascends stairs/ramp: " + str(x))
		print("MAP_CLIMB x=", x, " max_y=", max_y, " position=", player.position,
			" floor=", player.is_on_floor(), " velocity=", player.velocity)
		var start_y: float = player.position.y
		for tick in 180:
			await physics_frame
			player.simulate(Vector2(0, 1), 0, false, STEP)
		check(player.position.y < start_y - 1 and player.position.y > -0.05, "player descends without falling through floor")
	player.reset_at(Vector3(0, 0.02, 4))
	for tick in 100:
		await physics_frame
		player.simulate(Vector2(0, -1), 0, false, STEP)
	check(player.position.z > 2.25, "step solver does not climb a tall wall")
	var steep := GEOMETRY.build_object(DOC.object_data(101, "ramp", Vector3(12, 0, 0), Vector3(3, 3, 1.5)))
	arena.geometry.add_child(steep)
	player.reset_at(Vector3(12, 0.02, 2))
	var steep_height := 0.0
	for tick in 90:
		await physics_frame
		player.simulate(Vector2(0, -1), 0, false, STEP)
		steep_height = maxf(steep_height, player.position.y)
	check(steep_height < 0.35, "steep ramps cannot be climbed by repeated step lifting")
	steep.queue_free()
	var step_box := GEOMETRY.build_object(DOC.object_data(102, "box", Vector3(-12, 0, 0), Vector3(3, 0.25, 2)))
	var ceiling := GEOMETRY.build_object(DOC.object_data(103, "box", Vector3(-12, 1.95, 0), Vector3(3, 0.3, 6)))
	arena.geometry.add_child(step_box)
	arena.geometry.add_child(ceiling)
	player.reset_at(Vector3(-12, 0.02, 2))
	var ceiling_height := 0.0
	for tick in 90:
		await physics_frame
		player.simulate(Vector2(0, -1), 0, false, STEP)
		ceiling_height = maxf(ceiling_height, player.position.y)
	check(ceiling_height < 0.16 and player.position.z > 1.2, "step sweep respects overhead clearance")
	step_box.queue_free()
	ceiling.queue_free()
	player.reset_at(Vector3(10, 3, 8))
	for tick in 30:
		await physics_frame
		player.simulate(Vector2.ZERO, 0, false, STEP)
	check(player.velocity.y < -5, "normal mode has gravity off ledges")
	player.queue_free()
	await process_frame
	await physics_frame


func _test_bot_navigation() -> void:
	var player := preload("res://scenes/actors/arena_actor.tscn").instantiate()
	root.add_child(player)
	player.position = Vector3(6, 1.62, -5)
	var bot := CharacterBody3D.new()
	bot.set_script(preload("res://scripts/actors/static_target.gd"))
	root.add_child(bot)
	bot.terrain.arena = arena
	bot.floor_constant_speed = true
	bot.floor_snap_length = 0.35
	bot.floor_max_angle = deg_to_rad(44)
	bot.attack_enabled = false
	bot.reactive_enabled = false
	bot.reset_at(Vector3(0, 0.02, 7), 18431)
	var max_y := 0.0
	var closest := 100.0
	var visible_ticks := 0
	for tick in 1000:
		await physics_frame
		bot.bot_step(player, STEP, false)
		trace.append(["bot", 0, tick, bot.position.x, bot.position.y, bot.position.z])
		max_y = maxf(max_y, bot.position.y)
		closest = minf(closest, bot.position.distance_to(player.position))
		var sight := PhysicsRayQueryParameters3D.create(bot.position + Vector3.UP,
			player.position + Vector3.UP, 65, [bot.get_rid()])
		visible_ticks += int(bot.get_world_3d().direct_space_state.intersect_ray(sight).is_empty())
		check(arena.contains_point(bot.position) and bot.position.y > -0.2,
			"Bot stays on supported training surface")
	check(closest > 6.0, "live Bot preserves engagement distance instead of chasing player feet")
	check(visible_ticks > 120, "live Bot finds a firing position around occluding whitebox")
	print("BOT_MAP_PATH max_y=", max_y, " closest=", closest, " final=", bot.position)
	# Separately exercise forced traversal; maintaining range need not climb onto the player's small platform.
	bot.reset_at(Vector3(0, 0.02, 7), 18431)
	max_y = 0.0
	closest = 100.0
	for tick in 1000:
		await physics_frame
		var desired: Vector3 = player.position - bot.position
		desired.y = 0.0
		desired = desired.normalized() * bot.settings.move_speed
		var steered: Vector3 = bot.terrain.steer(bot, desired, player.position, STEP)
		bot.velocity = Vector3(steered.x, -0.5 if bot.is_on_floor() else bot.velocity.y - 18 * STEP, steered.z)
		preload("res://scripts/maps/terrain_motion.gd").move(bot, STEP)
		max_y = maxf(max_y, bot.position.y)
		closest = minf(closest, bot.position.distance_to(player.position))
		if closest < 0.8:
			break
	check(max_y > 1.5, "forced navigation still ascends platform")
	check(closest < 0.8, "forced navigation still reaches requested endpoint")
	player.position = Vector3(0, 1.62, -5)
	bot.reset_at(Vector3(0, 0.02, 7), 18431)
	await physics_frame
	var blocked_sight := PhysicsRayQueryParameters3D.create(bot.position + Vector3.UP,
		player.position + Vector3.UP, 65, [bot.get_rid()])
	check(not bot.get_world_3d().direct_space_state.intersect_ray(blocked_sight).is_empty(),
		"occluded combat case starts behind a solid wall")
	visible_ticks = 0
	closest = 100
	for tick in 1000:
		await physics_frame
		bot.bot_step(player, STEP, false)
		blocked_sight.from = bot.position + Vector3.UP
		visible_ticks += int(bot.get_world_3d().direct_space_state.intersect_ray(blocked_sight).is_empty())
		closest = minf(closest, bot.position.distance_to(player.position))
	check(visible_ticks > 120 and closest > 6,
		"occluded combat finds sight around the wall without chasing into melee range")
	bot.queue_free()
	player.queue_free()
	arena.queue_free()
	await process_frame
	await physics_frame


func _test_game() -> void:
	var workspace := root.get_node("MapWorkspace")
	var original: Dictionary = workspace.active_map
	workspace.active_map = DOC.enclosed_template()
	workspace.active_map.name = "Integration"
	workspace.active_map.player_yaw = 45.0
	var game := preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var start := Time.get_ticks_msec()
	while game.map_loading and Time.get_ticks_msec() - start < 15000:
		await physics_frame
	check(not game.map_loading and not game.map_failed, "game loads custom map")
	print("GAME_MAP_ERROR ", game.custom_arena.validation_error)
	check(game.custom_arena != null and game.player.terrain_enabled, "game enables terrain only for custom map")
	check(game.target.terrain.arena == game.custom_arena, "Bot receives map navigation")
	game._set_preference("floor_grid", false)
	check(game.custom_arena.geometry.get_node("Object_1").get_child(0).material_override.get_shader_parameter("grid_enabled") == false,
		"custom floor honors grid preference")
	check(is_equal_approx(game.input.yaw, PI / 4), "player spawn yaw reaches input")
	game.resume_training()
	check(not game.paused, "custom map can resume")
	game.player.position.x = 17.1
	game._physics_process(STEP)
	check(game.player.position.x > 17, "Bot activity boundary does not reset the player")
	for at in [Vector3(17.1, 0.02, 0), Vector3(-17.1, 0.02, 0),
		Vector3(0, 0.02, 15.1), Vector3(0, 0.02, -15.1), Vector3(17.1, 0.02, 15.1)]:
		game.target.position = at
		game.player.position = Vector3(10, 0.02, 7)
		var before_tick: int = game.clock.tick
		game._physics_process(STEP)
		check(game.target.position.distance_to(at) < 0.5 and game.player.position.x > 9.9
			and game.clock.tick >= before_tick, "Bot crossing bake extent does not restart round: " + str(at))
	game.player.position.y = -30
	game._physics_process(STEP)
	check(game.player.position.distance_to(Vector3(0, 0.02, 7)) < 0.1, "falling resets round to spawn")
	game.target.position = Vector3(4, 3, 0)
	game.target.velocity = Vector3.ZERO
	game.ready_to_start = false
	game.target.bot_step(game.player, STEP, false)
	check(game.target.velocity.y < 0, "normal Bot falls on custom map")
	game.queue_free()
	await process_frame
	workspace.active_map = {}
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	check(game.custom_arena == null and not game.player.terrain_enabled and game.target.terrain.arena == null,
		"default map keeps original movement path")
	game.queue_free()
	workspace.active_map = original
	await process_frame
