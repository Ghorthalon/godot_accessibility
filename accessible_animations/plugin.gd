@tool
extends EditorPlugin


const Dock = preload("res://addons/accessible_animations/dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Accessible Animation"
	_dock.editor_interface = get_editor_interface()
	_dock.editor_undo_redo = get_undo_redo()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)
	get_editor_interface().get_selection().selection_changed.connect(_dock._on_selection_changed)


func _exit_tree() -> void:
	if _dock != null:
		var sel := get_editor_interface().get_selection()
		if sel.selection_changed.is_connected(_dock._on_selection_changed):
			sel.selection_changed.disconnect(_dock._on_selection_changed)
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
