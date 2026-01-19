extends Camera3D

@export var move_speed := 20.0
@export var base_zoom_speed := 5.0
@export var min_size := 10.0
@export var max_size := 500.0

func _process(delta: float) -> void:
	var input := Vector3.ZERO

	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input.z -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input.z += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input.x += 1

	position += input.normalized() * move_speed * (size * 0.01) * delta

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Zoom speed scales with current size (exponential feel)
		# Each scroll step changes size by ~10%
		var zoom_amount := size * 0.1 * base_zoom_speed

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			size = max(size - zoom_amount, min_size)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size = min(size + zoom_amount, max_size)
