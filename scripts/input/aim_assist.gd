extends RefCounted


static func step(input: PlayerInput, origin: Vector3, point: Vector3, delta: float,
	mode: int, speed_degrees: float, response: float) -> void:
	if mode == 0 or delta <= 0.0:
		return
	var direction := point - origin
	if direction.length_squared() < 0.000001:
		return
	var goal_yaw := atan2(-direction.x, -direction.z)
	var goal_pitch := clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), -1.5, 1.5)
	var yaw_error := wrapf(goal_yaw - input.yaw, -PI, PI)
	var pitch_error := goal_pitch - input.pitch
	var error_length := sqrt(yaw_error * yaw_error + pitch_error * pitch_error)
	if error_length < 0.000001:
		return
	# Linear uses a constant combined yaw/pitch rate; smooth decays exponentially.
	var fraction := 1.0 - exp(-response * delta) if mode == 1 else 1.0
	fraction = minf(fraction, deg_to_rad(speed_degrees) * delta / error_length)
	input.correct_view(input.yaw + yaw_error * fraction, input.pitch + pitch_error * fraction)
