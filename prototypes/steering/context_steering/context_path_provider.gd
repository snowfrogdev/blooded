class_name ContextPathProvider
extends Resource
## Provides a desired direction for the seek behavior by querying [Pathfinder3D]
## for a path, projecting onto it, and computing a lookahead point.
## Adapted from [PathfindingDecomposer] — keeps path caching, replanning,
## projection, LOS-based smoothing, snapped-goal update, and adaptive lookahead.
## Includes optional lookahead LOS validation (toggleable via [member los_check_enabled]).

## How far ahead on the path to place the lookahead point.
@export var lookahead_distance: float = 6.0
## Re-query the path when the agent drifts farther than this from the cached path.
@export var agent_drift_threshold: float = 5.0
@export_flags_3d_physics var obstacle_mask: int = 4
## Terrain collision layer for path-smoothing LOS checks. Straight-line rays
## that include this mask detect terrain features (mounds, ridges) that protrude
## above the line between two waypoints.
@export_flags_3d_physics var terrain_mask: int = 1
## Half-width of the unit body for flanking LOS checks.
@export var agent_radius: float = 0.31

@export_group("Adaptive Lookahead")
## Turn angle (radians) at a waypoint considered sharp enough to reduce lookahead.
@export var sharp_turn_threshold: float = PI / 4.0
## Minimum fraction of base lookahead distance at the sharpest turns.
@export_range(0.1, 1.0) var min_lookahead_factor: float = 0.3

@export_group("Line of Sight")
## When enabled, verifies the agent can see the lookahead point via raycasts.
## If obstructed, pulls back to the farthest visible position along the path.
@export var los_check_enabled: bool = true
## Number of binary-search iterations to refine the visible/non-visible boundary.
@export_range(0, 8) var los_refine_iterations: int = 4
## Minimum Euclidean distance from agent to the lookahead target. Prevents the
## adaptive lookahead from collapsing too close at sharp corners.
@export var min_goal_distance: float = 0.5

var _service: Pathfinder3D
var _service_checked: bool = false
var _height_provider: HeightProvider
var _cached_path: PackedVector3Array
var _cached_goal_pos: Vector3
var _snapped_goal: Vector3
var _proj_seg: int
var _proj_t: float
var _last_seen_target: Vector3

## Current cached path, read by [ContextDebugDraw].
var debug_path: PackedVector3Array
## Lookahead target on the path. Read by the orchestrator for actuator arrive
## logic and by [ContextDebugDraw] for visualization.
var lookahead_target: Vector3


func _init() -> void:
	resource_local_to_scene = true


## Returns the normalized direction toward the lookahead point on the path.
## Returns [constant Vector3.ZERO] if there is no target or no pathfinder.
func get_desired_direction(agent: Node3D, moveable: Moveable3D) -> Vector3:
	if not moveable or not moveable.has_target:
		_cached_path = PackedVector3Array()
		debug_path = PackedVector3Array()
		return Vector3.ZERO

	if not _ensure_service(agent):
		return Vector3.ZERO

	var goal_pos := moveable.target_position
	if _needs_replan(goal_pos):
		_replan(agent, moveable)
	_last_seen_target = goal_pos
	if _cached_path.is_empty() or _cached_path.size() <= 1:
		# Same-cell or unreachable — point directly at target.
		debug_path = PackedVector3Array()
		lookahead_target = goal_pos
		var direct := goal_pos - agent.global_position
		direct.y = 0.0
		if direct.length_squared() < 0.0001:
			return Vector3.ZERO
		return direct.normalized()

	var path_dist := _update_projection(agent.global_position)
	if path_dist > agent_drift_threshold:
		_replan(agent, moveable)
		if _cached_path.is_empty() or _cached_path.size() <= 1:
			return Vector3.ZERO
		_update_projection(agent.global_position)

	var effective_lookahead := _get_adaptive_lookahead()
	var target_point := _get_lookahead_point(effective_lookahead)

	# LOS validation: ensure the agent can see the lookahead point. If obstructed,
	# pull back to the farthest visible position along the path.
	if los_check_enabled:
		var space_state := agent.get_world_3d().direct_space_state
		if not _has_line_of_sight(agent.global_position, target_point, space_state):
			target_point = _find_visible_lookahead(
				agent.global_position, effective_lookahead, space_state)

	# Euclidean distance floor: at sharp corners, path-distance and straight-line
	# distance diverge. Prevent the lookahead from collapsing too close.
	if agent.global_position.distance_to(target_point) < min_goal_distance:
		target_point = _get_lookahead_point(lookahead_distance)

	debug_path = _cached_path.duplicate()
	debug_path[0] = agent.global_position
	lookahead_target = target_point

	var dir := target_point - agent.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()


## Returns the potentially-snapped goal position for actuator arrive logic.
func get_goal_position(moveable: Moveable3D) -> Vector3:
	if _cached_path.size() >= 2:
		return _snapped_goal
	return moveable.target_position


## Invalidates cached path state. Called by the orchestrator when the system
## is re-enabled after a toggle.
func clear_cache() -> void:
	_cached_path = PackedVector3Array()
	_cached_goal_pos = Vector3.ZERO
	_snapped_goal = Vector3.ZERO
	_proj_seg = 0
	_proj_t = 0.0
	debug_path = PackedVector3Array()
	lookahead_target = Vector3.ZERO
	_last_seen_target = Vector3.ZERO


# --- Internals ---


func _ensure_service(agent: Node3D) -> bool:
	if _service and is_instance_valid(_service):
		return true
	if _service_checked:
		return false
	var node = agent.get_tree().get_first_node_in_group("pathfinding")
	if node:
		_service = node as Pathfinder3D
		if not _service:
			push_warning("ContextPathProvider: node in 'pathfinding' group is not a Pathfinder3D")
		else:
			_height_provider = _service.height_provider
	else:
		push_warning("ContextPathProvider: no node found in 'pathfinding' group")
	_service_checked = true
	return _service != null


func _needs_replan(goal_pos: Vector3) -> bool:
	if _cached_path.is_empty():
		return true
	if goal_pos != _last_seen_target:
		return true
	return false


func _replan(agent: Node3D, moveable: Moveable3D) -> void:
	var goal_pos := moveable.target_position
	_cached_path = _service.find_path(agent.global_position, goal_pos)
	if _cached_path.size() >= 2:
		_cached_path[0] = agent.global_position
		if _service.is_position_free(goal_pos):
			_snapped_goal = goal_pos
		else:
			_snapped_goal = _cached_path[_cached_path.size() - 1]
			# Target in a blocked cell — update Moveable3D so arrival detection works.
			moveable.target_position = _snapped_goal
		_cached_path[_cached_path.size() - 1] = _snapped_goal
	else:
		# Empty path: either same-cell (fine) or unreachable (should stop).
		if not _service.is_reachable(agent.global_position, goal_pos):
			moveable.clear_target()
			_cached_path = PackedVector3Array()
			return
		_snapped_goal = goal_pos
	if _cached_path.size() > 2:
		_cached_path = _smooth_path(agent, _cached_path)
	_cached_goal_pos = goal_pos


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


func _get_adaptive_lookahead() -> float:
	var base := lookahead_distance
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


func _find_visible_lookahead(
	agent_pos: Vector3,
	lookahead_dist: float,
	space_state: PhysicsDirectSpaceState3D
) -> Vector3:
	var lo := 0.0
	var hi := lookahead_dist
	for _iter in los_refine_iterations:
		var mid := (lo + hi) * 0.5
		var point := _get_lookahead_point(mid)
		if _has_line_of_sight(agent_pos, point, space_state):
			lo = mid
		else:
			hi = mid
	lo = maxf(lo, min_goal_distance)
	return _get_lookahead_point(lo)


func _distance_along_path_to(idx: int) -> float:
	var a := _cached_path[_proj_seg]
	var b := _cached_path[_proj_seg + 1]
	var dist := a.distance_to(b) * (1.0 - _proj_t)
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
			if _has_straight_line_of_sight(path[current], path[i], space_state):
				farthest = i
		result.append(path[farthest])
		current = farthest
	return result


const LOS_STEP_SIZE: float = 1.0

func _has_line_of_sight(
	from_pos: Vector3,
	to_pos: Vector3,
	space_state: PhysicsDirectSpaceState3D
) -> bool:
	var lift := Vector3(0, 0.5, 0)

	var offsets: Array[Vector3] = [Vector3.ZERO]
	var dir := to_pos - from_pos
	if dir.length_squared() > 0.001 and agent_radius > 0.0:
		var right := dir.normalized().cross(Vector3.UP) * agent_radius
		offsets.append(-right)
		offsets.append(right)

	var xz_dist := Vector2(dir.x, dir.z).length()
	var steps := maxi(1, ceili(xz_dist / LOS_STEP_SIZE))
	var inv_steps := 1.0 / steps

	for offset in offsets:
		var prev := _terrain_lifted_point(from_pos + offset, lift)
		for i in range(1, steps + 1):
			var t := i * inv_steps
			var sample_xz := from_pos.lerp(to_pos, t) + offset
			var curr := _terrain_lifted_point(sample_xz, lift)
			if not _cast_los_ray(prev, curr, space_state):
				return false
			prev = curr

	return true


func _terrain_lifted_point(pos: Vector3, lift: Vector3) -> Vector3:
	if _height_provider:
		return Vector3(pos.x, _height_provider.get_height(pos), pos.z) + lift
	return pos + lift


## Straight-line LOS check used by path smoothing. Casts rays directly between
## lifted endpoints (not surface-following) so terrain features like mounds and
## ridges that protrude above the line are detected.
func _has_straight_line_of_sight(
	from_pos: Vector3, to_pos: Vector3, space_state: PhysicsDirectSpaceState3D
) -> bool:
	var lift := Vector3(0, 0.5, 0)
	var from_lifted := from_pos + lift
	var to_lifted := to_pos + lift

	# Center ray
	if not _cast_smoothing_ray(from_lifted, to_lifted, space_state):
		return false

	# Flanking rays for agent width
	var dir := to_pos - from_pos
	if dir.length_squared() > 0.001 and agent_radius > 0.0:
		var right := dir.normalized().cross(Vector3.UP) * agent_radius
		if not _cast_smoothing_ray(from_lifted - right, to_lifted - right, space_state):
			return false
		if not _cast_smoothing_ray(from_lifted + right, to_lifted + right, space_state):
			return false

	return true


func _cast_smoothing_ray(
	from: Vector3, to: Vector3, space_state: PhysicsDirectSpaceState3D
) -> bool:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = obstacle_mask | terrain_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query).is_empty()


func _cast_los_ray(from: Vector3, to: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = obstacle_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query).is_empty()
