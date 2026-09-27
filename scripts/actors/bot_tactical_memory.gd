extends RefCounted

var clock := 0.0
var events: Array[Dictionary] = []
var held_lateral := 0.0
var held_closing := 0.0
var lateral_bias := 0.0
var closing_bias := 0.0
var last_observation := -10.0
var incoming := 0.0
var outgoing := 0.0
var damage_queue: Array[Dictionary] = []


func clear() -> void:
	clock = 0.0
	events.clear()
	damage_queue.clear()
	held_lateral = 0.0
	held_closing = 0.0
	lateral_bias = 0.0
	closing_bias = 0.0
	last_observation = -10.0
	incoming = 0.0
	outgoing = 0.0


func advance(delta: float) -> void:
	clock += delta
	while not events.is_empty() and events[0].at < clock - 3.0:
		events.pop_front()
	while not damage_queue.is_empty() and damage_queue[0].at <= clock:
		var sample: Dictionary = damage_queue.pop_front()
		incoming = minf(150.0, incoming + sample.incoming)
		outgoing = minf(150.0, outgoing + sample.outgoing)
	var decay := exp(-delta / 1.0)
	incoming *= exp(-delta / 1.5)
	outgoing *= exp(-delta / 1.5)
	var fresh := clock - last_observation <= 3.0
	lateral_bias = lerpf(held_lateral if fresh else 0.0, lateral_bias, decay)
	closing_bias = lerpf(held_closing if fresh else 0.0, closing_bias, decay)


func observe(lateral: float, closing: float) -> void:
	# Only callers with already-matured input observations may update the memory.
	var reversed := lateral * held_lateral < -0.1
	events.append({"at": clock, "reversed": reversed})
	if events.size() > 64:
		events.pop_front()
	held_lateral = lateral
	held_closing = closing
	last_observation = clock


func reversal_tendency() -> float:
	var count := 0
	for event in events:
		count += int(event.reversed)
	return clampf(count / 8.0, 0.0, 1.0)


func damage_received(amount: int, delay_seconds: float, dealt: bool = false) -> void:
	damage_queue.append({"at": clock + delay_seconds,
		"incoming": 0 if dealt else amount, "outgoing": amount if dealt else 0})
	if damage_queue.size() > 64:
		damage_queue.pop_front()


func pressure_bias() -> float:
	return clampf((outgoing - incoming) / 100.0, -1.0, 1.0)
