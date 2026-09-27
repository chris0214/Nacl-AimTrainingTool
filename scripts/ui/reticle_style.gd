extends RefCounted

# Shared geometry for the live HUD and the settings preview.
const DEFAULTS := {
	"crosshair_color": Color("#f6fff8"), "crosshair_width": 2.0, "crosshair_dot": 1.5,
	"crosshair_inner": true, "crosshair_length_x": 5.0, "crosshair_length_y": 5.0,
	"crosshair_gap": 5.0, "crosshair_opacity": 100.0, "crosshair_t": false,
	"crosshair_outer": false, "outer_length_x": 3.0, "outer_length_y": 3.0,
	"outer_gap": 15.0, "outer_width": 2.0, "outer_opacity": 60.0,
	"crosshair_outline": true, "outline_color": Color("#26352e"),
	"outline_width": 1.0, "outline_opacity": 100.0,
	"crosshair_dot_enabled": true, "dot_opacity": 100.0, "dot_square": false,
	"scope_color": Color("#91eee0"), "scope_width": 1.0, "scope_dot": 1.2,
	"scope_mask": 94.0, "scope_lines": true, "scope_ticks": true,
	"scope_gap": 8.0, "scope_length": 82.0, "scope_opacity": 100.0,
	"scope_dot_opacity": 100.0, "scope_outline": true,
	"scope_outline_width": 1.0, "scope_outline_opacity": 100.0,
	"scope_lens": true, "scope_distortion": 40.0, "scope_edge_shade": 20.0, "scope_quality": 75.0,
	"player_tracer": true, "bot_tracer": true
}
const KEYS := ["crosshair_color", "crosshair_width", "crosshair_dot", "crosshair_inner",
	"crosshair_length_x", "crosshair_length_y", "crosshair_gap", "crosshair_opacity", "crosshair_t",
	"crosshair_outer", "outer_length_x", "outer_length_y", "outer_gap", "outer_width", "outer_opacity",
	"crosshair_outline", "outline_color", "outline_width", "outline_opacity",
	"crosshair_dot_enabled", "dot_opacity", "dot_square", "scope_color", "scope_width", "scope_dot",
	"scope_mask", "scope_lines", "scope_ticks", "scope_gap", "scope_length", "scope_opacity",
	"scope_dot_opacity", "scope_outline", "scope_outline_width", "scope_outline_opacity",
	"scope_lens", "scope_distortion", "scope_edge_shade", "scope_quality", "player_tracer", "bot_tracer"]
const FLAGS := ["crosshair_inner", "crosshair_t", "crosshair_outer", "crosshair_outline",
	"crosshair_dot_enabled", "dot_square", "scope_lines", "scope_ticks", "scope_outline",
	"scope_lens", "player_tracer", "bot_tracer"]
const COLORS := ["crosshair_color", "scope_color", "outline_color"]
# min, max, step. Zero-length lines and zero-opacity parts are genuinely hidden.
const RANGES := {
	"crosshair_width": Vector3(0.5, 8, 0.5), "crosshair_dot": Vector3(0, 8, 0.1),
	"crosshair_length_x": Vector3(0, 30, 0.5), "crosshair_length_y": Vector3(0, 30, 0.5),
	"crosshair_gap": Vector3(0, 40, 0.5), "crosshair_opacity": Vector3(0, 100, 1),
	"outer_length_x": Vector3(0, 30, 0.5), "outer_length_y": Vector3(0, 30, 0.5),
	"outer_gap": Vector3(0, 60, 0.5), "outer_width": Vector3(0.5, 8, 0.5),
	"outer_opacity": Vector3(0, 100, 1), "outline_width": Vector3(0, 4, 0.5),
	"outline_opacity": Vector3(0, 100, 1), "dot_opacity": Vector3(0, 100, 1),
	"scope_width": Vector3(0.5, 8, 0.5), "scope_dot": Vector3(0, 8, 0.1),
	"scope_mask": Vector3(0, 100, 1), "scope_gap": Vector3(0, 40, 0.5),
	"scope_length": Vector3(10, 95, 1), "scope_opacity": Vector3(0, 100, 1),
	"scope_dot_opacity": Vector3(0, 100, 1), "scope_outline_width": Vector3(0, 4, 0.5),
	"scope_outline_opacity": Vector3(0, 100, 1),
	"scope_distortion": Vector3(0, 100, 1), "scope_edge_shade": Vector3(0, 100, 1),
	"scope_quality": Vector3(50, 100, 25)
}
const PRESET_NAMES := ["经典十字", "紧凑十字", "纯圆点", "T形", "内外双线"]


static func preset(index: int) -> Dictionary:
	var values := {}
	for key in KEYS:
		if not key.begins_with("scope_") and key not in ["player_tracer", "bot_tracer"]:
			values[key] = DEFAULTS[key]
	match index:
		1:
			values.merge({"crosshair_color": Color("#79e8e2"), "crosshair_dot_enabled": false,
				"crosshair_width": 1.0, "crosshair_gap": 3.0, "crosshair_length_x": 4.0,
				"crosshair_length_y": 4.0}, true)
		2:
			values.merge({"crosshair_inner": false, "crosshair_color": Color("#79e8e2"),
				"crosshair_dot": 2.0}, true)
		3:
			values.merge({"crosshair_t": true, "crosshair_dot_enabled": false,
				"crosshair_color": Color("#f5d876")}, true)
		4:
			values.merge({"crosshair_outer": true, "crosshair_color": Color("#79e8e2"),
				"crosshair_gap": 3.0, "outer_gap": 12.0}, true)
	return values


static func commands(values: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var outlined: bool = values.crosshair_outline
	var border: Color = values.outline_color
	border.a = values.outline_opacity / 100.0
	for outer in [false, true]:
		if not bool(values.get("crosshair_outer" if outer else "crosshair_inner")):
			continue
		var gap: float = values.outer_gap if outer else values.crosshair_gap
		var width: float = values.outer_width if outer else values.crosshair_width
		var color: Color = values.crosshair_color
		color.a = (values.outer_opacity if outer else values.crosshair_opacity) / 100.0
		if color.a <= 0:
			continue
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			if values.crosshair_t and direction == Vector2.UP:
				continue
			var length: float
			if outer:
				length = values.outer_length_x if direction.x != 0 else values.outer_length_y
			else:
				length = values.crosshair_length_x if direction.x != 0 else values.crosshair_length_y
			if length <= 0:
				continue
			result.append({"kind": "line", "a": direction * gap, "b": direction * (gap + length),
				"width": width, "color": color, "outline": values.outline_width if outlined else 0.0,
				"border": Color(border, border.a * color.a)})
	if values.crosshair_dot_enabled and values.crosshair_dot > 0 and values.dot_opacity > 0:
		var color: Color = values.crosshair_color
		color.a = values.dot_opacity / 100.0
		result.append({"kind": "square" if values.dot_square else "dot", "radius": values.crosshair_dot,
			"color": color, "outline": values.outline_width if outlined else 0.0,
			"border": Color(border, border.a * color.a)})
	return result


static func draw_crosshair(canvas: CanvasItem, center: Vector2, values: Dictionary, zoom: float = 1.0) -> void:
	for item in commands(values):
		if item.kind == "line":
			if item.outline > 0 and item.border.a > 0:
				canvas.draw_line(center + item.a * zoom, center + item.b * zoom,
					item.border, (item.width + item.outline * 2) * zoom)
			canvas.draw_line(center + item.a * zoom, center + item.b * zoom, item.color, item.width * zoom)
		elif item.kind == "square":
			var radius: float = item.radius * zoom
			if item.outline > 0 and item.border.a > 0:
				var edge: float = (item.radius + item.outline) * zoom
				canvas.draw_rect(Rect2(center - Vector2.ONE * edge, Vector2.ONE * edge * 2), item.border)
			canvas.draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), item.color)
		else:
			if item.outline > 0 and item.border.a > 0:
				canvas.draw_circle(center, (item.radius + item.outline) * zoom, item.border)
			canvas.draw_circle(center, item.radius * zoom, item.color)


static func draw_scope(canvas: CanvasItem, area: Rect2, values: Dictionary) -> void:
	var center := area.get_center()
	var radius := minf(area.size.x, area.size.y) * 0.4
	if radius < 1:
		return
	# Scan strips stay inside area, leaving the lens clear without overdraw outside preview tiles.
	var shade := Color(0.015, 0.02, 0.025, values.scope_mask / 100.0)
	var strip := maxf(1, area.size.y / 200.0)
	var y := area.position.y
	while y < area.end.y:
		var h := minf(strip, area.end.y - y)
		var dy := absf(y + h * 0.5 - center.y)
		var half := sqrt(maxf(0, radius * radius - dy * dy)) if dy < radius else 0.0
		canvas.draw_rect(Rect2(area.position.x, y, maxf(0, center.x - half - area.position.x), h), shade)
		canvas.draw_rect(Rect2(center.x + half, y, maxf(0, area.end.x - center.x - half), h), shade)
		y += strip
	canvas.draw_arc(center, radius + 2, 0, TAU, 128, Color("#172227"), 7, true)
	canvas.draw_arc(center, radius - 2, 0, TAU, 128, Color("#82968f"), 1, true)
	var color: Color = values.scope_color
	color.a = values.scope_opacity / 100.0
	var border := Color(0.08, 0.13, 0.15, values.scope_outline_opacity / 100.0 * color.a)
	var outline: float = values.scope_outline_width if values.scope_outline else 0.0
	if values.scope_lines and color.a > 0:
		var end_length: float = radius * values.scope_length / 100.0
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			if end_length > values.scope_gap:
				_scope_line(canvas, center + direction * values.scope_gap, center + direction * end_length,
					color, border, values.scope_width, outline)
			if values.scope_ticks:
				for index in [1, 2, 3]:
					var distance: float = radius * 0.17 * index
					if distance <= values.scope_gap or distance >= end_length:
						continue
					var at: Vector2 = center + direction * distance
					var cross: Vector2 = direction.orthogonal() * 4
					_scope_line(canvas, at - cross, at + cross, color, border, values.scope_width, outline)
	if values.scope_dot > 0 and values.scope_dot_opacity > 0:
		color.a = values.scope_dot_opacity / 100.0
		border.a = values.scope_outline_opacity / 100.0 * color.a
		if outline > 0 and border.a > 0:
			canvas.draw_circle(center, values.scope_dot + outline, border)
		canvas.draw_circle(center, values.scope_dot, color)


static func _scope_line(canvas: CanvasItem, a: Vector2, b: Vector2, color: Color, border: Color,
	width: float, outline: float) -> void:
	if outline > 0 and border.a > 0:
		canvas.draw_line(a, b, border, width + outline * 2, true)
	canvas.draw_line(a, b, color, width, true)
