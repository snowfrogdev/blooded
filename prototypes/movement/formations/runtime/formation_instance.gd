@tool
class_name FormationInstance
extends Node3D
## Runtime formation that manages units in a specific formation shape.
## Supports multiple templates (e.g., wedge, column) and can switch between them.

signal state_changed(new_state: State)
signal unit_assigned(slot_index: int, unit: Node3D)
signal unit_removed(slot_index: int, unit: Node3D)
signal formation_changed(new_template: Resource)

enum State {
	DISBANDED,  ## Formation inactive, units move independently
	FORMING,    ## Units moving toward assigned slots
	FORMED,     ## All units in position
	MOVING,     ## Formation moving as a group
}

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

var _active_template: Resource  # FormationTemplate
var _preview_meshes: Array[MeshInstance3D] = []
var _preview_container: Node3D = null
var _state: State = State.DISBANDED
var _slot_assignments: Dictionary = {}  # int (slot_index) -> Node3D (Unit or FormationInstance)
var _target_position: Vector3
var _target_rotation: float = 0.0
var _start_rotation: float = 0.0  # Rotation when move command was issued
var _rotation_factor: float = 1.0  # How much to rotate (0 = none, 1 = full)
var _has_target: bool = false
var _destination_markers: Node3D = null
var _marker_fade_time: float = 0.0
const MARKER_FADE_DURATION: float = 2.0


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



func _ready() -> void:
	# Always refresh active template from the array to ensure we have current data
	if templates.size() > 0:
		_active_template = templates[clampi(active_template_index, 0, templates.size() - 1)]


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview.call_deferred()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Update destination marker fade
	if _destination_markers != null:
		_marker_fade_time -= delta
		if _marker_fade_time <= 0:
			_clear_destination_markers()
		else:
			# Fade out the markers
			var alpha := _marker_fade_time / MARKER_FADE_DURATION
			for child in _destination_markers.get_children():
				if child is MeshInstance3D and child.material_override:
					child.material_override.albedo_color.a = alpha * 0.7

	match _state:
		State.MOVING:
			_update_anchor_movement(delta)
			_command_units_to_slots(false)
			_check_formation_state()
		State.FORMING:
			_command_units_to_slots(true)
			_check_formation_state()


func _update_anchor_movement(delta: float) -> void:
	if not _has_target:
		return

	var to_target := _target_position - global_position
	to_target.y = 0

	if to_target.length() <= 0.1:
		_has_target = false
		# Snap to final target rotation on arrival
		rotation.y = _target_rotation
		if _all_units_in_position():
			_set_state(State.FORMED)
		else:
			_set_state(State.FORMING)
	else:
		var direction := to_target.normalized()
		global_position += direction * move_speed * delta
		# Smoothly rotate toward target rotation (which was calculated based on distance)
		# The _target_rotation already accounts for distance-based rotation factor
		rotation.y = lerp_angle(rotation.y, _target_rotation, delta * 5.0)


func _command_units_to_slots(include_rotation: bool) -> void:
	if _active_template == null:
		return

	for slot_index in _slot_assignments:
		var unit = _slot_assignments[slot_index]
		if slot_index >= _active_template.slots.size():
			continue

		var world_pos := slot_to_world_position(slot_index)
		if unit.has_method("command_move"):
			if include_rotation:
				var world_rot := slot_to_world_rotation(slot_index)
				unit.command_move(world_pos, world_rot)
			else:
				unit.command_move(world_pos)


func _check_formation_state() -> void:
	if _state == State.DISBANDED:
		return

	if _all_units_in_position():
		if _state != State.FORMED and not _has_target:
			_set_state(State.FORMED)
	elif _state == State.FORMED:
		_set_state(State.FORMING)


func _all_units_in_position() -> bool:
	for slot_index in _slot_assignments:
		var unit = _slot_assignments[slot_index] as Node3D
		var world_pos := slot_to_world_position(slot_index)
		var dist: float = (unit.global_position - world_pos).length()
		if dist > slot_arrival_threshold:
			return false
	return true


func _set_state(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state
	state_changed.emit(new_state)


# --- Editor Preview ---

func _update_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	if not is_inside_tree():
		return

	_clear_preview()

	if not show_preview:
		return

	if _active_template == null and templates.size() > 0:
		_active_template = templates[0]

	if _active_template == null:
		return

	# Create container for preview meshes
	_preview_container = Node3D.new()
	_preview_container.name = "_EditorPreview"
	add_child(_preview_container)
	_preview_container.set_owner(null)  # Don't save preview to scene

	# Create preview mesh for each slot
	for i in _active_template.slots.size():
		var slot = _active_template.slots[i]
		var mesh_instance := MeshInstance3D.new()

		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		mesh_instance.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 1.0, 0.2, 0.9)  # Green
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_instance.material_override = mat

		# Position the mesh - sphere center at ground level + radius (0.5)
		var local_pos: Vector3 = slot.local_position * spacing_scale
		local_pos.y += 0.5  # Sphere radius, so bottom touches ground
		mesh_instance.position = local_pos
		mesh_instance.rotation.y = slot.local_rotation

		_preview_container.add_child(mesh_instance)
		_preview_meshes.append(mesh_instance)

		# Add label showing slot index and distance
		var label := Label3D.new()
		var distance: float = (slot.local_position * spacing_scale).length()
		label.text = "%d: %.1fm" % [i, distance]
		label.font_size = 32
		label.position = local_pos + Vector3(0.3, 1.2, 0.3)  # Offset above and to the side
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true  # Always visible
		label.shaded = false
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.outline_modulate = Color.BLACK
		_preview_container.add_child(label)

	# Add center marker
	var center_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.3
	cylinder.bottom_radius = 0.3
	cylinder.height = 1.0
	center_mesh.mesh = cylinder
	center_mesh.position.y = 0.5  # Cylinder center at half height, so bottom touches ground
	var center_mat := StandardMaterial3D.new()
	center_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	center_mat.albedo_color = Color(1.0, 0.3, 0.3, 0.9)
	center_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	center_mesh.material_override = center_mat
	_preview_container.add_child(center_mesh)

	# Add forward direction arrow (pointing toward +Z)
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.9)  # Blue
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Arrow shaft
	var shaft_mesh := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.08
	shaft.bottom_radius = 0.08
	shaft.height = 1.5
	shaft_mesh.mesh = shaft
	shaft_mesh.material_override = arrow_mat
	# Rotate to point along Z axis and position
	shaft_mesh.rotation.x = PI / 2  # Rotate from Y-up to Z-forward
	shaft_mesh.position = Vector3(0, 0.5, 0.75)  # Center of shaft at z=0.75
	_preview_container.add_child(shaft_mesh)

	# Arrow head (cone)
	var head_mesh := MeshInstance3D.new()
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.25
	head.height = 0.5
	head_mesh.mesh = head
	head_mesh.material_override = arrow_mat
	head_mesh.rotation.x = PI / 2  # Point along Z
	head_mesh.position = Vector3(0, 0.5, 1.75)  # At the end of the shaft
	_preview_container.add_child(head_mesh)


func _clear_preview() -> void:
	_preview_meshes.clear()
	if _preview_container != null and is_instance_valid(_preview_container):
		_preview_container.queue_free()
		_preview_container = null


func _exit_tree() -> void:
	_clear_preview()
	_clear_destination_markers()


# --- Destination Markers ---

func _show_destination_markers(target_pos: Vector3, target_rot: float) -> void:
	_clear_destination_markers()

	if _active_template == null:
		return

	_destination_markers = Node3D.new()
	_destination_markers.name = "_DestinationMarkers"
	get_tree().root.add_child(_destination_markers)
	_destination_markers.global_position = target_pos
	_destination_markers.rotation.y = target_rot

	# Create a ring/circle for each slot
	for i in _active_template.slots.size():
		var slot = _active_template.slots[i]
		var marker := MeshInstance3D.new()

		# Use a torus (ring) mesh for the marker
		var torus := TorusMesh.new()
		torus.inner_radius = 0.3
		torus.outer_radius = 0.5
		marker.mesh = torus

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.0, 0.0, 0.0, 0.7)  # Black, semi-transparent
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		marker.material_override = mat

		# Position flat on the ground
		var local_pos: Vector3 = slot.local_position * spacing_scale
		local_pos.y = 0.05  # Slightly above ground to avoid z-fighting
		marker.position = local_pos

		_destination_markers.add_child(marker)

	_marker_fade_time = MARKER_FADE_DURATION


func _clear_destination_markers() -> void:
	if _destination_markers != null and is_instance_valid(_destination_markers):
		_destination_markers.queue_free()
		_destination_markers = null


# --- Public API ---

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
	_target_position = target
	_has_target = true
	_start_rotation = rotation.y  # Store current rotation for interpolation

	# Calculate rotation based on movement direction and distance
	var to_target := target - global_position
	to_target.y = 0
	var distance := to_target.length()

	if is_nan(target_rot):
		if distance > 0.1:
			# Calculate desired rotation toward target
			var desired_rotation := atan2(to_target.x, to_target.z)
			# Scale rotation amount by distance
			_rotation_factor = _calculate_rotation_factor(distance)
			_target_rotation = lerp_angle(rotation.y, desired_rotation, _rotation_factor)
		else:
			# No significant movement, keep current rotation
			_rotation_factor = 0.0
			_target_rotation = rotation.y
	else:
		# Explicit rotation provided, use it fully
		_rotation_factor = 1.0
		_target_rotation = target_rot

	# Show destination markers with the rotation the formation will have when it arrives
	_show_destination_markers(_target_position, _target_rotation)

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
	if _active_template == null or slot_index >= _active_template.slots.size():
		return global_position

	var slot = _active_template.slots[slot_index]
	var local_pos: Vector3 = slot.local_position * spacing_scale

	# Transform by formation's rotation
	var rotated: Vector3 = local_pos.rotated(Vector3.UP, rotation.y)
	return global_position + rotated


func slot_to_world_rotation(slot_index: int) -> float:
	if _active_template == null or slot_index >= _active_template.slots.size():
		return rotation.y

	var slot = _active_template.slots[slot_index]
	return rotation.y + slot.local_rotation


func assign_unit(slot_index: int, unit: Node3D) -> bool:
	if _active_template == null:
		return false
	if slot_index < 0 or slot_index >= _active_template.slots.size():
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


func get_slot_assignment(slot_index: int):
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
	empty_slots.sort_custom(func(a, b):
		return _active_template.slots[a].priority > _active_template.slots[b].priority
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
				break  # Take first matching unit (greedy)

		if best_unit != null:
			assign_unit(slot_index, best_unit)
			units.remove_at(best_index)
			assigned_count += 1

	return assigned_count
