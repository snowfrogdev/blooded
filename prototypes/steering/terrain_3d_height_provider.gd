class_name Terrain3DHeightProvider
extends HeightProvider
## Height provider that reads elevation from a [Terrain3D] node.
##
## Expects a [Terrain3D] node in the [code]"terrain"[/code] group. Falls back
## to the current Y position if the terrain is unavailable or returns NaN.

var _terrain: Terrain3D

func setup(context: Node) -> void:
	var terrain_node = context.get_tree().get_first_node_in_group("terrain")
	if terrain_node:
		_terrain = terrain_node as Terrain3D
		if not _terrain:
			push_error("Terrain3DHeightProvider: node in 'terrain' group is not a Terrain3D")
	else:
		push_error("Terrain3DHeightProvider: no node in 'terrain' group found")

func get_height(global_position: Vector3) -> float:
	if _terrain and _terrain.data:
		var height = _terrain.data.get_height(global_position)
		if not is_nan(height):
			return height
	return global_position.y # Fallback: keep current height
