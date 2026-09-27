extends CharacterBody3D

const MAX_HEALTH: int = preload("res://scripts/combat/duel_rules.gd").MAX_HEALTH
@export var health: int = MAX_HEALTH
var max_health := MAX_HEALTH
var armor := 0
var max_armor := 0
@export var attack_enabled: bool = true
var player: Node3D
var rng := RandomNumberGenerator.new()
var aim_rng := RandomNumberGenerator.new()
var jump_rng := RandomNumberGenerator.new()
var tactic_rng := RandomNumberGenerator.new()
var pace_rng := RandomNumberGenerator.new()
var reaction_rng := RandomNumberGenerator.new()
var pattern := preload("res://scripts/actors/footwork_pattern.gd").new()
var predictor := preload("res://scripts/actors/input_predictor.gd").new()
var input_mode := 0
var prediction_horizon := 0.15
var prediction_strength := 0.5
var next_prediction := 0.0
var next_observation := 0.0
var pattern_position := Vector3.ZERO
var reactive_enabled := true
var reaction_clock := 0.0
var reaction_queue: Array[Dictionary] = []
var observed_move := Vector3.ZERO
var observed_fire := false
var action_kind := "strafe"
var action_pool := preload("res://scripts/actors/bot_action_pool.gd").new()
var memory := preload("res://scripts/actors/bot_tactical_memory.gd").new()
var aim_motor := preload("res://scripts/actors/bot_aim_motor.gd").new()
var perception_enabled := true
var adaptation_enabled := true
var movement_aim_enabled := true
var previous_aim_velocity := Vector3.ZERO
var movement_load := 0.0
var reaction_count := 0
var last_reaction_at := -1.0
var roaming_enabled := true
var pressure_enabled := true
var pressure := preload("res://scripts/actors/pressure_movement.gd").new()
var tactic_time := 0.0
var tactic := "close"
var preferred_distance := 5.0
var orbit_direction := 1.0
var tactic_count := 0
var distance_direction := 1.0
var distance_runs := 0
var lateral_runs := 0
var pace_time := 0.0
var roam_speed_factor := 1.0
var lateral_factor := 1.0
var angular_run := 0.0
var angular_sign := 0.0
var angular_limit := PI * 0.65
var same_side_time := 0.0
var jump_time := 0.6
var jumps := 0
var speed_factor := 1.0
var airborne := false
var settings := preload("res://scripts/actors/bot_settings.gd").new()
var lane_center := Vector3.ZERO
var lane_axis := Vector3.RIGHT
var lane_initialized := false
var aim_model := preload("res://scripts/actors/bot_aim.gd").new()
var flank := preload("res://scripts/actors/flank_controller.gd").new()
var spacing_out := false
var previous_distance := -1.0
var approach_rate := 0.0
var upper_pose: Dictionary = {}
var locomotion := "right"
var turn_count := 0
var action_time: float = 0.0
var action_duration: float = 0.7
var strafe_direction: float = 1.0
var action_name: String = "准备"
var look_yaw: float = 0.0
var fire: bool = false
var dead: bool = false
var status_label: Label3D
const MODELS = preload("res://scripts/combat/training_models.gd")
var visual: Node3D
var muzzle: Marker3D
var weapon_pivot: Node3D
var rifle_visual: Node3D
var sniper_visual: Node3D
var single_shot := false
var weapon_range := LgWeapon.RANGE
var aim_direction := Vector3.BACK
var model: Node3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var bot_model := 0
var bot_animation := true
var capsule_visual: MeshInstance3D
var animation_speed := 1.0
var pending_locomotion := ""
var locomotion_wait := 0.0
var collision: CollisionShape3D
var hit_area: Area3D
var hit_collision: CollisionShape3D
var pelvis_index := -1
var pelvis_pose := Transform3D.IDENTITY
var facing_correction := 0.0
var terrain := preload("res://scripts/maps/bot_terrain.gd").new()
const TERRAIN_MOTION = preload("res://scripts/maps/terrain_motion.gd")
const LAYERS = preload("res://scripts/maps/collision_layers.gd")


func _ready() -> void:
	floor_snap_length = 0.15
	safe_margin = 0.001
	collision_layer = 8
	collision_mask = 3
	add_to_group("lg_target")
	collision = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.82
	collision.position.y = 0.91
	collision.shape = shape
	add_child(collision)
	hit_area = Area3D.new()
	hit_area.name = "DamageHitbox"
	hit_area.collision_layer = 4
	hit_area.collision_mask = 0
	hit_area.monitoring = false
	hit_area.monitorable = false
	hit_area.add_to_group("lg_damage_hitbox")
	add_child(hit_area)
	hit_collision = CollisionShape3D.new()
	hit_collision.position.y = 0.91
	hit_area.add_child(hit_collision)
	visual = Node3D.new()
	muzzle = Marker3D.new()
	weapon_pivot = Node3D.new()
	visual.name = "RobotVisual"
	add_child(visual)
	model = MODELS.create_robot()
	visual.add_child(model)
	capsule_visual = MeshInstance3D.new()
	capsule_visual.name = "CapsuleTarget"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.3
	capsule_mesh.height = 1.82
	capsule_mesh.radial_segments = 48
	capsule_mesh.rings = 12
	capsule_visual.mesh = capsule_mesh
	capsule_visual.position.y = 0.91
	capsule_visual.visible = false
	add_child(capsule_visual)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	animator.play("forward")
	animator.advance(0.0)
	pelvis_index = skeleton.find_bone("pelvis")
	pelvis_pose = skeleton.get_bone_rest(pelvis_index)
	var spine := skeleton.find_bone("spine_01")
	for bone in skeleton.get_bone_count():
		var ancestor := bone
		while ancestor >= 0:
			if ancestor == spine:
				var bone_name := skeleton.get_bone_name(bone)
				upper_pose[bone] = skeleton.get_bone_rest(bone) if (
					bone_name.begins_with("spine") or bone_name.begins_with("neck") or bone_name == "head"
				) else skeleton.get_bone_pose(bone)
				break
			ancestor = skeleton.get_bone_parent(ancestor)
	_stabilize_pose()
	var shoulders := _shoulder_forward()
	facing_correction = -atan2(-shoulders.x, -shoulders.z)
	visual.add_child(weapon_pivot)
	var gun := MODELS.create_rifle()
	rifle_visual = gun
	weapon_pivot.add_child(gun)
	sniper_visual = preload("res://scripts/combat/sniper_model.gd").new()
	weapon_pivot.add_child(sniper_visual)
	sniper_visual.visible = false
	muzzle.position = MODELS.MUZZLE
	weapon_pivot.add_child(muzzle)
	status_label = Label3D.new()
	status_label.text = "BOT"
	status_label.font_size = 28
	status_label.pixel_size = 0.006
	status_label.position = Vector3(0, 2.02, 0)
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.modulate = Color("#f4e9df")
	status_label.outline_size = 8
	add_child(status_label)
	_apply_body_width()


func set_appearance(style: int, animated: bool) -> void:
	bot_model = clampi(style, 0, 2)
	bot_animation = animated
	model.visible = bot_model == 0
	weapon_pivot.visible = bot_model == 0
	status_label.visible = bot_model == 0
	capsule_visual.visible = bot_model != 0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#08090a") if bot_model == 1 else Color("#36ddd3")
	capsule_visual.material_override = material
	pending_locomotion = ""
	locomotion_wait = 0.0
	animation_speed = 1.0
	animator.play("idle")
	animator.advance(0.0)
	_stabilize_pose()
	_update_gun()


func muzzle_position() -> Vector3:
	return muzzle.global_position


func set_single_shot(enabled: bool) -> void:
	single_shot = enabled
	rifle_visual.visible = not enabled
	sniper_visual.visible = enabled
	muzzle.position = sniper_visual.MUZZLE if enabled else MODELS.MUZZLE
	weapon_range = 60.0 if enabled else LgWeapon.RANGE


func reset_at(spawn: Vector3, replay_seed: int = -1) -> void:
	terrain.clear()
	global_position = spawn
	velocity = Vector3.ZERO
	health = max_health
	armor = max_armor
	dead = false
	action_time = 0.0
	fire = false
	action_name = "准备"
	if replay_seed < 0:
		rng.randomize()
		aim_rng.randomize()
		jump_rng.randomize()
		tactic_rng.randomize()
		pace_rng.randomize()
		reaction_rng.randomize()
	else:
		rng.seed = replay_seed
		aim_rng.seed = replay_seed + 71990
		jump_rng.seed = replay_seed + 102301
		tactic_rng.seed = replay_seed + 207811
		pace_rng.seed = replay_seed + 309017
		reaction_rng.seed = replay_seed + 410029
	clear_reaction()
	reaction_clock = 0.0
	reaction_count = 0
	last_reaction_at = -1.0
	tactic_time = 0.0
	tactic_count = 0
	tactic = "close"
	distance_direction = 1.0
	distance_runs = 0
	lateral_runs = 0
	pace_time = 0.0
	roam_speed_factor = 1.0
	lateral_factor = 1.0
	angular_run = 0.0
	angular_sign = 0.0
	angular_limit = tactic_rng.randf_range(PI * 0.45, PI * 0.8)
	same_side_time = 0.0
	preferred_distance = settings.engagement_distance
	spacing_out = false
	previous_distance = -1.0
	approach_rate = 0.0
	flank.reset(replay_seed)
	action_pool.reset(replay_seed)
	pattern.reset(replay_seed)
	pressure.reset(replay_seed)
	pattern_position = spawn
	action_kind = "strafe"
	orbit_direction = 1.0 if tactic_rng.randf() < 0.5 else -1.0
	jump_time = jump_rng.randf_range(0.25, 0.8)
	jumps = 0
	airborne = false
	speed_factor = 1.0
	aim_model.reset(aim_rng)
	aim_motor.clear()
	previous_aim_velocity = Vector3.ZERO
	movement_load = 0.0
	lane_center = spawn
	lane_initialized = false
	strafe_direction = 1.0
	locomotion = "right"
	pending_locomotion = ""
	locomotion_wait = 0.0
	animation_speed = 1.0
	turn_count = 0
	rotation = Vector3.ZERO
	look_yaw = PI
	aim_direction = Vector3.BACK
	visual.rotation = Vector3(0, look_yaw + facing_correction, 0)
	hit_collision.rotation.y = look_yaw
	animator.play("idle")
	animator.seek(0.0, true)
	_stabilize_pose()
	_update_gun()


func configure(key: String, value: float) -> void:
	settings.update_value(key, value)
	if key in ["aim_level", "aim_turn_rate"]:
		aim_model.clear_history()
		aim_motor.clear()
	if key == "body_width":
		_apply_body_width()
	if key in ["reaction_strength", "reaction_delay"]:
		clear_reaction()
	if key == "turn_frequency":
		action_time = minf(action_time, 1.0 / settings.turn_frequency)
		tactic_time = minf(tactic_time, 2.5 / settings.turn_frequency)
		pace_time = minf(pace_time, 1.5 / settings.turn_frequency)
	if key in ["aggression", "distance_variation", "orbit_chance", "engagement_distance"]:
		tactic_time = 0.0
	if key in ["flank_chance", "reaction_delay"]:
		flank.clear()
	if key in ["engagement_distance", "distance_variation"]:
		preferred_distance = clampf(preferred_distance, settings.distance_band().x, settings.distance_band().y)
	if key == "randomness":
		action_time = 0.0
		pace_time = 0.0
	if key == "move_speed" and settings.move_speed == 0.0:
		velocity.x = 0.0
		velocity.z = 0.0


func _apply_body_width() -> void:
	model.scale.x = settings.body_width
	capsule_visual.scale.x = settings.body_width
	_stabilize_pose()
	visual.rotation.y = 0.0
	var shoulders := _shoulder_forward()
	facing_correction = -atan2(-shoulders.x, -shoulders.z)
	visual.rotation.y = look_yaw + facing_correction
	# A ray-only hull avoids expensive convex ground contacts; locomotion keeps its capsule.
	if is_equal_approx(settings.body_width, 1.0):
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.82
		hit_collision.shape = capsule
		return
	var points := PackedVector3Array()
	for hemisphere in [-1.0, 1.0]:
		for ring in range(7):
			var latitude := float(ring) / 6.0 * PI * 0.5
			for segment in 24:
				var longitude := float(segment) / 24.0 * TAU
				points.append(Vector3(
					0.3 * cos(latitude) * cos(longitude) * settings.body_width,
					hemisphere * (0.61 + 0.3 * sin(latitude)),
					0.3 * cos(latitude) * sin(longitude)))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	hit_collision.shape = hull


func _stabilize_pose() -> void:
	skeleton.set_bone_pose_position(pelvis_index, pelvis_pose.origin)
	skeleton.set_bone_pose_rotation(pelvis_index, pelvis_pose.basis.get_rotation_quaternion())
	for bone in upper_pose:
		var pose: Transform3D = upper_pose[bone]
		skeleton.set_bone_pose_position(bone, pose.origin)
		skeleton.set_bone_pose_rotation(bone, pose.basis.get_rotation_quaternion())


func _shoulder_forward() -> Vector3:
	var left := skeleton.get_bone_global_pose(skeleton.find_bone("clavicle_l")).origin
	var right := skeleton.get_bone_global_pose(skeleton.find_bone("clavicle_r")).origin
	return Vector3.UP.cross(skeleton.global_basis * (right - left)).normalized()


func clear_reaction() -> void:
	reaction_queue.clear()
	observed_move = Vector3.ZERO
	observed_fire = false
	memory.clear()
	predictor.clear()
	next_prediction = 0.0
	next_observation = 0.0
	aim_model.intent_weight = 0.0
	aim_model.instant_read = false


func observe_player_command(move: Vector2, yaw: float, firing: bool) -> void:
	if perception_enabled and player != null and not _can_see_player():
		return
	if roaming_enabled and settings.flank_chance > 0.0:
		flank.observe(yaw, settings.reaction_delay / 1000.0)
	if not reactive_enabled:
		return
	var world_move := Basis(Vector3.UP, yaw) * Vector3(move.x, 0.0, move.y)
	if world_move.distance_to(observed_move) < 0.15 and firing == observed_fire \
		and (input_mode == 0 or reaction_clock < next_observation):
		return
	next_observation = reaction_clock + 0.05
	observed_move = world_move
	observed_fire = firing
	reaction_queue.append({"at": reaction_clock + (0.0 if input_mode == 1 else settings.reaction_delay / 1000.0),
		"sample_at": reaction_clock, "move": world_move, "local_move": move, "yaw": yaw,
		"velocity": player.velocity if player is CharacterBody3D else Vector3.ZERO,
		"speed_limit": player.profile.ground_speed if player is ArenaActor else 10.0, "fire": firing})
	if reaction_queue.size() > 256:
		reaction_queue.pop_front()


func _react_to_input(delta: float) -> void:
	reaction_clock += delta
	memory.advance(delta)
	if not reactive_enabled:
		clear_reaction()
		return
	aim_model.instant_read = input_mode == 1
	aim_model.intent_weight = 0.0
	if perception_enabled and player != null and not _can_see_player():
		reaction_queue.clear()
		predictor.clear()
		return
	var observation: Dictionary = {}
	while not reaction_queue.is_empty() and reaction_queue[0].at <= reaction_clock:
		observation = reaction_queue.pop_front()
		if input_mode > 0:
			predictor.observe(observation)
	if input_mode >= 2 and predictor.observed_at >= 0:
		var expected := predictor.expected_velocity(reaction_clock, prediction_horizon, input_mode == 2)
		aim_model.intent_velocity = expected
		aim_model.intent_weight = prediction_strength * predictor.confidence
		if reaction_clock >= next_prediction:
			next_prediction = reaction_clock + 0.1
			observation = {"move": predictor.move.lerp(expected / maxf(predictor.speed_limit, 0.1),
				prediction_strength * predictor.confidence), "fire": predictor.firing}
	if observation.is_empty():
		return
	var radial := player.global_position - global_position
	radial.y = 0.0
	radial = radial.normalized()
	var tangent := Vector3(-radial.z, 0.0, radial.x) if roaming_enabled else lane_axis
	var lateral: float = observation.move.dot(tangent)
	if adaptation_enabled:
		memory.observe(lateral, observation.move.dot(radial))
	var chance := settings.reaction_strength / 100.0 * (1.0 if input_mode == 1 else 0.9)
	if reaction_rng.randf() >= chance or spacing_out or flank.active:
		return
	var previous := strafe_direction
	if absf(lateral) > 0.2:
		var counter_bias := 0.75
		if adaptation_enabled:
			counter_bias = clampf(0.65 + absf(memory.lateral_bias) * 0.15 - memory.reversal_tendency() * 0.2, 0.45, 0.8)
		strafe_direction = signf(lateral) * (-1.0 if reaction_rng.randf() < counter_bias else 1.0)
	elif observation.fire:
		strafe_direction = -strafe_direction
	turn_count += int(previous != strafe_direction)
	action_time = reaction_rng.randf_range(0.16, 0.34)
	if roaming_enabled:
		var closing: float = observation.move.dot(radial)
		if absf(closing) > 0.2 and not pressure_enabled:
			tactic = "close" if closing > 0.0 else "retreat"
			preferred_distance = clampf(player.global_position.distance_to(global_position)
				- signf(closing) * settings.distance_variation * reaction_rng.randf_range(0.3, 0.65),
				settings.distance_band().x, settings.distance_band().y)
			tactic_time = reaction_rng.randf_range(0.35, 0.8)
		if observation.fire and reaction_rng.randf() < 0.5:
			var custom_pattern := int(pattern.values.step_mode) != 0
			var speed_floor := maxf(0.8, pattern.values.pace_floor / 100.0) if custom_pattern else 0.8
			roam_speed_factor = reaction_rng.randf_range(speed_floor, 1.0)
			pace_time = pattern.sample_pace_time() if custom_pattern else reaction_rng.randf_range(0.2, 0.5)
	reaction_count += 1
	last_reaction_at = reaction_clock


func _update_gun() -> void:
	if bot_model == 0:
		var hand := skeleton.get_bone_global_pose(skeleton.find_bone("hand_r"))
		weapon_pivot.global_position = skeleton.global_transform * hand.origin
	else:
		# Keep the beam origin stable without animating an invisible skeleton.
		weapon_pivot.global_position = global_position + Basis(Vector3.UP, look_yaw) * Vector3(0.25, 1.2, 0)
	weapon_pivot.look_at(weapon_pivot.global_position + aim_direction, Vector3.UP)


func bot_step(target_player: Node3D, delta: float, advanced: bool) -> void:
	player = target_player
	if dead:
		return
	if not lane_initialized:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		lane_axis = Vector3(-to_player.z, 0.0, to_player.x).normalized()
		if lane_axis.length_squared() < 0.5:
			lane_axis = Vector3.RIGHT
		lane_initialized = true
	action_time -= delta
	action_pool.advance(delta)
	var advanced_pattern := int(pattern.values.step_mode) != 0
	var travel := Vector2(global_position.x - pattern_position.x, global_position.z - pattern_position.z).length()
	pattern_position = global_position
	var due := pattern.advance(delta, travel) if advanced_pattern else action_time <= 0.0
	if due and not flank.active:
		_choose_action()
	_react_to_input(delta)
	var offset := (global_position - lane_center).dot(lane_axis)
	var along := velocity.dot(lane_axis)
	var in_air := advanced and not is_on_floor()
	var braking_distance := along * along / (2.0 * maxf(settings.air_control, 1.0)) if in_air else (
		settings.move_speed * speed_factor * delta)
	# Ground movement can reverse immediately; airborne movement still needs braking room.
	if not roaming_enabled and absf(offset) + braking_distance >= settings.strafe_extent and offset * strafe_direction > 0.0:
		_choose_action(true)
	var desired := lane_axis * strafe_direction * settings.move_speed * speed_factor
	if advanced_pattern and not roaming_enabled:
		pace_time -= delta
		if pace_time <= 0:
			_choose_pace()
		desired = lane_axis * strafe_direction * settings.move_speed * roam_speed_factor
	if roaming_enabled:
		desired = _roaming_velocity(delta)
	if terrain.arena != null:
		desired = terrain.steer(self, desired, _navigation_destination(desired, delta), delta,
			player.global_position if roaming_enabled and spacing_out else Vector3.INF)
	if advanced_pattern and pattern.pause_left > 0 and not spacing_out and not flank.active:
		desired = Vector3.ZERO
	var horizontal := desired
	if in_air:
		horizontal = Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, settings.air_control * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if advanced:
		jump_time -= delta
		if is_on_floor():
			velocity.y = -0.5
			if jump_time <= 0.0:
				velocity.y = 6.0
				jumps += 1
				jump_time = settings.jump_interval * jump_rng.randf_range(0.65, 1.6)
		else:
			velocity.y -= 18.0 * delta
	else:
		velocity.y = velocity.y - 18.0 * delta if terrain.arena != null and not is_on_floor() else -0.5
	if terrain.arena != null:
		TERRAIN_MOTION.move(self, delta)
	else:
		move_and_slide()
	airborne = advanced and not is_on_floor()
	if is_on_wall() and not roaming_enabled:
		for index in get_slide_collision_count():
			if get_slide_collision(index).get_normal().dot(lane_axis * strafe_direction) < -0.5:
				_choose_action(true)
				break
	aim_step(player, delta, true)


func _navigation_destination(desired: Vector3, delta: float = 1.0 / 120.0) -> Vector3:
	if not roaming_enabled:
		return global_position + desired.normalized() * maxf(3.0, settings.engagement_distance * 0.5)
	var away := global_position - player.global_position
	away.y = 0.0
	var distance := away.length()
	if away.length_squared() < 0.001:
		away = Vector3.BACK
	var radius := maxf(settings.engagement_distance, distance + 3.0) if spacing_out else preferred_distance
	if pressure_enabled:
		radius = 5.0 if spacing_out else preferred_distance
		if pressure.phase == "orbit" and not spacing_out:
			away = (away.normalized() + desired.normalized() * 0.4).normalized() * distance
	var destination := player.global_position + away.normalized() * radius
	return terrain.combat_destination(self, player.global_position, destination, delta)


func _roaming_velocity(delta: float) -> Vector3:
	var separation := player.global_position - global_position
	separation.y = 0.0
	var distance := separation.length()
	var radial := separation.normalized() if distance > 0.01 else Vector3.FORWARD
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	var band: Vector2 = settings.distance_band()
	if previous_distance >= 0.0 and delta > 0.0:
		var observed := clampf((previous_distance - distance) / delta, -40.0, 40.0)
		approach_rate = lerpf(approach_rate, observed, 1.0 - exp(-delta / 0.15))
	previous_distance = distance
	var was_spacing := spacing_out
	var pressure_step: Dictionary = {}
	if pressure_enabled:
		pressure_step = pressure.step(distance, settings, delta)
		spacing_out = pressure_step.escaping
		tactic = pressure_step.phase
		preferred_distance = pressure_step.goal
		tactic_count = pressure.episodes
	var retreat_at := minf(settings.engagement_distance - 0.6,
		band.x + maxf(0.0, approach_rate) * 0.25)
	if not pressure_enabled:
		if distance < retreat_at:
			spacing_out = true
		elif distance >= settings.engagement_distance - 0.3:
			spacing_out = false
	if was_spacing != spacing_out:
		terrain.clear()
	flank.step(radial, distance, settings, spacing_out, delta)
	if flank.active:
		strafe_direction = flank.side
	# Bound actual angular travel, not just the number of AI decisions.
	var tangential_speed := velocity.dot(tangent)
	if absf(tangential_speed) > 0.25:
		var motion_sign := signf(tangential_speed)
		if motion_sign != angular_sign:
			angular_sign = motion_sign
			angular_run = 0.0
			same_side_time = 0.0
			angular_limit = tactic_rng.randf_range(PI * 0.45, PI * 0.8)
		angular_run += absf(tangential_speed) / maxf(distance, 0.5) * delta
		same_side_time += delta
	if (angular_run >= angular_limit or (not flank.active and same_side_time >= clampf(2.4 / settings.turn_frequency, 0.65, 2.0))) \
			and strafe_direction == angular_sign:
		flank.finish("arc_limit")
		_choose_action(true)
	orbit_direction = strafe_direction
	pace_time -= delta
	if pace_time <= 0.0:
		_choose_pace()
	tactic_time -= delta
	if tactic_time <= 0.0 and not pressure_enabled:
		_choose_tactic(distance)
	# AD is the baseline; approach/retreat adds W/S without dropping the lateral input.
	var closing := 0.0 if tactic == "orbit" else clampf((distance - preferred_distance) * 0.65, -1.0, 1.0)
	var side := strafe_direction * lateral_factor
	if pressure_enabled:
		closing = pressure_step.closing
		side = strafe_direction * pressure_step.side
	if flank.active:
		closing = 0.0 if pressure_enabled else clampf((distance - settings.engagement_distance) * 0.4, -0.5, 0.5)
		side = flank.side * 1.2
	if spacing_out:
		closing = -1.0
		side *= 0.8 if pressure_enabled else 0.35
	elif distance > band.y and not pressure_enabled:
		closing = 1.0
	if distance > LgWeapon.RANGE * 0.8:
		closing = 1.0
	var direction := (radial * closing + tangent * side).normalized()
	# Anticipate walls using the real arena collision, without a map-specific position clamp.
	var origin := global_position + Vector3.UP * 0.8
	var excluded: Array[RID] = [get_rid()]
	var wall_lookahead := 0.7 + settings.move_speed * (0.16 if airborne else 0.04)
	var query := PhysicsRayQueryParameters3D.create(origin,
		origin + direction * wall_lookahead, 1, excluded)
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		flank.finish("wall")
		var normal: Vector3 = obstruction.normal
		var slide := direction.slide(normal)
		if slide.length_squared() < 0.05:
			slide = Vector3(-normal.z, 0, normal.x) * orbit_direction
		direction = (slide + normal * 0.15).normalized()
		var escape := _wall_escape_direction(direction, radial, tangent, wall_lookahead)
		if escape.length_squared() > 0.01:
			direction = escape
			action_name = "脱离墙角"
		else:
			action_name = "贴边转向"
	else:
		action_name = {"close": "斜向压近", "retreat": "斜向拉远", "orbit": "横移对枪"}[tactic]
		if flank.active:
			action_name = "寻找背身"
		elif spacing_out:
			action_name = "拉开距离"
	var pace := 1.0 if spacing_out else (maxf(roam_speed_factor, 0.85) if flank.active else roam_speed_factor)
	if pressure_enabled and int(pattern.values.step_mode) == 0:
		pace = maxf(pace, 0.65 if tactic == "close" else 0.5)
	return direction * settings.move_speed * pace


func _wall_escape_direction(preferred: Vector3, radial: Vector3, tangent: Vector3, distance: float) -> Vector3:
	var candidates := [
		preferred,
		(tangent * orbit_direction + radial * 0.35).normalized(),
		(-tangent * orbit_direction + radial * 0.35).normalized(),
		(tangent * orbit_direction - radial * 0.35).normalized(),
		(-tangent * orbit_direction - radial * 0.35).normalized(),
		(-radial + tangent * orbit_direction * 0.45).normalized()
	]
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.8
	var best := Vector3.ZERO
	var best_score := -INF
	for candidate in candidates:
		if candidate.length_squared() < 0.01:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin,
			origin + candidate * maxf(1.0, distance * 1.8), 1, [get_rid()])
		var hit := space.intersect_ray(query)
		var clearance := distance * 1.8 if hit.is_empty() else origin.distance_to(hit.position)
		var score: float = clearance * 2.0 + candidate.dot(tangent * orbit_direction) * 0.6
		if candidate.dot(radial) < -0.7 and not spacing_out:
			score -= 0.45
		if score > best_score:
			best_score = score
			best = candidate
	return best


func _choose_pace() -> void:
	if int(pattern.values.step_mode) != 0:
		roam_speed_factor = pattern.sample_speed()
		pace_time = pattern.sample_pace_time()
		return
	var variety: float = settings.randomness / 100.0
	# Separate clock: a speed change need not coincide with a left/right reversal.
	var roll := pace_rng.randf()
	var pace := pace_rng.randf_range(0.22, 0.42) if roll < 0.3 else (
		pace_rng.randf_range(0.85, 1.0) if roll < 0.7 else pace_rng.randf_range(0.45, 0.8))
	roam_speed_factor = lerpf(1.0, pace, variety)
	pace_time = pace_rng.randf_range(0.25, 0.85) * pow(2.5 / settings.turn_frequency, 0.25)


func _choose_tactic(distance: float) -> void:
	var aggressive: float = settings.aggression / 100.0
	if adaptation_enabled and reactive_enabled:
		aggressive = clampf(aggressive + memory.pressure_bias() * 0.15, 0.0, 1.0)
	var band: Vector2 = settings.distance_band()
	var roll := tactic_rng.randf()
	if distance > band.y:
		tactic = "close"
	elif distance < band.x or spacing_out:
		tactic = "retreat"
	elif lateral_runs < 2 and roll < 0.55 + settings.orbit_chance / 100.0 * 0.25:
		tactic = "orbit"
	else:
		tactic = "close" if tactic_rng.randf() < lerpf(0.3, 0.7, aggressive) else "retreat"
	if tactic == "orbit":
		lateral_runs += 1
	else:
		lateral_runs = 0
		var next_distance_direction := 1.0 if tactic == "close" else -1.0
		# Lateral decisions must not erase the history of actual advances/retreats.
		if distance_runs >= 2 and next_distance_direction == distance_direction:
			next_distance_direction = -distance_direction
		if distance > band.y:
			next_distance_direction = 1.0
		elif distance < band.x or spacing_out:
			next_distance_direction = -1.0
		distance_runs = distance_runs + 1 if next_distance_direction == distance_direction else 1
		distance_direction = next_distance_direction
		tactic = "close" if distance_direction > 0.0 else "retreat"
	var excursion: float = settings.distance_variation * tactic_rng.randf_range(0.4, 1.0)
	preferred_distance = clampf(distance - distance_direction * excursion,
		band.x, band.y)
	tactic_time = tactic_rng.randf_range(0.45, 1.25) * pow(2.5 / settings.turn_frequency, 0.35)
	tactic_count += 1


func aim_step(target_player: Node3D, delta: float, active: bool) -> void:
	player = target_player
	var to_player := player.global_position - global_position
	if Vector2(to_player.x, to_player.z).length_squared() > 0.0001:
		look_yaw = atan2(-to_player.x, -to_player.z)
	var speed := Vector2(velocity.x, velocity.z).length()
	visual.rotation.y = look_yaw + facing_correction
	hit_collision.rotation.y = look_yaw
	capsule_visual.rotation.y = look_yaw
	var local_velocity := Basis(Vector3.UP, look_yaw).inverse() * velocity
	# Keep the locomotion cycle through a reversal instead of briefly playing idle.
	if speed > 0.35:
		var candidate := locomotion
		if absf(local_velocity.x) > absf(local_velocity.z):
			candidate = "right" if local_velocity.x > 0.0 else "left"
		else:
			candidate = "forward" if local_velocity.z < 0.0 else "back"
		if candidate != pending_locomotion:
			pending_locomotion = candidate
			locomotion_wait = 0
		locomotion_wait += delta
		if locomotion_wait >= 0.10:
			locomotion = candidate
	var stopped_pattern := int(pattern.values.step_mode) != 0 and pattern.pause_left > 0 and speed < 0.1
	var clip := locomotion if active and not dead and settings.move_speed > 0.0 and not stopped_pattern \
		and bot_model == 0 and bot_animation else "idle"
	if animator.current_animation != clip:
		var phase := animator.current_animation_position / maxf(0.001, animator.current_animation_length)
		animator.play(clip, 0.08)
		animator.seek(phase * animator.get_animation(clip).length)
	animation_speed = lerpf(animation_speed, clampf(speed / 4.0, 0.6, 1.5), 1.0 - exp(-delta / 0.12))
	if bot_model == 0 and bot_animation:
		animator.advance(delta * (animation_speed if clip != "idle" else 1.0))
	# Pose only: the capsule remains upright and physics controls all displacement.
	if airborne and bot_model == 0 and bot_animation:
		for name in ["thigh_l", "thigh_r"]:
			var bone := skeleton.find_bone(name)
			if bone >= 0:
				skeleton.set_bone_pose_rotation(bone,
					skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
					* Quaternion(Vector3.RIGHT, -0.28 if name == "thigh_l" else -0.48))
	_stabilize_pose()
	_update_gun()
	# The muzzle lies on the rifle axis; use its pivot so prior aim error cannot shift the next aperture.
	var aim_origin := weapon_pivot.global_position + Vector3.UP * muzzle.position.y
	var disturbance := clampf(velocity.distance_to(previous_aim_velocity) / maxf(settings.move_speed, 1.0), 0.0, 1.0)
	previous_aim_velocity = velocity
	movement_load = maxf(disturbance, movement_load * exp(-delta / 0.15))
	var visible := not perception_enabled or _can_see_player()
	var desired_aim := aim_model.step(aim_origin, player.global_position + Vector3.UP,
		0.34, settings.aim_level, delta, aim_rng, visible, aim_direction,
		movement_load if movement_aim_enabled else 0.0)
	if settings.aim_level >= 100.0:
		aim_direction = _hard_lock_direction(player.global_position + Vector3.UP)
		aim_motor.clear()
	else:
		aim_direction = aim_motor.step(aim_direction, desired_aim, settings.aim_level, settings.aim_turn_rate, delta)
	_update_gun()
	fire = active and not dead and attack_enabled and to_player.length() < weapon_range \
		and aim_model.state != "searching"


func _can_see_player() -> bool:
	var origin := weapon_pivot.global_position + Vector3.UP * muzzle.position.y
	var offset := player.global_position + Vector3.UP - origin
	if offset.length() > weapon_range:
		return false
	var flat := Vector3(offset.x, 0, offset.z).normalized()
	var facing := Vector3(aim_direction.x, 0, aim_direction.z).normalized()
	if flat.dot(facing) < cos(deg_to_rad(110.0)):
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, origin + offset, LAYERS.WORLD_RAY, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func record_dealt_damage(amount: int) -> void:
	if adaptation_enabled and reactive_enabled:
		memory.damage_received(amount, settings.reaction_delay / 1000.0, true)


func _hard_lock_direction(point: Vector3) -> Vector3:
	var offset := point - weapon_pivot.global_position
	var horizontal := Vector2(offset.x, offset.z).length()
	# The bore is above the rotating pivot, so pivot-to-target alone is not exact.
	var pitch := atan2(offset.y, horizontal) - asin(clampf(muzzle.position.y / maxf(offset.length(), 0.001), -1.0, 1.0))
	var flat := Vector3(offset.x, 0.0, offset.z).normalized()
	if horizontal < 0.0001:
		flat = Basis(Vector3.UP, look_yaw) * Vector3.FORWARD
	return (flat * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


func _choose_action(force_reverse: bool = false) -> void:
	if int(pattern.values.step_mode) != 0:
		var chosen := pattern.choose(force_reverse)
		var previous := strafe_direction
		if chosen.reverse:
			strafe_direction = -strafe_direction
		turn_count += int(previous != strafe_direction)
		action_kind = chosen.kind
		action_duration = chosen.duration
		action_time = action_duration
		speed_factor = pattern.sample_speed()
		if action_kind == "feint":
			speed_factor = maxf(pattern.values.pace_floor / 100.0, speed_factor * 0.7)
		lateral_factor = 1.0
		if not spacing_out and not flank.active and action_kind == "feint":
			roam_speed_factor = speed_factor
			pace_time = pattern.sample_pace_time()
		return
	var variety: float = settings.randomness / 100.0
	var previous := strafe_direction
	if force_reverse or rng.randf() < 1.0 - 0.24 * variety:
		strafe_direction = -strafe_direction
	if previous != strafe_direction:
		turn_count += 1
	var action := action_pool.choose(variety, memory.reversal_tendency() if adaptation_enabled else 0.0)
	action_kind = action.kind
	action_duration = maxf(0.05, action.duration / settings.turn_frequency)
	speed_factor = lerpf(1.0, rng.randf_range(0.65, 1.0), variety)
	if action_kind == "feint":
		speed_factor *= lerpf(1.0, 0.7, variety)
		if roaming_enabled and not spacing_out and not flank.active:
			roam_speed_factor = speed_factor
			pace_time = action_duration
	if roaming_enabled:
		lateral_factor = lerpf(1.0, rng.randf_range(1.0, 1.35), variety)
	action_time = action_duration
	action_name = "空中跟踪" if airborne else "随机横移"


func take_damage(amount: int, _tick: int) -> Dictionary:
	var result := preload("res://scripts/combat/duel_rules.gd").damage(health, armor, amount if not dead else 0)
	if dead:
		return result
	if adaptation_enabled and reactive_enabled:
		memory.damage_received(result.dealt, settings.reaction_delay / 1000.0)
	health = result.health
	armor = result.armor
	if health == 0:
		dead = true
		fire = false
		action_name = "失效"
	return result


func heal(amount: int) -> void:
	if not dead:
		health = mini(max_health, health + amount)
