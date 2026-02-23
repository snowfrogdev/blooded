class_name SlopePathCostCalculator
extends PathCostCalculator
## Adds slope-aware passability checks and directional edge-cost penalties.
##
## Rule A ([method check_cell]): Blocks cells exceeding [member max_slope_deg].
## Rule B ([method check_cell]): Forces subdivision of non-planar cells via
## discrete-Laplacian curvature detection — never blocks walkable terrain.
## Rule C ([method get_cost_penalty]): Applies asymmetric power-law edge-cost
## penalties for uphill/downhill traversal.

## Maximum walkable slope in degrees. Cells steeper than this are blocked entirely.
@export var max_slope_deg: float = 45.0
## Terrain non-planarity that triggers subdivision for finer cost resolution.
## Higher = coarser grid on hilly terrain. Units: height deviation per meter of cell width.
@export var curvature_threshold: float = 0.15
## Strength of uphill cost penalty.
@export var uphill_weight: float = 8.0
## Strength of downhill cost penalty (lower = downhill is cheaper).
@export var downhill_weight: float = 3.0
## Non-linearity of slope penalty (2.0 = quadratic, recommended).
@export_range(1.0, 4.0) var slope_exponent: float = 2.0

var _height_provider: HeightProvider
var _max_slope_ratio: float


func setup(context: Node) -> void:
	if "height_provider" in context:
		_height_provider = context.height_provider
	else:
		push_warning("SlopePathCostCalculator: context has no height_provider")
	_max_slope_ratio = tan(deg_to_rad(max_slope_deg))


func check_cell(
	pos: Vector3, cell_half_size: float, _space_state: PhysicsDirectSpaceState3D
) -> CellResult:
	if not _height_provider:
		return CellResult.PASSABLE

	# Sample heights at center + 4 edge midpoints.
	# NOTE: At terrain boundaries, height_provider may return NaN/0.0,
	# creating extreme slopes that block edge cells. This is intentional —
	# agents should not path off the world edge.
	var h_c := _height_provider.get_height(pos)
	var h_n := _height_provider.get_height(pos + Vector3(0, 0, cell_half_size))
	var h_s := _height_provider.get_height(pos + Vector3(0, 0, -cell_half_size))
	var h_e := _height_provider.get_height(pos + Vector3(cell_half_size, 0, 0))
	var h_w := _height_provider.get_height(pos + Vector3(-cell_half_size, 0, 0))

	# Rule A: Block cells with extreme slopes.
	var slopes := [
		absf(h_n - h_c) / cell_half_size,
		absf(h_s - h_c) / cell_half_size,
		absf(h_e - h_c) / cell_half_size,
		absf(h_w - h_c) / cell_half_size,
	]
	if slopes.max() > _max_slope_ratio:
		return CellResult.IMPASSABLE

	# Rule B: Non-planar terrain needs finer resolution for accurate edge costs.
	var ns_dev := absf(h_n + h_s - 2.0 * h_c)
	var ew_dev := absf(h_e + h_w - 2.0 * h_c)
	var curvature_val := maxf(ns_dev, ew_dev) / cell_half_size
	if curvature_val > curvature_threshold:
		return CellResult.SUBDIVIDE # Degrades to PASSABLE at min size

	return CellResult.PASSABLE


func get_cost_penalty(from_pos: Vector3, to_pos: Vector3) -> float:
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	var xz_dist := sqrt(dx * dx + dz * dz)
	if xz_dist < 0.0001:
		return 0.0

	var dy := to_pos.y - from_pos.y
	var slope := absf(dy) / xz_dist
	var weight := uphill_weight if dy > 0.0 else downhill_weight

	if slope_exponent == 2.0:
		return weight * slope * slope
	return weight * pow(slope, slope_exponent)
