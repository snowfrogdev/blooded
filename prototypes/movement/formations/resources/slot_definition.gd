@tool
class_name SlotDefinition
extends Resource
## Defines a single slot within a formation template.

## Position relative to the formation anchor/center
@export var local_position: Vector3 = Vector3.ZERO

## Rotation offset in radians (Y-axis)
@export var local_rotation: float = 0.0

## Tags that a unit must have to fill this slot (e.g., ["infantry"], ["infantry", "heavy"])
## Empty array means any unit can fill the slot
@export var required_tags: Array[StringName] = []

## Higher priority slots are filled first during assignment
@export var priority: int = 0


func can_accept_unit(unit_tags: Array[StringName]) -> bool:
	if required_tags.is_empty():
		return true
	# Unit must have ALL required tags
	for tag in required_tags:
		if tag not in unit_tags:
			return false
	return true
