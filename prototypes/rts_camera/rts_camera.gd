class_name RTSCamera
extends Node3D
## RTS-style camera with WASD movement, QE rotation, mouse wheel zoom, and automatic tilt.

# === Signals ===
signal zoom_changed(zoom_level: float)

# === Movement Settings ===
@export_group("Movement")
@export var move_speed: float = 20.0
@export_range(0.1, 50.0) var move_smoothing: float = 10.0

# === Rotation Settings ===
@export_group("Rotation")
@export var rotation_speed: float = 2.0  ## Radians per second
@export_range(0.1, 50.0) var rotation_smoothing: float = 10.0

# === Zoom Settings ===
@export_group("Zoom")
@export var zoom_min_distance: float = 5.0
@export var zoom_max_distance: float = 50.0
@export_range(0.01, 0.3) var zoom_step: float = 0.1
@export_range(0.1, 50.0) var zoom_smoothing: float = 8.0
@export_range(0.0, 1.0) var initial_zoom: float = 0.5

# === Tilt Settings ===
@export_group("Tilt")
@export_range(-90.0, 0.0) var pitch_at_min_zoom: float = -45.0  ## Degrees, when zoomed in (close)
@export_range(-90.0, 0.0) var pitch_at_max_zoom: float = -75.0  ## Degrees, when zoomed out (far)
@export_range(0.1, 50.0) var tilt_smoothing: float = 8.0

# === Mouse Camera Control ===
@export_group("Mouse Camera Control")
@export var allow_mouse_camera_control: bool = true
@export_range(0.0, 30.0) var tilt_offset_max: float = 15.0  ## Max tilt offset in degrees
@export_range(0.001, 0.5) var tilt_mouse_sensitivity: float = 0.2
@export_range(0.001, 0.02) var rotation_mouse_sensitivity: float = 0.005
@export var invert_tilt: bool = false  ## Invert vertical mouse direction for tilt

# === Node References ===
@onready var _gimbal: Node3D = $Gimbal
@onready var _camera_arm: Node3D = $Gimbal/CameraArm
@onready var _camera: Camera3D = $Gimbal/CameraArm/Camera3D

# === Internal State ===
var _target_position: Vector3
var _target_yaw: float
var _target_zoom: float  # 0 = close, 1 = far
var _zoom_level: float
var _tilt_offset: float = 0.0  # Degrees, added to zoom-based pitch
var _yaw_offset: float = 0.0   # Radians, added to Q/E rotation
var _is_mouse_looking: bool = false


func _ready() -> void:
	_target_position = position
	_target_yaw = rotation.y
	_target_zoom = initial_zoom
	_zoom_level = initial_zoom
	_apply_zoom_immediate()
	_apply_tilt_immediate()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_toward_cursor(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_toward_cursor(zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_mouse_looking = event.pressed

	elif event is InputEventMouseMotion and _is_mouse_looking and allow_mouse_camera_control:
		# Horizontal drag → rotation (yaw)
		_yaw_offset -= event.relative.x * rotation_mouse_sensitivity
		# Vertical drag → tilt (pitch)
		var tilt_direction := -1.0 if invert_tilt else 1.0
		_tilt_offset += event.relative.y * tilt_mouse_sensitivity * tilt_direction
		_tilt_offset = clampf(_tilt_offset, -tilt_offset_max, tilt_offset_max)


func _process(delta: float) -> void:
	_update_movement(delta)
	_update_rotation(delta)
	_update_zoom(delta)
	_update_tilt(delta)


# === Movement ===
func _update_movement(delta: float) -> void:
	var input_dir := _get_movement_input()
	if input_dir.length_squared() < 0.001:
		# Apply smoothing even when not moving (coast to a stop)
		position = position.lerp(_target_position, 1.0 - exp(-move_smoothing * delta))
		return

	# Convert 2D input to 3D movement direction
	var move_dir := Vector3(input_dir.x, 0.0, input_dir.y)
	# Rotate by camera's current yaw so movement is relative to view
	move_dir = move_dir.rotated(Vector3.UP, rotation.y)

	_target_position += move_dir * move_speed * delta
	position = position.lerp(_target_position, 1.0 - exp(-move_smoothing * delta))


func _get_movement_input() -> Vector2:
	var input := Vector2.ZERO

	# Try custom actions first, fall back to ui actions or direct keys
	if Input.is_action_pressed("move_forward") or Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_action_pressed("move_back") or Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_action_pressed("move_right") or Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input.x += 1.0

	return input.normalized() if input.length() > 1.0 else input


# === Rotation ===
func _update_rotation(delta: float) -> void:
	var rot_input := _get_rotation_input()
	_target_yaw += rot_input * rotation_speed * delta
	# Combine Q/E target with mouse offset
	var effective_yaw := _target_yaw + _yaw_offset
	rotation.y = lerp_angle(rotation.y, effective_yaw, 1.0 - exp(-rotation_smoothing * delta))


func _get_rotation_input() -> float:
	var input := 0.0

	# Try custom actions first, fall back to direct keys
	if Input.is_action_pressed("rotate_left") or Input.is_key_pressed(KEY_Q):
		input += 1.0
	if Input.is_action_pressed("rotate_right") or Input.is_key_pressed(KEY_E):
		input -= 1.0

	return input


# === Zoom ===
func _zoom_toward_cursor(zoom_delta: float) -> void:
	# Get world position under cursor before zoom
	var mouse_pos := get_viewport().get_mouse_position()
	var world_pos_before: Variant = _get_ground_position_at_screen(mouse_pos)

	# Apply zoom
	var old_zoom := _target_zoom
	_target_zoom = clampf(_target_zoom + zoom_delta, 0.0, 1.0)

	# If zoom didn't change, no need to adjust position
	if absf(_target_zoom - old_zoom) < 0.001:
		return

	# Calculate what the world position would be after zoom (at target state)
	# We need to simulate the zoom to find the new ground position
	var saved_zoom := _zoom_level
	var saved_arm_pos := _camera_arm.position.z
	var saved_gimbal_rot := _gimbal.rotation.x

	# Temporarily apply target zoom to calculate new intersection
	_zoom_level = _target_zoom
	_apply_zoom_immediate()
	_apply_tilt_immediate()

	var world_pos_after: Variant = _get_ground_position_at_screen(mouse_pos)

	# Restore actual state
	_zoom_level = saved_zoom
	_camera_arm.position.z = saved_arm_pos
	_gimbal.rotation.x = saved_gimbal_rot

	# Adjust target position to keep the same world point under cursor
	if world_pos_before != null and world_pos_after != null:
		var offset: Vector3 = world_pos_before - world_pos_after
		_target_position += Vector3(offset.x, 0.0, offset.z)


func _update_zoom(delta: float) -> void:
	var old_level := _zoom_level
	_zoom_level = lerpf(_zoom_level, _target_zoom, 1.0 - exp(-zoom_smoothing * delta))

	var distance := lerpf(zoom_min_distance, zoom_max_distance, _zoom_level)
	_camera_arm.position.z = distance

	if absf(_zoom_level - old_level) > 0.001:
		zoom_changed.emit(_zoom_level)


func _apply_zoom_immediate() -> void:
	var distance := lerpf(zoom_min_distance, zoom_max_distance, _zoom_level)
	_camera_arm.position.z = distance


func _get_ground_position_at_screen(screen_pos: Vector2) -> Variant:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	# Intersect with ground plane at y=0
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(ray_origin, ray_dir)


# === Tilt ===
func _update_tilt(delta: float) -> void:
	# Base pitch from zoom level
	var base_pitch := lerpf(
		deg_to_rad(pitch_at_min_zoom),
		deg_to_rad(pitch_at_max_zoom),
		_zoom_level
	)
	# Add user offset from mouse control
	var target_pitch := base_pitch + deg_to_rad(_tilt_offset)
	# Clamp to valid range (prevent looking up or straight down)
	target_pitch = clampf(target_pitch, deg_to_rad(-85.0), deg_to_rad(-10.0))

	_gimbal.rotation.x = lerpf(
		_gimbal.rotation.x,
		target_pitch,
		1.0 - exp(-tilt_smoothing * delta)
	)


func _apply_tilt_immediate() -> void:
	var base_pitch := lerpf(
		deg_to_rad(pitch_at_min_zoom),
		deg_to_rad(pitch_at_max_zoom),
		_zoom_level
	)
	var target_pitch := base_pitch + deg_to_rad(_tilt_offset)
	target_pitch = clampf(target_pitch, deg_to_rad(-85.0), deg_to_rad(-10.0))
	_gimbal.rotation.x = target_pitch
