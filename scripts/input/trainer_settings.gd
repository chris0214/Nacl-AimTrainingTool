extends RefCounted

const BOT = preload("res://scripts/actors/bot_settings.gd")
const FOOTWORK = preload("res://scripts/actors/footwork_pattern.gd")
const FORMAT_VERSION := 2
const RETICLE = preload("res://scripts/ui/reticle_style.gd")
const VISUAL_KEYS = RETICLE.KEYS
const DEFAULTS := {
	"dpi": 800.0, "cm360": 51.954545, "invert_y": false,
	"fov": 75.0, "fps": 240, "vsync": false, "fullscreen": false,
	"resolution": Vector2i(1440, 900), "attack": true, "advanced": false,
	"roaming": true, "fov_mode": 0, "reactive_bot": true,
	"bot_perception": true, "bot_adaptation": true, "bot_motion_aim": true,
	"instant_movement": false, "base_speed": 10.0, "assist_mode": 0,
	"health_pool": 1000, "movement_preset": 0, "input_mode": 0,
	"roam_style": 1,
	"bot_model": 1, "bot_animation": true,
	"simulation_hz": 120, "ad_bonus_weight": 10.0,
	"weapon_mode": 0, "score_limit": 25, "sniper_cooldown": 0.9, "sniper_volume": 45.0,
	"bot_sniper_cooldown": 0.75, "scope_zoom": 2.0, "scope_sensitivity": 100.0,
	"scope_mode": 0,
	"crosshair_color": Color("#f6fff8"), "crosshair_width": 2.0, "crosshair_dot": 1.5,
	"scope_color": Color("#91eee0"), "scope_width": 1.0, "scope_dot": 1.2,
	"scope_mask": 94.0, "player_tracer": true, "bot_tracer": true,
	"combat_mode": 0, "armor_pool": 300, "armor_sound": true, "armor_volume": 55.0,
	"armor_effect": true, "armor_effect_strength": 50.0,
	"prediction_horizon": 150.0, "prediction_strength": 50.0, "round_review": true,
	"assist_speed": 720.0, "assist_response": 12.0,
	"hit_sound": true, "hit_volume": 45.0, "hit_sound_style": 0,
	"sky_style": 0, "arena_style": 0, "floor_grid": true, "scene_brightness": 100.0
}
const RESOLUTIONS := [
	Vector2i(960, 600), Vector2i(1280, 720), Vector2i(1440, 900),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]
var values := DEFAULTS.duplicate()
var bindings := PlayerInput.DEFAULT_BINDINGS.duplicate()
var path := "user://trainer-settings.cfg"
var writable := true
var legacy_bytes := PackedByteArray()
var future_format := false


func _init() -> void:
	values.merge(RETICLE.DEFAULTS)
	for key in BOT.DEFAULTS:
		values[key] = BOT.DEFAULTS[key]
	values.merge(FOOTWORK.DEFAULTS)


func put(key: String, value: Variant) -> void:
	if not values.has(key):
		return
	if key in RETICLE.FLAGS:
		if value is bool:
			values[key] = value
		return
	if key in RETICLE.COLORS:
		if value is Color and is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a):
			values[key] = Color(clampf(value.r, 0, 1), clampf(value.g, 0, 1), clampf(value.b, 0, 1), 1)
		return
	if RETICLE.RANGES.has(key):
		if (value is int or value is float) and is_finite(float(value)):
			var range: Vector3 = RETICLE.RANGES[key]
			values[key] = roundf(snappedf(clampf(value, range.x, range.y), range.z) * 1000.0) / 1000.0
		return
	if key in ["invert_y", "vsync", "fullscreen", "attack", "advanced", "roaming", "reactive_bot", "instant_movement", "hit_sound", "floor_grid",
		"bot_perception", "bot_adaptation", "bot_motion_aim", "round_review", "armor_sound", "armor_effect", "bot_animation"]:
		if value is bool:
			values[key] = value
	elif key == "resolution":
		if value in RESOLUTIONS:
			values[key] = value
	elif (value is int or value is float) and is_finite(float(value)):
		var limits: Vector2 = BOT.LIMITS.get(key, Vector2.ZERO)
		if FOOTWORK.LIMITS.has(key):
			limits = FOOTWORK.LIMITS[key]
			if key in ["step_mode", "repeat_gap"]:
				if value == int(value):
					values[key] = clampi(int(value), int(limits.x), int(limits.y))
				return
		if key in ["health_pool", "armor_pool"]:
			if value in [300, 600, 1000]:
				values[key] = int(value)
			return
		if key == "simulation_hz":
			if value in SimulationClock.RATES:
				values[key] = int(value)
			return
		if key == "score_limit":
			if value in [25, 50]:
				values[key] = int(value)
			return
		if key in ["sniper_cooldown", "bot_sniper_cooldown"]:
			values[key] = snappedf(clampf(value, 0.3, 2.5), 0.05)
			return
		if key == "scope_zoom":
			values[key] = snappedf(clampf(value, 1.5, 8.0), 0.5)
			return
		if key == "scope_sensitivity":
			values[key] = snappedf(clampf(value, 10, 300), 1.0)
			return
		if key == "sniper_volume":
			values[key] = clampf(value, 0, 100)
			return
		if key == "ad_bonus_weight":
			values[key] = clampf(value, 0, 20)
			return
		if key in ["combat_mode", "roam_style", "weapon_mode", "scope_mode"]:
			if value in [0, 1]:
				values[key] = int(value)
			return
		if key == "bot_model":
			if value in [0, 1, 2]:
				values[key] = int(value)
			return
		if key in ["armor_volume", "armor_effect_strength"]:
			values[key] = clampf(value, 0, 100)
			return
		if key == "movement_preset" or key == "input_mode":
			var high := 5 if key == "movement_preset" else 3
			if value == int(value) and value >= 0 and value <= high:
				values[key] = int(value)
			return
		if key == "prediction_horizon":
			values[key] = clampf(value, 50, 250)
			return
		if key == "prediction_strength":
			values[key] = clampf(value, 0, 100)
			return
		if key == "dpi":
			values[key] = roundf(clampf(value, 50, 64000))
			return
		elif key == "cm360":
			values[key] = snappedf(clampf(value, 1, 500), 0.000001)
			return
		elif key == "fov":
			values[key] = snappedf(clampf(value, 30, 150), 0.01)
			return
		elif key == "fov_mode":
			if value in [0, 1]:
				values[key] = int(value)
			return
		elif key in ["assist_mode", "hit_sound_style", "sky_style", "arena_style"]:
			if value in [0, 1, 2]:
				values[key] = int(value)
			return
		elif key == "assist_speed":
			values[key] = clampf(value, 30.0, 1440.0)
			return
		elif key == "assist_response":
			values[key] = clampf(value, 2.0, 40.0)
			return
		elif key == "hit_volume":
			values[key] = clampf(value, 0.0, 100.0)
			return
		elif key == "scene_brightness":
			values[key] = clampf(value, 50.0, 150.0)
			return
		elif key == "base_speed":
			values[key] = clampf(value, 2.0, 20.0)
			return
		elif key == "fps":
			values[key] = 0 if value == 0 else roundi(clampf(value, 20, 1000))
			return
		values[key] = clampf(float(value), limits.x, limits.y)


func set_footwork(key: String, value: Variant) -> void:
	put(key, value)
	for low in FOOTWORK.PAIRS:
		var high: String = FOOTWORK.PAIRS[low]
		if values[low] > values[high]:
			if key == low:
				values[high] = values[low]
			else:
				values[low] = values[high]
	values.movement_preset = 5


func apply_movement_preset(index: int) -> void:
	if index < 0 or index >= FOOTWORK.PRESETS.size():
		return
	values.merge(FOOTWORK.preset(index), true)
	values.movement_preset = index


func set_base_speed(value: Variant) -> void:
	var previous: float = values.base_speed
	put("base_speed", value)
	put("move_speed", values.move_speed * values.base_speed / previous)


func vertical_fov() -> float:
	if values.fov_mode == 0:
		return values.fov
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(values.fov) * 0.5) / (16.0 / 9.0)))


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	legacy_bytes.clear()
	var version: Variant = config.get_value("meta", "format_version", 1)
	future_format = version is int and version > FORMAT_VERSION
	if version == 1:
		legacy_bytes = FileAccess.get_file_as_bytes(path)
		if not config.has_section_key("training", "aim_level"):
			put("aim_level", config.get_value("training", "accuracy", BOT.DEFAULTS.aim_level))
	for key in values:
		put(key, config.get_value("training", key, values[key]))
	for low in FOOTWORK.PAIRS:
		var high: String = FOOTWORK.PAIRS[low]
		values[high] = maxf(values[low], values[high])
	if values.movement_preset < FOOTWORK.PRESETS.size():
		var expected: Dictionary = FOOTWORK.preset(values.movement_preset)
		for key in FOOTWORK.DEFAULTS:
			if not is_equal_approx(float(values[key]), float(expected[key])):
				values.movement_preset = 5
				break
	var candidate: Dictionary = {}
	# Preserve explicitly saved keys first. A newly introduced action must not
	# invalidate an old config that already uses its default key for another action.
	for action in bindings:
		if not config.has_section_key("bindings", action):
			continue
		var code: Variant = config.get_value("bindings", action)
		if not code is int or not PlayerInput.valid_binding(code) or code in candidate.values():
			return
		candidate[action] = code
	for action in bindings:
		if candidate.has(action):
			continue
		var choices: Array = [bindings[action]]
		choices.append_array(PlayerInput.DEFAULT_BINDINGS.values())
		choices.append_array([-MOUSE_BUTTON_MIDDLE, KEY_Q, KEY_E, KEY_C, KEY_V])
		for code in choices:
			if code not in candidate.values():
				candidate[action] = code
				break
		if not candidate.has(action):
			return
	bindings = candidate


func save_settings() -> Error:
	if not writable:
		return OK
	if future_format:
		return ERR_UNAVAILABLE
	# Keep the original bytes before the first migrated save; never overwrite the backup.
	if not legacy_bytes.is_empty():
		var backup := path + ".v1-backup"
		if not FileAccess.file_exists(backup):
			var file := FileAccess.open(backup, FileAccess.WRITE)
			if file == null:
				return FileAccess.get_open_error()
			file.store_buffer(legacy_bytes)
			file.flush()
			var error := file.get_error()
			file.close()
			if error != OK:
				return error
		legacy_bytes.clear()
	var config := ConfigFile.new()
	config.set_value("meta", "format_version", FORMAT_VERSION)
	for key in values:
		config.set_value("training", key, values[key])
	for action in bindings:
		config.set_value("bindings", action, bindings[action])
	return config.save(path)
