extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
const SCORE = preload("res://scripts/combat/training_score.gd")
const AIM = preload("res://scripts/actors/bot_aim.gd")
const FLANK = preload("res://scripts/actors/flank_controller.gd")
var checks := 0
var failures := 0
var game: Node3D
var score_totals: Array[float] = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	var prefs := PREFS.new()
	prefs.put("simulation_hz", 360)
	prefs.put("ad_bonus_weight", 15)
	prefs.path = "res://artifacts/hz-score-settings.cfg"
	check(prefs.save_settings() == OK, "settings save")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	check(loaded.values.simulation_hz == 360 and loaded.values.ad_bonus_weight == 15, "settings reload")
	for invalid in [0, 121, 240.5, NAN, INF, "240", true]:
		loaded.put("simulation_hz", invalid)
		check(loaded.values.simulation_hz == 360, "unsupported frequency rejected")
	for hz in SimulationClock.RATES:
		_test_clock_weapon(hz)
		_test_delay(hz)
		_test_scoring(hz)
	check(score_totals.max() - score_totals.min() < 0.25, "movement bonus agrees across simulation rates")
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	game.pause_training()
	game._set_preference("hit_sound", false)
	game._set_preference("armor_sound", false)
	game._set_preference("attack", false)
	game._set_preference("move_speed", 0)
	for hz in SimulationClock.RATES:
		await _live(hz)
	if DisplayServer.get_name() != "headless":
		game.pause_training()
		for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
			root.size = size
			for tab in [2, 3]:
				game.hud.tabs.current_tab = tab
				for frame in 8:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/hz-score-%d-%dx%d.png" % [tab, size.x, size.y])
	game.queue_free()
	await process_frame
	Engine.physics_ticks_per_second = 120
	print("SIMULATION_SCORING_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_clock_weapon(hz: int) -> void:
	var clock := SimulationClock.new()
	clock.hz = hz
	clock.reset(1000000)
	check(clock.deadline_usec() == 1000000 + int(1000000.0 / hz), "rate-scaled input deadline")
	var gun := LgWeapon.new()
	gun.interval_ticks = hz / 20
	for tick in hz * 60:
		if gun.is_due(tick, true):
			gun.record_hit()
	check(gun.shots == 1200 and gun.damage == 6000, "60 seconds retains 20 shots/s and 100 damage/s")
	clock.tick = hz * 60
	clock.rebase(90000000)
	check(absi(clock.deadline_usec() - (90000000 + int(1000000.0 / hz))) <= 1, "pause rebase preserves seconds")
	check(not gun.is_due(hz * 61, false), "idle does not fire")
	var before := gun.shots
	check(gun.is_due(hz * 62, true) and gun.shots == before + 1, "resume never bursts missed shots")


func _test_delay(hz: int) -> void:
	var model := AIM.new()
	var flank := FLANK.new()
	var settings := preload("res://scripts/actors/bot_settings.gd").new()
	var dt := 1.0 / hz
	settings.reaction_delay = 600
	for tick in hz:
		var at := (tick + 1) * dt
		model._observe(Vector3(at, 0, 0), dt, 340, true)
		flank.observe(0, 0.6)
		flank.step(Vector3.FORWARD, 12, settings, false, dt)
	check(model.perceived_at > 0.65 and model.perceived_at < 0.67, "340ms aim observations survive high-rate buffer")
	check(flank.has_view and flank.views.size() <= 256, "600ms flank observations survive high-rate buffer")


func _score_case(hz: int, kind: String, weight: float = 10) -> Dictionary:
	var scoring := SCORE.new()
	scoring.reset({"ad_bonus_weight": weight})
	var dt := 1.0 / hz
	for tick in hz * 3:
		var side := 1.0 if int(tick / (hz / 2)) % 2 == 0 else -1.0
		var motion := Vector3(side * 10 * dt, 0, 0)
		var move := Vector2(side, 0)
		if kind == "jitter":
			move.x = 1 if tick % 2 == 0 else -1
			motion.x = move.x * 10 * dt
		if kind in ["idle", "wall"]:
			motion = Vector3.ZERO
		if kind == "idle":
			move = Vector2.ZERO
		if kind == "forward":
			motion = Vector3(0, 0, -10 * dt)
			move = Vector2(0, -1)
		if kind == "teleport":
			motion = Vector3(5, 0, 0)
		scoring.sample({"move": move, "yaw": 0, "displacement": motion,
			"speed_limit": 10, "visible": kind != "occluded", "firing": kind != "no_fire",
			"shot": tick % (hz / 20) == 0 and kind != "no_fire",
			"outgoing": 0 if kind == "miss" else 5, "assisted": kind == "assist"}, dt)
	return scoring.result()


func _test_scoring(hz: int) -> void:
	var moving := _score_case(hz, "moving")
	score_totals.append(moving.bonus)
	check(moving.base == 300 and moving.bonus > 25 and moving.bonus <= 30, "small capped AD reward on actual hits")
	for kind in ["idle", "wall", "jitter", "forward", "teleport", "occluded", "no_fire", "miss"]:
		check(_score_case(hz, kind).bonus == 0, kind + " never earns AD bonus")
	check(_score_case(hz, "moving", 0).bonus == 0, "zero disables bonus")
	check(is_equal_approx(_score_case(hz, "moving", 20).bonus, moving.bonus * 2), "weight scales bonus only")
	check(not _score_case(hz, "assist").valid, "assisted score excluded")
	var score := SCORE.new()
	score.reset({})
	score.base = 100
	score.bonus = 5
	score.discontinuity()
	check(score.base == 100 and score.bonus == 5 and score.run_distance == 0, "pause retains score but clears movement history")
	score.reset({})
	check(score.base == 0 and score.bonus == 0, "round reset clears score")
	print("HZ_SCORE hz=%d base=%.1f bonus=%.6f" % [hz, moving.base, moving.bonus])


func _live(hz: int) -> void:
	game.pause_training()
	game.hud.preference_controls.simulation_hz.item_selected.emit(SimulationClock.RATES.find(hz))
	await process_frame
	check(game.paused, "frequency switch retains pause")
	check(game.clock.hz == hz and Engine.physics_ticks_per_second == hz, "UI sets actual physics rate")
	check(game.weapon.interval_ticks == hz / 20 and game.bot_weapon.interval_ticks == hz / 20, "both guns use same rate")
	check(Engine.max_physics_steps_per_frame == 16 * hz / 120, "catch-up budget scales with rate")
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -10), 12)
	game.input.correct_view(0, atan2(0.91 - ArenaActor.EYE_HEIGHT, 10))
	game.input.firing = true
	game.ready_to_start = false
	for tick in hz * 3:
		await physics_frame
		game.clock.rebase(Time.get_ticks_usec())
		game._physics_process(1.0 / hz)
	print("HZ_LIVE hz=%d shots=%d hits=%d health=%d time=%.6f" % [
		hz, game.weapon.shots, game.weapon.hits, game.target.health, game.round_time])
	check(game.weapon.shots == 60 and game.weapon.hits == 60, "live shots independent of Hz")
	check(game.target.health == 700 and game.review.score.base == 300, "live damage and score agree")
	check(game.review.score.bonus == 0, "live stationary player gets no bonus")
	check(is_equal_approx(game.round_time, 3), "live clock retains wall-time units")
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -10), 12)
	game.input.firing = true
	game.ready_to_start = false
	for tick in hz * 2:
		await physics_frame
		game.clock.rebase(Time.get_ticks_usec())
		game.input.held[KEY_D] = int(tick / (hz / 2)) % 2 == 0
		game.input.held[KEY_A] = not game.input.held[KEY_D]
		var offset: Vector3 = game.target.position + Vector3.UP * 0.91 - game.player.eye_position()
		game.input.correct_view(atan2(-offset.x, -offset.z), atan2(offset.y, Vector2(offset.x, offset.z).length()))
		game._physics_process(1.0 / hz)
	check(game.review.score.bonus > 0 and game.review.score.bonus <= game.review.score.base * 0.1,
		"live displacement and actual damage award bounded AD bonus")
	game.hud.update_training_score(game.review.score.result())
	check(game.hud.training_score_label.text.contains("走位 +"), "HUD includes bonus")
	game._manual_review()
	check(game.last_review.score.bonus > 0 and game.hud.review_panel.summary.text.contains("积分"),
		"round review displays actual bonus")
	game.hud.hide_review()
	game.hud.update_state(false, "", 0, game.weapon, 0, false, 0)
	check(game.hud.performance_label.text.contains("%d Hz" % hz), "HUD shows actual rate")
	game.pause_training()
	game._set_preference("ad_bonus_weight", 15)
	await process_frame
	check(game.review.score.weight == 15, "bonus setting reaches scoring rules")
	game._set_preference("ad_bonus_weight", 10)
	await process_frame
