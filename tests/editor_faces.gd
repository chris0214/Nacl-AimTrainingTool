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
	_test_math()
	var workspace := root.get_node("MapWorkspace")
	workspace.document.data = DOC.template()
	editor = preload("res://scenes/editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	await physics_frame
	for yaw in [0.0, 37.0, 90.0]:
		for face in 6:
			await _test_drag(yaw, face)
	await _test_cancel()
	await _test_panel()
	await _test_visuals()
	editor.queue_free()
	await process_frame
	print("EDITOR_FACES_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_math() -> void:
	var original := DOC.object_data(1, "box", Vector3(2, 10, -3), Vector3(4, 3, 6))
	for yaw in [0.0, 37.0, 90.0, -126.0]:
		original.yaw = yaw
		for face in 6:
			for delta in [-1.0, 1.0, 0.0]:
				var result := FACES.resized(original, face, delta, 0.5)
				check(FACES.center(result, face ^ 1).is_equal_approx(FACES.center(original, face ^ 1)),
					"opposite face fixed yaw=%s face=%s delta=%s" % [yaw, face, delta])
				check(FACES.center(result, face).is_equal_approx(FACES.center(original, face) + FACES.normal(face, yaw) * delta),
					"moving face follows local normal")
				check(is_equal_approx(result.size[face / 2], original.size[face / 2] + delta), "face changes only its dimension")
			var small := FACES.resized(original, face, -1000, 0.5)
			check(is_equal_approx(small.size[face / 2], 0.1), "cannot invert a box face")
	var top := FACES.resized(original, 3, 1000, 0.5)
	check(is_equal_approx(top.position[1] + top.size[1], 48), "top constrained to map ceiling")
	var bottom := FACES.resized(original, 2, 1000, 0.5)
	check(is_equal_approx(bottom.position[1], -16), "bottom constrained to map depth")
	original.position = [127.9, 10.0, 127.9]
	for face in [0, 1, 4, 5]:
		var result := FACES.resized(original, face, 1000, 0.5)
		check(absf(result.position[0]) <= 128.00001 and absf(result.position[2]) <= 128.00001,
			"rotated face respects position limits")


func _fixture(yaw: float = 0.0) -> Dictionary:
	var item := DOC.object_data(1, "box", Vector3(0, 20, 0), Vector3(4, 3, 6))
	item.yaw = yaw
	editor.document.data = DOC.template()
	editor.document.data.objects = [item]
	editor.document.selected = 1
	editor.document.undo_stack.clear()
	editor.document.redo_stack.clear()
	editor.active_face = -1
	editor.tool = "select"
	editor.top_view = false
	editor.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	editor._rebuild()
	return item.duplicate(true)


func _test_drag(yaw: float, face: int) -> void:
	var original := _fixture(yaw)
	var at := FACES.center(original, face)
	var normal := FACES.normal(face, yaw)
	var tangent := Vector3.RIGHT if absf(normal.y) > 0.9 else Vector3.UP
	editor.camera.position = at + normal * 12 + tangent * 5
	editor.camera.look_at(at)
	await process_frame
	await physics_frame
	var mouse: Vector2 = editor.camera.unproject_position(at)
	var hit: Dictionary = editor._face_under_mouse(mouse)
	check(not hit.is_empty() and hit.face == face, "ray selects correct face yaw=%s face=%s" % [yaw, face])
	editor._pointer_down(mouse)
	check(editor.face_dragging and editor.active_face == face, "select tool starts face drag")
	var end: Vector2 = editor.camera.unproject_position(at + normal)
	editor._pointer_motion(mouse.lerp(end, 0.6))
	editor._pointer_motion(end)
	editor._pointer_up(end)
	var result: Dictionary = editor.document.object_by_id(1)
	check(is_equal_approx(result.size[face / 2], original.size[face / 2] + 1), "screen drag moves face one metre")
	check(FACES.center(result, face ^ 1).is_equal_approx(FACES.center(original, face ^ 1)), "screen drag anchors opposite face")
	check(editor.document.undo_stack.size() == 1, "one gesture one undo")
	var body := GEOMETRY.build_object(result)
	check(body.get_child(1).shape.size.is_equal_approx(DOC.vector3(result.size))
		and body.position.is_equal_approx(DOC.vector3(result.position)), "runtime mesh and collider use edited dimensions")
	body.free()
	editor.undo()
	check(editor.document.object_by_id(1) == original, "undo restores face geometry")
	editor.redo()
	check(is_equal_approx(editor.document.object_by_id(1).size[face / 2], original.size[face / 2] + 1), "redo reapplies face geometry")


func _test_cancel() -> void:
	var original := _fixture()
	var at := FACES.center(original, 5)
	editor.camera.position = at + Vector3(0, 0, 12)
	editor.camera.look_at(at)
	await process_frame
	await physics_frame
	var mouse: Vector2 = editor.camera.unproject_position(at)
	editor._pointer_down(mouse)
	check(not editor.face_uses_plane, "head-on drag uses stable vertical mapping")
	editor._pointer_motion(mouse - Vector2(0, 60))
	check(editor.document.object_by_id(1).size[2] > 6, "head-on drag can push face outward")
	editor._cancel_gesture()
	check(editor.document.object_by_id(1) == original and editor.document.undo_stack.is_empty(), "cancel restores box and history")
	editor._edit_field("size:0", 5, false)
	editor.undo()
	var redo_count: int = editor.document.redo_stack.size()
	await physics_frame
	editor._pointer_down(mouse)
	editor._pointer_motion(mouse - Vector2(0, 60))
	editor._cancel_gesture()
	check(editor.document.redo_stack.size() == redo_count, "cancel preserves previous redo history")
	await physics_frame
	editor._pointer_down(mouse)
	editor._pointer_up(mouse)
	check(editor.document.undo_stack.is_empty(), "selection-only click does not change geometry/history")
	editor._pointer_down(mouse)
	editor._pointer_motion(mouse - Vector2(0, 60))
	editor._pointer_motion(mouse)
	editor._pointer_up(mouse)
	check(editor.document.undo_stack.is_empty(), "drag out and back is a no-op")
	editor._pointer_down(mouse)
	editor._pointer_motion(mouse - Vector2(0, 60))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(1400, 400)
	editor._input(release)
	check(not editor.face_dragging, "release over inspector ends face drag")


func _test_panel() -> void:
	var original := _fixture(37)
	editor.active_face = 2
	editor._refresh_inspector()
	editor.slider_gesture = true
	editor.slider_checkpoint = false
	editor._panel_face_offset(0.5)
	editor._panel_face_offset(1.0)
	editor.slider_gesture = false
	var result: Dictionary = editor.document.object_by_id(1)
	check(is_equal_approx(result.position[1], 19) and is_equal_approx(result.size[1], 4),
		"panel edits bottom face without needing to see underside")
	check(FACES.center(result, 3).is_equal_approx(FACES.center(original, 3)), "bottom panel edit keeps top anchored")
	check(editor.document.undo_stack.size() == 1, "panel face slider coalesces history")
	check(editor._save_to("res://artifacts/face-edited.lgmap", false), "face-edited map saves")
	check(DOC.read_map("res://artifacts/face-edited.lgmap").has("data"), "face-edited map imports with existing format")


func _test_visuals() -> void:
	editor.document.data = DOC.template()
	editor.document.data.objects = [
		DOC.object_data(1, "box", Vector3(0, 0, -4), Vector3(10, 4, 0.7)),
		DOC.object_data(2, "box", Vector3(-5, 0, 0), Vector3(0.7, 4, 8)),
		DOC.object_data(3, "box", Vector3(5, 0, 0), Vector3(0.7, 4, 8)),
		DOC.object_data(4, "stairs", Vector3(0, 0, 1), Vector3(3, 2, 5))]
	editor.document.selected = 1
	editor.active_face = 5
	editor.hovered_face = 5
	editor._rebuild()
	editor.camera.position = Vector3(10, 8, 11)
	editor.camera.look_at(Vector3(0, 2, -1))
	check(editor.selection.material_override is ShaderMaterial, "selection uses edge shader instead of tinted volume")
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		await process_frame
		await process_frame
		check(editor.inspector.get_parent().get_global_rect().end.x <= size.x + 1, "face controls fit " + str(size))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/editor-faces-%dx%d.png" % [size.x, size.y])
			var image: Image = editor.viewport.get_texture().get_image()
			var edge_pixels := 0
			for y in range(0, image.get_height(), 2):
				for x in range(0, image.get_width(), 2):
					var color := image.get_pixel(x, y)
					if color.r > 0.9 and color.g > 0.35 and color.g < 0.85 and color.b < 0.5:
						edge_pixels += 1
			check(edge_pixels > 60, "native orange outline pixels visible")
