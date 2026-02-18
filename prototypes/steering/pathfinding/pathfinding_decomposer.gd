class_name PathfindingDecomposer
extends Decomposer3D
## Decomposes distant movement goals into nearby waypoints by querying the [Pathfinder3D] service
## for an AStar3D path. Caches the path and advances through waypoints as the agent progresses.

## Distance at which the agent advances to the next waypoint.
@export var waypoint_advance_radius: float = 1.5
## Re-query the path when the goal moves farther than this from the cached goal.
@export var path_replan_threshold: float = 3.0
## Re-query the path when the agent drifts farther than this from its current waypoint.
@export var agent_drift_threshold: float = 5.0

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
	_cached_goal_pos = goal.position
	_path_index = 1 # Skip index 0 (agent's start cell)
	# Clamp in case path has 0 or 1 points
	_path_index = mini(_path_index, maxi(_cached_path.size() - 1, 0))

func _advance_waypoint(agent: Node3D) -> void:
	while _path_index < _cached_path.size() - 1:
		if agent.global_position.distance_to(_cached_path[_path_index]) < waypoint_advance_radius:
			_path_index += 1
		else:
			break