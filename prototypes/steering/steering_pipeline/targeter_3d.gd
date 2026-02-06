class_name Targeter3D
extends Resource
## Generates top-level goals for steering by specifying target channels.
##
## A Targeter3D produces goals across one or more channels: position, rotation,
## velocity, and angular_velocity. Unspecified channels are treated as "don't care."
## Multiple Targeters can cooperate by each filling different channels (e.g., one
## provides position while another provides rotation). When multiple Targeters
## are used, only one should write to each channel - no conflict resolution is performed.
##
## Unlike "away from" behaviors (obstacle avoidance), Targeters always specify where
## to go, not what to avoid. Avoidance logic belongs in the constraints stage.


func get_goal(agent: Node3D) -> Goal3D:
	push_error("Targeter3D.get_goal() must be overridden")
	return null