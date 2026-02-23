class_name SteeringModeToggle
extends CanvasLayer
## UI toggle to switch all units between Pipeline and Context steering modes.

var _current_mode: StringName = &"context"
var _label: Label


func _ready() -> void:
	var hbox := HBoxContainer.new()
	hbox.position = Vector2(10, 10)
	add_child(hbox)

	var button := Button.new()
	button.text = "Toggle Steering"
	button.pressed.connect(_on_toggle_pressed)
	hbox.add_child(button)

	_label = Label.new()
	_label.text = "Context"
	hbox.add_child(_label)


func _on_toggle_pressed() -> void:
	if _current_mode == &"pipeline":
		_current_mode = &"context"
		_label.text = "Context"
	else:
		_current_mode = &"pipeline"
		_label.text = "Pipeline"

	for node in get_tree().root.find_children("*", "Unit", true, false):
		if node.has_method("set_steering_mode"):
			node.set_steering_mode(_current_mode)
