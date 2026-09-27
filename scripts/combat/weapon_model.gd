extends Node3D

const MODELS = preload("res://scripts/combat/training_models.gd")
const REST_POSITION := Vector3(0.18, -0.24, -0.28)
const SNIPER_POSITION := Vector3(0.24, -0.28, -0.55)
const MODEL_SCALE := 0.85
var muzzle := Marker3D.new()
var energy := 0.0
var flash := MeshInstance3D.new()
var rifle: Node3D
var sniper: Node3D
var single_shot := false


func _ready() -> void:
	position = REST_POSITION
	var model := MODELS.create_rifle()
	rifle = model
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	sniper = preload("res://scripts/combat/sniper_model.gd").new()
	sniper.scale = Vector3.ONE * 0.85
	add_child(sniper)
	sniper.visible = false
	muzzle.position = MODELS.MUZZLE * MODEL_SCALE
	add_child(muzzle)
	var light := StandardMaterial3D.new()
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.albedo_color = Color("#caffff")
	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	flash.mesh = sphere
	flash.material_override = light
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(flash)
	flash.visible = false


func muzzle_position() -> Vector3:
	return muzzle.global_position


func set_single_shot(enabled: bool) -> void:
	single_shot = enabled
	rifle.visible = not enabled
	sniper.visible = enabled
	muzzle.position = sniper.MUZZLE * 0.85 if enabled else MODELS.MUZZLE * MODEL_SCALE
	position = SNIPER_POSITION if enabled else REST_POSITION
	energy = 0


func update_cycle(remaining: float) -> void:
	sniper.cycle(remaining)


func update_state(firing: bool, delta: float) -> void:
	energy = move_toward(energy, 1.0 if firing else 0.0, delta * 12.0)
	position = (SNIPER_POSITION if single_shot else REST_POSITION) \
		+ Vector3(0.0, 0.0, energy * (0.045 if single_shot else 0.009))
	flash.visible = firing
	flash.scale = Vector3.ONE * (1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.04))
