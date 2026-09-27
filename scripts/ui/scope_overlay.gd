extends Control

const STYLE = preload("res://scripts/ui/reticle_style.gd")
var style_values := STYLE.DEFAULTS.duplicate()
var zoom_label: Label
var line_color := Color("#91eee0")
var line_width := 1.0
var dot_radius := 1.2
var mask_strength := 0.94
var lens: ColorRect


func configure(values: Dictionary) -> void:
	style_values = values.duplicate()
	line_color = values.scope_color
	line_width = values.scope_width
	dot_radius = values.scope_dot
	mask_strength = values.scope_mask / 100.0
	lens.configure(values)
	queue_redraw()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	lens = preload("res://scripts/ui/scope_lens.gd").new()
	add_child(lens)
	lens.configure(style_values)
	zoom_label = Label.new()
	zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	zoom_label.offset_left = -90
	zoom_label.offset_right = 90
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_label.add_theme_font_size_override("font_size", 15)
	zoom_label.add_theme_color_override("font_color", Color("#dce8e3"))
	zoom_label.add_theme_color_override("font_outline_color", Color("#151d20"))
	zoom_label.add_theme_constant_override("outline_size", 4)
	add_child(zoom_label)
	resized.connect(_resize)
	_resize()
	hide()


func _resize() -> void:
	if is_instance_valid(zoom_label):
		zoom_label.position.y = size.y * 0.5 - minf(size.x, size.y) * 0.4 + 20
	queue_redraw()


func set_scope(active: bool, zoom: float) -> void:
	visible = active
	if not active:
		lens.deactivate()
	zoom_label.text = "%.1f ×" % zoom


func _draw() -> void:
	STYLE.draw_scope(self, Rect2(Vector2.ZERO, size), style_values)
