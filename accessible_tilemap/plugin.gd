@tool
extends EditorPlugin


const Dock = preload("res://addons/accessible_tilemap/dock.gd")
const InspectorPluginCls = preload("res://addons/accessible_tilemap/inspector_plugin.gd")

var _dock: Control = null
var _inspector_plugin: EditorInspectorPlugin = null


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.name = "Accessible"
	_dock.editor_interface = get_editor_interface()
	_dock.editor_undo_redo = get_undo_redo()
	add_control_to_bottom_panel(_dock, "Accessible Tilemap")
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)
	_inspector_plugin = InspectorPluginCls.new()
	_inspector_plugin.tileset_selected.connect(_on_tileset_resource_selected)
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	if _dock != null:
		var sel := get_editor_interface().get_selection()
		if sel.selection_changed.is_connected(_on_selection_changed):
			sel.selection_changed.disconnect(_on_selection_changed)
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null


func _on_tileset_resource_selected(ts: TileSet) -> void:
	if ts == null:
		return
	if ts.resource_path.is_empty() or "::" in ts.resource_path:
		return
	_dock._set_tileset_resource(ts)
	make_bottom_panel_item_visible(_dock)


func _on_selection_changed() -> void:
	var selected := get_editor_interface().get_selection().get_selected_nodes()
	for node in selected:
		if node is TileMapLayer:
			make_bottom_panel_item_visible(_dock)
			_dock._set_tileset_from_layer(node as TileMapLayer)
			return
	if not _dock._is_in_resource_mode() and _dock.is_visible_in_tree():
		hide_bottom_panel()
