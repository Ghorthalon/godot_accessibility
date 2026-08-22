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
var confirm: ConfirmBar
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
	confirm = ConfirmBar.new()
	confirm.dock = dock
	rooms_tab.add_child(confirm)
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
	_move_cascade_checkbox.text = "Cascade move: drag connected rooms"
	_move_cascade_checkbox.tooltip_text = "Translate every room flush-connected to this one by the same delta, keeps L-shaped layouts connected"
	rooms_tab.add_child(_move_cascade_checkbox)
	_btn_into(rooms_tab, "Set from cursor", _move_set_from_cursor)
	_btn_into(rooms_tab, "Preview cascade (no changes)", _preview_move_cascade)
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
	for side in ["floor", "ceiling"]:
		_btn_into(dw_tab, "Punch hole in %s on current (at cursor XZ)" % side, _punch_horizontal.bind(side))

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
	var pos: Vector3 = dock.cursor
	var conflict: String = dock.scene_query.first_overlap(pos, _placement_footprint(size))
	if conflict != "":
		confirm.ask("New room would overlap %s." % conflict, "Place anyway",
				func(): _do_new_room(root, size, pos, "overlapping %s" % conflict))
		return
	_do_new_room(root, size, pos, "")

func _do_new_room(root: Node, size: Vector3, pos: Vector3, caveat: String) -> void:
	var r := Room3D.new()
	r.name = "Room%d" % (root.get_child_count() + 1)
	r.size = size
	_apply_surface_settings(r)
	dock.ops.add_node(root, r, "Create room %s" % r.name, pos)
	dock.current_entity = r
	_refresh()
	var msg := "Created %s, %.1f by %.1f by %.1f meters." % [r.name, r.size.x, r.size.y, r.size.z]
	if caveat != "": msg += " Note: placed %s." % caveat
	dock._say_ok(msg)

func _place_room_from_corners() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say_err("No scene open."); return
	var aabb: AABB = dock.corner_selector.get_aabb()
	var w: float = aabb.size.x; var h: float = aabb.size.y; var d: float = aabb.size.z
	if w < 0.1 or h < 0.1 or d < 0.1:
		dock._say_err("Corners too close in one or more axes, set corner A and corner B first."); return
	var size := Vector3(w, h, d)
	var pos := Vector3(aabb.position.x + w / 2.0, aabb.position.y, aabb.position.z + d / 2.0)
	var conflict: String = dock.scene_query.first_overlap(pos, _placement_footprint(size))
	if conflict != "":
		confirm.ask("Room from corners would overlap %s." % conflict, "Place anyway",
				func(): _do_new_room(root, size, pos, "overlapping %s" % conflict))
		return
	_do_new_room(root, size, pos, "")

func _add_neighbor(side: String) -> void:
	if not dock.current_entity is SpatialEntity3D:
		dock._say("No entity selected. Select a room or ramp first."); return
	var entity := dock.current_entity as SpatialEntity3D
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return

	var new_size := Vector3(new_w.value, new_h.value, new_d.value)
	var entity_pos: Vector3 = (entity as Node3D).global_position
	var new_pos: Vector3 = entity_pos + entity.neighbor_offset(side, new_size)

	# neighbor_offset returns ZERO when the side is invalid for this entity type.
	if new_pos == entity_pos:
		dock._say("Cannot attach a room to the %s side of %s." % [side, entity.name])
		return

	var conflict: String = dock.scene_query.first_overlap(new_pos, _placement_footprint(new_size))
	if conflict != "":
		confirm.ask("A room to the %s of %s would overlap %s." % [side, entity.name, conflict],
				"Add anyway",
				func(): _do_add_neighbor(entity, side, root, new_size, new_pos, conflict))
		return
	_do_add_neighbor(entity, side, root, new_size, new_pos, "")

func _do_add_neighbor(entity: SpatialEntity3D, side: String, root: Node,
		new_size: Vector3, new_pos: Vector3, conflict: String) -> void:
	var r := Room3D.new()
	r.name = "%s_%s" % [entity.name, side]
	r.size = new_size

	# Configure the new room's doorway BEFORE it enters the tree so that
	# add_doorway's internal _queue_rebuild is a no op (is_inside_tree = false)
	# and only the post-insert rebuild runs.
	var back_side: String = entity.neighbor_doorway_side(side)
	var new_floor_t: float = r.wall_floor.thickness if r.wall_floor else 0.0
	var cv_new: float = 0.0
	if back_side != "":
		cv_new = -r.size.y / 2.0 + door_h.value / 2.0 + new_floor_t
		r.add_doorway(back_side, 0.0, cv_new, door_w.value, door_h.value)
	_apply_surface_settings(r)

	# One transaction: the new room, both doorways and both placeholders undo together.
	dock.ops.begin("Add room %s to %s of %s" % [r.name, side, entity.name])
	dock.ops.add_child_node(root, r, new_pos)
	if back_side != "" and not r.door_list.is_empty():
		_add_door_placeholder(r, r.door_list[0], new_pos, new_size)
	if entity.has_wall(side):
		var cur_room := entity as Room3D
		var cur_floor_t: float = cur_room.wall_floor.thickness if cur_room.wall_floor else 0.0
		var cv_cur: float = -cur_room.size.y / 2.0 + door_h.value / 2.0 + cur_floor_t
		var u_off: float = _overlap_center_u_at(cur_room, cur_room.global_position,
				new_pos, new_size, side)
		_record_doorway(cur_room, side, u_off, cv_cur, door_w.value, door_h.value)
	dock.ops.commit()

	dock.current_entity = r
	_refresh()
	var msg := "Added room %s to %s of %s, connected by doorway." % [r.name, side, entity.name]
	if conflict != "": msg += " Note: it overlaps %s." % conflict
	dock._say_ok(msg)
	_refresh_door_list()

func _punch(side: String) -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var floor_t: float = room.wall_floor.thickness if room.wall_floor else 0.0
	var cv := -room.size.y / 2.0 + door_h.value / 2.0 + floor_t
	_commit_doorway(room, side, 0.0, cv, door_w.value, door_h.value,
			"Punch doorway on %s wall of %s" % [side, room.name])
	dock._say_ok("Doorway punched on %s wall of %s (%.1fm by %.1fm)." % [side, room.name, door_w.value, door_h.value])

## Builds the placeholder node for a doorway and registers it with the OPEN
## EditOps transaction, so it appears and disappears together with its doorway.
## room_pos/room_size are passed explicitly because the room may not be in the
## tree yet (a neighbour being created), where global_position still reads zero.
func _add_door_placeholder(room: Room3D, door: DoorEntry,
		room_pos: Vector3, room_size: Vector3) -> void:
	if not create_door_placeholder.button_pressed: return
	if door.side in ["floor", "ceiling"]: return
	var placeholder := Node3D.new()
	placeholder.name = "DoorPlaceholder_%s" % door.side
	placeholder.set_meta("door_placeholder", true)
	# Stable identity, plus the coordinate metas kept for the legacy fallback.
	placeholder.set_meta("door_id", door.ensure_id())
	placeholder.set_meta("door_side", door.side)
	placeholder.set_meta("door_cu", door.center_u)
	placeholder.set_meta("door_cv", door.center_v)
	placeholder.visible = false
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(door.width, door.height, 0.1)
	mesh_inst.mesh = box
	placeholder.add_child(mesh_inst)
	var xform := SceneQuery.wall_facing_transform_at(room_pos, room_size,
			door.side, door.center_u, door.center_v)
	dock.ops.add_child_node(room, placeholder, xform)

## Records one new doorway on room inside the OPEN transaction, placeholder
## included. The whole door_list is swapped rather than appended to, so undo
## cannot be confused by indices shifting underneath it.
func _record_doorway(room: Room3D, side: String, cu: float, cv: float,
		w: float, h: float) -> void:
	var before := EditOps.copy_doors(room)
	var after := EditOps.copy_doors(room)
	var d := DoorEntry.new()
	d.side = side; d.center_u = cu; d.center_v = cv
	d.width = w; d.height = h
	d.ensure_id()
	after.append(d)
	dock.ops.swap_doors(room, before, after)
	_add_door_placeholder(room, d, room.global_position, room.size)

## Single-doorway convenience: opens its own transaction around _record_doorway.
func _commit_doorway(room: Room3D, side: String, cu: float, cv: float,
		w: float, h: float, action_name: String) -> void:
	dock.ops.begin(action_name)
	_record_doorway(room, side, cu, cv, w, h)
	dock.ops.commit()
	_refresh_door_list()

## Records placeholder transform fixups into the OPEN transaction.
## The value is a LOCAL transform against the room's new position: a placeholder
## is a child of its room, so the local transform is what actually persists, and
## recording it that way lets prop() capture a correct undo value.
func _record_placeholder_fixups(fixups: Array) -> void:
	for f in fixups:
		var node: Node3D = f["node"]
		if is_instance_valid(node):
			dock.ops.prop(node, "transform", f["local"])

## Finds the placeholder belonging to door on room, or null.
##
## Matches on the door's stable id first. The float-coordinate comparison is
## kept only as a fallback for placeholders created before ids existed, so old
## scenes keep working; it is not reliable once a door has been edited.
func _find_door_placeholder(room: Room3D, door: DoorEntry) -> Node3D:
	var wanted := door.id
	if not wanted.is_empty():
		for c in room.get_children():
			if not c.has_meta("door_placeholder"): continue
			if str(c.get_meta("door_id", "")) == wanted:
				return c as Node3D
	for c in room.get_children():
		if not c.has_meta("door_placeholder"): continue
		if c.has_meta("door_id") and str(c.get_meta("door_id", "")) != "": continue
		if str(c.get_meta("door_side", "")) != door.side: continue
		if absf(float(c.get_meta("door_cu", INF)) - door.center_u) > 0.01: continue
		if absf(float(c.get_meta("door_cv", INF)) - door.center_v) > 0.01: continue
		return c as Node3D
	return null

func _apply_resize() -> void:
	if dock.current_entity == null: dock._say("No entity selected."); return
	confirm.dismiss()

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
		cascade_moves = _collect_cascade(room, room.global_position, room.size, new_pos, new_size, [room])

	var conflicts := _check_all_overlaps(room, new_pos, new_size, cascade_moves)
	if not conflicts.is_empty():
		var names := ", ".join(conflicts.map(func(r): return (r as Node).name))
		confirm.ask("Resizing %s would overlap %s." % [room.name, names], "Resize anyway",
				func(): _execute_resize(room, new_pos, new_size, cascade_moves))
		return

	_execute_resize(room, new_pos, new_size, cascade_moves)

func _refresh() -> void:
	room_list.clear()
	if dock.scene_query == null or dock.scene_query.edited_root() == null: return
	# A freed entity must not stay as the operation target: buttons would act on
	# a dangling reference with no way for the user to tell.
	if dock.current_entity != null and not is_instance_valid(dock.current_entity):
		dock.current_entity = null
	for c in dock.scene_query.entities_in_scene():
		if not c is SpatialEntity3D: continue
		var entity := c as SpatialEntity3D
		var label: String = dock.scene_query.entity_label(entity)
		var suffix := _connection_suffix(entity)
		if suffix != "": label += " " + suffix
		room_list.add_item(label)
		room_list.set_item_metadata(room_list.item_count - 1, entity)
	# Restore the highlight. Without this the list reads as "nothing selected"
	# while current_entity is still live, so what the user hears and what the
	# buttons act on drift apart.
	select_entity_in_list(dock.current_entity)

## Highlights entity's row without re-running _on_select's side effects
## (rebuilding the property UI, playing the locator sound, announcing).
func select_entity_in_list(entity: SpatialEntity3D) -> void:
	if entity == null or not is_instance_valid(entity):
		room_list.deselect_all()
		return
	for i in room_list.item_count:
		if room_list.get_item_metadata(i) == entity:
			room_list.select(i)
			room_list.ensure_current_is_visible()
			return
	room_list.deselect_all()

## Called when the editor selection changes, so a room picked in the scene tree
## or the viewport becomes the addon's operation target too. Without this the
## target only ever follows the addon's own list and silently diverges from
## what the user believes is selected.
func sync_to_entity(entity: SpatialEntity3D) -> void:
	if entity == null or entity == dock.current_entity: return
	dock.current_entity = entity
	select_entity_in_list(entity)
	confirm.dismiss()
	_populate_entity_panels(entity)

## Fills the resize/move/door/wall panels for entity. Shared by list selection
## and editor-selection sync so the two can never disagree.
func _populate_entity_panels(entity: SpatialEntity3D) -> void:
	for child in _resize_container.get_children():
		child.queue_free()
	await get_tree().process_frame
	entity.populate_properties_ui(_resize_container)
	if entity is Room3D:
		# World coordinates: must match _move_set_from_cursor and _apply_move.
		move_x.value = (entity as Node3D).global_position.x
		move_y.value = (entity as Node3D).global_position.y
		move_z.value = (entity as Node3D).global_position.z
	_refresh_door_list()
	_refresh_wall_list()
	_refresh_connection_list(entity)

## Describes the sticky settings that silently change what the next resize or
## move will do. Announced on every selection so a toggle set an hour ago
## cannot ambush the user.
func _sticky_state_summary() -> String:
	var anchor_names := {
		Vector2(0.0, 0.0): "northwest", Vector2(0.5, 0.0): "north", Vector2(1.0, 0.0): "northeast",
		Vector2(0.0, 0.5): "west", Vector2(0.5, 0.5): "center", Vector2(1.0, 0.5): "east",
		Vector2(0.0, 1.0): "southwest", Vector2(0.5, 1.0): "south", Vector2(1.0, 1.0): "southeast",
	}
	var parts: Array[String] = ["resize anchor %s" % anchor_names.get(_resize_anchor, "center")]
	if _cascade_checkbox.button_pressed: parts.append("cascade resize on")
	if _move_cascade_checkbox.button_pressed: parts.append("cascade move on")
	return ", ".join(parts)

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
	confirm.dismiss()
	var detail := ""
	if entity is Room3D: detail = " " + (entity as Room3D).interior_report() + "."
	dock._say("Selected %s.%s %s." % [dock.scene_query.entity_label(entity), detail, _sticky_state_summary()])
	dock.play_audio_3d("object", (entity as Node3D).global_position)
	_populate_entity_panels(entity)

func _bake_scene() -> void:
	var root: Node = dock.scene_query.edited_root()
	if root == null: dock._say("No scene open."); return
	var entities: Array[SpatialEntity3D] = BakeEngine.collect_entities(root)
	if entities.is_empty(): dock._say("No spatial entities found."); return
	# Baking in place replaces every editable room, ramp and stairs in THIS scene
	# with fixed meshes: sizes, doorways and wall settings stop being editable.
	# Never do that on a single button press without saying so first.
	var shown := entities.slice(0, 5).map(func(e): return (e as Node).name)
	var names := ", ".join(shown)
	if entities.size() > 5: names += " and %d more" % (entities.size() - 5)
	var question := "Bake in place replaces %d editable entit%s (%s) with fixed meshes in this scene. Bake to file instead if you want to keep this one editable." % [entities.size(), "ies" if entities.size() != 1 else "y", names]
	confirm.ask(question, "Bake and replace", _do_bake_scene)

func _do_bake_scene() -> void:
	var root: Node = dock.scene_query.edited_root()
	if root == null: dock._say("No scene open."); return
	var entities: Array[SpatialEntity3D] = BakeEngine.collect_entities(root)
	if entities.is_empty(): dock._say("No spatial entities found."); return
	var count := BakeEngine.bake_in_place(entities, root, dock.ops)
	dock.current_entity = null
	_refresh()
	dock._say_ok("Baked %d spatial entit%s with merged meshes and optimised collision. Press Control Z to bring the editable version back." % [count, "ies" if count != 1 else "y"])

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
	var root: Node = dock.scene_query.edited_root()
	if root == null: dock._say("No scene open."); return
	var count := BakeEngine.collect_entities(root).size()
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
	var local_v: float = cur.y - (room.global_position.y + room.size.y / 2.0)
	var local_u: float
	match side:
		"north", "south":
			local_u = cur.x - room.global_position.x
		"east", "west":
			local_u = room.global_position.z - cur.z
	_commit_doorway(room, side, local_u, local_v, door_w.value, door_h.value,
			"Punch doorway on %s wall of %s" % [side, room.name])
	_refresh()
	dock._say_ok("Door punched on %s wall of %s at offset %.1f, %.1f (%.1fm by %.1fm)." % [side, room.name, local_u, local_v, door_w.value, door_h.value])

func _punch_hole_at_cursor() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var cur: Vector3 = dock.cursor
	var side: String = _closest_surface(room, cur)
	var local_u: float
	var local_v: float
	match side:
		"north", "south":
			local_u = cur.x - room.global_position.x
			local_v = cur.y - (room.global_position.y + room.size.y / 2.0)
		"east", "west":
			local_u = room.global_position.z - cur.z
			local_v = cur.y - (room.global_position.y + room.size.y / 2.0)
		"floor", "ceiling":
			local_u = cur.x - room.global_position.x
			local_v = room.global_position.z - cur.z
	_commit_doorway(room, side, local_u, local_v, door_w.value, door_h.value,
			"Punch hole in %s of %s" % [side, room.name])
	_refresh()
	dock._say_ok("Hole punched on %s of %s at offset %.1f, %.1f (%.1fm by %.1fm)." % [side, room.name, local_u, local_v, door_w.value, door_h.value])

func _punch_horizontal(side: String) -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var cur: Vector3 = dock.cursor
	var local_u: float = cur.x - room.global_position.x
	var local_v: float = room.global_position.z - cur.z
	_commit_doorway(room, side, local_u, local_v, door_w.value, door_h.value,
			"Punch hole in %s of %s" % [side, room.name])
	_refresh()
	dock._say_ok("Hole punched in %s of %s at room-local (%.1f, %.1f) (%.1fm by %.1fm)." % [side, room.name, local_u, local_v, door_w.value, door_h.value])

func _closest_wall(room: Room3D, cur: Vector3) -> String:
	var rp := room.global_position; var rs := room.size
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

func _closest_surface(room: Room3D, cur: Vector3) -> String:
	var rp := room.global_position; var rs := room.size
	var dists := {
		"north":   abs(cur.z - (rp.z - rs.z/2)),
		"south":   abs(cur.z - (rp.z + rs.z/2)),
		"east":    abs(cur.x - (rp.x + rs.x/2)),
		"west":    abs(cur.x - (rp.x - rs.x/2)),
		"floor":   abs(cur.y - rp.y),
		"ceiling": abs(cur.y - (rp.y + rs.y)),
	}
	var best := "north"
	for s in dists:
		if dists[s] < dists[best]: best = s
	return best

func _overlap_center_u(a: Room3D, b: Room3D, side: String) -> float:
	return _overlap_center_u_at(a, a.global_position, b.global_position, b.size, side)

## Position-explicit form, for a neighbour room that is not in the tree yet and
## whose global_position therefore still reads as zero.
func _overlap_center_u_at(a: Room3D, a_pos: Vector3, b_pos: Vector3,
		b_size: Vector3, side: String) -> float:
	if side in ["north", "south"]:
		var lo := maxf(a_pos.x - a.size.x/2, b_pos.x - b_size.x/2)
		var hi := minf(a_pos.x + a.size.x/2, b_pos.x + b_size.x/2)
		return ((lo + hi) / 2.0) - a_pos.x
	else:
		var lo := maxf(a_pos.z - a.size.z/2, b_pos.z - b_size.z/2)
		var hi := minf(a_pos.z + a.size.z/2, b_pos.z + b_size.z/2)
		return a_pos.z - ((lo + hi) / 2.0)

func _measure_space_at_cursor() -> void:
	var space: Dictionary = dock.scene_query.measure_space(dock.cursor)
	dock._say("Space at cursor: north %.1fm, south %.1fm, east %.1fm, west %.1fm, up %.1fm, down %.1fm." % \
		[space["north"], space["south"], space["east"], space["west"], space["up"], space["down"]])

func _resize_fill_ew() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var sq: SceneQuery = dock.scene_query
	# Cast from just outside each wall to avoid hitting the room's own geometry.
	var ha = sq.raycast_direction(room.global_position + Vector3.RIGHT * (room.size.x / 2.0 + 0.05), Vector3.RIGHT)
	var hb = sq.raycast_direction(room.global_position + Vector3.LEFT  * (room.size.x / 2.0 + 0.05), Vector3.LEFT)
	if ha == null or hb == null: dock._say("Could not find walls on both east and west sides."); return
	var new_size := room.size
	new_size.x = (ha as Vector3).x - (hb as Vector3).x
	var new_pos := room.global_position
	new_pos.x = ((ha as Vector3).x + (hb as Vector3).x) / 2.0
	_execute_resize(room, new_pos, new_size, [])
	dock._say_ok("Room %s width set to %.1fm to fill east-west space. Press Control Z to undo." % [room.name, new_size.x])

func _resize_fill_ns() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var sq: SceneQuery = dock.scene_query
	# Cast from just outside each wall to avoid hitting the room's own geometry.
	var ha = sq.raycast_direction(room.global_position + Vector3.BACK    * (room.size.z / 2.0 + 0.05), Vector3.BACK)
	var hb = sq.raycast_direction(room.global_position + Vector3.FORWARD * (room.size.z / 2.0 + 0.05), Vector3.FORWARD)
	if ha == null or hb == null: dock._say("Could not find walls on both north and south sides."); return
	var new_size := room.size
	new_size.z = (ha as Vector3).z - (hb as Vector3).z
	var new_pos := room.global_position
	new_pos.z = ((ha as Vector3).z + (hb as Vector3).z) / 2.0
	_execute_resize(room, new_pos, new_size, [])
	dock._say_ok("Room %s depth set to %.1fm to fill north-south space. Press Control Z to undo." % [room.name, new_size.z])

func _door_list_owner() -> Object:
	var e = dock.current_entity
	if e is Room3D: return e
	return null

func _door_list_sides() -> Array:
	return ["north", "south", "east", "west", "floor", "ceiling"]

func _refresh_door_list() -> void:
	_door_item_list.clear()
	_current_door_idx = -1
	for c in _door_props_container.get_children(): c.queue_free()
	var owner_obj = _door_list_owner()
	if owner_obj == null: return
	var doors: Array = owner_obj.door_list
	if doors.is_empty(): return
	for i in doors.size():
		var d: DoorEntry = doors[i]
		var name_part := ("\"%s\" " % d.label) if d.label != "" else ""
		var scene_part := " [filled]" if d.scene_path != "" else " [empty]"
		_door_item_list.add_item("[%d] %s%s  U:%.2f V:%.2f  %.1f×%.1fm%s" % [i, name_part, d.side, d.center_u, d.center_v, d.width, d.height, scene_part])
		_door_item_list.set_item_metadata(i, i)

func _on_door_select(i: int) -> void:
	var owner_obj = _door_list_owner()
	if owner_obj == null: return
	_current_door_idx = _door_item_list.get_item_metadata(i)
	if _current_door_idx < 0 or _current_door_idx >= owner_obj.door_list.size(): return
	var d: DoorEntry = owner_obj.door_list[_current_door_idx]
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
	for s in _door_list_sides():
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
	var owner_obj = _door_list_owner()
	if owner_obj == null or _current_door_idx < 0:
		dock._say("No door selected."); return
	if _current_door_idx >= owner_obj.door_list.size():
		dock._say("Door index out of range."); return
	var d: DoorEntry = owner_obj.door_list[_current_door_idx]
	var before := EditOps.copy_doors(owner_obj as Room3D)
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

	# d was mutated in place above; `before` was taken first, so the swap gives
	# undo the original list and redo the edited one.
	var room_obj := owner_obj as Room3D
	dock.ops.begin("Edit door %d on %s" % [_current_door_idx, room_obj.name])
	dock.ops.swap_doors(room_obj, before, EditOps.copy_doors(room_obj))
	_sync_door_placeholder(room_obj, d)
	dock.ops.commit()
	_refresh_door_list()
	dock._say_ok("Door %d on %s updated. Press Control Z to undo." % [_current_door_idx, room_obj.name])

## Moves the door's placeholder to match an edited DoorEntry, or removes it when
## the door moved to the floor/ceiling (placeholders are wall-only).
func _sync_door_placeholder(room: Room3D, d: DoorEntry) -> void:
	var placeholder := _find_door_placeholder(room, d)
	if placeholder == null: return
	if d.side in ["floor", "ceiling"]:
		# Placeholders are wall-only. Removing rather than freeing keeps the node
		# recoverable, so undoing the door edit brings it back.
		dock.ops.remove_child_node(placeholder)
		return
	dock.ops.prop(placeholder, "name", "DoorPlaceholder_%s" % d.side)
	dock.ops.meta(placeholder, "door_id", d.ensure_id())
	dock.ops.meta(placeholder, "door_side", d.side)
	dock.ops.meta(placeholder, "door_cu", d.center_u)
	dock.ops.meta(placeholder, "door_cv", d.center_v)
	var world_xf: Transform3D = dock.scene_query.wall_facing_transform(room, d.side, d.center_u, d.center_v)
	dock.ops.prop(placeholder, "transform",
			Transform3D(world_xf.basis, world_xf.origin - room.global_position))
	for c in placeholder.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			dock.ops.prop((c as MeshInstance3D).mesh, "size", Vector3(d.width, d.height, 0.1))
			break

func _place_door_scene() -> void:
	var owner_obj = _door_list_owner()
	if owner_obj == null or _current_door_idx < 0:
		dock._say("No door selected."); return
	if _current_door_idx >= owner_obj.door_list.size():
		dock._say("Door index out of range."); return
	var door_idx := _current_door_idx
	# Persist any pending field edits (including scene path) before placing.
	# _apply_door_changes calls _refresh_door_list which resets _current_door_idx to -1,
	# so the index must be captured first.
	_apply_door_changes()
	var d: DoorEntry = owner_obj.door_list[door_idx]
	if d.scene_path == "":
		dock._say("Set a scene path on this door first."); return
	if not ResourceLoader.exists(d.scene_path):
		dock._say_err("Scene not found: %s" % d.scene_path); return
	var packed := load(d.scene_path) as PackedScene
	if packed == null: dock._say_err("Failed to load scene."); return

	var room: Room3D = owner_obj as Room3D
	var room_side: String = d.side

	var tf: Transform3D = dock.scene_query.wall_facing_transform(room, room_side, d.center_u, d.center_v)
	dock.tab_place.instantiate_aligned(packed, tf, room,
		"door %d (%s wall of %s)" % [door_idx, room_side, room.name])

func _remove_selected_door() -> void:
	var owner_obj = _door_list_owner()
	if owner_obj == null or _current_door_idx < 0:
		dock._say("No door selected."); return
	if _current_door_idx >= owner_obj.door_list.size():
		dock._say("Door index out of range."); return
	var room := owner_obj as Room3D
	var idx := _current_door_idx
	var d: DoorEntry = room.door_list[idx]
	var placeholder := _find_door_placeholder(room, d)
	var before := EditOps.copy_doors(room)
	var after := EditOps.copy_doors(room)
	after.remove_at(idx)
	dock.ops.begin("Remove door %d from %s" % [idx, room.name])
	dock.ops.swap_doors(room, before, after)
	if placeholder != null:
		dock.ops.remove_child_node(placeholder)
	dock.ops.commit()
	_refresh_door_list()
	dock._say_ok("Removed door %d from %s. Press Control Z to undo." % [idx, room.name])

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
	dock.ops.begin("Edit %s wall of %s" % [_current_wall_side, room.name])
	dock.ops.prop(wc, "enabled", enabled_cb.button_pressed)
	dock.ops.prop(wc, "surface", surf_edit.text.strip_edges())
	dock.ops.prop(wc, "thickness", thickness_spin.value)
	# WallConfig is a plain Resource: script assignment does not emit `changed`,
	# so the rebuild has to be requested explicitly on both do and undo.
	dock.ops.refresh(room, "_queue_rebuild")
	dock.ops.commit()
	_refresh_wall_list()
	dock._say_ok("%s wall of %s updated, surface: %s, thickness: %.2fm, %s. Press Control Z to undo." % [_current_wall_side, room.name, wc.surface, wc.thickness, "enabled" if wc.enabled else "disabled"])

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
	_cascade_checkbox.text = "Cascade resize: push connected rooms"
	_cascade_checkbox.tooltip_text = "When growing, recursively push rooms flush with the growing wall"
	c.add_child(_cascade_checkbox)

func _anchor_position(room: Room3D, new_size: Vector3, anchor: Vector2) -> Vector3:
	# World-space. anchor.x: 0=west edge fixed, 0.5=center, 1=east edge fixed
	# anchor.y: 0=north edge fixed, 0.5=center, 1=south edge fixed
	var ax := room.global_position.x + (anchor.x - 0.5) * room.size.x
	var az := room.global_position.z + (anchor.y - 0.5) * room.size.z
	return Vector3(ax - (anchor.x - 0.5) * new_size.x, room.global_position.y,
			az - (anchor.y - 0.5) * new_size.z)

func _collect_cascade(room: Room3D, old_pos: Vector3, old_size: Vector3,
		new_pos: Vector3, new_size: Vector3, visited: Array) -> Array:
	# All positions are world-space (global_position).
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
		for neighbor: Room3D in dock.scene_query.rooms_flush_with_wall(room, side):
			if neighbor in visited: continue
			var n_new_pos := neighbor.global_position + axis * delta
			result = result.filter(func(m): return m["room"] != neighbor)
			result.append({"room": neighbor, "new_pos": n_new_pos})
			visited.append(neighbor)
			var sub := _collect_cascade(neighbor, neighbor.global_position, neighbor.size,
					n_new_pos, neighbor.size, visited)
			for m in sub:
				result = result.filter(func(sr): return sr["room"] != m["room"])
				result.append(m)
	return result

func _check_all_overlaps(primary: Room3D, new_pos: Vector3, new_size: Vector3,
		cascade_moves: Array) -> Array:
	# All positions are world-space; checks every entity in the scene, nested or not.
	var moving: Dictionary = {primary: new_pos}
	for m in cascade_moves:
		moving[m["room"]] = m["new_pos"]
	var conflicts: Array = []
	for moved_room: Room3D in moving.keys():
		var m_pos: Vector3 = moving[moved_room]
		var m_size: Vector3 = new_size if moved_room == primary else moved_room.size
		for child in dock.scene_query.entities_in_scene():
			if child in moving: continue
			if not child is SpatialEntity3D: continue
			var other_pos: Vector3 = (child as Node3D).global_position
			var other_size: Vector3 = dock.scene_query._entity_footprint(child as SpatialEntity3D)
			if other_size == Vector3.ZERO: continue
			if SceneQuery.aabbs_overlap(m_pos, m_size, other_pos, other_size):
				if SceneQuery.aabb_contains(m_pos, m_size, other_pos, other_size): continue
				if SceneQuery.aabb_contains(other_pos, other_size, m_pos, m_size): continue
				if child not in conflicts:
					conflicts.append(child)
	return conflicts

func _adjust_doors_for_resize(room: Room3D, new_pos: Vector3, new_size: Vector3) -> Array:
	# new_pos is world-space; keeps each opening at its world position.
	# Returns placeholder fixups [{node, xform}] to re-apply AFTER the room has
	# actually moved, so placeholders stay world-pinned with their doorways.
	var fixups: Array = []
	var dx := new_pos.x - room.global_position.x
	var dz := new_pos.z - room.global_position.z
	var dy := new_size.y - room.size.y
	if absf(dx) < Room3D.EPSILON and absf(dz) < Room3D.EPSILON and absf(dy) < Room3D.EPSILON: return fixups
	for door in room.door_list:
		var placeholder := _find_door_placeholder(room, door)
		match door.side:
			"north", "south":
				door.center_u -= dx
				door.center_v -= dy / 2.0
			"east", "west":
				door.center_u += dz
				door.center_v -= dy / 2.0
			"floor", "ceiling":
				# u = world_x - pos.x, v = pos.z - world_z (see _punch_horizontal)
				door.center_u -= dx
				door.center_v += dz
		if placeholder != null:
			dock.ops.meta(placeholder, "door_cu", door.center_u)
			dock.ops.meta(placeholder, "door_cv", door.center_v)
			var world_xf := placeholder.global_transform
			fixups.append({"node": placeholder,
					"local": Transform3D(world_xf.basis, world_xf.origin - new_pos)})
	return fixups

func _execute_resize(room: Room3D, new_pos: Vector3, new_size: Vector3, cascade_moves: Array) -> void:
	confirm.dismiss()
	var action := "Resize %s" % room.name
	if not cascade_moves.is_empty():
		action += " and push %d connected room%s" % [cascade_moves.size(), "s" if cascade_moves.size() != 1 else ""]

	# Door lists are captured before the adjust pass mutates them in place, so
	# the whole group -- geometry, doorways and placeholders -- is one undo step.
	var affected: Array[Room3D] = [room]
	for m in cascade_moves: affected.append(m["room"] as Room3D)
	var doors_before: Dictionary = {}
	for r: Room3D in affected: doors_before[r] = EditOps.copy_doors(r)

	dock.ops.begin(action)
	# Positions/sizes are recorded first: prop() reads the CURRENT value for the
	# undo side, so it must run before anything actually moves.
	dock.ops.prop(room, "global_position", new_pos)
	dock.ops.prop(room, "size", new_size)
	for m in cascade_moves:
		dock.ops.prop(m["room"], "global_position", m["new_pos"])

	var fixups: Array = _adjust_doors_for_resize(room, new_pos, new_size)
	for m in cascade_moves:
		fixups += _adjust_doors_for_resize(m["room"], m["new_pos"], m["room"].size)
	for r: Room3D in affected:
		dock.ops.swap_doors(r, doors_before[r], EditOps.copy_doors(r))
	_record_placeholder_fixups(fixups)
	dock.ops.commit()

	# Keep the move fields in step with where the room actually ended up. A
	# non-centre anchor moves the room, and a stale value here would make the
	# next "Apply move" silently teleport it back.
	move_x.value = new_pos.x
	move_y.value = new_pos.y
	move_z.value = new_pos.z
	_refresh()
	var msg := "Resized %s to %.1f by %.1f by %.1f m." % [room.name, new_size.x, new_size.y, new_size.z]
	if not cascade_moves.is_empty():
		msg += " Moved %d connected room%s." % [cascade_moves.size(), "s" if cascade_moves.size() != 1 else ""]
	msg += " Press Control Z to undo."
	dock._say_ok(msg)

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
	confirm.dismiss()

	var new_pos := Vector3(move_x.value, move_y.value, move_z.value)
	var delta := new_pos - room.global_position
	if delta.length() < Room3D.EPSILON:
		dock._say("Room already at target position."); return

	var cascade_moves: Array = []
	if _move_cascade_checkbox.button_pressed:
		cascade_moves = _collect_move_cascade(room, delta, [room])

	# Both hazards are gathered first so the user hears the full cost of the
	# move in one question rather than being asked twice.
	var warnings: Array[String] = []
	var overlap_conflicts := _check_all_overlaps(room, new_pos, room.size, cascade_moves)
	if not overlap_conflicts.is_empty():
		warnings.append("it would overlap %s" % ", ".join(overlap_conflicts.map(func(r): return (r as Node).name)))
	var broken := _check_connections_after_move(room, new_pos, cascade_moves)
	if not broken.is_empty():
		warnings.append("%d doorway connection%s would be destroyed: %s" % [
				broken.size(), "s" if broken.size() != 1 else "",
				", ".join(broken.map(_describe_broken_connection))])

	if not warnings.is_empty():
		var msg := "Moving %s: %s." % [room.name, " and ".join(warnings)]
		if not broken.is_empty():
			msg += " Openings pushed off a wall are discarded, not clamped."
		confirm.ask(msg, "Move anyway", func(): _execute_move(room, new_pos, cascade_moves))
		return

	_execute_move(room, new_pos, cascade_moves)

## Names the specific doorways a move would destroy, not merely the rooms, so
## the warning says what is actually lost.
func _describe_broken_connection(b: Dictionary) -> String:
	var from_room: Room3D = b["from"]
	var side: String = b["side"]
	var neighbor: Room3D = b["neighbor"]
	var labels: Array[String] = []
	for d: DoorEntry in from_room.door_list:
		if d.side != side: continue
		labels.append("\"%s\"" % d.label if d.label != "" else "%.1fm by %.1fm" % [d.width, d.height])
	var door_part := " (%s)" % ", ".join(labels) if not labels.is_empty() else ""
	return "%s %s wall to %s%s" % [from_room.name, side, neighbor.name, door_part]

## Read-only: reports how far a cascade move would reach without changing
## anything, so the blast radius is knowable before it happens.
func _preview_move_cascade() -> void:
	if not dock.current_entity is Room3D:
		dock._say("Select a room first."); return
	var room := dock.current_entity as Room3D
	if not _move_cascade_checkbox.button_pressed:
		dock._say("Cascade move is off, only %s would move." % room.name); return
	var new_pos := Vector3(move_x.value, move_y.value, move_z.value)
	var delta := new_pos - room.global_position
	if delta.length() < Room3D.EPSILON:
		dock._say("Room already at target position, nothing would move."); return
	var cascade_moves: Array = _collect_move_cascade(room, delta, [room])
	if cascade_moves.is_empty():
		dock._say("Cascade move would drag nothing extra, %s has no flush neighbours." % room.name)
		return
	var names := ", ".join(cascade_moves.map(func(m): return (m["room"] as Room3D).name))
	dock._say("Cascade move would drag %d room%s along with %s: %s. Nothing has changed yet." % [
			cascade_moves.size(), "s" if cascade_moves.size() != 1 else "", room.name, names])

func _collect_move_cascade(room: Room3D, delta: Vector3, visited: Array) -> Array:
	var result: Array = []
	for side in ["north", "south", "east", "west"]:
		for neighbor: Room3D in dock.scene_query.rooms_flush_with_wall(room, side):
			if neighbor in visited: continue
			visited.append(neighbor)
			var n_new_pos := neighbor.global_position + delta
			result.append({"room": neighbor, "new_pos": n_new_pos})
			var sub := _collect_move_cascade(neighbor, delta, visited)
			for m in sub:
				result = result.filter(func(sr): return sr["room"] != m["room"])
				result.append(m)
	return result

func _check_connections_after_move(primary: Room3D, new_pos: Vector3,
		cascade_moves: Array) -> Array:
	var moving: Dictionary = {primary: new_pos}
	for m in cascade_moves: moving[m["room"]] = m["new_pos"]

	var broken_keys: Dictionary = {}
	var broken: Array = []
	for moved_room: Room3D in moving.keys():
		var moved_new_pos: Vector3 = moving[moved_room]
		for side in ["north", "south", "east", "west"]:
			for neighbor: Room3D in dock.scene_query.rooms_flush_with_wall(moved_room, side):
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
				# Also check neighbor's doors on the shared plane, they may be the only
				# DoorEntry on a wall opened from one side only.
				var opp_side := _opposite_side(side)
				for d: DoorEntry in neighbor.door_list:
					if d.side != opp_side: continue
					var nb_overlap := _compute_wall_local_overlap_at2(
						neighbor, opp_side, neighbor.global_position, moved_room, moved_room.global_position)
					var door_rect := Rect2(d.center_u - d.width / 2.0,
							d.center_v - d.height / 2.0, d.width, d.height)
					if not door_rect.intersects(nb_overlap): continue  # wasn't connected before move
					var new_nb_overlap := _compute_wall_local_overlap_at2(
						neighbor, opp_side, neighbor.global_position, moved_room, moved_new_pos)
					if new_nb_overlap.size.x <= SpatialEntity3D.EPSILON or \
							not door_rect.intersects(new_nb_overlap):
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
	var dx := room_new_pos.x - room.global_position.x
	var dz := room_new_pos.z - room.global_position.z
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
	return _compute_wall_local_overlap_at2(room, side, room_pos, other, other.global_position)

static func _compute_wall_local_overlap_at2(room: Room3D, side: String,
		room_pos: Vector3, other: Room3D, other_pos: Vector3) -> Rect2:
	# Mirrors Room3D._compute_wall_local_overlap but both rooms at explicit positions.
	var world_y_lo := maxf(room_pos.y, other_pos.y)
	var world_y_hi := minf(room_pos.y + room.size.y, other_pos.y + other.size.y)
	if world_y_hi - world_y_lo <= SpatialEntity3D.EPSILON: return Rect2()
	var wall_centre_y := room_pos.y + room.size.y / 2.0
	var v_lo := world_y_lo - wall_centre_y
	var v_hi := world_y_hi - wall_centre_y
	match side:
		"north", "south":
			var x_lo := maxf(room_pos.x - room.size.x / 2.0, other_pos.x - other.size.x / 2.0)
			var x_hi := minf(room_pos.x + room.size.x / 2.0, other_pos.x + other.size.x / 2.0)
			if x_hi - x_lo <= SpatialEntity3D.EPSILON: return Rect2()
			return Rect2(x_lo - room_pos.x, v_lo, x_hi - x_lo, v_hi - v_lo)
		"east", "west":
			var z_lo := maxf(room_pos.z - room.size.z / 2.0, other_pos.z - other.size.z / 2.0)
			var z_hi := minf(room_pos.z + room.size.z / 2.0, other_pos.z + other.size.z / 2.0)
			if z_hi - z_lo <= SpatialEntity3D.EPSILON: return Rect2()
			return Rect2(room_pos.z - z_hi, v_lo, z_hi - z_lo, v_hi - v_lo)
	return Rect2()

func _adjust_doors_for_move(room: Room3D, new_pos: Vector3, moving: Dictionary) -> Array:
	# Like _adjust_doors_for_resize but only world-pins doors on sides that face a
	# stationary (non-moving) neighbor. Doors facing moving rooms (or no room) ride
	# with their room and need no adjustment.
	var fixups: Array = []
	var dx := new_pos.x - room.global_position.x
	var dz := new_pos.z - room.global_position.z
	if absf(dx) < Room3D.EPSILON and absf(dz) < Room3D.EPSILON: return fixups
	for door in room.door_list:
		var has_stationary_neighbor := false
		for nb: Room3D in dock.scene_query.rooms_flush_with_wall(room, door.side):
			if not moving.has(nb):
				has_stationary_neighbor = true
				break
		if not has_stationary_neighbor: continue
		var placeholder := _find_door_placeholder(room, door)
		match door.side:
			"north", "south":
				door.center_u -= dx
			"east", "west":
				door.center_u += dz
			"floor", "ceiling":
				door.center_u -= dx
				door.center_v += dz
		if placeholder != null:
			dock.ops.meta(placeholder, "door_cu", door.center_u)
			dock.ops.meta(placeholder, "door_cv", door.center_v)
			var world_xf := placeholder.global_transform
			fixups.append({"node": placeholder,
					"local": Transform3D(world_xf.basis, world_xf.origin - new_pos)})
	return fixups

func _execute_move(room: Room3D, new_pos: Vector3, cascade_moves: Array) -> void:
	confirm.dismiss()
	var moving: Dictionary = {room: new_pos}
	for m in cascade_moves: moving[m["room"]] = m["new_pos"]

	var action := "Move %s" % room.name
	if not cascade_moves.is_empty():
		action += " and %d connected room%s" % [cascade_moves.size(), "s" if cascade_moves.size() != 1 else ""]

	var affected: Array[Room3D] = [room]
	for m in cascade_moves: affected.append(m["room"] as Room3D)
	var doors_before: Dictionary = {}
	for r: Room3D in affected: doors_before[r] = EditOps.copy_doors(r)

	dock.ops.begin(action)
	# Recorded before anything moves: prop() reads the current value for undo.
	dock.ops.prop(room, "global_position", new_pos)
	for m in cascade_moves:
		dock.ops.prop(m["room"], "global_position", m["new_pos"])

	var fixups: Array = _adjust_doors_for_move(room, new_pos, moving)
	for m in cascade_moves:
		fixups += _adjust_doors_for_move(m["room"], m["new_pos"], moving)
	for r: Room3D in affected:
		dock.ops.swap_doors(r, doors_before[r], EditOps.copy_doors(r))
	_record_placeholder_fixups(fixups)
	dock.ops.commit()

	move_x.value = new_pos.x
	move_y.value = new_pos.y
	move_z.value = new_pos.z
	_refresh()
	var msg := "Moved %s to (%.1f, %.1f, %.1f)." % [room.name, new_pos.x, new_pos.y, new_pos.z]
	if not cascade_moves.is_empty():
		msg += " Dragged %d connected room%s along." % [cascade_moves.size(), "s" if cascade_moves.size() != 1 else ""]
	msg += " Press Control Z to undo."
	dock._say_ok(msg)

func _auto_anchor() -> void:
	if not dock.current_entity is Room3D: dock._say("No room selected."); return
	var room := dock.current_entity as Room3D
	var root: Node = dock.scene_query.placement_parent()
	if root == null: return
	var has_n: bool = not dock.scene_query.rooms_flush_with_wall(room, "north").is_empty()
	var has_s: bool = not dock.scene_query.rooms_flush_with_wall(room, "south").is_empty()
	var has_e: bool = not dock.scene_query.rooms_flush_with_wall(room, "east").is_empty()
	var has_w: bool = not dock.scene_query.rooms_flush_with_wall(room, "west").is_empty()
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
