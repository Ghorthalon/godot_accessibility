@tool
extends EditorPlugin

const Dock := preload("res://addons/accessible_input/dock.gd")

var dock

func _enter_tree() -> void:
	dock = Dock.new()
	dock.plugin = self
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

func _exit_tree() -> void:
	remove_control_from_docks(dock)
	dock.queue_free()
