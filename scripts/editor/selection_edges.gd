extends RefCounted

const DOC = preload("res://scripts/maps/map_document.gd")


static func build(item: Dictionary) -> ArrayMesh:
	var size := DOC.vector3(item.size)
	var profile: Array[Vector2] = []
	var bottom := -size.y * 0.5
	profile.append(Vector2(size.z * 0.5, bottom))
	if item.kind == "stairs":
		for index in int(item.steps):
			var height: float = bottom + size.y * (index + 1) / item.steps
			profile.append(Vector2(size.z * 0.5 - size.z * index / item.steps, height))
			profile.append(Vector2(size.z * 0.5 - size.z * (index + 1) / item.steps, height))
	elif item.kind == "ramp":
		profile.append(Vector2(-size.z * 0.5, size.y * 0.5))
	else:
		profile.append(Vector2(size.z * 0.5, size.y * 0.5))
		profile.append(Vector2(-size.z * 0.5, size.y * 0.5))
	profile.append(Vector2(-size.z * 0.5, bottom))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	for index in profile.size():
		var p := profile[index]
		var q := profile[(index + 1) % profile.size()]
		_segment(surface, Vector3(-size.x * 0.5, p.y, p.x), Vector3(size.x * 0.5, p.y, p.x))
		for side in [-1.0, 1.0]:
			_segment(surface, Vector3(side * size.x * 0.5, p.y, p.x),
				Vector3(side * size.x * 0.5, q.y, q.x))
	return surface.commit()


static func _segment(surface: SurfaceTool, start: Vector3, end: Vector3) -> void:
	for spec in [Vector2(-1, 1), Vector2(-1, -1), Vector2(1, 1),
		Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		var other := end if spec.y > 0 else start
		surface.set_custom(0, Color(other.x, other.y, other.z, 1))
		surface.set_uv(spec)
		surface.add_vertex(start if spec.y > 0 else end)
