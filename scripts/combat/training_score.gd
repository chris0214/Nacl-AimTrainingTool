extends RefCounted

var weight := 10.0
var base := 0.0
var bonus := 0.0
var lateral_distance := 0.0
var interval_time := 0.0
var interval_credit := 0.0
var run_distance := 0.0
var last_side := 0
var assisted := false


func reset(config: Dictionary) -> void:
	weight = clampf(float(config.get("ad_bonus_weight", 10.0)), 0, 20)
	base = 0
	bonus = 0
	lateral_distance = 0
	assisted = int(config.get("assist_mode", 0)) != 0
	discontinuity()


func discontinuity() -> void:
	interval_time = 0
	interval_credit = 0
	run_distance = 0
	last_side = 0


func sample(row: Dictionary, delta: float) -> void:
	if delta <= 0:
		return
	assisted = assisted or bool(row.get("assisted", false))
	var side := int(signf(row.move.x))
	var displacement: Vector3 = row.get("displacement", Vector3.ZERO)
	var right := Basis(Vector3.UP, float(row.yaw)) * Vector3.RIGHT
	var lateral := displacement.dot(right)
	var limit := maxf(float(row.get("speed_limit", 10.0)), 0.01)
	# Credit actual input-aligned displacement, never key events or blocked velocity.
	var valid: bool = row.firing and row.visible and side != 0 and lateral * side > 0 \
		and Vector2(displacement.x, displacement.z).length() <= limit * delta * 1.5
	var speed := absf(lateral) / delta
	if not valid or speed < limit * 0.3:
		run_distance = 0
		last_side = 0
	else:
		if side != last_side:
			run_distance = 0
		last_side = side
		var before := run_distance
		run_distance += absf(lateral)
		lateral_distance += absf(lateral)
		# Ignore the first 20 cm of each run; crossing ticks receive partial credit.
		var useful := maxf(0, run_distance - 0.2) - maxf(0, before - 0.2)
		interval_credit += useful / limit
	if not row.firing:
		discontinuity()
	else:
		interval_time += delta
	if row.shot:
		var dealt := maxf(0, float(row.get("outgoing", 0)))
		base += dealt
		bonus += dealt * weight / 100.0 * clampf(interval_credit / maxf(interval_time, delta), 0, 1)
		interval_time = 0
		interval_credit = 0


func result(invalid: bool = false) -> Dictionary:
	return {"base": base, "bonus": bonus, "total": base + bonus, "weight": weight,
		"lateral_distance": lateral_distance, "valid": not invalid and not assisted}
