class_name ContextActuator
extends Resource
## Converts the context map's evaluate result into acceleration.
## Uses min(interest_speed, arrive_speed) — danger-reduced interest handles
## obstacle/turn speed modulation emergently; the arrive ramp handles
## open-field stopping at the destination.

@export var max_speed: float = 4.0
@export var min_speed: float = 1.5
@export var max_acceleration: float = 4.0
## Distance at which the agent begins to decelerate toward the goal.
@export var slow_radius: float = 3.0
## Arrival threshold — returns null when within this distance.
@export var target_radius: float = 0.3
@export var time_to_target: float = 0.15

@export_group("Slope")
## How far ahead (meters) to sample terrain height for slope detection.
@export var slope_sample_distance: float = 0.5
## Speed reduction at maximum slope when going uphill (0.6 → 40% of normal speed).
@export var uphill_penalty: float = 0.6
## Speed increase at maximum slope when going downhill (0.2 → 120% of normal speed).
@export var downhill_bonus: float = 0.2
## Slope ratio (rise/run) treated as maximum. Matches tan(45°) = 1.0.
@export var max_slope_ratio: float = 1.0

var _height_provider: HeightProvider


func setup(height_provider: HeightProvider) -> void:
	_height_provider = height_provider


func compute_steering(
	map: ContextMap3D,
	agent: Node3D,
	kinematic: Kinematic3D,
	goal_pos: Vector3
) -> SteeringOutput3D:
	var direction := map.chosen_direction
	var strength := map.chosen_strength
	var distance := agent.global_position.distance_to(goal_pos)

	if distance < target_radius:
		return null

	# Interest-derived speed: emergent from danger masking.
	var arrive_speed := strength * max_speed
	arrive_speed *= _get_slope_factor(agent.global_position, direction)

	if distance <= slow_radius:
		arrive_speed = arrive_speed * distance / slow_radius

	var target_speed := maxf(arrive_speed, min_speed)
	var target_velocity := direction * target_speed

	var safe_ttt := maxf(time_to_target, 0.01)
	var result := SteeringOutput3D.new()
	result.linear_acceleration = (target_velocity - kinematic.velocity) / safe_ttt

	if result.linear_acceleration.length() > max_acceleration:
		result.linear_acceleration = result.linear_acceleration.normalized() * max_acceleration

	return result


func _get_slope_factor(position: Vector3, direction: Vector3) -> float:
	if not _height_provider:
		return 1.0
	var ahead := position + direction * slope_sample_distance
	var dy := _height_provider.get_height(ahead) - _height_provider.get_height(position)
	var slope := dy / slope_sample_distance
	var t := clampf(absf(slope) / max_slope_ratio, 0.0, 1.0)
	if slope > 0.0:
		return 1.0 - uphill_penalty * t
	return 1.0 + downhill_bonus * t
