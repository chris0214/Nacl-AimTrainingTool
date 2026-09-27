extends SceneTree

const AUDIO = preload("res://scripts/combat/hit_audio.gd")
const PREFS = preload("res://scripts/input/trainer_settings.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node3D
var native := false


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	native = DisplayServer.get_name() != "headless"
	_test_pcm()
	_test_persistence()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.pause_training()
	_test_controls()
	await _test_scene()
	await _test_combat_audio()
	if native:
		await _test_audio_mix()
	game.queue_free()
	await process_frame
	print("COMBAT_ATMOSPHERE_RESULT native=%s checks=%d failures=%d" % [native, checks, failures])
	quit(1 if failures else 0)


func _test_pcm() -> void:
	var buffers: Array = []
	for style in 3:
		var clip := AUDIO.make_clip(style)
		check(clip.format == AudioStreamWAV.FORMAT_16_BITS and clip.mix_rate == 44100
			and not clip.stereo and clip.get_length() > 0.03 and clip.get_length() < 0.05, "PCM format and duration")
		var peak := 0.0
		var square := 0.0
		for index in clip.data.size() / 2:
			var value := clip.data.decode_s16(index * 2) / 32768.0
			peak = maxf(peak, absf(value))
			square += value * value
		var rms := sqrt(square / (clip.data.size() / 2))
		check(peak < 0.7 and rms > 0.02, "audible non-clipping waveform")
		check(clip.data.decode_s16(0) == 0 and abs(clip.data.decode_s16(clip.data.size() - 2)) < 4,
			"bounded attack and release")
		check(not clip.data in buffers, "distinct sound styles")
		buffers.append(clip.data)
		check(clip.save_to_wav("res://artifacts/hit-sound-%d.wav" % style) == OK, "preview WAV export")


func _test_persistence() -> void:
	var settings := PREFS.new()
	settings.path = "res://artifacts/atmosphere-settings.cfg"
	var values := {"sky_style": 2, "arena_style": 1, "floor_grid": false, "scene_brightness": 123.0,
		"hit_sound": false, "hit_sound_style": 2, "hit_volume": 31.0, "aim_level": 72.0}
	for item in values:
		settings.put(item, values[item])
	check(settings.save_settings() == OK, "new preferences save")
	var loaded := PREFS.new()
	loaded.path = settings.path
	loaded.load_settings()
	for key in values:
		check(loaded.values[key] == values[key], "preference round trip: " + key)
	check(absf(loaded.values.cm360 - settings.values.cm360) < 0.000001, "mouse precision preserved")
	for key in ["sky_style", "arena_style", "hit_sound_style"]:
		var original: int = loaded.values[key]
		loaded.put(key, 99)
		loaded.put(key, 0.5)
		loaded.put(key, NAN)
		check(loaded.values[key] == original, "invalid enum rejected: " + key)
	loaded.put("hit_volume", 200)
	loaded.put("scene_brightness", 0)
	check(loaded.values.hit_volume == 100 and loaded.values.scene_brightness == 50, "numeric limits")


func _test_controls() -> void:
	var controls: Dictionary = game.hud.preference_controls
	check(game.hud.tabs.get_tab_count() == 5, "new tab appended without reordering")
	for key in ["sky_style", "arena_style", "hit_sound_style"]:
		controls[key].item_selected.emit(2)
		check(game.preferences.values[key] == 2, "choice reaches preferences: " + key)
	controls.hit_volume.value = 27
	check(game.hit_audio.level == 27 and is_equal_approx(game.hit_audio.volume_db, linear_to_db(0.27)),
		"volume control reaches real player gain")
	controls.hit_sound.button_pressed = false
	var count: int = game.hit_audio.played_events
	game.hud.hit_sound_preview.emit()
	check(game.hit_audio.played_events == count, "muted preview stays silent")
	controls.hit_sound.button_pressed = true
	game.hud.hit_sound_preview.emit()
	check(game.hit_audio.played_events == count + 1, "preview plays chosen clip")
	game.hit_audio.confirmed_hit(0)
	check(game.hit_audio.played_events == count + 1, "zero damage produces no audio")
	game._set_preference("hit_volume", 0)
	game.hit_audio.confirmed_hit(5)
	check(game.hit_audio.played_events == count + 1, "zero volume does not play")
	game._set_preference("hit_volume", 45)
	game.hud.preference_controls.scene_brightness.value = 120
	check(is_equal_approx(game.get_node("Arena/Sun").light_energy, 0.72), "brightness reaches light")


func _test_scene() -> void:
	var arena: Node3D = game.get_node("Arena")
	check(arena.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		and arena.environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED,
		"sky does not alter target ambient or reflection")
	var shape: Shape3D = arena.get_node("Floor/Collision").shape
	var size: Vector3 = shape.size
	var start: Vector3 = arena.get_node("PlayerSpawn").position
	check(size == Vector3(36, 1, 32) and start == Vector3(0, 0.02, 7)
		and arena.get_node("TargetSpawn").position == Vector3(0, 0, -4),
		"minimal arena preserves original dimensions and spawns")
	for wall in ["BackWall", "FrontWall", "LeftWall", "RightWall"]:
		check(arena.get_node(wall) is StaticBody3D
			and arena.get_node(wall).get_child(1) is CollisionShape3D,
			"minimal arena keeps solid boundary: " + wall)
	for decoration in ["BackRib*", "Lane*", "DistanceMark*"]:
		check(arena.find_children(decoration, "", true, false).is_empty(),
			"minimal arena removes decoration: " + decoration)
	for preset in 3:
		game._set_preference("sky_style", preset)
		game._set_preference("arena_style", preset)
		check(arena.environment.background_mode == (Environment.BG_COLOR if preset == 0 else Environment.BG_SKY),
			"sky mode applied")
		check(arena.environment.sky == (null if preset == 0 else arena.skies[preset - 1]), "sky resource applied")
		check(arena.find_children("*", "Label3D", true, false).is_empty(),
			"arena stays text-free in every appearance preset")
		check(arena.get_node("Floor/Collision").shape == shape and shape.size == size
			and arena.get_node("PlayerSpawn").position == start, "appearance preserves collision and spawn")
		await physics_frame
		if native:
			await RenderingServer.frame_post_draw
		var floor_ray := PhysicsRayQueryParameters3D.create(Vector3(0, 4, 0), Vector3(0, -2, 0), 1)
		check(not arena.get_world_3d().direct_space_state.intersect_ray(floor_ray).is_empty(), "floor remains solid")
	game._set_preference("floor_grid", false)
	check(arena.floor_material.get_shader_parameter("grid_enabled") == false, "grid toggle updates shader")
	var cached: Array = arena.skies.duplicate()
	for cycle in 50:
		game._set_preference("sky_style", 1 + cycle % 2)
		game._set_preference("scene_brightness", 80 + cycle)
	check(arena.skies == cached, "repeated appearance changes reuse sky resources")
	var second := preload("res://scenes/arena/flat_arena.tscn").instantiate()
	root.add_child(second)
	check(second.environment != arena.environment and second.floor_material != arena.floor_material,
		"appearance resources are instance-local")
	second.queue_free()
	await process_frame


func _combat_start(firing: bool, yaw: float, attacking: bool) -> void:
	game._set_preference("attack", attacking)
	game._set_preference("move_speed", 0)
	game._set_preference("aim_level", 100)
	game.reset_training()
	game.ready_to_start = false
	game.input.correct_view(yaw, 0)
	if firing:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		game.input.ingest(event, Time.get_ticks_usec())


func _combat_ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		game.clock.rebase(Time.get_ticks_usec())
		game._physics_process(STEP)


func _test_combat_audio() -> void:
	_combat_start(true, 0, false)
	var events: int = game.hit_audio.played_events
	await _combat_ticks(30)
	check(game.weapon.hits == 5 and game.target.health == 975, "real ray causes expected damage")
	check(game.hit_audio.played_events - events == game.weapon.hits, "one sound per outgoing confirmed hit")
	game.pause_training()
	check(not game.hit_audio.playing, "pause stops hit audio")
	_combat_start(true, PI, false)
	events = game.hit_audio.played_events
	await _combat_ticks(30)
	check(game.weapon.shots == 5 and game.weapon.hits == 0 and game.hit_audio.played_events == events,
		"misses do not sound")
	_combat_start(false, 0, true)
	events = game.hit_audio.played_events
	await _combat_ticks(60)
	check(game.bot_weapon.hits >= 9 and game.player_health < 1000
		and game.hit_audio.played_events == events, "incoming hits do not trigger outgoing sound")
	game.hit_audio.confirmed_hit(5)
	game.reset_training()
	check(not game.hit_audio.playing, "restart stops hit audio")


func _test_audio_mix() -> void:
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "HitVerification")
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus, capture)
	game.hit_audio.bus = "HitVerification"
	game._set_preference("hit_sound", true)
	game._set_preference("hit_volume", 45)
	game.hit_audio.confirmed_hit(5)
	await create_timer(0.15).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	check(frames.size() > 0 and peak > 0.01 and peak < 0.7, "native mixer receives bounded nonzero sound")
	print("NATIVE_AUDIO_MIX frames=", frames.size(), " peak=", peak, " driver=", AudioServer.get_driver_name())
	game.hit_audio.stop()
	game.hit_audio.bus = "Master"
	AudioServer.remove_bus(bus)
