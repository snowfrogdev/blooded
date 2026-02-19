class_name PathCostCalculator
extends Resource
## Base cost calculation strategy for pathfinding grid cells.
##
## Subclasses override only the methods relevant to their cost factor.
## All methods have safe defaults so that calculators can be composed freely.
## [b]Performance contract:[/b] [method get_cost_multiplier] is called per-edge
## during every [code]find_path()[/code] query - keep it lightweight. Heavy
## computation (physics queries, raycasts, etc.) should happen at grid build time
## and cache results for fast lookup.

## Return cost multiplier for traversing between positions. 1.0 = normal, INF = impassable.
## Called per-edge during pathfinding - must be fast.
func get_cost_multiplier(_from_position: Vector3, _to_position: Vector3) -> float:
	return 1.0

## Called once per cell during grid construction. Return [code]true[/code] if the cell is
## passable, [code]false[/code] to disable it. The service passes the physics [param space_state]
## so calculators don't need to cache it.
func check_passability(_pos: Vector3, _cell_half_size: float,_space_state: PhysicsDirectSpaceState3D) -> bool:
	return true

## Called once during grid setup to give calculator scene tree access.
func setup(_context: Node) -> void:
	pass