extends RefCounted

# One hit is one match point. Movement bonus is a separate practice metric.
var limit := 25
var player_points := 0
var bot_points := 0
var finished := false
var goal_reached := false
var elapsed := 0.0
var bonus := 0.0
var weight := 10.0
var moving_time := 0.0
var shots_by_side := [0, 0, 0]
var hits_by_side := [0, 0, 0]
var error_sum := 0.0
var shot_count := 0
var motion: Array[Dictionary] = []
var run_distance := 0.0
var last_side := 0
var bot_wait := 0.0
var bot_decision_at := -1.0
var random := RandomNumberGenerator.new()
const MAX_SNAPSHOTS := 512
var shot_snapshots: Array[Dictionary] = []
var dropped_snapshots := 0


func reset(points: int, bonus_weight: float, seed_value: int = -1) -> void:
	limit = points
	player_points = 0
	bot_points = 0
	finished = false
	goal_reached = false
	elapsed = 0
	bonus = 0
	weight = bonus_weight
	moving_time = 0
	shots_by_side = [0, 0, 0]
	hits_by_side = [0, 0, 0]
	error_sum = 0
	shot_count = 0
	shot_snapshots.clear()
	dropped_snapshots = 0
	if seed_value >= 0:
		random.seed = seed_value
	else:
		random.randomize()
	discontinuity()


func discontinuity() -> void:
	motion.clear()
	run_distance = 0
	last_side = 0
	bot_wait = 0
	bot_decision_at = -1


func sample(delta: float, displacement: Vector3, move: Vector2, yaw: float,
	speed_limit: float, visible: bool) -> void:
	elapsed += delta
	var side := int(signf(move.x))
	var lateral := displacement.dot(Basis(Vector3.UP, yaw) * Vector3.RIGHT)
	var valid := visible and side != 0 and lateral * side > 0 \
		and absf(lateral) >= speed_limit * delta * 0.3 \
		and Vector2(displacement.x, displacement.z).length() <= speed_limit * delta * 1.5
	var credit := 0.0
	if valid:
		moving_time += delta
		if side != last_side:
			run_distance = 0
		var before := run_distance
		run_distance += absf(lateral)
		credit = (maxf(0, run_distance - 0.2) - maxf(0, before - 0.2)) / maxf(speed_limit, 0.01)
	else:
		run_distance = 0
	last_side = side if valid else 0
	motion.append({"time": elapsed, "credit": credit})
	while not motion.is_empty() and motion[0].time <= elapsed - 0.4:
		motion.pop_front()


func record_player_shot(hit: bool, move: Vector2, error_degrees: float) -> void:
	if finished:
		return
	var index := int(signf(move.x)) + 1
	shots_by_side[index] += 1
	hits_by_side[index] += int(hit)
	shot_count += 1
	error_sum += error_degrees
	if hit:
		player_points += 1
		var credit := 0.0
		for item in motion:
			credit += item.credit
		bonus += weight / 100.0 * clampf(credit / 0.4, 0, 1)


func settle(bot_hit: bool) -> String:
	if finished:
		return ""
	bot_points += int(bot_hit)
	goal_reached = player_points >= limit or bot_points >= limit
	finished = goal_reached
	if not finished:
		return ""
	if player_points >= limit and bot_points >= limit:
		return "平局"
	return "玩家胜利" if player_points >= limit else "Bot 胜利"


func add_snapshot(value: Dictionary) -> void:
	if finished:
		return
	if shot_snapshots.size() >= MAX_SNAPSHOTS:
		shot_snapshots.pop_front()
		dropped_snapshots += 1
	shot_snapshots.append(value.duplicate(true))


func wants_bot_shot(delta: float, ready: bool, active: bool, perceived: bool,
	level: float, perceived_angle: float) -> bool:
	# No current player hit test is used to decide whether to shoot.
	if not ready or not active or not perceived:
		bot_wait = 0
		bot_decision_at = -1
		return false
	if level >= 100:
		return true
	var skill := clampf(level / 100.0, 0, 1)
	if bot_decision_at < 0:
		bot_decision_at = lerpf(0.30, 0.05, skill) * random.randf_range(0.8, 1.3)
	bot_wait += delta
	var tolerance := deg_to_rad(lerpf(10.0, 2.0, skill))
	var fire := bot_wait >= bot_decision_at and (perceived_angle <= tolerance \
		or bot_wait >= bot_decision_at + lerpf(0.55, 0.18, skill))
	if fire:
		bot_wait = 0
		bot_decision_at = -1
	return fire


func report(title: String, gun: LgWeapon, enemy_gun: LgWeapon, invalid: bool) -> Dictionary:
	var lines: Array[String] = []
	for index in 3:
		var side: String = ["向左移动", "无横向输入", "向右移动"][index]
		lines.append("%s：%d / %d 发命中%s" % [side, hits_by_side[index], shots_by_side[index],
			"（样本较少）" if shots_by_side[index] < 10 else ""])
	return {"title": title, "seconds": elapsed, "shots": gun.shots, "hits": gun.hits,
		"damage": 0, "accuracy": 100.0 * gun.hits / gun.shots if gun.shots > 0 else -1.0,
		"sniper": true, "player_points": player_points, "bot_points": bot_points, "limit": limit,
		"shot_snapshots": shot_snapshots.duplicate(true), "dropped_snapshots": dropped_snapshots,
		"score": {"base": float(player_points), "bonus": bonus, "total": player_points + bonus,
			"weight": weight, "valid": not invalid},
		"sections": [
			{"title": "单发定位", "lines": [
				"开枪时准星与目标中心的平均角度偏差：%.2f°（不是距命中边缘的误差）" % (error_sum / maxf(shot_count, 1)),
				"Bot：%d / %d 发命中。双方命中各得1分，打空不扣分。" % [enemy_gun.hits, enemy_gun.shots]]},
			{"title": "移动与出枪", "lines": lines + [
				"可见目标期间有效横移 %.1f 秒；走位奖励 +%.2f，独立展示，不决定胜负。" % [moving_time, bonus]]}],
		"notice": ("本轮非计分（自瞄、性能保护或中途更改设置）。" if invalid else "") \
			+ ("已达到目标分数。" if goal_reached else "手动结束，尚未达到目标分数。") \
			+ " 按玩家开枪时的左右输入分组；少量样本不判断左右手能力。"}
