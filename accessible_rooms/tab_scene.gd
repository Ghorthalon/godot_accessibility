@tool
extends VBoxContainer

var dock

var _node_list: ItemList

func _ready() -> void:
	var lbl := Label.new()
	lbl.text = "3D nodes sorted by distance to cursor:"
	add_child(lbl)

	var btn_row := HBoxContainer.new()
	var btn := Button.new()
	btn.text = "Refresh"
	btn.pressed.connect(_refresh)
	btn_row.add_child(btn)
	add_child(btn_row)

	_node_list = ItemList.new()
	_node_list.custom_minimum_size = Vector2(0, 300)
	_node_list.item_selected.connect(_on_select)
	add_child(_node_list)

func _refresh() -> void:
	_node_list.clear()
	var root: Node = dock.scene_query.edited_root()
	if root == null:
		dock._say("No scene open.")
		return

	var nodes: Array[Node3D] = []
	_collect(root, root, nodes)

	var cursor: Vector3 = dock.cursor
	nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(cursor) < b.global_position.distance_to(cursor)
	)

	for n in nodes:
		_node_list.add_item(_label_for(n))
		_node_list.set_item_metadata(_node_list.item_count - 1, n)

	dock._say("Scene list refreshed: %d nodes." % nodes.size())

func _collect(node: Node, root: Node, out: Array[Node3D]) -> void:
	if node.has_meta("generated"): return
	if node != root and node is Node3D:
		out.append(node as Node3D)
	for child in node.get_children():
		_collect(child, root, out)

func _label_for(n: Node3D) -> String:
	var p := n.global_position
	var dist := p.distance_to(dock.cursor)
	var pos_str := "%.1f, %.1f, %.1f" % [p.x, p.y, p.z]

	var ancestors: Array[String] = []
	var cur: Node = n.get_parent()
	var root: Node = dock.scene_query.edited_root()
	while cur != null and cur != root:
		ancestors.push_front(cur.name)
		cur = cur.get_parent()

	var containing: SpatialEntity3D = dock.scene_query.entity_containing(p)

	var parts: Array[String] = []
	parts.append("%s: %s (%.1fm)" % [n.name, pos_str, dist])
	if ancestors.size() > 0:
		parts.append("child of %s" % " > ".join(ancestors))
	if containing != null:
		parts.append("in %s" % containing.name)
	return " - ".join(parts)

func _on_select(index: int) -> void:
	var node: Node = _node_list.get_item_metadata(index)
	if not is_instance_valid(node): return
	var sel: EditorSelection = dock.plugin.get_editor_interface().get_selection()
	sel.clear()
	sel.add_node(node)
	dock._say("Selected %s." % node.name)
