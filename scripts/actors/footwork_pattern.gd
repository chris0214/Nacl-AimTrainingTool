extends RefCounted

const DEFAULTS := {
	"step_mode": 0, "step_min": 0.5, "step_max": 3.5,
	"step_time_min": 0.12, "step_time_max": 0.8,
	"pace_floor": 22.0, "pace_min": 0.25, "pace_max": 0.85,
	"micro_weight": 38.0, "strafe_weight": 43.0, "burst_weight": 13.0, "feint_weight": 6.0,
	"repeat_gap": 1, "continue_chance": 20.0,
	"pause_chance": 0.0, "pause_min": 0.10, "pause_max": 0.30
}
const LIMITS := {
	"step_mode": Vector2(0, 2), "step_min": Vector2(0.1, 8), "step_max": Vector2(0.1, 8),
	"step_time_min": Vector2(0.05, 2), "step_time_max": Vector2(0.05, 2),
	"pace_floor": Vector2(10, 100), "pace_min": Vector2(0.05, 3), "pace_max": Vector2(0.05, 3),
	"micro_weight": Vector2(0, 100), "strafe_weight": Vector2(0, 100),
	"burst_weight": Vector2(0, 100), "feint_weight": Vector2(0, 100),
	"repeat_gap": Vector2(0, 3), "continue_chance": Vector2(0, 100),
	"pause_chance": Vector2(0, 100), "pause_min": Vector2(0.05, 1), "pause_max": Vector2(0.05, 1)
}
const PAIRS := {"step_min": "step_max", "step_time_min": "step_time_max",
	"pace_min": "pace_max", "pause_min": "pause_max"}
const LABELS := ["原有游走", "连续长变向", "连续短变向", "连续不规则变向", "非连续变向", "自定义"]
const EXPLANATIONS := [
	"保留原有游走、长短步与独立变速逻辑；高级步法参数不参与。",
	"走较长距离后左右换向，途中不停步，速度保持上限；避墙、距离保护和输入应对可提前打断。",
	"走很短距离就反向，不主动停步；近似连续快速AD。移速越快换向越快；避墙、距离保护和输入应对可打断。",
	"混合短步、普通步、长步与变速假动作；步长、方向延续与变速节奏独立抽样。",
	"按随机时长横移，部分动作前短暂停顿，再起步或反向；有近身威胁时优先后撤。",
	"手动参数组合；保持距离、避墙和输入应对仍可打断动作。"
]
const PRESETS := [
	{},
	{"step_mode": 2, "step_min": 2.5, "step_max": 5.0, "pace_floor": 100.0,
		"micro_weight": 0.0, "strafe_weight": 0.0, "burst_weight": 100.0, "feint_weight": 0.0,
		"repeat_gap": 0, "continue_chance": 0.0},
	{"step_mode": 2, "step_min": 0.3, "step_max": 0.9, "pace_floor": 100.0,
		"micro_weight": 100.0, "strafe_weight": 0.0, "burst_weight": 0.0, "feint_weight": 0.0,
		"repeat_gap": 0, "continue_chance": 0.0},
	{"step_mode": 2, "step_min": 0.3, "step_max": 4.5, "pace_floor": 25.0},
	{"step_mode": 1, "step_time_min": 0.18, "step_time_max": 0.8,
		"pace_floor": 55.0, "pause_chance": 45.0, "pause_min": 0.08, "pause_max": 0.3}
]
var values := DEFAULTS.duplicate()
var random := RandomNumberGenerator.new()
var recent: Array[String] = []
var elapsed := 0.0
var duration := 0.4
var distance_left := 1.0
var pause_left := 0.0
var stalled := 0.0
var started := false


static func preset(index: int) -> Dictionary:
	var result := DEFAULTS.duplicate()
	if index >= 0 and index < PRESETS.size():
		result.merge(PRESETS[index], true)
	return result


func reset(seed_value: int) -> void:
	if seed_value < 0:
		random.randomize()
	else:
		random.seed = seed_value + 827103
	clear()


func clear() -> void:
	recent.clear()
	elapsed = 0
	distance_left = 0
	pause_left = 0
	stalled = 0
	started = false


func advance(delta: float, travelled: float) -> bool:
	if not started:
		return true
	if pause_left > 0:
		pause_left = maxf(0, pause_left - delta)
		return false
	elapsed += delta
	distance_left -= maxf(0, travelled)
	stalled = stalled + delta if travelled < 0.0001 else 0.0
	if int(values.step_mode) == 1:
		return elapsed >= duration
	return distance_left <= 0 or stalled >= 1.0 or elapsed >= 8.0


func choose(force_reverse: bool = false) -> Dictionary:
	var weights := {"micro": values.micro_weight, "strafe": values.strafe_weight,
		"burst": values.burst_weight, "feint": values.feint_weight}
	var eligible: Dictionary = {}
	for kind in weights:
		if weights[kind] > 0 and not kind in recent:
			eligible[kind] = weights[kind]
	if eligible.is_empty():
		for kind in weights:
			if weights[kind] > 0:
				eligible[kind] = weights[kind]
	if eligible.is_empty():
		eligible.strafe = 1.0
	var total := 0.0
	for weight in eligible.values():
		total += float(weight)
	var roll := random.randf() * total
	var kind: String = eligible.keys()[0]
	for option in eligible:
		kind = option
		roll -= float(eligible[option])
		if roll <= 0:
			break
	recent.append(kind)
	while recent.size() > int(values.repeat_gap):
		recent.pop_front()
	var zones := {"micro": Vector2(0, 0.25), "strafe": Vector2(0.25, 0.7),
		"burst": Vector2(0.7, 1), "feint": Vector2(0.15, 0.55)}
	# A single active template uses the full user interval.
	var active := 0
	for weight in weights.values():
		active += int(weight > 0)
	var zone: Vector2 = zones[kind] if active > 1 else Vector2(0, 1)
	var fraction := random.randf_range(zone.x, zone.y)
	duration = lerpf(values.step_time_min, values.step_time_max, fraction)
	distance_left = lerpf(values.step_min, values.step_max, fraction)
	pause_left = 0.0
	if not force_reverse and random.randf() < values.pause_chance / 100.0:
		pause_left = random.randf_range(values.pause_min, values.pause_max)
	elapsed = 0.0
	stalled = 0.0
	started = true
	return {"kind": kind, "reverse": force_reverse or random.randf() >= values.continue_chance / 100.0,
		"duration": duration, "distance": distance_left}


func sample_speed() -> float:
	return random.randf_range(values.pace_floor / 100.0, 1.0)


func sample_pace_time() -> float:
	return random.randf_range(values.pace_min, values.pace_max)
