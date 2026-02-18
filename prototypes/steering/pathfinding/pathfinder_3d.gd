@tool
class_name Pathfinder3D
extends Node3D
## Scene-tree node that owns the AStar3D navigation grid and provides pathfinding queries to
## [PathfindingDecomposer] instances via the [code]"pathfinding"[/code] group.
##
## The grid is built on the first physics frame (not [code]_ready()[/code]) to ensure
## the physics world has synchronized all static bodies.

## Distance between grid cell centers in meters.
@export var cell_size: float = 1.5
## World-space XZ bounds of the grid. The gris spans from grid_min to grid_max.
@export var grid_min: Vector2 = Vector2(-64.0, -64.0)
@export var grid_max: Vector2 = Vector2(64.0, 64.0)
## Cost calculators applied during grid construction and pathfinding queries.
@export var cost_calculators: Array[PathCostCalculator] = []
## Enable debug visualization of grid points and paths.
@export var debug_enabled: bool = false

var _astar: WeightedAStar
var _grid_width: int # number of cells along X
var _grid_depth: int # number of cells along Z
var _terrain: Terrain3D
var _grid_built: bool = false
var _debug_mesh_instance: MeshInstance3D
var _debug_im: ImmediateMesh

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	if not _terrain:
		push_error("Pathfinder3D: no Terrain3D node found in 'terrain' group")
	_astar = WeightedAStar.new()
	_astar.cost_calculators = cost_calculators
	for calc in cost_calculators:
		calc.setup(self)
	if debug_enabled:
		_setup_debug()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _grid_built:
		_build_grid()
		_grid_built = true
		set_physics_process(false) # One-shot; disable after build

func _build_grid() -> void:
	_add_grid_points()
	_apply_passability()
	_connect_neighbors()
	if debug_enabled:
		_draw_debug_grid()

func _add_grid_points() -> void:
	_grid_width = int((grid_max.x - grid_min.x) / cell_size) + 1
	_grid_depth = int((grid_max.y - grid_min.y) / cell_size) + 1
	_astar.reserve_space(_grid_width * _grid_depth)
	for zi in _grid_depth:
		for xi in _grid_width:
			var world_x := grid_min.x + xi * cell_size
			var world_z := grid_min.y + zi * cell_size
			var world_y := 0.0
			if _terrain:
				world_y = _terrain.data.get_height(Vector3(world_x, 0.0, world_z))
			_astar.add_point(_grid_id(xi, zi), Vector3(world_x, world_y, world_z))

func _grid_id(xi: int, zi: int) -> int:
	return zi * _grid_width + xi

func _apply_passability() -> void:
	var space_state := get_world_3d().direct_space_state
	for zi in _grid_depth:
		for xi in _grid_width:
			var id := _grid_id(xi, zi)
			var pos := _astar.get_point_position(id)
			for calc in cost_calculators:
				if not calc.check_passability(pos, space_state):
					_astar.set_point_disabled(id, true)
					break

func _connect_neighbors() -> void:
	for zi in _grid_depth:
		for xi in _grid_width:
			var id := _grid_id(xi, zi)
			if _astar.is_point_disabled(id):
				continue
			# Cardinal connections (right, down) - bidirectional, so half-iteration suffices
			for offset in _CARDINAL_OFFSETS:
				var nx := xi + offset.x
				var nz := zi + offset.y
				if nx >= _grid_width or nz >= _grid_depth:
					continue
				var nid := _grid_id(nx, nz)
				if not _astar.is_point_disabled(nid):
					_astar.connect_points(id, nid)
			# Diagonal connections - only if at least one adjacent cardinal is passable
			for offset in _DIAGONAL_OFFSETS:
				var nx := xi + offset.x
				var nz := zi + offset.y
				if nx >= _grid_width or nz < 0 or nz >= _grid_depth:
					continue
				var nid := _grid_id(nx, nz)
				if _astar.is_point_disabled(nid):
					continue
				# Check the two cardinal cells that share the diagonal's corner
				var card_x := _grid_id(xi + offset.x, zi) # horizontal neighbor
				var card_z := _grid_id(xi, zi + offset.y) # vertical neighbor
				if _astar.is_point_disabled(card_x) and _astar.is_point_disabled(card_z):
					continue # Both cardinals blocked - would clip through corner
				_astar.connect_points(id, nid)

## Cardinal offsets checked first, then diagonals.
const _CARDINAL_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
const _DIAGONAL_OFFSETS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1)]

## Returns a path from [param from] to [param to] as world-space waypoints.
## Returns an empty array if no path exists or positions can't be snapped.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _grid_built:
		return PackedVector3Array()
	var from_id := _astar.get_closest_point(from)
	var to_id := _astar.get_closest_point(to)
	if from_id == -1 or to_id == -1 or from_id == to_id:
		return PackedVector3Array()
	return _astar.get_point_path(from_id, to_id)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if cost_calculators.is_empty():
		warnings.append("At least one PathCostCalculator is needed for meaningful pathfinding.")
	if not is_in_group("pathfinding"):
		warnings.append("This node should be in the 'pathfinding' group so decomposers can discover it.")
	return warnings

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

func _draw_debug_grid() -> void:
	_debug_im.clear_surfaces()
	var color := Color(1, 0, 0, 0.35)
	var half := cell_size * 0.5
	var y_offset := Vector3(0, 0.05, 0) # Slight lift to avoid z-fighting with terrain
	_debug_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _debug_mesh_instance.material_override)
	for zi in _grid_depth:
		for xi in _grid_width:
			var id := _grid_id(xi, zi)
			if not _astar.is_point_disabled(id):
				continue
			var pos := _astar.get_point_position(id) + y_offset
			var a := pos + Vector3(-half, 0, -half)
			var b := pos + Vector3(half, 0, -half)
			var c := pos + Vector3(half, 0, half)
			var d := pos + Vector3(-half, 0, half)
			_debug_im.surface_set_color(color)
			_debug_im.surface_add_vertex(a)
			_debug_im.surface_add_vertex(b)
			_debug_im.surface_add_vertex(c)
			_debug_im.surface_set_color(color)
			_debug_im.surface_add_vertex(a)
			_debug_im.surface_add_vertex(c)
			_debug_im.surface_add_vertex(d)
	_debug_im.surface_end()