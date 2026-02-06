class_name SteeringPath3D
extends RefCounted
## Ordered sequence of waypoints describing a planned movement path.
##
## Produced by the actuator and inspected by constraints to detect violations
## before movement occurs.

var points: PackedVector3Array = PackedVector3Array() ## Waypoints from current position toward the goal