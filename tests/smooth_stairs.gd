extends SceneTree

const DOC = preload("res://scripts/maps/map_document.gd")
const GEOMETRY = preload("res://scripts/maps/map_geometry.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var arena: Node3D


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _load(data: Dictionary) -> void:
	arena = preload("res://scenes/arena/flat_arena.tscn").instantiate()
	arena.set_script(preload("res://scripts/maps/custom_arena.gd"))
	arena.map_data = data
	root.add_child(arena)
	var start := Time.get_ticks_msec()
	while arena.loading and Time.get_ticks_msec() - start < 15000:
		await physics_frame
	check(not arena.loading and arena.navigation_ready and arena.validation_error.is_empty(), "smooth map loads navigation")


func _run() -> void:
	await _test_empty()
	var data := DOC.template()
	var stairs := DOC.object_data(1, "stairs", Vector3(-6, 0, 0), Vector3(4, 3, 4.8))
	stairs.auto_steps = true
	DOC.fit_stairs(stairs)
	data.objects = [stairs,
		DOC.object_data(2, "ramp", Vector3(6, 0, 0), Vector3(4, 3, 4.8)),
		DOC.object_data(3, "box", Vector3(0, 0, -4.4), Vector3(20, 3, 4))]
	data.player_spawn = [-6.0, 0.02, 5.0]
	data.bot_spawn = [6.0, 3.02, -4.0]
	await _load(data)
	await _test_layers(stairs)
	await _test_motion()
	arena.queue_free()
	await process_frame
	data.objects[0].size = [4.0, 10.25, 16.4]
	DOC.fit_stairs(data.objects[0])
	data.objects[1].size = [4.0, 10.25, 16.4]
	data.objects[2].size = [20.0, 10.25, 4.0]
	data.objects[2].position = [0.0, 0.0, -10.2]
	data.player_spawn = [-6.0, 0.02, 10.0]
	data.bot_spawn = [6.0, 10.27, -10.0]
	await _load(data)
	await _test_motion(10.25, 16.4)
	arena.queue_free()
	await process_frame
	await _test_inspector()
	print("SMOOTH_STAIRS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_empty() -> void:
	await _load(DOC.template())
	var meshes := arena.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 1 and meshes[0] == arena.infinite_ground.visual,
		"empty infinite map has only the ground mesh, no anonymous wall trims")
	check(arena.geometry.get_child_count() == 0, "empty map has no invisible default walls")
	check(arena.has_support(Vector3(500, 0, 500)), "infinite ground still supports outside old frame")
	if DisplayServer.get_name() != "headless":
		var camera := Camera3D.new()
		arena.add_child(camera)
		camera.position = Vector3(23, 12, 25)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		root.size = Vector2i(1440, 900)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/infinite-no-frame.png")
	arena.queue_free()
	await process_frame
	var original := preload("res://scenes/arena/flat_arena.tscn").instantiate()
	root.add_child(original)
	check(original.find_children("*", "MeshInstance3D", true, false).size() == 9,
		"default arena retains its own walls and trims")
	original.queue_free()
	await process_frame


func _test_layers(stairs: Dictionary) -> void:
	var body: StaticBody3D = arena.geometry.get_node("Object_1")
	check(body.collision_layer == 64 and body.get_node("WalkSurface").collision_layer == 1,
		"detail and movement layers separated")
	var preview := GEOMETRY.build_object(stairs, true)
	check(preview.collision_layer == 1 and not preview.has_node("WalkSurface"), "editor picks actual treads without proxy")
	preview.free()
	var space := arena.get_world_3d().direct_space_state
	var origin := Vector3(-6, 6, 1.9)
	var support := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 8, 1))
	var weapon := LgWeapon.new()
	var shot := weapon.trace(space, origin, Vector3.DOWN)
	check(not support.is_empty() and is_equal_approx(support.position.y, 0.3125), "support ray sees continuous slope")
	check(not shot.is_empty() and is_equal_approx(shot.position.y, 0.5), "weapon sees actual tread above slope")
	var riser := weapon.trace(space, Vector3(-6, 0.45, 4), Vector3.FORWARD)
	check(not riser.is_empty() and is_equal_approx(riser.position.z, 2.0), "weapon hits actual riser, not hidden wedge")
	var path: PackedVector3Array = arena.path_between(Vector3(-6, 0.02, 4), Vector3(-6, 3.02, -4))
	check(not path.is_empty() and path[-1].y > 2.9, "Bot route climbs smooth staircase")
	check(DOC.write_map("res://artifacts/smooth-stairs.lgmap", arena.map_data).is_empty(), "existing map format saves")
	check(DOC.read_map("res://artifacts/smooth-stairs.lgmap").has("data"), "existing map format imports")


func _test_motion(height: float = 3, depth: float = 4.8) -> void:
	var player := preload("res://scenes/actors/arena_actor.tscn").instantiate()
	root.add_child(player)
	player.profile = preload("res://resources/movement/normal.tres")
	player.terrain_enabled = true
	player.instant_movement = true
	player.floor_constant_speed = true
	player.floor_snap_length = 0.35
	player.floor_max_angle = deg_to_rad(44)
	for descending in [false, true]:
		var reference: Array[Vector3] = []
		for x in [-6.0, 6.0]:
			var start_z := depth * 0.5 + 1.6
			player.reset_at(Vector3(x, height + 0.02 if descending else 0.02, -start_z if descending else start_z))
			for tick in 10:
				await physics_frame
				player.simulate(Vector2.ZERO, 0, false, STEP)
			var last: Vector3 = player.position
			var last_dy := 0.0
			var previous_inside := false
			var max_change := 0.0
			var max_lift := 0.0
			var samples := 0
			var mismatch := 0.0
			var ticks := int((depth + 4.8) / (8.5 / sqrt(1 + pow(height / depth, 2))) / STEP)
			for tick in ticks:
				await physics_frame
				player.simulate(Vector2(0, 1 if descending else -1), 0, false, STEP)
				var dy: float = player.position.y - last.y
				var inside: bool = absf(player.position.z) < depth * 0.5 - 0.6 and absf(last.z) < depth * 0.5 - 0.6
				if inside and previous_inside:
					max_change = maxf(max_change, absf(dy - last_dy))
					max_lift = maxf(max_lift, player.step_camera_offset)
					samples += 1
				previous_inside = inside
				last_dy = dy
				last = player.position
				var local := Vector3(player.position.x - x, player.position.y, player.position.z)
				if x < 0:
					reference.append(local)
				else:
					mismatch = maxf(mismatch, local.distance_to(reference[tick]))
			print("SMOOTH_MOTION height=", height, " x=", x, " descending=", descending, " delta_change=", max_change,
				" camera_lift=", max_lift, " ramp_difference=", mismatch, " samples=", samples)
			check(samples > 30, "measured enough slope samples")
			# Allow millimetre-scale convex contact error, not the former 0.25 m tread impulses.
			check(max_change < 0.005, "no per-tread vertical impulse")
			check(max_lift < 0.001, "slope does not trigger discrete camera step easing")
			check(player.position.y < 0.1 if descending else player.position.y > height - 0.1, "player reaches slope endpoint")
			if x > 0:
				check(mismatch < (0.015 if depth > 10 else 0.005), "staircase movement matches equivalent ramp")
	player.queue_free()
	await process_frame


func _test_inspector() -> void:
	var workspace := root.get_node("MapWorkspace")
	workspace.document.data = DOC.template()
	var item := DOC.object_data(1, "stairs", Vector3.ZERO, Vector3(5, 3, 4.8))
	item.auto_steps = true
	DOC.fit_stairs(item)
	workspace.document.data.objects = [item]
	workspace.document.selected = 1
	var editor := preload("res://scenes/editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	editor.active_face = 3
	editor._refresh_inspector()
	editor.focus_selected()
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		await process_frame
		await process_frame
		check(editor.viewport_panel.size.x >= 500, "sidebar leaves useful viewport space")
		check(editor.inspector.size.x >= 300, "inspector offers wider fields")
		check(editor.inspector.get_global_rect().end.x <= size.x - 10, "inspector has right padding")
		var transform: Control = editor.inspector.get_node("TransformFields")
		check(not transform.visible, "secondary transforms collapsed initially")
		for axis in 3:
			var spin: SpinBox = editor.field_controls["size:%d" % axis]
			var slider: HSlider = spin.get_parent().get_child(2)
			check(spin.size.x >= 100 and spin.size.y >= 30, "dimension input is comfortably sized")
			check(slider.get_global_rect().position.x >= spin.get_global_rect().end.x + 7,
				"dimension slider does not crowd input")
			check(slider.get_global_rect().end.x <= editor.inspector.get_global_rect().end.x,
				"dimension slider stays in sidebar")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/inspector-roomy-%dx%d.png" % [size.x, size.y])
		editor.inspector.get_node("TransformToggle").pressed.emit()
		await process_frame
		check(editor._transform_section().visible, "transform disclosure expands")
		var before: float = item.position[0]
		editor.field_controls["position:0"].value = before + 1
		check(item.position[0] == before + 1, "expanded position input edits geometry")
		editor.undo()
		item = editor.document.object_by_id(1)
		editor.inspector.get_node("TransformToggle").pressed.emit()
	editor.queue_free()
	await process_frame
