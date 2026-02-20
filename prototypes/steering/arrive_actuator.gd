class_name ArriveActuator
extends Actuator3D

@export var max_speed: float = 4.0
@export var max_acceleration: float = 4.0
@export var slow_radius: float = 5.0
@export var target_radius: float = 0.3
@export var time_to_target: float = 0.15

@export_group("Turn Constraints")
## Maximum angular velocity (rad/s) of the velocity vector at [member reference_speed].
## Above reference_speed the effective rate scales inversely with speed, producing
## wider arcs at higher speed. Below reference_speed the rate stays at this maximum.
@export var max_turn_rate: float = 1.5
## Speed at which [member max_turn_rate] fully applies. Below this speed the turn
## rate is unconstrained (up to max_turn_rate). Above it the effective rate is
## max_turn_rate * reference_speed / current_speed.
@export var reference_speed: float = 2.0
## Below this speed the turn rate constraint is disabled entirely, allowing the
## unit to pivot in place.
@export var min_speed_for_turn_constraint: float = 0.3
## Fraction of [member max_acceleration] available for lateral (turning) force.
## Lower values make the unit slow down more aggressively before turns.
@export_range(0.1, 1.0) var lateral_fraction: float = 0.6

func get_steering_path(_agent: Node3D, _kinematic: Kinematic3D, goal: Goal3D) -> SteeringPath3D:
	var path := SteeringPath3D.new()
	if goal.has_position:
		path.points.append(goal.position)
	return path

func compute_steering(agent: Node3D, kinematic: Kinematic3D, _path: SteeringPath3D, goal: Goal3D) -> SteeringOutput3D:
	if not goal.has_position:
		return null

	var result := SteeringOutput3D.new()
	var direction := goal.position - agent.position
	var distance := direction.length()

	if distance < target_radius:
		return null

	# --- Arrive-based target speed ---
	var target_speed: float
	if distance <= slow_radius:
		target_speed = max_speed * distance / slow_radius
	else:
		target_speed = max_speed

	# --- Angle-distance speed modulation ---
	var vel_xz := Vector3(kinematic.velocity.x, 0.0, kinematic.velocity.z)
	var speed_xz := vel_xz.length()
	if speed_xz > min_speed_for_turn_constraint:
		var dir_xz := Vector3(direction.x, 0.0, direction.z)
		var dist_xz := dir_xz.length()
		if dist_xz > 0.001:
			var angle := vel_xz.angle_to(dir_xz)
			if angle > 0.01:
				var half_tan := maxf(tan(angle * 0.5), 0.01)
				var a_lateral := max_acceleration * lateral_fraction
				var v_safe := sqrt(a_lateral * dist_xz / half_tan)
				target_speed = minf(target_speed, maxf(v_safe, min_speed_for_turn_constraint))

	var target_velocity := direction.normalized() * target_speed

	result.linear_acceleration = target_velocity - kinematic.velocity
	result.linear_acceleration /= time_to_target

	if result.linear_acceleration.length() > max_acceleration:
		result.linear_acceleration = result.linear_acceleration.normalized()
		result.linear_acceleration *= max_acceleration

	# --- Turn rate constraint (perpendicular acceleration clamping) ---
	if speed_xz > min_speed_for_turn_constraint:
		result.linear_acceleration = _constrain_turn_rate(result.linear_acceleration, vel_xz, speed_xz)

	return result


## Clamps the perpendicular component of [param acceleration] so the velocity
## vector cannot rotate faster than the speed-coupled turn rate allows.
func _constrain_turn_rate(acceleration: Vector3, vel_xz: Vector3, speed_xz: float) -> Vector3:
	var v_dir := vel_xz / speed_xz

	# Decompose acceleration's XZ component into tangential and perpendicular.
	var accel_xz := Vector3(acceleration.x, 0.0, acceleration.z)
	var a_tangential := v_dir * accel_xz.dot(v_dir)
	var a_perpendicular := accel_xz - a_tangential

	# Effective turn rate scales inversely with speed above reference_speed.
	var speed_ratio := maxf(speed_xz / reference_speed, 1.0)
	var effective_turn_rate := max_turn_rate / speed_ratio

	var max_a_perp := effective_turn_rate * speed_xz
	var a_perp_len := a_perpendicular.length()

	if a_perp_len > max_a_perp:
		a_perpendicular *= max_a_perp / a_perp_len

	# Reconstruct: constrained XZ + original Y.
	return a_tangential + a_perpendicular + Vector3(0.0, acceleration.y, 0.0)