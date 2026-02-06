@tool
class_name Unit
extends Node3D
## Selectable, movable RTS unit with click-to-move functionality.

signal selected
signal deselected

@export var arrival_radius: float = 0.3

var _is_selected: bool = false
var _target_position: Vector3
var _target_rotation: float = NAN # Target Y rotation (radians), NAN means face movement direction
var _has_target: bool = false

@onready var _selection_indicator: MeshInstance3D = $SelectionIndicator

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_selection_indicator.visible = false

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _has_target and global_position.distance_to(_target_position) < arrival_radius:
		clear_target()


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
	_target_position = target
	_target_rotation = target_rotation
	_has_target = true


func is_selected() -> bool:
	return _is_selected

func get_target_position() -> Vector3:
	return _target_position

func has_target() -> bool:
	return _has_target

func clear_target() -> void:
	_has_target = false