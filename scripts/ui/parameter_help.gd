extends Label


func _make_custom_tooltip(for_text: String) -> Object:
	var label := Label.new()
	label.text = for_text
	label.custom_minimum_size.x = 400
	label.custom_maximum_size.x = 400
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", get_theme_font("font"))
	label.add_theme_font_size_override("font_size", 16)
	return label
