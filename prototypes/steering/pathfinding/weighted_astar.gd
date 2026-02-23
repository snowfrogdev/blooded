class_name WeightedAStar
extends AStar3D
## AStar3D subclass that delegates edge cost calculation to an array of [PathCostCalculator]
## strategies. Each calculator returns a non-negative penalty added to the base Euclidean
## distance via [code]base_distance * (1 + sum_of_penalties)[/code].

var cost_calculators: Array[PathCostCalculator] = []

## Called by AStar3D during every find_path() — keep calculators lightweight.
## Heavy computation should happen at grid build time via setup()/check_cell().
func _compute_cost(from_id: int, to_id: int) -> float:
	var from_pos = get_point_position(from_id)
	var to_pos = get_point_position(to_id)
	var base_distance := from_pos.distance_to(to_pos)
	var total_penalty := 0.0
	for calc in cost_calculators:
		total_penalty += calc.get_cost_penalty(from_pos, to_pos)
	var cost := base_distance * (1.0 + total_penalty)
	assert(cost >= 0.0, "Negative path cost — check calculator penalty values")
	return cost

func _estimate_cost(from_id: int, to_id: int) -> float:
	# Admissible heuristic — never overestimates (total_penalty >= 0)
	return get_point_position(from_id).distance_to(get_point_position(to_id))
