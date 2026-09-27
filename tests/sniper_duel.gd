extends SceneTree

const MATCH = preload("res://scripts/combat/sniper_match.gd")
const PREFS = preload("res://scripts/input/trainer_settings.gd")
var checks := 0
var failures := 0
var game: Node3D


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	_unit()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.preferences.put("sniper_volume", 0)
	game._set_preference("hit_sound", false)
	game._set_preference("attack", false)
	game._set_preference("move_speed", 0)
	game._set_preference("weapon_mode", 1)
	await process_frame
	check(game.sniper_mode and game.weapon.shot_damage == 0, "UI preference activates independent rules")
	check(game.hud.setting_rows.score_limit.visible and not game.hud.setting_rows.combat_mode.visible, "mode-specific controls")
	for hz in [120, 240, 360]:
		await _live(hz)
	await _finish(25)
	await _finish(50)
	await _bot_and_wall()
	await _controls_and_motion()
	await _screenshots()
	game._set_preference("weapon_mode", 0)
	await process_frame
	check(not game.sniper_mode and game.weapon.shot_damage == LgWeapon.DAMAGE, "switch restores LG damage")
	check(game.weapon.interval_ticks == game.clock.hz / 20 and game.weapon.range_m == 24, "switch restores LG timing/range")
	check(game.sniper_match.player_points == 0 and game.sniper_match.bot_points == 0, "switch resets match")
	game.queue_free()
	await process_frame
	print("SNIPER_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _unit() -> void:
	var prefs := PREFS.new()
	prefs.put("weapon_mode", 1)
	prefs.put("score_limit", 50)
	prefs.put("sniper_cooldown", 1.25)
	prefs.put("sniper_volume", 0)
	prefs.path = "res://artifacts/sniper-settings.cfg"
	check(prefs.save_settings() == OK, "settings saved")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	check(loaded.values.weapon_mode == 1 and loaded.values.score_limit == 50 \
		and loaded.values.sniper_cooldown == 1.25 and loaded.values.sniper_volume == 0, "new settings round trip")
	for invalid in [0, 26, 50.5, NAN, "50", true]:
		loaded.put("score_limit", invalid)
		check(loaded.values.score_limit == 50, "invalid target rejected")
	for hz in [120, 240, 360]:
		var gun := LgWeapon.new()
		gun.interval_ticks = int(0.9 * hz)
		for tick in hz * 9:
			gun.is_due(tick, true)
		check(gun.shots == 10, "cooldown shot count rate independent")
		check(not gun.is_due(hz * 9, false), "idle does not replay shots")
	for limit in [25, 50]:
		for winner in ["player", "bot", "draw"]:
			var match_state := MATCH.new()
			match_state.reset(limit, 10, 3)
			for index in limit:
				match_state.record_player_shot(winner != "bot", Vector2.ZERO, 0)
				var result: String = match_state.settle(winner != "player")
				check(result.is_empty() if index < limit - 1 else not result.is_empty(), "finish only at target")
			check(match_state.finished, "match frozen at target")
			var before: int = match_state.player_points
			match_state.record_player_shot(true, Vector2.ZERO, 0)
			match_state.settle(true)
			check(before == match_state.player_points, "no extra points after result")
	var model := MATCH.new()
	model.reset(25, 10, 2)
	check(not model.wants_bot_shot(1, true, true, false, 50, 0), "no shot without perceived target")
	check(not model.wants_bot_shot(1, false, true, true, 100, 0), "hard lock still respects cooldown")
	check(model.wants_bot_shot(0.01, true, true, true, 100, 0), "100-level ready hard lock")
	model.discontinuity()
	var attempted := false
	for tick in 240:
		attempted = attempted or model.wants_bot_shot(1.0 / 120, true, true, true, 50, PI / 3)
	check(attempted, "Bot can fire with imperfect perceived alignment")
	for hz in [120, 240, 360]:
		for kind in ["moving", "jitter", "wall", "idle", "occluded"]:
			model.reset(25, 10, 4)
			for tick in hz:
				var side := -1 if kind == "jitter" and tick % 2 else 1
				var displacement := Vector3(side * 10.0 / hz, 0, 0)
				if kind in ["wall", "idle"]:
					displacement = Vector3.ZERO
				model.sample(1.0 / hz, displacement, Vector2(side, 0), 0, 10, kind != "occluded")
			model.record_player_shot(true, Vector2.RIGHT, 0)
			check(model.bonus > 0.09 and model.bonus <= 0.100001 if kind == "moving" else model.bonus == 0,
				"rolling AD bonus: " + kind)
			model.discontinuity()
			var before: float = model.bonus
			model.record_player_shot(true, Vector2.RIGHT, 0)
			check(model.bonus == before, "pause clears pending movement credit")


func _setup(hz: int = 120) -> void:
	game.preferences.put("simulation_hz", hz)
	game.preferences.put("weapon_mode", 1)
	game.preferences.put("sniper_cooldown", 0.9)
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -10), 12)
	game.input.correct_view(0, atan2(0.91 - ArenaActor.EYE_HEIGHT, 10))


func _step(press: bool = false, release: bool = false) -> void:
	if press or release:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = press
		game.input.ingest(event, 0)
	await physics_frame
	game.clock.rebase(Time.get_ticks_usec())
	game._physics_process(1.0 / game.clock.hz)


func _live(hz: int) -> void:
	_setup(hz)
	await _step(true)
	check(game.weapon.shots == 1 and game.sniper_match.player_points == 1, "first click starts and scores one")
	check(game.target.health == game.round_health and game.player_health == game.round_health, "hits do not change health")
	for tick in hz:
		await _step()
	check(game.weapon.shots == 1, "held fire does not repeat")
	await _step(false, true)
	await _step(true)
	check(game.weapon.shots == 2, "release then press shoots again")
	await _step(false, true)
	await _step(true)
	check(game.weapon.shots == 2, "cooldown click discarded")
	for tick in hz:
		await _step()
	check(game.weapon.shots == 2, "discarded click never fires later")
	game.pause_training()
	var tick_before: int = game.clock.tick
	await _step(true)
	check(game.clock.tick == tick_before, "pause freezes clock")
	game.resume_training()
	await _step()
	check(game.weapon.shots == 2, "resume clears held and buffered fire")
	check(game.weapon.hits == 2 and game.sniper_match.player_points == 2, "real ray hits score at every Hz")
	game._manual_review()
	check(game.last_review.sniper and game.last_review.player_points == 2 \
		and game.hud.review_panel.summary.text.contains("25分制"), "manual review includes actual points")
	game.hud.hide_review()


func _finish(limit: int) -> void:
	game.preferences.put("score_limit", limit)
	_setup()
	for index in limit:
		# Skip only cooldown time here; live cooldown behavior tested separately.
		game.clock.tick = index * game.weapon.interval_ticks
		game.input.firing = false
		await _step(true)
		if index < limit - 1:
			check(not game.paused, "ordinary hit keeps duel running")
	check(game.sniper_match.player_points == limit and game.paused, "goal automatically freezes match")
	check(game.hud.review_panel.visible and game.last_review.player_points == limit, "goal opens result")
	var before: int = game.weapon.shots
	await _step(true)
	check(game.weapon.shots == before, "result blocks extra shots")
	game.hud.hide_review()


func _bot_and_wall() -> void:
	game.preferences.put("score_limit", 25)
	_setup()
	game._set_preference("attack", true)
	game._set_preference("aim_level", 100)
	game.ready_to_start = false
	for tick in 125:
		await _step()
	check(game.sniper_match.bot_points == 2 and game.bot_weapon.hits == 2, "hard lock bot scores real rays on cooldown")
	check(game.player_health == game.round_health, "Bot score does not kill or drain player")
	game._set_preference("attack", false)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.position = Vector3(0, 2, -5)
	_setup()
	await _step(true)
	check(game.weapon.shots == 1 and game.sniper_match.player_points == 0, "wall blocks player score")
	check(game.shot_endpoint.z > -6, "tracer ends at blocking wall")
	game._set_preference("attack", true)
	for tick in 120:
		await _step()
	check(game.sniper_match.bot_points == 0, "wall blocks Bot score even at hard lock")
	game._set_preference("attack", false)
	wall.queue_free()
	await physics_frame
	_setup()
	game._set_preference("attack", true)
	game.ready_to_start = false
	game.sniper_match.player_points = 24
	game.sniper_match.bot_points = 24
	await _step(true)
	check(game.round_result == "平局" and game.sniper_match.player_points == 25 \
		and game.sniper_match.bot_points == 25, "simultaneous final live hits draw")
	game.hud.hide_review()
	game._set_preference("attack", false)
	_setup()
	game.non_scoring = true
	game.sniper_match.player_points = 24
	var wins: int = game.player_wins
	await _step(true)
	check(not game.last_review.score.valid and game.player_wins == wins, "non-scoring cannot earn a win")
	game.hud.hide_review()


func _controls_and_motion() -> void:
	_setup()
	game.pause_training()
	game.hud.preference_controls.score_limit.item_selected.emit(1)
	await process_frame
	check(game.paused and game.sniper_match.limit == 50, "real score selector restarts while remaining paused")
	check(game.sniper_match.player_points == 0, "selector clears old points")
	game.hud.preference_controls.sniper_cooldown.value = 1.25
	await process_frame
	check(game.weapon.interval_ticks == 150 and game.bot_weapon.interval_ticks == 90, "player cooldown UI leaves independent Bot cooldown unchanged")
	game.preferences.put("score_limit", 25)
	_setup()
	game.player.instant_movement = true
	game.input.held[KEY_D] = true
	game.ready_to_start = false
	for tick in 60:
		await _step()
	var offset: Vector3 = game.target.position + Vector3.UP * 0.91 - game.player.eye_position()
	game.input.correct_view(atan2(-offset.x, -offset.z), atan2(offset.y, Vector2(offset.x, offset.z).length()))
	await _step(true)
	check(game.sniper_match.player_points == 1 and game.sniper_match.bonus > 0, "live movement before click gets bonus")
	game.pause_training()
	var before: float = game.sniper_match.bonus
	game.resume_training()
	game.input.held.clear()
	game.clock.tick = game.weapon.next_shot_tick
	await _step(true)
	check(game.sniper_match.bonus == before, "pause cannot carry movement credit into next shot")
	_setup()
	game._set_preference("attack", true)
	game._set_preference("aim_level", 35)
	game.ready_to_start = false
	for tick in 600:
		await _step()
	check(game.bot_weapon.shots > 0 and game.bot_weapon.shots <= 6, "ordinary Bot uses reaction and shared cooldown")
	check(game.bot_weapon.hits < game.bot_weapon.shots, "ordinary Bot does not require guaranteed ray hit before shooting")
	game._set_preference("attack", false)


func _screenshots() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_setup()
	game._process(0.016)
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		game.resume_training()
		for frame in 8:
			await process_frame
		game._process(0.016)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/sniper-play-%dx%d.png" % [size.x, size.y])
		game.pause_training()
		game.hud.tabs.current_tab = 3
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/sniper-settings-%dx%d.png" % [size.x, size.y])
	game.hud.hide_review()
	game.round_result = "手动结束"
	game._present_review()
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/sniper-review.png")
	game.hud.hide_review()
