extends RefCounted

const DOC = preload("res://scripts/maps/map_document.gd")
const LAYERS = preload("res://scripts/maps/collision_layers.gd")


static func build_object(item: Dictionary, editor_preview: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Object_%d" % int(item.id)
	body.set_meta("map_id", int(item.id))
	body.position = DOC.vector3(item.position)
	body.rotation.y = deg_to_rad(item.yaw)
	body.collision_layer = 1
	body.collision_mask = 0
	var size := DOC.vector3(item.size)
	var material: Material
	if editor_preview:
		var checker := ShaderMaterial.new()
		checker.shader = preload("res://assets/materials/whitebox_checker.gdshader")
		material = checker
	else:
		var solid := StandardMaterial3D.new()
		solid.albedo_color = Color(DOC.COLORS[int(item.color)])
		solid.roughness = 0.9
		material = solid
	if item.kind in ["box", "barrier"]:
		_box(body, size, Vector3.UP * size.y * 0.5, material)
		if item.kind == "barrier":
			body.get_child(0).visible = editor_preview
			if editor_preview:
				var ghost := StandardMaterial3D.new()
				ghost.albedo_color = Color(0.3, 0.65, 0.9, 0.25)
				ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				body.get_child(0).material_override = ghost
	elif item.kind == "stairs":
		var count := int(item.steps)
		for index in count:
			var height := size.y * (index + 1) / count
			var depth := size.z / count
			_box(body, Vector3(size.x, height, depth),
				Vector3(0, height * 0.5, size.z * 0.5 - depth * (index + 0.5)), material)
		if not editor_preview and count > 1:
			# Detailed treads remain queryable by weapons; characters/navigation use the inner wedge.
			body.collision_layer = LAYERS.STAIR_DETAIL
			var walk := StaticBody3D.new()
			walk.name = "WalkSurface"
			walk.collision_layer = LAYERS.WORLD
			walk.collision_mask = 0
			var collision := CollisionShape3D.new()
			var shape := ConvexPolygonShape3D.new()
			shape.points = _wedge_points(size)
			collision.shape = shape
			walk.add_child(collision)
			body.add_child(walk)
	else:
		var points := _wedge_points(size)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_smooth_group(-1)
		var indices := [0, 1, 5, 0, 5, 4, 2, 4, 5, 2, 5, 3, 0, 4, 2, 1, 3, 5, 0, 2, 3, 0, 3, 1]
		for triangle in indices.size() / 3:
			for corner in [0, 2, 1]:
				surface.add_vertex(points[indices[triangle * 3 + corner]])
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.mesh = surface.commit()
		mesh.material_override = material
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		collision.shape = shape
		body.add_child(collision)
	return body


static func _wedge_points(size: Vector3) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-size.x / 2, 0, size.z / 2), Vector3(size.x / 2, 0, size.z / 2),
		Vector3(-size.x / 2, 0, -size.z / 2), Vector3(size.x / 2, 0, -size.z / 2),
		Vector3(-size.x / 2, size.y, -size.z / 2), Vector3(size.x / 2, size.y, -size.z / 2)])


static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = material
	parent.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	parent.add_child(collision)
