@tool
class_name SteeringPipeline3D
extends Node

@export_group("Pipeline Components")
## Targeters that generate the top-level goal. Each targeter may fill one or more
## channels (position, rotation, velocity, angular_velocity). Multiple targeters should
## cooperate by writing to different channels - later targeters will overwrite earlier ones.
@export var targeters: Array[Targeter3D] = []
## Decomposers that break down goals into achievable sub-goals. Processed in order -
## early decomposers should provide coarse decomposition (e.g., high-level pathfinding),
## later ones refine the sub-goal in more detail. Each receives the output of the previous.
@export var decomposers: Array[Decomposer3D] = []
## Constraints that detect and avoid obstacles. Each reviews the planned path and may
## suggest an alternative sub-goal if a violation is detected. The pipeline iterates
## until all constraints pass or deadlock occurs.
@export var constraints: Array[Constraint3D] = []
## The actuator that converts the sub-goal into actual movement. Unlike other stages,
## only one actuator is used. It determines the path to the goal based on the character's
## physical capabilities and outputs the acceleration to follow that path.
@export var actuator: Actuator3D:
	set(value):
		actuator = value
		update_configuration_warnings()
## The kinematic component that holds velocity state for the steered node.
@export var kinematic: Kinematic3D:
	set(value):
		kinematic = value
		update_configuration_warnings()
## Fallback behavior used when constraints cannot be satisfied after [member constraint_steps]
## attempts. Typically a simple wander or full pathfinding call to escape the stuck state.
@export var deadlock_fallback: SteeringBehavior3D:
	set(value):
		deadlock_fallback = value
		update_configuration_warnings()

## The number of attempts the algorithm will make to find an unconstrained route.
@export var constraint_steps: int = 5:
	set(value):
		constraint_steps = value
		update_configuration_warnings()

var _agent: Node3D ## The Node3D that this pipeline steers (parent node)
var _kinematic: Kinematic3D ## Cached reference to the kinematic component

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_agent = get_parent() as Node3D
	_kinematic = kinematic
	if not _kinematic:
		push_error("SteeringPipeline: kinematic is required")
	if not actuator:
		push_error("SteeringPipeline: actuator is required")
	if not deadlock_fallback:
		push_error("SteeringPipeline: deadlock_fallback behavior is required")
	if constraint_steps < 1:
		push_warning("SteeringPipeline: constraint_steps is %d; must be >= 1" % constraint_steps)
		constraint_steps = max(constraint_steps, 1)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not kinematic:
		warnings.append("A Kinematic3D reference is required.")
	if not actuator:
		warnings.append("An Actuator3D is required.")
	if not deadlock_fallback:
		warnings.append("A deadlock fallback SteeringBehavior3D is required.")
	if constraint_steps < 1:
		warnings.append("constraint_steps must be >= 1.")
	return warnings

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _kinematic or not actuator or not deadlock_fallback:
		return
	var steering: SteeringOutput3D = _get_steering()
	if steering == null:
		_kinematic.velocity = Vector3.ZERO
		_kinematic.angular_velocity = 0.0
		return
	_kinematic.velocity += steering.linear_acceleration * delta
	_kinematic.angular_velocity += steering.angular_acceleration * delta

## Runs the full steering pipeline: target -> decompose -> constrain/iterate -> actuate.
## Falls back to deadlock_fallback if constraints cannot be satisfied.
func _get_steering() -> SteeringOutput3D:
	var goal := Goal3D.new()
	for targeter in targeters:
		var targeter_goal = targeter.get_goal(_agent)
		if targeter_goal:
			goal.merge_from(targeter_goal)

	for decomposer in decomposers:
		var decomposed = decomposer.decompose(_agent, goal)
		if decomposed:
			goal = decomposed

	for i in range(constraint_steps):
		var path = actuator.get_steering_path(_agent, _kinematic, goal)
		if path == null:
			break
		var violated_constraint = _check_constraints(path)
		if violated_constraint:
			goal = violated_constraint.suggest(_agent, path, goal)
			continue
		return actuator.compute_steering(_agent, _kinematic, path, goal)

	return deadlock_fallback.get_steering(_agent, _kinematic)

func _check_constraints(path: SteeringPath3D) -> Constraint3D:
	for constraint in constraints:
		if constraint.is_violated(_agent, _kinematic, path):
			return constraint
	return null
