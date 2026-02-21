@tool
class_name Unit
extends Node3D
## Selectable, movable RTS unit with click-to-move functionality.

signal selected
signal deselected

var _is_selected: bool = false

@onready var _selection_indicator: MeshInstance3D = $SelectionIndicator
@onready var _moveable: Moveable3D = $Moveable3D

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_selection_indicator.visible = false


func select() -> void:
	if _is_selected:
		return
	_is_selected = true
	_selection_indicator.visible = true
	selected.emit()


func deselect() -> void:
	if not _is_selected:
		return
	_is_selected = false
	_selection_indicator.visible = false
	deselected.emit()


func command_move(target: Vector3, target_rotation: float = NAN) -> void:
	_moveable.set_target(target, target_rotation)


func is_selected() -> bool:
	return _is_selected


func set_steering_mode(mode: StringName) -> void:
	var pipeline = get_node_or_null("SteeringPipeline")
	var context = get_node_or_null("ContextSteering3D")
	var pipeline_debug = get_node_or_null("SteeringDebugDraw")
	var context_debug = get_node_or_null("ContextDebugDraw")
	var kin = get_node_or_null("GroundedKinematic3D")

	# Zero velocity on kinematic BEFORE switching (prevents one-frame drift).
	if kin:
		kin.velocity = Vector3.ZERO
		kin.angular_velocity = 0.0

	if mode == &"pipeline":
		if pipeline: pipeline.process_mode = PROCESS_MODE_INHERIT
		if context: context.set_steering_mode_enabled(false)
		if pipeline_debug: pipeline_debug.process_mode = PROCESS_MODE_INHERIT
		if context_debug: context_debug.process_mode = PROCESS_MODE_DISABLED
	elif mode == &"context":
		if pipeline: pipeline.process_mode = PROCESS_MODE_DISABLED
		if context: context.set_steering_mode_enabled(true)
		if pipeline_debug: pipeline_debug.process_mode = PROCESS_MODE_DISABLED
		if context_debug: context_debug.process_mode = PROCESS_MODE_INHERIT
