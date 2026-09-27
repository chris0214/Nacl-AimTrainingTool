extends RefCounted

const ACTIONS := {
	"micro": {"weight": 0.38, "duration": Vector2(0.18, 0.48), "cooldown": 0.0},
	"strafe": {"weight": 0.43, "duration": Vector2(0.55, 1.25), "cooldown": 0.0},
	"burst": {"weight": 0.13, "duration": Vector2(1.3, 2.2), "cooldown": 0.65},
	"feint": {"weight": 0.06, "duration": Vector2(0.3, 0.6), "cooldown": 1.1}
}
var random := RandomNumberGenerator.new()
var clock := 0.0
var available_at: Dictionary = {}
var recent: Array[String] = []
var selected := "strafe"


func reset(seed_value: int) -> void:
	if seed_value < 0:
		random.randomize()
	else:
		random.seed = seed_value + 634219
	clear()


func clear() -> void:
	clock = 0.0
	available_at.clear()
	recent.clear()
	selected = "strafe"


func advance(delta: float) -> void:
	clock += delta


func choose(variety: float, frequent_reversals: float) -> Dictionary:
	if variety <= 0:
		selected = "strafe"
		return {"kind": selected, "duration": 1.0}
	var weights: Dictionary = {}
	var total := 0.0
	for kind in ACTIONS:
		if available_at.get(kind, 0.0) > clock:
			continue
		if recent.size() >= 2 and recent[-1] == kind and recent[-2] == kind:
			continue
		var weight: float = ACTIONS[kind].weight
		for used in recent:
			if used == kind:
				weight *= 0.55
		if kind == "strafe" or kind == "burst":
			weight *= 1.0 + 0.4 * frequent_reversals
		weights[kind] = weight
		total += weight
	var roll := random.randf() * total
	for kind in weights:
		selected = kind
		roll -= weights[kind]
		if roll <= 0:
			break
	var action: Dictionary = ACTIONS[selected]
	available_at[selected] = clock + action.cooldown
	recent.append(selected)
	if recent.size() > 4:
		recent.pop_front()
	return {"kind": selected, "duration": lerpf(1.0,
		random.randf_range(action.duration.x, action.duration.y), variety)}
