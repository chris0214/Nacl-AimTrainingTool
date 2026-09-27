extends RefCounted

const STEP_HEIGHT := 0.32


static func move(body: CharacterBody3D, delta: float) -> float:
	var before := body.global_position
	var snap := body.floor_snap_length
	var stepped := false
	var horizontal := Vector3(body.velocity.x, 0, body.velocity.z) * delta
	# Only step from grounded motion. All three legs are swept with the actual capsule.
	if body.is_on_floor() and body.velocity.y <= 0.0 and horizontal.length_squared() > 0.000001:
		var contact := KinematicCollision3D.new()
		if body.test_move(body.global_transform, horizontal, contact, body.safe_margin) \
			and contact.get_normal().y < cos(body.floor_max_angle):
			var raised := body.global_transform
			var up := Vector3.UP * STEP_HEIGHT
			if not body.test_move(raised, up, null, body.safe_margin):
				raised.origin += up
				if not body.test_move(raised, horizontal, null, body.safe_margin):
					raised.origin += horizontal
					var landing := KinematicCollision3D.new()
					if body.test_move(raised, -up, landing, body.safe_margin):
						var ahead := before + horizontal.normalized() * 0.45
						var probe := PhysicsRayQueryParameters3D.create(ahead + up,
							ahead - Vector3.UP * 0.01, 1, [body.get_rid()])
						var surface := body.get_world_3d().direct_space_state.intersect_ray(probe)
						var walkable: bool = not surface.is_empty() and surface.normal.y >= cos(body.floor_max_angle)
						if walkable and surface.position.y - before.y > 0.01 \
							and surface.position.y - before.y <= STEP_HEIGHT:
							body.global_position.y = surface.position.y + body.safe_margin
							body.floor_snap_length = 0
							body.velocity.y = 0
							stepped = true
	body.move_and_slide()
	body.floor_snap_length = snap
	# Camera step easing is for discrete lifts, not continuous motion along a slope.
	return maxf(0, body.global_position.y - before.y) if stepped else 0.0
