extends ConfirmationDialog

signal chosen(data: Dictionary, path: String)
signal default_chosen
const DOC = preload("res://scripts/maps/map_document.gd")
var list: ItemList
var status: Label
var picker: FileDialog
var entries: Array[Dictionary] = []


func _ready() -> void:
	title = "选择地图"
	size = Vector2i(600, 420)
	ok_button_text = "加载"
	cancel_button_text = "取消"
	var layout := VBoxContainer.new()
	add_child(layout)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(520, 260)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(list)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status)
	var import_button := Button.new()
	import_button.text = "导入 .lgmap"
	import_button.pressed.connect(func(): picker.popup_centered_ratio(0.75))
	layout.add_child(import_button)
	picker = FileDialog.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.lgmap ; LG Trainer Map"])
	picker.file_selected.connect(_import)
	add_child(picker)
	dialog_hide_on_ok = false
	confirmed.connect(_load)
	list.item_activated.connect(func(_index: int): _load())
	refresh()


func refresh() -> void:
	entries = get_node("/root/MapWorkspace").library()
	list.clear()
	list.add_item("默认训练场")
	for entry in entries:
		list.add_item(entry.name)
	list.select(0)


func _load() -> void:
	var selection := list.get_selected_items()
	if selection.is_empty():
		return
	if selection[0] == 0:
		hide()
		default_chosen.emit()
		return
	var path: String = entries[selection[0] - 1].path
	var result := DOC.read_map(path)
	if result.has("error"):
		status.text = result.error
		return
	hide()
	chosen.emit(result.data, path)


func _import(path: String) -> void:
	var result := DOC.read_map(path)
	if result.has("error"):
		status.text = result.error
		return
	var folder: String = get_node("/root/MapWorkspace").map_directory
	var name := path.get_file().get_basename().validate_filename()
	var destination := folder.path_join(name + ".lgmap")
	var suffix := 1
	while FileAccess.file_exists(destination):
		destination = folder.path_join("%s-%d.lgmap" % [name, suffix])
		suffix += 1
	var error := DOC.write_map(destination, result.data)
	if not error.is_empty():
		status.text = error
		return
	refresh()
	for index in entries.size():
		if entries[index].path == destination:
			list.select(index + 1)
			break
	status.text = "已导入：" + destination.get_file()
