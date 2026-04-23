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

var _floor_offset: SpinBox
var _wall_offset: SpinBox
var _door_inset: SpinBox

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
	zone_corner_a_label = Label.new(); zone_corner_a_label.text = "A: "
	zone_corner_b_label = Label.new(); zone_corner_b_label.text = "B: "
	corner_labels_row.add_child(zone_corner_a_label)
	corner_labels_row.add_child(zone_corner_b_label)
	add_child(corner_labels_row)

	_btn("Add zone to current room floor", _add_floor_zone)
	_btn("Clear all zones from current room floor", _clear_floor_zones)

	add_child(HSeparator.new())
	var snap_lbl := Label.new(); snap_lbl.text = "Snap selected node:"
	add_child(snap_lbl)

	var floor_row := HBoxContainer.new()
	var floor_lbl := Label.new(); floor_lbl.text = "Floor offset (m):"
	_floor_offset = SpinBox.new()
	_floor_offset.min_value = -10.0; _floor_offset.max_value = 10.0
	_floor_offset.step = 0.05; _floor_offset.value = 0.0
	var floor_btn := Button.new(); floor_btn.text = "Nudge to floor"
	floor_btn.pressed.connect(_nudge_to_floor)
	floor_row.add_child(floor_lbl); floor_row.add_child(_floor_offset); floor_row.add_child(floor_btn)
	add_child(floor_row)

	var wall_row := HBoxContainer.new()
	var wall_lbl := Label.new(); wall_lbl.text = "Wall offset (m):"
	_wall_offset = SpinBox.new()
	_wall_offset.min_value = 0.0; _wall_offset.max_value = 5.0
	_wall_offset.step = 0.05; _wall_offset.value = 0.0
	var wall_btn := Button.new(); wall_btn.text = "Snap to nearest wall"
	wall_btn.pressed.connect(_snap_to_nearest_wall)
	wall_row.add_child(wall_lbl); wall_row.add_child(_wall_offset); wall_row.add_child(wall_btn)
	add_child(wall_row)

	var center_row := HBoxContainer.new()
	var cew_btn := Button.new(); cew_btn.text = "Center E\u2194W"
	cew_btn.pressed.connect(_center_east_west)
	var cns_btn := Button.new(); cns_btn.text = "Center N\u2194S"
	cns_btn.pressed.connect(_center_north_south)
	center_row.add_child(cew_btn); center_row.add_child(cns_btn)
	add_child(center_row)

	var door_row := HBoxContainer.new()
	var door_lbl := Label.new(); door_lbl.text = "Door inset (m):"
	_door_inset = SpinBox.new()
	_door_inset.min_value = 0.0; _door_inset.max_value = 2.0
	_door_inset.step = 0.05; _door_inset.value = 0.05
	var door_btn := Button.new(); door_btn.text = "Snap to nearest doorway"
	door_btn.pressed.connect(_snap_to_nearest_doorway)
	door_row.add_child(door_lbl); door_row.add_child(_door_inset); door_row.add_child(door_btn)
	add_child(door_row)

	_btn("Measure space at node", _measure_space)

# --- Node placement ---

func _insert_node_at_cursor() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var type_name: String = node_type_option.get_item_text(node_type_option.selected)
	var obj: Object = ClassDB.instantiate(type_name)
	if obj == null: dock._say("Could not create %s." % type_name); return
	var n := obj as Node
	n.name = "%s%d" % [type_name, root.get_child_count() + 1]
	if n is Node3D:
		(n as Node3D).position = dock.cursor
	root.add_child(n); n.owner = root
	dock.last_placed_node = n as Node3D
	dock._say("Inserted %s at %.1f %.1f %.1f." % [n.name, dock.cursor.x, dock.cursor.y, dock.cursor.z])

func _insert_scene_at_cursor() -> void:
	var path := scene_path_edit.text.strip_edges()
	if path.is_empty(): dock._say("Enter a scene path first."); return
	if not ResourceLoader.exists(path): dock._say("Scene not found: %s" % path); return
	var packed := load(path) as PackedScene
	if packed == null: dock._say("Failed to load scene."); return
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var instance := packed.instantiate()
	if instance is Node3D:
		(instance as Node3D).position = dock.cursor
	root.add_child(instance); instance.owner = root
	if instance is Node3D: dock.last_placed_node = instance as Node3D
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
	if dock.current_entity == null: dock._say("No current room selected."); return
	var ax: float = zone_corner_a.x - (dock.current_entity as Room3D).position.x
	var az: float = zone_corner_a.z - (dock.current_entity as Room3D).position.z
	var bx: float = zone_corner_b.x - (dock.current_entity as Room3D).position.x
	var bz: float = zone_corner_b.z - (dock.current_entity as Room3D).position.z
	var rect := Rect2(minf(ax, bx), minf(az, bz), absf(bx - ax), absf(bz - az))
	if rect.size.x < 0.01 or rect.size.y < 0.01:
		dock._say("Zone too small, move cursor between corners first."); return
	var surface := zone_surface_edit.text.strip_edges()
	if surface.is_empty(): dock._say("Enter a surface name first."); return
	var floor_cfg: Dictionary = dock.current_entity.walls["floor"]
	if not floor_cfg.has("zones"):
		floor_cfg["zones"] = []
	floor_cfg["zones"].append({"rect": rect, "surface": surface})
	dock.current_entity.walls["floor"] = floor_cfg
	dock.current_entity.rebuild()
	dock._say("Added %s zone (%.1f x %.1f m) to floor of %s." % \
		[surface, rect.size.x, rect.size.y, dock.current_entity.name])

func _clear_floor_zones() -> void:
	if dock.current_entity == null: dock._say("No current room selected."); return
	var floor_cfg: Dictionary = dock.current_entity.walls["floor"]
	floor_cfg["zones"] = []
	dock.current_entity.walls["floor"] = floor_cfg
	dock.current_entity.rebuild()
	dock._say("Cleared all floor zones from %s." % dock.current_entity.name)

# --- Snap helpers ---

func _nudge_to_floor() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var floor_y = dock.scene_query.raycast_down(n.global_position)
	if floor_y == null: dock._say("No floor found below node."); return
	n.global_position.y = floor_y + _floor_offset.value
	dock._say("Nudged %s to floor (y=%.2f)." % [n.name, n.global_position.y])

func _snap_to_nearest_wall() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var dirs := {"north": Vector3.FORWARD, "south": Vector3.BACK,
				 "east": Vector3.RIGHT, "west": Vector3.LEFT}
	var best_hit: Vector3
	var best_dir: Vector3
	var best_side := ""
	var best_dist := INF
	for side in dirs:
		var hit = dock.scene_query.raycast_direction(n.global_position, dirs[side])
		if hit == null: continue
		var d: float = n.global_position.distance_to(hit)
		if d < best_dist:
			best_dist = d; best_hit = hit; best_dir = dirs[side]; best_side = side
	if best_side == "":
		dock._say("No wall found in any direction."); return
	n.global_position = best_hit - best_dir * _wall_offset.value
	dock._say("Snapped %s to %s wall (%.1fm away)." % [n.name, best_side, best_dist])

func _center_east_west() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var gap: Dictionary = dock.scene_query.wall_gap(n.global_position, Vector3.RIGHT)
	if gap.is_empty(): dock._say("Could not find walls on both east and west sides."); return
	n.global_position.x = (gap["midpoint"] as Vector3).x
	dock._say("Centered %s east-west (gap %.1fm)." % [n.name, gap["gap"]])

func _center_north_south() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var gap: Dictionary = dock.scene_query.wall_gap(n.global_position, Vector3.BACK)
	if gap.is_empty(): dock._say("Could not find walls on both north and south sides."); return
	n.global_position.z = (gap["midpoint"] as Vector3).z
	dock._say("Centered %s north-south (gap %.1fm)." % [n.name, gap["gap"]])

func _snap_to_nearest_doorway() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var info: Dictionary = dock.scene_query.nearest_doorway(n.global_position)
	if info.is_empty(): dock._say("No doorway found nearby. Is the cursor inside a room?"); return
	var wpos: Vector3 = info["world_pos"]
	# Offset inward from wall face so node sits inside the opening.
	var inward_normals := {"north": Vector3.BACK, "south": Vector3.FORWARD,
						   "east": Vector3.LEFT, "west": Vector3.RIGHT}
	var inward: Vector3 = inward_normals.get(info["side"], Vector3.ZERO)
	n.global_position = wpos + inward * _door_inset.value
	dock._say("Snapped %s to %s doorway (%.1fm × %.1fm)." % [n.name, info["side"], info["width"], info["height"]])

func _measure_space() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var space: Dictionary = dock.scene_query.measure_space(n.global_position)
	dock._say("Space around %s: north %.1fm, south %.1fm, east %.1fm, west %.1fm, up %.1fm, down %.1fm." % \
		[n.name, space["north"], space["south"], space["east"], space["west"], space["up"], space["down"]])

# --- Helpers ---

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
