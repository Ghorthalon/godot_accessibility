@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var node_type_option: OptionButton
var scene_path_edit: LineEdit
var zone_surface_edit: LineEdit

var _floor_offset: SpinBox
var _wall_offset: SpinBox
var _door_inset: SpinBox

var _body_type_option: OptionButton
var _phys_width: SpinBox
var _phys_height: SpinBox
var _phys_depth: SpinBox

var auto_parent_to_room: bool = false

var confirm: ConfirmBar

func _ready() -> void:
	var room_toggle := CheckButton.new()
	room_toggle.text = "Place inside containing room"
	room_toggle.tooltip_text = "When on, objects placed at the cursor become children of the room (or other SpatialEntity3D) that contains the cursor. Falls back to the normal placement parent when the cursor isn't inside any room."
	room_toggle.toggled.connect(func(on: bool) -> void:
		auto_parent_to_room = on
		dock._say("Auto-parent to containing room: %s." % ("on" if on else "off"))
	)
	add_child(room_toggle)

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
	_btn("Insert scene at nearest doorway", _insert_scene_at_nearest_doorway)
	_btn("Insert scene aligned to nearest wall", _insert_scene_aligned_to_wall)

	confirm = ConfirmBar.new()
	confirm.dock = dock
	add_child(confirm)

	add_child(HSeparator.new())
	var po_lbl := Label.new(); po_lbl.text = "Insert sized body / area:"
	add_child(po_lbl)
	var bt_row := HBoxContainer.new()
	var bt_lbl := Label.new(); bt_lbl.text = "Type:"
	_body_type_option = OptionButton.new()
	for t in ["StaticBody3D", "Area3D", "RigidBody3D", "CharacterBody3D"]:
		_body_type_option.add_item(t)
	bt_row.add_child(bt_lbl); bt_row.add_child(_body_type_option)
	add_child(bt_row)
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
	_btn("Create at cursor", _insert_physical_object)
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

## Returns the room containing pos when "Place inside containing room" is on
## and such a room exists, otherwise falls back to scene_query.placement_parent().
func _resolve_parent_for(pos: Vector3) -> Node:
	if auto_parent_to_room:
		var room := dock.scene_query.innermost_entity_containing(pos) as SpatialEntity3D
		if room != null:
			return room
	return dock.scene_query.placement_parent()

func _insert_node_at_cursor() -> void:
	var parent: Node = _resolve_parent_for(dock.cursor)
	if parent == null: dock._say("No scene open."); return
	var owner_node: Node = dock.scene_query.edited_root()
	var type_name: String = node_type_option.get_item_text(node_type_option.selected)
	var obj: Object = ClassDB.instantiate(type_name)
	if obj == null: dock._say("Could not create %s." % type_name); return
	var n := obj as Node
	n.name = "%s%d" % [type_name, parent.get_child_count() + 1]
	dock.ops.add_node(parent, n, "Insert %s" % n.name, dock.cursor if n is Node3D else null)
	dock.last_placed_node = n as Node3D
	dock._say_ok("Inserted %s at %.1f %.1f %.1f. Press Control Z to undo." % [n.name, dock.cursor.x, dock.cursor.y, dock.cursor.z])

func _insert_scene_at_cursor() -> void:
	var packed := _load_scene_from_path()
	if packed == null: return
	var parent: Node = _resolve_parent_for(dock.cursor)
	if parent == null: dock._say("No scene open."); return
	var tf := Transform3D(Basis(), dock.cursor)
	instantiate_aligned(packed, tf, parent, "%.1f %.1f %.1f" % [dock.cursor.x, dock.cursor.y, dock.cursor.z])

## Loads the PackedScene named in scene_path_edit, or returns null and tells you why.
func _load_scene_from_path() -> PackedScene:
	var path := scene_path_edit.text.strip_edges()
	if path.is_empty(): dock._say("Enter a scene path first."); return null
	if not ResourceLoader.exists(path): dock._say("Scene not found: %s" % path); return null
	var packed := load(path) as PackedScene
	if packed == null: dock._say("Failed to load scene.")
	return packed

func _insert_scene_at_nearest_doorway() -> void:
	var packed := _load_scene_from_path()
	if packed == null: return
	var info: Dictionary = dock.scene_query.nearest_doorway(dock.cursor)
	if info.is_empty(): dock._say("No doorway found nearby. Move the cursor inside a room with a doorway."); return
	var room: Room3D = info["room"]
	var tf: Transform3D = dock.scene_query.wall_facing_transform(
		room, info["side"], info["cu"], info["cv"])
	instantiate_aligned(packed, tf, room,
		"%s doorway of %s (%.1fm × %.1fm)" % [info["side"], room.name, info["width"], info["height"]])

func _insert_scene_aligned_to_wall() -> void:
	var packed := _load_scene_from_path()
	if packed == null: return
	var room := dock.scene_query.innermost_entity_containing(dock.cursor) as Room3D
	if room == null: dock._say("Cursor is not inside a room."); return
	var side: String = dock.scene_query.nearest_wall_side(room, dock.cursor)
	var uv: Vector2 = dock.scene_query.wall_uv_from_world(room, side, dock.cursor)
	var tf: Transform3D = dock.scene_query.wall_facing_transform(room, side, uv.x, uv.y)
	instantiate_aligned(packed, tf, room, "%s wall of %s" % [side, room.name])

## Instantiates packed under parent at tf, with these collision behaviors:
##   - no collision: place normally.
##   - colliding, a clear spot found nearby: offer that spot on the confirm bar.
##   - colliding, nothing clear within 5m: offer to place anyway, in place.
## Nothing is ever inserted without either a clear spot or an explicit Proceed.
## Probes collision on an un-parented instance, then re-instantiates fresh
## on commit, so a refused/cancelled scene never appears in the tree.
func instantiate_aligned(packed: PackedScene, tf: Transform3D, parent: Node, where: String) -> void:
	var owner_node: Node = dock.scene_query.edited_root()
	var probe := packed.instantiate()
	if not probe is Node3D:
		# No spatial root, so there is nothing to collision-check or orient.
		dock.ops.add_node(parent, probe, "Insert %s" % probe.name)
		dock._say_ok("Inserted %s at %s (no Node3D root, transform skipped). Press Control Z to undo." % [probe.name, where])
		return
	var n3d := probe as Node3D
	n3d.transform.basis = tf.basis  # orient probe shape before the collision query
	var result: Dictionary = dock.scene_query.check_placement(n3d, tf.origin)
	var collides: bool = result.get("collides", false)
	if not collides:
		probe.queue_free()
		_commit_place(packed, tf, parent, owner_node, where)
		return
	var suggested = dock.scene_query.find_fit_position(n3d, tf.origin, 5.0)
	probe.queue_free()
	var name_part: String = packed.resource_path.get_file() if packed.resource_path != "" else "scene"
	if suggested == null:
		confirm.ask("%s would collide with %s at %s, and no clear spot was found within 5m." % [name_part, result["collider_name"], where],
				"Place anyway",
				func(): _commit_place(packed, tf, parent, owner_node, "%s (overlapping %s)" % [where, result["collider_name"]]))
		return
	var suggested_tf := Transform3D(tf.basis, suggested as Vector3)
	var offset_str: String = SceneQuery.describe_offset((suggested as Vector3) - tf.origin)
	confirm.ask("%s would collide with %s. There is a clear spot %s." % [name_part, result["collider_name"], offset_str],
			"Place at clear spot",
			func(): _commit_place(packed, suggested_tf, parent, owner_node, "%s (auto-moved %s)" % [where, offset_str]))

func _commit_place(packed: PackedScene, tf: Transform3D, parent: Node, owner_node: Node, where: String) -> void:
	var instance := packed.instantiate()
	dock.ops.add_node(parent, instance, "Insert %s" % instance.name, tf if instance is Node3D else null)
	if instance is Node3D:
		dock.last_placed_node = instance as Node3D
	dock._say_ok("Inserted %s at %s. Press Control Z to undo." % [instance.name, where])

# --- Floor zones ---

func _add_floor_zone() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var world_rect: Rect2 = dock.corner_selector.get_rect2_xz()
	var rect := Rect2(world_rect.position.x - room.global_position.x,
		room.global_position.z - world_rect.end.y, world_rect.size.x, world_rect.size.y)
	if rect.size.x < 0.01 or rect.size.y < 0.01:
		dock._say("Zone too small, move cursor between corners first."); return
	var surface := zone_surface_edit.text.strip_edges()
	if surface.is_empty(): dock._say("Enter a surface name first."); return
	var wc: WallConfig = room.cfg("floor")
	var after: Array[Dictionary] = wc.zones.duplicate(true)
	after.append({"rect": rect, "surface": surface})
	dock.ops.begin("Add %s zone to floor of %s" % [surface, room.name])
	dock.ops.prop(wc, "zones", after)
	dock.ops.refresh(room, "_queue_rebuild")
	dock.ops.commit()
	dock._say_ok("Added %s zone (%.1f x %.1f m) to floor of %s. Press Control Z to undo." % [surface, rect.size.x, rect.size.y, room.name])

func _clear_floor_zones() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var wc: WallConfig = room.cfg("floor")
	if wc.zones.is_empty():
		dock._say("%s has no floor zones to clear." % room.name); return
	# A bulk delete of work that took many placements to build: always ask.
	confirm.ask("Clear all %d floor zone%s from %s?" % [wc.zones.size(), "s" if wc.zones.size() != 1 else "", room.name],
			"Clear all zones", func(): _do_clear_floor_zones(room, wc))

func _do_clear_floor_zones(room: Room3D, wc: WallConfig) -> void:
	var count := wc.zones.size()
	var empty: Array[Dictionary] = []
	dock.ops.begin("Clear floor zones from %s" % room.name)
	dock.ops.prop(wc, "zones", empty)
	dock.ops.refresh(room, "_queue_rebuild")
	dock.ops.commit()
	dock._say_ok("Cleared %d floor zone%s from %s. Press Control Z to undo." % [count, "s" if count != 1 else "", room.name])

# --- Snap helpers ---

func _nudge_to_floor() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var floor_y = dock.scene_query.raycast_down(n.global_position)
	if floor_y == null: dock._say("No floor found below node."); return
	var target := Vector3(n.global_position.x, floor_y + _floor_offset.value, n.global_position.z)
	dock.ops.set_prop(n, "global_position", target, "Nudge %s to floor" % n.name)
	dock._say_ok("Nudged %s to floor (y=%.2f). Press Control Z to undo." % [n.name, target.y])

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
	dock.ops.set_prop(n, "global_position", best_hit - best_dir * _wall_offset.value,
			"Snap %s to %s wall" % [n.name, best_side])
	dock._say_ok("Snapped %s to %s wall (%.1fm away). Press Control Z to undo." % [n.name, best_side, best_dist])

func _center_east_west() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var gap: Dictionary = dock.scene_query.wall_gap(n.global_position, Vector3.RIGHT)
	if gap.is_empty(): dock._say("Could not find walls on both east and west sides."); return
	var target := n.global_position
	target.x = (gap["midpoint"] as Vector3).x
	dock.ops.set_prop(n, "global_position", target, "Centre %s east-west" % n.name)
	dock._say_ok("Centered %s east-west (gap %.1fm). Press Control Z to undo." % [n.name, gap["gap"]])

func _center_north_south() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var gap: Dictionary = dock.scene_query.wall_gap(n.global_position, Vector3.BACK)
	if gap.is_empty(): dock._say("Could not find walls on both north and south sides."); return
	var target := n.global_position
	target.z = (gap["midpoint"] as Vector3).z
	dock.ops.set_prop(n, "global_position", target, "Centre %s north-south" % n.name)
	dock._say_ok("Centered %s north-south (gap %.1fm). Press Control Z to undo." % [n.name, gap["gap"]])

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
	dock.ops.set_prop(n, "global_position", wpos + inward * _door_inset.value,
			"Snap %s to %s doorway" % [n.name, info["side"]])
	dock._say_ok("Snapped %s to %s doorway (%.1fm by %.1fm). Press Control Z to undo." % [n.name, info["side"], info["width"], info["height"]])

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
	var parent: Node = _resolve_parent_for(dock.cursor)
	if parent == null: dock._say("No scene open."); return
	var size := Vector3(_phys_width.value, _phys_height.value, _phys_depth.value)
	var type_name: String = _body_type_option.get_item_text(_body_type_option.selected)
	if type_name != "Area3D":
		var reason := _fit_check(dock.cursor, size)
		if reason != "":
			var pos: Vector3 = dock.cursor
			confirm.ask("%s (%.1f by %.1f by %.1f m) does not fit at the cursor: %s." % [type_name, size.x, size.y, size.z, reason],
					"Create anyway",
					func(): _create_physical_object(parent, dock.scene_query.edited_root(), pos, size))
			return
	_create_physical_object(parent, dock.scene_query.edited_root(), dock.cursor, size)

func _insert_physical_object_from_selection() -> void:
	var aabb: AABB = dock.corner_selector.get_aabb()
	if aabb.size.x < 0.05 or aabb.size.y < 0.05 or aabb.size.z < 0.05:
		dock._say("Selection too small, set corner A and B first."); return
	var pos := Vector3(aabb.position.x + aabb.size.x / 2.0, aabb.position.y, aabb.position.z + aabb.size.z / 2.0)
	var parent: Node = _resolve_parent_for(pos)
	if parent == null: dock._say("No scene open."); return
	var type_name: String = _body_type_option.get_item_text(_body_type_option.selected)
	if type_name != "Area3D":
		var reason := _fit_check(pos, aabb.size)
		if reason != "":
			var sz: Vector3 = aabb.size
			confirm.ask("%s (%.1f by %.1f by %.1f m) does not fit in the selection: %s." % [type_name, sz.x, sz.y, sz.z, reason],
					"Create anyway",
					func(): _create_physical_object(parent, dock.scene_query.edited_root(), pos, sz))
			return
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
	var type_name: String = _body_type_option.get_item_text(_body_type_option.selected)
	var body := ClassDB.instantiate(type_name) as Node3D
	if body == null: dock._say("Could not create %s." % type_name); return
	body.name = "%s%d" % [type_name, parent.get_child_count() + 1]
	var cs := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	cs.shape = box_shape
	cs.position = Vector3(0.0, size.y / 2.0, 0.0)
	body.add_child(cs)
	var mi: MeshInstance3D = null
	if type_name != "Area3D":
		mi = MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mi.mesh = box_mesh
		mi.position = Vector3(0.0, size.y / 2.0, 0.0)
		body.add_child(mi)
	dock.ops.add_node(parent, body, "Create %s" % body.name, pos)
	dock.last_placed_node = body
	dock._say_ok("Created %s (%.1f by %.1f by %.1f m) at %.1f %.1f %.1f. Press Control Z to undo." % [type_name, size.x, size.y, size.z, pos.x, pos.y, pos.z])
