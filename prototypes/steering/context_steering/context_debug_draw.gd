class_name ContextDebugDraw extends MeshInstance3D
## Visualizes context steering debug data using ImmediateMesh.
## Add as a sibling of [ContextSteering3D].

@export_group("Toggles")
@export var draw_effective: bool = true
@export var draw_danger: bool = true
@export var draw_chosen_direction: bool = true
@export var draw_pathfinding_path: bool = true
@export var draw_lookahead: bool = true
@export var draw_target: bool = true

@export_group("Colors")
@export var effective_color: Color = Color.GREEN
@export var danger_color: Color = Color.RED
@export var chosen_color: Color = Color.CYAN
@export var path_color: Color = Color(0.2, 0.6, 1.0, 0.8)
@export var lookahead_color: Color = Color.YELLOW
@export var target_color: Color = Color(1, 0.3, 0.7, 0.9)

@export_group("Scale")
## Maximum line length for slot values.
@export var ray_scale: float = 2.0
@export var path_half_width: float = 0.06
@export var chosen_line_width: float = 0.1

var _im: ImmediateMesh
var _material: StandardMaterial3D
var _steering: ContextSteering3D
var _moveable: Moveable3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_im = ImmediateMesh.new()
	mesh = _im

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for sibling in get_parent().get_children():
		if sibling is ContextSteering3D:
			_steering = sibling
		elif sibling is Moveable3D:
			_moveable = sibling

	top_level = true


func _process(_delta: float) -> void:
	if not _steering or not _im:
		return

	_im.clear_surfaces()

	var agent := _steering.get_parent() as Node3D
	if not agent:
		return
	var origin: Vector3 = agent.global_position + Vector3(0, 0.3, 0)

	# Check if we have data to draw.
	if _steering.debug_effective.is_empty():
		_draw_target_and_path(origin)
		return

	if not _steering._map:
		return
	var map_dirs: Array[Vector3] = _steering._map.ray_directions

	# --- Lines: effective, danger, chosen direction ---
	if draw_effective or draw_danger or draw_chosen_direction:
		_im.surface_begin(Mesh.PRIMITIVE_LINES, _material)

		if draw_effective:
			for i in _steering.debug_effective.size():
				var val: float = _steering.debug_effective[i]
				if val > 0.0:
					var end: Vector3 = origin + map_dirs[i] * val * ray_scale
					_draw_line(origin, end, effective_color)

		if draw_danger:
			for i in _steering.debug_danger.size():
				var val: float = _steering.debug_danger[i]
				if val > 0.0:
					var end: Vector3 = origin + map_dirs[i] * val * ray_scale
					_draw_line(origin, end, danger_color)

		if draw_chosen_direction and _steering.debug_chosen_strength > 0.0:
			var end: Vector3 = origin + _steering.debug_chosen_direction * _steering.debug_chosen_strength * ray_scale
			_draw_line(origin, end, chosen_color)

		_im.surface_end()

	_draw_target_and_path(origin)


func _draw_target_and_path(origin: Vector3) -> void:
	# --- Target cross ---
	if draw_target and _moveable and _moveable.has_target:
		_im.surface_begin(Mesh.PRIMITIVE_LINES, _material)
		var target_pos := _moveable.target_position + Vector3(0, 0.1, 0)
		_draw_cross(target_pos, 0.5, target_color)
		_im.surface_end()

	# --- Pathfinding path + lookahead (triangles for thick lines) ---
	if not _steering.path_provider:
		return
	var pp := _steering.path_provider
	if draw_pathfinding_path and not pp.debug_path.is_empty():
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
		var pts := pp.debug_path
		_im.surface_set_color(path_color)
		for i in pts.size() - 1:
			_draw_thick_line(pts[i], pts[i + 1], path_half_width)
		_im.surface_end()

	if draw_lookahead and pp.lookahead_target != Vector3.ZERO:
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
		var lp := pp.lookahead_target
		_im.surface_set_color(lookahead_color)
		_draw_thick_line(lp - Vector3(0.3, 0, 0), lp + Vector3(0.3, 0, 0), path_half_width)
		_draw_thick_line(lp - Vector3(0, 0, 0.3), lp + Vector3(0, 0, 0.3), path_half_width)
		_im.surface_end()


# --- Drawing helpers ---


func _draw_line(from: Vector3, to: Vector3, color: Color) -> void:
	_im.surface_set_color(color)
	_im.surface_add_vertex(from)
	_im.surface_add_vertex(to)


func _draw_cross(center: Vector3, size: float, color: Color) -> void:
	var half := size * 0.5
	_draw_line(center - Vector3(half, 0, 0), center + Vector3(half, 0, 0), color)
	_draw_line(center - Vector3(0, half, 0), center + Vector3(0, half, 0), color)
	_draw_line(center - Vector3(0, 0, half), center + Vector3(0, 0, half), color)


func _draw_thick_line(from: Vector3, to: Vector3, half_width: float) -> void:
	var dir := (to - from).normalized()
	var perp := Vector3(-dir.z, 0, dir.x) * half_width
	_im.surface_add_vertex(from - perp)
	_im.surface_add_vertex(to - perp)
	_im.surface_add_vertex(to + perp)
	_im.surface_add_vertex(from - perp)
	_im.surface_add_vertex(to + perp)
	_im.surface_add_vertex(from + perp)
