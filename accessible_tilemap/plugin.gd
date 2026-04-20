@tool
extends EditorPlugin



const Dock = preload("res://addons/accessible_tilemap/dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Accessible"
	_dock.editor_interface = get_editor_interface()
	_dock.editor_undo_redo = get_undo_redo()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
