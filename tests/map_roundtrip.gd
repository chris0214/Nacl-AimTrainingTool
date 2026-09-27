extends SceneTree

const DOC = preload("res://scripts/maps/map_document.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", text)


func wait_scene(name: String) -> Node:
	for attempt in 300:
		await process_frame
		if current_scene != null and current_scene.name == name and current_scene.is_node_ready():
			return current_scene
	check(false, "scene transition timeout: " + name)
	return null


func _run() -> void:
	var workspace := root.get_node("MapWorkspace")
	workspace.map_directory = "res://artifacts/map-library"
	DirAccess.make_dir_recursive_absolute(workspace.map_directory)
	var sample := DOC.read_map("res://resources/maps/whitebox-demo.lgmap")
	check(sample.has("data"), "bundled example validates")
	workspace.document.data = sample.data.duplicate(true)
	workspace.document.mark_saved()
	workspace.open_editor()
	var editor := await wait_scene("MapEditor")
	editor.select_id(9)
	editor._edit_field("size:0", 3, false)
	var snapshot: String = JSON.stringify(editor.document.data)
	var history: int = editor.document.undo_stack.size()
	editor.play()
	var game := await wait_scene("Trainer")
	var loading_started := Time.get_ticks_msec()
	while game.map_loading and Time.get_ticks_msec() - loading_started < 15000:
		await physics_frame
	print("ROUNDTRIP_LOAD loading=", game.map_loading, " failed=", game.map_failed,
		" detail=", game.custom_arena.validation_error)
	check(not game.map_failed and not game.map_loading, "actual play button loads and validates the map")
	check(workspace.return_to_editor, "trial keeps return-to-editor state")
	check(JSON.stringify(workspace.document.data) == snapshot and workspace.document.changed(),
		"play keeps unsaved editor document")
	check(game.custom_arena.geometry.get_node("Object_9").get_child(0).mesh.size.x == 3,
		"unsaved geometry is playable")
	game.resume_training()
	if DisplayServer.get_name() != "headless":
		var warmup := Time.get_ticks_msec()
		while Time.get_ticks_msec() - warmup < 1100:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/map-editor-play.png")
	game.pause_training()
	game.hud.map_editor_requested.emit()
	editor = await wait_scene("MapEditor")
	check(JSON.stringify(editor.document.data) == snapshot and editor.document.undo_stack.size() == history
		and editor.document.selected == 9, "real scene return preserves edits, history and selection")
	editor.undo()
	check(editor.document.object_by_id(9).size[0] == 2, "undo still works after actual play/return")
	editor.redo()
	check(editor._save_to("res://artifacts/map-roundtrip-saved.lgmap", false), "save after returning")
	check(not editor.document.changed(), "saved document becomes clean")
	var library := preload("res://scripts/maps/map_library.gd").new()
	root.add_child(library)
	library._import("res://artifacts/map-roundtrip-saved.lgmap")
	var count: int = workspace.library().size()
	library._import("res://artifacts/map-roundtrip-saved.lgmap")
	check(workspace.library().size() == count + 1, "duplicate imports get unique filenames without overwriting")
	library._import("res://artifacts/map-broken.lgmap")
	check(workspace.library().size() == count + 1, "invalid import does not enter map library")
	var selected := false
	library.chosen.connect(func(_data: Dictionary, _path: String): library.set_meta("chosen", true))
	library.list.select(1)
	library._load()
	selected = library.get_meta("chosen", false)
	check(selected, "map picker loads a validated library entry")
	library.queue_free()
	await process_frame
	workspace.active_map = sample.data.duplicate(true)
	workspace.active_path = "res://resources/maps/whitebox-demo.lgmap"
	workspace.return_to_editor = false
	workspace.open_editor()
	editor = await wait_scene("MapEditor")
	check(editor.document.data.name == sample.data.name and editor.document.path.is_empty(),
		"editing bundled map uses save-as, never overwrites the example")
	check(editor.document.object_by_id(9).size[0] == 2, "editor opens currently loaded map")
	editor.select_id(9)
	editor._edit_field("size:0", 4, false)
	editor._request_action("new")
	check(editor.confirm.visible and editor.document.object_by_id(9).size[0] == 4,
		"new map requires confirmation before discarding changes")
	editor.confirm.hide()
	workspace.default_training()
	game = await wait_scene("Trainer")
	check(game.custom_arena == null, "default map remains available after editor workflow")
	print("MAP_ROUNDTRIP_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
