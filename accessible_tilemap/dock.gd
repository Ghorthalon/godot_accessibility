@tool
extends VBoxContainer

const AccessibleAnnouncerCls := preload("res://addons/accessible_tilemap/announcer.gd")
const AtlasTabCls := preload("res://addons/accessible_tilemap/atlas_tab.gd")
const MapTabCls := preload("res://addons/accessible_tilemap/map_tab.gd")
const SpatialTabCls := preload("res://addons/accessible_tilemap/spatial_tab.gd")

# Set from plugin.gd before _ready().
var editor_interface: EditorInterface
var editor_undo_redo: EditorUndoRedoManager

var announcer: AccessibleAnnouncer
var _tabs: TabContainer
var _atlas_tab
var _map_tab
var _spatial_tab

func _ready() -> void:
	custom_minimum_size = Vector2(320, 400)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	announcer = AccessibleAnnouncerCls.new()
	announcer.name = "Announcer"
	add_child(announcer)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_tabs = false
	if _tabs.has_method(&"set_accessibility_name"):
		_tabs.call(&"set_accessibility_name", "Accessible editor tabs")
	_tabs.tab_changed.connect(_on_tab_changed)
	add_child(_tabs)

	_atlas_tab = AtlasTabCls.new()
	_atlas_tab.name = "Atlas"
	_atlas_tab.announcer = announcer
	_atlas_tab.editor_interface = editor_interface
	_atlas_tab.editor_undo_redo = editor_undo_redo
	_tabs.add_child(_atlas_tab)

	_map_tab = MapTabCls.new()
	_map_tab.name = "Map"
	_map_tab.announcer = announcer
	_map_tab.editor_interface = editor_interface
	_map_tab.editor_undo_redo = editor_undo_redo
	_map_tab.atlas_tab = _atlas_tab
	_tabs.add_child(_map_tab)

	_spatial_tab = SpatialTabCls.new()
	_spatial_tab.name = "Spatial"
	_spatial_tab.announcer = announcer
	_spatial_tab.editor_interface = editor_interface
	_tabs.add_child(_spatial_tab)

func _on_tab_changed(idx: int) -> void:
	var tab := _tabs.get_tab_control(idx)
	if tab == null:
		return
	if tab.has_method(&"grab_entry_focus"):
		# tab.call_deferred(&"grab_entry_focus")
