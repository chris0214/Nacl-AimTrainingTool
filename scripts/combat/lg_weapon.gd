class_name LgWeapon
extends RefCounted

const INTERVAL_TICKS: int = 6
const DAMAGE: int = preload("res://scripts/combat/duel_rules.gd").DAMAGE
const RANGE: float = 24.0
const LAYERS = preload("res://scripts/maps/collision_layers.gd")
var next_shot_tick: int = 0
var interval_ticks: int = INTERVAL_TICKS
var shots: int = 0
var hits: int = 0
var damage: int = 0
var shot_damage := DAMAGE
var range_m := RANGE


func is_due(tick: int, firing: bool) -> bool:
	if not firing or tick < next_shot_tick:
		return false
	# Resuming after an idle gap never replays missed shots.
	next_shot_tick = tick + interval_ticks
	shots += 1
	return true


func trace(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3,
	excluded: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * range_m, LAYERS.WORLD_RAY | 2 | 4)
	query.collide_with_areas = true
	query.exclude = excluded
	var result := space.intersect_ray(query)
	if not result.is_empty() and result.collider.is_in_group("lg_damage_hitbox"):
		result["collider"] = result.collider.get_parent()
	return result


func record_hit() -> void:
	hits += 1
	damage += shot_damage


func reset() -> void:
	next_shot_tick = 0
	shots = 0
	hits = 0
	damage = 0
