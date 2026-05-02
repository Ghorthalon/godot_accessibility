@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var node_type_option: OptionButton
var scene_path_edit: LineEdit
var zone_surface_edit: LineEdit

var _floor_offset: SpinBox
var _wall_offset: SpinBox
var _door_inset: SpinBox

var _phys_width: SpinBox
var _phys_height: SpinBox
var _phys_depth: SpinBox

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
	var po_lbl := Label.new(); po_lbl.text = "Insert physical object:"
	add_child(po_lbl)
	var po_row := HBoxContainer.new()
	var pw_lbl := Label.new(); pw_lbl.text = "W:"
	_phys_width = SpinBox.new()
	_phys_width.min_value = 0.1; _phys_width.max_value = 20.0
	_phys_width.step = 0.1; _phys_width.value = 1.0
	var ph_lbl := Label.new(); ph_lbl.text = "H:"
	_phys_height = SpinBox.new()
	_phys_height.min_value = 0.1; _phys_height.max_value = 20.0
	_phys_height.step = 0.1; _phys_height.value = 1.0
	var pd_lbl := Label.new(); pd_lbl.text = "D:"
	_phys_depth = SpinBox.new()
	_phys_depth.min_value = 0.1; _phys_depth.max_value = 20.0
	_phys_depth.step = 0.1; _phys_depth.value = 1.0
	po_row.add_child(pw_lbl); po_row.add_child(_phys_width)
	po_row.add_child(ph_lbl); po_row.add_child(_phys_height)
	po_row.add_child(pd_lbl); po_row.add_child(_phys_depth)
	add_child(po_row)
	_btn("Create physical object at cursor", _insert_physical_object)
	_btn("Create from selection (corner A/B)", _insert_physical_object_from_selection)

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

func _add_floor_zone() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var world_rect: Rect2 = dock.corner_selector.get_rect2_xz()
	var rect := Rect2(world_rect.position - Vector2(room.position.x, room.position.z), world_rect.size)
	if rect.size.x < 0.01 or rect.size.y < 0.01:
		dock._say("Zone too small, move cursor between corners first."); return
	var surface := zone_surface_edit.text.strip_edges()
	if surface.is_empty(): dock._say("Enter a surface name first."); return
	room.cfg("floor").zones.append({"rect": rect, "surface": surface})
	room._queue_rebuild()
	dock._say("Added %s zone (%.1f x %.1f m) to floor of %s." % \
		[surface, rect.size.x, rect.size.y, room.name])

func _clear_floor_zones() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	room.cfg("floor").zones.clear()
	room._queue_rebuild()
	dock._say("Cleared all floor zones from %s." % room.name)

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

# --- Physical object insertion ---

func _insert_physical_object() -> void:
	var parent: Node = dock.scene_query.placement_parent()
	if parent == null: dock._say("No scene open."); return
	var size := Vector3(_phys_width.value, _phys_height.value, _phys_depth.value)
	var reason := _fit_check(dock.cursor, size)
	if reason != "":
		dock._say("Object (%.1f x %.1f x %.1f m) does not fit: %s." % [size.x, size.y, size.z, reason]); return
	_create_physical_object(parent, dock.scene_query.edited_root(), dock.cursor, size)

func _insert_physical_object_from_selection() -> void:
	var parent: Node = dock.scene_query.placement_parent()
	if parent == null: dock._say("No scene open."); return
	var aabb: AABB = dock.corner_selector.get_aabb()
	if aabb.size.x < 0.05 or aabb.size.y < 0.05 or aabb.size.z < 0.05:
		dock._say("Selection too small — set corner A and B first."); return
	var pos := Vector3(aabb.position.x + aabb.size.x / 2.0, aabb.position.y, aabb.position.z + aabb.size.z / 2.0)
	var reason := _fit_check(pos, aabb.size)
	if reason != "":
		dock._say("Object (%.1f x %.1f x %.1f m) does not fit: %s." % [aabb.size.x, aabb.size.y, aabb.size.z, reason]); return
	_create_physical_object(parent, dock.scene_query.edited_root(), pos, aabb.size)

func _fit_check(pos: Vector3, size: Vector3) -> String:
	var space: Dictionary = dock.scene_query.measure_space(pos)
	if space["east"] < size.x / 2.0 or space["west"] < size.x / 2.0:
		return "not enough east-west space (need %.1fm, have %.1f/%.1fm)" % [size.x, space["west"], space["east"]]
	if space["north"] < size.z / 2.0 or space["south"] < size.z / 2.0:
		return "not enough north-south space (need %.1fm, have %.1f/%.1fm)" % [size.z, space["north"], space["south"]]
	if space["up"] < size.y:
		return "not enough height (need %.1fm, have %.1fm)" % [size.y, space["up"]]
	return ""

func _create_physical_object(parent: Node, owner_node: Node, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "PhysicalObject%d" % (parent.get_child_count() + 1)
	body.position = pos
	var cs := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	cs.shape = box_shape
	cs.position = Vector3(0.0, size.y / 2.0, 0.0)
	var mi := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mi.mesh = box_mesh
	mi.position = Vector3(0.0, size.y / 2.0, 0.0)
	body.add_child(cs); body.add_child(mi)
	parent.add_child(body)
	body.owner = owner_node; cs.owner = owner_node; mi.owner = owner_node
	dock.last_placed_node = body
	dock._say("Created %.1f x %.1f x %.1f m physical object at %.1f %.1f %.1f." % \
		[size.x, size.y, size.z, pos.x, pos.y, pos.z])
