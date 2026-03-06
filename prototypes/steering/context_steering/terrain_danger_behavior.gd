class_name TerrainDangerBehavior
extends ContextBehavior3D
## Fills danger based on nearby terrain types. Repels the agent from
## impassable terrain (water) and reduces corner-cutting through expensive
## terrain (sand) during path following.
## Samples terrain at multiple distances per slot direction for graduated,
## proximity-weighted danger with neighbor spread for body clearance.

## Maximum distance to sample terrain ahead.
@export var look_ahead: float = 4.0
## Number of distance samples per slot direction.
@export_range(1, 8) var num_samples: int = 3
## Cost penalties keyed by terrain type. INF = impassable (full danger).
@export var terrain_costs: Dictionary = TerrainType.PATH_COSTS
## Cost value that maps to maximum danger (1.0). Costs at or above this
## produce full repulsion; lower costs scale proportionally.
@export var max_cost: float = 1.0

var _terrain: Terrain3D


func _init() -> void:
	resource_local_to_scene = true


func populate(agent: Node3D, _kinematic: Kinematic3D, map: ContextMap3D) -> void:
	if not _ensure_terrain(agent):
		return

	var origin := agent.global_position
	var dangers: Array[float] = []
	dangers.resize(map.NUM_SLOTS)
	dangers.fill(0.0)

	var step := look_ahead / num_samples

	for i in map.NUM_SLOTS:
		var dir := map.ray_directions[i]
		for s in num_samples:
			var dist := step * (s + 1)
			var sample_pos := origin + dir * dist
			var cost := _get_terrain_cost(sample_pos)
			if cost <= 0.0:
				continue
			var proximity := 1.0 - (dist / look_ahead)
			var intensity: float
			if is_inf(cost):
				intensity = 1.0
			else:
				intensity = clampf(cost / max_cost, 0.0, 1.0)
			var danger := proximity * intensity
			if danger > dangers[i]:
				dangers[i] = danger

	# Subtract baseline: remove uniform danger that only reduces speed
	# without providing directional information.
	var baseline := INF
	for i in map.NUM_SLOTS:
		if dangers[i] < baseline:
			baseline = dangers[i]
	if is_inf(baseline):
		return
	if baseline > 0.0:
		for i in map.NUM_SLOTS:
			dangers[i] -= baseline

	for i in map.NUM_SLOTS:
		if dangers[i] > 0.0:
			map.merge_danger(i, dangers[i])


func _get_terrain_cost(pos: Vector3) -> float:
	var tex := _terrain.data.get_texture_id(pos)
	if is_nan(tex.x):
		return 0.0
	var base_cost: float = terrain_costs.get(int(tex.x), 0.0)
	var overlay_cost: float = terrain_costs.get(int(tex.y), 0.0)
	# Handle INF: if either layer is impassable and dominant, return INF.
	if is_inf(base_cost) and tex.z < 0.5:
		return INF
	if is_inf(overlay_cost) and tex.z > 0.5:
		return INF
	# Clamp INF for blending.
	if is_inf(base_cost):
		base_cost = max_cost
	if is_inf(overlay_cost):
		overlay_cost = max_cost
	return lerpf(base_cost, overlay_cost, tex.z)


func _ensure_terrain(agent: Node3D) -> bool:
	if _terrain and is_instance_valid(_terrain):
		return _terrain.data != null
	_terrain = null
	var node = agent.get_tree().get_first_node_in_group("terrain")
	if node:
		_terrain = node as Terrain3D
		if not _terrain:
			push_error("TerrainDangerBehavior: node in 'terrain' group is not Terrain3D")
	return _terrain != null and _terrain.data != null
