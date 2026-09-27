extends RefCounted

const MOTION = preload("res://scripts/maps/terrain_motion.gd")

var arena: Node3D
var path := PackedVector3Array()
var path_index := 0
var repath_time := 0.0
var blocked_time := 0.0
var previous := Vector3.ZERO
var initialized := false
var routing := false
var route_hold := 0.0
var last_destination := Vector3.INF
var combat_goal := Vector3.INF
var goal_time := 0.0


func clear() -> void:
	path.clear()
	path_index = 0
	repath_time = 0.0
	blocked_time = 0.0
	initialized = false
	routing = false
	route_hold = 0.0
	last_destination = Vector3.INF
	combat_goal = Vector3.INF
	goal_time = 0.0


func combat_destination(body: CharacterBody3D, target: Vector3, fallback: Vector3, delta: float) -> Vector3:
	if arena == null or not arena.navigation_ready:
		return fallback
	goal_time -= delta
	var space := body.get_world_3d().direct_space_state
	var sight := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP,
		target + Vector3.UP, preload("res://scripts/maps/collision_layers.gd").WORLD_RAY, [body.get_rid()])
	if space.intersect_ray(sight).is_empty():
		combat_goal = Vector3.INF
		return fallback
	if goal_time > 0.0 and combat_goal != Vector3.INF:
		return combat_goal
	goal_time = 0.4
	combat_goal = fallback
	var offset := fallback - target
	offset.y = 0.0
	var best_cost := INF
	# Search the engagement ring for a supported firing position, not the player's feet.
	for degrees in [0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180]:
		var candidate := target + offset.rotated(Vector3.UP, deg_to_rad(degrees))
		if not arena.contains_point(candidate):
			continue
		var floor_query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 3,
			candidate - Vector3.UP * 32, 1, [body.get_rid()])
		var floor_hit := space.intersect_ray(floor_query)
		if floor_hit.is_empty() or floor_hit.normal.y < cos(body.floor_max_angle):
			continue
		candidate = floor_hit.position
		sight.from = candidate + Vector3.UP
		if not space.intersect_ray(sight).is_empty():
			continue
		var route: PackedVector3Array = arena.path_between(body.global_position, candidate)
		if route.is_empty() or route[-1].distance_to(candidate) > 1.0:
			continue
		var cost := body.global_position.distance_to(route[0])
		for index in range(1, route.size()):
			cost += route[index - 1].distance_to(route[index])
		if cost < best_cost:
			best_cost = cost
			combat_goal = candidate
	return combat_goal


func steer(body: CharacterBody3D, desired: Vector3, destination: Vector3, delta: float,
	retreat_from: Vector3 = Vector3.INF) -> Vector3:
	if arena == null or not arena.navigation_ready or desired.length_squared() < 0.001:
		return desired
	var at := body.global_position
	if last_destination == Vector3.INF or destination.distance_to(last_destination) > 2.0:
		repath_time = 0.0
		last_destination = destination
	if initialized and at.distance_to(previous) < desired.length() * delta * 0.15:
		blocked_time += delta
	else:
		blocked_time = maxf(0.0, blocked_time - delta * 2.0)
	previous = at
	initialized = true
	repath_time -= delta
	route_hold = maxf(0, route_hold - delta)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, destination + Vector3.UP, 1)
	var obstructed := not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var needs_route := combat_goal != Vector3.INF or obstructed or absf(at.y - destination.y) > 0.6 or blocked_time > 0.5
	if needs_route:
		route_hold = 0.8
	routing = needs_route or route_hold > 0
	var direction := desired.normalized()
	var toward := Vector3.ZERO
	if retreat_from != Vector3.INF:
		toward = retreat_from - at
		toward.y = 0.0
		toward = toward.normalized()
	if routing:
		if repath_time <= 0.0:
			path = arena.path_between(at, destination)
			path_index = 0
			repath_time = 0.4
		while path_index < path.size() and Vector2(path[path_index].x - at.x, path[path_index].z - at.z).length() < 0.3:
			path_index += 1
		if path_index < path.size():
			direction = path[path_index] - at
			direction.y = 0.0
			direction = direction.normalized()
		else:
			direction = desired.normalized()
	# Stairs or a concave obstacle may require a temporary approach to reach a farther endpoint.
	var escape_route := false
	if retreat_from != Vector3.INF and path_index < path.size():
		var end_offset := path[path.size() - 1] - retreat_from
		var at_offset := at - retreat_from
		end_offset.y = 0.0
		at_offset.y = 0.0
		escape_route = end_offset.length() > at_offset.length() + 1.0
	if direction.dot(toward) > 0.05 and not escape_route:
		direction = desired.normalized()
	# Probe the footprint ahead. Do not clamp/teleport the Bot across a wall or a ledge.
	if body.is_on_floor():
		var lookahead := maxf(0.55, desired.length() * 0.16)
		for angle in [0.0, 45.0, -45.0, 90.0, -90.0, 180.0]:
			var candidate := direction.rotated(Vector3.UP, deg_to_rad(angle))
			if (candidate.dot(toward) <= 0.05 or escape_route) and _supported_path(body, candidate, lookahead):
				return candidate * desired.length()
		return Vector3.ZERO
	return direction * desired.length() if direction.dot(toward) <= 0.05 or escape_route else Vector3.ZERO


func _supported_path(body: CharacterBody3D, direction: Vector3, distance: float) -> bool:
	# Follow successive tread heights instead of casting the far ray at the starting elevation.
	var point := body.global_position
	var count := maxi(1, int(ceil(distance / 0.2)))
	var stride := direction * (distance / count)
	var space := body.get_world_3d().direct_space_state
	for index in count:
		point += stride
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * MOTION.STEP_HEIGHT,
			point - Vector3.UP * 0.65, 1, [body.get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < cos(body.floor_max_angle):
			return false
		point.y = hit.position.y + body.safe_margin
	return true
