class_name SelectionController
extends Node3D
## Handles unit selection and movement commands via mouse input.
## Left-click to select units, right-click to command movement.

signal selection_changed(units: Array[Unit])

@export_node_path("Camera3D") var camera_path: NodePath
@export var formation_instance: Formation

const TERRAIN_LAYER := 1
const UNIT_LAYER := 2

var _camera: Camera3D
var _selected_units: Array[Unit] = []


func _ready() -> void:
	if camera_path:
		_camera = get_node(camera_path) as Camera3D
	if not _camera:
		push_error("SelectionController: No camera assigned")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if not _camera:
		return

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_handle_select(event.position)
		MOUSE_BUTTON_RIGHT:
			_handle_command(event.position)


func _handle_select(screen_pos: Vector2) -> void:
	var result := _raycast(screen_pos, UNIT_LAYER | TERRAIN_LAYER)

	if result.is_empty():
		_deselect_all()
		return

	if result.collider is Unit:
		_select_unit(result.collider)
	else:
		# Clicked ground or non-unit object
		_deselect_all()


func _handle_command(screen_pos: Vector2) -> void:
	var result := _raycast(screen_pos, TERRAIN_LAYER)
	if result.is_empty():
		return

	# If we have a formation, move it instead of individual units
	if formation_instance:
		formation_instance.command_move(result.position)
	else:
		for unit in _selected_units:
			unit.command_move(result.position)


func _select_unit(unit: Unit) -> void:
	_deselect_all()
	unit.select()
	_selected_units.append(unit)
	selection_changed.emit(_selected_units.duplicate())


func _deselect_all() -> void:
	for unit in _selected_units:
		unit.deselect()
	_selected_units.clear()
	selection_changed.emit(_selected_units.duplicate())


func _raycast(screen_pos: Vector2, mask: int) -> Dictionary:
	var origin := _camera.project_ray_origin(screen_pos)
	var end := origin + _camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, mask)
	return get_world_3d().direct_space_state.intersect_ray(query)


func get_selected_units() -> Array[Unit]:
	return _selected_units.duplicate()
