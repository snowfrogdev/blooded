class_name SeekBehavior
extends ContextBehavior3D
## Fills interest based on a desired direction provided externally (by the path provider).
## Uses dot product against each slot direction — naturally spreads across neighboring slots.

## Set each frame by the orchestrator before [method populate] is called.
var desired_direction: Vector3 = Vector3.ZERO


func populate(_agent: Node3D, _kinematic: Kinematic3D, map: ContextMap3D) -> void:
	if desired_direction.is_zero_approx():
		return
	for i in map.NUM_SLOTS:
		var dot := map.ray_directions[i].dot(desired_direction)
		if dot > 0.0:
			map.merge_interest(i, dot)
