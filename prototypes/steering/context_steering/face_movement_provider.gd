class_name FaceMovementProvider
extends FacingProvider
## Faces the unit in its current movement direction.
##
## Returns the velocity direction (XZ plane) when the unit is moving
## above [member min_speed]. Returns [code]Vector3.ZERO[/code] when
## stationary so the unit holds its last facing.

## Minimum speed (units/s) below which the provider has no opinion.
@export var min_speed: float = 0.5


func get_desired_facing(
	_agent: Node3D, _kinematic: Kinematic3D, _moveable: Moveable3D
) -> Vector3:
	var vel := _kinematic.velocity
	var xz := Vector3(vel.x, 0.0, vel.z)
	if xz.length_squared() < min_speed * min_speed:
		return Vector3.ZERO
	return xz.normalized()
