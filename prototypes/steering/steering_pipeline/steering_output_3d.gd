class_name SteeringOutput3D
extends RefCounted
## Output from steering behaviors representing acceleration (not velocity).
##
## Values are applied to velocity over time: velocity += linear_acceleration * delta.
## This allows smooth acceleration/deceleration rather than instant velocity changes.

var linear_acceleration: Vector3 = Vector3.ZERO ## In units per second squared
var angular_acceleration: float = 0.0 ## In radians per second squared