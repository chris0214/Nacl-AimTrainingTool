extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
const PATTERN = preload("res://scripts/actors/footwork_pattern.gd")
const PREDICTOR = preload("res://scripts/actors/input_predictor.gd")
const REVIEW = preload("res://scripts/combat/round_review.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node3D
var rich_report: Dictionary
var trace: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	_test_config()
	_test_patterns()
	_test_predictor()
	_test_review()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pause_training()
	game._set_preference("hit_sound", false)
	await _test_health_and_popup()
	await _test_controls_and_input()
	_test_prediction_effect()
	await _test_live_patterns()
	await _screenshots()
	var trace_id := "native" if DisplayServer.get_name() != "headless" else "120"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trace-id="):
			trace_id = arg.trim_prefix("--trace-id=").validate_filename()
	var file := FileAccess.open("res://artifacts/options-trace-%s.json" % trace_id, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "trace": trace}))
	file.close()
	game.queue_free()
	await process_frame
	print("TRAINING_OPTIONS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_config() -> void:
	var prefs := PREFS.new()
	for health in [300, 600, 1000]:
		prefs.put("health_pool", health)
		check(prefs.values.health_pool == health, "health option validates")
	prefs.put("health_pool", 400)
	check(prefs.values.health_pool == 1000, "unsupported health rejected")
	prefs.put("input_mode", 1.5)
	check(prefs.values.input_mode == 0, "noninteger mode rejected")
	var base: float = prefs.values.base_speed
	var aim: float = prefs.values.aim_level
	for index in range(1, 5):
		prefs.apply_movement_preset(index)
		check(prefs.values.base_speed == base and prefs.values.aim_level == aim, "preset preserves unrelated tuning")
		check(prefs.values.movement_preset == index and prefs.values.step_mode > 0, "preset activates new step engine")
	prefs.set_footwork("step_min", 7)
	check(prefs.values.step_max == 7 and prefs.values.movement_preset == 5, "min/max pair stays valid, custom shown")
	prefs.set_footwork("step_max", 0.2)
	check(prefs.values.step_min == 0.2, "lowering maximum clamps paired minimum")
	prefs.put("health_pool", 600)
	prefs.put("input_mode", 2)
	prefs.path = "res://artifacts/training-options.cfg"
	check(prefs.save_settings() == OK, "new controls save")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	var matched := true
	for key in prefs.values:
		if prefs.values[key] is float:
			matched = matched and absf(prefs.values[key] - loaded.values[key]) < 0.000001
		else:
			matched = matched and prefs.values[key] == loaded.values[key]
	check(matched, "new controls round trip within config precision")
	for index in range(5):
		prefs.apply_movement_preset(index)
		check(prefs.save_settings() == OK, "named preset saves")
		loaded.load_settings()
		check(loaded.values.movement_preset == index, "named preset survives config float serialization")


func _test_patterns() -> void:
	for index in range(1, 5):
		var a := PATTERN.new()
		var b := PATTERN.new()
		a.values = PATTERN.preset(index)
		b.values = PATTERN.preset(index)
		a.reset(71)
		b.reset(71)
		var exact := true
		var bounded := true
		for repeat in 100:
			var first := a.choose()
			exact = exact and first == b.choose()
			bounded = bounded and first.distance >= a.values.step_min and first.distance <= a.values.step_max \
				and first.duration >= a.values.step_time_min and first.duration <= a.values.step_time_max
		check(exact and bounded, "preset deterministic and within user bounds")
	var p := PATTERN.new()
	p.values = PATTERN.preset(3)
	p.reset(13)
	p.values.micro_weight = 0
	p.values.strafe_weight = 0
	p.values.burst_weight = 0
	p.values.feint_weight = 0
	check(p.choose().kind == "strafe", "zero weights have defined fallback")
	p.values.strafe_weight = 100
	p.values.repeat_gap = 3
	var safe := true
	for repeat in 20:
		safe = safe and p.choose().kind == "strafe"
	check(safe, "single template not starved by repeat protection")
	p.values = PATTERN.preset(3)
	var previous := ""
	var repeats := false
	p.clear()
	for repeat in 100:
		var kind: String = p.choose().kind
		repeats = repeats or kind == previous
		previous = kind
	check(not repeats, "repeat gap excludes previous template when alternatives exist")
	p.values.pause_chance = 100
	p.values.pause_min = 0.2
	p.values.pause_max = 0.2
	p.choose()
	check(is_equal_approx(p.pause_left, 0.2) and not p.advance(0.1, 0), "pause consumes no action duration")
	p.choose(true)
	check(p.pause_left == 0, "forced safety reversal skips pause")
	p.values.step_min = 1
	p.values.step_max = 1
	p.choose(true)
	check(not p.advance(STEP, 0.5) and p.advance(STEP, 0.5), "distance mode counts actual travel")
	p.choose(true)
	check(p.advance(1.01, 0), "distance mode yields if blocked instead of waiting forever")
	p.values.step_mode = 1
	p.values.step_time_min = 0.5
	p.values.step_time_max = 0.5
	p.choose(true)
	check(not p.advance(0.2, 100) and p.advance(0.3, 0), "time mode does not use distance threshold")


func _test_predictor() -> void:
	var predictor := PREDICTOR.new()
	for tick in 81:
		var at := tick * 0.05
		var side := 1 if int(tick / 10) % 2 == 0 else -1
		predictor.observe({"sample_at": at, "local_move": Vector2(side, 0), "move": Vector3(side, 0, 0),
			"velocity": Vector3(side * 10, 0, 0), "yaw": 0.0, "speed_limit": 10.0, "fire": true})
	var expected := predictor.expected_velocity(4.4, 0.15, true)
	check(predictor.transition_count >= 8 and predictor.durations.size() >= 8, "learns observed alternating episodes")
	check(predictor.confidence > 0 and expected.x < 10, "history changes future direction estimate without future input")
	check(expected.length() <= 10.001, "prediction has speed bound")
	predictor.expected_velocity(8, 0.15, true)
	check(predictor.confidence == 0, "stale input stops predictions")
	predictor.clear()
	check(predictor.observed_at == -1 and predictor.durations.is_empty(), "reset discards learning")
	var input := PlayerInput.new()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_D
	event.pressed = true
	input.ingest(event, 100)
	check(input.consume(99).move == Vector2.ZERO and input.queue.size() == 1, "future timestamp input stays queued")
	check(input.consume(100).move == Vector2.RIGHT, "input becomes readable only at its simulation deadline")


func _row() -> Dictionary:
	return {"eye": Vector3(0, 1, 0), "target": Vector3(0, 1, -10), "radius": 0.3,
		"yaw": 0.0, "pitch": 0.0, "look": Vector2.ZERO, "move": Vector2.ZERO,
		"speed": 0.0, "hit": false, "firing": true, "shot": false, "visible": true,
		"incoming": 0, "assisted": false}


func _test_review() -> void:
	var review := REVIEW.new()
	review.begin({})
	var row := _row()
	var empty := review.result(0, 0, 0, "空回合")
	check(empty.accuracy == -1 and empty.sections[0].lines[0].contains("不足"), "empty review does not fabricate diagnosis")
	row.visible = false
	for tick in 120:
		review.sample(row, STEP)
	check(review.eligible_time == 0, "occluded samples excluded")
	review.begin({})
	var previous_yaw := 0.0
	for tick in 1200:
		var time := tick * STEP
		var bearing := sin(time * 2) * 0.3
		row = _row()
		row.target = Vector3(-sin(bearing) * 10, 1, -cos(bearing) * 10)
		var after_reverse := tick % 90 < 30
		row.yaw = bearing - 0.05 * signf(cos(time * 2)) if after_reverse else bearing
		row.look = Vector2(row.yaw - previous_yaw, 0)
		previous_yaw = row.yaw
		row.move.x = 1 if int(tick / 90) % 2 == 0 else -1
		row.speed = 10
		row.hit = not after_reverse
		row.shot = tick % 6 == 0
		review.sample(row, STEP)
	rich_report = review.result(200, 133, 665, "玩家胜利")
	check(review.reversals >= 12 and review.episodes.size() >= 12, "movement reversal sample counts")
	check(review.left_time > 1 and review.right_time > 1, "both screen directions sampled")
	check(rich_report.sections[2].lines[0].contains("250ms"), "coordination compares explicit reversal window")
	check(review.behind_time > review.ahead_time, "signed angle identifies lagging without swapping sides")
	check(review.episodes.size() <= 128, "review history bounded")
	review.assisted = true
	var assisted := review.result(200, 200, 1000, "自瞄")
	check(assisted.sections[0].lines[0].contains("自瞄") and assisted.sections[2].lines[0].contains("自瞄"),
		"assisted round suppresses mouse and coordination judgments")
	review.assisted = false
	review.mixed_settings = true
	check(review.result(200, 133, 665, "变更").sections[0].lines[0].contains("中途"), "mixed settings not treated as calibration")
	review.discontinuity()
	check(not review.initialized and review.last_side == 0, "pause cannot create false reversal")


func _test_health_and_popup() -> void:
	for health in [300, 600, 1000]:
		game.hud.preference_controls.health_pool.item_selected.emit(
			game.hud.preference_controls.health_pool.get_item_index(health))
		await process_frame
		check(game.round_health == health and game.player_health == health
			and game.target.health == health and game.target.max_health == health, "health mode resets both sides")
		game.target.health = health - 3
		game.target.heal(5)
		check(game.target.health == health, "bot lifesteal clamps to selected health")
		game._set_preference("attack", false)
		game._set_preference("move_speed", 0)
		game._set_preference("instant_movement", true)
		game.reset_training()
		game.player.reset_at(Vector3.ZERO)
		game.target.reset_at(Vector3(0, 0, -8), 19)
		game.player_health = health - 1
		game.ready_to_start = false
		game.input.firing = true
		var count := 0
		while not game.target.dead and count < health * 2:
			await physics_frame
			game.clock.rebase(Time.get_ticks_usec())
			game._physics_process(STEP)
			count += 1
		check(game.target.dead and game.weapon.hits == health / 5, "actual weapon ray kills at selected pool")
		check(game.player_health == health, "player lifesteal clamps to selected health")
		check(game.paused and game.hud.review_panel.visible and game.result_timer == 0, "death pauses in review instead of auto restart")
		check(game.hud.review_panel.report.shots == game.weapon.shots, "review shows actual firing totals")
		var tick: int = game.clock.tick
		game._physics_process(STEP)
		check(game.clock.tick == tick, "review freezes simulation")
		game.hud.review_panel.next_round.emit()
		check(not game.hud.review_panel.visible and game.target.health == health and game.ready_to_start,
			"next round clears review and restores selected pool")
		game.pause_training()
	game.reset_training()
	game.ready_to_start = false
	game.review.sample(_row(), STEP)
	game._set_preference("cm360", game.preferences.values.cm360)
	check(not game.review.mixed_settings, "unchanged setting does not invalidate review")
	game._manual_review()
	check(game.paused and game.hud.review_panel.visible and game.round_result == "手动结束",
		"manual review ends and pauses current round")
	game.hud.review_panel.settings_requested.emit()
	check(game.hud.panel.visible and not game.hud.review_panel.visible, "review opens settings")
	game._set_preference("health_pool", 300)
	await process_frame
	check(game.paused and game.ready_to_start and game.target.max_health == 300
		and game.last_review.is_empty(), "changing health from review settings begins clean paused round")
	game.resume_training()
	check(not game.paused and game.ready_to_start, "resume after health change is ready")
	game._set_preference("round_review", false)
	game.target.health = 5
	game.player.reset_at(Vector3.ZERO)
	game.target.position = Vector3(0, 0, -8)
	game.ready_to_start = false
	game.input.firing = true
	for tick in 10:
		await physics_frame
		game.clock.rebase(Time.get_ticks_usec())
		game._physics_process(STEP)
		if game.target.dead:
			break
	check(game.target.dead and not game.paused and game.result_timer > 0
		and not game.hud.review_panel.visible, "review off keeps timed auto restart")
	game.input.firing = false
	for tick in 250:
		await physics_frame
		game.clock.rebase(Time.get_ticks_usec())
		game._physics_process(STEP)
	check(game.target.health == 300 and game.ready_to_start, "review off actually auto restarts")
	game._set_preference("round_review", true)
	game.pause_training()


func _test_controls_and_input() -> void:
	game._set_preference("move_speed", 4.5)
	for index in range(1, 5):
		game.hud.preference_controls.movement_preset.item_selected.emit(index)
		check(game.target.pattern.values == PATTERN.preset(index), "preset connected to runtime")
		check(not game.hud.help_markers.movement_preset.tooltip_text.is_empty(), "preset explanation available")
	game.hud.preference_controls.step_max.value = 5.3
	check(game.preferences.values.movement_preset == 5, "manual override changes preset to custom")
	check(not game.hud.preference_controls.step_min.editable, "distance field disabled for time mode")
	game.hud.preference_controls.step_mode.item_selected.emit(2)
	check(game.hud.preference_controls.step_min.editable and not game.hud.preference_controls.step_time_min.editable,
		"mode disables conflicting settings")
	game.hud.preference_controls.step_min.value = 6
	check(is_equal_approx(game.hud.preference_controls.step_max.value, 6), "paired UI stays synchronized")
	for mode in [0, 1, 2, 3]:
		game._set_preference("input_mode", mode)
		game._set_preference("reaction_strength", 100)
		game._set_preference("reactive_bot", true)
		game._set_preference("bot_perception", false)
		game.player.reset_at(Vector3.ZERO)
		game.target.reset_at(Vector3(0, 0, -12), 87)
		game.target.player = game.player
		game.target.spacing_out = false
		game.target.observe_player_command(Vector2.RIGHT, 0, true)
		game.target._react_to_input(STEP)
		check(game.target.reaction_count == (1 if mode == 1 else 0), "only instant mode removes observation wait")
		if mode != 1:
			for tick in 24:
				game.target._react_to_input(STEP)
			check(game.target.reaction_count > 0, "delayed observations eventually affect selected mode")
		game.target.configure("aim_level", 100)
		game.target.aim_step(game.player, STEP, true)
		check(game.target.aim_model.state == "hard_lock", "hard lock preserved for every input mode")
	game._set_preference("movement_preset", 1)
	game._set_preference("input_mode", 1)
	game._set_preference("roaming", true)
	game.target.reset_at(Vector3(0, 0, -12), 87)
	game.target.spacing_out = false
	var respected_floor := true
	for tick in 100:
		game.target.observe_player_command(Vector2.RIGHT if tick % 2 == 0 else Vector2.LEFT, 0, true)
		game.target._react_to_input(STEP)
		respected_floor = respected_floor and game.target.roam_speed_factor >= 0.999
	check(respected_floor and game.target.reaction_count > 20, "input reactions respect full-speed preset")
	game._set_preference("reactive_bot", false)
	game.target._react_to_input(STEP)
	check(not game.target.aim_model.instant_read and game.target.predictor.observed_at < 0,
		"turning input response off disables experiments")
	game.pause_training()


func _test_live_patterns() -> void:
	var rows: Array = []
	for index in range(1, 5):
		game._set_preference("movement_preset", index)
		game._set_preference("roaming", false)
		game._set_preference("strafe_extent", 5)
		game._set_preference("move_speed", 4.5)
		game.player.reset_at(Vector3.ZERO)
		game.target.reset_at(Vector3(0, 0.02, -12), 1007)
		var idle := 0
		var maximum := 0.0
		var minimum := INF
		for tick in 1200:
			await physics_frame
			game.target.bot_step(game.player, STEP, false)
			trace.append([index, tick, game.target.position.x, game.target.position.y, game.target.position.z,
				game.target.velocity.x, game.target.velocity.y, game.target.velocity.z,
				game.target.strafe_direction, game.target.pattern.pause_left, game.target.pattern.distance_left,
				game.target.aim_direction.x, game.target.aim_direction.y, game.target.aim_direction.z])
			var speed := Vector2(game.target.velocity.x, game.target.velocity.z).length()
			idle += int(speed < 0.1)
			maximum = maxf(maximum, speed)
			minimum = minf(minimum, speed)
		rows.append({"preset": index, "turns": game.target.turn_count, "idle": idle, "max": maximum, "min": minimum})
		check(maximum <= 4.501, "custom step engine obeys speed cap")
	check(rows[1].turns > rows[0].turns * 2, "short preset actually changes direction more frequently than long")
	check(rows[0].idle < 3 and rows[1].idle < 3 and rows[2].idle < 3, "continuous presets do not inject pauses")
	check(rows[3].idle > 20, "noncontinuous preset inserts physical pauses")
	check(rows[2].min < rows[2].max * 0.6, "irregular preset has observable speed variation")
	print("FOOTWORK_ROWS ", rows)
	game._set_preference("movement_preset", 3)
	game._set_preference("pause_chance", 100)
	game._set_preference("roaming", true)
	game.target.reset_at(Vector3(0, 0.02, -2), 1007)
	await physics_frame
	game.target.bot_step(game.player, STEP, false)
	check(game.target.spacing_out and game.target.velocity.z < 0, "spacing outranks scheduled pause")


func _test_prediction_effect() -> void:
	var bot: Node3D = game.target
	game._set_preference("reactive_bot", true)
	game._set_preference("bot_perception", false)
	game._set_preference("reaction_strength", 0)
	for mode in [2, 3]:
		game._set_preference("input_mode", mode)
		game._set_preference("prediction_strength", 100)
		for tick in 81:
			var side := 1 if int(tick / 10) % 2 == 0 else -1
			bot.predictor.observe({"sample_at": tick * 0.05, "local_move": Vector2(side, 0),
				"move": Vector3(side, 0, 0), "velocity": Vector3(side * 4, 0, 0),
				"yaw": 0.0, "speed_limit": 10.0, "fire": false})
		bot.reaction_clock = 4.4
		bot._react_to_input(STEP)
		check(bot.aim_model.intent_weight > 0, "prediction mode feeds aim compensation")
		var base := preload("res://scripts/actors/bot_aim.gd").new()
		var predicted := preload("res://scripts/actors/bot_aim.gd").new()
		predicted.intent_velocity = bot.aim_model.intent_velocity
		predicted.intent_weight = bot.aim_model.intent_weight
		var difference := 0.0
		for tick in 60:
			var point := Vector3(tick * STEP * 4, 1, -12)
			difference = base._observe(point, STEP, 180, true).distance_to(
				predicted._observe(point, STEP, 180, true))
		check(difference > 0.01, "prediction changes actual delayed aim point")
		game._set_preference("prediction_strength", 0)
		bot._react_to_input(STEP)
		check(bot.aim_model.intent_weight == 0, "zero strength removes predictive aim influence")
	game._set_preference("reactive_bot", false)


func _screenshots() -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.pause_training()
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		for tab in ["Bot", "玩家"]:
			game.hud.hide_review()
			game.hud.set_paused(true)
			game.hud.tabs.current_tab = game.hud.tabs.get_children().find(game.hud.tabs.get_node(tab))
			for frame in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/options-%s-%dx%d.png" % [tab, size.x, size.y])
			if tab == "Bot":
				var help: Label = game.hud.help_markers.input_mode
				var popup := PopupPanel.new()
				root.add_child(popup)
				var tooltip: Label = help._make_custom_tooltip(help.tooltip_text)
				popup.add_child(tooltip)
				popup.popup(Rect2i(70, 160, 420, 40))
				for frame in 5:
					await process_frame
				await RenderingServer.frame_post_draw
				check(tooltip.get_line_count() > 1 and tooltip.size.x <= 401,
					"long parameter tooltip wraps at bounded width")
				root.get_texture().get_image().save_png("res://artifacts/options-help-%dx%d.png" % [size.x, size.y])
				popup.queue_free()
				await process_frame
		game.hud.show_review(rich_report)
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		check(game.hud.review_panel.visible and not game.hud.panel.visible, "review is sole foreground panel")
		root.get_texture().get_image().save_png("res://artifacts/options-review-%dx%d.png" % [size.x, size.y])
