class_name PathfindingDecomposer
extends Decomposer3D
## Decomposes distant movement goals into nearby waypoints by querying the [Pathfinder3D] service
## for an AStar3D path, then smooths the result via line-of-sight checks.
## Caches the path and advances through waypoints as the agent progresses.

## Distance at which the agent advances to the next waypoint.
@export var waypoint_advance_radius: float = 1.5
## Re-query the path when the goal moves farther than this from the cached goal.
@export var path_replan_threshold: float = 3.0
## Re-query the path when the agent drifts farther than this from its current waypoint.
@export var agent_drift_threshold: float = 5.0
@export_flags_3d_physics var obstacle_mask: int = 4

var _service: Pathfinder3D
var _service_checked: bool = false
var _cached_path: PackedVector3Array
var _cached_goal_pos: Vector3
var _path_index: int = 0

var debug_path: PackedVector3Array ## Current cached path, read by SteeringDebugDraw.
var debug_waypoint_index: int ## Active waypoint index in the path.

func _init() -> void:
	resource_local_to_scene = true

func decompose(agent: Node3D, goal: Goal3D) -> Goal3D:
	if not _ensure_service(agent):
		return goal
	if not goal.has_position:
		return goal
	if _needs_replan(agent, goal):
		_replan(agent, goal)
	if _cached_path.is_empty() or _cached_path.size() <= 1:
		return goal # Direct line or no path found
	_advance_waypoint(agent)
	var new_goal := Goal3D.new()
	new_goal.merge_from(goal)
	new_goal.has_position = true
	# Use actual goal position for the final waypoint to avoid ~1m grid snap error.l
	if _path_index >= _cached_path.size() - 1:
		new_goal.position = goal.position
	else:
		new_goal.position = _cached_path[_path_index]
	debug_path = _cached_path
	debug_waypoint_index = _path_index
	return new_goal

func _ensure_service(agent: Node3D) -> bool:
	if _service and is_instance_valid(_service):
		return true
	if _service_checked:
		return false
	var node = agent.get_tree().get_first_node_in_group("pathfinding")
	if node:
		_service = node as Pathfinder3D
		if not _service:
			push_warning("PathfindingDecomposer: node in 'pathfinding' group is not a Pathfinder3D")
	else:
		push_warning("PathfindingDecomposer: no node found in 'pathfinding' group; passing goals through unchanged")
	_service_checked = true
	return _service != null

func _needs_replan(agent: Node3D, goal: Goal3D) -> bool:
	if _cached_path.is_empty():
		return true
	if goal.position.distance_to(_cached_goal_pos) > path_replan_threshold:
		return true
	# Replan if agent has drifted too far from current waypoint (e.g. pushed by physics)
	if _path_index < _cached_path.size() and \
		agent.global_position.distance_to(_cached_path[_path_index]) > agent_drift_threshold:
		return true
	return false

func _replan(agent: Node3D, goal: Goal3D) -> void:
	_cached_path = _service.find_path(agent.global_position, goal.position)
	if _cached_path.size() > 2:
		_cached_path = _smooth_path(agent, _cached_path)
	_cached_goal_pos = goal.position
	_path_index = 1 # Skip index 0 (agent's start cell)
	# Clamp in case path has 0 or 1 points
	_path_index = mini(_path_index, maxi(_cached_path.size() - 1, 0))

func _smooth_path(agent: Node3D, path: PackedVector3Array) -> PackedVector3Array:
	var space_state := agent.get_world_3d().direct_space_state
	var result := PackedVector3Array()
	result.append(path[0])
	var current := 0
	while current < path.size() - 1:
		var farthest := current + 1
		for i in range(current + 2, path.size()):
			if _has_line_of_sight(path[current], path[i], space_state):
				farthest = i
		result.append(path[farthest])
		current = farthest
	return result

func _has_line_of_sight(
	from_pos: Vector3, 
	to_pos: Vector3, 
	space_state: PhysicsDirectSpaceState3D
) -> bool:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from_pos + Vector3(0, 0.5, 0)
	query.to = to_pos + Vector3(0, 0.5, 0)
	query.collision_mask = obstacle_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query).is_empty()


func _advance_waypoint(agent: Node3D) -> void:
	while _path_index < _cached_path.size() - 1:
		if agent.global_position.distance_to(_cached_path[_path_index]) < waypoint_advance_radius:
			_path_index += 1
		else:
			break