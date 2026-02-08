@tool
class_name GroundedKinematic3D
extends Kinematic3D
## Kinematic3D variant that snaps the parent's Y position to a height source.
##
## Moves the parent using velocity on the XZ plane and delegates vertical
## placement to the assigned [member height_provider]. Without a provider,
## Y position is determined by the base [Kinematic3D] velocity as normal.

@export var height_provider: HeightProvider: ## Determines the parent's Y position each frame
	set(value):
		height_provider = value
		update_configuration_warnings()

func _ready() -> void:
	super._ready()
	if height_provider:
		height_provider.setup(self)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _parent:
		return
	if height_provider:
		_parent.position.y = height_provider.get_height(_parent.global_position)
	velocity.y = 0.0

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not height_provider:
		warnings.append("A HeightProvider resource is required for ground snapping.")
	return warnings
