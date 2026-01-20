@tool
extends EditorPlugin

const FormationGizmoPlugin := preload("res://addons/formation_editor/formation_gizmo_plugin.gd")

var _gizmo_plugin: FormationGizmoPlugin


func _enter_tree() -> void:
	_gizmo_plugin = FormationGizmoPlugin.new()
	_gizmo_plugin.editor_plugin = self
	add_node_3d_gizmo_plugin(_gizmo_plugin)


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmo_plugin)
