extends SceneTree

const DOC = preload("res://scripts/maps/map_document.gd")
const FACES = preload("res://scripts/editor/box_faces.gd")
const GEOMETRY = preload("res://scripts/maps/map_geometry.gd")
var checks := 0
var failures := 0
var editor: Control


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	_test_resize()
	root.get_node("MapWorkspace").document.data = DOC.template()
	editor = preload("res://scenes/editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	for kind in DOC.KINDS:
		await _test_placement(kind, false)
		await _test_placement(kind, true)
	await _test_accidental_input()
	await _test_shape_picking()
	await _test_auto_stairs()
	await _test_stair_lift()
	editor.queue_free()
	await process_frame
	print("EDITOR_SOLID_WORKFLOW_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_resize() -> void:
	for kind in ["stairs", "ramp"]:
		for yaw in [0.0, 37.0, 90.0]:
			var original := DOC.object_data(1, kind, Vector3(3, 5, 2), Vector3(4, 2, 6))
			original.yaw = yaw
			for face in 6:
				for delta in [-0.5, 1.0]:
					var result := FACES.resized(original, face, delta, 0.5)
					check(is_equal_approx(result.size[face / 2], original.size[face / 2] + delta), "shape face adjusts dimension")
					check(FACES.center(result, face ^ 1).is_equal_approx(FACES.center(original, face ^ 1)),
						"opposite bounding plane remains fixed")
					var map := DOC.template()
					map.objects = [result]
					check(DOC.validate(map).is_empty(), "resized shape validates")
					var body := GEOMETRY.build_object(result)
					check(body.collision_layer == (64 if kind == "stairs" else 1) and body.position.is_equal_approx(DOC.vector3(result.position)), "collision origin follows shape")
					body.free()
	var stairs := DOC.object_data(1, "stairs", Vector3(0, 5, 0), Vector3(3, 1, 2))
	stairs.auto_steps = true
	DOC.fit_stairs(stairs)
	for face in 6:
		for delta in [-100.0, 0.5, 100.0]:
			var result := FACES.resized(stairs, face, delta, 0.5)
			var map := DOC.template()
			map.objects = [result]
			check(DOC.validate(map).is_empty(), "automatic stairs remain valid under constrained push/pull")
			check(is_zero_approx((FACES.center(result, face ^ 1) - FACES.center(stairs, face ^ 1)).dot(FACES.normal(face))),
				"auto stairs keep opposite bounding plane")
			check(result.steps == int(ceil(result.size[1] / DOC.MAX_RISE)), "step count follows height")
			if face / 2 == 1:
				var before := FACES.center(stairs, 4)
				var after := FACES.center(result, 4)
				check(Vector2(before.x, before.z).is_equal_approx(Vector2(after.x, after.z)),
					"height pull keeps high landing horizontal position")
	check(FACES.picked_face(DOC.object_data(1, "ramp", Vector3.ZERO, Vector3(2, 6, 1)),
		Vector3(0, 1, 6).normalized()) == 3, "steep ramp slope controls height not depth")


func _reset() -> void:
	editor._cancel_gesture()
	editor.document.data = DOC.template()
	editor.document.selected = -1
	editor.document.undo_stack.clear()
	editor.document.redo_stack.clear()
	editor.top_view = true
	editor.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	editor.camera.position = Vector3(0, 60, 0)
	editor.camera.rotation = Vector3(-PI / 2, 0, 0)
	editor.camera.size = 30
	editor.placement_yaw = 0
	editor._rebuild()


func _test_placement(kind: String, click_mode: bool) -> void:
	_reset()
	editor.set_tool(kind)
	await process_frame
	await physics_frame
	var first: Vector2 = editor.camera.unproject_position(Vector3(-4, 0, -3))
	var last: Vector2 = editor.camera.unproject_position(Vector3(0, 0, 3))
	var raised := last - Vector2(0, 60)
	editor._pointer_down(first)
	if click_mode:
		editor._pointer_up(first)
		check(editor.drawing and editor.document.data.objects.is_empty(), "first corner click never creates an object")
	editor._pointer_motion(last)
	check(editor.drawing and not editor.raising and editor.preview.get_child(0).mesh.size.y < 0.03,
		"first stage previews only the footprint")
	check(editor.preview.collision_layer == 0, "footprint cannot block placement rays")
	if click_mode:
		editor._pointer_down(last)
	editor._pointer_up(last)
	check(editor.raising and not editor.drawing and editor.document.data.objects.is_empty(), "confirm footprint enters height without saving")
	var base: Array = editor.draft.position.duplicate()
	var size: Array = editor.draft.size.duplicate()
	editor._pointer_down(last)
	editor._pointer_up(last)
	check(editor.raising and editor.document.data.objects.is_empty(), "duplicate base confirmation cannot accidentally place")
	editor._pointer_motion(raised)
	check(editor.height_adjusted and is_equal_approx(editor.draft.size[1], 1.5), "height preview follows mouse")
	check(editor.draft.position == base and editor.draft.size[0] == size[0] and editor.draft.size[2] == size[2],
		"confirmed footprint remains unchanged")
	editor._pointer_down(raised)
	check(editor.document.data.objects.is_empty(), "confirmation press alone does not place")
	editor._pointer_up(raised)
	check(editor.document.data.objects.size() == 1 and editor.tool == "select", "confirmation release places and exits creation tool")
	check(editor.document.undo_stack.size() == 1, "whole placement is one undo")
	check(DOC.validate(editor.document.data).is_empty(), "placed object produces a valid map")
	editor.undo()
	check(editor.document.data.objects.is_empty(), "single undo removes placement")
	editor.redo()
	check(editor.document.data.objects.size() == 1, "redo restores placement")


func _test_accidental_input() -> void:
	_reset()
	editor.set_tool("box")
	await physics_frame
	var first: Vector2 = editor.camera.unproject_position(Vector3(-4, 0, -3))
	var last: Vector2 = editor.camera.unproject_position(Vector3(0, 0, 3))
	var event := InputEventMouseButton.new()
	event.position = first
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	editor._viewport_input(event)
	event.pressed = false
	editor._viewport_input(event)
	event.pressed = true
	event.double_click = true
	editor._viewport_input(event)
	event.pressed = false
	editor._viewport_input(event)
	check(editor.drawing and editor.document.data.objects.is_empty(), "double-click does not produce a preset box")
	editor._cancel_gesture()
	check(editor.document.undo_stack.is_empty(), "cancel first stage leaves history untouched")
	editor._pointer_down(first)
	editor._pointer_motion(last)
	editor._pointer_up(last)
	editor._pointer_motion(last - Vector2(0, 80))
	editor._cancel_gesture()
	check(editor.document.data.objects.is_empty() and editor.document.undo_stack.is_empty(), "cancel height discards whole draft")
	editor._pointer_down(first)
	editor._pointer_motion(last)
	editor._pointer_up(last)
	editor._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not editor.raising and editor.draft.is_empty(), "focus loss cancels draft before a refocus click")


func _test_shape_picking() -> void:
	for kind in ["stairs", "ramp"]:
		_reset()
		var item := DOC.object_data(1, kind, Vector3(0, 10, 0), Vector3(4, 2, 6))
		item.yaw = 37
		editor.document.data.objects = [item]
		editor.select_id(1)
		editor._rebuild()
		editor.set_tool("select")
		editor.top_view = false
		editor.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		for face in 6:
			var point := FACES.surface_center(item, face)
			var normal := FACES.normal(face, item.yaw)
			editor.camera.position = point + normal * 6 + (Vector3.RIGHT if face / 2 == 1 else Vector3.UP) * 3
			editor.camera.look_at(point)
			await process_frame
			await physics_frame
			var mouse: Vector2 = editor.camera.unproject_position(editor.face_handles.get_child(face).position)
			var picked: Dictionary = editor._face_under_mouse(mouse)
			check(not picked.is_empty() and picked.face == face, "six shape handles pick correctly: %s %d" % [kind, face])
			editor.active_face = face
			editor._refresh_inspector()
			var original := item.duplicate(true)
			editor._panel_face_offset(0.5)
			check(FACES.center(item, face ^ 1).is_equal_approx(FACES.center(original, face ^ 1)), "shape panel anchors opposite face")
			editor.undo()
			item = editor.document.object_by_id(1)


func _test_auto_stairs() -> void:
	_reset()
	editor.set_tool("stairs")
	await physics_frame
	var first: Vector2 = editor.camera.unproject_position(Vector3(-2, 0, -1))
	var last: Vector2 = editor.camera.unproject_position(Vector3(2, 0, 1))
	editor._pointer_down(first)
	editor._pointer_motion(last)
	editor._pointer_up(last)
	editor._pointer_motion(last - Vector2(0, 400))
	check(is_equal_approx(editor.draft.size[1], 1.25) and editor.draft.size[2] == 2, "auto stairs cap height rather than expand locked footprint")
	check(editor.draft.steps == 5, "bounded height derives climbable step count")
	if DisplayServer.get_name() != "headless":
		editor.top_view = false
		editor.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		editor.camera.position = Vector3(8, 7, 10)
		editor.camera.look_at(Vector3(0, 0.6, 0))
		for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
			root.size = size
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/editor-staged-%dx%d.png" % [size.x, size.y])
	editor._pointer_down(last - Vector2(0, 400))
	editor._pointer_up(last - Vector2(0, 400))
	var item: Dictionary = editor.document.object_by_id(1)
	editor.active_face = 3
	editor._refresh_inspector()
	editor._panel_face_offset(-0.5)
	check(item.steps == 3 and is_equal_approx(item.size[1], 0.75) and item.size[2] == 2, "height pull rebuilds steps without expanding base")
	check(editor._save_to("res://artifacts/staged-stairs.lgmap", false), "edited automatic staircase saves")
	check(DOC.read_map("res://artifacts/staged-stairs.lgmap").has("data"), "edited staircase roundtrips")


func _test_stair_lift() -> void:
	for yaw in [0.0, 37.0, 90.0, -126.0]:
		_reset()
		var item := DOC.object_data(1, "stairs", Vector3(0, 2, 0), Vector3(3, 2, 3.2))
		item.yaw = yaw
		item.auto_steps = true
		DOC.fit_stairs(item)
		var original := item.duplicate(true)
		editor.document.data.objects = [item]
		editor.select_id(1)
		editor._rebuild()
		editor.set_tool("select")
		editor.top_view = false
		editor.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		var point := FACES.surface_center(item, 3)
		editor.camera.position = point + Vector3(5, 5, 8).rotated(Vector3.UP, deg_to_rad(yaw))
		editor.camera.look_at(point)
		await process_frame
		await physics_frame
		var mouse: Vector2 = editor.camera.unproject_position(point)
		var end: Vector2 = editor.camera.unproject_position(point + Vector3.UP)
		editor._pointer_down(mouse)
		check(editor.face_dragging and editor.active_face == 3, "top handle starts automatic staircase lift")
		editor._pointer_motion(end)
		editor._pointer_up(end)
		check(is_equal_approx(item.size[1], 3) and item.steps == 12 and is_equal_approx(item.size[2], 4.8),
			"capped staircase now lifts one metre and adds climbable steps")
		var before := FACES.center(original, 4)
		var after := FACES.center(item, 4)
		check(Vector2(before.x, before.z).is_equal_approx(Vector2(after.x, after.z)) and item.position[1] == 2,
			"lift anchors bottom height and upper landing horizontal alignment")
		check(DOC.validate(editor.document.data).is_empty(), "lifted automatic staircase validates")
		check(editor.document.undo_stack.size() == 1, "height and depth growth are one undo")
		if DisplayServer.get_name() != "headless" and yaw == 0:
			for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
				root.size = size
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/stair-lift-%dx%d.png" % [size.x, size.y])
				var image: Image = editor.viewport.get_texture().get_image()
				var orange := 0
				for y in range(0, image.get_height(), 2):
					for x in range(0, image.get_width(), 2):
						var color := image.get_pixel(x, y)
						if color.r > 0.9 and color.g > 0.35 and color.g < 0.85 and color.b < 0.5:
							orange += 1
				check(orange > 60, "lifted staircase has visible native outline")
				check(editor.inspector.get_parent().get_global_rect().end.x <= size.x + 1,
					"lifted staircase inspector fits window")
		editor.undo()
		check(editor.document.object_by_id(1) == original, "undo restores height depth steps and origin")
		editor.redo()
		check(is_equal_approx(editor.document.object_by_id(1).size[1], 3), "redo restores full lift")
		editor.undo()
		await physics_frame
		editor._pointer_down(mouse)
		editor._pointer_motion(end)
		editor._cancel_gesture()
		check(editor.document.object_by_id(1) == original and editor.document.redo_stack.size() == 1,
			"cancel lift restores geometry and preexisting redo")
		for at in [Vector3(127.9, 0, 127.9), Vector3(-127.9, 0, -127.9)]:
			var edge := original.duplicate(true)
			edge.position = DOC.array3(at)
			var map := DOC.template()
			map.objects = [FACES.resized(edge, 3, 1000, 0)]
			check(DOC.validate(map).is_empty(), "coupled height growth respects rotated map position limits")
