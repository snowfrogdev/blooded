class_name SlopeDangerBehavior
extends ContextBehavior3D
## Fills danger when terrain slope exceeds the impassable threshold.
## Prevents corner-cutting across steep slopes that the pathfinder blocks.
## Binary response: slopes at or above [member max_slope_ratio] produce full
## danger; slopes below produce none. Samples height at consecutive points
## along each slot direction for graduated proximity-weighted danger.

## Maximum distance to sample terrain ahead.
@export var look_ahead: float = 6.0
## Number of distance samples per slot direction.
@export_range(1, 8) var num_samples: int = 5
## Slope ratio (rise/run) at or above which danger is applied.
## Default tan(45°) = 1.0, matching [member SlopePathCostCalculator.max_slope_deg]
## and [member ContextActuator.max_slope_ratio].
@export var max_slope_ratio: float = 1.0

var _height_provider: HeightProvider


func _init() -> void:
	resource_local_to_scene = true


func populate(agent: Node3D, kinematic: Kinematic3D, map: ContextMap3D) -> void:
	if not _ensure_height_provider(kinematic):
		return

	var origin := agent.global_position
	var origin_height := _height_provider.get_height(origin)
	var dangers: Array[float] = []
	dangers.resize(map.NUM_SLOTS)
	dangers.fill(0.0)

	var step := look_ahead / num_samples

	for i in map.NUM_SLOTS:
		var dir := map.ray_directions[i]
		var prev_height := origin_height
		for s in num_samples:
			var dist := step * (s + 1)
			var sample_pos := origin + dir * dist
			var cur_height := _height_provider.get_height(sample_pos)
			var slope_ratio := absf(cur_height - prev_height) / step
			if slope_ratio >= max_slope_ratio:
				var proximity := 1.0 - (dist / look_ahead)
				if proximity > dangers[i]:
					dangers[i] = proximity
			prev_height = cur_height

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


func _ensure_height_provider(kinematic: Kinematic3D) -> bool:
	if _height_provider:
		return true
	if kinematic is GroundedKinematic3D:
		_height_provider = kinematic.height_provider
	return _height_provider != null
