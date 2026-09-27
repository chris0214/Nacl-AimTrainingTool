class_name PlayerInput
extends RefCounted

var sensitivity: float = 0.022
const DEFAULT_BINDINGS := {
	"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
	"jump": KEY_SPACE, "fire": -MOUSE_BUTTON_LEFT, "restart": KEY_R,
	"scope": -MOUSE_BUTTON_RIGHT
}
var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var invert_y := false
var yaw: float = 0.0
var pitch: float = 0.0
var preview_yaw: float = 0.0
var preview_pitch: float = 0.0
var sequence: int = 0
var queue: Array[Dictionary] = []
var held: Dictionary = {}
var firing: bool = false
var scope_enabled := false
var scope_zoom := 2.0
var scope_sensitivity := 100.0
var preview_scoped := false
var scope_mode := 0
var preview_scope_down := false
var scoped := false


func ingest(event: InputEvent, received_usec: int) -> void:
	var item: Dictionary = {"time": received_usec, "sequence": sequence}
	if event is InputEventMouseMotion:
		# GDScript floats accumulate in double precision; Vector2 intermediates do not.
		# Scale at event arrival, after preceding scope edges, not once per render/physics frame.
		var gain := sensitivity * scope_gain() if scope_enabled and preview_scoped else sensitivity
		item["look_x"] = float(event.screen_relative.x) * deg_to_rad(gain)
		item["look_y"] = float(event.screen_relative.y) * deg_to_rad(gain) * (-1.0 if invert_y else 1.0)
		preview_yaw -= item.look_x
		preview_pitch = clampf(preview_pitch - item.look_y, -1.50, 1.50)
	elif event is InputEventKey:
		if event.echo:
			return
		item["key"] = event.physical_keycode
		item["pressed"] = event.pressed
	elif event is InputEventMouseButton:
		item["key"] = -event.button_index
		item["pressed"] = event.pressed
	else:
		return
	if item.has("key") and item.key == bindings.scope:
		var rising: bool = item.pressed and not preview_scope_down
		preview_scope_down = item.pressed
		if not scope_enabled:
			preview_scoped = false
		elif scope_mode == 0:
			preview_scoped = item.pressed
		elif rising:
			preview_scoped = not preview_scoped
		item["scope_state"] = preview_scoped
	sequence += 1
	queue.append(item)


func consume(deadline_usec: int) -> Dictionary:
	var before := Vector2(yaw, pitch)
	var jump := false
	var fire_pressed := false
	var scope_pressed := false
	var consumed := 0
	for item in queue:
		if item.time > deadline_usec:
			break
		if item.has("look_x"):
			yaw -= item.look_x
			pitch = clampf(pitch - item.look_y, -1.50, 1.50)
		if item.has("scope_state"):
			scoped = scope_enabled and item.scope_state
		if item.has("key"):
			if item.key == bindings.scope and scope_enabled and item.pressed and not held.get(bindings.scope, false):
				scope_pressed = true
			if item.key == bindings.jump and item.pressed and not held.get(bindings.jump, false):
				jump = true
			if item.key == bindings.fire:
				fire_pressed = fire_pressed or (item.pressed and not firing)
				firing = item.pressed
			held[item.key] = item.pressed
		if item.has("fire"):
			fire_pressed = fire_pressed or (item.fire and not firing)
			firing = item.fire
		consumed += 1
	if consumed:
		queue = queue.slice(consumed)
	var move := Vector2(
		float(held.get(bindings.right, false)) - float(held.get(bindings.left, false)),
		float(held.get(bindings.back, false)) - float(held.get(bindings.forward, false))
	).limit_length()
	return {"move": move, "jump": jump, "fire": firing, "fire_pressed": fire_pressed,
		"scope": scope_enabled and scoped, "scope_pressed": scope_pressed,
		"look": Vector2(yaw, pitch) - before}


func clear(reset_view: bool = false) -> void:
	queue.clear()
	held.clear()
	firing = false
	preview_scoped = false
	preview_scope_down = false
	scoped = false
	if reset_view:
		yaw = 0.0
		pitch = 0.0
	preview_yaw = yaw
	preview_pitch = pitch


func correct_view(next_yaw: float, next_pitch: float) -> void:
	yaw = next_yaw
	pitch = clampf(next_pitch, -1.50, 1.50)
	# Rebuild the render preview without consuming or dropping queued sensor counts.
	preview_yaw = yaw
	preview_pitch = pitch
	for item in queue:
		if item.has("look_x"):
			preview_yaw -= item.look_x
			preview_pitch = clampf(preview_pitch - item.look_y, -1.50, 1.50)


static func horizontal_fov(vertical_degrees: float, aspect: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical_degrees) * 0.5) * aspect))


static func sensitivity_from_cm(dpi: float, cm360: float) -> float:
	if not is_finite(dpi) or not is_finite(cm360) or dpi <= 0.0 or cm360 <= 0.0:
		return 0.022
	return 914.4 / (dpi * cm360)


func configure_scope(enabled: bool, zoom: float, percent: float, mode: int = 0) -> void:
	if enabled != scope_enabled or mode != scope_mode:
		# A settings/mode change starts from released input; queued edges cannot
		# reopen the scope under a different interpretation.
		clear()
	scope_mode = mode
	scope_enabled = enabled
	scope_zoom = zoom
	scope_sensitivity = percent
	if not enabled:
		preview_scoped = false


func scope_gain() -> float:
	return scope_sensitivity / (100.0 * scope_zoom)


static func scoped_fov(base_vertical: float, zoom: float) -> float:
	# True projection magnification, not base_fov / zoom.
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_vertical) * 0.5) / zoom))


static func valid_binding(code: int) -> bool:
	return (code > 0 and code < (1 << 23) and code != KEY_ESCAPE) or code in [-1, -2, -3, -8, -9]


func bind_action(action: String, code: int) -> bool:
	if not bindings.has(action) or not valid_binding(code):
		return false
	for other in bindings:
		if other != action and bindings[other] == code:
			bindings[other] = bindings[action]
	bindings[action] = code
	clear()
	return true


func is_restart(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode == bindings.restart
	if event is InputEventMouseButton:
		return event.pressed and -event.button_index == bindings.restart
	return false
