extends Node

const DOC = preload("res://scripts/maps/map_document.gd")
const MAP_DIR := "user://maps"
var map_directory := MAP_DIR
var document = DOC.new()
var editor_view: Dictionary = {}
var active_map: Dictionary = {}
var active_path := ""
var return_to_editor := false
var launch_error := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(map_directory)
	document.mark_saved()


func play_map(value: Dictionary, file_path: String = "", from_editor: bool = false) -> String:
	var error := DOC.validate(value)
	if not error.is_empty():
		return error
	active_map = value.duplicate(true)
	active_path = file_path
	return_to_editor = from_editor
	launch_error = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	return ""


func open_editor() -> void:
	if not return_to_editor and not active_map.is_empty():
		if not document.changed():
			document = DOC.new()
			document.data = active_map.duplicate(true)
			document.path = "" if DOC.is_builtin(active_path) else active_path
			document.mark_saved()
			editor_view.clear()
		else:
			launch_error = "保留了尚未保存的编辑内容。"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/editor/map_editor.tscn")


func default_training() -> void:
	active_map = {}
	active_path = ""
	return_to_editor = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func library() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"name": "白盒练习场 · 示例", "path": "res://resources/maps/whitebox-demo.lgmap"}]
	for file in DirAccess.get_files_at(map_directory):
		if file.get_extension().to_lower() == "lgmap":
			result.append({"name": file.get_basename(), "path": map_directory.path_join(file)})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a.name.naturalnocasecmp_to(b.name) < 0)
	return result
