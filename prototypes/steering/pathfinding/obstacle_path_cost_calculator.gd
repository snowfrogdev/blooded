class_name ObstaclePathCostCalculator
extends PathCostCalculator
## Marks grid cells overlapping with obstacles as impassable.
##
## Performs sphere-overlap queries at grid build time and caches results.
## The query radius is derived from half the grid's [member Pathfinder3D.cell_size],
## which guarantees no obstacle falls between cell centers undetected. Fine-grained
## agent clearance is handled by the local [AvoidObstacleConstraint].

## Physics collision mask for obstacle detection (default: layer 3).
@export_flags_3d_physics var obstacle_mask: int = 4

var _query_shape: SphereShape3D

func setup(context: Node) -> void:
	var cell_size: float = context.cell_size if "cell_size" in context else 1.5
	_query_shape = SphereShape3D.new()
	_query_shape.radius = cell_size * 0.5

func check_passability(pos: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _query_shape
	params.transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y + 0.5, pos.z))
	params.collision_mask = obstacle_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return space_state.intersect_shape(params, 1).is_empty()
