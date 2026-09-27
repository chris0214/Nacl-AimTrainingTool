extends RefCounted

const DOC = preload("res://scripts/maps/map_document.gd")


static func normal(face: int, yaw: float = 0.0) -> Vector3:
	var result := Vector3.ZERO
	result[face / 2] = -1.0 if face % 2 == 0 else 1.0
	return result.rotated(Vector3.UP, deg_to_rad(yaw))


static func center(item: Dictionary, face: int) -> Vector3:
	var size := DOC.vector3(item.size)
	return DOC.vector3(item.position) + Vector3.UP * size.y * 0.5 \
		+ normal(face, item.yaw) * size[face / 2] * 0.5


static func from_normal(world_normal: Vector3, yaw: float) -> int:
	var local := world_normal.rotated(Vector3.UP, -deg_to_rad(yaw))
	var axis := local.abs().max_axis_index()
	return axis * 2 + (1 if local[axis] > 0 else 0)


static func surface_center(item: Dictionary, face: int) -> Vector3:
	var size := DOC.vector3(item.size)
	var local := Vector3(0, size.y * 0.5, 0)
	local[face / 2] += normal(face)[face / 2] * size[face / 2] * 0.5
	if item.kind in ["stairs", "ramp"]:
		if face / 2 == 0:
			local.y = size.y * 0.25
		elif face == 3:
			local.y = size.y * 0.5 if item.kind == "ramp" else size.y
			if item.kind == "stairs":
				local.z = -size.z * 0.5 + size.z / item.steps * 0.5
		elif face == 5:
			local.y = 0.0 if item.kind == "ramp" else size.y / item.steps * 0.5
	return DOC.vector3(item.position) + local.rotated(Vector3.UP, deg_to_rad(item.yaw))


static func picked_face(item: Dictionary, world_normal: Vector3) -> int:
	# The slope is a height control, even when steeper than 45 degrees.
	if item.kind == "ramp" and world_normal.y > 0.001:
		return 3
	return from_normal(world_normal, item.yaw)


static func height_limit(item: Dictionary) -> float:
	var limit := minf(64, 48.0 - float(item.position[1]))
	if item.kind == "stairs" and item.get("auto_steps", false):
		var count := clampi(int(floor((float(item.size[2]) + 0.00001) / DOC.MIN_TREAD)), 1, 64)
		limit = minf(limit, count * DOC.MAX_RISE)
	return limit


static func resized(original: Dictionary, face: int, distance: float, snap: float) -> Dictionary:
	var result := original.duplicate(true)
	var axis := face / 2
	var size := DOC.vector3(original.size)
	var at := DOC.vector3(original.position)
	var shift := normal(face, original.yaw) * 0.5
	if axis == 1:
		shift = Vector3.DOWN if face % 2 == 0 else Vector3.ZERO
	var low := 0.1 - size[axis]
	var high := 64.0 - size[axis]
	if original.kind == "stairs" and original.get("auto_steps", false):
		if axis == 1:
			# Keep the high landing aligned; any required tread length grows toward the entrance.
			var extended := resized(original, 5, 10000, 0)
			high = minf(high, minf(16, floor((float(extended.size[2]) + 0.00001) / DOC.MIN_TREAD) * DOC.MAX_RISE) - size.y)
		elif axis == 2:
			low = maxf(low, ceil(float(size.y) / DOC.MAX_RISE) * DOC.MIN_TREAD - size.z)
	if axis == 1:
		high = minf(high, at.y + 16.0 if face % 2 == 0 else 48.0 - at.y - size.y)
	for component in [0, 2]:
		if absf(shift[component]) > 0.00001:
			var first := (-128.0 - at[component]) / shift[component]
			var second := (128.0 - at[component]) / shift[component]
			low = maxf(low, minf(first, second))
			high = minf(high, maxf(first, second))
	var delta := snappedf(distance, snap) if snap > 0 else distance
	delta = clampf(delta, low, high)
	size[axis] += delta
	at += shift * delta
	result.size = DOC.array3(size)
	result.position = DOC.array3(at)
	if result.kind == "stairs" and result.get("auto_steps", false):
		result.steps = maxi(1, int(ceil(float(result.size[1]) / DOC.MAX_RISE)))
		if axis == 1:
			var extension := maxf(0, result.steps * DOC.MIN_TREAD - float(result.size[2]))
			result.size[2] += extension
			result.position = DOC.array3(at + normal(5, original.yaw) * extension * 0.5)
	return result
