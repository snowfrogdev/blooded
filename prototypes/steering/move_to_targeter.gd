class_name MoveToTargeter
extends Targeter3D

func get_goal(agent: Node3D) -> Goal3D:
	var goal = Goal3D.new()

	if agent.has_method("has_target") and agent.has_target():
		goal.has_position = true
		goal.position = agent.get_target_position()
	
	return goal
