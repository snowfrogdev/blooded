@tool
class_name FormationTemplate
extends Resource
## Defines a reusable formation shape (wedge, column, line, etc.)
## Contains slot positions for units or nested sub-formations.

## Display name for this formation (e.g., "Wedge", "Column", "Line")
@export var display_name: String = "Formation"

## Description of when to use this formation
@export_multiline var description: String = ""

## All slots in this formation
@export var slots: Array[SlotDefinition] = []

## Default spacing multiplier (allows runtime scaling)
@export var default_spacing: float = 1.0


func get_slot_count() -> int:
	return slots.size()
