@tool
extends EditorPlugin


const Dock = preload("res://addons/accessible_animations/dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Accessible Animation"
	_dock.editor_interface = get_editor_interface()
	_dock.editor_undo_redo = get_undo_redo()
	add_control_to_bottom_panel(_dock, "Accessible Anim")
	var sel := get_editor_interface().get_selection()
	sel.selection_changed.connect(_dock._on_selection_changed)
	sel.selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	if _dock != null:
		var sel := get_editor_interface().get_selection()
		if sel.selection_changed.is_connected(_dock._on_selection_changed):
			sel.selection_changed.disconnect(_dock._on_selection_changed)
		if sel.selection_changed.is_connected(_on_selection_changed):
			sel.selection_changed.disconnect(_on_selection_changed)
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null


func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	for node in selected:
		if node is AnimationPlayer:
			make_bottom_panel_item_visible(_dock)
			return
		for child in node.get_children():
			if child is AnimationPlayer:
				make_bottom_panel_item_visible(_dock)
				return
	if _dock.is_visible_in_tree():
		hide_bottom_panel()
