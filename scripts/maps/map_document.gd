extends RefCounted

const VERSION := 1
const MAX_OBJECTS := 256
const MAX_BYTES := 1048576
const COLORS := ["#cbd0d2", "#51585b", "#e5e7e6", "#619b99", "#b2a376"]
const KINDS := ["box", "stairs", "ramp", "barrier"]
const MAX_RISE := 0.25
const MIN_TREAD := 0.4
var data: Dictionary = template()
var path := ""
var selected := -1
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var saved_text := ""


static func template() -> Dictionary:
	return {"version": VERSION, "name": "Untitled", "objects": [],
		"infinite_ground": true,
		"player_spawn": [0.0, 0.02, 7.0], "player_yaw": 0.0,
		"bot_spawn": [0.0, 0.02, -4.0], "bot_yaw": 180.0,
		"bounds": [-32.0, -32.0, 32.0, 32.0], "kill_y": -12.0}


static func enclosed_template() -> Dictionary:
	var result := {"version": VERSION, "name": "Untitled", "objects": [
		object_data(1, "box", Vector3(0, -1, 0), Vector3(36, 1, 32)),
		object_data(2, "box", Vector3(0, 0, -16), Vector3(36, 5, 0.6)),
		object_data(3, "box", Vector3(0, 0, 16), Vector3(36, 5, 0.6)),
		object_data(4, "box", Vector3(-18, 0, 0), Vector3(0.6, 5, 32)),
		object_data(5, "box", Vector3(18, 0, 0), Vector3(0.6, 5, 32))],
		"player_spawn": [0.0, 0.02, 7.0], "player_yaw": 0.0,
		"bot_spawn": [0.0, 0.02, -4.0], "bot_yaw": 180.0,
		"bounds": [-17.0, -15.0, 17.0, 15.0], "kill_y": -12.0}
	result.objects[0].color = 1
	return result


static func object_data(id: int, kind: String, at: Vector3, size: Vector3) -> Dictionary:
	return {"id": id, "kind": kind, "position": array3(at), "size": array3(size),
		"yaw": 0.0, "steps": 8, "color": 0}


static func fit_stairs(item: Dictionary) -> void:
	if item.kind != "stairs" or not item.get("auto_steps", false):
		return
	# A smaller rise alone does not make a steep staircase traversable.
	item.size[1] = clampf(item.size[1], 0.1, 16.0)
	item.steps = maxi(1, int(ceil(float(item.size[1]) / MAX_RISE)))
	item.size[2] = maxf(float(item.size[2]), item.steps * MIN_TREAD)


static func array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func vector3(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func is_builtin(file_path: String) -> bool:
	return ProjectSettings.localize_path(file_path).replace("\\", "/").to_lower().begins_with("res://resources/maps/")


static func number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high


static func numeric_array(value: Variant, count: int, low: float, high: float) -> bool:
	if not value is Array or value.size() != count:
		return false
	for item in value:
		if not number(item, low, high):
			return false
	return true


static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "Map must be a JSON object."
	var keys := ["version", "name", "objects", "player_spawn", "player_yaw", "bot_spawn",
		"bot_yaw", "bounds", "kill_y"]
	for key in keys:
		if not value.has(key):
			return "Missing field: " + key
	for key in value:
		if not key in keys and key != "infinite_ground":
			return "Unsupported field: " + str(key)
	if value.has("infinite_ground") and not value.infinite_ground is bool:
		return "Infinite ground must be a boolean."
	if not number(value.version, VERSION, VERSION):
		return "Unsupported map version."
	if not value.name is String or value.name.strip_edges().is_empty() or value.name.length() > 64:
		return "Map name must contain 1-64 characters."
	if not value.objects is Array or value.objects.size() > MAX_OBJECTS:
		return "Map supports up to 256 objects."
	if value.objects.is_empty() and not value.get("infinite_ground", false):
		return "An empty map requires infinite ground."
	var ids := {}
	var parts := 0
	for item in value.objects:
		if not item is Dictionary:
			return "Invalid object."
		for key in ["id", "kind", "position", "size", "yaw", "steps", "color"]:
			if not item.has(key):
				return "Incomplete object: " + key
		for key in item:
			if not key in ["id", "kind", "position", "size", "yaw", "steps", "color", "auto_steps"]:
				return "Unsupported object field: " + str(key)
		if item.has("auto_steps") and not item.auto_steps is bool:
			return "Automatic stairs must be a boolean."
		if not number(item.id, 1, 1000000) or item.id != int(item.id) or ids.has(int(item.id)):
			return "Object IDs must be unique integers."
		ids[int(item.id)] = true
		if not item.kind in KINDS:
			return "Unsupported object type."
		if not numeric_array(item.position, 3, -128, 128) or not numeric_array(item.size, 3, 0.1, 64):
			return "Object coordinates or dimensions exceed limits."
		if item.position[1] < -16 or item.position[1] + item.size[1] > 48:
			return "Geometry must stay between Y=-16 and Y=48."
		if not number(item.yaw, -360, 360) or not number(item.steps, 1, 64) or item.steps != int(item.steps):
			return "Invalid rotation or step count."
		if item.kind == "stairs" and item.get("auto_steps", false):
			var fitted: Dictionary = item.duplicate(true)
			fit_stairs(fitted)
			if fitted.steps != item.steps or not vector3(fitted.size).is_equal_approx(vector3(item.size)):
				return "Automatic stairs require rise <= 0.25 m and tread >= 0.4 m."
		if not number(item.color, 0, COLORS.size() - 1) or item.color != int(item.color):
			return "Invalid material."
		parts += int(item.steps) if item.kind == "stairs" else 1
	if parts > 1024:
		return "Map exceeds 1024 collision parts."
	if not numeric_array(value.bounds, 4, -128, 128):
		return "Invalid training bounds."
	if value.bounds[2] - value.bounds[0] < 4 or value.bounds[3] - value.bounds[1] < 4 \
		or value.bounds[2] - value.bounds[0] > 128 or value.bounds[3] - value.bounds[1] > 128:
		return "Training bounds must span 4-128 metres."
	for key in ["player_spawn", "bot_spawn"]:
		if not numeric_array(value[key], 3, -128, 128):
			return "Invalid spawn coordinates."
		var p := vector3(value[key])
		if p.y < -15 or p.y > 46:
			return "Spawn height must stay between Y=-15 and Y=46."
		if p.x < value.bounds[0] or p.x > value.bounds[2] or p.z < value.bounds[1] or p.z > value.bounds[3]:
			return "Spawn must be inside training bounds."
	if vector3(value.player_spawn).distance_to(vector3(value.bot_spawn)) < 2.0:
		return "Spawns must be at least 2 metres apart."
	if not number(value.player_yaw, -360, 360) or not number(value.bot_yaw, -360, 360) \
		or not number(value.kill_y, -128, 0):
		return "Invalid spawn rotation or fall reset height."
	if value.kill_y >= minf(value.player_spawn[1], value.bot_spawn[1]) - 2.0:
		return "Fall reset height must be below both spawns."
	return ""


static func read_map(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open map (%d)." % FileAccess.get_open_error()}
	if file.get_length() > MAX_BYTES:
		return {"error": "Map file exceeds 1 MB."}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"error": "Invalid JSON at line %d." % parser.get_error_line()}
	var error := validate(parser.data)
	return {"data": parser.data} if error.is_empty() else {"error": error}


static func write_map(file_path: String, value: Dictionary) -> String:
	var error := validate(value)
	if not error.is_empty():
		return error
	# Stage in the same directory. Never discard a valid map if the write fails.
	var temporary := file_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write map (%d)." % FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return "Map write failed (%d)." % write_error
	var moved := DirAccess.rename_absolute(temporary, file_path)
	return "" if moved == OK else "Cannot replace destination (%d)." % moved


func changed() -> bool:
	return JSON.stringify(data) != saved_text


func mark_saved() -> void:
	saved_text = JSON.stringify(data)


func checkpoint() -> void:
	undo_stack.append({"data": data.duplicate(true), "selected": selected})
	if undo_stack.size() > 64:
		undo_stack.pop_front()
	redo_stack.clear()


func undo() -> bool:
	return _restore(undo_stack, redo_stack)


func redo() -> bool:
	return _restore(redo_stack, undo_stack)


func _restore(source: Array[Dictionary], destination: Array[Dictionary]) -> bool:
	if source.is_empty():
		return false
	destination.append({"data": data.duplicate(true), "selected": selected})
	var state: Dictionary = source.pop_back()
	data = state.data
	selected = state.selected
	return true


func object_by_id(id: int) -> Dictionary:
	for item in data.objects:
		if int(item.id) == id:
			return item
	return {}


func next_id() -> int:
	var id := 0
	for item in data.objects:
		id = maxi(id, int(item.id))
	return id + 1
