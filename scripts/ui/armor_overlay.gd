extends Control

var enabled := true
var strength := 0.5
var remaining := 0.0
var shattered := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func configure(values: Dictionary) -> void:
	enabled = values.armor_effect and int(values.combat_mode) == 1
	strength = values.armor_effect_strength / 100.0
	if not enabled or strength == 0:
		clear()


func pulse(broken: bool) -> void:
	if not enabled or strength <= 0:
		return
	shattered = broken
	remaining = 0.42 if broken else 0.10
	queue_redraw()


func advance(delta: float) -> void:
	if remaining > 0:
		remaining = maxf(0, remaining - delta)
		queue_redraw()


func clear() -> void:
	remaining = 0
	queue_redraw()


func _draw() -> void:
	if remaining <= 0 or not enabled:
		return
	var duration := 0.42 if shattered else 0.10
	var fade := remaining / duration * strength
	var tint := Color(0.82, 0.93, 1, fade * 0.85) if shattered else Color(0.28, 0.82, 0.95, fade * 0.55)
	# Peripheral plates and fractures never enter the central 60% aiming region.
	for side in [-1, 1]:
		var edge := 0.0 if side == -1 else size.x
		var inward := -float(side)
		for index in 3:
			var y := size.y * (0.27 + index * 0.20)
			var a := Vector2(edge, y - size.y * 0.08)
			var b := Vector2(edge + inward * size.x * 0.022, y - size.y * 0.05)
			var c := Vector2(edge + inward * size.x * 0.015, y + size.y * 0.06)
			var d := Vector2(edge, y + size.y * 0.09)
			draw_colored_polygon(PackedVector2Array([a, b, c, d]), Color(tint, tint.a * 0.3))
			draw_polyline(PackedVector2Array([a, b, c, d]), tint, 2, true)
			if shattered:
				var fracture := PackedVector2Array([b, b + Vector2(inward * size.x * 0.028, 14),
					b + Vector2(inward * size.x * 0.05, -8), b + Vector2(inward * size.x * 0.075, 26)])
				draw_polyline(fracture, tint, 2, true)
