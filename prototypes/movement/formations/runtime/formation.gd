@tool
class_name Formation
extends Node3D
## Runtime formation that manages units in a specific formation shape.
## Supports multiple templates (e.g., wedge, column) and can switch between them.


#region Signals and Enums

signal state_changed(new_state: State)
signal unit_assigned(slot_index: int, unit: Node3D)
signal unit_removed(slot_index: int, unit: Node3D)
signal formation_changed(new_template: Resource)

enum State {
	DISBANDED, ## Formation inactive, units move independently
	FORMING, ## Units moving toward assigned slots
	FORMED, ## All units in position
	MOVING, ## Formation moving as a group
}

#endregion


#region Exports

## Available formation templates this instance can use
@export var templates: Array[Resource] = []:
	set(value):
		templates = value
		if Engine.is_editor_hint():
			_update_editor_preview()
			notify_property_list_changed()

## Index of the active template (for editor preview)
@export var active_template_index: int = 0:
	set(value):
		active_template_index = clampi(value, 0, maxi(0, templates.size() - 1))
		if templates.size() > 0:
			_active_template = templates[active_template_index]
		if Engine.is_editor_hint():
			_update_editor_preview()
			update_gizmos()

## Movement speed of the formation anchor
@export var move_speed: float = 4.0

## How close units must be to their slot to be considered "in position"
@export var slot_arrival_threshold: float = 0.5

## Spacing multiplier applied to slot positions
@export var spacing_scale: float = 1.0:
	set(value):
		spacing_scale = value
		if Engine.is_editor_hint():
			_update_editor_preview()

## Minimum distance for any rotation to occur (below this, formation maintains facing)
@export var min_rotation_distance: float = 2.0

## Distance at which full rotation occurs (above this, formation fully rotates to face target)
@export var full_rotation_distance: float = 10.0

## Show slot positions in editor
@export var show_preview: bool = true:
	set(value):
		show_preview = value
		if Engine.is_editor_hint():
			_update_editor_preview()

#endregion


#region Private Variables

var _active_template: FormationTemplate = null
var _state: State = State.DISBANDED
var _slot_assignments: Dictionary = {} # int (slot_index) -> Node3D (Unit or Formation)

# Movement target state
var _movement_target_position: Vector3
var _movement_target_rotation: float = 0.0
var _movement_is_active: bool = false

# Helper objects
var _preview: FormationPreview = null
var _marker_manager: DestinationMarkerManager = null

const MIN_MOVEMENT_DISTANCE: float = 0.1

#endregion


#region Lifecycle

func _ready() -> void:
	# Always refresh active template from the array to ensure we have current data
	if templates.size() > 0:
		_active_template = templates[clampi(active_template_index, 0, templates.size() - 1)]

	# Initialize helper objects
	if Engine.is_editor_hint():
		_preview = FormationPreview.new(self)
	else:
		_marker_manager = DestinationMarkerManager.new(get_tree())


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview.call_deferred()


func _exit_tree() -> void:
	if _preview:
		_preview.clear()
	if _marker_manager:
		_marker_manager.clear()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _marker_manager:
		_marker_manager.update_fade(delta)

	match _state:
		State.MOVING:
			_update_anchor_movement(delta)
			_command_units_to_positions()
			_check_formation_state()
		State.FORMING:
			_command_units_to_slots_with_rotation()
			_check_formation_state()

#endregion


#region Public API

func get_active_template() -> Resource:
	return _active_template


func set_active_template(template: Resource) -> void:
	if template == _active_template:
		return
	if template not in templates:
		push_warning("Template not in available templates list")
		return

	_active_template = template

	# Update index
	for i in templates.size():
		if templates[i] == template:
			active_template_index = i
			break

	formation_changed.emit(template)

	# Trigger units to reposition
	if _state != State.DISBANDED:
		_set_state(State.FORMING)


func switch_to_template_by_name(template_name: String) -> bool:
	for template in templates:
		if template.display_name == template_name:
			set_active_template(template)
			return true
	return false


func command_move(target: Vector3, target_rot: float = NAN) -> void:
	_movement_target_position = target
	_movement_is_active = true

	var to_target := target - global_position
	to_target.y = 0
	_movement_target_rotation = _calculate_move_rotation(to_target, target_rot)

	if _marker_manager:
		_marker_manager.show(_movement_target_position, _movement_target_rotation, _active_template, spacing_scale)

	if _state == State.DISBANDED:
		_set_state(State.FORMING)
	else:
		_set_state(State.MOVING)


func get_state() -> State:
	return _state


func disband() -> void:
	_set_state(State.DISBANDED)
	_slot_assignments.clear()


func slot_to_world_position(slot_index: int) -> Vector3:
	if not _is_valid_slot_index(slot_index):
		return global_position

	var slot = _active_template.slots[slot_index]
	var local_pos: Vector3 = slot.local_position * spacing_scale

	# Transform by formation's rotation
	var rotated: Vector3 = local_pos.rotated(Vector3.UP, rotation.y)
	return global_position + rotated


func slot_to_world_rotation(slot_index: int) -> float:
	if not _is_valid_slot_index(slot_index):
		return rotation.y

	var slot = _active_template.slots[slot_index]
	return rotation.y + slot.local_rotation


func assign_unit(slot_index: int, unit: Node3D) -> bool:
	if not _is_valid_slot_index(slot_index):
		return false

	# Remove from previous slot if reassigning
	var previous_slot := get_unit_slot(unit)
	if previous_slot >= 0:
		remove_unit(previous_slot)

	_slot_assignments[slot_index] = unit
	unit_assigned.emit(slot_index, unit)

	if _state == State.DISBANDED:
		_set_state(State.FORMING)

	return true


func remove_unit(slot_index: int) -> Node3D:
	if slot_index not in _slot_assignments:
		return null

	var unit = _slot_assignments[slot_index]
	_slot_assignments.erase(slot_index)
	unit_removed.emit(slot_index, unit)
	return unit


func get_unit_slot(unit: Node3D) -> int:
	for slot_index in _slot_assignments:
		if _slot_assignments[slot_index] == unit:
			return slot_index
	return -1


func get_assigned_units() -> Array[Node3D]:
	var units: Array[Node3D] = []
	for slot_index in _slot_assignments:
		units.append(_slot_assignments[slot_index])
	return units


func get_slot_assignment(slot_index: int) -> Node3D:
	return _slot_assignments.get(slot_index)


func get_empty_slots() -> Array[int]:
	if _active_template == null:
		return []

	var empty: Array[int] = []
	for i in _active_template.slots.size():
		if i not in _slot_assignments:
			empty.append(i)
	return empty


func auto_assign_units(units: Array) -> int:
	## Assigns units to empty slots using a greedy algorithm.
	## Returns the number of units assigned.
	if _active_template == null:
		return 0

	var assigned_count := 0
	var empty_slots := get_empty_slots()

	# Sort slots by priority (higher first)
	empty_slots.sort_custom(func(slot_a: int, slot_b: int) -> bool:
		return _active_template.slots[slot_a].priority > _active_template.slots[slot_b].priority
	)

	for slot_index in empty_slots:
		if units.is_empty():
			break

		var slot = _active_template.slots[slot_index]

		# Find best matching unit
		var best_unit = null
		var best_index := -1

		for i in units.size():
			var unit = units[i]
			var unit_tags: Array[StringName] = []
			if unit.has_method("get_tags"):
				unit_tags = unit.get_tags()

			if slot.can_accept_unit(unit_tags):
				best_unit = unit
				best_index = i
				break # Take first matching unit (greedy)

		if best_unit != null:
			assign_unit(slot_index, best_unit)
			units.remove_at(best_index)
			assigned_count += 1

	return assigned_count

#endregion


#region Private Methods

## Calculates how much the formation should rotate based on move distance.
## Returns 0.0 for distances <= min_rotation_distance (no rotation)
## Returns 1.0 for distances >= full_rotation_distance (full rotation)
## Returns interpolated value for distances in between
func _calculate_rotation_factor(distance: float) -> float:
	if distance <= min_rotation_distance:
		return 0.0
	if distance >= full_rotation_distance:
		return 1.0
	# Linear interpolation between thresholds
	return (distance - min_rotation_distance) / (full_rotation_distance - min_rotation_distance)


func _calculate_move_rotation(to_target: Vector3, explicit_rot: float) -> float:
	if not is_nan(explicit_rot):
		return explicit_rot

	var distance := to_target.length()
	if distance <= MIN_MOVEMENT_DISTANCE:
		return rotation.y

	var desired_rotation := atan2(to_target.x, to_target.z)
	var factor := _calculate_rotation_factor(distance)
	return lerp_angle(rotation.y, desired_rotation, factor)


func _update_anchor_movement(delta: float) -> void:
	if not _movement_is_active:
		return

	var to_target := _movement_target_position - global_position
	to_target.y = 0

	if to_target.length() <= MIN_MOVEMENT_DISTANCE:
		_movement_is_active = false
		# Snap to final target rotation on arrival
		rotation.y = _movement_target_rotation
		if _all_units_in_position():
			_set_state(State.FORMED)
		else:
			_set_state(State.FORMING)
	else:
		var direction := to_target.normalized()
		global_position += direction * move_speed * delta
		# Smoothly rotate toward target rotation (which was calculated based on distance)
		# The _movement_target_rotation already accounts for distance-based rotation factor
		rotation.y = lerp_angle(rotation.y, _movement_target_rotation, delta * 5.0)


func _command_units_to_positions() -> void:
	if _active_template == null:
		return

	for slot_index in _slot_assignments:
		var unit = _slot_assignments[slot_index]
		if not _is_valid_slot_index(slot_index):
			continue

		var world_pos := slot_to_world_position(slot_index)
		if unit.has_method("command_move"):
			unit.command_move(world_pos)


func _command_units_to_slots_with_rotation() -> void:
	if _active_template == null:
		return

	for slot_index in _slot_assignments:
		var unit = _slot_assignments[slot_index]
		if not _is_valid_slot_index(slot_index):
			continue

		var world_pos := slot_to_world_position(slot_index)
		var world_rot := slot_to_world_rotation(slot_index)
		if unit.has_method("command_move"):
			unit.command_move(world_pos, world_rot)


func _check_formation_state() -> void:
	if _state == State.DISBANDED:
		return

	if _all_units_in_position():
		if _state != State.FORMED and not _movement_is_active:
			_set_state(State.FORMED)
	elif _state == State.FORMED:
		_set_state(State.FORMING)


func _all_units_in_position() -> bool:
	for slot_index in _slot_assignments:
		var unit = _slot_assignments[slot_index] as Node3D
		var world_pos := slot_to_world_position(slot_index)
		var distance_to_slot: float = (unit.global_position - world_pos).length()
		if distance_to_slot > slot_arrival_threshold:
			return false
	return true


func _set_state(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state
	state_changed.emit(new_state)


func _is_valid_slot_index(slot_index: int) -> bool:
	if _active_template == null:
		return false
	return slot_index >= 0 and slot_index < _active_template.slots.size()


func _update_editor_preview() -> void:
	if _preview == null:
		_preview = FormationPreview.new(self)

	var template := _active_template
	if template == null and templates.size() > 0:
		template = templates[0]
		_active_template = template

	_preview.update(template, spacing_scale, show_preview)

#endregion


#region Destination Maker Manager

class DestinationMarkerManager extends RefCounted:
	## Manages destination markers that show where units will move to.
	## Handles creation, fading, and cleanup of marker visuals.

	const FADE_DURATION: float = 2.0

	var _markers_container: Node3D = null
	var _fade_time: float = 0.0
	var _scene_tree: SceneTree

	func _init(scene_tree: SceneTree) -> void:
		_scene_tree = scene_tree

	func show(target_pos: Vector3, target_rot: float, template: FormationTemplate, spacing_scale: float) -> void:
		clear()

		if template == null:
			return

		_markers_container = Node3D.new()
		_markers_container.name = "_DestinationMarkers"
		_scene_tree.root.add_child(_markers_container)
		_markers_container.global_position = target_pos
		_markers_container.rotation.y = target_rot

		# Create a ring/circle for each slot
		for i in template.slots.size():
			var slot = template.slots[i]
			var marker := MeshInstance3D.new()

			# Use a torus (ring) mesh for the marker
			var torus := TorusMesh.new()
			torus.inner_radius = 0.3
			torus.outer_radius = 0.5
			marker.mesh = torus

			marker.material_override = _create_unshaded_material(Color(0.0, 0.0, 0.0, 0.7))

			# Position flat on the ground
			var local_pos: Vector3 = slot.local_position * spacing_scale
			local_pos.y = 0.05 # Slightly above ground to avoid z-fighting
			marker.position = local_pos

			_markers_container.add_child(marker)

		_fade_time = FADE_DURATION

	func clear() -> void:
		if _markers_container != null and is_instance_valid(_markers_container):
			_markers_container.queue_free()
			_markers_container = null

	func update_fade(delta: float) -> void:
		if _markers_container == null:
			return

		_fade_time -= delta
		if _fade_time <= 0:
			clear()
			return

		var alpha := _fade_time / FADE_DURATION
		for child in _markers_container.get_children():
			if child is MeshInstance3D and child.material_override:
				child.material_override.albedo_color.a = alpha * 0.7

	func _create_unshaded_material(color: Color) -> StandardMaterial3D:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return material

#endregion


#region Inner Classes - Editor

class FormationPreview extends RefCounted:
	## Handles editor preview visualization for a Formation.
	## Creates and manages preview meshes showing slot positions, center marker, and direction arrow.

	var _formation: Node3D
	var _preview_meshes: Array[MeshInstance3D] = []
	var _preview_container: Node3D = null

	func _init(formation: Node3D) -> void:
		_formation = formation

	func update(template: FormationTemplate, spacing_scale: float, show_preview: bool) -> void:
		if not Engine.is_editor_hint() or not _formation.is_inside_tree():
			return

		clear()

		if not show_preview:
			return

		if template == null:
			return

		_preview_container = _create_preview_container()
		_formation.add_child(_preview_container)

		_create_slot_previews(template, spacing_scale)
		_preview_container.add_child(_create_center_marker())
		_create_direction_arrow()

	func clear() -> void:
		_preview_meshes.clear()
		if _preview_container != null and is_instance_valid(_preview_container):
			_preview_container.queue_free()
			_preview_container = null

	func _create_preview_container() -> Node3D:
		var container := Node3D.new()
		container.name = "_EditorPreview"
		container.set_owner(null)
		return container

	func _create_slot_previews(template: FormationTemplate, spacing_scale: float) -> void:
		for slot_index in template.slots.size():
			var sphere := _create_slot_sphere(template, slot_index, spacing_scale)
			_preview_container.add_child(sphere)
			_preview_meshes.append(sphere)

			var label := _create_slot_label(template, slot_index, spacing_scale)
			_preview_container.add_child(label)

	func _create_slot_sphere(template: FormationTemplate, slot_index: int, spacing_scale: float) -> MeshInstance3D:
		var slot = template.slots[slot_index]
		var mesh_instance := MeshInstance3D.new()

		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		mesh_instance.mesh = sphere
		mesh_instance.material_override = _create_unshaded_material(Color(0.2, 1.0, 0.2, 0.9))

		var local_pos: Vector3 = slot.local_position * spacing_scale
		local_pos.y += 0.5
		mesh_instance.position = local_pos
		mesh_instance.rotation.y = slot.local_rotation

		return mesh_instance

	func _create_slot_label(template: FormationTemplate, slot_index: int, spacing_scale: float) -> Label3D:
		var slot = template.slots[slot_index]
		var local_pos: Vector3 = slot.local_position * spacing_scale
		local_pos.y += 0.5

		var label := Label3D.new()
		var distance: float = (slot.local_position * spacing_scale).length()
		label.text = "%d: %.1fm" % [slot_index, distance]
		label.font_size = 32
		label.position = local_pos + Vector3(0.3, 1.2, 0.3)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.shaded = false
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.outline_modulate = Color.BLACK

		return label

	func _create_center_marker() -> MeshInstance3D:
		var center_mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.3
		cylinder.bottom_radius = 0.3
		cylinder.height = 1.0
		center_mesh.mesh = cylinder
		center_mesh.position.y = 0.5
		center_mesh.material_override = _create_unshaded_material(Color(1.0, 0.3, 0.3, 0.9))

		return center_mesh

	func _create_direction_arrow() -> void:
		var arrow_material := _create_unshaded_material(Color(0.2, 0.5, 1.0, 0.9))

		# Shaft
		var shaft_mesh := MeshInstance3D.new()
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.08
		shaft.bottom_radius = 0.08
		shaft.height = 1.5
		shaft_mesh.mesh = shaft
		shaft_mesh.material_override = arrow_material
		shaft_mesh.rotation.x = PI / 2
		shaft_mesh.position = Vector3(0, 0.5, 0.75)
		_preview_container.add_child(shaft_mesh)

		# Head
		var head_mesh := MeshInstance3D.new()
		var head := CylinderMesh.new()
		head.top_radius = 0.0
		head.bottom_radius = 0.25
		head.height = 0.5
		head_mesh.mesh = head
		head_mesh.material_override = arrow_material
		head_mesh.rotation.x = PI / 2
		head_mesh.position = Vector3(0, 0.5, 1.75)
		_preview_container.add_child(head_mesh)

	func _create_unshaded_material(color: Color) -> StandardMaterial3D:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return material

#endregion
