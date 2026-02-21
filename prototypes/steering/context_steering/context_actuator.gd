class_name ContextActuator
extends Resource
## Converts the context map's evaluate result into acceleration.
## Uses min(interest_speed, arrive_speed) — danger-reduced interest handles
## obstacle/turn speed modulation emergently; the arrive ramp handles
## open-field stopping at the destination.

@export var max_speed: float = 4.0
@export var max_acceleration: float = 4.0
## Distance at which the agent begins to decelerate toward the goal.
@export var slow_radius: float = 3.0
## Arrival threshold — returns null when within this distance.
@export var target_radius: float = 0.3
@export var time_to_target: float = 0.15


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
	var interest_speed := strength * max_speed

	# Distance-based arrive ramp for open-field stopping.
	var arrive_speed: float
	if distance <= slow_radius:
		arrive_speed = max_speed * distance / slow_radius
	else:
		arrive_speed = max_speed

	var target_speed := minf(interest_speed, arrive_speed)
	var target_velocity := direction * target_speed

	var safe_ttt := maxf(time_to_target, 0.01)
	var result := SteeringOutput3D.new()
	result.linear_acceleration = (target_velocity - kinematic.velocity) / safe_ttt

	if result.linear_acceleration.length() > max_acceleration:
		result.linear_acceleration = result.linear_acceleration.normalized() * max_acceleration

	return result
