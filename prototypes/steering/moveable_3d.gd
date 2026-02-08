@tool
class_name Moveable3D
extends Node

## Game-logic arrival threshold. When the agent is within this distance of the
## target, the movement command is considered complete and cleared.
## Note: ArriveActuator has a separate `target_radius` for steering cutoff.
## Both should use similar values -- if they diverge, the unit may briefly
## oscillate (Moveable3D clears too early) or waste cycles (clears too late).
@export var arrival_radius: float = 0.3

var target_position: Vector3 = Vector3.ZERO
var target_rotation: float = NAN
var has_target: bool = false

var _parent: Node3D

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_parent = get_parent() as Node3D
	if not _parent:
		push_error("Moveable3D must be a child of a Node3D")

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _parent:
		return
	if has_target and _parent.global_position.distance_to(target_position) < arrival_radius:
		clear_target()

func set_target(position: Vector3, rotation: float = NAN) -> void:
	target_position = position
	target_rotation = rotation
	has_target = true

func clear_target() -> void:
	has_target = false
