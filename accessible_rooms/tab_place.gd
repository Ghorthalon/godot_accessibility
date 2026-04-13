@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var node_type_option: OptionButton
var scene_path_edit: LineEdit
var zone_surface_edit: LineEdit
var zone_corner_a: Vector3 = Vector3.ZERO
var zone_corner_b: Vector3 = Vector3.ZERO
var zone_corner_a_label: Label
var zone_corner_b_label: Label

func _ready() -> void:
	var pn_lbl := Label.new(); pn_lbl.text = "Place node at cursor:"
	add_child(pn_lbl)
	node_type_option = OptionButton.new()
	for t in ["Marker3D", "AudioStreamPlayer3D", "OmniLight3D", "SpotLight3D",
			  "GPUParticles3D", "Node3D"]:
		node_type_option.add_item(t)
	var pn_row := HBoxContainer.new()
	pn_row.add_child(node_type_option)
	var insert_btn := Button.new()
	insert_btn.text = "Insert"
	insert_btn.pressed.connect(_insert_node_at_cursor)
	pn_row.add_child(insert_btn)
	add_child(pn_row)

	var sc_lbl := Label.new(); sc_lbl.text = "Or insert scene (.tscn path):"
	add_child(sc_lbl)
	var sc_row := HBoxContainer.new()
	scene_path_edit = LineEdit.new()
	scene_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_path_edit.placeholder_text = "res://path/to/scene.tscn"
	sc_row.add_child(scene_path_edit)
	var insert_scene_btn := Button.new()
	insert_scene_btn.text = "Insert Scene"
	insert_scene_btn.pressed.connect(_insert_scene_at_cursor)
	sc_row.add_child(insert_scene_btn)
	add_child(sc_row)

	add_child(HSeparator.new())
	var fz_lbl := Label.new(); fz_lbl.text = "Floor zones:"
	add_child(fz_lbl)

	var surf_row := HBoxContainer.new()
	var surf_lbl := Label.new(); surf_lbl.text = "Surface:"
	zone_surface_edit = LineEdit.new()
	zone_surface_edit.placeholder_text = "grass, dirt, stone..."
	zone_surface_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surf_row.add_child(surf_lbl); surf_row.add_child(zone_surface_edit)
	add_child(surf_row)

	var corner_row := HBoxContainer.new()
	var ca_btn := Button.new(); ca_btn.text = "Set corner A (cursor)"
	ca_btn.pressed.connect(_set_zone_corner_a)
	var cb_btn := Button.new(); cb_btn.text = "Set corner B (cursor)"
	cb_btn.pressed.connect(_set_zone_corner_b)
	corner_row.add_child(ca_btn); corner_row.add_child(cb_btn)
	add_child(corner_row)

	var corner_labels_row := HBoxContainer.new()
	zone_corner_a_label = Label.new(); zone_corner_a_label.text = "A: —"
	zone_corner_b_label = Label.new(); zone_corner_b_label.text = "B: —"
	corner_labels_row.add_child(zone_corner_a_label)
	corner_labels_row.add_child(zone_corner_b_label)
	add_child(corner_labels_row)

	_btn("Add zone to current room floor", _add_floor_zone)
	_btn("Clear all zones from current room floor", _clear_floor_zones)

# --- Node placement ---

func _insert_node_at_cursor() -> void:
	var root: Node = dock.scene_query.edited_root()
	if root == null: dock._say("No scene open."); return
	var type_name: String = node_type_option.get_item_text(node_type_option.selected)
	var obj: Object = ClassDB.instantiate(type_name)
	if obj == null: dock._say("Could not create %s." % type_name); return
	var n := obj as Node
	n.name = "%s%d" % [type_name, root.get_child_count() + 1]
	if n is Node3D:
		(n as Node3D).position = dock.cursor
	root.add_child(n); n.owner = root
	dock._say("Inserted %s at %.1f %.1f %.1f." % [n.name, dock.cursor.x, dock.cursor.y, dock.cursor.z])

func _insert_scene_at_cursor() -> void:
	var path := scene_path_edit.text.strip_edges()
	if path.is_empty(): dock._say("Enter a scene path first."); return
	if not ResourceLoader.exists(path): dock._say("Scene not found: %s" % path); return
	var packed := load(path) as PackedScene
	if packed == null: dock._say("Failed to load scene."); return
	var root: Node = dock.scene_query.edited_root()
	if root == null: dock._say("No scene open."); return
	var instance := packed.instantiate()
	if instance is Node3D:
		(instance as Node3D).position = dock.cursor
	root.add_child(instance); instance.owner = root
	dock._say("Inserted %s at %.1f %.1f %.1f." % [instance.name, dock.cursor.x, dock.cursor.y, dock.cursor.z])

# --- Floor zones ---

func _set_zone_corner_a() -> void:
	zone_corner_a = dock.cursor
	zone_corner_a_label.text = "A: %.1f, %.1f" % [dock.cursor.x, dock.cursor.z]
	dock._say("Zone corner A set at %.1f, %.1f." % [dock.cursor.x, dock.cursor.z])

func _set_zone_corner_b() -> void:
	zone_corner_b = dock.cursor
	zone_corner_b_label.text = "B: %.1f, %.1f" % [dock.cursor.x, dock.cursor.z]
	dock._say("Zone corner B set at %.1f, %.1f." % [dock.cursor.x, dock.cursor.z])

func _add_floor_zone() -> void:
	if dock.current_room == null: dock._say("No current room selected."); return
	var ax: float = zone_corner_a.x - (dock.current_room as Room3D).position.x
	var az: float = zone_corner_a.z - (dock.current_room as Room3D).position.z
	var bx: float = zone_corner_b.x - (dock.current_room as Room3D).position.x
	var bz: float = zone_corner_b.z - (dock.current_room as Room3D).position.z
	var rect := Rect2(minf(ax, bx), minf(az, bz), absf(bx - ax), absf(bz - az))
	if rect.size.x < 0.01 or rect.size.y < 0.01:
		dock._say("Zone too small — move cursor between corners first."); return
	var surface := zone_surface_edit.text.strip_edges()
	if surface.is_empty(): dock._say("Enter a surface name first."); return
	var floor_cfg: Dictionary = dock.current_room.walls["floor"]
	if not floor_cfg.has("zones"):
		floor_cfg["zones"] = []
	floor_cfg["zones"].append({"rect": rect, "surface": surface})
	dock.current_room.walls["floor"] = floor_cfg
	dock.current_room.rebuild()
	dock._say("Added %s zone (%.1f x %.1f m) to floor of %s." % \
		[surface, rect.size.x, rect.size.y, dock.current_room.name])

func _clear_floor_zones() -> void:
	if dock.current_room == null: dock._say("No current room selected."); return
	var floor_cfg: Dictionary = dock.current_room.walls["floor"]
	floor_cfg["zones"] = []
	dock.current_room.walls["floor"] = floor_cfg
	dock.current_room.rebuild()
	dock._say("Cleared all floor zones from %s." % dock.current_room.name)

# --- Helpers ---

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
