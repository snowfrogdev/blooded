class_name Constraint3D
extends Resource
## Limits movement by detecting and avoiding obstacles or invalid paths.
##
## Constraints review the path toward the current sub-goal and detect if it would
## cause a violation (e.g., collision with an obstacle). If so, they suggest an
## alternative sub-goal to avoid the problem. A constraint may provide any channel:
## a position to steer around an obstacle, or a velocity to drift away from it.
##
## Multiple constraints may conflict - solving one may violate another. The pipeline
## iterates until all constraints are satisfied or deadlock is detected. In deadlock,
## a fallback behavior (e.g., wander or full pathfinding) takes over.

func is_violated(agent: Node3D, kinematic: Kinematic3D, path: SteeringPath3D) -> bool:
	push_error("Constraint3D.is_violated() must be overridden")
	return false

func suggest(agent: Node3D, path: SteeringPath3D, goal: Goal3D) -> Goal3D:
	push_error("Constraint3D.suggest() must be overridden")
	return goal