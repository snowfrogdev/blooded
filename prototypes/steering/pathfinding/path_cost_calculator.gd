class_name PathCostCalculator
extends Resource
## Base cost calculation strategy for pathfinding grid cells.
##
## Subclasses override only the methods relevant to their cost factor.
## All methods have safe defaults so that calculators can be composed freely.
## [b]Performance contract:[/b] [method get_cost_penalty] is called per-edge
## during every [code]find_path()[/code] query — keep it lightweight. Heavy
## computation (physics queries, raycasts, etc.) should happen at grid build time
## via [method check_cell] and cache results for fast lookup.

## Tri-state result for cell evaluation during grid construction.
enum CellResult {
	PASSABLE,   ## Cell is free to traverse at this resolution.
	IMPASSABLE, ## Cell is blocked — subdivide if above min size, else block.
	SUBDIVIDE,  ## Cell needs finer resolution — subdivide if above min size, else treat as PASSABLE.
}

## Return a non-negative extra cost fraction for traversing between positions.
## 0.0 = no penalty, 1.0 = doubles base cost. Called per-edge during pathfinding — must be fast.
func get_cost_penalty(_from_position: Vector3, _to_position: Vector3) -> float:
	return 0.0

## Evaluate a cell during grid construction. Return [constant PASSABLE] if the cell is
## free, [constant IMPASSABLE] if it contains obstacles or impassable terrain, or
## [constant SUBDIVIDE] if it needs finer resolution for accurate cost calculation.
## At minimum cell size, [constant SUBDIVIDE] degrades to [constant PASSABLE] (never blocks).
## The service passes the physics [param space_state] so calculators don't need to cache it.
func check_cell(
	_pos: Vector3, _cell_half_size: float, _space_state: PhysicsDirectSpaceState3D
) -> CellResult:
	return CellResult.PASSABLE

## Called once during grid setup to give calculator scene tree access.
func setup(_context: Node) -> void:
	pass
