extends SceneTree

const PREFS = preload("res://scripts/input/trainer_settings.gd")
const LENS = preload("res://scripts/ui/scope_lens.gd")
var checks := 0
var failures := 0
var game: Node3D


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", title)


func _run() -> void:
	game = preload("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_unhandled_input(false)
	_settings()
	for hz in [120, 240, 360]:
		for lens_mode in [true, false]:
			await _live(hz, lens_mode)
	await _native()
	game.queue_free()
	await process_frame
	print("SCOPE_OPTICS_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func _settings() -> void:
	var prefs := PREFS.new()
	check(prefs.values.scope_lens and prefs.values.scope_distortion == 40, "new lens defaults")
	prefs.path = "res://artifacts/optics-settings.cfg"
	prefs.put("scope_lens", false)
	prefs.put("scope_quality", 50)
	prefs.put("scope_distortion", 83)
	prefs.put("scope_edge_shade", 0)
	check(prefs.save_settings() == OK, "optics saves")
	var loaded := PREFS.new()
	loaded.path = prefs.path
	loaded.load_settings()
	for key in ["scope_lens", "scope_quality", "scope_distortion", "scope_edge_shade"]:
		check(loaded.values[key] == prefs.values[key], "optics persists " + key)
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "format_version", 2)
	legacy.set_value("training", "scope_zoom", 4)
	legacy.set_value("training", "scope_mask", 25)
	legacy.save("res://artifacts/optics-legacy.cfg")
	loaded = PREFS.new()
	loaded.path = "res://artifacts/optics-legacy.cfg"
	loaded.load_settings()
	check(loaded.values.scope_zoom == 4 and loaded.values.scope_mask == 25 and loaded.values.scope_lens,
		"old config keeps multiplier and mask, enables new lens")
	for canvas in [Vector2(1440, 900), Vector2(1920, 800), Vector2(600, 960)]:
		for zoom in [1.5, 2.0, 4.0, 8.0]:
			for base in [30.0, 75.0, 120.0]:
				var crop := LENS.crop_fov(base, zoom, canvas)
				var lens_ppu := minf(canvas.x, canvas.y) * 0.8 / (2 * tan(deg_to_rad(crop) * 0.5))
				var base_ppu: float = canvas.y / (2 * tan(deg_to_rad(base) * 0.5))
				check(absf(lens_ppu / base_ppu - zoom) < 0.00001, "crop projection gives true center magnification")


func _setup(hz: int, lens_mode: bool) -> void:
	game.preferences.put("simulation_hz", hz)
	game.preferences.put("weapon_mode", 1)
	game.preferences.put("attack", false)
	game.preferences.put("move_speed", 0)
	game.preferences.put("reactive_bot", false)
	game.preferences.put("scope_mode", 0)
	game.preferences.put("scope_lens", lens_mode)
	game.preferences.put("scope_zoom", 4)
	game.preferences.put("scope_mask", 35)
	game.preferences.put("scope_distortion", 100)
	game.preferences.put("sniper_volume", 0)
	game.preferences.put("hit_sound", false)
	game._apply_preferences()
	game.reset_training()
	game.player.reset_at(Vector3.ZERO)
	game.target.reset_at(Vector3(0, 0, -12), 123)
	game.input.correct_view(0, atan2(0.91 - ArenaActor.EYE_HEIGHT, 12))


func _event(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	game.input.ingest(event, 0)


func _step() -> void:
	await physics_frame
	game.clock.rebase(Time.get_ticks_usec())
	game._physics_process(1.0 / game.clock.hz)
	game._process(0)


func _live(hz: int, lens_mode: bool) -> void:
	_setup(hz, lens_mode)
	var lens = game.hud.scope_overlay.lens
	check(lens.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hip fire has no extra rendering")
	_event(MOUSE_BUTTON_RIGHT, true)
	await _step()
	var base: float = game.preferences.vertical_fov()
	var expected: float = base if lens_mode else PlayerInput.scoped_fov(base, 4)
	check(is_equal_approx(game.camera.fov, expected), "outer projection selected correctly")
	check(lens.visible == lens_mode, "lens enabled only in lens mode")
	if lens_mode:
		check(lens.viewport.world_3d == game.get_world_3d(), "lens shares world without duplicate physics")
		check(lens.lens_camera.global_transform.is_equal_approx(game.camera.global_transform), "camera synced same frame")
		check(lens.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "scoped rendering active")
		check(is_equal_approx(lens.lens_camera.fov, LENS.crop_fov(base, 4, lens.size)), "lens crop FOV correct")
		var ray: Vector3 = lens.lens_camera.project_ray_normal(Vector2(lens.viewport.size) * 0.5)
		check(ray.distance_to(-game.camera.global_basis.z) < 0.00001, "lens center ray matches gun")
	var before := Vector2(game.input.yaw, game.input.pitch)
	_event(MOUSE_BUTTON_LEFT, true)
	await _step()
	check(game.weapon.hits == 1 and game.sniper_match.player_points == 1, "scoped hit and score at every physics rate")
	check(before == Vector2(game.input.yaw, game.input.pitch), "distortion never modifies aim")
	var tick: int = game.clock.tick
	game._set_preference("scope_distortion", 50)
	game._set_preference("scope_quality", 50)
	check(game.clock.tick == tick and not game.review.mixed_settings, "lens appearance preserves round and scoring")
	game.pause_training()
	check(not lens.visible and lens.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"pause disables lens immediately")
	game.hud.preference_controls.scope_lens.button_pressed = not lens_mode
	check(game.preferences.values.scope_lens == not lens_mode, "actual lens switch applies")
	check(game.hud.visual_sliders.scope_distortion.editable == not lens_mode, "inactive lens controls disabled")
	game.hud._apply_reticle_preset(1)
	check(game.preferences.values.scope_lens == not lens_mode and game.preferences.values.scope_distortion == 50,
		"ordinary preset preserves optics")
	game.resume_training()
	_event(MOUSE_BUTTON_RIGHT, true)
	await _step()
	_event(MOUSE_BUTTON_RIGHT, false)
	await _step()
	check(not lens.visible and lens.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
		and is_equal_approx(game.camera.fov, base), "release restores base view and stops lens render")
	_event(MOUSE_BUTTON_RIGHT, true)
	await _step()
	game.reset_training()
	check(lens.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "reset stops lens rendering")
	_event(MOUSE_BUTTON_RIGHT, true)
	await _step()
	game._manual_review()
	check(not lens.visible and lens.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "review stops rendering")
	game.hud.hide_review()


func _capture(name: String) -> Image:
	for frame in 6:
		await process_frame
		game._update_camera()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if not name.is_empty():
		image.save_png("res://artifacts/" + name + ".png")
	return image


func _native() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_setup(120, true)
	_event(MOUSE_BUTTON_RIGHT, true)
	await _step()
	var lens = game.hud.scope_overlay.lens
	for window_size in [Vector2i(1440, 900), Vector2i(960, 600), Vector2i(1920, 800)]:
		root.size = window_size
		for quality in [50, 75, 100]:
			game._set_preference("scope_quality", quality)
			await _capture("optics-%dx%d-q%d" % [window_size.x, window_size.y, quality])
			check(lens.viewport.size.x == roundi(mini(window_size.x, window_size.y) * 0.8 * quality / 100.0),
				"lens render size uses framebuffer pixels")
			# Compare an off-center world point in both projection systems, including crop and quality.
			var point: Vector3 = game.camera.global_transform * Vector3(0.15, 0.05, -10)
			var outer: Vector2 = game.camera.unproject_position(point) - game.hud.root.size * 0.5
			var inner: Vector2 = lens.lens_camera.unproject_position(point) - Vector2(lens.viewport.size) * 0.5
			inner *= minf(lens.size.x, lens.size.y) * 0.8 / lens.viewport.size.x
			check((inner - outer * 4).length() < 0.1, "rendered projection center stays 4x in all sizes and qualities")
	# Fullscreen-style reduced render size, without changing the actual desktop mode.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1280, 720)
	game._set_preference("scope_quality", 75)
	await _capture("optics-reduced-render")
	check(lens.viewport.size == Vector2i(432, 432), "reduced render viewport uses 720px height")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(960, 600)
	game._set_preference("scope_quality", 100)
	game._set_preference("scope_lines", false)
	game._set_preference("scope_dot", 0)
	game._set_preference("scope_edge_shade", 0)
	game._set_preference("scope_mask", 0)
	game._set_preference("scope_distortion", 0)
	await _capture("optics-clear-lens")
	game._set_preference("scope_distortion", 100)
	await _capture("optics-distorted-lens")
	# Known texture tests the actual shader independently of moving targets / frame timing.
	var gradient := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			gradient.set_pixel(x, y, Color(x / 255.0, y / 255.0, 0.25, 1))
	lens.shader.set_shader_parameter("lens_texture", ImageTexture.create_from_image(gradient))
	game._set_preference("scope_distortion", 0)
	var plain := await _capture("")
	game._set_preference("scope_distortion", 100)
	var bent := await _capture("")
	var center := Vector2i(plain.get_width() / 2, plain.get_height() / 2)
	var radius := mini(plain.get_width(), plain.get_height()) * 0.4
	check(plain.get_pixelv(center) == bent.get_pixelv(center), "shader never moves center pixel")
	var central := center + Vector2i(roundi(radius * 0.4), 0)
	check(plain.get_pixelv(central) == bent.get_pixelv(central), "central 55 percent remains undistorted")
	var edge := center + Vector2i(roundi(radius * 0.9), 0)
	check(absf(plain.get_pixelv(edge).r - bent.get_pixelv(edge).r) > 0.025, "shader visibly warps edge samples")
	var outside := center + Vector2i(roundi(radius + 15), 0)
	check(plain.get_pixelv(outside) == bent.get_pixelv(outside), "shader leaves outside world untouched")
	game._set_preference("scope_edge_shade", 60)
	var shaded := await _capture("")
	check(shaded.get_pixelv(edge).r < bent.get_pixelv(edge).r - 0.1, "edge shade visibly darkens rim")
	check(shaded.get_pixelv(center) == bent.get_pixelv(center), "edge shade leaves center untouched")
	lens.shader.set_shader_parameter("lens_texture", lens.viewport.get_texture())
	game._set_preference("scope_lines", true)
	game._set_preference("scope_dot", 1.2)
	game._set_preference("scope_edge_shade", 20)
	game._set_preference("scope_distortion", 40)
	await _capture("optics-default-effects")
	game._set_preference("scope_lens", false)
	await _capture("optics-classic")
	game.pause_training()
	game.hud.tabs.current_tab = 5
	game._set_preference("scope_lens", true)
	var content: VBoxContainer = game.hud.setting_rows.scope_lens.get_parent()
	var section: Button = content.get_parent().get_child(content.get_index() - 1)
	section.button_pressed = true
	await process_frame
	game.hud.tabs.get_child(5).ensure_control_visible(game.hud.preference_controls.scope_quality)
	await _capture("optics-settings")
