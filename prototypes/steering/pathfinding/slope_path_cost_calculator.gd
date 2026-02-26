@tool
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

const SQRT2 := 1.4142135623730951
const MAX_SAMPLES_PER_AXIS := 16

var _height_provider: HeightProvider
var _max_slope_ratio: float
var _min_cell_size: float


func setup(context: Node) -> void:
	if "height_provider" in context:
		_height_provider = context.height_provider
	else:
		push_warning("SlopePathCostCalculator: context has no height_provider")
	if "min_cell_size" in context:
		_min_cell_size = context.min_cell_size
	else:
		_min_cell_size = 1.0
	_max_slope_ratio = tan(deg_to_rad(max_slope_deg))


func check_cell(
	pos: Vector3, cell_half_size: float, _space_state: PhysicsDirectSpaceState3D
) -> CellResult:
	if not _height_provider:
		return CellResult.PASSABLE

	# Density-scaled sampling: step at min_cell_size intervals, capped for large cells.
	var cell_width := cell_half_size * 2.0
	var step := maxf(_min_cell_size, cell_width / MAX_SAMPLES_PER_AXIS)
	var n := int(cell_width / step) + 1
	if n < 2:
		n = 2

	# Sample heights on an n×n grid covering the cell.
	# NOTE: At terrain boundaries, height_provider may return NaN/0.0,
	# creating extreme slopes that block edge cells. This is intentional —
	# agents should not path off the world edge.
	var origin_x := pos.x - cell_half_size
	var origin_z := pos.z - cell_half_size
	var heights := PackedFloat64Array()
	heights.resize(n * n)
	for j in n:
		var sz := origin_z + j * step
		for i in n:
			var sx := origin_x + i * step
			heights[j * n + i] = _height_provider.get_height(Vector3(sx, 0.0, sz))

	# Rule A: Block cells with extreme slopes between adjacent sample pairs.
	# Check horizontal, vertical, and both diagonal neighbors.
	var inv_step := 1.0 / step
	var inv_diag := 1.0 / (step * SQRT2)
	for j in n:
		var row := j * n
		for i in n:
			var h_cur := heights[row + i]
			# Right neighbor
			if i + 1 < n:
				if absf(heights[row + i + 1] - h_cur) * inv_step > _max_slope_ratio:
					return CellResult.IMPASSABLE
			# Down neighbor
			if j + 1 < n:
				if absf(heights[row + n + i] - h_cur) * inv_step > _max_slope_ratio:
					return CellResult.IMPASSABLE
			# Down-right diagonal
			if i + 1 < n and j + 1 < n:
				if absf(heights[row + n + i + 1] - h_cur) * inv_diag > _max_slope_ratio:
					return CellResult.IMPASSABLE
			# Down-left diagonal
			if i > 0 and j + 1 < n:
				if absf(heights[row + n + i - 1] - h_cur) * inv_diag > _max_slope_ratio:
					return CellResult.IMPASSABLE

	# Rule B: Non-planar terrain needs finer resolution for accurate edge costs.
	# Discrete Laplacian at every interior grid point.
	var curv_scale := inv_step * 0.25  # 1 / (4 * step) for 4-neighbor Laplacian
	for j in range(1, n - 1):
		var row := j * n
		for i in range(1, n - 1):
			var h_cur := heights[row + i]
			var laplacian := absf(
				heights[row + i - 1] + heights[row + i + 1]
				+ heights[row - n + i] + heights[row + n + i]
				- 4.0 * h_cur)
			if laplacian * curv_scale > curvature_threshold:
				return CellResult.SUBDIVIDE  # Degrades to PASSABLE at min size

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
