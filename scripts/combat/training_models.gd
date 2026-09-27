extends RefCounted

# Original geometry and analytic animation. No imported mesh, texture or motion data.
# This factory isolates target/weapon appearance from simulation and hitboxes.
const MUZZLE := Vector3(0.0, 0.105, -0.51)
const CLIPS := ["idle", "left", "right", "forward", "back"]


static func _material(color: String, metallic: float = 0.0, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.metallic = metallic
	material.roughness = 0.55
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


static func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = position
	parent.add_child(part)
	return part


static func _tube(parent: Node3D, radius: float, length: float, position: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = position
	part.rotation.x = PI / 2
	parent.add_child(part)


static func create_rifle() -> Node3D:
	var root := Node3D.new()
	root.name = "TrainingEmitter"
	var frame := _material("#414f59", 0.65)
	var shell := _material("#bec8c7", 0.35)
	var grip := _material("#1d282e")
	var energy := _material("#60e6dc", 0.0, true)
	_box(root, Vector3(0.13, 0.15, 0.30), Vector3(0, 0.09, -0.13), shell)
	_box(root, Vector3(0.11, 0.11, 0.18), Vector3(0, 0.055, 0.1), frame)
	_box(root, Vector3(0.13, 0.16, 0.035), Vector3(0, 0.055, 0.2), grip)
	var handle := _box(root, Vector3(0.075, 0.16, 0.07), Vector3(0, -0.055, -0.02), grip)
	handle.rotation.x = -0.2
	_tube(root, 0.039, 0.28, Vector3(0, 0.105, -0.34), frame)
	_tube(root, 0.062, 0.035, Vector3(0, 0.105, -0.49), shell)
	_tube(root, 0.03, 0.002, MUZZLE, energy)
	for x in [-0.07, 0.07]:
		_box(root, Vector3(0.018, 0.05, 0.16), Vector3(x, 0.11, -0.14), grip)
		_box(root, Vector3(0.02, 0.012, 0.12), Vector3(x, 0.11, -0.14), energy)
	for z in [-0.3, -0.36, -0.42]:
		_tube(root, 0.047, 0.017, Vector3(0, 0.105, z), energy)
	_box(root, Vector3(0.045, 0.025, 0.20), Vector3(0, 0.18, -0.14), frame)
	return root


static func _bone(skeleton: Skeleton3D, name: String, parent: String, at: Vector3) -> void:
	var index := skeleton.add_bone(name)
	if not parent.is_empty():
		skeleton.set_bone_parent(index, skeleton.find_bone(parent))
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, at))


static func _attach(skeleton: Skeleton3D, bone: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = bone + "_parts"
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	return attachment


static func create_robot() -> Node3D:
	var root := Node3D.new()
	root.name = "TrainingRobot"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	_bone(skeleton, "pelvis", "", Vector3(0, 0.92, 0))
	_bone(skeleton, "spine_01", "pelvis", Vector3(0, 0.24, 0))
	_bone(skeleton, "head", "spine_01", Vector3(0, 0.48, 0))
	for side in ["l", "r"]:
		var sign_x := -1.0 if side == "l" else 1.0
		_bone(skeleton, "clavicle_" + side, "spine_01", Vector3(sign_x * 0.24, 0.20, 0))
		_bone(skeleton, "upperarm_" + side, "clavicle_" + side, Vector3.ZERO)
		_bone(skeleton, "hand_" + side, "upperarm_" + side, Vector3(-sign_x * 0.03, -0.16, -0.21))
		_bone(skeleton, "thigh_" + side, "pelvis", Vector3(sign_x * 0.15, -0.04, 0))
		_bone(skeleton, "shin_" + side, "thigh_" + side, Vector3(0, -0.38, 0))
	skeleton.reset_bone_poses()
	var shell := _material("#c3cbd0", 0.35)
	var dark := _material("#303e48", 0.25)
	var accent := _material("#ffbd68", 0, true)
	_box(_attach(skeleton, "pelvis"), Vector3(0.37, 0.16, 0.24), Vector3.ZERO, dark)
	var torso := _attach(skeleton, "spine_01")
	_box(torso, Vector3(0.39, 0.36, 0.24), Vector3(0, 0.06, 0), shell)
	_box(torso, Vector3(0.26, 0.13, 0.02), Vector3(0, 0.12, -0.13), dark)
	_box(torso, Vector3(0.12, 0.024, 0.025), Vector3(0, 0.12, -0.145), accent)
	var head := _attach(skeleton, "head")
	_box(head, Vector3(0.25, 0.28, 0.25), Vector3.ZERO, shell)
	_box(head, Vector3(0.23, 0.075, 0.018), Vector3(0, 0.02, -0.134), dark)
	_box(head, Vector3(0.18, 0.024, 0.02), Vector3(0, 0.02, -0.147), accent)
	for side in ["l", "r"]:
		var shoulder := _attach(skeleton, "upperarm_" + side)
		_box(shoulder, Vector3(0.13, 0.22, 0.16), Vector3(0, -0.06, 0), shell)
		var forearm := _box(shoulder, Vector3(0.10, 0.10, 0.24), Vector3(0, -0.17, -0.11), dark)
		forearm.rotation.x = -0.15
		_box(_attach(skeleton, "hand_" + side), Vector3(0.1, 0.1, 0.1), Vector3.ZERO, dark)
		_box(_attach(skeleton, "thigh_" + side), Vector3(0.17, 0.33, 0.19), Vector3(0, -0.18, 0), shell)
		var shin := _attach(skeleton, "shin_" + side)
		_box(shin, Vector3(0.15, 0.33, 0.17), Vector3(0, -0.18, 0), dark)
		_box(shin, Vector3(0.19, 0.10, 0.28), Vector3(0, -0.43, -0.05), shell)
	var animator := AnimationPlayer.new()
	animator.name = "AnimationPlayer"
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(animator)
	var library := AnimationLibrary.new()
	for clip in CLIPS:
		var animation := Animation.new()
		animation.length = 0.8
		animation.loop_mode = Animation.LOOP_LINEAR
		for side in ["l", "r"]:
			for part in ["thigh_", "shin_"]:
				var track := animation.add_track(Animation.TYPE_ROTATION_3D)
				animation.track_set_path(track, NodePath("Skeleton3D:" + part + side))
				for key in 17:
					var phase := key / 16.0 * TAU + (PI if side == "r" else 0.0)
					var angle := sin(phase) * 0.28 if part == "thigh_" else maxf(0, -sin(phase)) * 0.32
					if clip == "idle":
						angle = 0.0
					var axis := Vector3.FORWARD if clip in ["left", "right"] and part == "thigh_" else Vector3.RIGHT
					if clip in ["left", "back"]:
						angle *= -1
					animation.rotation_track_insert_key(track, key / 16.0 * animation.length, Quaternion(axis, angle))
		library.add_animation(clip, animation)
	animator.add_animation_library("", library)
	return root
