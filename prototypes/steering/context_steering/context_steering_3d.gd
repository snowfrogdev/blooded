class_name ContextSteering3D
extends Node
## Main orchestrator for context steering. Equivalent of [SteeringPipeline3D]
## but simpler: behaviors populate a context map, then the actuator converts
## the best direction into acceleration.

@export var behaviors: Array[ContextBehavior3D] = []
@export var path_provider: ContextPathProvider
@export var actuator: ContextActuator
@export var kinematic: Kinematic3D

@export_group("Danger Spread")
## Fraction of danger to spread to adjacent slots for body clearance.
## Applied after velocity reshaping so spread values are not re-amplified.
@export var neighbor_spread: float = 0.5

@export_group("Velocity Danger")
## Multiplicative boost to danger in the velocity direction at full speed.
## 0.0 = no amplification. 1.5 = up to 2.5x danger directly ahead.
@export var velocity_danger_boost: float = 1.5
## Reduction factor for danger opposite the velocity direction at full speed.
## 0.7 = danger behind reduced to 0.3x.
@export var velocity_danger_attenuation: float = 0.7
## Speed (m/s) at which full reshaping applies. Below this, effect scales linearly.
## At zero speed, no reshaping — raw danger values stand as-is.
@export var velocity_danger_speed_ref: float = 5.0

@export_group("Facing")
## Provides the desired facing direction each frame. See [FacingProvider].
@export var facing_provider: FacingProvider
## Maximum angular speed in radians per second.
@export var max_angular_speed: float = 8.0
## Angular distance (radians) at which rotation stops (dead zone).
@export var facing_align_radius: float = 0.02
## Angular distance (radians) at which deceleration begins.
@export var facing_slow_radius: float = 0.5

var _agent: Node3D
var _moveable: Moveable3D
var _map: ContextMap3D

## Debug snapshots, read by [ContextDebugDraw].
var debug_interest: Array[float] = []
var debug_danger: Array[float] = []
var debug_effective: Array[float] = []
var debug_chosen_direction: Vector3 = Vector3.ZERO
var debug_chosen_strength: float = 0.0
var debug_facing_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_agent = get_parent() as Node3D
	_map = ContextMap3D.new()
	# Find Moveable3D sibling (same pattern as MoveToTargeter).
	for child in _agent.get_children():
		if child is Moveable3D:
			_moveable = child
			break
	if kinematic is GroundedKinematic3D and actuator:
		var terrain_node = get_tree().get_first_node_in_group("terrain")
		var terrain_3d: Terrain3D = terrain_node as Terrain3D if terrain_node else null
		actuator.setup(kinematic.height_provider, terrain_3d)


## Called by [method Unit.set_steering_mode] to enable/disable this system.
func set_steering_mode_enabled(enabled: bool) -> void:
	if enabled:
		process_mode = PROCESS_MODE_INHERIT
		if path_provider:
			path_provider.clear_cache()
	else:
		process_mode = PROCESS_MODE_DISABLED


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not kinematic:
		return

	var has_movement := actuator and path_provider and _moveable and _moveable.has_target

	if has_movement:
		_process_movement(delta)
	else:
		kinematic.velocity = Vector3.ZERO
		_clear_debug()

	_process_facing(delta)


func _process_movement(delta: float) -> void:
	var desired_dir := path_provider.get_desired_direction(_agent, _moveable)

	for behavior in behaviors:
		if behavior is SeekBehavior:
			behavior.desired_direction = desired_dir

	_map.clear()

	for behavior in behaviors:
		behavior.populate(_agent, kinematic, _map)

	_reshape_danger_by_velocity()
	_map.apply_neighbor_spread(neighbor_spread)

	_map.evaluate()

	if _map.chosen_strength <= 0.0 or _map.chosen_direction.is_zero_approx():
		kinematic.velocity = Vector3.ZERO
		_snapshot_debug()
		return

	var lookahead_pos := path_provider.lookahead_target
	var output := actuator.compute_steering(_map, _agent, kinematic, lookahead_pos)

	if output == null:
		kinematic.velocity = Vector3.ZERO
		_snapshot_debug()
		return

	kinematic.velocity += output.linear_acceleration * delta
	_snapshot_debug()


func _reshape_danger_by_velocity() -> void:
	var vel_xz := Vector3(kinematic.velocity.x, 0.0, kinematic.velocity.z)
	var speed := vel_xz.length()
	if speed < 0.1:
		return
	var speed_factor := clampf(speed / velocity_danger_speed_ref, 0.0, 1.0)
	_map.reshape_danger(
		vel_xz / speed,
		velocity_danger_boost * speed_factor,
		velocity_danger_attenuation * speed_factor)


func _process_facing(delta: float) -> void:
	if not facing_provider:
		debug_facing_direction = Vector3.ZERO
		return

	var desired := facing_provider.get_desired_facing(_agent, kinematic, _moveable)
	debug_facing_direction = desired

	if desired.is_zero_approx():
		# No opinion — decelerate to stop.
		kinematic.angular_velocity = move_toward(
			kinematic.angular_velocity, 0.0, max_angular_speed * delta / maxf(facing_slow_radius, 0.01))
		return

	kinematic.angular_velocity = _compute_angular_velocity(desired)


## Compute angular velocity directly — no acceleration layer.
## Uses arrive-style ramp: full speed outside [member facing_slow_radius],
## linearly scaled inside, zero within [member facing_align_radius].
## Assigning velocity directly prevents overshoot.
func _compute_angular_velocity(desired_direction: Vector3) -> float:
	var target_yaw := atan2(desired_direction.x, desired_direction.z)
	var current_yaw := _agent.rotation.y
	var delta_yaw := wrapf(target_yaw - current_yaw, -PI, PI)

	# Dead zone — close enough.
	if absf(delta_yaw) < facing_align_radius:
		return 0.0

	# Full speed outside slow_radius, linearly ramped inside.
	var speed := max_angular_speed
	if absf(delta_yaw) < facing_slow_radius:
		speed = max_angular_speed * absf(delta_yaw) / facing_slow_radius

	return speed * signf(delta_yaw)


func _snapshot_debug() -> void:
	debug_interest = _map.interest.duplicate()
	debug_danger = _map.danger.duplicate()
	debug_effective.resize(_map.NUM_SLOTS)
	for i in _map.NUM_SLOTS:
		debug_effective[i] = maxf(0.0, _map.interest[i] - _map.danger[i])
	debug_chosen_direction = _map.chosen_direction
	debug_chosen_strength = _map.chosen_strength


func _clear_debug() -> void:
	debug_interest.clear()
	debug_danger.clear()
	debug_effective.clear()
	debug_chosen_direction = Vector3.ZERO
	debug_chosen_strength = 0.0
	debug_facing_direction = Vector3.ZERO
