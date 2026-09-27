extends RefCounted

const LEVELS := [0.0, 20.0, 40.0, 60.0, 80.0, 95.0, 100.0]
const DELAYS := [340.0, 280.0, 220.0, 160.0, 90.0, 25.0, 0.0]
var tracked_point := Vector3.ZERO
var initialized := false
var observation_clock := 0.0
var observations: Array[Dictionary] = []
var previous_point := Vector3.ZERO
var perceived_point := Vector3.ZERO
var perceived_velocity := Vector3.ZERO
var perceived_at := 0.0
var observing := false
var bias_from := Vector2.ZERO
var bias_to := Vector2.ZERO
var bias_time := 0.0
var bias_duration := 0.4
var state := "acquiring"
var visible_observation := true
var sampled_visible := false
var has_target := false
var last_visible_at := 0.0
var stable_time := 0.0
var reversal_age := 10.0
var vertical_acceleration := 0.0
var search_forward := Vector3.BACK
var search_time := 0.0
var instant_read := false
var intent_velocity := Vector3.ZERO
var intent_weight := 0.0


static func delay_for_level(level: float) -> float:
	level = clampf(level, 0.0, 100.0)
	for index in range(1, LEVELS.size()):
		if level <= LEVELS[index]:
			return lerpf(DELAYS[index - 1], DELAYS[index],
				inverse_lerp(LEVELS[index - 1], LEVELS[index], level))
	return 0.0


static func correction_time(level: float) -> float:
	return 0.16 * pow(1.0 - clampf(level / 100.0, 0.0, 1.0), 1.5)


static func error_scale(level: float) -> float:
	return 5.0 * pow(1.0 - clampf(level / 100.0, 0.0, 1.0), 1.25)


func reset(random: RandomNumberGenerator) -> void:
	bias_from = _random_bias(random)
	bias_to = _random_bias(random)
	bias_time = 0.0
	bias_duration = random.randf_range(0.25, 0.65)
	clear_history()


func clear_history() -> void:
	observations.clear()
	observation_clock = 0.0
	perceived_at = 0.0
	perceived_velocity = Vector3.ZERO
	observing = false
	initialized = false
	state = "acquiring"
	visible_observation = true
	sampled_visible = false
	has_target = false
	last_visible_at = 0.0
	stable_time = 0.0
	reversal_age = 10.0
	vertical_acceleration = 0.0
	search_time = 0.0


func _random_bias(random: RandomNumberGenerator) -> Vector2:
	var angle := random.randf_range(-PI, PI)
	return Vector2(cos(angle), sin(angle)) * random.randf_range(0.55, 1.0)


func _bias(delta: float, random: RandomNumberGenerator) -> Vector2:
	bias_time += delta
	while bias_time >= bias_duration:
		bias_time -= bias_duration
		bias_from = bias_to
		bias_to = _random_bias(random)
		bias_duration = random.randf_range(0.25, 0.65)
	var weight := bias_time / bias_duration
	return bias_from.lerp(bias_to, weight * weight * (3.0 - 2.0 * weight))


func _observe(point: Vector3, delta: float, delay_ms: float, visible: bool) -> Vector3:
	if not observing:
		previous_point = point if visible else Vector3.ZERO
		perceived_point = previous_point
		observing = true
	observation_clock += delta
	reversal_age += delta
	var velocity := (point - previous_point) / maxf(delta, 0.000001) if visible and sampled_visible else Vector3.ZERO
	sampled_visible = visible
	if visible:
		previous_point = point
	observations.append({"at": observation_clock, "visible": visible,
		"point": point if visible else Vector3.ZERO, "velocity": velocity})
	var cutoff := observation_clock - delay_ms / 1000.0
	# Reversals become visible only when their samples mature; no second reaction timer.
	while not observations.is_empty() and observations[0].at <= cutoff + 0.0000001:
		var sample: Dictionary = observations.pop_front()
		if not sample.visible:
			visible_observation = false
			state = "searching"
			stable_time = 0.0
			continue
		if not visible_observation:
			state = "acquiring"
			stable_time = 0.0
		var changed: bool = perceived_velocity.dot(sample.velocity) < -0.25 \
			or (perceived_velocity.length() > 1.0 and sample.velocity.length() < 0.2)
		if changed and visible_observation:
			state = "reacquiring"
			reversal_age = 0.0
			stable_time = 0.0
		vertical_acceleration = clampf((sample.velocity.y - perceived_velocity.y)
			/ maxf(sample.at - perceived_at, delta), -24.0, 0.0) if visible_observation and has_target else 0.0
		visible_observation = true
		has_target = true
		last_visible_at = sample.at
		perceived_point = sample.point
		perceived_velocity = sample.velocity
		perceived_at = sample.at
	# Cover the longest supported delay even at 360 Hz.
	if observations.size() > 256:
		observations.pop_front()
	var age := maxf(0.0, observation_clock - perceived_at)
	var estimated := perceived_velocity.lerp(intent_velocity, clampf(intent_weight, 0, 1))
	estimated.y = perceived_velocity.y
	var prediction := estimated * age
	# Confidence only changes when the delayed observation reveals a reversal or stop.
	prediction.x *= lerpf(0.8, 1.0, clampf(reversal_age / 0.12, 0.0, 1.0))
	prediction.z *= lerpf(0.8, 1.0, clampf(reversal_age / 0.12, 0.0, 1.0))
	prediction.y += 0.5 * vertical_acceleration * age * age
	return perceived_point + prediction.limit_length(2.5)


func step(origin: Vector3, point: Vector3, radius: float, level: float,
	delta: float, random: RandomNumberGenerator, visible: bool = true,
	initial_direction: Vector3 = Vector3.BACK, movement_load: float = 0.0) -> Vector3:
	if level >= 100.0:
		clear_history()
		state = "hard_lock"
		tracked_point = point
		return (point - origin).normalized()
	var was_searching := state == "searching"
	var predicted := _observe(point, delta, 0.0 if instant_read else delay_for_level(level), visible)
	if not visible_observation or (not has_target and not visible):
		state = "searching"
		if not was_searching:
			search_forward = initial_direction
			search_time = 0.0
		search_time += delta
		if has_target and observation_clock - last_visible_at < 0.25:
			return (perceived_point - origin).normalized()
		return search_forward.rotated(Vector3.UP, search_time * deg_to_rad(90.0)).normalized()
	search_time = 0.0
	var tau := correction_time(level)
	var alpha := 1.0 - exp(-delta / maxf(tau, 0.000001))
	# Exact discrete steady-velocity compensation, using only the perceived velocity.
	var lag := delta * (1.0 - alpha) / maxf(alpha, 0.000001)
	predicted += (perceived_velocity * lag).limit_length(1.0)
	if not initialized:
		tracked_point = predicted
		initialized = true
	tracked_point = tracked_point.lerp(predicted, alpha)
	if has_target:
		var aligned := tracked_point.distance_to(predicted) < radius * 0.4
		stable_time = stable_time + delta if aligned else 0.0
		if stable_time >= 0.12:
			state = "stable"
		elif state == "acquiring" and aligned:
			state = "tracking"
		elif state == "stable" and not aligned:
			state = "tracking"
	var forward := (tracked_point - origin).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	var noise := _bias(delta, random)
	var bias := noise * radius * error_scale(level)
	bias *= 1.0 + clampf(movement_load, 0.0, 1.0) * (1.0 - level / 100.0) * 0.2
	# Torso selection is small; deliberate tracking error remains a separate offset.
	var target_height := noise.y * 0.12 * (1.0 - level / 100.0)
	var aimed := tracked_point + right * bias.x + up * bias.y + Vector3.UP * target_height
	return (aimed - origin).normalized()
