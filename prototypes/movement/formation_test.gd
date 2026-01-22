extends Node3D
## Test script for formation system. Attach to the Movement root node.

@export var formation: Formation

var _units: Array[Unit] = []


func _ready() -> void:
	# Gather all units in the scene
	for child in get_children():
		if child is Unit:
			_units.append(child)

	print("Found ", _units.size(), " units")

	# Auto-assign units to formation if we have one
	if formation and _units.size() > 0:
		var assigned := formation.auto_assign_units(_units.duplicate())
		print("Assigned ", assigned, " units to formation")

		# Position formation at the average position of units
		var avg_pos := Vector3.ZERO
		for unit in _units:
			avg_pos += unit.global_position
		avg_pos /= _units.size()
		formation.global_position = avg_pos


func _input(event: InputEvent) -> void:
	if not formation:
		return

	# Press 1, 2, 3 to switch formations
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				if formation.templates.size() > 0:
					formation.active_template_index = 0
					print("Switched to: ", formation.get_active_template().display_name)
			KEY_2:
				if formation.templates.size() > 1:
					formation.active_template_index = 1
					print("Switched to: ", formation.get_active_template().display_name)
			KEY_3:
				if formation.templates.size() > 2:
					formation.active_template_index = 2
					print("Switched to: ", formation.get_active_template().display_name)
