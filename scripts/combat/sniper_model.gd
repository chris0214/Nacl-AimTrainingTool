extends Node3D

# Original procedural training rifle. No downloaded mesh or textures.
const MUZZLE := Vector3(0, 0, -0.94)
var bolt: Node3D


func _ready() -> void:
	var metal := _material("#414b53", 0.65)
	var dark := _material("#1b2329", 0.25)
	var stock := _material("#74867a", 0.1)
	var accent := _material("#a6cdc4", 0.45)
	_box(Vector3(0.105, 0.12, 0.38), Vector3(0, -0.005, -0.17), metal)
	_box(Vector3(0.12, 0.09, 0.32), Vector3(0, -0.06, -0.43), stock)
	_box(Vector3(0.10, 0.14, 0.30), Vector3(0, -0.04, 0.16), stock)
	_box(Vector3(0.12, 0.17, 0.035), Vector3(0, -0.05, 0.32), dark)
	_box(Vector3(0.09, 0.04, 0.19), Vector3(0, 0.045, 0.15), dark)
	var grip := _box(Vector3(0.075, 0.17, 0.08), Vector3(0, -0.13, 0.005), dark)
	grip.rotation.x = -0.25
	_box(Vector3(0.07, 0.12, 0.085), Vector3(0, -0.13, -0.16), metal)
	_tube(0.024, 0.58, Vector3(0, 0, -0.61), metal)
	_tube(0.038, 0.09, Vector3(0, 0, -0.895), dark)
	_tube(0.018, 0.002, MUZZLE, _material("#070a0c", 0))
	for z in [-0.07, -0.28]:
		_box(Vector3(0.07, 0.09, 0.045), Vector3(0, 0.085, z), dark)
	_tube(0.038, 0.31, Vector3(0, 0.14, -0.16), dark)
	_tube(0.052, 0.065, Vector3(0, 0.14, -0.335), metal)
	_tube(0.048, 0.045, Vector3(0, 0.14, 0.015), metal)
	_tube(0.042, 0.002, Vector3(0, 0.14, 0.039), _material("#3b8785", 0.75))
	_box(Vector3(0.045, 0.045, 0.045), Vector3(0, 0.19, -0.12), metal)
	for z in [-0.30, -0.35, -0.40, -0.45, -0.50]:
		_box(Vector3(0.123, 0.017, 0.012), Vector3(0, -0.052, z), dark)
	_box(Vector3(0.004, 0.025, 0.08), Vector3(0.055, 0.015, -0.12), accent)
	bolt = Node3D.new()
	add_child(bolt)
	_box(Vector3(0.085, 0.018, 0.025), Vector3(0.065, 0.015, 0), metal, bolt)
	_box(Vector3(0.03, 0.04, 0.04), Vector3(0.11, 0.005, 0), dark, bolt)


func cycle(remaining: float) -> void:
	# Visual cycle only; the simulation owns cooldown and hit timing.
	if is_instance_valid(bolt):
		bolt.position.z = sin(clampf(remaining, 0, 1) * PI) * 0.10
		bolt.rotation.z = sin(clampf(remaining, 0, 1) * PI) * 0.5


func _material(color: String, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.metallic = metallic
	material.roughness = 0.55
	return material


func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(mesh, at, material, parent)


func _tube(radius: float, length: float, at: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 20
	var part := _part(mesh, at, material, self)
	part.rotation.x = PI / 2


func _part(mesh: Mesh, at: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part
