class_name ContextMap3D
extends RefCounted
## Direction-selection data structure using interest and danger arrays.
## Based on Andrew Fray's context steering approach (Game AI Pro 2, GDC 2013).
##
## Each slot represents a direction on the XZ plane at 15-degree intervals.
## Behaviors populate the interest and danger arrays via max-merging, then
## [method evaluate] subtracts danger from interest per slot to find the best
## direction. The effective strength of the winning slot drives speed — danger
## eating into interest produces emergent deceleration near obstacles.

const NUM_SLOTS: int = 24

var interest: Array[float] = []
var danger: Array[float] = []
var ray_directions: Array[Vector3] = []

## Result of [method evaluate], read by the orchestrator.
var chosen_direction: Vector3 = Vector3.ZERO
## Effective value of the winning slot. Used by the actuator as
## interest_speed = chosen_strength * max_speed.
var chosen_strength: float = 0.0


func _init() -> void:
	interest.resize(NUM_SLOTS)
	danger.resize(NUM_SLOTS)
	interest.fill(0.0)
	danger.fill(0.0)
	ray_directions.resize(NUM_SLOTS)
	for i in NUM_SLOTS:
		var angle := TAU * i / NUM_SLOTS
		ray_directions[i] = Vector3(cos(angle), 0.0, sin(angle))


func clear() -> void:
	interest.fill(0.0)
	danger.fill(0.0)


func merge_interest(slot: int, value: float) -> void:
	interest[slot] = maxf(interest[slot], value)


func merge_danger(slot: int, value: float) -> void:
	danger[slot] = maxf(danger[slot], value)


## Subtracts danger from interest per slot, picks the best direction, and sets
## [member chosen_direction] and [member chosen_strength].
func evaluate() -> void:
	var best_slot: int = -1
	var best_value: float = 0.0

	for i in NUM_SLOTS:
		var effective := maxf(0.0, interest[i] - danger[i])
		if effective > best_value:
			best_value = effective
			best_slot = i

	# All-zero edge case: no viable direction. Orchestrator must brake.
	if best_slot < 0 or best_value <= 0.0:
		chosen_direction = Vector3.ZERO
		chosen_strength = 0.0
		return

	# Interpolate with neighbors for sub-slot precision.
	var prev := posmod(best_slot - 1, NUM_SLOTS)
	var next := posmod(best_slot + 1, NUM_SLOTS)
	var val_prev := maxf(0.0, interest[prev] - danger[prev])
	var val_next := maxf(0.0, interest[next] - danger[next])

	var weighted_dir := ray_directions[best_slot] * best_value \
		+ ray_directions[prev] * val_prev \
		+ ray_directions[next] * val_next

	var length := weighted_dir.length()
	if length > 0.0001:
		chosen_direction = weighted_dir / length
	else:
		chosen_direction = ray_directions[best_slot]

	chosen_strength = best_value
