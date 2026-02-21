class_name ObstacleDangerBehavior
extends ContextBehavior3D
## Fills danger by casting a raycast along each of the 24 slot directions.
## Graduated danger: closer obstacles produce higher values.
## Spreads danger to adjacent slots so the agent maintains body clearance.

## Ray length in meters.
@export var look_ahead: float = 3.0
@export_flags_3d_physics var obstacle_mask: int = 4
## Fraction of danger to spread to adjacent slots.
@export var neighbor_spread: float = 0.5


func _init() -> void:
	resource_local_to_scene = true


func populate(agent: Node3D, _kinematic: Kinematic3D, map: ContextMap3D) -> void:
	var space_state := agent.get_world_3d().direct_space_state
	var origin := agent.global_position + Vector3(0, 0.5, 0)
	var dangers: Array[float] = []
	dangers.resize(map.NUM_SLOTS)
	dangers.fill(0.0)

	for i in map.NUM_SLOTS:
		var query := PhysicsRayQueryParameters3D.new()
		query.from = origin
		query.to = origin + map.ray_directions[i] * look_ahead
		query.collision_mask = obstacle_mask
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			var distance := origin.distance_to(result.position)
			dangers[i] = 1.0 - (distance / look_ahead)

	# Apply dangers with neighbor spread.
	for i in map.NUM_SLOTS:
		if dangers[i] > 0.0:
			map.merge_danger(i, dangers[i])
			var prev := posmod(i - 1, map.NUM_SLOTS)
			var next := posmod(i + 1, map.NUM_SLOTS)
			map.merge_danger(prev, dangers[i] * neighbor_spread)
			map.merge_danger(next, dangers[i] * neighbor_spread)
