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
