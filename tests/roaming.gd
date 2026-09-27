extends Node

var game: Node3D
var bot: Node3D
var steps := 0
var cap := 60
var failures := 0
var checks := 0
var minimum_distance := INF
var maximum_distance := 0.0
var min_x := INF
var max_x := -INF
var min_z := INF
var max_z := -INF
var max_speed := 0.0
var max_height := 0.0
var behind_ticks := 0
var tactics: Dictionary = {}
var trace: Array = []
var escaped := false
var min_separation := INF
var last_tangent_sign := 0.0
var actual_reversals := 0
var max_angular_run := 0.0


func _ready() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	bot = game.target
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cap="):
			cap = int(arg.trim_prefix("--cap="))
	Engine.max_fps = cap
	game.player.reset_at(Vector3(0, 0, 0))
	bot.reset_at(Vector3(0, 0, -11), 41837)
	check(bot.roaming_enabled, "new sessions default to roaming")


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", message)


func _physics_process(delta: float) -> void:
	steps += 1
	game.player.simulate(Vector2.ZERO, 0, false, delta)
	bot.bot_step(game.player, delta, steps > 2880)
	var distance: float = Vector2(bot.position.x - game.player.position.x, bot.position.z - game.player.position.z).length()
	max_speed = maxf(max_speed, Vector2(bot.velocity.x, bot.velocity.z).length())
	min_separation = minf(min_separation, distance)
	if steps <= 2880:
		minimum_distance = minf(minimum_distance, distance)
		maximum_distance = maxf(maximum_distance, distance)
		min_x = minf(min_x, bot.position.x)
		max_x = maxf(max_x, bot.position.x)
		min_z = minf(min_z, bot.position.z)
		max_z = maxf(max_z, bot.position.z)
		behind_ticks += int(bot.position.z > 2.0)
		tactics[bot.tactic] = true
		var radial: Vector3 = (game.player.position - bot.position).normalized()
		var tangential_speed: float = bot.velocity.dot(Vector3(-radial.z, 0, radial.x))
		if absf(tangential_speed) > 0.8:
			var direction := signf(tangential_speed)
			actual_reversals += int(last_tangent_sign != 0.0 and direction != last_tangent_sign)
			last_tangent_sign = direction
		max_angular_run = maxf(max_angular_run, bot.angular_run)
	else:
		max_height = maxf(max_height, bot.position.y)
	escaped = escaped or absf(bot.position.x) > 17.8 or absf(bot.position.z) > 15.8 or bot.position.y < -0.1
	trace.append([steps, bot.position.x, bot.position.y, bot.position.z,
		bot.velocity.x, bot.velocity.y, bot.velocity.z, bot.aim_direction.x,
		bot.aim_direction.y, bot.aim_direction.z, bot.tactic_count, bot.jumps])
	if steps == 2880:
		check(tactics.size() == 3, "close retreat and orbit all occur")
		check(minimum_distance < 6.0 and maximum_distance > 9.0, "bot changes engagement distance")
		# Short reversible arcs need not sweep equally far on both world axes.
		var span := Vector2(max_x - min_x, max_z - min_z)
		check(maxf(span.x, span.y) > 7 and minf(span.x, span.y) > 3.5,
			"roaming covers a broad area without requiring long uninterrupted orbits")
		check(actual_reversals >= 20 and max_angular_run < PI,
			"roaming physically reverses often without sustained half-circle runs")
	if steps == 3600:
		check(bot.jumps >= 3 and max_height > 0.8, "advanced roaming retains repeated jumps")
		bot.reset_at(Vector3(16.5, 0, 12), 48211)
		game.player.reset_at(Vector3(14, 0, 10))
	if steps == 4320:
		check(not escaped, "wall avoidance and collision keep bot inside arena")
		check(min_separation > 0.5, "bot does not pass through player")
		check(max_speed <= 4.501, "diagonal roaming respects scalar speed cap")
		var file := FileAccess.open("res://artifacts/roaming-%d.json" % cap, FileAccess.WRITE)
		file.store_string(JSON.stringify({
			"checks": checks, "failures": failures, "cap": cap, "min_distance": minimum_distance,
			"max_distance": maximum_distance, "span_x": max_x - min_x, "span_z": max_z - min_z,
			"behind_ticks": behind_ticks, "max_speed": max_speed, "max_height": max_height,
			"actual_reversals": actual_reversals, "max_angular_run": max_angular_run,
			"trace": trace
		}))
		file.close()
		print("ROAMING_RESULT cap=%d checks=%d failures=%d distance=%.2f..%.2f span=%.2f/%.2f behind=%d" % [
			cap, checks, failures, minimum_distance, maximum_distance, max_x - min_x, max_z - min_z, behind_ticks])
		get_tree().quit(1 if failures else 0)
