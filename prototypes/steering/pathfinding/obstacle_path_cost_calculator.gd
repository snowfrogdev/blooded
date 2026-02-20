class_name ObstaclePathCostCalculator
extends PathCostCalculator
## Marks grid cells overlapping with obstacles as impassable.
##
## Performs box-overlap queries at grid build time using [BoxShape3D] sized to each
## cell's footprint. Shapes are cached per subdivision level to avoid per-call
## allocation. Fine-grained agent clearance is handled by the local
## [AvoidObstacleConstraint].

## Physics collision mask for obstacle detection (default: layer 3).
@export_flags_3d_physics var obstacle_mask: int = 4
## Additional clearance buffer (meters) added to each side of the cell's overlap box.
## Cells within this distance of an obstacle are marked blocked, ensuring paths
## maintain minimum clearance at the grid level. Set to 0.0 to disable (default).
@export var inflation: float = 0.0

var _shapes_by_half_size: Dictionary = {} # float -> BoxShape3D

func setup(context: Node) -> void:
	# Pre-create BoxShape3D for each power-of-2 subdivision level.
	var min_half: float = context.min_cell_size * 0.5 if "min_cell_size" in context else 0.5
	var grid_min: Vector2 = context.grid_min if "grid_min" in context else Vector2(-64, -64)
	var grid_max: Vector2 = context.grid_max if "grid_max" in context else Vector2(64, 64)
	var span := maxf(grid_max.x - grid_min.x, grid_max.y - grid_min.y)
	var root_size := 1.0
	while root_size < span:
		root_size *= 2.0

	var half := root_size * 0.5
	while half >= min_half:
		var box := BoxShape3D.new()
		var side := half * 2.0 + inflation * 2.0
		box.size = Vector3(side, 100.0, side)
		_shapes_by_half_size[half] = box
		half *= 0.5


func check_passability(
	pos: Vector3,
	cell_half_size: float,
	space_state: PhysicsDirectSpaceState3D
) -> bool:
	var shape: BoxShape3D = _shapes_by_half_size.get(cell_half_size)
	if not shape:
		# Fallback: create on-the-fly for unexpected sizes
		shape = BoxShape3D.new()
		var side := cell_half_size * 2.0 + inflation * 2.0
		shape.size = Vector3(side, 100.0, side)
		_shapes_by_half_size[cell_half_size] = shape
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y, pos.z))
	params.collision_mask = obstacle_mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return space_state.intersect_shape(params, 1).is_empty()
	
