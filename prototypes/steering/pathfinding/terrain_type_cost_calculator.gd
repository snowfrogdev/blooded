@tool
class_name TerrainTypeCostCalculator
extends PathCostCalculator
## Adds terrain-type passability checks and movement-cost penalties.
##
## Rule A ([method check_cell]): Blocks cells containing impassable terrain
## (e.g. water) using density-scaled multi-sampling.
## Rule B ([method check_cell]): Forces subdivision of cells spanning multiple
## terrain types for finer cost resolution at boundaries.
## Rule C ([method get_cost_penalty]): Applies blend-aware cost penalties
## based on the destination cell's terrain type.

## Pathfinding cost penalties keyed by [enum TerrainType.Type].
## 0.0 = no penalty, 0.5 = +50% cost, INF = impassable.
@export var terrain_costs: Dictionary = TerrainType.PATH_COSTS
## Blend threshold above which an impassable overlay blocks the cell.
## At 0.5, a sample is blocked when the impassable texture is dominant.
@export_range(0.0, 1.0) var impassable_blend_threshold: float = 0.5

const MAX_SAMPLES_PER_AXIS := 16
## Finite stand-in for INF costs during edge-weight lerp. Impassable cells
## are already blocked by check_cell; this value just needs to be high enough
## that IMPASSABLE_PENALTY_THRESHOLD (9.0) in smoothing logic catches it.
const IMPASSABLE_COST_STANDIN := 10.0

var _terrain: Terrain3D
var _min_cell_size: float


func setup(context: Node) -> void:
	var terrain_node = context.get_tree().get_first_node_in_group("terrain")
	if terrain_node:
		_terrain = terrain_node as Terrain3D
		if not _terrain:
			push_error("TerrainTypeCostCalculator: node in 'terrain' group is not Terrain3D")
	else:
		push_error("TerrainTypeCostCalculator: no node in 'terrain' group found")
	if "min_cell_size" in context:
		_min_cell_size = context.min_cell_size
	else:
		_min_cell_size = 1.0


func check_cell(
	pos: Vector3, cell_half_size: float, _space_state: PhysicsDirectSpaceState3D
) -> CellResult:
	if not _terrain or not _terrain.data:
		return CellResult.PASSABLE

	# Density-scaled sampling: step at min_cell_size intervals, capped for large cells.
	var cell_width := cell_half_size * 2.0
	var step := maxf(_min_cell_size, cell_width / MAX_SAMPLES_PER_AXIS)
	var n := int(cell_width / step) + 1
	if n < 2:
		n = 2

	var origin_x := pos.x - cell_half_size
	var origin_z := pos.z - cell_half_size
	var first_type := -1
	var mixed := false

	for j in n:
		var sz := origin_z + j * step
		for i in n:
			var sx := origin_x + i * step
			var tex := _terrain.data.get_texture_id(Vector3(sx, 0.0, sz))
			if is_nan(tex.x):
				continue

			var base_id := int(tex.x)
			var overlay_id := int(tex.y)
			var blend := tex.z

			# Rule A: Block if any sample contains impassable terrain.
			var base_cost: float = terrain_costs.get(base_id, 0.0)
			var overlay_cost: float = terrain_costs.get(overlay_id, 0.0)
			if is_inf(base_cost) and blend < (1.0 - impassable_blend_threshold):
				return CellResult.IMPASSABLE
			if is_inf(overlay_cost) and blend > impassable_blend_threshold:
				return CellResult.IMPASSABLE

			# Track dominant type for Rule B (mixed-type subdivision).
			var dominant_id := overlay_id if blend > 0.5 else base_id
			if first_type < 0:
				first_type = dominant_id
			elif dominant_id != first_type:
				mixed = true

	# Rule B: Mixed terrain types need finer resolution for accurate edge costs.
	if mixed:
		return CellResult.SUBDIVIDE

	return CellResult.PASSABLE


func get_cost_penalty(_from_pos: Vector3, to_pos: Vector3) -> float:
	if not _terrain or not _terrain.data:
		return 0.0
	var tex := _terrain.data.get_texture_id(to_pos)
	if is_nan(tex.x):
		return 0.0

	var base_cost: float = terrain_costs.get(int(tex.x), 0.0)
	var overlay_cost: float = terrain_costs.get(int(tex.y), 0.0)

	# Clamp INF to avoid poisoning the lerp — impassable cells are already
	# blocked by check_cell, so any edge reaching them uses the finite cost.
	if is_inf(base_cost):
		base_cost = IMPASSABLE_COST_STANDIN
	if is_inf(overlay_cost):
		overlay_cost = IMPASSABLE_COST_STANDIN

	return lerpf(base_cost, overlay_cost, tex.z)
