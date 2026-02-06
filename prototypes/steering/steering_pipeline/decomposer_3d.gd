class_name Decomposer3D
extends Resource
## Splits a goal into a more achievable sub-goal.
##
## Decomposers take a goal (e.g., a distant position) and return a closer sub-goal
## that moves toward it. The most common use is pathfinding: when a target is not
## directly reachable, a decomposer plans a route and returns the first waypoint.
##
## Decomposers are processed in order, enabling hierarchical decomposition. Early
## decomposers should act broadly (coarse pathfinding), while later ones refine the
## sub-goal in more detail. Each decomposer only sees the sub-goal from the previous
## stage, not the original target, allowing efficient multi-resolution planning.

func decompose(agent: Node3D, goal: Goal3D) -> Goal3D:
	push_error("Decomposer3D.decompose() must be overridden")
	return goal