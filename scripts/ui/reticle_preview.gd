extends Control

const STYLE = preload("res://scripts/ui/reticle_style.gd")
var values := STYLE.DEFAULTS.duplicate()
var background := 0
var cells: Array[Rect2] = []
var tiles: Array[Control] = []


func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for index in 3:
		var tile := Control.new()
		tile.clip_contents = true
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tile)
		tiles.append(tile)
		tile.draw.connect(func(): _draw_tile(tile, index))
	resized.connect(_layout)
	_layout()


func configure(config: Dictionary) -> void:
	values = config.duplicate()
	queue_redraw()
	for tile in tiles:
		tile.queue_redraw()


func _layout() -> void:
	cells.clear()
	for index in tiles.size():
		var area := Rect2(Vector2(size.x * index / 3.0 + 3, 25),
			Vector2(size.x / 3.0 - 6, size.y - 29))
		cells.append(area)
		tiles[index].position = area.position
		tiles[index].size = area.size
		tiles[index].queue_redraw()
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	for index in cells.size():
		var title: String = ["普通 · 1× UI像素", "普通 · 4× 细节", "镜内 · 缩略示意"][index]
		draw_string(font, Vector2(cells[index].position.x + 6, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#dce8e3"))


func _draw_tile(tile: Control, index: int) -> void:
	var colors := [Color("#182329"), Color("#d6dfdb"), Color("#667779")]
	var base: Color = colors[background]
	var ink := Color("#e1eee9") if background == 0 else Color("#122a2e")
	var area := Rect2(Vector2.ZERO, tile.size)
	tile.draw_rect(area, base)
	if background == 2:
		tile.draw_rect(Rect2(area.position, Vector2(area.size.x, area.size.y * 0.45)), Color("#bacbd0"))
		tile.draw_circle(area.get_center(), 18, Color("#27343a"))
	if index == 2:
		STYLE.draw_scope(tile, area, values)
	else:
		STYLE.draw_crosshair(tile, area.get_center(), values, 1 if index == 0 else 4)
	tile.draw_rect(area, Color(ink, 0.3), false, 1)
