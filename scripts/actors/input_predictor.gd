extends RefCounted

var transitions := [[1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.0, 1.0]]
var durations: Array[float] = []
var direction := 0
var since := 0.0
var observed_at := -1.0
var move := Vector3.ZERO
var velocity := Vector3.ZERO
var acceleration := Vector3.ZERO
var basis_right := Vector3.RIGHT
var speed_limit := 10.0
var transition_count := 0
var confidence := 0.0
var firing := false


func clear() -> void:
	transitions = [[1.0, 1.0, 1.0], [1.0, 1.0, 1.0], [1.0, 1.0, 1.0]]
	durations.clear()
	direction = 0
	since = 0
	observed_at = -1
	move = Vector3.ZERO
	velocity = Vector3.ZERO
	acceleration = Vector3.ZERO
	transition_count = 0
	confidence = 0
	firing = false


func observe(sample: Dictionary) -> void:
	var next := int(signf(sample.local_move.x))
	var at: float = sample.sample_at
	if observed_at >= 0:
		acceleration = ((sample.velocity - velocity) / maxf(0.000001, at - observed_at)).limit_length(60)
		if next != direction:
			transitions[direction + 1][next + 1] += 1.0
			transition_count += 1
			if direction != 0:
				durations.append(clampf(at - since, 0.05, 3))
				if durations.size() > 32:
					durations.pop_front()
			since = at
	else:
		since = at
	direction = next
	move = sample.move
	velocity = sample.velocity
	basis_right = Basis(Vector3.UP, sample.yaw) * Vector3.RIGHT
	speed_limit = sample.speed_limit
	observed_at = at
	firing = sample.fire


func expected_velocity(now: float, horizon: float, probabilistic: bool) -> Vector3:
	confidence = 0.0
	if observed_at < 0 or now - observed_at > 1.0:
		return velocity
	if not probabilistic:
		confidence = 0.5
		return (velocity + acceleration * minf(horizon, 0.25)).limit_length(speed_limit)
	if durations.size() < 4 or direction == 0:
		return velocity
	var survivors := 0
	var endings := 0
	var age := maxf(0, now - since)
	for duration in durations:
		if duration >= age:
			survivors += 1
			endings += int(duration <= age + horizon)
	if survivors < 3:
		return velocity
	var probability := float(endings) / survivors
	var row: Array = transitions[direction + 1]
	var total: float = row[0] + row[1] + row[2]
	var next_direction: float = (row[2] - row[0]) / total
	confidence = minf(1, float(transition_count) / 12.0)
	var expected := lerpf(float(direction), next_direction, probability * confidence)
	var result := velocity - basis_right * velocity.dot(basis_right)
	result += basis_right * expected * speed_limit
	return result.limit_length(speed_limit)
