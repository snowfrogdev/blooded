class_name Goal3D
extends RefCounted
## Represents a steering goal across multiple optional channels.
##
## Each channel (position, rotation, velocity, angular_velocity) can be independently
## set or left unspecified. Unset channels are treated as "don't care" by downstream
## pipeline stages. Multiple targeters can cooperate by each setting different channels.

var has_position: bool = false
var has_rotation: bool = false
var has_velocity: bool = false
var has_angular_velocity: bool = false

var position: Vector3 = Vector3.ZERO
var rotation: float = 0.0 ## Yaw around Y axis
var velocity: Vector3 = Vector3.ZERO
var angular_velocity: float = 0.0 ## Radians per second around Y axis

func merge_from(other: Goal3D) -> void:
	if other.has_position:
		has_position = true
		position = other.position
	if other.has_rotation:
		has_rotation = true
		rotation = other.rotation
	if other.has_velocity:
		has_velocity = true
		velocity = other.velocity
	if other.has_angular_velocity:
		has_angular_velocity = true
		angular_velocity = other.angular_velocity