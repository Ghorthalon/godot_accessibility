@tool
extends VBoxContainer

var plugin: EditorPlugin
var audio_debugger  # AudioPreviewDebugger instance, set by plugin.gd

# Shared state read/written by tabs
var cursor: Vector3 = Vector3.ZERO
var step: float = 1.0
var current_entity: SpatialEntity3D
var scene_query: SceneQuery

var use_selected_node: bool = false
var follow_selection: bool = false
var last_placed_node: Node3D
var corner_selector: CornerSelector  # shared selection, set by tab_cursor

signal cursor_jumped

var tab_rooms  # set in _ready exposes room actions to other tabs
var tab_place  # set in _ready exposes place actions to other tabs

var announce: Label

func _ready() -> void:
	name = "Rooms"

	announce = Label.new()
	announce.accessibility_live = 1  # ACCESSIBILITY_LIVE_POLITE
	add_child(announce)

	scene_query = SceneQuery.new()
	scene_query.plugin = plugin
	scene_query.dock = self
	add_child(scene_query)

	var toggle := CheckButton.new()
	toggle.text = "Use selected node as parent"
	toggle.tooltip_text = "When on, rooms and placed nodes are added as children of the currently selected node instead of the scene root."
	toggle.toggled.connect(func(on: bool) -> void:
		use_selected_node = on
		_say("Parent: %s." % ("selected node" if on else "scene root"))
	)
	add_child(toggle)

	var follow_toggle := CheckButton.new()
	follow_toggle.text = "Move cursor to selected object"
	follow_toggle.tooltip_text = "When on, the cursor jumps to any node you select in the viewport or scene tree."
	follow_toggle.toggled.connect(func(on: bool) -> void:
		follow_selection = on
		_say("Follow selection: %s." % ("on" if on else "off"))
	)
	add_child(follow_toggle)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	tab_rooms = preload("res://addons/accessible_rooms/tab_rooms.gd").new()
	tab_rooms.name = "Rooms"
	tab_rooms.dock = self
	tabs.add_child(tab_rooms)

	var tab_ramps = preload("res://addons/accessible_rooms/tab_ramps.gd").new()
	tab_ramps.name = "Ramps"
	tab_ramps.dock = self
	tabs.add_child(tab_ramps)

	var tab_cursor = preload("res://addons/accessible_rooms/tab_cursor.gd").new()
	tab_cursor.name = "Cursor"
	tab_cursor.dock = self
	tabs.add_child(tab_cursor)

	tab_place = preload("res://addons/accessible_rooms/tab_place.gd").new()
	tab_place.name = "Place"
	tab_place.dock = self
	tabs.add_child(tab_place)

	var tab_objects = preload("res://addons/accessible_rooms/tab_objects.gd").new()
	tab_objects.name = "Objects"
	tab_objects.dock = self
	tabs.add_child(tab_objects)

	var tab_scene = preload("res://addons/accessible_rooms/tab_scene.gd").new()
	tab_scene.name = "Scene"
	tab_scene.dock = self
	tabs.add_child(tab_scene)

func get_target_node() -> Node3D:
	var sel: Array = plugin.get_editor_interface().get_selection().get_selected_nodes()
	for n in sel:
		if n is Node3D: return n as Node3D
	if last_placed_node != null and is_instance_valid(last_placed_node):
		return last_placed_node
	_say("No node selected. Insert a node or select one first.")
	return null

func move_cursor_to(pos: Vector3) -> void:
	cursor = pos
	cursor_jumped.emit()

func _say(msg: String) -> void:
	announce.text = msg
