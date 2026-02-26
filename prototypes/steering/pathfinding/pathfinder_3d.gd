@tool
class_name Pathfinder3D
extends Node3D
## Scene-tree node that owns the AStar3D navigation grid and provides pathfinding queries to
## [PathfindingDecomposer] instances via the [code]"pathfinding"[/code] group.
##
## The grid is built on the first physics frame (not [code]_ready()[/code]) to ensure
## the physics world has synchronized all static bodies.

## Finest resolution near obstacles (full cell side length).
@export var min_cell_size: float = 1
## World-space XZ bounds of the grid. The grid spans from grid_min to grid_max.
@export var grid_min: Vector2 = Vector2(-64.0, -64.0)
@export var grid_max: Vector2 = Vector2(64.0, 64.0)
## Cost calculators applied during grid construction and pathfinding queries.
@export var cost_calculators: Array[PathCostCalculator] = []
## Provides ground elevation for cell centers.
@export var height_provider: HeightProvider
## Enable debug visualization of grid points and paths.
@export var debug_enabled: bool = false
@warning_ignore("unused_variable")
@export_tool_button("Build Editor Grid") var _build_editor_grid_btn = _build_editor_grid
@warning_ignore("unused_variable")
@export_tool_button("Clear Editor Grid") var _clear_editor_grid_btn = _clear_editor_grid

var _astar: WeightedAStar
var _root: QuadTree.Cell
var _leaves: Array[QuadTree.Cell]
var _grid_built: bool = false
var _editor_grid_built: bool = false
var _active_im: ImmediateMesh
var _debug_mesh_instance: MeshInstance3D
var _debug_im: ImmediateMesh
var _editor_mesh_instance: MeshInstance3D
var _editor_im: ImmediateMesh

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_root = null
	_leaves = []
	_editor_grid_built = false
	_astar = WeightedAStar.new()
	_astar.cost_calculators = cost_calculators
	height_provider.setup(self)
	for calc in cost_calculators:
		calc.setup(self)
	if debug_enabled:
		_setup_debug()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if not _editor_mesh_instance:
		_setup_editor_bounds()
	if not _editor_grid_built:
		_draw_editor_bounds()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _grid_built:
		_build_grid()
		_grid_built = true
		set_physics_process(false) # One-shot; disable after build

func _build_grid() -> void:
	var space_state := get_world_3d().direct_space_state
	var checker := _make_passability_checker(space_state)

	# Compute root as min_cell_size * 2^n so subdivision lands exactly on min_cell_size.
	var span := Vector2(grid_max.x - grid_min.x, grid_max.y - grid_min.y)
	var root_size := _next_aligned_size(maxf(span.x, span.y), min_cell_size)
	var root_center := Vector2((grid_min.x + grid_max.x) * 0.5, (grid_min.y + grid_max.y) * 0.5)

	_root = QuadTree.build(
		root_center, 
		root_size * 0.5, 
		min_cell_size * 0.5, 
		height_provider, 
		checker
	)
	_leaves = QuadTree.get_free_leaves(_root)

	# Register leaves in AStar3D
	_astar.reserve_space(_leaves.size())
	for i in _leaves.size():
		_leaves[i].astar_id = i
		_astar.add_point(i, _leaves[i].center)

	# Connect neighbors via Samet's algorithm (cardinal + diagonal)
	for leaf in _leaves:
		for dir in QuadTree.Direction.values():
			for neighbor in QuadTree.find_neighbors(leaf, dir):
				if neighbor.astar_id < 0:
					continue
				if _astar.are_points_connected(leaf.astar_id, neighbor.astar_id):
					continue
				if dir >= QuadTree.Direction.NE and not _is_diagonal_passable(leaf, neighbor):
					continue
				_astar.connect_points(leaf.astar_id, neighbor.astar_id)

	if debug_enabled:
		_draw_grid(_debug_im, _debug_mesh_instance.material_override)

func _make_passability_checker(space_state: PhysicsDirectSpaceState3D) -> Callable:
	return func(center: Vector3, half_size: float) -> PathCostCalculator.CellResult:
		var dominated := PathCostCalculator.CellResult.PASSABLE
		for calc in cost_calculators:
			var r := calc.check_cell(center, half_size, space_state)
			if r == PathCostCalculator.CellResult.IMPASSABLE:
				return r # Short-circuit: impassable dominates
			if r == PathCostCalculator.CellResult.SUBDIVIDE:
				dominated = r # Accumulate: subdivide if any calculator requests it
		return dominated

func _is_diagonal_passable(a: QuadTree.Cell, b: QuadTree.Cell) -> bool:
	var corner1 := Vector3(a.center.x, 0.0, b.center.z)
	var corner2 := Vector3(b.center.x, 0.0, a.center.z)
	var cell1 := QuadTree.find_leaf_at(_root, corner1)
	var cell2 := QuadTree.find_leaf_at(_root, corner2)
	if cell1 != null and cell1.is_blocked:
		return false
	if cell2 != null and cell2.is_blocked:
		return false
	return true

static func _next_aligned_size(span: float, cell_size: float) -> float:
	var size := cell_size
	while size < span:
		size *= 2.0
	return size


## Returns a path from [param from] to [param to] as world-space waypoints.
## Returns an empty array if no path exists or positions can't be snapped.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _grid_built:
		return PackedVector3Array()
	var from_id := _get_cell_id(from)
	var to_id := _get_cell_id(to)
	if from_id == -1 or to_id == -1 or from_id == to_id:
		return PackedVector3Array()
	return _astar.get_point_path(from_id, to_id)

## Returns true if a path exists between [param from] and [param to].
## Returns true for same-cell positions (trivially reachable).
func is_reachable(from: Vector3, to: Vector3) -> bool:
	if not _grid_built:
		return false
	var from_id := _get_cell_id(from)
	var to_id := _get_cell_id(to)
	if from_id == -1 or to_id == -1:
		return false
	if from_id == to_id:
		return true
	return not _astar.get_point_path(from_id, to_id).is_empty()

## Penalty threshold treating a smoothing sample as impassable. Must be below
## the INF-replacement value used by cost calculators (IMPASSABLE_COST_STANDIN
## in TerrainTypeCostCalculator) to catch edges that touch impassable terrain.
const IMPASSABLE_PENALTY_THRESHOLD := 9.0

## Maximum XZ distance between successive terrain-height samples during
## cost-integration walks. Smaller = more accurate but more samples.
const COST_STEP_SIZE: float = 1.0


## Returns true if the straight-line cost from [param path]\[from_idx] to
## [param path]\[to_idx] is within [param tolerance] of the original sub-path cost.
func is_shortcut_cost_acceptable(
	path: PackedVector3Array, from_idx: int, to_idx: int, tolerance: float
) -> bool:
	if cost_calculators.is_empty():
		return true
	var shortcut_cost := integrate_line_cost(path[from_idx], path[to_idx])
	var original_cost := sum_subpath_cost(path, from_idx, to_idx)
	return shortcut_cost <= original_cost * (1.0 + tolerance)


## Walks a straight line from [param from_pos] to [param to_pos] in steps of
## [constant COST_STEP_SIZE], summing distance * (1 + penalty). Returns INF if
## any sample lands in a blocked cell or exceeds the impassable threshold.
func integrate_line_cost(from_pos: Vector3, to_pos: Vector3) -> float:
	var total_dist := from_pos.distance_to(to_pos)
	if total_dist < 0.001:
		return 0.0
	var steps := maxi(1, ceili(total_dist / COST_STEP_SIZE))
	var step_dist := total_dist / steps
	var cost := 0.0
	for i in steps:
		var sample_from := from_pos.lerp(to_pos, float(i) / steps)
		var sample_to := from_pos.lerp(to_pos, float(i + 1) / steps)
		if height_provider:
			sample_from.y = height_provider.get_height(sample_from)
			sample_to.y = height_provider.get_height(sample_to)
		if not is_position_free(sample_from) or not is_position_free(sample_to):
			return INF
		var penalty := 0.0
		for calc in cost_calculators:
			penalty += calc.get_cost_penalty(sample_from, sample_to)
		if penalty > IMPASSABLE_PENALTY_THRESHOLD:
			return INF
		cost += step_dist * (1.0 + penalty)
	return cost


## Sums the cost along the original A* sub-path from [param from_idx] to
## [param to_idx], using each calculator's penalty.
func sum_subpath_cost(path: PackedVector3Array, from_idx: int, to_idx: int) -> float:
	var cost := 0.0
	for i in range(from_idx, to_idx):
		var seg_from := path[i]
		var seg_to := path[i + 1]
		var base_dist := seg_from.distance_to(seg_to)
		var penalty := 0.0
		for calc in cost_calculators:
			penalty += calc.get_cost_penalty(seg_from, seg_to)
		cost += base_dist * (1.0 + penalty)
	return cost


## Returns true if [param pos] lands in a free (passable) leaf cell.
func is_position_free(pos: Vector3) -> bool:
	var leaf := QuadTree.find_leaf_at(_root, pos)
	return leaf != null and leaf.astar_id >= 0

## Find the AStar ID of the free leaf containing [param pos].
## Uses quadtree containment first; falls back to nearest-point if the
## position is outside the grid or lands in a blocked cell.
func _get_cell_id(pos: Vector3) -> int:
	var leaf := QuadTree.find_leaf_at(_root, pos)
	if leaf and leaf.astar_id >= 0:
		return leaf.astar_id
	return _astar.get_closest_point(pos)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if cost_calculators.is_empty():
		warnings.append("At least one PathCostCalculator is needed for meaningful pathfinding.")
	if not is_in_group("pathfinding"):
		warnings.append("This node should be in the 'pathfinding' group so decomposers can discover it.")
	return warnings

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_editor_mesh_instance):
			_editor_mesh_instance.queue_free()

func _setup_editor_bounds() -> void:
	_editor_im = ImmediateMesh.new()
	_editor_mesh_instance = MeshInstance3D.new()
	_editor_mesh_instance.mesh = _editor_im
	_editor_mesh_instance.top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	_editor_mesh_instance.material_override = mat
	add_child(_editor_mesh_instance, false, Node.INTERNAL_MODE_BACK)

func _draw_editor_bounds() -> void:
	_editor_im.clear_surfaces()
	_editor_im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_editor_im.surface_set_color(Color(0.2, 0.6, 1.0, 0.8))
	var a := Vector3(grid_min.x, 0, grid_min.y)
	var b := Vector3(grid_max.x, 0, grid_min.y)
	var c := Vector3(grid_max.x, 0, grid_max.y)
	var d := Vector3(grid_min.x, 0, grid_max.y)
	_editor_im.surface_add_vertex(a)
	_editor_im.surface_add_vertex(b)
	_editor_im.surface_add_vertex(c)
	_editor_im.surface_add_vertex(d)
	_editor_im.surface_add_vertex(a) # Close the loop
	_editor_im.surface_end()

func _build_editor_grid() -> void:
	if not Engine.is_editor_hint():
		return
	if not height_provider:
		push_warning("Pathfinder3D: Cannot build editor grid — no height_provider set.")
		return
	if cost_calculators.is_empty():
		push_warning("Pathfinder3D: No cost calculators set. Grid will show all cells as passable.")

	height_provider.setup(self)
	for calc in cost_calculators:
		calc.setup(self)

	if not _editor_mesh_instance:
		_setup_editor_bounds()
	var mat := _editor_mesh_instance.material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var space_state := get_world_3d().direct_space_state
	var checker := _make_passability_checker(space_state)
	var span := Vector2(grid_max.x - grid_min.x, grid_max.y - grid_min.y)
	var root_size := _next_aligned_size(maxf(span.x, span.y), min_cell_size)
	var root_center := Vector2((grid_min.x + grid_max.x) * 0.5, (grid_min.y + grid_max.y) * 0.5)

	_root = QuadTree.build(root_center, root_size * 0.5, min_cell_size * 0.5, height_provider, checker)
	_leaves = QuadTree.get_free_leaves(_root)

	_draw_grid(_editor_im, mat)
	_editor_grid_built = true
	print("Pathfinder3D: Editor grid built — %d free leaves" % _leaves.size())

func _clear_editor_grid() -> void:
	if not Engine.is_editor_hint():
		return
	_root = null
	_leaves = []
	_editor_grid_built = false
	if _editor_im:
		_editor_im.clear_surfaces()
	if _editor_mesh_instance:
		var mat := _editor_mesh_instance.material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_BACK

func _setup_debug() -> void:
	_debug_im = ImmediateMesh.new()
	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.mesh = _debug_im
	_debug_mesh_instance.top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_mesh_instance.material_override = mat
	add_child(_debug_mesh_instance)

func _corner_pos(center: Vector3, dx: float, dz: float, y_offset: Vector3) -> Vector3:
	var pos := Vector3(center.x + dx, 0.0, center.z + dz)
	pos.y = height_provider.get_height(pos) if height_provider else center.y
	return pos + y_offset

func _draw_grid(im: ImmediateMesh, mat: Material) -> void:
	_active_im = im
	im.clear_surfaces()
	if _leaves.is_empty():
		_active_im = null
		return
	var color := Color(0, 0.5, 0, 0.35)
	var blocked_color := Color(1, 0, 0, 0.35)
	var blocked_outline_color := Color(0.5, 0, 0, 0.5)
	var y_offset := Vector3(0, 0.05, 0)
	var line_hw := 0.06 # Half-width of outline quads

	# Draw blocked cells (fill + outline), then free cell outlines as thin quads
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	_draw_blocked_leaves(_root, y_offset, blocked_color, blocked_outline_color, line_hw)
	_active_im.surface_set_color(color)
	for leaf in _leaves:
		var h := leaf.half_size
		var a := _corner_pos(leaf.center, -h, -h, y_offset)
		var b := _corner_pos(leaf.center,  h, -h, y_offset)
		var c := _corner_pos(leaf.center,  h,  h, y_offset)
		var d := _corner_pos(leaf.center, -h,  h, y_offset)
		_draw_line_quad(a, b, line_hw)
		_draw_line_quad(b, c, line_hw)
		_draw_line_quad(c, d, line_hw)
		_draw_line_quad(d, a, line_hw)
	im.surface_end()
	_active_im = null

func _draw_line_quad(from: Vector3, to: Vector3, half_width: float) -> void:
	var dir := (to - from).normalized()
	var perp := Vector3(-dir.z, 0, dir.x) * half_width
	_active_im.surface_add_vertex(from - perp)
	_active_im.surface_add_vertex(to - perp)
	_active_im.surface_add_vertex(to + perp)
	_active_im.surface_add_vertex(from - perp)
	_active_im.surface_add_vertex(to + perp)
	_active_im.surface_add_vertex(from + perp)

func _draw_blocked_leaves(cell: QuadTree.Cell, y_offset: Vector3, color: Color, outline_color: Color, line_hw: float) -> void:
	if cell.is_leaf():
		if cell.is_blocked:
			var h := cell.half_size
			var a := _corner_pos(cell.center, -h, -h, y_offset)
			var b := _corner_pos(cell.center,  h, -h, y_offset)
			var c := _corner_pos(cell.center,  h,  h, y_offset)
			var d := _corner_pos(cell.center, -h,  h, y_offset)
			_active_im.surface_set_color(color)
			_active_im.surface_add_vertex(a)
			_active_im.surface_add_vertex(b)
			_active_im.surface_add_vertex(c)
			_active_im.surface_add_vertex(a)
			_active_im.surface_add_vertex(c)
			_active_im.surface_add_vertex(d)
			_active_im.surface_set_color(outline_color)
			_draw_line_quad(a, b, line_hw)
			_draw_line_quad(b, c, line_hw)
			_draw_line_quad(c, d, line_hw)
			_draw_line_quad(d, a, line_hw)
		return
	for child in cell.children:
		_draw_blocked_leaves(child, y_offset, color, outline_color, line_hw)
