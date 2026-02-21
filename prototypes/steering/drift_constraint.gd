class_name DriftConstraint extends Constraint3D
## Detects when the agent's velocity will carry it into a wall and adjusts
## the sub-goal laterally to steer away from the impending collision.
##
## Unlike AvoidObstacleConstraint (which checks along the agent-to-goal
## direction), this constraint casts rays along the agent's current velocity
## vector. This catches lateral drift when entering corridors at an angle,
## where goal-directed whiskers rotate away from the wall the agent is
## actually sliding toward.

## Half-width of the agent body for flanking ray offset.
@export var agent_radius: float = 0.31
## Additive clearance beyond the agent radius when offsetting the goal.
@export var margin: float = 0.5
## Seconds ahead to project the velocity ray. Ray length = speed * time_horizon.
@export var time_horizon: float = 0.5
## Minimum XZ speed to activate the check. Below this, drift is negligible.
@export var min_speed: float = 0.5
## Physics collision mask for obstacle detection (default: layer 3).
@export_flags_3d_physics var obstacle_mask: int = 4
## When true, debug state variables are populated for SteeringDebugDraw.
@export var debug_enabled: bool = false

# Cached violation data from is_violated(), consumed by suggest().
var _hit_normal: Vector3
var _hit_point: Vector3

## Debug state — populated when debug_enabled is true, read by SteeringDebugDraw.
var debug_velocity_ray_from: Vector3
var debug_velocity_ray_to: Vector3
var debug_velocity_ray_hit: bool
var debug_velocity_ray_hit_point: Vector3
var debug_violated: bool

func _init() -> void:
	resource_local_to_scene = true


func is_violated(agent: Node3D, kinematic: Kinematic3D, _path: SteeringPath3D) -> bool:
	debug_violated = false
	debug_velocity_ray_hit = false

	var vel_xz := Vector3(kinematic.velocity.x, 0.0, kinematic.velocity.z)
	var speed := vel_xz.length()
	if speed < min_speed:
		return false

	var vel_dir := vel_xz / speed
	var ray_length := speed * time_horizon

	var origin := agent.global_position
	var lift := Vector3(0.0, 0.5, 0.0)
	var from_base := origin + lift
	var to_base := origin + vel_dir * ray_length + lift

	# Perpendicular offset for flanking rays.
	var right := vel_dir.cross(Vector3.UP) * agent_radius
	var origins: Array[Vector3] = [from_base, from_base - right, from_base + right]
	var ends: Array[Vector3] = [to_base, to_base - right, to_base + right]

	var space_state := agent.get_world_3d().direct_space_state

	for i in 3:
		var query := PhysicsRayQueryParameters3D.create(origins[i], ends[i], obstacle_mask)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result := space_state.intersect_ray(query)

		if not result.is_empty():
			_hit_normal = result.normal
			_hit_point = result.position
			debug_violated = true
			if debug_enabled:
				debug_velocity_ray_from = origins[i]
				debug_velocity_ray_to = ends[i]
				debug_velocity_ray_hit = true
				debug_velocity_ray_hit_point = result.position
			return true

	# No hit — populate debug with center ray for visualization.
	if debug_enabled:
		debug_velocity_ray_from = from_base
		debug_velocity_ray_to = to_base

	return false


func suggest(_agent: Node3D, _path: SteeringPath3D, goal: Goal3D) -> Goal3D:
	var new_goal := Goal3D.new()
	new_goal.merge_from(goal)

	if not new_goal.has_position:
		return new_goal

	# Wall normal projected onto XZ plane.
	var normal_xz := Vector3(_hit_normal.x, 0.0, _hit_normal.z)
	if normal_xz.length_squared() < 0.001:
		return new_goal
	normal_xz = normal_xz.normalized()

	# Offset the goal position away from the wall.
	new_goal.position += normal_xz * (agent_radius + margin)
	new_goal.has_position = true
	return new_goal
