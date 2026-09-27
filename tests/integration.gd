extends Node

var game: Node3D
var steps: int = 0
var checks: int = 0
var failures: int = 0
var paused_position: Vector3
var paused_tick: int
var paused_damage: int


func _ready() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	add_child(game)


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func fire(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _physics_process(_delta: float) -> void:
	steps += 1
	match steps:
		30:
			check(game.player.is_on_floor(), "actor settles on real floor")
			var ray: Dictionary = game.weapon.trace(game.get_world_3d().direct_space_state, game.player.eye_position(), Vector3.FORWARD)
			check(not ray.is_empty() and ray.collider == game.target, "real ray hits target")
			var blocked: Dictionary = game.weapon.trace(game.get_world_3d().direct_space_state, Vector3(0, 1.6, 20), Vector3.FORWARD)
			check(not blocked.is_empty() and blocked.collider != game.target, "wall blocks shot")
			var distant: Dictionary = game.weapon.trace(game.get_world_3d().direct_space_state, Vector3(0, 1.6, 50), Vector3.FORWARD)
			check(distant.is_empty(), "finite LG range")
			fire(true)
		65:
			check(game.weapon.hits > 0 and game.weapon.damage == game.weapon.hits * LgWeapon.DAMAGE, "input path causes actual ray damage")
			fire(false)
			key(KEY_W, true)
		95:
			check(game.player.position.z < 6.9, "W moves actor through input adapter")
			key(KEY_W, false)
			key(KEY_SPACE, true)
		100:
			key(KEY_SPACE, false)
		110:
			check(game.player.position.y < 0.02, "normal jump disabled in scene")
			var motion := InputEventMouseMotion.new()
			motion.screen_relative = Vector2(1000, 0)
			Input.parse_input_event(motion)
		115:
			check(absf(rad_to_deg(game.input.yaw) + 22) < 0.01, "mouse event updates view exactly once")
		120:
			game.hud.mode_changed.emit(true)
		150:
			check(game.player.profile.advanced and game.weapon.shots == 0, "mode UI signal resets training")
			key(KEY_SPACE, true)
		155:
			key(KEY_SPACE, false)
			key(KEY_D, true)
		180:
			check(game.player.position.y > 0.6, "advanced jump raises actor")
			check(game.player.velocity.x > 0.1, "air steering changes actor velocity")
		185:
			fire(true)
		190:
			key(KEY_D, false)
			game.pause_training()
			paused_position = game.player.position
			paused_tick = game.clock.tick
			paused_damage = game.weapon.damage
			fire(true)
			key(KEY_W, true)
		220:
			check(game.player.position == paused_position, "pause freezes actor")
			check(game.clock.tick == paused_tick and game.weapon.damage == paused_damage, "pause freezes time and damage")
			check(game.input.queue.is_empty(), "paused input is discarded")
			game.hud.fov_changed.emit(85)
			game.hud.sensitivity_changed.emit(0.03)
			game.hud.frame_limit_changed.emit(120)
			check(game.camera.fov == 85 and is_equal_approx(game.input.sensitivity, 0.03) and Engine.max_fps == 120, "settings signals update live values")
			game.hud.resumed.emit()
		240:
			check(not game.input.firing and not game.paused, "resume does not replay paused fire")
			game.hud.restarted.emit()
		270:
			check(game.weapon.shots == 0 and game.clock.tick == 0 and game.ready_to_start, "restart clears score and clock")
			key(KEY_D, true)
		900:
			check(game.player.position.x > 16 and game.player.position.x < 17.4, "wall collision prevents escape")
			key(KEY_D, false)
			game.pause_training()
			check(game.hud.panel.visible, "pause panel visible")
		905:
			var buttons: Array[Node] = game.hud.panel.find_children("*", "Button", true, false)
			for button in buttons:
				if button.text == "继续练习":
					button.emit_signal("pressed")
		915:
			check(not game.paused, "resume button callback responds")
			print("INTEGRATION_RESULT checks=%d failures=%d" % [checks, failures])
			get_tree().quit(1 if failures else 0)
