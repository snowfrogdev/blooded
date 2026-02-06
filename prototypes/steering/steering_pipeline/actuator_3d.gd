class_name Actuator3D
extends Resource
## Determines how a character achieves its sub-goal based on physical capabilities.
##
## The Actuator3D takes the current sub-goal and returns a path describing how the
## character will move to reach it, plus the acceleration needed to follow that path.
## It decides which goal channels take priority and which to ignore based on the
## character's movement constraints.
##
## Simple characters (walking units, floating ghosts) can use trivial actuators that
## head straight for the target. Constrained characters (vehicles, tanks) need complex
## actuators that respect turning limits, acceleration, and movement direction.
## The pipeline supports both - use the simplest actuator that works.

func get_steering_path(agent: Node3D, kinematic: Kinematic3D, goal: Goal3D) -> SteeringPath3D:
	push_error("Actuator3D.get_steering_path() must be overridden")
	return null

func compute_steering(agent: Node3D, kinematic: Kinematic3D, path: SteeringPath3D, goal: Goal3D) -> SteeringOutput3D:
	push_error("Actuator3D.compute_steering() must be overridden")
	return null
