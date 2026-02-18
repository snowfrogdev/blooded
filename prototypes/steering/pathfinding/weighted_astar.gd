class_name WeightedAStar
extends AStar3D
## AStar3D subclass that delegates edge cost calculation to an array of [PathCostCalculator]
## strategies. Each calculator returns a multiplier applied to the base Euclidean distance.

var cost_calculators: Array[PathCostCalculator] = []

## Called by AStar3D during every find_path() - keep calculators lightweight.
## Heavy computation should happen at grid build time viat setup()/check_passability().
func _compute_cost(from_id: int, to_id: int) -> float:
	var from_pos = get_point_position(from_id)
	var to_pos = get_point_position(to_id)
	var base_distance := from_pos.distance_to(to_pos)
	for calc in cost_calculators:
		base_distance *= calc.get_cost_multiplier(from_pos, to_pos)
	return base_distance

func _estimate_cost(from_id: int, to_id: int) -> float:
	# Admissible heuristic - never overestimates
	return get_point_position(from_id).distance_to(get_point_position(to_id))