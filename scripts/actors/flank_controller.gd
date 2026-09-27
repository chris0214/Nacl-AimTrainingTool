extends RefCounted

var random := RandomNumberGenerator.new()
var clock := 0.0
var views: Array[Dictionary] = []
var perceived_forward := Vector3.FORWARD
var has_view := false
var active := false
var side := 1.0
var remaining := 0.0
var cooldown := 0.0
var opportunity_time := 0.0
var facing_time := 0.0
var next_check := 0.0
var attempts := 0
var successes := 0
var last_end := ""


func reset(replay_seed: int) -> void:
	if replay_seed < 0:
		random.randomize()
	else:
		random.seed = replay_seed + 521029
	clear()
	clock = 0.0
	cooldown = 0.0
	attempts = 0
	successes = 0
	last_end = ""


func clear() -> void:
	views.clear()
	has_view = false
	active = false
	remaining = 0.0
	opportunity_time = 0.0
	facing_time = 0.0
	next_check = 0.0


func observe(yaw: float, delay_seconds: float) -> void:
	views.append({"at": clock + delay_seconds, "forward": Basis(Vector3.UP, yaw) * Vector3.FORWARD})
	# Even paused/misused callers cannot grow the observation buffer without bound.
	if views.size() > 256:
		views.pop_front()


func finish(reason: String) -> void:
	if not active:
		return
	active = false
	remaining = 0.0
	cooldown = random.randf_range(3.5, 6.0)
	opportunity_time = 0.0
	facing_time = 0.0
	last_end = reason
	if reason == "behind":
		successes += 1


func step(radial: Vector3, distance: float, settings: Resource, spacing_out: bool, delta: float) -> void:
	clock += delta
	cooldown = maxf(0.0, cooldown - delta)
	next_check -= delta
	while not views.is_empty() and views[0].at <= clock:
		perceived_forward = views.pop_front().forward
		has_view = true
	if not has_view:
		return
	var alignment := perceived_forward.dot(-radial)
	if active:
		remaining -= delta
		facing_time = facing_time + delta if alignment > 0.88 else 0.0
		if settings.flank_chance <= 0.0 or settings.move_speed <= 0.0 or spacing_out:
			finish("spacing")
		elif alignment < -0.55:
			finish("behind")
		elif facing_time > 0.2:
			finish("faced")
		elif remaining <= 0.0:
			finish("timeout")
		return
	var opportunity := alignment < 0.65 and alignment > -0.55 and not spacing_out \
		and distance < minf(16.0, settings.engagement_distance + 3.0)
	opportunity_time = opportunity_time + delta if opportunity else 0.0
	if cooldown > 0.0 or opportunity_time < 0.15 or next_check > 0.0 \
		or settings.move_speed <= 0.0 or settings.flank_chance <= 0.0:
		return
	next_check = random.randf_range(0.4, 0.7)
	if random.randf() >= settings.flank_chance / 100.0:
		return
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	side = 1.0 if tangent.dot(-perceived_forward) >= 0.0 else -1.0
	active = true
	remaining = 3.0
	facing_time = 0.0
	attempts += 1
