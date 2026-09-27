class_name ArenaActor
extends CharacterBody3D

const EYE_HEIGHT: float = 1.64
var profile: MovementProfile
var previous_position: Vector3
var jumps: int = 0
var instant_movement := false
var terrain_enabled := false
var step_camera_offset := 0.0
const TERRAIN_MOTION = preload("res://scripts/maps/terrain_motion.gd")


static func integrate_velocity(
	current: Vector3, wish: Vector3, grounded: bool, jump: bool,
	rules: MovementProfile, delta: float, instant: bool = false
) -> Vector3:
	var flat := Vector3(current.x, 0.0, current.z)
	var before_friction := flat
	var jumping := grounded and jump and rules.advanced
	if grounded and not jumping:
		var speed := flat.length()
		if speed > 0.0:
			var drop := maxf(speed, rules.stop_speed) * rules.friction * delta
			flat *= maxf(speed - drop, 0.0) / speed
	var wish_speed := rules.ground_speed if grounded else rules.air_wish_speed
	var acceleration := rules.ground_acceleration if grounded else rules.air_acceleration
	if wish.length_squared() > 0.0:
		var remaining := wish_speed - flat.dot(wish)
		# Active input replaces forward friction loss; braking and lateral drag remain.
		var drive := acceleration * delta + maxf(0.0, (before_friction - flat).dot(wish))
		flat += wish * minf(maxf(remaining, 0.0), drive)
	flat = flat.limit_length(rules.speed_limit)
	if instant and grounded:
		flat = wish.limit_length() * minf(rules.ground_speed, rules.speed_limit)
	var vertical := current.y
	if jumping:
		vertical = rules.jump_speed
	elif grounded:
		vertical = -0.5
	else:
		vertical -= rules.gravity * delta
	return Vector3(flat.x, vertical, flat.z)


func simulate(move: Vector2, yaw: float, jump: bool, delta: float) -> void:
	previous_position = global_position
	var wish := Basis(Vector3.UP, yaw) * Vector3(move.x, 0.0, move.y)
	wish = wish.limit_length()
	if is_on_floor() and jump and profile.advanced:
		jumps += 1
	velocity = integrate_velocity(velocity, wish, is_on_floor(), jump, profile, delta, instant_movement)
	if terrain_enabled:
		step_camera_offset *= exp(-18.0 * delta)
		var rise := TERRAIN_MOTION.move(self, delta)
		if rise > 0.04:
			step_camera_offset = minf(0.4, step_camera_offset + rise)
	else:
		move_and_slide()


func reset_at(spawn: Vector3) -> void:
	global_position = spawn
	previous_position = spawn
	velocity = Vector3.ZERO
	jumps = 0
	step_camera_offset = 0.0
	reset_physics_interpolation()


func eye_position() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT
