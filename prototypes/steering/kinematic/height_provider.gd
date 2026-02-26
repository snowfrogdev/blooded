@tool
@abstract class_name HeightProvider
extends Resource
## Abstract base for providing ground height at a given world position.
##
## Subclass this resource and override [method get_height] to snap entities to
## terrain, water surfaces, or any other height source. Override [method setup]
## to resolve scene-tree dependencies during [method Node._ready].

func setup(_context: Node) -> void:
	pass

@abstract func get_height(global_position: Vector3) -> float