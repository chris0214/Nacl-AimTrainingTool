extends Node3D

const NORMAL = preload("res://resources/movement/normal.tres")
const ADVANCED = preload("res://resources/movement/advanced.tres")
const RULES = preload("res://scripts/combat/duel_rules.gd")
const AIM_ASSIST = preload("res://scripts/input/aim_assist.gd")
@onready var player: ArenaActor = $Player
@onready var camera: Camera3D = $Camera
@onready var target: CharacterBody3D = $Target
@onready var hud: CanvasLayer = $HUD
@onready var beam: Node3D = $Beam
@onready var bot_beam: Node3D = $BotBeam
var input := PlayerInput.new()
var weapon := LgWeapon.new()
var bot_weapon := LgWeapon.new()
var clock := SimulationClock.new()
var paused: bool = false
var ready_to_start: bool = true
var is_advanced: bool = false
var non_scoring: bool = false
var aiming_hit: bool = false
var endpoint: Vector3
var bot_endpoint: Vector3
var last_firing: bool = false
var probe_mode: bool = false
var visual_probe: bool = false
var active_steps: int = 0
var benchmark: bool = false
var player_health: int = RULES.MAX_HEALTH
var round_time: float = 0.0
var round_result: String = ""
var result_timer: float = 0.0
var preferences := preload("res://scripts/input/trainer_settings.gd").new()
var pending_display: Dictionary = {}
var display_deadline := 0
var player_wins := 0
var bot_wins := 0
var bot_aiming_hit := false
var info_time := 0.0
var window_decoration := Vector2i(16, 40)
var hit_audio := preload("res://scripts/combat/hit_audio.gd").new()
var armor_audio := preload("res://scripts/combat/armor_audio.gd").new()
var player_armor := 0
var round_armor := 0
var round_combat_mode := 0
var custom_arena: Node3D
var map_loading := false
var map_failed := false
var round_health := RULES.MAX_HEALTH
var review := preload("res://scripts/combat/round_review.gd").new()
var last_review: Dictionary = {}
var health_restart_queued := false
var simulation_restart_queued := false
var sniper_mode := false
var sniper_match := preload("res://scripts/combat/sniper_match.gd").new()
var sniper_audio := preload("res://scripts/combat/sniper_audio.gd").new()
var enemy_sniper_audio := preload("res://scripts/combat/sniper_audio.gd").new()
var shot_flash_until := -1
var bot_flash_until := -1
var shot_origin := Vector3.ZERO
var shot_endpoint := Vector3.ZERO
var bot_shot_origin := Vector3.ZERO
var bot_shot_endpoint := Vector3.ZERO
var bot_shot_hit := false
var bolt_sound_at := -1
var bot_bolt_sound_at := -1


func _ready() -> void:
	hit_audio.name = "HitAudio"
	add_child(hit_audio)
	armor_audio.name = "ArmorAudio"
	add_child(armor_audio)
	add_child(sniper_audio)
	add_child(enemy_sniper_audio)
	Input.use_accumulated_input = false
	Engine.max_fps = 240
	benchmark = "--benchmark" in OS.get_cmdline_user_args()
	visual_probe = "--probe" in OS.get_cmdline_user_args()
	probe_mode = "--probe" in OS.get_cmdline_user_args() or "--integration" in OS.get_cmdline_user_args() or benchmark
	_install_custom_map()
	preferences.writable = false
	if not probe_mode:
		preferences.load_settings()
	hud.resumed.connect(resume_training)
	hud.restarted.connect(reset_training)
	hud.mode_changed.connect(change_mode)
	hud.sensitivity_changed.connect(func(value: float):
		if is_finite(value) and value > 0:
			_set_preference("cm360", 914.4 / (preferences.values.dpi * value)))
	hud.fov_changed.connect(func(value: float): _set_preference("fov", value))
	hud.frame_limit_changed.connect(func(value: int): _set_preference("fps", value))
	hud.quit_requested.connect(_request_quit)
	hud.bot_setting_changed.connect(_set_preference)
	hud.bot_attack_changed.connect(func(enabled: bool): _set_preference("attack", enabled))
	hud.preference_changed.connect(_set_preference)
	hud.binding_changed.connect(_set_binding)
	hud.display_requested.connect(_request_display)
	hud.display_confirmed.connect(_confirm_display)
	hud.display_reverted.connect(_revert_display)
	hud.hit_sound_preview.connect(func(): hit_audio.confirmed_hit(1))
	hud.armor_sound_preview.connect(func(own: bool): armor_audio.broken(own))
	hud.review_requested.connect(_manual_review)
	hud.maps_requested.connect(_show_maps)
	hud.map_editor_requested.connect(func():
		if hud.commit_edits():
			_revert_display()
			get_node("/root/MapWorkspace").open_editor())
	input.bindings = preferences.bindings.duplicate()
	is_advanced = preferences.values.advanced
	_apply_preferences()
	hud.sync_preferences(preferences.values, input.bindings)
	hud.update_window_limit(_window_client_limit())
	preferences.writable = not probe_mode
	if not probe_mode:
		_apply_display(preferences.values.fullscreen, preferences.values.resolution)
		hud.sync_display(preferences.values.fullscreen, preferences.values.resolution)
	get_window().size_changed.connect(func(): call_deferred("_refresh_runtime_info"))
	bot_beam.set_enemy_style()
	reset_training()
	if map_loading:
		pause_training()
		call_deferred("_finish_map_loading")
	if get_node("/root/MapWorkspace").return_to_editor:
		get_tree().auto_accept_quit = false
	if not probe_mode and not map_loading:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func reset_training() -> void:
	if map_failed:
		return
	if hud.panel.visible and not hud.commit_edits():
		return
	_revert_display()
	hit_audio.stop()
	armor_audio.stop()
	sniper_audio.stop()
	enemy_sniper_audio.stop()
	hud.armor_overlay.clear()
	round_combat_mode = int(preferences.values.combat_mode)
	sniper_mode = int(preferences.values.weapon_mode) == 1
	input.configure_scope(sniper_mode, preferences.values.scope_zoom, preferences.values.scope_sensitivity, int(preferences.values.scope_mode))
	sniper_match.reset(int(preferences.values.score_limit), preferences.values.ad_bonus_weight, 713 if probe_mode else -1)
	shot_flash_until = -1
	bot_flash_until = -1
	bolt_sound_at = -1
	bot_bolt_sound_at = -1
	$Camera/WeaponModel.set_single_shot(sniper_mode)
	target.set_single_shot(sniper_mode)
	var vitals := RULES.vitals(preferences.values.health_pool, round_combat_mode, preferences.values.armor_pool)
	_apply_simulation_rate()
	round_health = vitals.health
	round_armor = vitals.armor
	target.max_health = round_health
	target.max_armor = round_armor
	_apply_movement_profile()
	player.reset_at($Arena/PlayerSpawn.global_position)
	target.global_position = $Arena/TargetSpawn.global_position
	target.reset_at($Arena/TargetSpawn.global_position, 18431 if probe_mode else -1)
	if custom_arena != null:
		target.look_yaw = $Arena/TargetSpawn.rotation.y
		target.aim_direction = Vector3.FORWARD.rotated(Vector3.UP, target.look_yaw)
		target.visual.rotation.y = target.look_yaw + target.facing_correction
		target.hit_collision.rotation.y = target.look_yaw
		target._update_gun()
	target.player = player
	player_health = round_health
	player_armor = round_armor
	round_time = 0.0
	round_result = ""
	result_timer = 0.0
	input.clear(true)
	if custom_arena != null:
		input.correct_view($Arena/PlayerSpawn.rotation.y, 0)
	weapon.reset()
	bot_weapon.reset()
	clock.reset(Time.get_ticks_usec())
	non_scoring = preferences.values.assist_mode != 0
	review.begin(preferences.values)
	last_review.clear()
	hud.hide_review()
	hud.update_duel_state(player_health, target.health, "", false, 0, bot_weapon)
	hud.update_armor_state(not sniper_mode and round_combat_mode == 1, player_armor, target.armor, round_armor)
	ready_to_start = true
	paused = false
	active_steps = 0
	last_firing = false
	aiming_hit = false
	bot_aiming_hit = false
	endpoint = player.eye_position() + Vector3.FORWARD * LgWeapon.RANGE
	bot_endpoint = target.muzzle_position()
	beam.visible = false
	bot_beam.visible = false
	hud.set_paused(false)
	if not probe_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera()


func change_mode(advanced: bool) -> void:
	if not hud.commit_edits():
		hud.mode_normal.set_pressed_no_signal(not is_advanced)
		hud.mode_advanced.set_pressed_no_signal(is_advanced)
		return
	var was_paused := paused
	is_advanced = advanced
	preferences.put("advanced", advanced)
	_save_preferences()
	reset_training()
	hud.sync_training_options(preferences.values)
	if was_paused:
		pause_training()


func pause_training(overloaded: bool = false) -> void:
	if hud.review_panel.visible:
		return
	hit_audio.stop()
	armor_audio.stop()
	sniper_audio.stop()
	enemy_sniper_audio.stop()
	sniper_match.discontinuity()
	shot_flash_until = -1
	bot_flash_until = -1
	bolt_sound_at = -1
	bot_bolt_sound_at = -1
	hud.armor_overlay.clear()
	target.aim_model.clear_history()
	target.aim_motor.clear()
	target.action_pool.clear()
	target.pattern.clear()
	target.pressure.clear()
	review.discontinuity()
	target.previous_aim_velocity = Vector3.ZERO
	target.movement_load = 0.0
	target.flank.clear()
	paused = true
	target.clear_reaction()
	non_scoring = non_scoring or overloaded
	input.clear()
	last_firing = false
	beam.visible = false
	bot_beam.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_paused(true, overloaded)
	_update_scope_view()
	hud.update_window_limit(_window_client_limit())
	_refresh_runtime_info()


func resume_training() -> void:
	if map_loading or map_failed:
		return
	if not hud.commit_edits():
		return
	if not round_result.is_empty():
		reset_training()
		return
	_revert_display()
	input.clear()
	clock.invalid = false
	clock.rebase(Time.get_ticks_usec())
	paused = false
	hud.set_paused(false)
	_update_scope_view()
	if not probe_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not probe_mode:
		pause_training()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready() \
		and get_node("/root/MapWorkspace").return_to_editor:
		_request_quit()


func _exit_tree() -> void:
	get_tree().auto_accept_quit = true


func _request_quit() -> void:
	_revert_display()
	var workspace := get_node("/root/MapWorkspace")
	if workspace.return_to_editor and workspace.document.changed():
		pause_training()
		var dialog := ConfirmationDialog.new()
		dialog.title = "未保存的地图"
		dialog.dialog_text = "试玩前的地图尚未保存。放弃修改并退出？"
		dialog.ok_button_text = "放弃并退出"
		dialog.cancel_button_text = "取消"
		dialog.add_button("返回编辑器", true, "editor")
		dialog.custom_action.connect(func(_action: String): workspace.open_editor())
		dialog.confirmed.connect(func(): get_tree().quit())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered()
	else:
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if benchmark or visual_probe:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if paused:
				resume_training()
			else:
				pause_training()
			get_viewport().set_input_as_handled()
			return
	if not paused and input.is_restart(event):
		reset_training()
		get_viewport().set_input_as_handled()
		return
	if not paused:
		input.ingest(event, Time.get_ticks_usec())


func _physics_process(delta: float) -> void:
	if paused or map_loading or map_failed:
		return
	if result_timer > 0.0:
		result_timer -= delta
		if result_timer <= 0.0:
			reset_training()
		return
	var now := Time.get_ticks_usec()
	if not ready_to_start and not clock.guard_frame(now, Engine.get_process_frames()):
		pause_training(true)
		return
	if ready_to_start:
		clock.rebase(now)
	var command := input.consume(clock.deadline_usec())
	if benchmark and $PlaytestProbe.running:
		command = $PlaytestProbe.command_for_tick(clock.tick)
		input.yaw = 0.0
		input.pitch = 0.0
		input.preview_yaw = 0.0
		input.preview_pitch = 0.0
	if ready_to_start and (command.fire_pressed or (sniper_mode and command.get("scope_pressed", false))):
		ready_to_start = false
		clock.reset(now)
	# Movement remains available before shooting; only the score clock is idle.
	var probe_started := Time.get_ticks_usec() if visual_probe else 0
	var player_before := player.global_position
	player.simulate(command.move, input.yaw, command.jump, delta)
	var displacement := player.global_position - player_before
	if not ready_to_start:
		target.observe_player_command(command.move, input.yaw, command.fire)
		target.bot_step(player, delta, is_advanced)
	else:
		target.aim_step(player, delta, false)
	if custom_arena != null and (player.position.y < custom_arena.map_data.kill_y \
		or target.position.y < custom_arena.map_data.kill_y):
		reset_training()
		return
	if visual_probe and Time.get_ticks_usec() - probe_started > 20000:
		print("PROBE_SLOW_ACTORS us=", Time.get_ticks_usec() - probe_started, " tick=", clock.tick)
	active_steps += 1
	_apply_player_assist(command.fire and not ready_to_start, delta)
	var direction := Basis.from_euler(Vector3(input.pitch, input.yaw, 0.0)) * Vector3.FORWARD
	var ray := weapon.trace(get_world_3d().direct_space_state, player.eye_position(), direction, [player.get_rid()])
	endpoint = ray.get("position", player.eye_position() + direction * weapon.range_m)
	aiming_hit = not ray.is_empty() and ray.collider == target
	last_firing = command.fire and not ready_to_start
	if sniper_mode:
		if not ready_to_start:
			_step_sniper(command, delta, displacement, direction, ray)
		return
	if not ready_to_start:
		var shots_before := weapon.shots
		var incoming := 0
		var outgoing := 0
		if weapon.is_due(clock.tick, last_firing) and aiming_hit:
			weapon.record_hit()
			var damage: Dictionary = target.take_damage(LgWeapon.DAMAGE, clock.tick)
			var dealt: int = damage.dealt
			outgoing = dealt
			player_health = mini(round_health, player_health + dealt)
			if damage.broken:
				armor_audio.broken(false)
			hit_audio.confirmed_hit(dealt)
		var bot_origin: Vector3 = target.muzzle_position()
		var bot_direction: Vector3 = target.aim_direction
		var bot_ray: Dictionary = bot_weapon.trace(get_world_3d().direct_space_state,
			bot_origin, bot_direction, [target.get_rid(), target.hit_area.get_rid()])
		bot_endpoint = bot_ray.get("position", bot_origin + bot_direction * LgWeapon.RANGE)
		bot_aiming_hit = bot_ray.get("collider", null) == player
		if bot_weapon.is_due(clock.tick, target.fire):
			if bot_aiming_hit:
				var damage := _damage_player(LgWeapon.DAMAGE)
				var dealt: int = damage.dealt
				incoming = dealt
				bot_weapon.record_hit()
				target.heal(dealt)
				target.record_dealt_damage(dealt)
		_record_review(command, delta, weapon.shots > shots_before, incoming, outgoing, displacement)
		clock.tick += 1
		round_time = clock.tick / float(clock.hz)
		if player_health <= 0 or target.health <= 0:
			round_result = "玩家胜利" if target.health <= 0 and player_health > 0 else "Bot 胜利"
			if target.health <= 0 and player_health <= 0:
				round_result = "同时失效"
			elif not non_scoring:
				player_wins += int(player_health > 0)
				bot_wins += int(target.health > 0)
			result_timer = 2.0
			target.fire = false
			last_firing = false
			beam.visible = false
			bot_beam.visible = false
			if preferences.values.round_review and not benchmark:
				_present_review()
	if benchmark:
		$PlaytestProbe.after_step()


func _process(_delta: float) -> void:
	info_time += _delta
	if paused and info_time >= 0.25:
		info_time = 0.0
		_refresh_runtime_info()
	if not pending_display.is_empty():
		var seconds := (display_deadline - Time.get_ticks_msec()) / 1000.0
		if seconds <= 0.0:
			_revert_display()
		else:
			hud.display_pending(seconds)
	if not paused:
		_update_camera()
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var phase := "准备" if ready_to_start else ("非计分练习" if non_scoring else "训练中")
	if preferences.values.assist_mode != 0:
		phase = "娱乐 / " + ("平滑自瞄" if preferences.values.assist_mode == 1 else "线性自瞄")
	if paused:
		phase = "已暂停"
	hud.update_state(is_advanced, phase, clock.tick, weapon, speed,
		aiming_hit and last_firing, clock.backlog_usec / 1000.0)
	hud.update_player_tuning(speed, player.profile.ground_speed, player.instant_movement)
	hud.update_duel_state(player_health, target.health, target.action_name,
		target.fire and not paused and result_timer <= 0.0, round_time, bot_weapon)
	hud.update_armor_state(not sniper_mode and round_combat_mode == 1, player_armor, target.armor, round_armor)
	if not paused:
		hud.armor_overlay.advance(_delta)
	hud.update_bot_behavior(target.aim_model.state, target.action_kind)
	hud.set_round_result(round_result)
	if map_loading:
		hud.setting_status.text = "正在准备地图与导航..."
	elif map_failed:
		hud.setting_status.text = custom_arena.validation_error
	hud.update_scores(player_wins, bot_wins)
	hud.update_training_score(review.score.result(non_scoring or review.mixed_settings))
	var playing := not paused and result_timer <= 0.0 and not ready_to_start
	hud.set_weapon_mode(sniper_mode)
	if sniper_mode:
		var remaining := maxf(0, float(weapon.next_shot_tick - clock.tick) / clock.hz)
		var bot_remaining := maxf(0, float(bot_weapon.next_shot_tick - clock.tick) / clock.hz)
		hud.update_sniper(sniper_match, remaining, bot_remaining, weapon, non_scoring or review.mixed_settings)
		$Camera/WeaponModel.update_state(clock.tick < shot_flash_until and playing, _delta)
		$Camera/WeaponModel.update_cycle(remaining / preferences.values.sniper_cooldown)
		target.sniper_visual.cycle(bot_remaining / preferences.values.bot_sniper_cooldown)
		beam.show_segment(shot_origin, shot_endpoint, clock.tick < shot_flash_until and playing and not input.preview_scoped and preferences.values.player_tracer)
		bot_beam.show_segment(bot_shot_origin, bot_shot_endpoint,
			clock.tick < bot_flash_until and playing and preferences.values.bot_tracer, bot_shot_hit)
		return
	$Camera/WeaponModel.update_state(last_firing and playing, _delta)
	beam.show_segment($Camera/WeaponModel.muzzle_position(), endpoint, last_firing and playing and preferences.values.player_tracer)
	bot_beam.show_segment(target.muzzle_position(), bot_endpoint,
		target.fire and playing and not target.dead and preferences.values.bot_tracer, bot_aiming_hit)


func _damage_player(amount: int) -> Dictionary:
	var result := RULES.damage(player_health, player_armor, amount)
	player_health = result.health
	player_armor = result.armor
	if result.armor_damage > 0:
		hud.armor_overlay.pulse(result.broken)
	if result.broken:
		armor_audio.broken(true)
	return result


func _apply_player_assist(firing: bool, delta: float) -> void:
	if preferences.values.assist_mode == 0 or not firing or paused or result_timer > 0.0 or target.dead:
		return
	non_scoring = true
	var origin := player.eye_position()
	var point := target.global_position + Vector3.UP * 1.35
	var direction := point - origin
	if direction.length_squared() < 0.000001 or direction.length() > weapon.range_m:
		return
	var visibility := weapon.trace(get_world_3d().direct_space_state, origin, direction.normalized(), [player.get_rid()])
	if visibility.get("collider", null) != target:
		return
	AIM_ASSIST.step(input, origin, point, delta, preferences.values.assist_mode,
		preferences.values.assist_speed, preferences.values.assist_response)


func _update_camera() -> void:
	var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	camera.global_position = player.previous_position.lerp(player.global_position, fraction) + Vector3.UP * ArenaActor.EYE_HEIGHT
	camera.global_position.y -= player.step_camera_offset
	camera.rotation = Vector3(input.preview_pitch, input.preview_yaw, 0)
	_update_scope_view()


func _update_scope_view() -> void:
	var scoped := sniper_mode and input.preview_scoped and not paused and not sniper_match.finished
	var base := preferences.vertical_fov()
	camera.fov = PlayerInput.scoped_fov(base, input.scope_zoom) if scoped and not preferences.values.scope_lens else base
	$Camera/WeaponModel.visible = not scoped
	hud.set_scope(scoped, input.scope_zoom)
	hud.scope_overlay.lens.update_view(camera, scoped, base, input.scope_zoom)


func _install_custom_map() -> void:
	var workspace := get_node("/root/MapWorkspace")
	if workspace.active_map.is_empty():
		return
	var old := $Arena
	remove_child(old)
	old.queue_free()
	custom_arena = preload("res://scenes/arena/flat_arena.tscn").instantiate()
	custom_arena.set_script(preload("res://scripts/maps/custom_arena.gd"))
	custom_arena.map_data = workspace.active_map.duplicate(true)
	custom_arena.name = "Arena"
	add_child(custom_arena)
	player.terrain_enabled = true
	player.floor_constant_speed = true
	player.floor_max_angle = deg_to_rad(44)
	player.floor_snap_length = 0.35
	target.terrain.arena = custom_arena
	target.floor_constant_speed = true
	target.floor_max_angle = deg_to_rad(44)
	target.floor_snap_length = 0.35
	map_loading = true


func _finish_map_loading() -> void:
	while custom_arena.loading:
		await get_tree().physics_frame
	map_loading = false
	map_failed = not custom_arena.validation_error.is_empty()
	if map_failed:
		get_node("/root/MapWorkspace").launch_error = custom_arena.validation_error
		pause_training()
	else:
		reset_training()
		pause_training()


func _show_maps() -> void:
	if not hud.commit_edits():
		return
	_revert_display()
	var dialog := preload("res://scripts/maps/map_library.gd").new()
	add_child(dialog)
	dialog.chosen.connect(func(data: Dictionary, path: String):
		get_node("/root/MapWorkspace").play_map(data, path))
	dialog.default_chosen.connect(func(): get_node("/root/MapWorkspace").default_training())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _set_preference(key: String, value: Variant) -> void:
	var previous := preferences.values.duplicate()
	if key == "fov_mode":
		var vertical := preferences.vertical_fov()
		preferences.put(key, value)
		preferences.put("fov", vertical if preferences.values.fov_mode == 0 else PlayerInput.horizontal_fov(vertical, 16.0 / 9.0))
		hud.preference_controls.fov.set_value_no_signal(preferences.values.fov)
	elif key == "base_speed":
		preferences.set_base_speed(value)
	elif key == "movement_preset" and value is int:
		if value == 5:
			preferences.put(key, value)
		else:
			preferences.apply_movement_preset(value)
	elif preferences.FOOTWORK.DEFAULTS.has(key):
		preferences.set_footwork(key, value)
	else:
		preferences.put(key, value)
	if not ready_to_start and review.ticks > 0 \
		and key not in preferences.VISUAL_KEYS \
		and key not in ["round_review", "hit_sound", "hit_volume", "hit_sound_style", "armor_sound", "armor_volume", "sniper_volume"]:
		for option in preferences.values:
			var before: Variant = previous[option]
			var after: Variant = preferences.values[option]
			var changed: bool = absf(before - after) > 0.000000001 if before is float and after is float else before != after
			review.mixed_settings = review.mixed_settings or changed
	_apply_preference(key)
	hud.sync_training_options(preferences.values)
	if hud.preference_controls.has(key):
		var control: Control = hud.preference_controls[key]
		if control is ColorPickerButton:
			control.color = preferences.values[key]
		elif control is SpinBox and not control.has_meta("draft"):
			control.set_value_no_signal(preferences.values[key])
		elif control is OptionButton:
			control.select(control.get_item_index(int(preferences.values[key])))
			control.set_meta("applied", preferences.values[key])
		elif control is CheckButton:
			control.set_pressed_no_signal(preferences.values[key])
	if hud.bot_controls.has(key):
		hud.bot_controls[key].set_value_no_signal(preferences.values[key])
		hud.bot_sliders[key].set_value_no_signal(preferences.values[key])
	if key == "body_width":
		hud.sync_body_width(preferences.values.body_width)
	if key == "aim_level":
		hud.update_aim_profile(preferences.values.aim_level)
	if key == "roaming":
		hud.roaming_toggle.set_pressed_no_signal(preferences.values.roaming)
	elif key == "attack":
		hud.attack_toggle.set_pressed_no_signal(preferences.values.attack)
	hud.update_mouse_readout(preferences.values.dpi, preferences.values.cm360)
	_refresh_runtime_info()
	_save_preferences()


func _apply_movement_profile() -> void:
	var template: MovementProfile = ADVANCED if is_advanced else NORMAL
	player.profile = template.duplicate()
	var ratio: float = preferences.values.base_speed / template.ground_speed
	player.profile.ground_speed *= ratio
	player.profile.ground_acceleration *= ratio
	player.profile.stop_speed *= ratio
	player.profile.air_wish_speed *= ratio
	player.profile.air_acceleration *= ratio
	player.profile.speed_limit *= ratio


func _apply_preferences() -> void:
	var values: Dictionary = preferences.values
	input.sensitivity = PlayerInput.sensitivity_from_cm(values.dpi, values.cm360)
	input.invert_y = values.invert_y
	input.configure_scope(int(values.weapon_mode) == 1, values.scope_zoom, values.scope_sensitivity, int(values.scope_mode))
	camera.fov = preferences.vertical_fov()
	Engine.max_fps = values.fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	target.attack_enabled = values.attack
	target.roaming_enabled = values.roaming
	target.pressure_enabled = int(values.roam_style) == 1
	target.reactive_enabled = values.reactive_bot
	target.perception_enabled = values.bot_perception
	target.adaptation_enabled = values.bot_adaptation
	target.movement_aim_enabled = values.bot_motion_aim
	player.instant_movement = values.instant_movement
	_apply_movement_profile()
	hit_audio.configure(values)
	armor_audio.configure(values)
	hud.armor_overlay.configure(values)
	hud.configure_visuals(values)
	$Arena.apply_appearance(values)
	for key in target.settings.DEFAULTS:
		target.configure(key, values[key])
	target.set_appearance(values.bot_model, values.bot_animation)
	_apply_training_options()


func _apply_training_options() -> void:
	for key in preferences.FOOTWORK.DEFAULTS:
		target.pattern.values[key] = preferences.values[key]
	target.input_mode = int(preferences.values.input_mode)
	target.prediction_horizon = preferences.values.prediction_horizon / 1000.0
	target.prediction_strength = preferences.values.prediction_strength / 100.0


func _record_review(command: Dictionary, delta: float, shot: bool, incoming: int,
	outgoing: int = 0, displacement: Vector3 = Vector3.ZERO) -> void:
	var point := target.global_position + Vector3.UP * 0.91
	var eye := player.eye_position()
	var query := PhysicsRayQueryParameters3D.create(eye, point,
		preload("res://scripts/maps/collision_layers.gd").WORLD_RAY, [player.get_rid()])
	var visible := eye.distance_to(point) <= weapon.range_m and (
		get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	review.sample({"eye": eye, "target": point, "radius": 0.3 * target.settings.body_width,
		"yaw": input.yaw, "pitch": input.pitch, "look": command.get("look", Vector2.ZERO),
		"move": command.move, "speed": Vector2(player.velocity.x, player.velocity.z).length(),
		"displacement": displacement, "speed_limit": player.profile.ground_speed, "outgoing": outgoing,
		"hit": aiming_hit, "firing": last_firing, "shot": shot, "visible": visible,
		"incoming": incoming, "assisted": preferences.values.assist_mode != 0}, delta)


func _manual_review() -> void:
	if ready_to_start or review.ticks == 0:
		hud.setting_status.text = "本轮还没有开火数据"
		return
	if not hud.commit_edits():
		return
	round_result = "手动结束" if round_result.is_empty() else round_result
	_present_review()


func _present_review() -> void:
	if sniper_mode:
		sniper_match.finished = true
		last_review = sniper_match.report(round_result, weapon, bot_weapon, non_scoring or review.mixed_settings)
	else:
		last_review = review.result(weapon.shots, weapon.hits, weapon.damage, round_result)
	last_review.score.valid = last_review.score.valid and not non_scoring
	result_timer = 0
	pause_training()
	hud.show_review(last_review)


func _restart_health_mode() -> void:
	health_restart_queued = false
	var was_paused := paused
	reset_training()
	if was_paused:
		pause_training()


func _apply_preference(key: String) -> void:
	var values: Dictionary = preferences.values
	if key in preferences.VISUAL_KEYS:
		hud.configure_visuals(values)
		_update_scope_view()
		if not values.player_tracer:
			beam.visible = false
		if not values.bot_tracer:
			bot_beam.visible = false
	elif key in ["dpi", "cm360"]:
		input.sensitivity = PlayerInput.sensitivity_from_cm(values.dpi, values.cm360)
	elif key == "invert_y":
		input.invert_y = values.invert_y
	elif key in ["fov", "fov_mode", "scope_zoom", "scope_sensitivity", "scope_mode"]:
		input.configure_scope(sniper_mode, values.scope_zoom, values.scope_sensitivity, int(values.scope_mode))
		_update_scope_view()
	elif key == "fps":
		Engine.max_fps = values.fps
	elif key in ["simulation_hz", "ad_bonus_weight", "weapon_mode", "score_limit", "sniper_cooldown", "bot_sniper_cooldown"]:
		if (key in ["weapon_mode", "score_limit", "sniper_cooldown", "bot_sniper_cooldown"] \
			or clock.hz != int(values.simulation_hz) or not is_equal_approx(review.score.weight, values.ad_bonus_weight)) \
			and not simulation_restart_queued:
			simulation_restart_queued = true
			call_deferred("_restart_simulation_settings")
	elif key == "vsync":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	elif key == "attack":
		target.attack_enabled = values.attack
	elif key in ["bot_model", "bot_animation"]:
		target.set_appearance(values.bot_model, values.bot_animation)
	elif key == "roaming":
		target.roaming_enabled = values.roaming
		target.lane_center = target.global_position
		target.lane_initialized = false
		target.tactic_time = 0.0
		target.flank.clear()
		target.spacing_out = false
		target.action_pool.clear()
		target.clear_reaction()
		target.pressure.clear()
	elif key == "roam_style":
		target.pressure_enabled = int(values.roam_style) == 1
		target.pressure.clear()
		target.flank.clear()
		target.terrain.clear()
		target.spacing_out = false
		target.tactic_time = 0
		target.clear_reaction()
	elif key == "reactive_bot":
		target.reactive_enabled = values.reactive_bot
		target.clear_reaction()
	elif key == "bot_perception":
		target.perception_enabled = values.bot_perception
		target.aim_model.clear_history()
		target.aim_motor.clear()
		target.flank.clear()
		target.clear_reaction()
	elif key == "bot_adaptation":
		target.adaptation_enabled = values.bot_adaptation
		target.clear_reaction()
	elif key == "bot_motion_aim":
		target.movement_aim_enabled = values.bot_motion_aim
		target.movement_load = 0.0
		target.previous_aim_velocity = target.velocity
	elif key == "instant_movement":
		player.instant_movement = values.instant_movement
	elif key == "base_speed":
		_apply_movement_profile()
		target.configure("move_speed", values.move_speed)
		hud.bot_controls.move_speed.set_value_no_signal(values.move_speed)
		hud.bot_sliders.move_speed.set_value_no_signal(values.move_speed)
	elif key == "assist_mode":
		non_scoring = non_scoring or values.assist_mode != 0
		review.assisted = review.assisted or values.assist_mode != 0
	elif key in ["health_pool", "armor_pool", "combat_mode"]:
		var vitals := RULES.vitals(values.health_pool, values.combat_mode, values.armor_pool)
		hud.armor_overlay.configure(values)
		if (round_health != vitals.health or round_armor != vitals.armor \
			or round_combat_mode != int(values.combat_mode)) and not health_restart_queued:
			health_restart_queued = true
			call_deferred("_restart_health_mode")
	elif key == "movement_preset" or preferences.FOOTWORK.DEFAULTS.has(key):
		_apply_training_options()
		target.pattern.clear()
		target.pattern_position = target.global_position
		target.action_time = 0
		target.pace_time = 0
	elif key in ["input_mode", "prediction_strength", "prediction_horizon"]:
		_apply_training_options()
		target.clear_reaction()
		target.aim_model.clear_history()
	elif key in ["hit_sound", "hit_volume", "hit_sound_style"]:
		hit_audio.configure(values)
	elif key in ["armor_sound", "armor_volume"]:
		armor_audio.configure(values)
	elif key in ["armor_effect", "armor_effect_strength"]:
		hud.armor_overlay.configure(values)
	elif key in ["sky_style", "arena_style", "floor_grid", "scene_brightness"]:
		$Arena.apply_appearance(values)
	elif target.settings.DEFAULTS.has(key):
		target.configure(key, values[key])


func _apply_simulation_rate() -> void:
	clock.hz = int(preferences.values.simulation_hz)
	Engine.physics_ticks_per_second = clock.hz
	Engine.max_physics_steps_per_frame = 16 * (clock.hz / 120)
	weapon.interval_ticks = clock.hz / 20
	bot_weapon.interval_ticks = clock.hz / 20
	for gun in [weapon, bot_weapon]:
		gun.shot_damage = 0 if sniper_mode else LgWeapon.DAMAGE
		gun.range_m = 60.0 if sniper_mode else LgWeapon.RANGE
		if sniper_mode:
			gun.interval_ticks = ceili(preferences.values.sniper_cooldown * clock.hz - 0.000001)
	if sniper_mode:
		bot_weapon.interval_ticks = ceili(preferences.values.bot_sniper_cooldown * clock.hz - 0.000001)


func _step_sniper(command: Dictionary, delta: float, displacement: Vector3, direction: Vector3, shot_ray: Dictionary = {}) -> void:
	if sniper_match.finished:
		return
	var space := get_world_3d().direct_space_state
	var center: Vector3 = target.global_position + Vector3.UP * 0.91
	var sight := PhysicsRayQueryParameters3D.create(player.eye_position(), center,
		preload("res://scripts/maps/collision_layers.gd").WORLD_RAY, [player.get_rid()])
	var visible := player.eye_position().distance_to(center) <= weapon.range_m and space.intersect_ray(sight).is_empty()
	sniper_match.sample(delta, displacement, command.move, input.yaw, player.profile.ground_speed, visible)
	if bolt_sound_at >= 0 and clock.tick >= bolt_sound_at:
		sniper_audio.trigger(true, preferences.values.sniper_volume)
		bolt_sound_at = -1
	if bot_bolt_sound_at >= 0 and clock.tick >= bot_bolt_sound_at:
		enemy_sniper_audio.trigger(true, preferences.values.sniper_volume, true)
		bot_bolt_sound_at = -1
	var fired := weapon.is_due(clock.tick, command.fire_pressed)
	if fired:
		if aiming_hit:
			weapon.record_hit()
			hit_audio.confirmed_hit(1)
		sniper_match.record_player_shot(aiming_hit, command.move,
			rad_to_deg(direction.angle_to(center - player.eye_position())))
		var offset := center - player.eye_position()
		var bearing := atan2(-offset.x, -offset.z)
		var elevation := atan2(offset.y, Vector2(offset.x, offset.z).length())
		var local_motion := Basis(Vector3.UP, input.yaw).inverse() * (displacement / maxf(delta, 0.000001))
		var trace_kind := "命中目标" if aiming_hit else ("击中场景" if not shot_ray.is_empty() else "未碰撞")
		sniper_match.add_snapshot({
			"number": weapon.shots, "time": float(clock.tick) / clock.hz, "hit": aiming_hit,
			"horizontal": rad_to_deg(wrapf(bearing - input.yaw, -PI, PI)),
			"vertical": rad_to_deg(input.pitch - elevation),
			"angle": rad_to_deg(direction.angle_to(offset)), "distance": offset.length(),
			"input_move": command.move, "lateral_speed": local_motion.x, "forward_speed": -local_motion.z,
			"vertical_speed": local_motion.y, "scoped": command.get("scope", false),
			"zoom": input.scope_zoom if command.get("scope", false) else 1.0,
			"center_blocked": not space.intersect_ray(sight).is_empty(),
			"out_of_range": offset.length() > weapon.range_m, "trace": trace_kind,
			"ray_distance": player.eye_position().distance_to(shot_ray.get("position", player.eye_position() + direction * weapon.range_m))
		})
		shot_origin = $Camera/WeaponModel.muzzle_position()
		shot_endpoint = endpoint
		shot_flash_until = clock.tick + maxi(1, ceili(clock.hz * 0.06))
		bolt_sound_at = clock.tick + maxi(1, weapon.interval_ticks / 3)
		sniper_audio.trigger(false, preferences.values.sniper_volume)
	var perceived: bool = target.settings.aim_level >= 100 or \
		(target.aim_model.has_target and target.aim_model.visible_observation)
	var perceived_direction: Vector3 = target.aim_model.tracked_point - target.muzzle_position()
	var should_fire := sniper_match.wants_bot_shot(delta, clock.tick >= bot_weapon.next_shot_tick,
		target.fire, perceived, target.settings.aim_level, target.aim_direction.angle_to(perceived_direction))
	var enemy_hit := false
	if bot_weapon.is_due(clock.tick, should_fire):
		var ray := bot_weapon.trace(space, target.muzzle_position(), target.aim_direction,
			[target.get_rid(), target.hit_area.get_rid()])
		enemy_hit = ray.get("collider", null) == player
		bot_aiming_hit = enemy_hit
		if enemy_hit:
			bot_weapon.record_hit()
		bot_shot_origin = target.muzzle_position()
		bot_shot_endpoint = ray.get("position", bot_shot_origin + target.aim_direction * bot_weapon.range_m)
		bot_shot_hit = enemy_hit
		bot_flash_until = clock.tick + maxi(1, ceili(clock.hz * 0.06))
		bot_bolt_sound_at = clock.tick + maxi(1, bot_weapon.interval_ticks / 3)
		enemy_sniper_audio.trigger(false, preferences.values.sniper_volume, true)
	_record_review(command, delta, fired, 0, 0, displacement)
	# Both rays are evaluated before finishing: simultaneous final points are a draw.
	var result := sniper_match.settle(enemy_hit)
	clock.tick += 1
	round_time = clock.tick / float(clock.hz)
	if not result.is_empty():
		round_result = result
		if not non_scoring and not review.mixed_settings:
			player_wins += int(result == "玩家胜利")
			bot_wins += int(result == "Bot 胜利")
		_present_review()


func _restart_simulation_settings() -> void:
	simulation_restart_queued = false
	var was_paused := paused
	reset_training()
	if was_paused:
		pause_training()


func _set_binding(action: String, code: int) -> void:
	if action != "" and input.bind_action(action, code):
		preferences.bindings = input.bindings.duplicate()
		_save_preferences()
	hud.sync_bindings(input.bindings)


func _save_preferences() -> void:
	if preferences.save_settings() != OK:
		hud.setting_status.text = "设置保存失败；本次会话仍然生效"
	else:
		hud.setting_status.text = ""


func _apply_display(fullscreen: bool, resolution: Vector2i) -> void:
	var window := get_window()
	if fullscreen:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		window.content_scale_size = resolution
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_size = Vector2i(1440, 900)
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var limit := _window_client_limit()
		var fit := resolution
		if resolution.x > limit.x or resolution.y > limit.y:
			for candidate in preferences.RESOLUTIONS:
				if candidate.x <= limit.x and candidate.y <= limit.y:
					fit = candidate
			if pending_display.is_empty():
				preferences.put("resolution", fit)
		DisplayServer.window_set_size(fit)
		DisplayServer.window_set_position(usable.position + (usable.size - fit) / 2)
	call_deferred("_refresh_runtime_info")


func _request_display(fullscreen: bool, resolution: Vector2i) -> void:
	if not pending_display.is_empty() or not resolution in preferences.RESOLUTIONS:
		return
	if not hud.commit_edits():
		return
	var limit := _window_client_limit()
	if not fullscreen and (resolution.x > limit.x or resolution.y > limit.y):
		hud.display_status.text = "所选窗口大于当前屏幕可用区域"
		return
	pause_training()
	pending_display = {
		"mode": DisplayServer.window_get_mode(), "size": DisplayServer.window_get_size(),
		"position": DisplayServer.window_get_position(),
		"fullscreen": fullscreen, "resolution": resolution,
		"scale_mode": get_window().content_scale_mode,
		"scale_size": get_window().content_scale_size,
		"scale_aspect": get_window().content_scale_aspect
	}
	display_deadline = Time.get_ticks_msec() + 15000
	_apply_display(fullscreen, resolution)
	hud.display_pending(15.0)


func _confirm_display() -> void:
	if pending_display.is_empty():
		return
	preferences.put("fullscreen", pending_display.fullscreen)
	preferences.put("resolution", pending_display.resolution)
	pending_display.clear()
	_save_preferences()
	hud.display_pending(0)
	hud.sync_display(preferences.values.fullscreen, preferences.values.resolution)


func _revert_display() -> void:
	if pending_display.is_empty():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(pending_display.size)
	DisplayServer.window_set_position(pending_display.position)
	DisplayServer.window_set_mode(pending_display.mode)
	get_window().content_scale_mode = pending_display.scale_mode
	get_window().content_scale_size = pending_display.scale_size
	get_window().content_scale_aspect = pending_display.scale_aspect
	pending_display.clear()
	hud.sync_display(preferences.values.fullscreen, preferences.values.resolution)
	hud.display_pending(0)
	call_deferred("_refresh_runtime_info")


func _window_client_limit() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(3840, 2160)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		window_decoration = (DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()).max(Vector2i.ZERO)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return usable.size - window_decoration - Vector2i(8, 8)


func _refresh_runtime_info() -> void:
	if not is_node_ready():
		return
	# This build's ViewportTexture.get_size() is scaled again in canvas-items mode.
	# These framebuffer pixel dimensions are verified against get_image() in tests.
	var render_size := get_window().content_scale_size if (
		get_window().content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT) else get_window().size
	var aspect := float(render_size.x) / maxf(1.0, render_size.y)
	hud.update_runtime_display(DisplayServer.window_get_size(), render_size, camera.fov,
		PlayerInput.horizontal_fov(camera.fov, aspect),
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED, Engine.max_fps)
