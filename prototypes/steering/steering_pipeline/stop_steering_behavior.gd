class_name StopSteeringBehavior
extends SteeringBehavior3D

@export var time_to_stop: float = 0.1

func get_steering(_agent: Node3D, kinematic: Kinematic3D) -> SteeringOutput3D:
	var result := SteeringOutput3D.new()
	result.linear_acceleration = -kinematic.velocity / time_to_stop
	result.angular_acceleration = -kinematic.angular_velocity / time_to_stop
	return result