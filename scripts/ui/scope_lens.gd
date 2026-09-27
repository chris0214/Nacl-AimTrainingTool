extends ColorRect

# A second view of the same world, never a second simulation.
# Render only the lens's square crop, not another full rectangular screen.
const LENS_SHADER = preload("res://assets/materials/scope_lens.gdshader")
var viewport: SubViewport
var lens_camera: Camera3D
var shader: ShaderMaterial
var quality := 0.75
var enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.name = "LensViewport"
	viewport.size = Vector2i(2, 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	lens_camera = Camera3D.new()
	lens_camera.name = "LensCamera"
	viewport.add_child(lens_camera)
	lens_camera.current = true
	shader = ShaderMaterial.new()
	shader.shader = LENS_SHADER
	shader.set_shader_parameter("lens_texture", viewport.get_texture())
	material = shader
	resized.connect(func(): shader.set_shader_parameter("canvas_size", size))
	hide()


func configure(values: Dictionary) -> void:
	enabled = values.scope_lens
	quality = values.scope_quality / 100.0
	shader.set_shader_parameter("distortion", values.scope_distortion / 100.0)
	shader.set_shader_parameter("edge_shade", values.scope_edge_shade / 100.0)
	if not enabled:
		deactivate()


static func crop_fov(base_vertical: float, zoom: float, canvas: Vector2) -> float:
	var diameter_ratio := 0.8 * minf(canvas.x, canvas.y) / maxf(canvas.y, 1.0)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_vertical) * 0.5) * diameter_ratio / zoom))


func update_view(source: Camera3D, active: bool, base_vertical: float, zoom: float) -> void:
	if not active or not enabled:
		deactivate()
		return
	# Copy the interpolated main camera after it has been updated, in the same frame.
	if viewport.world_3d != source.get_world_3d():
		viewport.world_3d = source.get_world_3d()
	lens_camera.global_transform = source.global_transform
	lens_camera.near = source.near
	lens_camera.far = source.far
	lens_camera.cull_mask = source.cull_mask
	lens_camera.environment = source.environment
	lens_camera.attributes = source.attributes
	lens_camera.fov = crop_fov(base_vertical, zoom, size)
	var window := get_window()
	var pixels := window.content_scale_size if (
		window.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT) else window.size
	var side := maxi(2, roundi(mini(pixels.x, pixels.y) * 0.8 * quality))
	if viewport.size != Vector2i(side, side):
		viewport.size = Vector2i(side, side)
	shader.set_shader_parameter("canvas_size", size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	show()


func deactivate() -> void:
	hide()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
