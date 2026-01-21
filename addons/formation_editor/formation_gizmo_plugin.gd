@tool
extends EditorNode3DGizmoPlugin

var editor_plugin: EditorPlugin


func _init() -> void:
	# Create handle material - billboard=true makes handles face camera
	create_handle_material("slot_handle", false, null)
	create_material("lines", Color(0.5, 0.5, 0.5, 0.7), false, true)
	create_material("label_text", Color(1.0, 1.0, 1.0, 1.0), false, false)


func _get_gizmo_name() -> String:
	return "FormationGizmo"


func _get_priority() -> int:
	return -1


func _has_gizmo(node: Node3D) -> bool:
	return node is FormationInstance


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var formation := gizmo.get_node_3d() as FormationInstance
	if formation == null:
		return

	var template = formation.get_active_template()
	if template == null:
		return

	var slots: Array = template.slots
	if slots.is_empty():
		return

	# Collect handle positions
	var handles := PackedVector3Array()
	var lines := PackedVector3Array()

	for i in slots.size():
		var slot = slots[i]
		var pos: Vector3 = slot.local_position * formation.spacing_scale
		pos.y += 0.5  # Elevate handles slightly
		handles.append(pos)

		# Draw line from center to slot
		lines.append(Vector3(0, 0.5, 0))
		lines.append(pos)

	# Draw connecting lines
	gizmo.add_lines(lines, get_material("lines", gizmo), false)

	# Draw handles - use IDs array matching handle count
	var ids := PackedInt32Array()
	for i in handles.size():
		ids.append(i)

	gizmo.add_handles(handles, get_material("slot_handle", gizmo), ids, false, false)


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return "Slot %d" % handle_id


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var formation := gizmo.get_node_3d() as FormationInstance
	if formation == null:
		return Vector3.ZERO

	var template = formation.get_active_template()
	if template == null or handle_id >= template.slots.size():
		return Vector3.ZERO

	return template.slots[handle_id].local_position


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var formation := gizmo.get_node_3d() as FormationInstance
	if formation == null:
		return

	var template = formation.get_active_template()
	if template == null or handle_id >= template.slots.size():
		return

	# Project screen position to XZ plane at formation's Y position
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	# Plane at formation's global Y position (handles are at Y + 0.5, but we want the slot position)
	var plane := Plane(Vector3.UP, formation.global_position.y)
	var intersection = plane.intersects_ray(origin, dir)

	if intersection:
		# Convert world intersection to formation local space
		var local_pos: Vector3 = formation.to_local(intersection)
		template.slots[handle_id].local_position = local_pos / formation.spacing_scale

		# Trigger gizmo and preview update
		formation.update_gizmos()
		if formation.has_method("_update_editor_preview"):
			formation._update_editor_preview()


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var formation := gizmo.get_node_3d() as FormationInstance
	if formation == null:
		return

	var template = formation.get_active_template()
	if template == null or handle_id >= template.slots.size():
		return

	var slot = template.slots[handle_id]

	if cancel:
		slot.local_position = restore
		formation.update_gizmos()
		formation._update_editor_preview()
		return

	# Create undo/redo action using the plugin's undo/redo manager
	var undo_redo := editor_plugin.get_undo_redo()
	undo_redo.create_action("Move Formation Slot %d" % handle_id, UndoRedo.MERGE_DISABLE, formation)
	undo_redo.add_do_property(slot, "local_position", slot.local_position)
	undo_redo.add_undo_property(slot, "local_position", restore)
	undo_redo.add_do_method(formation, "update_gizmos")
	undo_redo.add_do_method(formation, "_update_editor_preview")
	undo_redo.add_undo_method(formation, "update_gizmos")
	undo_redo.add_undo_method(formation, "_update_editor_preview")
	undo_redo.commit_action(false)  # false = don't execute do, already done

	# Save the template resource to disk
	if template.resource_path != "":
		ResourceSaver.save(template, template.resource_path)
