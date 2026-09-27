extends RefCounted

var ticks := 0
var eligible_time := 0.0
var aim_time := 0.0
var idle_time := 0.0
var moving_time := 0.0
var close_time := 0.0
var distance_sum := 0.0
var horizontal_error := 0.0
var vertical_error := 0.0
var left_time := 0.0
var left_aim := 0.0
var right_time := 0.0
var right_aim := 0.0
var behind_time := 0.0
var ahead_time := 0.0
var missed_time := 0.0
var post_time := 0.0
var post_aim := 0.0
var other_time := 0.0
var other_aim := 0.0
var reversals := 0
var last_side := 0
var side_since := 0.0
var now := 0.0
var post_until := -1.0
var episodes: Array[float] = []
var assisted := false
var mixed_settings := false
var initialized := false
var previous_bearing := 0.0
var mouse_rotation := 0.0
var strafe_shots := [0, 0, 0]
var strafe_hits := [0, 0, 0]
var incoming_idle := 0
var incoming_moving := 0
var setup: Dictionary = {}
var score := preload("res://scripts/combat/training_score.gd").new()


func begin(config: Dictionary) -> void:
	score.reset(config)
	ticks = 0
	eligible_time = 0
	aim_time = 0
	idle_time = 0
	moving_time = 0
	close_time = 0
	distance_sum = 0
	horizontal_error = 0
	vertical_error = 0
	left_time = 0
	left_aim = 0
	right_time = 0
	right_aim = 0
	behind_time = 0
	ahead_time = 0
	missed_time = 0
	post_time = 0
	post_aim = 0
	other_time = 0
	other_aim = 0
	reversals = 0
	last_side = 0
	side_since = 0
	now = 0
	post_until = -1
	episodes.clear()
	assisted = false
	mixed_settings = false
	initialized = false
	mouse_rotation = 0
	strafe_shots = [0, 0, 0]
	strafe_hits = [0, 0, 0]
	incoming_idle = 0
	incoming_moving = 0
	setup = config.duplicate(true)


func discontinuity() -> void:
	score.discontinuity()
	initialized = false
	last_side = 0
	side_since = now
	post_until = -1


func sample(row: Dictionary, delta: float) -> void:
	if delta <= 0:
		return
	score.sample(row, delta)
	ticks += 1
	now += delta
	assisted = assisted or row.assisted
	var moving: bool = row.speed > 0.5
	if moving:
		moving_time += delta
		incoming_moving += int(row.incoming)
	else:
		idle_time += delta
		incoming_idle += int(row.incoming)
	var offset: Vector3 = row.target - row.eye
	var flat_distance := Vector2(offset.x, offset.z).length()
	distance_sum += flat_distance * delta
	close_time += delta if flat_distance < 6.0 else 0.0
	var side := int(signf(row.move.x))
	if side != last_side:
		if last_side != 0:
			episodes.append(now - side_since)
			if episodes.size() > 128:
				episodes.pop_front()
		if side * last_side < 0:
			reversals += 1
			post_until = now + 0.25
		side_since = now
		last_side = side
	if row.shot:
		strafe_shots[side + 1] += 1
		strafe_hits[side + 1] += int(row.hit)
	var bearing := atan2(-offset.x, -offset.z)
	var bearing_rate := wrapf(bearing - previous_bearing, -PI, PI) / delta if initialized else 0.0
	previous_bearing = bearing
	mouse_rotation += absf(row.look.x)
	if not row.visible or not row.firing or flat_distance < 0.5:
		initialized = false
		return
	initialized = true
	eligible_time += delta
	aim_time += delta if row.hit else 0.0
	var error_x := wrapf(row.yaw - bearing, -PI, PI)
	var desired_pitch := atan2(offset.y, flat_distance)
	var error_y: float = row.pitch - desired_pitch
	var half_width := atan2(row.radius, flat_distance)
	horizontal_error += absf(error_x) / maxf(half_width, 0.001) * delta
	vertical_error += absf(error_y) * delta
	if bearing_rate > deg_to_rad(2):
		left_time += delta
		left_aim += delta if row.hit else 0
	elif bearing_rate < -deg_to_rad(2):
		right_time += delta
		right_aim += delta if row.hit else 0
	if not row.hit and absf(error_x) > half_width and absf(bearing_rate) > deg_to_rad(2):
		missed_time += delta
		behind_time += delta if error_x * bearing_rate < 0 else 0
		ahead_time += delta if error_x * bearing_rate > 0 else 0
	if now <= post_until:
		post_time += delta
		post_aim += delta if row.hit else 0
	else:
		other_time += delta
		other_aim += delta if row.hit else 0


func result(shots: int, hits: int, damage: int, title: String) -> Dictionary:
	var enough := eligible_time >= 2.0 and shots >= 20
	var ratio := 100.0 * aim_time / maxf(eligible_time, 0.001)
	var aim_lines: Array[String] = []
	var move_lines: Array[String] = []
	var joint_lines: Array[String] = []
	if assisted:
		aim_lines.append("本轮使用过娱乐自瞄，鼠标瞄准与配合结论不生成。")
	elif not enough:
		aim_lines.append("有效跟踪样本不足：%.2f秒、%d发；至少2秒且20发后再观察倾向。" % [eligible_time, shots])
	else:
		aim_lines.append("无遮挡且开火时的准星覆盖率 %.1f%%（%.2f / %.2f秒）。" % [ratio, aim_time, eligible_time])
		aim_lines.append("平均水平偏差 %.2f 个目标半宽；平均垂直偏差 %.2f°。" % [
			horizontal_error / eligible_time, rad_to_deg(vertical_error / eligible_time)])
		aim_lines.append("本轮已消费的鼠标水平转动累计 %.1f°；偏差以目标躯干中心为参考。" % rad_to_deg(mouse_rotation))
		if missed_time >= 0.5:
			aim_lines.append("横向脱靶样本 %.2f秒：落后目标 %.0f%%，超前目标 %.0f%%。" % [
				missed_time, 100 * behind_time / missed_time, 100 * ahead_time / missed_time])
			aim_lines.append("可先降低移动靶速度练习变向后的持续跟随；此项含自身移动带来的相对视角变化。")
		if left_time >= 1 and right_time >= 1:
			aim_lines.append("目标向画面左/右运动时的覆盖率 %.1f%% / %.1f%%（%.1f / %.1f秒）。" % [
				100 * left_aim / left_time, 100 * right_aim / right_time, left_time, right_time])
		else:
			aim_lines.append("左右跟踪样本不均衡，暂不比较方向差异。")
	if now < 3:
		move_lines.append("回合较短，移动规律结论暂不生成；可继续多轮观察。")
	else:
		move_lines.append("静止/低速 %.1f%%；直接AD反向 %d 次；平均交战距离 %.2f米。" % [
			100 * idle_time / now, reversals, distance_sum / now])
		move_lines.append("低于6米 %.2f秒。距离数据受地图、Bot速度与追逐策略影响。" % close_time)
		if idle_time >= 1 and moving_time >= 1:
			move_lines.append("静止/移动时承受伤害速率 %.1f / %.1f 每秒（%.1f / %.1f秒）。" % [
				incoming_idle / idle_time, incoming_moving / moving_time, idle_time, moving_time])
		if episodes.size() >= 6:
			var mean := 0.0
			for duration in episodes:
				mean += duration / episodes.size()
			var variance := 0.0
			for duration in episodes:
				variance += pow(duration - mean, 2) / episodes.size()
			var variation := sqrt(variance) / maxf(mean, 0.001)
			move_lines.append("最近%d段横移：平均%.2f秒，时长波动约为平均值的%.0f%%。" % [episodes.size(), mean, variation * 100])
			if variation < 0.2:
				move_lines.append("横移时长较一致；可以尝试混合长短步，观察受伤是否下降，而非只增加按键频率。")
		else:
			move_lines.append("完整横移段不足6段，不判断节奏是否容易被预判。")
	if assisted or not enough:
		joint_lines.append("配合分析样本不足或受自瞄影响，暂不生成。")
	elif reversals >= 4 and post_time >= 1 and other_time >= 1:
		var after := 100 * post_aim / post_time
		var other := 100 * other_aim / other_time
		joint_lines.append("自身AD变向后250ms覆盖率 %.1f%%；其他时段 %.1f%%（%.2f / %.2f秒）。" % [
			after, other, post_time, other_time])
		joint_lines.append("变向后覆盖率下降，可以单独练习变向时的鼠标补偿。相关性不等于左手导致失误。" \
			if after < other - 15 else "本轮未观察到明显的变向后覆盖率下降；不代表所有场景都已稳定。")
	else:
		joint_lines.append("至少4次直接AD反向，且变向后/其他时段各1秒，才能比较配合。")
	var notice := "按输入功能区分移动侧与瞄准侧，不推断你的实际持鼠手。遮挡、射程外、未开火不计跟踪偏差；结论是本轮现象，不是能力评分。"
	if mixed_settings:
		notice += " 本轮中途改过设置，只展示混合条件下的描述数据。"
		aim_lines = ["中途改过设置，不生成统一条件的瞄准结论。"]
		joint_lines = ["中途改过设置，不生成配合结论。"]
	return {"title": title, "seconds": now, "shots": shots, "hits": hits, "damage": damage,
		"score": score.result(mixed_settings),
		"accuracy": 100.0 * hits / shots if shots > 0 else -1.0, "assisted": assisted,
		"eligible_seconds": eligible_time, "coverage": ratio, "reversals": reversals,
		"settings": setup.duplicate(true), "notice": notice,
		"sections": [{"title": "瞄准侧 / 通常右手", "lines": aim_lines},
			{"title": "移动侧 / 通常左手", "lines": move_lines},
			{"title": "移动与瞄准配合", "lines": joint_lines}]}
