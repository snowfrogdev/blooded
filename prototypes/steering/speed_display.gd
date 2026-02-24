class_name SpeedDisplay
extends CanvasLayer
## Shows the selected unit's speed in m/s.

@export var selection_controller: SelectionController

var _label: Label
var _selected_unit: Unit


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(10, 50)
	_label.visible = false
	add_child(_label)

	if selection_controller:
		selection_controller.selection_changed.connect(_on_selection_changed)


func _process(_delta: float) -> void:
	if not _selected_unit:
		return
	var kin: Kinematic3D = _selected_unit.get_node_or_null("GroundedKinematic3D")
	if not kin:
		return
	var v := kin.velocity
	var speed := Vector2(v.x, v.z).length()
	_label.text = "Speed: %.1f m/s" % speed


func _on_selection_changed(units: Array[Unit]) -> void:
	if units.is_empty():
		_selected_unit = null
		_label.visible = false
	else:
		_selected_unit = units[0]
		_label.visible = true
