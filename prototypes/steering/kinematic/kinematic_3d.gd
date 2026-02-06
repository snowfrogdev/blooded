class_name Kinematic3D
extends Node
## Applies velocity and angular velocity to the parent Node3D each physics frame.
##
## Add as a child of any Node3D to give it kinematic movement. External systems
## (steering behaviors, AI, etc.) set [member velocity] and [member angular_velocity]
## directly, and this component handles applying them to the parent's transform.

@export_group("Debug (Runtime)") # Only meant for runtime debugging
@export var velocity: Vector3 = Vector3.ZERO ## Units per second
@export var angular_velocity: float = 0.0 ## Radians per second around Y axis

var _parent: Node3D

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_parent = get_parent() as Node3D
	if not _parent:
		push_error("Kinematic3D must be a child of a Node3D")

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _parent:
		return
	_parent.position += velocity * delta
	_parent.rotation.y += angular_velocity * delta