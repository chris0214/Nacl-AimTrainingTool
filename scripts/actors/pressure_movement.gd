extends RefCounted

var random := RandomNumberGenerator.new()
var phase := "close"
var remaining := 0.0
var goal := 8.0
var near_time := 0.0
var escaping := false
var episodes := 0
var same_phase := 0
var radial_weight := 0.85


func reset(seed_value: int) -> void:
	if seed_value < 0:
		random.randomize()
	else:
		random.seed = seed_value + 690719
	clear()
	episodes = 0


func clear() -> void:
	phase = "close"
	remaining = 0
	near_time = 0
	escaping = false
	same_phase = 0


func band(settings: Resource) -> Vector2:
	return Vector2(clampf(settings.engagement_distance - settings.distance_variation * 0.8, 4.0, 11.0),
		clampf(settings.engagement_distance + settings.distance_variation * 0.25, 7.0, 18.0))


func choose(distance: float, settings: Resource) -> void:
	var limits := band(settings)
	var previous := phase
	var aggression: float = settings.aggression / 100.0
	if escaping:
		phase = "retreat"
	elif distance > limits.y:
		phase = "close"
	elif distance < limits.x:
		phase = "orbit" if phase == "close" else "retreat"
	elif episodes == 0:
		phase = "close"
	else:
		var roll := random.randf()
		var orbit_weight: float = lerpf(0.15, 0.5, settings.orbit_chance / 100.0)
		var close_weight := (1.0 - orbit_weight) * lerpf(0.35, 0.8, aggression)
		phase = "orbit" if roll < orbit_weight else ("close" if roll < orbit_weight + close_weight else "retreat")
		# Progress matters: do not keep renewing the same radial intent indefinitely.
		if phase == previous and same_phase >= 1:
			phase = "orbit" if previous != "orbit" else ("close" if distance > (limits.x + limits.y) * 0.5 else "retreat")
	same_phase = same_phase + 1 if phase == previous else 0
	radial_weight = random.randf_range(0.75, 1.2)
	if phase == "close":
		goal = random.randf_range(limits.x, lerpf(limits.x, limits.y, 0.25))
		remaining = random.randf_range(1.3, 2.5)
	elif phase == "retreat":
		goal = random.randf_range(lerpf(limits.x, limits.y, 0.6), limits.y)
		remaining = random.randf_range(0.7, 1.5)
	else:
		goal = distance
		remaining = random.randf_range(0.6, 1.5)
	episodes += 1


func step(distance: float, settings: Resource, delta: float) -> Dictionary:
	near_time = near_time + delta if distance < 3.5 else maxf(0, near_time - delta * 2)
	if distance < 2.6 or near_time > 0.8:
		escaping = true
	elif distance >= 4.8:
		if escaping:
			remaining = 0
		escaping = false
	remaining -= delta
	var reached := (phase == "close" and distance <= goal) or (phase == "retreat" and distance >= goal)
	if remaining <= 0 or reached:
		choose(distance, settings)
	if escaping:
		return {"closing": -1.0, "side": 0.8, "goal": 5.0, "phase": "retreat", "escaping": true}
	var closing := 0.0
	if phase == "close":
		closing = radial_weight if distance > goal else 0.0
	elif phase == "retreat":
		closing = -radial_weight if distance < goal else 0.0
	# Orbit follows the player's local tangent without correcting back to one radius.
	if distance > minf(20.0, band(settings).y + 2.0):
		closing = 1.0
	# Keep lateral movement visibly dominant in the default pressure profile.
	return {"closing": closing, "side": 1.15, "goal": goal, "phase": phase, "escaping": false}
