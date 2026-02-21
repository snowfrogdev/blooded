class_name SteeringDebugDraw extends MeshInstance3D
## Visualizes steering pipeline debug data using ImmediateMesh.
## Add as a child of a node that has a SteeringPipeline3D sibling.

@export_group("Toggles")
@export var draw_whisker_rays: bool = true
@export var draw_sub_goals: bool = true
@export var draw_avoidance_zones: bool = true
@export var draw_pathfinding_path: bool = true
## When true, path segments are colored by turn sharpness at each waypoint
## (green = straight / full speed, red = sharp turn / slow). When false, uses
## the uniform [member path_color].
@export var color_path_by_turn_sharpness: bool = true
@export var draw_target: bool = true

@export_group("Colors")
@export var ray_hit_color: Color = Color.RED
@export var ray_miss_color: Color = Color.GREEN
@export var chosen_goal_color: Color = Color.CYAN
@export var rejected_goal_color: Color = Color(1, 1, 1, 0.3)
@export var avoidance_zone_color: Color = Color(1, 0.5, 0, 0.5)
@export var shape_outline_color: Color = Color(1, 1, 1, 0.2)
@export var path_color: Color = Color(0.2, 0.6, 1.0, 0.8)
@export var waypoint_color: Color = Color.YELLOW
@export var los_pullback_color: Color = Color(1.0, 0.4, 0.0, 1.0)
@export var target_color: Color = Color(1, 0.3, 0.7, 0.9)
@export var path_half_width: float = 0.06

var _im: ImmediateMesh
var _material: StandardMaterial3D
var _pipeline: SteeringPipeline3D
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

	# Find sibling SteeringPipeline3D and Moveable3D.
	for sibling in get_parent().get_children():
		if sibling is SteeringPipeline3D:
			_pipeline = sibling
		elif sibling is Moveable3D:
			_moveable = sibling

	# Use global coordinates — set top_level so the mesh isn't offset by parent transform.
	top_level = true


func _process(_delta: float) -> void:
	if not _pipeline or not _im:
		return

	_im.clear_surfaces()

	var has_constraint_lines := false
	for constraint in _pipeline.constraints:
		if constraint is AvoidObstacleConstraint and constraint.debug_enabled:
			if draw_whisker_rays and not constraint.debug_rays.is_empty():
				has_constraint_lines = true
			if draw_sub_goals and constraint.debug_violated:
				has_constraint_lines = true
			if draw_avoidance_zones and constraint.debug_violated:
				has_constraint_lines = true

	if has_constraint_lines:
		_im.surface_begin(Mesh.PRIMITIVE_LINES, _material)
		for constraint in _pipeline.constraints:
			if constraint is AvoidObstacleConstraint and constraint.debug_enabled:
				if draw_whisker_rays:
					_draw_whisker_rays(constraint)
				if draw_sub_goals:
					_draw_sub_goals(constraint)
				if draw_avoidance_zones:
					_draw_avoidance_zone(constraint)
		_im.surface_end()

	if draw_target and _moveable and _moveable.has_target:
		_im.surface_begin(Mesh.PRIMITIVE_LINES, _material)
		var target_pos := _moveable.target_position + Vector3(0, 0.1, 0)
		_draw_cross(target_pos, 0.5, target_color)
		_im.surface_end()

	if draw_pathfinding_path:
		var has_path := false
		for decomposer in _pipeline.decomposers:
			if decomposer is PathfindingDecomposer and not decomposer.debug_path.is_empty():
				has_path = true
				break
		if has_path:
			_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			for decomposer in _pipeline.decomposers:
				if decomposer is PathfindingDecomposer:
					_draw_pathfinding_path(decomposer)
			_im.surface_end()


func _draw_whisker_rays(constraint: AvoidObstacleConstraint) -> void:
	for ray in constraint.debug_rays:
		if ray.hit:
			_draw_line(ray.from, ray.hit_point, ray_hit_color)
			_draw_cross(ray.hit_point, 0.2, ray_hit_color)
		else:
			_draw_line(ray.from, ray.to, ray_miss_color)


func _draw_sub_goals(constraint: AvoidObstacleConstraint) -> void:
	if not constraint.debug_violated:
		return
	# Chosen candidate — solid cross.
	_draw_cross(constraint.debug_chosen, 0.4, chosen_goal_color)
	# Rejected candidate — dim cross.
	var rejected := constraint.debug_candidate_b \
		if constraint.debug_chosen == constraint.debug_candidate_a \
		else constraint.debug_candidate_a
	_draw_cross(rejected, 0.3, rejected_goal_color)
	# Lines from obstacle center to each candidate.
	_draw_line(constraint.debug_obstacle_center, constraint.debug_candidate_a, rejected_goal_color)
	_draw_line(constraint.debug_obstacle_center, constraint.debug_candidate_b, rejected_goal_color)


func _draw_avoidance_zone(constraint: AvoidObstacleConstraint) -> void:
	if not constraint.debug_violated:
		return
	var avoidance_radius := constraint.debug_half_width + constraint.margin
	_draw_circle_xz(constraint.debug_obstacle_center, avoidance_radius, avoidance_zone_color)
	_draw_circle_xz(constraint.debug_obstacle_center, constraint.debug_half_width, shape_outline_color)


func _draw_pathfinding_path(decomposer: PathfindingDecomposer) -> void:
	if decomposer.debug_path.is_empty():
		return
	var pts := decomposer.debug_path
	for i in pts.size() - 1:
		# Color the segment approaching a turn based on the turn sharpness at its
		# end-waypoint (i+1). The last segment has no outgoing direction, so it
		# falls back to the uniform path_color.
		if color_path_by_turn_sharpness and i < pts.size() - 2:
			_im.surface_set_color(_turn_color_at(pts, i + 1))
		else:
			_im.surface_set_color(path_color)
		_draw_thick_line(pts[i], pts[i + 1], path_half_width)
	var lp := decomposer.debug_lookahead_point
	var lp_color := los_pullback_color if decomposer.debug_los_pulled_back else waypoint_color
	_im.surface_set_color(lp_color)
	_draw_thick_line(lp - Vector3(0.3, 0, 0), lp + Vector3(0.3, 0, 0), path_half_width)
	_draw_thick_line(lp - Vector3(0, 0, 0.3), lp + Vector3(0, 0, 0.3), path_half_width)


## Returns a green-to-red color based on the turn angle at waypoint [param idx].
func _turn_color_at(pts: PackedVector3Array, idx: int) -> Color:
	var dir_in := (pts[idx] - pts[idx - 1]).normalized()
	var dir_out := (pts[idx + 1] - pts[idx]).normalized()
	var dot := clampf(dir_in.dot(dir_out), -1.0, 1.0)
	# 0 = straight (green), 1 = U-turn (red).
	var sharpness := 1.0 - (dot + 1.0) * 0.5
	return Color(sharpness, 1.0 - sharpness, 0.0, 0.8)


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


func _draw_circle_xz(center: Vector3, radius: float, color: Color, segments: int = 24) -> void:
	for i in segments:
		var angle_a := TAU * i / segments
		var angle_b := TAU * (i + 1) / segments
		var a := center + Vector3(cos(angle_a) * radius, 0, sin(angle_a) * radius)
		var b := center + Vector3(cos(angle_b) * radius, 0, sin(angle_b) * radius)
		_draw_line(a, b, color)
