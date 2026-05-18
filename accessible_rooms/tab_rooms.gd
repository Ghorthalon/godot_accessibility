@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var new_w: SpinBox; var new_h: SpinBox; var new_d: SpinBox
var resize_w: SpinBox; var resize_h: SpinBox; var resize_d: SpinBox
var move_x: SpinBox; var move_y: SpinBox; var move_z: SpinBox
var _move_cascade_checkbox: CheckBox
var door_w: SpinBox; var door_h: SpinBox
var room_list: ItemList
var _resize_container: VBoxContainer
var create_door_placeholder: CheckBox
var _door_item_list: ItemList
var _door_props_container: VBoxContainer
var _current_door_idx: int = -1
var _wall_item_list: ItemList
var _wall_props_container: VBoxContainer
var _current_wall_side: String = ""
var build_walls: CheckBox
var build_ceiling: CheckBox
var _resize_anchor := Vector2(0.5, 0.5)
var _anchor_buttons: Array[Button] = []
var _cascade_checkbox: CheckBox
var _pending_resize: Dictionary = {}
var _resize_conflict_bar: HBoxContainer
var _resize_conflict_label: Label
var _connection_container: VBoxContainer
var _gap_max_spin: SpinBox
var _gap_list: ItemList
var _gap_results: Array[Dictionary] = []

func _ready() -> void:
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	# SUBTAB: Rooms
	var rooms_tab := VBoxContainer.new()
	rooms_tab.name = "Rooms"
	tabs.add_child(rooms_tab)

	room_list = ItemList.new()
	room_list.custom_minimum_size = Vector2(0, 200)
	room_list.item_selected.connect(_on_select)
	rooms_tab.add_child(room_list)
	_btn_into(rooms_tab, "Refresh entity list", _refresh)

	rooms_tab.add_child(HSeparator.new())

	var rl := Label.new(); rl.text = "Edit selected entity:"
	rooms_tab.add_child(rl)
	_build_anchor_ui_into(rooms_tab)
	_resize_container = VBoxContainer.new()
	rooms_tab.add_child(_resize_container)
	_btn_into(rooms_tab, "Apply changes", _apply_resize)
	_resize_conflict_bar = HBoxContainer.new()
	_resize_conflict_bar.visible = false
	_resize_conflict_label = Label.new()
	_resize_conflict_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resize_conflict_bar.add_child(_resize_conflict_label)
	var _proceed_btn := Button.new(); _proceed_btn.text = "Proceed"
	_proceed_btn.pressed.connect(_on_resize_confirm)
	var _cancel_btn := Button.new(); _cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_resize_cancel)
	_resize_conflict_bar.add_child(_proceed_btn)
	_resize_conflict_bar.add_child(_cancel_btn)
	rooms_tab.add_child(_resize_conflict_bar)
	_btn_into(rooms_tab, "Measure space at cursor", _measure_space_at_cursor)
	_btn_into(rooms_tab, "Resize room to fill E\u2194W", _resize_fill_ew)
	_btn_into(rooms_tab, "Resize room to fill N\u2194S", _resize_fill_ns)

	rooms_tab.add_child(HSeparator.new())

	var ml := Label.new(); ml.text = "Move selected room to (m):"
	rooms_tab.add_child(ml)
	move_x = _spinbox(-1000.0, 1000.0, 0.5, 0.0)
	move_y = _spinbox(-1000.0, 1000.0, 0.5, 0.0)
	move_z = _spinbox(-1000.0, 1000.0, 0.5, 0.0)
	var mr := HBoxContainer.new()
	for pair in [["X:", move_x], ["Y:", move_y], ["Z:", move_z]]:
		var lbl := Label.new(); lbl.text = pair[0]
		mr.add_child(lbl); mr.add_child(pair[1])
	rooms_tab.add_child(mr)
	_move_cascade_checkbox = CheckBox.new()
	_move_cascade_checkbox.text = "Cascade: drag connected rooms"
	_move_cascade_checkbox.tooltip_text = "Translate every room flush-connected to this one by the same delta, keeps L-shaped layouts connected"
	rooms_tab.add_child(_move_cascade_checkbox)
	_btn_into(rooms_tab, "Set from cursor", _move_set_from_cursor)
	_btn_into(rooms_tab, "Apply move", _apply_move)

	rooms_tab.add_child(HSeparator.new())

	var nl := Label.new(); nl.text = "New room size (m):"
	rooms_tab.add_child(nl)
	new_w = _spinbox(1.0, 200.0, 1.0, 6.0)
	new_h = _spinbox(1.0, 100.0, 0.5, 3.0)
	new_d = _spinbox(1.0, 200.0, 1.0, 6.0)
	var nr := HBoxContainer.new()
	for pair in [["W:", new_w], ["H:", new_h], ["D:", new_d]]:
		var lbl := Label.new(); lbl.text = pair[0]
		nr.add_child(lbl); nr.add_child(pair[1])
	rooms_tab.add_child(nr)
	var surface_row := HBoxContainer.new()
	build_walls = CheckBox.new()
	build_walls.text = "Build walls"
	build_walls.button_pressed = true
	build_ceiling = CheckBox.new()
	build_ceiling.text = "Build ceiling"
	build_ceiling.button_pressed = true
	surface_row.add_child(build_walls)
	surface_row.add_child(build_ceiling)
	rooms_tab.add_child(surface_row)
	_btn_into(rooms_tab, "New standalone room", _new_root_room)
	var cc_lbl := Label.new(); cc_lbl.text = "Corner-to-corner room:"
	rooms_tab.add_child(cc_lbl)
	_btn_into(rooms_tab, "Place room from corners", _place_room_from_corners)
	rooms_tab.add_child(HSeparator.new())
	for side in ["north", "south", "east", "west"]:
		_btn_into(rooms_tab, "Add room to %s of current" % side, _add_neighbor.bind(side))

	rooms_tab.add_child(HSeparator.new())
	var gap_header := Label.new(); gap_header.text = "Gap detection:"
	rooms_tab.add_child(gap_header)
	var gap_row := HBoxContainer.new()
	var gap_lbl := Label.new(); gap_lbl.text = "Max gap (m):"
	_gap_max_spin = _spinbox(0.5, 10.0, 0.5, 2.0)
	gap_row.add_child(gap_lbl); gap_row.add_child(_gap_max_spin)
	rooms_tab.add_child(gap_row)
	_btn_into(rooms_tab, "Check gaps", _check_gaps)
	_gap_list = ItemList.new()
	_gap_list.custom_minimum_size = Vector2(0, 150)
	_gap_list.item_selected.connect(_on_gap_selected)
	rooms_tab.add_child(_gap_list)

	# SUBTAB: Doors & Walls
	var dw_tab := VBoxContainer.new()
	dw_tab.name = "Doors & Walls"
	tabs.add_child(dw_tab)

	var dl := Label.new(); dl.text = "Doorway size (m):"
	dw_tab.add_child(dl)
	door_w = _spinbox(0.5, 20.0, 0.1, 1.2)
	door_h = _spinbox(0.5, 20.0, 0.1, 2.5)
	var dr := HBoxContainer.new()
	for pair in [["W:", door_w], ["H:", door_h]]:
		var lbl := Label.new(); lbl.text = pair[0]
		dr.add_child(lbl); dr.add_child(pair[1])
	dw_tab.add_child(dr)
	create_door_placeholder = CheckBox.new()
	create_door_placeholder.text = "Create door placeholder at new doorways"
	create_door_placeholder.button_pressed = true
	dw_tab.add_child(create_door_placeholder)
	_btn_into(dw_tab, "Punch door at cursor (on nearest wall)", _punch_at_cursor)
	_btn_into(dw_tab, "Punch hole at cursor (on nearest wall)", _punch_hole_at_cursor)
	for side in ["north", "south", "east", "west"]:
		_btn_into(dw_tab, "Punch doorway %s on current" % side, _punch.bind(side))

	dw_tab.add_child(HSeparator.new())

	var door_lbl := Label.new(); door_lbl.text = "Doors on selected room:"
	dw_tab.add_child(door_lbl)
	_door_item_list = ItemList.new()
	_door_item_list.custom_minimum_size = Vector2(0, 100)
	_door_item_list.item_selected.connect(_on_door_select)
	dw_tab.add_child(_door_item_list)
	_door_props_container = VBoxContainer.new()
	dw_tab.add_child(_door_props_container)
	_btn_into(dw_tab, "Apply door changes", _apply_door_changes)
	_btn_into(dw_tab, "Remove selected door", _remove_selected_door)

	dw_tab.add_child(HSeparator.new())

	var wall_lbl := Label.new(); wall_lbl.text = "Walls on selected room:"
	dw_tab.add_child(wall_lbl)
	_wall_item_list = ItemList.new()
	_wall_item_list.custom_minimum_size = Vector2(0, 100)
	_wall_item_list.item_selected.connect(_on_wall_select)
	dw_tab.add_child(_wall_item_list)
	_wall_props_container = VBoxContainer.new()
	dw_tab.add_child(_wall_props_container)
	_btn_into(dw_tab, "Apply wall changes", _apply_wall_changes)

	dw_tab.add_child(HSeparator.new())

	var conn_hdr := Label.new(); conn_hdr.text = "Connections:"
	dw_tab.add_child(conn_hdr)
	_connection_container = VBoxContainer.new()
	dw_tab.add_child(_connection_container)

	# SUBTAB: Bake
	var bake_tab := VBoxContainer.new()
	bake_tab.name = "Bake"
	tabs.add_child(bake_tab)

	var bake_lbl := Label.new()
	bake_lbl.text = "Merges all spatial entities into optimised static meshes.\nIn-place modifies the current scene; Bake to file saves a copy."
	bake_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bake_tab.add_child(bake_lbl)
	_btn_into(bake_tab, "Bake to scene (in place)", _bake_scene)
	_btn_into(bake_tab, "Bake to file\u2026", _open_bake_to_file_dialog)

	_refresh()

# --- Room management ---

func _new_root_room() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say_err("No scene open."); return
	var size := Vector3(new_w.value, new_h.value, new_d.value)
	var conflict: String = dock.scene_query.first_overlap(dock.cursor, _placement_footprint(size), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say_err("Cannot place room: overlaps with %s. Move cursor clear first, or hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)
	var r := Room3D.new()
	r.name = "Room%d" % (root.get_child_count() + 1)
	r.size = size
	r.position = dock.cursor
	_apply_surface_settings(r)
	root.add_child(r); r.owner = dock.scene_query.edited_root(); r.rebuild()
	dock.current_entity = r
	_refresh()
	dock._say_ok("Created %s, %.1f by %.1f by %.1f meters." % [r.name, r.size.x, r.size.y, r.size.z])

func _place_room_from_corners() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say_err("No scene open."); return
	var aabb: AABB = dock.corner_selector.get_aabb()
	var w: float = aabb.size.x; var h: float = aabb.size.y; var d: float = aabb.size.z
	if w < 0.1 or h < 0.1 or d < 0.1:
		dock._say_err("Corners too close in one or more axes, set corner A and corner B first."); return
	var size := Vector3(w, h, d)
	var pos := Vector3(aabb.position.x + w / 2.0, aabb.position.y, aabb.position.z + d / 2.0)
	var conflict: String = dock.scene_query.first_overlap(pos, _placement_footprint(size), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say_err("Cannot place room: overlaps with %s. Hold Shift to force." % conflict); return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)
	var r := Room3D.new()
	r.name = "Room%d" % (root.get_child_count() + 1)
	r.size = size
	r.position = pos
	_apply_surface_settings(r)
	root.add_child(r); r.owner = dock.scene_query.edited_root(); r.rebuild()
	dock.current_entity = r
	_refresh()
	dock._say_ok("Created %s, %.1f by %.1f by %.1f meters." % [r.name, r.size.x, r.size.y, r.size.z])

func _add_neighbor(side: String) -> void:
	if not dock.current_entity is SpatialEntity3D:
		dock._say("No entity selected. Select a room or ramp first."); return
	var entity := dock.current_entity as SpatialEntity3D
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return

	var new_size := Vector3(new_w.value, new_h.value, new_d.value)
	var new_pos: Vector3 = (entity as Node3D).position + entity.neighbor_offset(side, new_size)

	# neighbor_offset returns ZERO when the side is invalid for this entity type.
	if new_pos == (entity as Node3D).position:
		dock._say("Cannot attach a room to the %s side of %s." % [side, entity.name])
		return

	# Overlap check before creating anything.
	var conflict: String = dock.scene_query.first_overlap(new_pos, _placement_footprint(new_size), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say_err("Cannot add neighbor: proposed position overlaps with %s. Hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	var r := Room3D.new()
	r.name = "%s_%s" % [entity.name, side]
	r.size = new_size

	# Configure the new room's doorway BEFORE adding it to the tree so that
	# add_doorway's internal _queue_rebuild is a no op (is_inside_tree = false).
	# This ensures r.rebuild() below is the only rebuild that runs.
	var back_side: String = entity.neighbor_doorway_side(side)
	var cv_new: float = -r.size.y / 2.0 + door_h.value / 2.0
	if back_side != "":
		r.add_doorway(back_side, 0.0, cv_new, door_w.value, door_h.value)
	_apply_surface_settings(r)

	root.add_child(r); r.owner = dock.scene_query.edited_root()
	r.position = new_pos
	r.rebuild()   # single rebuild, config fully set, not in tree when add_doorway was called

	# Placeholder for new room's backside doorway
	if back_side != "":
		_make_door_placeholder(r, back_side, 0.0, cv_new, door_w.value, door_h.value)


	if entity.has_wall(side):
		var cv_cur: float = -(entity as Room3D).size.y / 2.0 + door_h.value / 2.0
		var u_off: float = _overlap_center_u(entity as Room3D, r, side)
		(entity as Room3D).add_doorway(side, u_off, cv_cur, door_w.value, door_h.value)
		_make_door_placeholder(entity as Room3D, side, u_off, cv_cur, door_w.value, door_h.value)

	_refresh()
	dock._say_ok("Added room %s to %s of %s, connected by doorway." % [r.name, side, entity.name])
	_refresh_door_list()

func _punch(side: String) -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	room.punch_doorway(side, door_w.value, door_h.value)
	var cv := -room.size.y / 2.0 + door_h.value / 2.0
	_make_door_placeholder(room, side, 0.0, cv, door_w.value, door_h.value)
	dock._say("Doorway punched on %s wall (%.1fm × %.1fm)." % [side, door_w.value, door_h.value])
	_refresh_door_list()

func _make_door_placeholder(room: Room3D, side: String, cu: float, cv: float, w: float, h: float) -> void:
	if not create_door_placeholder.button_pressed: return
	var scene_root: Node = dock.scene_query.edited_root()
	if scene_root == null: return
	var placeholder := Node3D.new()
	placeholder.name = "DoorPlaceholder_%s" % side
	placeholder.set_meta("door_placeholder", true)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, h, 0.1)
	mesh_inst.mesh = box
	placeholder.add_child(mesh_inst)
	room.add_child(placeholder)
	placeholder.global_transform = dock.scene_query.wall_facing_transform(room, side, cu, cv)
	placeholder.owner = scene_root
	mesh_inst.owner = scene_root
	placeholder.visible = false

func _apply_resize() -> void:
	if dock.current_entity == null: dock._say("No entity selected."); return
	_resize_conflict_bar.visible = false

	if not dock.current_entity is Room3D:
		dock.current_entity.apply_properties_ui(_resize_container)
		_refresh()
		dock._say("Applied changes to %s." % dock.current_entity.entity_label())
		return

	var room := dock.current_entity as Room3D
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return

	var spins: Array[SpinBox] = []
	for row in _resize_container.get_children():
		for child in row.get_children():
			if child is SpinBox: spins.append(child as SpinBox)
	if spins.size() < 3: dock._say("No resize controls found."); return
	var new_size := Vector3(spins[0].value, spins[1].value, spins[2].value)

	var new_pos := _anchor_position(room, new_size, _resize_anchor)

	var cascade_moves: Array = []
	if _cascade_checkbox.button_pressed:
		cascade_moves = _collect_cascade(room, room.position, room.size, new_pos, new_size, root, [room])

	var conflicts := _check_all_overlaps(room, new_pos, new_size, cascade_moves, root)
	if not conflicts.is_empty():
		var names := ", ".join(conflicts.map(func(r): return (r as Room3D).name))
		dock._say_err("Resize would overlap %s. Choose Proceed or Cancel." % names)
		_pending_resize = {"room": room, "pos": new_pos, "size": new_size, "cascade": cascade_moves}
		_resize_conflict_label.text = "Overlaps: %s. Proceed?" % names
		_resize_conflict_bar.visible = true
		return

	_execute_resize(room, new_pos, new_size, cascade_moves)

func _refresh() -> void:
	room_list.clear()
	var root: Node = dock.scene_query.placement_parent() if dock.scene_query else null
	if root == null: return
	for c in root.get_children():
		if not c is SpatialEntity3D: continue
		var entity := c as SpatialEntity3D
		var label: String = dock.scene_query.entity_label(entity)
		var suffix := _connection_suffix(entity)
		if suffix != "": label += " " + suffix
		room_list.add_item(label)
		room_list.set_item_metadata(room_list.item_count - 1, entity)

func _connection_suffix(entity: SpatialEntity3D) -> String:
	if dock.scene_query == null: return ""
	var conns: Array[ConnectionInfo] = dock.scene_query.find_connections(entity)
	if conns.is_empty(): return ""
	var n_open := 0; var n_blocked := 0
	for info: ConnectionInfo in conns:
		if info.status == ConnectionInfo.Status.OPEN: n_open += 1
		else: n_blocked += 1
	if n_open > 0 and n_blocked > 0: return "[%d open, %d blocked]" % [n_open, n_blocked]
	if n_open > 0: return "[%d open]" % n_open
	return "[%d blocked]" % n_blocked

func _on_select(i: int) -> void:
	var entity := room_list.get_item_metadata(i) as SpatialEntity3D
	dock.current_entity = entity
	for child in _resize_container.get_children():
		child.queue_free()
	await get_tree().process_frame
	entity.populate_properties_ui(_resize_container)
	if entity is Room3D:
		move_x.value = (entity as Node3D).position.x
		move_y.value = (entity as Node3D).position.y
		move_z.value = (entity as Node3D).position.z
	dock._say("Selected %s." % dock.scene_query.entity_label(entity))
	dock.play_audio_3d("object", (entity as Node3D).global_position)
	_refresh_door_list()
	_refresh_wall_list()
	_refresh_connection_list(entity)

func _bake_scene() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var entities: Array[SpatialEntity3D] = []
	for c in root.get_children():
		if c is SpatialEntity3D: entities.append(c as SpatialEntity3D)
	if entities.is_empty(): dock._say("No spatial entities found."); return
	var count := BakeEngine.bake_in_place(entities, root)
	dock.current_entity = null
	_refresh()
	dock._say_ok("Baked %d spatial entit%s with merged meshes and optimised collision." \
		% [count, "ies" if count != 1 else "y"])

func _open_bake_to_file_dialog() -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.add_filter("*.tscn", "Scene Files")
	dlg.file_selected.connect(_bake_to_file)
	dlg.close_requested.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.7)

func _bake_to_file(target_path: String) -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var count := 0
	for c in root.get_children():
		if c is SpatialEntity3D: count += 1
	if count == 0: dock._say("No spatial entities found."); return
	var packed := BakeEngine.bake_to_packed_scene(root)
	if packed == null: dock._say_err("Failed to pack scene."); return
	var err := ResourceSaver.save(packed, target_path)
	if err != OK: dock._say_err("Failed to save scene (error %d)." % err); return
	dock._say_ok("Baked %d entit%s → %s" \
		% [count, "ies" if count != 1 else "y", target_path])

# --- Helpers ---

func _placement_footprint(s: Vector3) -> Vector3:
	if build_walls.button_pressed:
		return s
	return Vector3(s.x, 0.01, s.z)

func _apply_surface_settings(r: Room3D) -> void:
	if not build_walls.button_pressed:
		for side in ["north", "south", "east", "west"]:
			r.cfg(side).enabled = false
	if not build_ceiling.button_pressed:
		r.cfg("ceiling").enabled = false

func _spinbox(min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v; s.max_value = max_v
	s.step = step_v; s.value = default_v
	return s

func _punch_at_cursor() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var cur: Vector3 = dock.cursor
	var side: String = _closest_wall(room, cur)
	var local_v: float = cur.y - (room.position.y + room.size.y / 2.0)
	var local_u: float
	match side:
		"north", "south":
			local_u = cur.x - room.position.x
		"east", "west":
			local_u = room.position.z - cur.z
	room.add_doorway(side, local_u, local_v, door_w.value, door_h.value)
	_make_door_placeholder(room, side, local_u, local_v, door_w.value, door_h.value)
	_refresh()
	dock._say("Door punched on %s wall at offset %.1f, %.1f (%.1fm × %.1fm)." % \
		[side, local_u, local_v, door_w.value, door_h.value])
	_refresh_door_list()

func _punch_hole_at_cursor() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var cur: Vector3 = dock.cursor
	var side: String = _closest_wall(room, cur)
	var local_v: float = cur.y - (room.position.y + room.size.y / 2.0)
	var local_u: float
	match side:
		"north", "south":
			local_u = cur.x - room.position.x
		"east", "west":
			local_u = room.position.z - cur.z
	room.punch_hole(side, local_u, local_v, door_w.value, door_h.value)
	_refresh()
	dock._say("Hole punched on %s wall at offset %.1f, %.1f (%.1fm × %.1fm)." % \
		[side, local_u, local_v, door_w.value, door_h.value])
	_refresh_door_list()

func _closest_wall(room: Room3D, cur: Vector3) -> String:
	var rp := room.position; var rs := room.size
	var dists := {
		"north": abs(cur.z - (rp.z - rs.z/2)),
		"south": abs(cur.z - (rp.z + rs.z/2)),
		"east":  abs(cur.x - (rp.x + rs.x/2)),
		"west":  abs(cur.x - (rp.x - rs.x/2)),
	}
	var best := "north"
	for s in dists:
		if dists[s] < dists[best]: best = s
	return best

func _overlap_center_u(a: Room3D, b: Room3D, side: String) -> float:
	if side in ["north", "south"]:
		var lo := maxf(a.position.x - a.size.x/2, b.position.x - b.size.x/2)
		var hi := minf(a.position.x + a.size.x/2, b.position.x + b.size.x/2)
		return ((lo + hi) / 2.0) - a.position.x
	else:
		var lo := maxf(a.position.z - a.size.z/2, b.position.z - b.size.z/2)
		var hi := minf(a.position.z + a.size.z/2, b.position.z + b.size.z/2)
		return a.position.z - ((lo + hi) / 2.0)

func _measure_space_at_cursor() -> void:
	var space: Dictionary = dock.scene_query.measure_space(dock.cursor)
	dock._say("Space at cursor: north %.1fm, south %.1fm, east %.1fm, west %.1fm, up %.1fm, down %.1fm." % \
		[space["north"], space["south"], space["east"], space["west"], space["up"], space["down"]])

func _resize_fill_ew() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var gap: Dictionary = dock.scene_query.wall_gap(room.position, Vector3.RIGHT)
	if gap.is_empty(): dock._say("Could not find walls on both east and west sides."); return
	room.size.x = gap["gap"]
	room.rebuild()
	dock._say("Room width set to %.1fm to fill east-west space." % room.size.x)

func _resize_fill_ns() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var gap: Dictionary = dock.scene_query.wall_gap(room.position, Vector3.BACK)
	if gap.is_empty(): dock._say("Could not find walls on both north and south sides."); return
	room.size.z = gap["gap"]
	room.rebuild()
	dock._say("Room depth set to %.1fm to fill north-south space." % room.size.z)

func _refresh_door_list() -> void:
	_door_item_list.clear()
	_current_door_idx = -1
	for c in _door_props_container.get_children(): c.queue_free()
	if not dock.current_entity is Room3D: return
	var room := dock.current_entity as Room3D
	if room.door_list.is_empty():
		return
	for i in room.door_list.size():
		var d: DoorEntry = room.door_list[i]
		var name_part := ("\"%s\" " % d.label) if d.label != "" else ""
		var scene_part := " [filled]" if d.scene_path != "" else " [empty]"
		_door_item_list.add_item("[%d] %s%s  U:%.2f V:%.2f  %.1f×%.1fm%s" % [i, name_part, d.side, d.center_u, d.center_v, d.width, d.height, scene_part])
		_door_item_list.set_item_metadata(i, i)

func _on_door_select(i: int) -> void:
	if not dock.current_entity is Room3D: return
	var room := dock.current_entity as Room3D
	_current_door_idx = _door_item_list.get_item_metadata(i)
	if _current_door_idx < 0 or _current_door_idx >= room.door_list.size(): return
	var d: DoorEntry = room.door_list[_current_door_idx]
	for c in _door_props_container.get_children(): c.queue_free()
	await get_tree().process_frame
	var name_row := HBoxContainer.new()
	var name_lbl := Label.new(); name_lbl.text = "Name:"
	var name_edit := LineEdit.new()
	name_edit.text = d.label
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_lbl); name_row.add_child(name_edit)
	_door_props_container.add_child(name_row)
	var side_row := HBoxContainer.new()
	var side_lbl := Label.new(); side_lbl.text = "Side:"
	var side_opt := OptionButton.new()
	for s in ["north", "south", "east", "west"]:
		side_opt.add_item(s)
		if s == d.side: side_opt.selected = side_opt.item_count - 1
	side_row.add_child(side_lbl); side_row.add_child(side_opt)
	_door_props_container.add_child(side_row)
	SpatialEntity3D._add_spinbox(_door_props_container, "U (horiz):", -50.0, 50.0, 0.1, d.center_u)
	SpatialEntity3D._add_spinbox(_door_props_container, "V (vert):", -50.0, 50.0, 0.1, d.center_v)
	SpatialEntity3D._add_spinbox(_door_props_container, "W:", 0.5, 20.0, 0.1, d.width)
	SpatialEntity3D._add_spinbox(_door_props_container, "H:", 0.5, 20.0, 0.1, d.height)
	var scene_row := HBoxContainer.new()
	var scene_lbl := Label.new(); scene_lbl.text = "Scene:"
	var scene_edit := LineEdit.new()
	scene_edit.text = d.scene_path
	scene_edit.placeholder_text = "res://path/to/door.tscn"
	scene_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_row.add_child(scene_lbl); scene_row.add_child(scene_edit)
	_door_props_container.add_child(scene_row)
	var place_btn := Button.new()
	place_btn.text = "Place scene at this door"
	place_btn.pressed.connect(_place_door_scene)
	_door_props_container.add_child(place_btn)

func _apply_door_changes() -> void:
	if not dock.current_entity is Room3D or _current_door_idx < 0:
		dock._say("No door selected."); return
	var room := dock.current_entity as Room3D
	if _current_door_idx >= room.door_list.size():
		dock._say("Door index out of range."); return
	var d: DoorEntry = room.door_list[_current_door_idx]
	var children := _door_props_container.get_children()
	var name_edit2 := children[0].get_child(1) as LineEdit
	d.label = name_edit2.text
	var side_opt := children[1].get_child(1) as OptionButton
	d.side = side_opt.get_item_text(side_opt.selected)
	var spins: Array[SpinBox] = []
	var scene_edit: LineEdit = null
	for row in children.slice(2):
		if not row is Container: continue
		for c in row.get_children():
			if c is SpinBox: spins.append(c)
			elif c is LineEdit: scene_edit = c
	if spins.size() >= 4:
		d.center_u = spins[0].value; d.center_v = spins[1].value
		d.width = spins[2].value; d.height = spins[3].value
	if scene_edit != null: d.scene_path = scene_edit.text.strip_edges()
	room._queue_rebuild()
	_refresh_door_list()
	dock._say("Door %d on %s updated." % [_current_door_idx, room.name])

func _place_door_scene() -> void:
	if not dock.current_entity is Room3D or _current_door_idx < 0:
		dock._say("No door selected."); return
	var room := dock.current_entity as Room3D
	if _current_door_idx >= room.door_list.size():
		dock._say("Door index out of range."); return
	# Persist any pending field edits (including scene path) before placing.
	_apply_door_changes()
	var d: DoorEntry = room.door_list[_current_door_idx]
	if d.scene_path == "":
		dock._say("Set a scene path on this door first."); return
	if not ResourceLoader.exists(d.scene_path):
		dock._say_err("Scene not found: %s" % d.scene_path); return
	var packed := load(d.scene_path) as PackedScene
	if packed == null: dock._say_err("Failed to load scene."); return
	var tf: Transform3D = dock.scene_query.wall_facing_transform(room, d.side, d.center_u, d.center_v)
	dock.tab_place.instantiate_aligned(packed, tf, room,
		"door %d (%s wall of %s)" % [_current_door_idx, d.side, room.name])

func _remove_selected_door() -> void:
	if not dock.current_entity is Room3D or _current_door_idx < 0:
		dock._say("No door selected."); return
	var room := dock.current_entity as Room3D
	room.remove_door(_current_door_idx)
	_refresh_door_list()
	dock._say("Removed door %d from %s." % [_current_door_idx, room.name])

func _refresh_connection_list(entity: SpatialEntity3D) -> void:
	for child in _connection_container.get_children(): child.queue_free()
	if dock.scene_query == null: return
	await get_tree().process_frame
	var conns: Array[ConnectionInfo] = dock.scene_query.find_connections(entity)
	if conns.is_empty():
		var lbl := Label.new(); lbl.text = "No connections found."
		_connection_container.add_child(lbl); return
	for info: ConnectionInfo in conns:
		var to_name: String = info.to_entity.name if info.to_entity != null else "unknown"
		var status_text: String
		if info.status == ConnectionInfo.Status.OPEN:
			status_text = "open"
		else:
			status_text = "blocked, add a door on the %s wall of %s" % [info.to_wall_side, to_name]
		var line: String
		if info.to_wall_side != "":
			line = "%s connects to %s (%s wall): %s" % [info.from_label, to_name, info.to_wall_side, status_text]
		else:
			line = "%s connects to %s: %s" % [info.from_label, to_name, status_text]
		var lbl := Label.new()
		lbl.text = line
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_connection_container.add_child(lbl)

func _refresh_wall_list() -> void:
	_wall_item_list.clear()
	_current_wall_side = ""
	for c in _wall_props_container.get_children(): c.queue_free()
	if not dock.current_entity is Room3D: return
	var room := dock.current_entity as Room3D
	for side in ["north", "south", "east", "west", "floor", "ceiling"]:
		var wc: WallConfig = room.cfg(side)
		var state := "on" if wc.enabled else "off"
		_wall_item_list.add_item("%s, %s, %.2fm (%s)" % [side, wc.surface, wc.thickness, state])
		_wall_item_list.set_item_metadata(_wall_item_list.item_count - 1, side)

func _on_wall_select(i: int) -> void:
	if not dock.current_entity is Room3D: return
	var room := dock.current_entity as Room3D
	_current_wall_side = _wall_item_list.get_item_metadata(i)
	var wc: WallConfig = room.cfg(_current_wall_side)
	for c in _wall_props_container.get_children(): c.queue_free()
	await get_tree().process_frame
	var enabled_cb := CheckBox.new()
	enabled_cb.text = "Enabled"
	enabled_cb.button_pressed = wc.enabled
	_wall_props_container.add_child(enabled_cb)
	var surf_row := HBoxContainer.new()
	var surf_lbl := Label.new(); surf_lbl.text = "Surface:"
	var surf_edit := LineEdit.new()
	surf_edit.text = wc.surface
	surf_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surf_row.add_child(surf_lbl); surf_row.add_child(surf_edit)
	_wall_props_container.add_child(surf_row)
	SpatialEntity3D._add_spinbox(_wall_props_container, "Thickness (m):", 0.05, 5.0, 0.05, wc.thickness)
	dock._say("Selected %s wall, surface: %s, thickness: %.2fm, %s." % [_current_wall_side, wc.surface, wc.thickness, "enabled" if wc.enabled else "disabled"])

func _apply_wall_changes() -> void:
	if not dock.current_entity is Room3D or _current_wall_side == "":
		dock._say("No wall selected."); return
	var room := dock.current_entity as Room3D
	var wc: WallConfig = room.cfg(_current_wall_side)
	var children := _wall_props_container.get_children()
	if children.size() < 3: dock._say("Wall controls not ready."); return
	var enabled_cb := children[0] as CheckBox
	var surf_row := children[1]
	var thickness_row := children[2]
	var surf_edit: LineEdit
	for c in surf_row.get_children():
		if c is LineEdit: surf_edit = c; break
	var thickness_spin: SpinBox
	for c in thickness_row.get_children():
		if c is SpinBox: thickness_spin = c; break
	if enabled_cb == null or surf_edit == null or thickness_spin == null: return
	wc.enabled = enabled_cb.button_pressed
	wc.surface = surf_edit.text.strip_edges()
	wc.thickness = thickness_spin.value
	room._queue_rebuild()
	_refresh_wall_list()
	dock._say("%s wall updated, surface: %s, thickness: %.2fm, %s." % [_current_wall_side, wc.surface, wc.thickness, "enabled" if wc.enabled else "disabled"])

func _build_anchor_ui_into(c: VBoxContainer) -> void:
	var anchor_lbl := Label.new()
	anchor_lbl.text = "Resize anchor:"
	c.add_child(anchor_lbl)

	var anchor_grid := GridContainer.new()
	anchor_grid.columns = 3
	c.add_child(anchor_grid)

	var anchor_defs := [
		["NW", Vector2(0.0, 0.0), "Northwest corner, keep northwest fixed"],
		["N",  Vector2(0.5, 0.0), "North edge, keep north fixed"],
		["NE", Vector2(1.0, 0.0), "Northeast corner, keep northeast fixed"],
		["W",  Vector2(0.0, 0.5), "West edge, keep west fixed"],
		["C",  Vector2(0.5, 0.5), "Center, resize equally on all sides (default)"],
		["E",  Vector2(1.0, 0.5), "East edge, keep east fixed"],
		["SW", Vector2(0.0, 1.0), "Southwest corner, keep southwest fixed"],
		["S",  Vector2(0.5, 1.0), "South edge, keep south fixed"],
		["SE", Vector2(1.0, 1.0), "Southeast corner, keep southeast fixed"],
	]

	_anchor_buttons.clear()
	var btn_group := ButtonGroup.new()
	for i in anchor_defs.size():
		var def: Array = anchor_defs[i]
		var btn := Button.new()
		btn.text = def[0]
		btn.tooltip_text = def[2]
		btn.toggle_mode = true
		btn.button_group = btn_group
		btn.button_pressed = (i == 4)  # center by default
		var anchor_val: Vector2 = def[1]
		btn.toggled.connect(func(on: bool): if on: _resize_anchor = anchor_val)
		anchor_grid.add_child(btn)
		_anchor_buttons.append(btn)

	var smart_btn := Button.new()
	smart_btn.text = "Smart anchor"
	smart_btn.tooltip_text = "Auto-select anchor based on which sides have connected rooms"
	smart_btn.pressed.connect(_auto_anchor)
	c.add_child(smart_btn)

	_cascade_checkbox = CheckBox.new()
	_cascade_checkbox.text = "Cascade: push connected rooms"
	_cascade_checkbox.tooltip_text = "When growing, recursively push rooms flush with the growing wall"
	c.add_child(_cascade_checkbox)

func _anchor_position(room: Room3D, new_size: Vector3, anchor: Vector2) -> Vector3:
	# anchor.x: 0=west edge fixed, 0.5=center, 1=east edge fixed
	# anchor.y: 0=north edge fixed, 0.5=center, 1=south edge fixed
	var ax := room.position.x + (anchor.x - 0.5) * room.size.x
	var az := room.position.z + (anchor.y - 0.5) * room.size.z
	return Vector3(ax - (anchor.x - 0.5) * new_size.x, room.position.y,
			az - (anchor.y - 0.5) * new_size.z)

func _collect_cascade(room: Room3D, old_pos: Vector3, old_size: Vector3,
		new_pos: Vector3, new_size: Vector3, root: Node, visited: Array) -> Array:
	var result: Array = []
	var side_data := [
		["east",  new_pos.x + new_size.x/2 - (old_pos.x + old_size.x/2), Vector3(1, 0, 0)],
		["west",  (old_pos.x - old_size.x/2) - (new_pos.x - new_size.x/2), Vector3(-1, 0, 0)],
		["south", new_pos.z + new_size.z/2 - (old_pos.z + old_size.z/2), Vector3(0, 0, 1)],
		["north", (old_pos.z - old_size.z/2) - (new_pos.z - new_size.z/2), Vector3(0, 0, -1)],
	]
	for sd in side_data:
		var side: String = sd[0]
		var delta: float = sd[1]
		var axis: Vector3 = sd[2]
		if delta < Room3D.EPSILON: continue  # only push outward, not pull inward
		for neighbor: Room3D in dock.scene_query.rooms_flush_with_wall(room, side, root):
			if neighbor in visited: continue
			var n_new_pos := neighbor.position + axis * delta
			result = result.filter(func(m): return m["room"] != neighbor)
			result.append({"room": neighbor, "new_pos": n_new_pos})
			visited.append(neighbor)
			var sub := _collect_cascade(neighbor, neighbor.position, neighbor.size,
					n_new_pos, neighbor.size, root, visited)
			for m in sub:
				result = result.filter(func(sr): return sr["room"] != m["room"])
				result.append(m)
	return result

func _check_all_overlaps(primary: Room3D, new_pos: Vector3, new_size: Vector3,
		cascade_moves: Array, root: Node) -> Array:
	var moving: Dictionary = {primary: new_pos}
	for m in cascade_moves:
		moving[m["room"]] = m["new_pos"]
	var conflicts: Array = []
	for moved_room: Room3D in moving.keys():
		var m_pos: Vector3 = moving[moved_room]
		var m_size: Vector3 = new_size if moved_room == primary else moved_room.size
		for child in root.get_children():
			if child in moving: continue
			if not child is Room3D: continue
			var other := child as Room3D
			if SceneQuery.aabbs_overlap(m_pos, m_size, other.position, other.size):
				if SceneQuery.aabb_contains(m_pos, m_size, other.position, other.size): continue
				if SceneQuery.aabb_contains(other.position, other.size, m_pos, m_size): continue
				if other not in conflicts:
					conflicts.append(other)
	return conflicts

func _adjust_doors_for_resize(room: Room3D, new_pos: Vector3, new_size: Vector3) -> void:
	var dx := new_pos.x - room.position.x
	var dz := new_pos.z - room.position.z
	var dy := new_size.y - room.size.y
	if absf(dx) < Room3D.EPSILON and absf(dz) < Room3D.EPSILON and absf(dy) < Room3D.EPSILON: return
	for door in room.door_list:
		match door.side:
			"north", "south":
				door.center_u -= dx
				door.center_v -= dy / 2.0
			"east", "west":
				door.center_u += dz
				door.center_v -= dy / 2.0

func _execute_resize(room: Room3D, new_pos: Vector3, new_size: Vector3, cascade_moves: Array) -> void:
	_resize_conflict_bar.visible = false
	_pending_resize = {}
	_adjust_doors_for_resize(room, new_pos, new_size)
	for m in cascade_moves:
		_adjust_doors_for_resize(m["room"], m["new_pos"], m["room"].size)
	room.position = new_pos
	room.size = new_size
	for m in cascade_moves:
		(m["room"] as Room3D).position = m["new_pos"]
	_refresh()
	var msg := "Resized %s to %.1f×%.1f×%.1f m." % [room.name, new_size.x, new_size.y, new_size.z]
	if not cascade_moves.is_empty():
		msg += " Moved %d connected room%s." % \
				[cascade_moves.size(), "s" if cascade_moves.size() != 1 else ""]
	dock._say_ok(msg)

func _on_resize_confirm() -> void:
	if _pending_resize.is_empty(): return
	_execute_resize(_pending_resize["room"], _pending_resize["pos"],
			_pending_resize["size"], _pending_resize["cascade"])

func _on_resize_cancel() -> void:
	_pending_resize = {}
	_resize_conflict_bar.visible = false
	dock._say("Resize cancelled.")

# --- Move room ---

func _move_set_from_cursor() -> void:
	move_x.value = dock.cursor.x
	move_y.value = dock.cursor.y
	move_z.value = dock.cursor.z
	dock._say("Move target set to cursor: (%.1f, %.1f, %.1f)." % \
			[dock.cursor.x, dock.cursor.y, dock.cursor.z])

func _apply_move() -> void:
	if not dock.current_entity is Room3D:
		dock._say_err("Select a room first."); return
	var room := dock.current_entity as Room3D
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say_err("No scene open."); return

	var new_pos := Vector3(move_x.value, move_y.value, move_z.value)
	var delta := new_pos - room.position
	if delta.length() < Room3D.EPSILON:
		dock._say("Room already at target position."); return

	var cascade_moves: Array = []
	if _move_cascade_checkbox.button_pressed:
		cascade_moves = _collect_move_cascade(room, delta, root, [room])

	var shift_held := Input.is_key_pressed(KEY_SHIFT)

	var overlap_conflicts := _check_all_overlaps(room, new_pos, room.size, cascade_moves, root)
	if not overlap_conflicts.is_empty():
		var names := ", ".join(overlap_conflicts.map(func(r): return (r as Room3D).name))
		if not shift_held:
			dock._say_err("Cannot move room: would overlap with %s. Hold Shift to force." % names)
			return
		dock._say("Warning: overlaps with %s, moving anyway (Shift held)." % names)

	var broken := _check_connections_after_move(room, new_pos, cascade_moves, root)
	if not broken.is_empty():
		var msg := ", ".join(broken.map(func(b): return "%s (%s wall)" % [b["neighbor"].name, b["side"]]))
		if not shift_held:
			dock._say_err("Cannot move room: connection to %s would break. Hold Shift to force." % msg)
			return
		dock._say("Warning: connection to %s broken, moving anyway (Shift held)." % msg)

	_execute_move(room, new_pos, cascade_moves)

func _collect_move_cascade(room: Room3D, delta: Vector3, root: Node, visited: Array) -> Array:
	var result: Array = []
	for side in ["north", "south", "east", "west"]:
		for neighbor: Room3D in dock.scene_query.rooms_flush_with_wall(room, side, root):
			if neighbor in visited: continue
			visited.append(neighbor)
			var n_new_pos := neighbor.position + delta
			result.append({"room": neighbor, "new_pos": n_new_pos})
			var sub := _collect_move_cascade(neighbor, delta, root, visited)
			for m in sub:
				result = result.filter(func(sr): return sr["room"] != m["room"])
				result.append(m)
	return result

func _check_connections_after_move(primary: Room3D, new_pos: Vector3,
		cascade_moves: Array, root: Node) -> Array:
	var moving: Dictionary = {primary: new_pos}
	for m in cascade_moves: moving[m["room"]] = m["new_pos"]

	var broken_keys: Dictionary = {}
	var broken: Array = []
	for moved_room: Room3D in moving.keys():
		var moved_new_pos: Vector3 = moving[moved_room]
		for side in ["north", "south", "east", "west"]:
			for neighbor: Room3D in dock.scene_query.rooms_flush_with_wall(moved_room, side, root):
				if neighbor in moving: continue
				var current_overlap := moved_room._compute_wall_local_overlap(side, neighbor)
				if current_overlap.size.x <= SpatialEntity3D.EPSILON: continue
				for d: DoorEntry in moved_room.door_list:
					if d.side != side: continue
					var door_rect := Rect2(d.center_u - d.width / 2.0,
							d.center_v - d.height / 2.0, d.width, d.height)
					if not door_rect.intersects(current_overlap): continue
					if not _door_still_connects(moved_room, moved_new_pos, side, d, neighbor):
						var key := "%s::%s::%s" % [moved_room.name, neighbor.name, side]
						if broken_keys.has(key): continue
						broken_keys[key] = true
						broken.append({"from": moved_room, "side": side, "neighbor": neighbor})
	return broken

func _door_still_connects(room: Room3D, room_new_pos: Vector3, side: String,
		d: DoorEntry, neighbor: Room3D) -> bool:
	var new_plane := _wall_plane_coord_at(room, side, room_new_pos)
	var neighbor_plane := Room3D._wall_plane_coord(neighbor, _opposite_side(side))
	if absf(new_plane - neighbor_plane) > SpatialEntity3D.EPSILON:
		return false
	var dx := room_new_pos.x - room.position.x
	var dz := room_new_pos.z - room.position.z
	var new_cu := d.center_u
	if side in ["north", "south"]:
		new_cu -= dx
	else:
		new_cu += dz
	var new_overlap := _compute_wall_local_overlap_at(room, side, room_new_pos, neighbor)
	if new_overlap.size.x <= SpatialEntity3D.EPSILON: return false
	if new_overlap.size.y <= SpatialEntity3D.EPSILON: return false
	var new_door_rect := Rect2(new_cu - d.width / 2.0,
			d.center_v - d.height / 2.0, d.width, d.height)
	return new_door_rect.intersects(new_overlap)

static func _opposite_side(side: String) -> String:
	match side:
		"north": return "south"
		"south": return "north"
		"east":  return "west"
		"west":  return "east"
	return ""

static func _wall_plane_coord_at(room: Room3D, side: String, pos: Vector3) -> float:
	match side:
		"north": return pos.z - room.size.z / 2.0
		"south": return pos.z + room.size.z / 2.0
		"east":  return pos.x + room.size.x / 2.0
		"west":  return pos.x - room.size.x / 2.0
	return 0.0

static func _compute_wall_local_overlap_at(room: Room3D, side: String,
		room_pos: Vector3, other: Room3D) -> Rect2:
	# Mirrors Room3D._compute_wall_local_overlap but for a hypothetical room_pos.
	var world_y_lo := maxf(room_pos.y, other.position.y)
	var world_y_hi := minf(room_pos.y + room.size.y, other.position.y + other.size.y)
	if world_y_hi - world_y_lo <= SpatialEntity3D.EPSILON: return Rect2()
	var wall_centre_y := room_pos.y + room.size.y / 2.0
	var v_lo := world_y_lo - wall_centre_y
	var v_hi := world_y_hi - wall_centre_y
	match side:
		"north", "south":
			var x_lo := maxf(room_pos.x - room.size.x / 2.0, other.position.x - other.size.x / 2.0)
			var x_hi := minf(room_pos.x + room.size.x / 2.0, other.position.x + other.size.x / 2.0)
			if x_hi - x_lo <= SpatialEntity3D.EPSILON: return Rect2()
			return Rect2(x_lo - room_pos.x, v_lo, x_hi - x_lo, v_hi - v_lo)
		"east", "west":
			var z_lo := maxf(room_pos.z - room.size.z / 2.0, other.position.z - other.size.z / 2.0)
			var z_hi := minf(room_pos.z + room.size.z / 2.0, other.position.z + other.size.z / 2.0)
			if z_hi - z_lo <= SpatialEntity3D.EPSILON: return Rect2()
			return Rect2(room_pos.z - z_hi, v_lo, z_hi - z_lo, v_hi - v_lo)
	return Rect2()

func _execute_move(room: Room3D, new_pos: Vector3, cascade_moves: Array) -> void:
	_adjust_doors_for_resize(room, new_pos, room.size)
	for m in cascade_moves:
		_adjust_doors_for_resize(m["room"], m["new_pos"], m["room"].size)
	room.position = new_pos
	for m in cascade_moves:
		(m["room"] as Room3D).position = m["new_pos"]
	move_x.value = new_pos.x
	move_y.value = new_pos.y
	move_z.value = new_pos.z
	_refresh()
	var msg := "Moved %s to (%.1f, %.1f, %.1f)." % [room.name, new_pos.x, new_pos.y, new_pos.z]
	if not cascade_moves.is_empty():
		msg += " Dragged %d connected room%s along." % \
				[cascade_moves.size(), "s" if cascade_moves.size() != 1 else ""]
	dock._say_ok(msg)

func _auto_anchor() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var root: Node = dock.scene_query.placement_parent()
	if root == null: return
	var has_n: bool = not dock.scene_query.rooms_flush_with_wall(room, "north", root).is_empty()
	var has_s: bool = not dock.scene_query.rooms_flush_with_wall(room, "south", root).is_empty()
	var has_e: bool = not dock.scene_query.rooms_flush_with_wall(room, "east",  root).is_empty()
	var has_w: bool = not dock.scene_query.rooms_flush_with_wall(room, "west",  root).is_empty()
	var ax := 0.5
	var ay := 0.5
	if has_e and not has_w: ax = 1.0
	elif has_w and not has_e: ax = 0.0
	if has_s and not has_n: ay = 1.0
	elif has_n and not has_s: ay = 0.0
	_set_anchor_to(Vector2(ax, ay))
	var sides: Array = []
	if has_n: sides.append("north")
	if has_s: sides.append("south")
	if has_e: sides.append("east")
	if has_w: sides.append("west")
	if sides.is_empty():
		dock._say("No connected rooms found, anchor kept at center.")
	else:
		dock._say("Anchor set based on connected sides: %s." % ", ".join(sides))

func _set_anchor_to(anchor: Vector2) -> void:
	_resize_anchor = anchor
	var anchor_map := [
		Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(1.0, 0.0),
		Vector2(0.0, 0.5), Vector2(0.5, 0.5), Vector2(1.0, 0.5),
		Vector2(0.0, 1.0), Vector2(0.5, 1.0), Vector2(1.0, 1.0),
	]
	for i in _anchor_buttons.size():
		_anchor_buttons[i].set_block_signals(true)
		_anchor_buttons[i].button_pressed = (anchor_map[i] == anchor)
		_anchor_buttons[i].set_block_signals(false)

func _check_gaps() -> void:
	if dock.scene_query == null: dock._say("No scene open."); return
	_gap_results = dock.scene_query.detect_gaps(_gap_max_spin.value)
	_gap_list.clear()
	if _gap_results.is_empty():
		dock._say_ok("No gaps found within %.1f meters." % _gap_max_spin.value)
		return
	for i in _gap_results.size():
		var g: Dictionary = _gap_results[i]
		var label := "%s (%s) \u2194 %s (%s): %.2fm gap" % [
			g["entity_a"].name, g["wall_a"],
			g["entity_b"].name, g["wall_b"],
			g["gap_distance"]]
		_gap_list.add_item(label)
	dock._say("Found %d gap%s within %.1f meters." % [
		_gap_results.size(), "s" if _gap_results.size() != 1 else "", _gap_max_spin.value])

func _on_gap_selected(i: int) -> void:
	if i < 0 or i >= _gap_results.size(): return
	var g: Dictionary = _gap_results[i]
	dock.cursor = g["midpoint"]
	dock._say("Cursor moved to gap between %s and %s (%.2fm)." % [
		g["entity_a"].name, g["entity_b"].name, g["gap_distance"]])

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)

func _btn_into(c: Control, label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); c.add_child(b)
