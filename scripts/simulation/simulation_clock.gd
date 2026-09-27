class_name SimulationClock
extends RefCounted

const HZ: int = 120
const STEP: float = 1.0 / HZ
const RATES := [120, 240, 360]
var hz: int = HZ
const STALL_USEC: int = 250000
const BACKLOG_USEC: int = 100000
var tick: int = 0
var epoch_usec: int = 0
var last_frame_usec: int = 0
var frame_index: int = -1
var lagged_frames: int = 0
var backlog_usec: int = 0
var max_gap_usec: int = 0
var invalid: bool = false


func reset(now_usec: int) -> void:
	tick = 0
	invalid = false
	rebase(now_usec)


func rebase(now_usec: int) -> void:
	epoch_usec = now_usec - int(tick * 1000000.0 / hz)
	last_frame_usec = now_usec
	frame_index = -1
	lagged_frames = 0
	backlog_usec = 0


func guard_frame(now_usec: int, current_frame: int) -> bool:
	if frame_index == current_frame:
		return not invalid
	frame_index = current_frame
	var gap := now_usec - last_frame_usec
	max_gap_usec = maxi(max_gap_usec, gap)
	last_frame_usec = now_usec
	backlog_usec = maxi(0, now_usec - deadline_usec())
	if backlog_usec > BACKLOG_USEC:
		lagged_frames += 1
	else:
		lagged_frames = 0
	if gap >= STALL_USEC or lagged_frames >= 3:
		invalid = true
	return not invalid


func deadline_usec() -> int:
	return epoch_usec + int((tick + 1) * 1000000.0 / hz)
