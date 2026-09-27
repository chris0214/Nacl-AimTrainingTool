extends SceneTree

# Use the editor/console engine with --main-pack <exported exe> from outside the source tree.
# Release templates may ignore --script; inspect the actual pack with the matching engine.
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", message)


func _run() -> void:
	check(not FileAccess.file_exists("res://assets/third_party/epic_templates/manny.fbx"),
		"removed mesh absent from pack")
	check(not FileAccess.file_exists("res://tests/run_tests.gd"), "test scripts excluded")
	check(not FileAccess.file_exists("res://tools/godot.ps1"), "build tools excluded")
	for path in ["res://LICENSE", "res://THIRD_PARTY_NOTICES.md", "res://assets/editor/icons/LICENSE"]:
		check(FileAccess.get_file_as_string(path).length() > 100, "license text in pack " + path)
	var icon = load("res://assets/editor/icons/box.svg") as Texture2D
	check(icon != null and icon.get_width() == 24, "imported runtime SVG texture in pack")
	var map = load("res://scripts/maps/map_document.gd").new()
	var parsed: Dictionary = map.read_map("res://resources/maps/whitebox-demo.lgmap")
	check(not parsed.is_empty(), "built-in JSON map in pack")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pause_training()
	game._set_preference("bot_model", 0)
	check(game.target.model.name == "TrainingRobot", "pack uses original robot")
	game._set_preference("weapon_mode", 1)
	await process_frame
	game.reset_training()
	game.input.preview_scoped = true
	game._update_camera()
	check(game.hud.scope_overlay.lens.visible, "pack scope lens activates")
	if DisplayServer.get_name() != "headless":
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		check(not game.hud.scope_overlay.lens.viewport.get_texture().get_image().is_empty(), "lens renders in exported pack")
	game.pause_training()
	var dialog = load("res://scripts/ui/license_panel.gd").new()
	game.hud.root.add_child(dialog)
	dialog.popup_centered(Vector2i(700, 460))
	await process_frame
	check(dialog.visible and dialog.get_child(0) != null, "packed license dialog opens")
	dialog.queue_free()
	game.queue_free()
	await process_frame
	var editor = load("res://scenes/editor/map_editor.tscn").instantiate()
	root.add_child(editor)
	for frame in 8:
		await process_frame
	var icon_count := 0
	for button in editor.find_children("*", "Button", true, false):
		if button.icon != null:
			icon_count += 1
	check(icon_count > 10, "exported editor has populated icon buttons")
	editor.queue_free()
	await process_frame
	print("EXPORT_PROBE_RESULT failures=%d" % failures)
	quit(1 if failures else 0)
