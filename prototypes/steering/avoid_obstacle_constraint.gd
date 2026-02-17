class_name AvoidObstacleConstraint extends Constraint3D
## Detects obstacles along the steering path and suggests sub-goals that route
## around them at the obstacle's shape edge plus a clearance margin.

## Additive clearance in meters beyond the obstacle's shape edge.
@export var margin: float = 0.5
## Half-width of the agent body for whisker ray offset.
@export var agent_radius: float = 0.5
## Physics collision mask for obstacle detection (default: layer 3).
@export_flags_3d_physics var obstacle_mask: int = 4
## When true, all 3 whisker rays are always cast and debug state is populated.
## When false, rays short-circuit on first hit for performance.
@export var debug_enabled: bool = false

# Cached violation data from is_violated(), consumed by suggest().
var _collider: Node3D
var _segment_start: Vector3
var _segment_end: Vector3
# Side commitment — prevents oscillation when the same obstacle is detected across frames.
var _committed_collider: Node3D
var _committed_position: Vector3

## Debug state — populated when debug_enabled is true, read by SteeringDebugDraw.
var debug_rays: Array[Dictionary] = []
var debug_violated: bool = false
var debug_candidate_a: Vector3
var debug_candidate_b: Vector3
var debug_chosen: Vector3
var debug_obstacle_center: Vector3
var debug_half_width: float

func is_violated(agent: Node3D, _kinematic: Kinematic3D, path: SteeringPath3D) -> bool:
	_collider = null
	debug_violated = false
	if debug_enabled:
		debug_rays.clear()

	var space_state := agent.get_world_3d().direct_space_state
	var prev := agent.global_position

	for i in path.points.size():
		var next := path.points[i]

		# Raise ray origin/end above ground to avoid terrain surface hits.
		var from := Vector3(prev.x, prev.y + 0.5, prev.z)
		var to := Vector3(next.x, next.y + 0.5, next.z)

		var result := _cast_whisker_rays(space_state, from, to)

		if not result.is_empty():
			_collider = result.collider as Node3D
			_segment_start = prev
			_segment_end = next
			debug_violated = true
			return true

		prev = next

	return false


## Casts center + two flanking rays to approximate the agent's body width.
## When debug_enabled is true, all 3 rays are always cast and recorded in debug_rays.
func _cast_whisker_rays(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var dir := to - from
	var has_width := dir.length_squared() > 0.001
	var right := dir.normalized().cross(Vector3.UP) * agent_radius if has_width else Vector3.ZERO

	var origins: Array[Vector3] = [from, from - right, from + right]
	var ends: Array[Vector3] = [to, to - right, to + right]

	var first_hit := {}

	for i in 3:
		# Skip flanking rays if segment is too short for a meaningful perpendicular.
		if i > 0 and not has_width:
			if debug_enabled:
				debug_rays.append({from = from, to = to, hit = false, hit_point = Vector3.ZERO})
			continue

		var query := PhysicsRayQueryParameters3D.create(origins[i], ends[i], obstacle_mask)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result := space_state.intersect_ray(query)

		if debug_enabled:
			debug_rays.append({
				from = origins[i],
				to = ends[i],
				hit = not result.is_empty(),
				hit_point = result.position if not result.is_empty() else Vector3.ZERO,
			})

		if not result.is_empty() and first_hit.is_empty():
			first_hit = result
			if not debug_enabled:
				return first_hit

	return first_hit


func suggest(agent: Node3D, _path: SteeringPath3D, goal: Goal3D) -> Goal3D:
	var new_goal := Goal3D.new()
	new_goal.merge_from(goal)

	if not new_goal.has_position or not _collider:
		return new_goal
	
	# Segment direction in XZ plane.
	var segment_dir := Vector3(
		_segment_end.x - _segment_start.x, 0.0, _segment_end.z - _segment_start.z
	)
	if segment_dir.length_squared() < 0.001:
		return new_goal
	segment_dir = segment_dir.normalized()

	# Perpendicular to segment direction in ZX (90-degree rotation).
	var perp := Vector3(-segment_dir.z, 0.0, segment_dir.x)

	# Compute how far the obstacle extends from its center in the perpendicular direction
	var half_width := _get_shape_half_width(_collider, perp)

	# Two candidate sub-goals on either side of the obstacle at edge + margin.
	var center_xz := Vector3(_collider.global_position.x, 0.0, _collider.global_position.z)
	var offset := half_width + margin
	var candidate_a := center_xz + perp * offset
	var candidate_b := center_xz - perp * offset

	if _collider == _committed_collider and is_instance_valid(_committed_collider):
		# Same obstacle — pick whichever candidate is closer to our committed position.
		if candidate_a.distance_squared_to(_committed_position) <= candidate_b.distance_squared_to(_committed_position):
			new_goal.position = Vector3(candidate_a.x, goal.position.y, candidate_a.z)
		else:
			new_goal.position = Vector3(candidate_b.x, goal.position.y, candidate_b.z)
	else:
		# New obstacle — validate with point overlap, then commit.
		var space_state := agent.get_world_3d().direct_space_state
		var check_y := agent.global_position.y + 0.5
		var a_blocked := _is_point_inside_obstacle(space_state, Vector3(candidate_a.x, check_y, candidate_a.z))
		var b_blocked := _is_point_inside_obstacle(space_state, Vector3(candidate_b.x, check_y, candidate_b.z))

		if a_blocked and not b_blocked:
			new_goal.position = Vector3(candidate_b.x, goal.position.y, candidate_b.z)
		elif b_blocked and not a_blocked:
			new_goal.position = Vector3(candidate_a.x, goal.position.y, candidate_a.z)
		else:
			var goal_xz := Vector3(goal.position.x, 0.0, goal.position.z)
			if candidate_a.distance_squared_to(goal_xz) <= candidate_b.distance_squared_to(goal_xz):
				new_goal.position = Vector3(candidate_a.x, goal.position.y, candidate_a.z)
			else:
				new_goal.position = Vector3(candidate_b.x, goal.position.y, candidate_b.z)

	_committed_collider = _collider
	_committed_position = Vector3(new_goal.position.x, 0.0, new_goal.position.z)

	if debug_enabled:
		debug_obstacle_center = center_xz
		debug_half_width = half_width
		debug_candidate_a = candidate_a
		debug_candidate_b = candidate_b
		debug_chosen = new_goal.position

	new_goal.has_position = true
	return new_goal

## Returns true if the given point is inside any obstacle shape (excluding the
## currently detected collider, to avoid self-detection at small margins).
func _is_point_inside_obstacle(space_state: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	var params := PhysicsPointQueryParameters3D.new()
	params.position = point
	params.collision_mask = obstacle_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if _collider:
		params.exclude = [_collider.get_rid()]
	return not space_state.intersect_point(params).is_empty()


## Returns how far the obstacle's collision shape extends from its center
## along the given world-space direction (support function, XZ only).
## Uses the shape's debug mesh vertices for a universal formula that works
## with any Shape3D type. Allocates per call; cache the mesh if this matters.
func _get_shape_half_width(collider: Node3D, world_dir: Vector3) -> float:
	for child in collider.get_children():
		if child is CollisionShape3D and child.shape:
			# Transform direction into the shape's local space (handles rotation).
			var local_dir: Vector3 = child.global_transform.basis.inverse() * world_dir
			local_dir.y = 0.0
			if local_dir.length_squared() < 0.001:
				return 1.0
			local_dir = local_dir.normalized()

			# Support function: farthest vertex projection in the given direction.
			var debug_mesh: ArrayMesh = child.shape.get_debug_mesh()
			var max_proj := 0.0
			for surface_idx in debug_mesh.get_surface_count():
				var verts: PackedVector3Array = debug_mesh.surface_get_arrays(surface_idx)[Mesh.ARRAY_VERTEX]
				for v in verts:
					max_proj = maxf(max_proj, v.x * local_dir.x + v.z * local_dir.z)
			return max_proj
	return 1.0