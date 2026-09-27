extends SceneTree

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func _run() -> void:
	_test_weapon()
	_test_input()
	_test_movement()
	_test_clock()
	_test_lifesteal()
	print("TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _test_weapon() -> void:
	var weapon := LgWeapon.new()
	for tick in 7200:
		if weapon.is_due(tick, true):
			weapon.record_hit()
	check(weapon.shots == 1200, "60s continuous LG: 1200 shots")
	check(weapon.damage == 6000, "60s continuous LG: 6000 damage")
	weapon.reset()
	for tick in 1200:
		if weapon.is_due(tick, true):
			weapon.record_hit()
	check(weapon.damage == 1000, "10 seconds perfect fire: 1000 damage")
	weapon.reset()
	for tick in 120:
		weapon.is_due(tick, tick % 2 == 0)
	check(weapon.shots == 20, "tapping cannot bypass cooldown")
	check(not weapon.is_due(118, true), "same/earlier tick cannot fire twice")
	check(weapon.is_due(999, true), "idle resume emits one event")
	check(not weapon.is_due(999, true), "idle resume never catches up damage")
	weapon.reset()
	check(weapon.shots == 0 and weapon.damage == 0 and weapon.next_shot_tick == 0, "weapon reset")


func _test_input() -> void:
	var input := PlayerInput.new()
	for i in 100:
		var motion := InputEventMouseMotion.new()
		motion.screen_relative = Vector2(10, 0)
		input.ingest(motion, i * 100)
	input.consume(20000)
	check(absf(rad_to_deg(input.yaw) + 22) < 0.01, "mouse increments are not multiplied by delta")
	check(absf(input.yaw - input.preview_yaw) < 0.00001, "camera preview does not double motion")
	var yaw := input.yaw
	input.consume(30000)
	check(input.yaw == yaw, "mouse increments consumed once")
	input.clear(true)
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(1000, 0)
	input.ingest(motion, 100)
	input.consume(99)
	check(input.yaw == 0, "new input does not backfill old ticks")
	input.consume(100)
	check(absf(rad_to_deg(input.yaw) + 22) < 0.01, "batching preserves total angle")
	check(absf(PlayerInput.horizontal_fov(90, 1) - 90) < 0.01, "FOV square aspect")
	check(absf(PlayerInput.horizontal_fov(75, 16.0 / 9) - 107.5124) < 0.01, "FOV 16:9")
	input.clear()
	check(input.queue.is_empty() and not input.firing, "pause clears pending input")


func _test_movement() -> void:
	var normal: MovementProfile = load("res://resources/movement/normal.tres")
	var advanced: MovementProfile = load("res://resources/movement/advanced.tres")
	var velocity := ArenaActor.integrate_velocity(Vector3.ZERO, Vector3.ZERO, true, true, normal, 1.0 / 120)
	check(velocity.y <= 0, "normal mode cannot jump")
	velocity = ArenaActor.integrate_velocity(Vector3.ZERO, Vector3.ZERO, true, true, advanced, 1.0 / 120)
	check(absf(velocity.y - advanced.jump_speed) < 0.00001, "advanced mode jumps")
	velocity = ArenaActor.integrate_velocity(Vector3(0, 2, -8), Vector3.RIGHT, false, false, advanced, 1.0 / 120)
	check(velocity.x > 0 and velocity.z == -8, "air control preserves forward momentum")
	var stopped := ArenaActor.integrate_velocity(Vector3(8, 0, 0), Vector3.ZERO, true, false, normal, 1.0 / 120)
	var drifting := ArenaActor.integrate_velocity(Vector3(8, 0, 0), Vector3.ZERO, true, false, advanced, 1.0 / 120)
	check(stopped.x < drifting.x, "normal brakes faster than advanced")
	velocity = Vector3.ZERO
	for i in 7200:
		velocity = ArenaActor.integrate_velocity(velocity, Vector3.RIGHT, false, false, advanced, 1.0 / 120)
	check(Vector2(velocity.x, velocity.z).length() <= advanced.speed_limit, "air speed bounded")


func _test_clock() -> void:
	var clock := SimulationClock.new()
	clock.reset(0)
	check(clock.guard_frame(50000, 1), "50ms frame may catch up")
	clock.reset(0)
	check(clock.guard_frame(100000, 1), "100ms isolated stall may catch up")
	clock.reset(0)
	check(not clock.guard_frame(250000, 1), "250ms stall pauses before simulation")
	clock.reset(0)
	check(not clock.guard_frame(500000, 1), "500ms stall pauses before simulation")
	clock.reset(0)
	check(clock.guard_frame(120000, 1), "backlog sample 1")
	check(clock.guard_frame(140000, 2), "backlog sample 2")
	check(not clock.guard_frame(160000, 3), "persistent backlog pauses")
	clock.tick = 120
	clock.invalid = false
	clock.rebase(10000000)
	check(abs(clock.deadline_usec() - 10008333) <= 1, "resume rebases clock without replay")


func _test_lifesteal() -> void:
	var bot := preload("res://scripts/actors/static_target.gd").new()
	bot.health = 900
	bot.heal(5)
	check(bot.health == 905, "bot heals from a hit")
	bot.heal(1000)
	check(bot.health == 1000, "bot healing is capped")
	bot.take_damage(5, 1)
	check(bot.health == 995, "bot damage reduces health")
	bot.free()
