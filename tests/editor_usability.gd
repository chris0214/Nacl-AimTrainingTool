extends SceneTree

const DOC = preload("res://scripts/maps/map_document.gd")
const GEOMETRY = preload("res://scripts/maps/map_geometry.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func place(editor: Control, kind: String, at: Vector3, size: Vector3) -> void:
	editor.set_tool(kind)
	var snap: float = editor.snap_control.value
	editor.snap_control.value = 0
	var first: Vector2 = editor.camera.unproject_position(at - Vector3(size.x, 0, size.z) * 0.5)
	var last: Vector2 = editor.camera.unproject_position(at + Vector3(size.x, 0, size.z) * 0.5)
	editor._pointer_down(first)
	editor._pointer_motion(last)
	editor._pointer_up(last)
	var raised := last - Vector2(0, size.y / 0.025)
	editor._pointer_motion(raised)
	editor._pointer_down(raised)
	editor._pointer_up(raised)
	editor.snap_control.value = snap


func _run() -> void:
	var blank := DOC.template()
	check(blank.objects.is_empty() and blank.infinite_ground and DOC.validate(blank).is_empty(),
		"new map is playable empty infinite ground")
	check(DOC.validate(DOC.enclosed_template()).is_empty(), "legacy optional fields remain compatible")
	for invalid in [{"infinite_ground": 1}, {"infinite_ground": false}]:
		var value := blank.duplicate(true)
		value.merge(invalid, true)
		check(not DOC.validate(value).is_empty(), "invalid ground setting rejected")
	var stair := DOC.object_data(1, "stairs", Vector3(0, 0, 0), Vector3(3, 3, 1))
	stair.auto_steps = true
	DOC.fit_stairs(stair)
	check(stair.steps == 12 and is_equal_approx(stair.size[2], 4.8), "steep stairs gain count AND run")
	var value := blank.duplicate(true)
	value.objects.append(stair)
	check(DOC.validate(value).is_empty(), "fitted stairs validate")
	value.objects[0].steps = 1
	check(not DOC.validate(value).is_empty(), "unsafe automatic stair document rejected")
	stair = DOC.object_data(1, "stairs", Vector3.ZERO, Vector3(3, 64, 1))
	stair.auto_steps = true
	DOC.fit_stairs(stair)
	check(stair.size[1] == 16 and stair.steps == 64 and stair.size[2] >= 25.6,
		"automatic stairs obey bounded step budget")

	var workspace := root.get_node("MapWorkspace")
	workspace.document.data = blank.duplicate(true)
	var editor := preload("res://scenes/editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	await physics_frame
	check(editor.ground != null and editor.objects.item_count == 0, "blank editor has ground and no fake objects")
	editor.toggle_view()
	await process_frame
	editor.set_tool("box")
	var mouse: Vector2 = editor.camera.unproject_position(Vector3(-6, 0, 0))
	editor._hover(mouse)
	check(editor.hover_preview != null and editor.hover_preview.collision_layer == 0, "placement ghost has no collision")
	place(editor, "box", Vector3(-6, 0, 0), Vector3(2, 2, 2))
	check(editor.document.data.objects.size() == 1 and not editor.raising, "staged gesture places box")
	await physics_frame
	editor.set_tool("box")
	var top: Vector2 = editor.camera.unproject_position(Vector3(-6, 2, 0))
	editor._hover(top)
	check(is_equal_approx(editor.hover_preview.position.y, 2), "surface preview sits on existing box")
	place(editor, "box", Vector3(-6, 2, 0), Vector3(1, 2, 1))
	check(is_equal_approx(editor.document.object_by_id(2).position[1], 2), "surface placement stacks without overlap")
	editor.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	editor.camera.position = Vector3(0, 3, 0)
	editor.camera.look_at(Vector3(-6, 1, 0))
	editor.set_tool("box")
	var side: Vector2 = editor.camera.unproject_position(Vector3(-5, 1, 0))
	var side_at: Vector3 = editor._placement(side)
	check(is_equal_approx(side_at.x, -5), "placement corner anchors to clicked wall face")
	editor.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	editor.camera.position = Vector3(0, 60, 0)
	editor.camera.rotation = Vector3(-PI / 2, 0, 0)
	editor._clear_hover()
	editor.select_id(1)
	var original: String = JSON.stringify(editor.document.data)
	var history: int = editor.document.undo_stack.size()
	editor.slider_gesture = true
	editor.slider_checkpoint = false
	editor._edit_field("size:0", 3, false)
	editor._edit_field("size:0", 4, false)
	editor._edit_field("size:0", 5, false)
	editor.slider_gesture = false
	check(editor.document.undo_stack.size() == history + 1, "slider drag creates one undo transaction")
	editor.undo()
	check(JSON.stringify(editor.document.data) == original, "single undo restores slider start")
	editor.set_tool("scale")
	await physics_frame
	var center: Vector2 = editor.camera.unproject_position(editor.handles.position + Vector3.RIGHT * 1.4)
	editor._pointer_down(center)
	editor._pointer_motion(center + Vector2(40, 0))
	editor._pointer_up(center + Vector2(40, 0))
	check(editor.document.object_by_id(1).size[0] > 2, "axis scale changes dimension")
	editor.undo()
	print("SCALE_UNDO_WIDTH ", editor.document.object_by_id(1).size[0])
	check(is_equal_approx(editor.document.object_by_id(1).size[0], 2), "axis scale undo")
	editor.set_tool("stairs")
	mouse = editor.camera.unproject_position(Vector3(3, 0, 0))
	place(editor, "stairs", Vector3(3, 0, 0), Vector3(4, 1.6, 6.4))
	editor._edit_field("size:1", 3, false)
	editor._edit_field("size:2", 1, false)
	var item: Dictionary = editor.document.object_by_id(3)
	check(item.auto_steps and item.steps == 12 and item.size[2] >= 4.8, "inspector auto-adjusts steep stairs")
	check(is_equal_approx(editor.field_controls["size:2"].value, item.size[2]), "auto-corrected dimension appears in inspector")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.alt_pressed = true
	var old_value: float = editor.field_controls["size:0"].value
	editor._number_wheel(wheel, editor.field_controls["size:0"])
	check(is_equal_approx(editor.document.object_by_id(3).size[0], old_value + 0.1), "numeric wheel precise increment")
	var before: Vector3 = editor.camera.position
	editor.toggle_view()
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	editor._viewport_input(middle)
	before = editor.camera.position
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30, 15)
	editor._viewport_input(motion)
	check(editor.camera.position.distance_to(before) > 1, "MMB orbit changes camera")
	before = editor.camera.position
	motion.shift_pressed = true
	editor._viewport_input(motion)
	check(editor.camera.position.distance_to(before) > 0.2, "Shift MMB pans camera")
	editor._stop_flying()
	editor._clear_hover()
	editor.focus_selected()
	check(editor._save_to("res://artifacts/editor-v2.lgmap", false), "new map format saves")
	var saved := DOC.read_map("res://artifacts/editor-v2.lgmap")
	check(saved.has("data") and saved.data.infinite_ground, "ground setting roundtrips: " + str(saved.get("error", "")))
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		await process_frame
		await process_frame
		check(editor.inspector.get_parent().get_global_rect().end.x <= size.x + 1, "inspector fits " + str(size))
		check(editor.tools.bot.get_global_rect().end.y < size.y - 28, "tool rail fits " + str(size))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/editor-v2-%dx%d.png" % [size.x, size.y])
			var scene_image: Image = editor.viewport.get_texture().get_image()
			var colors := {}
			for y in range(0, scene_image.get_height(), 12):
				for x in range(0, scene_image.get_width(), 12):
					colors[scene_image.get_pixel(x, y).to_html()] = true
			check(colors.size() > 24, "native checker and scene render nonblank")
	editor.queue_free()
	await process_frame

	var arena := preload("res://scenes/arena/flat_arena.tscn").instantiate()
	arena.set_script(preload("res://scripts/maps/custom_arena.gd"))
	arena.map_data = blank.duplicate(true)
	root.add_child(arena)
	var started := Time.get_ticks_msec()
	while arena.loading and Time.get_ticks_msec() - started < 15000:
		await physics_frame
	check(not arena.loading and arena.validation_error.is_empty() and arena.navigation_ready,
		"empty infinite ground navigation loads: " + arena.validation_error)
	check(arena.has_support(Vector3(3000, 0, 3000)), "ground collision beyond visual patch and navigation extent")
	check(arena.has_support(Vector3(100, 0, 100)), "infinite map supports roaming outside bake extent")
	check(arena.path_between(Vector3(100, 0, 100), Vector3(110, 0, 100)).is_empty(),
		"out-of-bake navigation does not return a false clamped route")
	var player := preload("res://scenes/actors/arena_actor.tscn").instantiate()
	root.add_child(player)
	player.profile = preload("res://resources/movement/normal.tres")
	player.terrain_enabled = true
	player.floor_constant_speed = true
	player.floor_snap_length = 0.35
	player.floor_max_angle = deg_to_rad(44)
	player.reset_at(Vector3(3000, 0.02, 3000))
	for tick in 100:
		await physics_frame
		player.simulate(Vector2(1, 0), 0, false, STEP)
	check(player.position.y > -0.02 and player.position.x > 3002, "player walks on remote infinite ground")
	var barrier := GEOMETRY.build_object(DOC.object_data(10, "barrier", Vector3(0, 0, 0), Vector3(6, 4, 0.6)))
	arena.geometry.add_child(barrier)
	await physics_frame
	check(not barrier.get_child(0).visible and barrier.collision_layer == 1, "blocking volume invisible but solid")
	player.reset_at(Vector3(0, 0.02, 2))
	for tick in 90:
		await physics_frame
		player.simulate(Vector2(0, -1), 0, false, STEP)
	check(player.position.z > 0.6, "barrier prevents walking through boundary")
	barrier.queue_free()
	await physics_frame
	stair = DOC.object_data(11, "stairs", Vector3.ZERO, Vector3(4, 3, 1))
	stair.auto_steps = true
	DOC.fit_stairs(stair)
	arena.geometry.add_child(GEOMETRY.build_object(stair))
	player.reset_at(Vector3(0, 0.02, 4))
	var maximum := 0.0
	for tick in 180:
		await physics_frame
		player.simulate(Vector2(0, -1), 0, false, STEP)
		maximum = maxf(maximum, player.position.y)
	check(maximum > 2.9, "automatically repaired steep staircase is actually climbable")
	player.queue_free()
	arena.queue_free()
	await process_frame
	workspace.active_map = blank.duplicate(true)
	var game := preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	started = Time.get_ticks_msec()
	while game.map_loading and Time.get_ticks_msec() - started < 15000:
		await physics_frame
	check(not game.map_loading and not game.map_failed, "game accepts the empty infinite map")
	game._set_preference("floor_grid", false)
	check(game.custom_arena.infinite_ground.visual.material_override.get_shader_parameter("grid_enabled") == false,
		"infinite runtime ground honors display preferences")
	game.resume_training()
	game.player.position = Vector3(100, 0.02, 100)
	game.target.position = Vector3(105, 0.02, 100)
	game.player_health = 777
	game.round_time = 12
	game._physics_process(STEP)
	check(game.player_health == 777 and game.round_time >= 12 and game.target.position.x > 100,
		"outside bake extent keeps health and round state")
	game.target.attack_enabled = false
	var bot_start: Vector3 = game.target.position
	for tick in 120:
		await physics_frame
		game.target.bot_step(game.player, STEP, false)
	check(game.target.position.y > -0.1 and game.target.position.distance_to(bot_start) > 1,
		"Bot continues supported combat movement outside navigation area")
	game.queue_free()
	workspace.active_map = {}
	await process_frame
	print("EDITOR_USABILITY_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
