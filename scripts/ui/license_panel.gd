extends AcceptDialog


static func engine_licenses() -> String:
	var text := "GODOT ENGINE\n\n" + Engine.get_license_text() + "\n\nCOMPONENTS\n\n"
	for component in Engine.get_copyright_info():
		text += str(component) + "\n\n"
	text += "\nLICENSE TEXTS\n\n"
	var licenses := Engine.get_license_info()
	for title in licenses:
		text += str(title) + "\n" + str(licenses[title]) + "\n\n"
	return text


func _ready() -> void:
	title = "关于与许可"
	min_size = Vector2i(480, 320)
	var text := TextEdit.new()
	text.editable = false
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.custom_minimum_size = Vector2(480, 280)
	text.text = "Nacl Aim Training Tool\n作者：bilibili：克里斯提亚娜\n\n"
	for path in ["res://LICENSE", "res://THIRD_PARTY_NOTICES.md", "res://assets/editor/icons/LICENSE"]:
		text.text += FileAccess.get_file_as_string(path) + "\n\n"
	text.text += engine_licenses()
	add_child(text)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
