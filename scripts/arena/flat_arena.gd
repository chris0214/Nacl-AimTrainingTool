extends Node3D

var wall_material: StandardMaterial3D
var floor_material: ShaderMaterial
var environment: Environment
var skies: Array[Sky] = []


func _ready() -> void:
	environment = $WorldEnvironment.environment.duplicate()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	$WorldEnvironment.environment = environment
	floor_material = $Floor/Mesh.mesh.material.duplicate()
	$Floor/Mesh.material_override = floor_material
	skies.resize(2)
	wall_material = material(Color("#d8ddda"))
	_build_boundaries()


func _build_boundaries() -> void:
	var trim := material(Color("#374848"))
	_box("BackWall", Vector3(36, 5, 0.6), Vector3(0, 2.5, -16), wall_material, true)
	_box("FrontWall", Vector3(36, 5, 0.6), Vector3(0, 2.5, 16), wall_material, true)
	_box("LeftWall", Vector3(0.6, 5, 32), Vector3(-18, 2.5, 0), wall_material, true)
	_box("RightWall", Vector3(0.6, 5, 32), Vector3(18, 2.5, 0), wall_material, true)
	for z in [-15.64, 15.64]:
		_box("WallBand", Vector3(35.4, 0.24, 0.035), Vector3(0, 0.45, z), trim)
	for x in [-17.64, 17.64]:
		_box("WallBand", Vector3(0.035, 0.24, 31.4), Vector3(x, 0.45, 0), trim)


func apply_appearance(values: Dictionary) -> void:
	var theme: int = values.arena_style
	wall_material.albedo_color = [Color("#d8ddda"), Color("#444a50"), Color("#d9e4ec")][theme]
	floor_material.set_shader_parameter("floor_color",
		[Color(0.49, 0.53, 0.54), Color("#303538"), Color("#8d9ca7")][theme])
	floor_material.set_shader_parameter("grid_color",
		[Color(0.38, 0.43, 0.44), Color("#687276"), Color("#56646d")][theme])
	floor_material.set_shader_parameter("grid_enabled", values.floor_grid)
	var sky_index: int = values.sky_style
	if sky_index > 0 and skies[sky_index - 1] == null:
		skies[sky_index - 1] = _create_sky(sky_index == 2)
	environment.background_mode = Environment.BG_COLOR if sky_index == 0 else Environment.BG_SKY
	environment.sky = null if sky_index == 0 else skies[sky_index - 1]
	# Keep ambient color explicit so sky changes do not trigger dynamic GI or affect target contrast.
	environment.ambient_light_energy = 0.4 * values.scene_brightness / 100.0
	$Sun.light_energy = 0.6 * values.scene_brightness / 100.0
	$Sun.light_color = Color(1, 0.96, 0.9)


func _create_sky(dusk: bool) -> Sky:
	var sky := Sky.new()
	var surface := ProceduralSkyMaterial.new()
	surface.sky_top_color = Color("#182544") if dusk else Color("#237fc6")
	surface.sky_horizon_color = Color("#e3ac94") if dusk else Color("#d6ebf0")
	surface.ground_horizon_color = surface.sky_horizon_color
	surface.ground_bottom_color = Color("#404346")
	sky.sky_material = surface
	return sky


func _box(label: String, size: Vector3, at: Vector3, surface: Material, solid: bool = false) -> void:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = label
	root.position = at
	add_child(root)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = surface
	root.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		root.add_child(collision)


static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	return result
