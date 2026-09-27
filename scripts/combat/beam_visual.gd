extends Node3D

var beam := MeshInstance3D.new()
var halo := MeshInstance3D.new()
var beam_material: StandardMaterial3D
var halo_material: StandardMaterial3D
var enemy_style := false


func _ready() -> void:
	var line := CylinderMesh.new()
	line.top_radius = 0.014
	line.bottom_radius = 0.014
	line.height = 1.0
	line.cap_top = false
	line.cap_bottom = false
	beam.mesh = line
	beam_material = StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.albedo_color = Color("#d1fff5")
	beam.material_override = beam_material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var outer := CylinderMesh.new()
	outer.top_radius = 0.045
	outer.bottom_radius = 0.045
	outer.height = 1.0
	outer.radial_segments = 12
	outer.cap_top = false
	outer.cap_bottom = false
	halo.mesh = outer
	halo_material = StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.albedo_color = Color(0.15, 0.9, 1.0, 0.3)
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	visible = false


func show_segment(origin: Vector3, endpoint: Vector3, firing: bool, viewer_hit: bool = false) -> void:
	visible = firing
	if not firing:
		return
	# Only a confirmed player hit continues visually through the body toward the screen.
	# Wall hits and misses retain the exact ray endpoint.
	if enemy_style and viewer_hit:
		endpoint += (endpoint - origin).normalized() * 2.0
	var delta := endpoint - origin
	var length := delta.length()
	if length < 0.001:
		visible = false
		return
	var y := delta / length
	var helper := Vector3.RIGHT if absf(y.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x := y.cross(helper).normalized()
	var z := x.cross(y).normalized()
	beam.global_transform = Transform3D(Basis(x, y * length, z), (origin + endpoint) * 0.5)
	halo.global_transform = beam.global_transform


func set_enemy_style() -> void:
	enemy_style = true
	if beam_material:
		beam_material.albedo_color = Color("#fff2b0")
		halo_material.albedo_color = Color(1.0, 0.24, 0.08, 0.35)
		var outer := halo.mesh as CylinderMesh
		outer.top_radius = 0.025
		outer.bottom_radius = 0.025
