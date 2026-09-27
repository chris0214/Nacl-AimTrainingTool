extends SceneTree


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://build")
	var file := FileAccess.open("res://build/GODOT_LICENSES.txt", FileAccess.WRITE)
	if file == null:
		printerr("Could not write engine license report")
		quit(1)
		return
	file.store_string(preload("res://scripts/ui/license_panel.gd").engine_licenses())
	file.close()
	quit(0)
