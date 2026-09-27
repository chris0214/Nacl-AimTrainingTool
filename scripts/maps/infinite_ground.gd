extends StaticBody3D

var visual: MeshInstance3D


func _init() -> void:
	name = "InfiniteGround"
	collision_layer = 1
	collision_mask = 0
	var collision := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0)
	collision.shape = plane
	add_child(collision)
	visual = MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(4096, 4096)
	visual.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/whitebox_checker.gdshader")
	material.set_shader_parameter("cell_size", 2.0)
	material.set_shader_parameter("base_color", Color("#777b7e"))
	visual.material_override = material
	add_child(visual)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# Only the visual patch follows the viewer. Physics is a stationary infinite plane.
		visual.global_position = Vector3(
			snappedf(camera.global_position.x, 64), 0, snappedf(camera.global_position.z, 64))
