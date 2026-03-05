class_name FacingProvider
extends Resource
## Abstract base for facing direction providers.
##
## Returns the desired facing direction for a unit. The orchestrator
## ([ContextSteering3D]) handles smooth rotation toward this direction
## using a reach-orientation algorithm.
##
## Return [code]Vector3.ZERO[/code] to indicate "no opinion" — the unit
## will hold its current facing.


func get_desired_facing(
	_agent: Node3D, _kinematic: Kinematic3D, _moveable: Moveable3D
) -> Vector3:
	push_error("FacingProvider.get_desired_facing() is abstract — subclass must override")
	return Vector3.ZERO
