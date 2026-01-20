class_name Unit
extends CharacterBody3D
## Selectable, movable RTS unit with click-to-move functionality.

signal selected
signal deselected

@export var move_speed: float = 5.0
@export var arrival_threshold: float = 0.2

## Tags used for formation slot filtering (e.g., ["infantry"], ["infantry", "medic"])
@export var tags: Array[StringName] = [&"infantry"]

var _is_selected: bool = false
var _target_position: Vector3
var _target_rotation: float = NAN  # Target Y rotation (radians), NAN means face movement direction
var _has_target: bool = false

@onready var _selection_indicator: MeshInstance3D = $SelectionIndicator


func _ready() -> void:
	_selection_indicator.visible = false


func _physics_process(delta: float) -> void:
	if _has_target:
		var to_target := _target_position - global_position
		to_target.y = 0  # Ignore vertical difference for distance check

		if to_target.length() <= arrival_threshold:
			_has_target = false
			velocity = Vector3.ZERO
			# Face target rotation if specified
			if not is_nan(_target_rotation):
				rotation.y = _target_rotation
		else:
			var direction := to_target.normalized()
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			# Face movement direction (+Z forward)
			look_at(global_position + direction, Vector3.UP, true)

	# Apply gravity when not on floor
	if not is_on_floor():
		velocity.y -= 20.0 * delta

	move_and_slide()


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


func get_tags() -> Array[StringName]:
	return tags


func has_tag(tag: StringName) -> bool:
	return tag in tags
