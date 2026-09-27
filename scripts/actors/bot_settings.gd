extends Resource

const DEFAULTS := {
	"aim_level": 35.0,
	"aim_turn_rate": 720.0,
	"move_speed": 5.5,
	"turn_frequency": 1.5,
	"strafe_extent": 3.5,
	"randomness": 85.0,
	"jump_interval": 1.3,
	"air_control": 28.0,
	"aggression": 75.0,
	"engagement_distance": 12.0,
	"flank_chance": 40.0,
	"distance_variation": 7.0,
	"orbit_chance": 40.0,
	"body_width": 1.25,
	"reaction_strength": 65.0,
	"reaction_delay": 180.0
}
const LIMITS := {
	"aim_level": Vector2(0.0, 100.0),
	"aim_turn_rate": Vector2(90.0, 1440.0),
	"move_speed": Vector2(0.0, 20.0),
	"turn_frequency": Vector2(0.5, 6.0),
	"strafe_extent": Vector2(0.4, 5.0),
	"randomness": Vector2(0.0, 100.0),
	"jump_interval": Vector2(0.4, 4.0),
	"air_control": Vector2(0.0, 90.0),
	"aggression": Vector2(0.0, 100.0),
	"engagement_distance": Vector2(6.0, 14.0),
	"flank_chance": Vector2(0.0, 100.0),
	"distance_variation": Vector2(1.0, 12.0),
	"orbit_chance": Vector2(0.0, 100.0),
	"body_width": Vector2(0.75, 2.0),
	"reaction_strength": Vector2(0.0, 100.0),
	"reaction_delay": Vector2(80.0, 600.0)
}

@export var aim_level := 35.0
@export var aim_turn_rate := 720.0
@export var move_speed := 4.5
@export var turn_frequency := 2.5
@export var strafe_extent := 2.0
@export var randomness := 85.0
@export var jump_interval := 1.3
@export var air_control := 28.0
@export var aggression := 75.0
@export var engagement_distance := 12.0
@export var flank_chance := 40.0
@export var distance_variation := 7.0
@export var orbit_chance := 40.0
@export var body_width := 1.25
@export var reaction_strength := 65.0
@export var reaction_delay := 180.0


func update_value(key: String, value: float) -> void:
	if not LIMITS.has(key) or not is_finite(value):
		return
	var limits: Vector2 = LIMITS[key]
	set(key, clampf(value, limits.x, limits.y))


func distance_band() -> Vector2:
	# Large distance variation expands outward more than inward.
	return Vector2(maxf(5.0, engagement_distance - minf(2.0, distance_variation * 0.2)),
		minf(18.0, engagement_distance + distance_variation * 0.45))
