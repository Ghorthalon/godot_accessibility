@tool
extends VBoxContainer

var announcer: AccessibleAnnouncer
var editor_interface: EditorInterface

# UI
var _mode_option: OptionButton
var _sort_option: OptionButton
var _filter_field: LineEdit
var _class_filter_option: OptionButton
var _refresh_button: Button
var _list: ItemList
var _status: RichTextLabel
var _cone_spin: SpinBox

# State
var _all_nodes: Array[Node] = []
var _filtered_nodes: Array[Node] = []
var _mode: int = 0  # 0=list, 1=spatial

enum SortMode { X, Y, NAME, TYPE }
enum ModeKind { LIST, SPATIAL }


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()


func grab_entry_focus() -> void:
	_refresh_nodes()
	if _list != null:
		_list.grab_focus()


# ----- UI -----

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	# Mode
	_make_label(self, "Mode:")
	_mode_option = OptionButton.new()
	_mode_option.add_item("List (flat, sortable)")
	_mode_option.add_item("Spatial (directional jump)")
	_set_a11y(_mode_option, "Exploration mode",
		"Switch between flat list navigation and directional spatial jumping.")
	_mode_option.item_selected.connect(func(i: int): _mode = i; _refresh_nodes())
	add_child(_mode_option)

	# Sort
	_make_label(self, "Sort (list mode):")
	_sort_option = OptionButton.new()
	_sort_option.add_item("by X position")
	_sort_option.add_item("by Y position")
	_sort_option.add_item("by name")
	_sort_option.add_item("by type")
	_set_a11y(_sort_option, "Sort order",
		"How the flat list is sorted.")
	_sort_option.item_selected.connect(func(_i: int): _refresh_nodes())
	add_child(_sort_option)

	# Class filter
	_make_label(self, "Class filter:")
	_class_filter_option = OptionButton.new()
	_class_filter_option.add_item("All types")
	_class_filter_option.add_item("Node2D and subclasses")
	_class_filter_option.add_item("Control and subclasses")
	_class_filter_option.add_item("Area2D")
	_class_filter_option.add_item("CharacterBody2D")
	_class_filter_option.add_item("StaticBody2D")
	_class_filter_option.add_item("Sprite2D")
	_class_filter_option.add_item("TileMapLayer")
	_set_a11y(_class_filter_option, "Class filter",
		"Only show nodes of a specific class.")
	_class_filter_option.item_selected.connect(func(_i: int): _refresh_nodes())
	add_child(_class_filter_option)

	# Name filter
	_make_label(self, "Name / class substring filter:")
	_filter_field = LineEdit.new()
	_filter_field.placeholder_text = "(leave blank to show all)"
	_set_a11y(_filter_field, "Name filter",
		"Case-insensitive substring match on node name or class. Press Enter to apply.")
	_filter_field.text_submitted.connect(func(_t: String): _refresh_nodes())
	add_child(_filter_field)

	# Cone angle (spatial mode)
	var cone_row := HBoxContainer.new()
	add_child(cone_row)
	_make_label(cone_row, "Directional cone (degrees, spatial mode):")
	_cone_spin = SpinBox.new()
	_cone_spin.min_value = 15
	_cone_spin.max_value = 90
	_cone_spin.value = 60
	_set_a11y(_cone_spin, "Directional cone",
		"Half-angle in degrees for the directional jump cone.")
	cone_row.add_child(_cone_spin)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh node list"
	_set_a11y(_refresh_button, "Refresh", "Re-scan the edited scene.")
	_refresh_button.pressed.connect(_refresh_nodes)
	add_child(_refresh_button)

	# The list
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 200)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_set_a11y(_list, "Node list",
		"Arrow keys to navigate. Enter to select in the editor. Use arrow keys + Ctrl in spatial mode to jump directionally.")
	_list.item_selected.connect(_on_list_item_selected)
	_list.item_activated.connect(_on_list_item_activated)
	_list.gui_input.connect(_on_list_gui_input)
	add_child(_list)

	_status = RichTextLabel.new()
	_status.custom_minimum_size = Vector2(0, 60)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.bbcode_enabled = false
	_status.fit_content = true
	_status.selection_enabled = true
	_set_a11y(_status, "Node detail", "Detailed info on the selected node.")
	add_child(_status)


# ----- Refreshing -----

func _refresh_nodes() -> void:
	_list.clear()
	_all_nodes.clear()
	_filtered_nodes.clear()

	if editor_interface == null:
		announcer.speak("No editor interface.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		_status.text = "No scene open."
		return
	_collect_all(root)

	var filter_text := _filter_field.text.strip_edges().to_lower()
	var class_filter := _class_filter_option.selected
	for n in _all_nodes:
		if not _passes_class_filter(n, class_filter):
			continue
		if not filter_text.is_empty():
			var name_lc := String(n.name).to_lower()
			var class_lc := n.get_class().to_lower()
			if not (filter_text in name_lc or filter_text in class_lc):
				continue
		_filtered_nodes.append(n)

	# Sort
	if _mode == ModeKind.LIST:
		_filtered_nodes.sort_custom(_comparator_for_sort(_sort_option.selected))
	else:
		# Spatial mode: sort by y then x for a stable initial order.
		_filtered_nodes.sort_custom(func(a: Node, b: Node) -> bool:
			var pa := _pos_of(a)
			var pb := _pos_of(b)
			if pa.y == pb.y:
				return pa.x < pb.x
			return pa.y < pb.y
		)

	for n in _filtered_nodes:
		_list.add_item(_list_label(n))

	_status.text = "%d nodes (of %d total in scene)." % [
		_filtered_nodes.size(), _all_nodes.size()
	]
	announcer.speak("Found %d nodes." % _filtered_nodes.size())


func _collect_all(node: Node) -> void:
	_all_nodes.append(node)
	for c in node.get_children():
		_collect_all(c)


func _passes_class_filter(n: Node, class_idx: int) -> bool:
	match class_idx:
		0: return true
		1: return n is Node2D
		2: return n is Control
		3: return n is Area2D
		4: return n is CharacterBody2D
		5: return n is StaticBody2D
		6: return n is Sprite2D
		7: return n is TileMapLayer
	return true


func _comparator_for_sort(sort: int) -> Callable:
	match sort:
		SortMode.X:
			return func(a: Node, b: Node) -> bool:
				return _pos_of(a).x < _pos_of(b).x
		SortMode.Y:
			return func(a: Node, b: Node) -> bool:
				return _pos_of(a).y < _pos_of(b).y
		SortMode.TYPE:
			return func(a: Node, b: Node) -> bool:
				if a.get_class() == b.get_class():
					return String(a.name) < String(b.name)
				return a.get_class() < b.get_class()
		_: # NAME
			return func(a: Node, b: Node) -> bool:
				return String(a.name) < String(b.name)


func _pos_of(n: Node) -> Vector2:
	if n is Node2D:
		return (n as Node2D).global_position
	if n is Control:
		return (n as Control).global_position
	return Vector2.ZERO


func _list_label(n: Node) -> String:
	var pos := _pos_of(n)
	return "%s  [%s]  (%.0f, %.0f)" % [n.name, n.get_class(), pos.x, pos.y]


# ----- Selection / activation -----

func _on_list_item_selected(idx: int) -> void:
	if idx < 0 or idx >= _filtered_nodes.size():
		return
	var n := _filtered_nodes[idx]
	var pos := _pos_of(n)
	var extra: Array[String] = []
	if not (n is Node2D or n is Control):
		extra.append("not positioned")
	var parent_path := String(n.get_parent().get_path()) if n.get_parent() != null else ""
	_status.text = "Name: %s\nClass: %s\nPosition: (%.1f, %.1f)\nParent: %s\nChildren: %d%s" % [
		n.name, n.get_class(), pos.x, pos.y, parent_path, n.get_child_count(),
		("\n" + "\n".join(extra)) if extra.size() > 0 else ""
	]
	announcer.speak("%s, %s, at %.0f, %.0f." % [n.name, n.get_class(), pos.x, pos.y])


func _on_list_item_activated(idx: int) -> void:
	# Enter pressed: select the node in the editor's Scene dock.
	if idx < 0 or idx >= _filtered_nodes.size():
		return
	var n := _filtered_nodes[idx]
	if editor_interface != null:
		var sel := editor_interface.get_selection()
		sel.clear()
		sel.add_node(n)
		editor_interface.edit_node(n)
		announcer.speak("Selected %s in editor." % n.name, AccessibleAnnouncer.Priority.ASSERTIVE)


func _on_list_gui_input(event: InputEvent) -> void:
	if _mode != ModeKind.SPATIAL:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ke := event as InputEventKey
	if not (ke.ctrl_pressed or ke.meta_pressed):
		return
	var dir := Vector2.ZERO
	match ke.keycode:
		KEY_LEFT: dir = Vector2.LEFT
		KEY_RIGHT: dir = Vector2.RIGHT
		KEY_UP: dir = Vector2.UP
		KEY_DOWN: dir = Vector2.DOWN
		_: return
	_list.accept_event()
	_jump_directional(dir)


# ----- Directional jump (spatial mode) -----

func _jump_directional(dir: Vector2) -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		if _filtered_nodes.size() > 0:
			_list.select(0)
			_on_list_item_selected(0)
		return
	var from_idx: int = sel[0]
	var from_node := _filtered_nodes[from_idx]
	var from_pos := _pos_of(from_node)

	var cone_deg: float = _cone_spin.value
	var cone_rad := deg_to_rad(cone_deg)

	var best_idx := -1
	var best_dist := INF
	for i in _filtered_nodes.size():
		if i == from_idx:
			continue
		var n := _filtered_nodes[i]
		var p := _pos_of(n)
		var offset := p - from_pos
		if offset.length() < 0.001:
			continue
		# Angle between offset and direction.
		var ang := absf(offset.normalized().angle_to(dir))
		if ang > cone_rad:
			continue
		if offset.length() < best_dist:
			best_dist = offset.length()
			best_idx = i

	if best_idx < 0:
		announcer.speak("No node in that direction.",
			AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	_list.select(best_idx)
	_list.ensure_current_is_visible()
	_on_list_item_selected(best_idx)


# ----- Helpers -----

func _make_label(parent: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _set_a11y(c: Control, name: String, desc: String = "") -> void:
	if c.has_method(&"set_accessibility_name"):
		c.call(&"set_accessibility_name", name)
	if not desc.is_empty() and c.has_method(&"set_accessibility_description"):
		c.call(&"set_accessibility_description", desc)
