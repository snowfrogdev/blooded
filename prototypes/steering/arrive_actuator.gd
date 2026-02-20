class_name ArriveActuator
extends Actuator3D

@export var max_speed: float = 4.0
@export var max_acceleration: float = 4.0
@export var slow_radius: float = 5.0
@export var target_radius: float = 0.3
@export var time_to_target: float = 0.15

func get_steering_path(_agent: Node3D, _kinematic: Kinematic3D, goal: Goal3D) -> SteeringPath3D:
	var path := SteeringPath3D.new()
	if goal.has_position:
		path.points.append(goal.position)
	return path

func compute_steering(agent: Node3D, kinematic: Kinematic3D, _path: SteeringPath3D, goal: Goal3D) -> SteeringOutput3D:
	if not goal.has_position:
		return null

	var result := SteeringOutput3D.new()
	var direction = goal.position - agent.position
	var distance = direction.length()

	if distance < target_radius:
		return null

	var target_speed: float
	if distance <= slow_radius:
		target_speed = max_speed * distance / slow_radius
	else:
		target_speed = max_speed

	var target_velocity = direction.normalized() * target_speed

	result.linear_acceleration = target_velocity - kinematic.velocity
	result.linear_acceleration /= time_to_target

	if result.linear_acceleration.length() > max_acceleration:
		result.linear_acceleration = result.linear_acceleration.normalized()
		result.linear_acceleration *= max_acceleration

	return result