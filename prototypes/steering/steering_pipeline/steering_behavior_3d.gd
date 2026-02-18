@abstract class_name SteeringBehavior3D
extends Resource
## Base class for steering behaviors. Subclasses must override `get_steering()`

@abstract func get_steering(agent: Node3D, kinematic: Kinematic3D) -> SteeringOutput3D