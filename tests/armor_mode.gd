extends SceneTree

const RULES = preload("res://scripts/combat/duel_rules.gd")
const PREFS = preload("res://scripts/input/trainer_settings.gd")
const AUDIO = preload("res://scripts/combat/armor_audio.gd")
const STEP := 1.0 / 120.0
var checks := 0
var failures := 0
var game: Node3D
var trace: Array = []


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	_rules()
	_preferences()
	_audio_pcm()
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.pause_training()
	game._set_preference("hit_sound", false)
	game._set_preference("armor_sound", false)
	await _controls()
	await _outgoing()
	await _incoming()
	await _feedback()
	await _screenshots()
	game.armor_audio.stop()
	game.hit_audio.stop()
	game.queue_free()
	await process_frame
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	var tag := "native" if DisplayServer.get_name() != "headless" else "120"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cap=") and DisplayServer.get_name() == "headless":
			tag = arg.trim_prefix("--cap=").validate_filename()
	var file := FileAccess.open("res://artifacts/armor-trace-%s.json" % tag, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "trace": trace}))
	file.close()
	print("ARMOR_MODE_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _rules() -> void:
	for pool in [300, 600, 1000]:
		var pure := RULES.vitals(pool, 0, 300)
		var split := RULES.vitals(1000, 1, pool)
		check(pure.health == pool and pure.armor == 0, "pure health unchanged")
		check(split.health + split.armor == pool, "armor mode preserves total durability")
		var hp: int = split.health
		var armor: int = split.armor
		var breaks := 0
		var shots := 0
		while hp > 0:
			var hit := RULES.damage(hp, armor, 5)
			check(hit.dealt == 5, "no damage lost at armor boundary")
			breaks += int(hit.broken)
			hp = hit.health
			armor = hit.armor
			shots += 1
		check(shots * 5 == pool and breaks == 1, "one break per life at original DPS")
	var overflow := RULES.damage(100, 3, 5)
	check(overflow.health == 98 and overflow.armor == 0 and overflow.broken
		and overflow.dealt == 5, "damage overflows armor into health")
	check(not RULES.damage(98, 0, 5).broken, "health hits do not repeat break")
	check(RULES.damage(2, 1, 50).dealt == 3, "overkill lifesteal bounded by remaining durability")
	check(RULES.damage(0, 10, 5).dealt == 0, "dead actor cannot absorb further damage")
	check(RULES.damage(10, 10, -5).dealt == 0 and RULES.damage(10, 10, 0).armor == 10,
		"zero or negative damage cannot heal or break")


func _preferences() -> void:
	var prefs := PREFS.new()
	check(prefs.values.combat_mode == 0 and prefs.values.armor_pool == 300, "old settings opt into no armor")
	prefs.put("health_pool", 600)
	prefs.put("combat_mode", 1)
	prefs.put("armor_pool", 1000)
	prefs.put("armor_volume", 32)
	prefs.put("armor_effect_strength", 70)
	prefs.put("combat_mode", 1.5)
	prefs.put("armor_pool", 450)
	check(prefs.values.combat_mode == 1 and prefs.values.armor_pool == 1000, "invalid modes rejected")
	prefs.path = "res://artifacts/armor-settings.cfg"
	check(prefs.save_settings() == OK, "armor settings save")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	for key in ["health_pool", "combat_mode", "armor_pool", "armor_sound", "armor_volume",
		"armor_effect", "armor_effect_strength"]:
		check(loaded.values[key] == prefs.values[key], "armor field round trip: " + key)
	loaded.put("combat_mode", 0)
	check(loaded.values.health_pool == 600 and loaded.values.armor_pool == 1000, "mode pools remain independent")


func _audio_pcm() -> void:
	var buffers: Array = []
	for side in 2:
		var clip := AUDIO.make_clip(side)
		var peak := 0.0
		var energy := 0.0
		for index in clip.data.size() / 2:
			var value := clip.data.decode_s16(index * 2) / 32768.0
			peak = maxf(peak, absf(value))
			energy += value * value
		check(clip.mix_rate == 44100 and clip.get_length() > 0.15 and clip.get_length() < 0.3,
			"break sound format and bounded length")
		check(peak < 0.85 and sqrt(energy / (clip.data.size() / 2)) > 0.02, "audible nonclipping PCM")
		check(clip.data.decode_s16(0) == 0 and abs(clip.data.decode_s16(clip.data.size() - 2)) < 4, "smooth PCM boundaries")
		check(not clip.data in buffers, "distinct enemy and own break tones")
		buffers.append(clip.data)
		check(clip.save_to_wav("res://artifacts/armor-break-%d.wav" % side) == OK, "break WAV exported")


func _controls() -> void:
	var hud: CanvasLayer = game.hud
	check(hud.tabs.get_tab_count() == 6 and not hud.tabs.has_node("步法")
		and not hud.tabs.has_node("输入实验"), "one Bot tab replaces three tabs")
	for key in ["aim", "movement", "footwork", "input"]:
		check(not hud.bot_sections[key].visible, "advanced Bot group collapsed initially")
	for key in ["movement_preset", "aim_level", "move_speed", "engagement_distance"]:
		check(hud.setting_rows[key].is_visible_in_tree(), "common controls visible first")
	hud.bot_section_buttons.footwork.button_pressed = true
	check(hud.bot_sections.footwork.visible, "disclosure expands")
	var number: SpinBox = hud.preference_controls.step_min
	number.set_meta("draft", "invalid")
	hud.bot_section_buttons.footwork.button_pressed = false
	check(hud.bot_section_buttons.footwork.button_pressed and hud.bot_sections.footwork.visible,
		"invalid draft prevents hiding its group")
	number.remove_meta("draft")
	hud.bot_section_buttons.footwork.button_pressed = false
	check(not hud.bot_sections.footwork.visible, "valid group closes")
	game._set_preference("reactive_bot", false)
	game._set_preference("input_mode", 2)
	check(hud.preference_controls.input_mode.disabled and not hud.preference_controls.prediction_strength.editable,
		"disabled response cannot pretend prediction is active")
	game._set_preference("reactive_bot", true)
	check(not hud.preference_controls.input_mode.disabled and hud.preference_controls.prediction_strength.editable,
		"enabling response unlocks predictions")
	game._set_preference("aim_level", 100)
	check(not hud.bot_controls.aim_turn_rate.editable, "hard lock disables irrelevant turn cap")
	game.change_mode(true)
	check(hud.bot_controls.air_control.editable, "advanced mode enables air control")
	game.change_mode(false)
	check(not hud.bot_controls.air_control.editable, "normal mode disables air control")
	game._set_preference("health_pool", 600)
	await process_frame
	hud.preference_controls.combat_mode.item_selected.emit(1)
	await process_frame
	check(game.round_combat_mode == 1 and game.player_health == 100 and game.player_armor == 200,
		"UI mode activates separate default armor pool")
	check(not hud.setting_rows.health_pool.visible and hud.setting_rows.armor_pool.visible and hud.armor_controls.visible,
		"only active pool and relevant feedback controls shown")
	hud.preference_controls.armor_pool.item_selected.emit(1)
	await process_frame
	check(game.player_health == 200 and game.player_armor == 400 and game.paused, "armor pool UI restarts paused")
	var invalid: SpinBox = hud.preference_controls.armor_volume
	invalid.set_meta("draft", "invalid")
	hud.preference_controls.armor_pool.select(2)
	hud.preference_controls.armor_pool.item_selected.emit(2)
	check(hud.preference_controls.armor_pool.get_selected_id() == 600 and game.preferences.values.armor_pool == 600,
		"rejected pool selection restores item ID rather than treating it as an index")
	invalid.remove_meta("draft")
	var cm: float = game.preferences.values.cm360
	hud._reset_bot_controls()
	check(game.preferences.values.armor_pool == 600 and game.preferences.values.health_pool == 600
		and game.preferences.values.combat_mode == 1 and game.preferences.values.cm360 == cm,
		"Bot reset preserves rule pools and mouse")
	check(game.preferences.values.movement_preset == 0 and game.preferences.values.input_mode == 0,
		"Bot reset includes movement and input models")
	game._set_preference("combat_mode", 0)
	await process_frame
	check(game.player_health == 600 and game.player_armor == 0 and game.target.max_armor == 0,
		"return to pure mode restores its own saved pool")


func _combat_start(attacking: bool, firing: bool) -> void:
	game._set_preference("attack", attacking)
	game._set_preference("move_speed", 0)
	game._set_preference("aim_level", 100)
	game._set_preference("bot_perception", false)
	game._set_preference("armor_sound", true)
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -8), 19)
	game.ready_to_start = false
	game.input.firing = firing


func _tick() -> void:
	await physics_frame
	game.clock.rebase(Time.get_ticks_usec())
	game._physics_process(STEP)


func _outgoing() -> void:
	game._set_preference("combat_mode", 1)
	await process_frame
	for pool in [300, 600, 1000]:
		game._set_preference("armor_pool", pool)
		await process_frame
		_combat_start(false, true)
		game.player_health -= 1
		game.player_armor -= 9
		var events: int = game.armor_audio.played_events[0]
		var count := 0
		while not game.target.dead and count < 1300:
			await _tick()
			trace.append([pool, game.clock.tick, game.player_health, game.player_armor,
				game.target.health, game.target.armor, game.weapon.shots, game.weapon.hits,
				game.bot_weapon.shots, game.bot_weapon.hits, game.armor_audio.played_events[0] - events])
			count += 1
		check(game.target.dead and game.weapon.hits * 5 == pool, "real outgoing ray kills full armor pool")
		check(game.armor_audio.played_events[0] - events == 1, "real outgoing fire breaks armor once")
		check(game.player_health == game.round_health and game.player_armor == game.round_armor - 9,
			"outgoing lifesteal heals only life up to cap")
		check(game.hud.review_panel.visible and game.last_review.settings.combat_mode == 1,
			"armor victory enters review with rules snapshot")
		game.hud.review_panel.next_round.emit()
		check(game.player_armor == game.round_armor and game.target.armor == game.round_armor,
			"new round restores both armor pools")
		game.pause_training()


func _incoming() -> void:
	game._set_preference("armor_pool", 300)
	await process_frame
	_combat_start(true, false)
	game.target.health -= 1
	game.target.armor -= 17
	var events: int = game.armor_audio.played_events[1]
	for tick in 12:
		await _tick()
	check(game.player_health == 100 and game.player_armor < 200 and game.player_armor > 0,
		"enemy actual beam damages armor before life")
	check(game.target.health == 100 and game.target.armor == 183, "enemy lifesteal also cannot refill armor")
	var count := 0
	while game.player_health > 0 and count < 500:
		await _tick()
		count += 1
	check(game.player_health == 0 and game.player_armor == 0 and game.bot_weapon.hits == 60,
		"enemy actual beam exhausts total durability")
	check(game.armor_audio.played_events[1] - events == 1, "one own break sound despite later life hits")
	game.hud.review_panel.next_round.emit()
	game.player_armor = 3
	var hit: Dictionary = game._damage_player(5)
	check(game.player_health == 98 and hit.broken and game.hud.armor_overlay.shattered,
		"overflow hit triggers first-person break effect")
	game.pause_training()
	check(game.hud.armor_overlay.remaining == 0, "pause clears first-person effect")


func _feedback() -> void:
	var audio: Node = game.armor_audio
	game._set_preference("armor_sound", false)
	var count: int = audio.played_events[1]
	game.hud.armor_sound_preview.emit(true)
	check(audio.played_events[1] == count, "sound toggle mutes preview")
	game._set_preference("armor_sound", true)
	game._set_preference("armor_volume", 0)
	game.hud.armor_sound_preview.emit(true)
	check(audio.played_events[1] == count, "zero volume mutes break")
	game._set_preference("armor_effect", false)
	game.hud.armor_overlay.pulse(true)
	check(game.hud.armor_overlay.remaining == 0, "effect disabled")
	game._set_preference("armor_effect", true)
	game._set_preference("armor_effect_strength", 0)
	game.hud.armor_overlay.pulse(true)
	check(game.hud.armor_overlay.remaining == 0, "zero effect strength")
	game._set_preference("armor_effect_strength", 50)
	if DisplayServer.get_name() == "headless":
		return
	game._set_preference("armor_volume", 55)
	var bus := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus, "ArmorVerification")
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus, capture)
	for voice in audio.voices:
		voice.bus = "ArmorVerification"
	for own in [false, true]:
		capture.clear_buffer()
		var before: Array = audio.played_events.duplicate()
		var buttons: HBoxContainer = game.hud.armor_controls.get_child(game.hud.armor_controls.get_child_count() - 1)
		buttons.get_child(int(own)).pressed.emit()
		check(audio.played_events[int(own)] == before[int(own)] + 1
			and audio.played_events[1 - int(own)] == before[1 - int(own)], "preview button selects correct break voice")
		var deadline := Time.get_ticks_msec() + 320
		while Time.get_ticks_msec() < deadline:
			await process_frame
		var frames := capture.get_buffer(capture.get_frames_available())
		var peak := 0.0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		check(frames.size() > 0 and peak > 0.01 and peak < 0.9, "native mixer receives break tone")
		print("ARMOR_AUDIO own=", own, " frames=", frames.size(), " peak=", peak)
	audio.stop()
	for voice in audio.voices:
		voice.bus = "Master"
	AudioServer.remove_bus(bus)


func _capture(path: String) -> Image:
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://artifacts/" + path)
	return image


func _screenshots() -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.reset_training()
	game.pause_training()
	game._process(0)
	for size in [Vector2i(1440, 900), Vector2i(960, 600)]:
		root.size = size
		game.hud.set_paused(true)
		game.hud.tabs.current_tab = 0
		for key in game.hud.bot_section_buttons:
			game.hud.bot_section_buttons[key].button_pressed = false
		await _capture("armor-bot-%dx%d.png" % [size.x, size.y])
		game.hud.bot_section_buttons.input.button_pressed = true
		await _capture("armor-input-%dx%d.png" % [size.x, size.y])
		var input_header: Control = game.hud.bot_section_buttons.input
		var viewport: Control = game.hud.tabs.get_child(0)
		check(input_header.get_global_rect().position.y >= viewport.get_global_rect().position.y - 2
			and input_header.get_global_rect().position.y < viewport.get_global_rect().position.y + viewport.get_global_rect().size.y * 0.25,
			"expanded section header scrolls into view")
		game.hud.bot_section_buttons.input.button_pressed = false
		game.hud.tabs.current_tab = 3
		await _capture("armor-settings-%dx%d.png" % [size.x, size.y])
		game.hud.set_paused(false)
		var before := await _capture("armor-hud-%dx%d.png" % [size.x, size.y])
		game.hud.armor_overlay.pulse(true)
		var after := await _capture("armor-break-%dx%d.png" % [size.x, size.y])
		var center_changes := 0
		var edge_changes := 0
		for y in range(0, after.get_height(), 3):
			for x in range(0, after.get_width(), 3):
				if before.get_pixel(x, y) != after.get_pixel(x, y):
					if x > after.get_width() * 0.2 and x < after.get_width() * 0.8:
						center_changes += 1
					else:
						edge_changes += 1
		check(center_changes == 0 and edge_changes > 40, "visible shield effect preserves central aiming region")
		game.hud.armor_overlay.advance(0.5)
		check(game.hud.armor_overlay.remaining == 0, "shield effect expires without affecting gameplay")
		game.pause_training()
