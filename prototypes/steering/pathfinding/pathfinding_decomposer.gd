class_name PathfindingDecomposer
extends Decomposer3D
## Decomposes distant movement goals into nearby waypoints by querying the [Pathfinder3D] service
## for an AStar3D path, then smooths the result via line-of-sight checks.
## Uses continuous path projection (Reynolds-style) to produce a lookahead sub-goal that
## smoothly curves around corners, rather than chasing discrete waypoints.

## Extra distance beyond the actuator's slow_radius for the lookahead sub-goal.
## The effective lookahead is slow_radius + this margin, ensuring the agent
## reaches full speed during path following and only decelerates at the endpoint.
@export var lookahead_margin: float = 1.0
## Re-query the path when the goal moves farther than this from the cached goal.
@export var path_replan_threshold: float = 3.0
## Re-query the path when the agent drifts farther than this from the cached path.
@export var agent_drift_threshold: float = 5.0
@export_flags_3d_physics var obstacle_mask: int = 4
## Half-width of the unit body. The line-of-sight check for path smoothing casts
## flanking rays offset by this amount, ensuring smoothed paths maintain clearance.
@export var agent_radius: float = 0.31

@export_group("Adaptive Lookahead")
## Turn angle (radians) at a waypoint that is considered sharp enough to trigger
## lookahead reduction. Turns sharper than this make the decomposer place the
## sub-goal closer, inducing earlier deceleration via the actuator's arrive ramp.
@export var sharp_turn_threshold: float = PI / 4.0
## Minimum fraction of the base lookahead distance. Prevents the lookahead from
## collapsing too close to the agent even at very sharp turns.
@export_range(0.1, 1.0) var min_lookahead_factor: float = 0.3
## Minimum Euclidean distance from agent to the decomposed goal. At sharp
## corners, path-distance and straight-line distance diverge; if the adaptive
## lookahead collapses the target closer than this, the base lookahead is used.
@export var min_goal_distance: float = 0.5

var _service: Pathfinder3D
var _service_checked: bool = false
var _cached_path: PackedVector3Array
var _cached_goal_pos: Vector3
var _snapped_goal: Vector3 ## Actual reachable endpoint (may differ from goal if target is in a blocked cell).
var _proj_seg: int ## Segment index of latest projection.
var _proj_t: float ## Parametric t on the projected segment.
var _lookahead_distance: float ## Computed at startup: slow_radius + lookahead_margin.

var debug_path: PackedVector3Array ## Current cached path, read by SteeringDebugDraw.
var debug_lookahead_point: Vector3 ## Lookahead target, read by SteeringDebugDraw.

func _init() -> void:
	resource_local_to_scene = true

func decompose(agent: Node3D, goal: Goal3D) -> Goal3D:
	if not _ensure_service(agent):
		return goal
	_ensure_lookahead(agent)
	if not goal.has_position:
		_cached_path = PackedVector3Array()
		return goal
	if _needs_replan(agent, goal):
		_replan(agent, goal)
	if _cached_path.is_empty() or _cached_path.size() <= 1:
		return goal

	var path_dist := _update_projection(agent.global_position)
	if path_dist > agent_drift_threshold:
		_replan(agent, goal)
		if _cached_path.is_empty() or _cached_path.size() <= 1:
			return goal
		_update_projection(agent.global_position)

	var effective_lookahead := _get_adaptive_lookahead()
	var target_point := _get_lookahead_point(effective_lookahead)

	# Euclidean distance floor: at sharp corners, path-distance and straight-line
	# distance diverge. If the adaptive lookahead collapsed the target too close,
	# extend to the full base lookahead so the actuator doesn't treat it as arrived.
	if agent.global_position.distance_to(target_point) < min_goal_distance:
		target_point = _get_lookahead_point(_lookahead_distance)

	var new_goal := Goal3D.new()
	new_goal.merge_from(goal)
	new_goal.has_position = true
	new_goal.position = target_point

	debug_path = _cached_path.duplicate()
	debug_path[0] = agent.global_position
	debug_lookahead_point = target_point
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

func _ensure_lookahead(agent: Node3D) -> void:
	if _lookahead_distance > 0:
		return
	for child in agent.get_children():
		if child is SteeringPipeline3D and child.actuator:
			var slow_r = child.actuator.get("slow_radius")
			if slow_r != null:
				_lookahead_distance = slow_r + lookahead_margin
				return
	_lookahead_distance = lookahead_margin + 3.0 # Fallback

func _needs_replan(_agent: Node3D, goal: Goal3D) -> bool:
	if _cached_path.is_empty():
		return true
	if goal.position.distance_to(_cached_goal_pos) > path_replan_threshold:
		return true
	return false

func _replan(agent: Node3D, goal: Goal3D) -> void:
	_cached_path = _service.find_path(agent.global_position, goal.position)
	# Replace both endpoints with actual positions BEFORE smoothing,
	# so LOS checks verify against real start/end, not cell centers.
	if _cached_path.size() >= 2:
		_cached_path[0] = agent.global_position
		if _service.is_position_free(goal.position):
			_snapped_goal = goal.position
		else:
			_snapped_goal = _cached_path[_cached_path.size() - 1]
			# Target was in a blocked cell — update Moveable3D so arrival detection works.
			var moveable := agent.get_node_or_null("Moveable3D") as Moveable3D
			if moveable:
				moveable.target_position = _snapped_goal
		_cached_path[_cached_path.size() - 1] = _snapped_goal
	else:
		_snapped_goal = goal.position
	if _cached_path.size() > 2:
		_cached_path = _smooth_path(agent, _cached_path)
	_cached_goal_pos = goal.position

## Projects [param pos] onto [member _cached_path] and stores the result in
## [member _proj_seg] / [member _proj_t]. Returns distance from pos to the path.
func _update_projection(pos: Vector3) -> float:
	var best_dist_sq := INF
	for i in range(_cached_path.size() - 1):
		var a := _cached_path[i]
		var b := _cached_path[i + 1]
		var ab := b - a
		var ab_len_sq := ab.length_squared()
		if ab_len_sq < 0.0001:
			continue
		var t := clampf((pos - a).dot(ab) / ab_len_sq, 0.0, 1.0)
		var closest := a + ab * t
		var dist_sq := pos.distance_squared_to(closest)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			_proj_seg = i
			_proj_t = t
	return sqrt(best_dist_sq)

## From the current projection, advances [param distance] along the path.
## Returns the target point. When the lookahead overshoots the path endpoint,
## returns the endpoint (which is _snapped_goal after _replan replaces it).
func _get_lookahead_point(distance: float) -> Vector3:
	var a := _cached_path[_proj_seg]
	var b := _cached_path[_proj_seg + 1]
	var seg_len := a.distance_to(b)
	var remaining := seg_len * (1.0 - _proj_t)
	if distance <= remaining and seg_len > 0.0001:
		return a.lerp(b, _proj_t + distance / seg_len)
	distance -= remaining
	for i in range(_proj_seg + 1, _cached_path.size() - 1):
		seg_len = _cached_path[i].distance_to(_cached_path[i + 1])
		if distance <= seg_len and seg_len > 0.0001:
			return _cached_path[i].lerp(_cached_path[i + 1], distance / seg_len)
		distance -= seg_len
	return _cached_path[_cached_path.size() - 1]

## Returns a lookahead distance reduced when a sharp turn is detected ahead on
## the path. Placing the sub-goal closer triggers the actuator's arrive
## deceleration before the corner.
func _get_adaptive_lookahead() -> float:
	var base := _lookahead_distance
	for i in range(_proj_seg + 1, _cached_path.size() - 1):
		var dist := _distance_along_path_to(i)
		if dist > base * 2.0:
			break
		var dir_in := (_cached_path[i] - _cached_path[i - 1]).normalized()
		var dir_out := (_cached_path[i + 1] - _cached_path[i]).normalized()
		var dot := clampf(dir_in.dot(dir_out), -1.0, 1.0)
		var turn_angle := acos(dot)
		if turn_angle > sharp_turn_threshold:
			var proximity := clampf(dist / base, min_lookahead_factor, 1.0)
			return base * proximity
	return base


## Returns the distance along the path from the current projection to waypoint [param idx].
func _distance_along_path_to(idx: int) -> float:
	# Remaining distance on the current projected segment.
	var a := _cached_path[_proj_seg]
	var b := _cached_path[_proj_seg + 1]
	var dist := a.distance_to(b) * (1.0 - _proj_t)
	# Sum full segments between projection segment end and the target waypoint.
	for i in range(_proj_seg + 1, idx):
		dist += _cached_path[i].distance_to(_cached_path[i + 1])
	return dist


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
	var lift := Vector3(0, 0.5, 0)
	var f := from_pos + lift
	var t := to_pos + lift

	# Center ray.
	if not _cast_los_ray(f, t, space_state):
		return false

	# Flanking rays offset by agent_radius perpendicular to the segment.
	var dir := to_pos - from_pos
	if dir.length_squared() > 0.001 and agent_radius > 0.0:
		var right := dir.normalized().cross(Vector3.UP) * agent_radius
		if not _cast_los_ray(f - right, t - right, space_state):
			return false
		if not _cast_los_ray(f + right, t + right, space_state):
			return false

	return true


func _cast_los_ray(from: Vector3, to: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = obstacle_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query).is_empty()
