extends RefCounted

var angles := Vector2.ZERO
var angular_velocity := Vector2.ZERO
var initialized := false


func clear() -> void:
	initialized = false
	angular_velocity = Vector2.ZERO


static func view_angles(direction: Vector3) -> Vector2:
	return Vector2(atan2(-direction.x, -direction.z), asin(clampf(direction.y, -1.0, 1.0)))


func step(current: Vector3, desired: Vector3, level: float, limit_degrees: float, delta: float) -> Vector3:
	if level >= 100:
		clear()
		return desired
	if not initialized:
		angles = view_angles(current.normalized())
		initialized = true
	var target := view_angles(desired.normalized())
	var error := Vector2(wrapf(target.x - angles.x, -PI, PI), target.y - angles.y)
	var fraction := clampf(level / 100.0, 0.0, 1.0)
	var max_speed := deg_to_rad(limit_degrees) * lerpf(0.35, 1.0, fraction)
	var acceleration := max_speed * lerpf(12.0, 40.0, fraction)
	var desired_velocity := (error / maxf(delta, 0.000001)).limit_length(max_speed)
	angular_velocity = angular_velocity.move_toward(desired_velocity, acceleration * delta)
	angular_velocity = angular_velocity.limit_length(max_speed)
	angles += angular_velocity * delta
	angles.x = wrapf(angles.x, -PI, PI)
	# Pitch stops at the neck limit; yaw and pitch otherwise share one speed budget.
	angles.y = clampf(angles.y, -PI * 0.49, PI * 0.49)
	return Vector3(-sin(angles.x) * cos(angles.y), sin(angles.y), -cos(angles.x) * cos(angles.y)).normalized()
