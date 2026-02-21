class_name ContextSteering3D
extends Node
## Main orchestrator for context steering. Equivalent of [SteeringPipeline3D]
## but simpler: behaviors populate a context map, then the actuator converts
## the best direction into acceleration.

@export var behaviors: Array[ContextBehavior3D] = []
@export var path_provider: ContextPathProvider
@export var actuator: ContextActuator
@export var kinematic: Kinematic3D

var _agent: Node3D
var _moveable: Moveable3D
var _map: ContextMap3D

## Debug snapshots, read by [ContextDebugDraw].
var debug_interest: Array[float] = []
var debug_danger: Array[float] = []
var debug_effective: Array[float] = []
var debug_chosen_direction: Vector3 = Vector3.ZERO
var debug_chosen_strength: float = 0.0


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


## Called by [method Unit.set_steering_mode] to enable/disable this system.
func set_steering_mode_enabled(enabled: bool) -> void:
	if enabled:
		process_mode = PROCESS_MODE_INHERIT
		if path_provider:
			path_provider.clear_cache()
	else:
		process_mode = PROCESS_MODE_DISABLED


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not kinematic or not actuator or not path_provider:
		return

	# Early-out if no target: prevents drifting in "least dangerous" direction.
	if not _moveable or not _moveable.has_target:
		kinematic.velocity = Vector3.ZERO
		_clear_debug()
		return

	var desired_dir := path_provider.get_desired_direction(_agent, _moveable)

	# Set desired direction on the seek behavior.
	for behavior in behaviors:
		if behavior is SeekBehavior:
			behavior.desired_direction = desired_dir

	_map.clear()

	for behavior in behaviors:
		behavior.populate(_agent, kinematic, _map)

	_map.evaluate()

	# Zero-strength check: all directions blocked — brake.
	if _map.chosen_strength <= 0.0 or _map.chosen_direction.is_zero_approx():
		kinematic.velocity = Vector3.ZERO
		_snapshot_debug()
		return

	var lookahead_pos := path_provider.lookahead_target
	var output := actuator.compute_steering(_map, _agent, kinematic, lookahead_pos)

	# Null check: within target_radius — arrived.
	if output == null:
		kinematic.velocity = Vector3.ZERO
		_snapshot_debug()
		return

	kinematic.velocity += output.linear_acceleration * delta
	_snapshot_debug()


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
