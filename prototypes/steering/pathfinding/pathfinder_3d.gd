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

var _astar: WeightedAStar
var _root: QuadTree.Cell
var _leaves: Array[QuadTree.Cell]
var _grid_built: bool = false
var _debug_mesh_instance: MeshInstance3D
var _debug_im: ImmediateMesh
var _editor_mesh_instance: MeshInstance3D
var _editor_im: ImmediateMesh

func _ready() -> void:
	if Engine.is_editor_hint():
		return
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

	# Compute power-of-2 root that covers grid_min..grid_max
	var span := Vector2(grid_max.x - grid_min.x, grid_max.y - grid_min.y)
	var root_size := _next_power_of_2(maxf(span.x, span.y))
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
		_draw_debug_grid()

func _make_passability_checker(space_state: PhysicsDirectSpaceState3D) -> Callable:
	return func(center: Vector3, half_size: float) -> bool:
		for calc in cost_calculators:
			if not calc.check_passability(center, half_size, space_state):
				return false
		return true

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

static func _next_power_of_2(value: float) -> int:
	var p := 1
	while p < value:
		p *= 2
	return p


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

func _draw_debug_grid() -> void:
	_debug_im.clear_surfaces()
	if _leaves.is_empty():
		return
	var color := Color(0, 0.5, 0, 0.35)
	var blocked_color := Color(1, 0, 0, 0.35)
	var blocked_outline_color := Color(0.5, 0, 0, 0.5)
	var y_offset := Vector3(0, 0.05, 0)
	var line_hw := 0.06 # Half-width of outline quads

	# Draw blocked cells (fill + outline), then free cell outlines as thin quads
	_debug_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _debug_mesh_instance.material_override)
	_draw_blocked_leaves(_root, y_offset, blocked_color, blocked_outline_color, line_hw)
	_debug_im.surface_set_color(color)
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
	_debug_im.surface_end()

func _draw_line_quad(from: Vector3, to: Vector3, half_width: float) -> void:
	var dir := (to - from).normalized()
	var perp := Vector3(-dir.z, 0, dir.x) * half_width
	_debug_im.surface_add_vertex(from - perp)
	_debug_im.surface_add_vertex(to - perp)
	_debug_im.surface_add_vertex(to + perp)
	_debug_im.surface_add_vertex(from - perp)
	_debug_im.surface_add_vertex(to + perp)
	_debug_im.surface_add_vertex(from + perp)

func _draw_blocked_leaves(cell: QuadTree.Cell, y_offset: Vector3, color: Color, outline_color: Color, line_hw: float) -> void:
	if cell.is_leaf():
		if cell.is_blocked:
			var h := cell.half_size
			var a := _corner_pos(cell.center, -h, -h, y_offset)
			var b := _corner_pos(cell.center,  h, -h, y_offset)
			var c := _corner_pos(cell.center,  h,  h, y_offset)
			var d := _corner_pos(cell.center, -h,  h, y_offset)
			_debug_im.surface_set_color(color)
			_debug_im.surface_add_vertex(a)
			_debug_im.surface_add_vertex(b)
			_debug_im.surface_add_vertex(c)
			_debug_im.surface_add_vertex(a)
			_debug_im.surface_add_vertex(c)
			_debug_im.surface_add_vertex(d)
			_debug_im.surface_set_color(outline_color)
			_draw_line_quad(a, b, line_hw)
			_draw_line_quad(b, c, line_hw)
			_draw_line_quad(c, d, line_hw)
			_draw_line_quad(d, a, line_hw)
		return
	for child in cell.children:
		_draw_blocked_leaves(child, y_offset, color, outline_color, line_hw)
