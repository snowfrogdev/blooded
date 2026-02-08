class_name MoveToTargeter
extends Targeter3D

func get_goal(agent: Node3D) -> Goal3D:
	var goal = Goal3D.new()
	var moveable := _find_moveable(agent)
	if moveable and moveable.has_target:
		goal.has_position = true
		goal.position = moveable.target_position
	return goal

func _find_moveable(agent: Node3D) -> Moveable3D:
	for child in agent.get_children():
		if child is Moveable3D:
			return child
	return null
