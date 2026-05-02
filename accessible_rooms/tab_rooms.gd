@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var new_w: SpinBox; var new_h: SpinBox; var new_d: SpinBox
var resize_w: SpinBox; var resize_h: SpinBox; var resize_d: SpinBox
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

func _ready() -> void:
	var nl := Label.new(); nl.text = "New room size (m):"
	add_child(nl)
	new_w = _spinbox(1.0, 200.0, 1.0, 6.0)
	new_h = _spinbox(1.0, 100.0, 0.5, 3.0)
	new_d = _spinbox(1.0, 200.0, 1.0, 6.0)
	var nr := HBoxContainer.new()
	for pair in [["W:", new_w], ["H:", new_h], ["D:", new_d]]:
		var lbl := Label.new(); lbl.text = pair[0]
		nr.add_child(lbl); nr.add_child(pair[1])
	add_child(nr)
	var surface_row := HBoxContainer.new()
	build_walls = CheckBox.new()
	build_walls.text = "Build walls"
	build_walls.button_pressed = true
	build_ceiling = CheckBox.new()
	build_ceiling.text = "Build ceiling"
	build_ceiling.button_pressed = true
	surface_row.add_child(build_walls)
	surface_row.add_child(build_ceiling)
	add_child(surface_row)

	add_child(HSeparator.new())
	var dl := Label.new(); dl.text = "Doorway size (m):"
	add_child(dl)
	door_w = _spinbox(0.5, 20.0, 0.1, 1.2)
	door_h = _spinbox(0.5, 20.0, 0.1, 2.5)
	var dr := HBoxContainer.new()
	for pair in [["W:", door_w], ["H:", door_h]]:
		var lbl := Label.new(); lbl.text = pair[0]
		dr.add_child(lbl); dr.add_child(pair[1])
	add_child(dr)
	create_door_placeholder = CheckBox.new()
	create_door_placeholder.text = "Create door placeholder at new doorways"
	create_door_placeholder.button_pressed = true
	add_child(create_door_placeholder)
	add_child(HSeparator.new())

	_btn("New standalone room", _new_root_room)

	add_child(HSeparator.new())
	var cc_lbl := Label.new(); cc_lbl.text = "Corner-to-corner room:"
	add_child(cc_lbl)
	_btn("Place room from corners", _place_room_from_corners)

	add_child(HSeparator.new())
	for side in ["north", "south", "east", "west"]:
		_btn("Add room to %s of current" % side, _add_neighbor.bind(side))
		_btn("Punch doorway %s on current" % side, _punch.bind(side))
	_btn("Punch door at cursor (on nearest wall)", _punch_at_cursor)
	_btn("Punch hole at cursor (on nearest wall)", _punch_hole_at_cursor)

	add_child(HSeparator.new())

	room_list = ItemList.new()
	room_list.custom_minimum_size = Vector2(0, 200)
	room_list.item_selected.connect(_on_select)
	add_child(room_list)
	_btn("Refresh entity list", _refresh)
	add_child(HSeparator.new())
	_btn("Bake scene (replace spatial entities with plain nodes)", _bake_scene)
	_btn("Bake scene to file...", _open_bake_to_file_dialog)

	add_child(HSeparator.new())
	var rl := Label.new(); rl.text = "Edit selected entity:"
	add_child(rl)
	_build_anchor_ui()
	# Dynamic resize container, populated by entity.populate_properties_ui().
	_resize_container = VBoxContainer.new()
	add_child(_resize_container)
	_btn("Apply changes", _apply_resize)
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
	add_child(_resize_conflict_bar)
	add_child(HSeparator.new())
	_btn("Measure space at cursor", _measure_space_at_cursor)
	_btn("Resize room to fill E\u2194W", _resize_fill_ew)
	_btn("Resize room to fill N\u2194S", _resize_fill_ns)

	add_child(HSeparator.new())
	var door_lbl := Label.new(); door_lbl.text = "Doors on selected room:"
	add_child(door_lbl)
	_door_item_list = ItemList.new()
	_door_item_list.custom_minimum_size = Vector2(0, 100)
	_door_item_list.item_selected.connect(_on_door_select)
	add_child(_door_item_list)
	add_child(HSeparator.new())
	var door_edit_lbl := Label.new(); door_edit_lbl.text = "Edit selected door:"
	add_child(door_edit_lbl)
	_door_props_container = VBoxContainer.new()
	add_child(_door_props_container)
	_btn("Apply door changes", _apply_door_changes)
	_btn("Remove selected door", _remove_selected_door)

	add_child(HSeparator.new())
	var wall_lbl := Label.new(); wall_lbl.text = "Walls on selected room:"
	add_child(wall_lbl)
	_wall_item_list = ItemList.new()
	_wall_item_list.custom_minimum_size = Vector2(0, 100)
	_wall_item_list.item_selected.connect(_on_wall_select)
	add_child(_wall_item_list)
	add_child(HSeparator.new())
	var wall_edit_lbl := Label.new(); wall_edit_lbl.text = "Edit selected wall:"
	add_child(wall_edit_lbl)
	_wall_props_container = VBoxContainer.new()
	add_child(_wall_props_container)
	_btn("Apply wall changes", _apply_wall_changes)

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
	root.add_child(r); r.owner = root; r.rebuild()
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
	root.add_child(r); r.owner = root; r.rebuild()
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

	root.add_child(r); r.owner = root
	r.position = new_pos
	r.rebuild()   # single rebuild, config fully set, not in tree when add_doorway was called

	# Placeholder for new room's backside doorway (room is now in tree, global_position valid).
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
	var root: Node = dock.scene_query.placement_parent()
	if root == null: return
	var world_pos: Vector3 = dock.scene_query._doorway_world_pos(room, side, cu, cv)
	var placeholder := Node3D.new()
	placeholder.name = "DoorPlaceholder_%s" % side
	placeholder.set_meta("door_placeholder", true)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(w, h, 0.1)
	mesh_inst.mesh = box
	placeholder.add_child(mesh_inst)
	mesh_inst.owner = root
	placeholder.position = world_pos
	room.add_child(placeholder)
	placeholder.owner = root
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
		if c is SpatialEntity3D:
			room_list.add_item(dock.scene_query.entity_label(c))
			room_list.set_item_metadata(room_list.item_count - 1, c)

func _on_select(i: int) -> void:
	var entity := room_list.get_item_metadata(i) as SpatialEntity3D
	dock.current_entity = entity
	for child in _resize_container.get_children():
		child.queue_free()
	await get_tree().process_frame
	entity.populate_properties_ui(_resize_container)
	dock._say("Selected %s." % dock.scene_query.entity_label(entity))
	dock.play_audio_3d("object", (entity as Node3D).global_position)
	_refresh_door_list()
	_refresh_wall_list()

func _bake_scene() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var entities: Array = []
	for c in root.get_children():
		if c is SpatialEntity3D:
			entities.append(c)
	if entities.is_empty(): dock._say("No spatial entities found."); return

	for entity in entities:
		var original_name: String = entity.name
		entity.name = entity.name + "__bake_temp"
		var wrapper := Node3D.new()
		wrapper.name = original_name
		wrapper.transform = (entity as Node3D).transform
		root.add_child(wrapper)
		wrapper.owner = root

		var bodies: Array[StaticBody3D] = (entity as SpatialEntity3D).generated_bodies()
		var by_surface: Dictionary = {}
		for body in bodies:
			var surf: String = body.get_meta("surface", "concrete")
			if not by_surface.has(surf): by_surface[surf] = []
			by_surface[surf].append(body)

		for child in entity.get_children():
			if not child.has_meta("generated"):
				entity.remove_child(child)
				wrapper.add_child(child)
				_set_owners_recursive(child, root)

		# Merge visual neshes, one ArrayMesh per surface type.
		for surf in by_surface:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for body in by_surface[surf]:
				var mi: MeshInstance3D
				for ch in body.get_children():
					if ch is MeshInstance3D: mi = ch; break
				if mi == null: continue
				st.append_from(mi.mesh, 0, body.transform)
			var merged_mi := MeshInstance3D.new()
			merged_mi.name = original_name + "_" + surf + "_mesh"
			merged_mi.mesh = st.commit()
			wrapper.add_child(merged_mi)
			merged_mi.owner = root

		# Single StaticBody3D with trimesh collision for the whole entity.
		var all_tris := PackedVector3Array()
		for surf in by_surface:
			for body in by_surface[surf]:
				var mi: MeshInstance3D
				for ch in body.get_children():
					if ch is MeshInstance3D: mi = ch; break
				if mi == null: continue
				var arrays: Array = mi.mesh.surface_get_arrays(0)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for idx in range(0, verts.size(), 3):
						all_tris.append(body.transform * verts[idx])
						all_tris.append(body.transform * verts[idx + 1])
						all_tris.append(body.transform * verts[idx + 2])
				else:
					for idx in range(0, indices.size(), 3):
						all_tris.append(body.transform * verts[indices[idx]])
						all_tris.append(body.transform * verts[indices[idx + 1]])
						all_tris.append(body.transform * verts[indices[idx + 2]])

		if all_tris.size() > 0:
			var phys_body := StaticBody3D.new()
			phys_body.name = "Collision"
			var cshape := CollisionShape3D.new()
			var trimesh := ConcavePolygonShape3D.new()
			trimesh.set_faces(all_tris)
			cshape.shape = trimesh
			phys_body.add_child(cshape)
			wrapper.add_child(phys_body)
			phys_body.owner = root
			cshape.owner = root

		root.remove_child(entity)
		entity.queue_free()

	dock.current_entity = null
	_refresh()
	dock._say_ok("Baked %d spatial entit%s with merged meshes and optimised collision." % \
		[entities.size(), "ies" if entities.size() != 1 else "y"])

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

	var dup_root: Node = root.duplicate()
	_set_owners_recursive(dup_root, dup_root)

	var entities: Array = []
	for c in dup_root.get_children():
		if c is SpatialEntity3D:
			entities.append(c)
	if entities.is_empty():
		dock._say("No spatial entities found.")
		dup_root.free()
		return

	for entity in entities:
		var original_name: String = entity.name
		entity.name = entity.name + "__bake_temp"
		var wrapper := Node3D.new()
		wrapper.name = original_name
		wrapper.transform = (entity as Node3D).transform
		dup_root.add_child(wrapper)
		wrapper.owner = dup_root

		var bodies: Array[StaticBody3D] = (entity as SpatialEntity3D).generated_bodies()
		var by_surface: Dictionary = {}
		for body in bodies:
			var surf: String = body.get_meta("surface", "concrete")
			if not by_surface.has(surf): by_surface[surf] = []
			by_surface[surf].append(body)

		for child in entity.get_children():
			if not child.has_meta("generated"):
				entity.remove_child(child)
				wrapper.add_child(child)
				_set_owners_recursive(child, dup_root)

		for surf in by_surface:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for body in by_surface[surf]:
				var mi: MeshInstance3D = body.get_child(0)
				st.append_from(mi.mesh, 0, body.transform)
			var merged_mi := MeshInstance3D.new()
			merged_mi.name = original_name + "_" + surf + "_mesh"
			merged_mi.mesh = st.commit()
			wrapper.add_child(merged_mi)
			merged_mi.owner = dup_root

		var all_tris := PackedVector3Array()
		for surf in by_surface:
			for body in by_surface[surf]:
				var mi: MeshInstance3D = body.get_child(0)
				var arrays: Array = mi.mesh.surface_get_arrays(0)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for idx in range(0, verts.size(), 3):
						all_tris.append(body.transform * verts[idx])
						all_tris.append(body.transform * verts[idx + 1])
						all_tris.append(body.transform * verts[idx + 2])
				else:
					for idx in range(0, indices.size(), 3):
						all_tris.append(body.transform * verts[indices[idx]])
						all_tris.append(body.transform * verts[indices[idx + 1]])
						all_tris.append(body.transform * verts[indices[idx + 2]])

		if all_tris.size() > 0:
			var phys_body := StaticBody3D.new()
			phys_body.name = "Collision"
			var cshape := CollisionShape3D.new()
			var trimesh := ConcavePolygonShape3D.new()
			trimesh.set_faces(all_tris)
			cshape.shape = trimesh
			phys_body.add_child(cshape)
			wrapper.add_child(phys_body)
			phys_body.owner = dup_root
			cshape.owner = dup_root

		dup_root.remove_child(entity)
		entity.free()

	var packed := PackedScene.new()
	var err := packed.pack(dup_root)
	if err != OK:
		dock._say_err("Failed to pack scene (error %d)." % err)
		dup_root.free()
		return

	err = ResourceSaver.save(packed, target_path)
	dup_root.free()
	if err != OK:
		dock._say_err("Failed to save scene (error %d)." % err)
		return

	dock._say_ok("Baked %d entit%s → %s" % [
		entities.size(),
		"ies" if entities.size() != 1 else "y",
		target_path
	])

func _set_owners_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owners_recursive(child, owner)

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
		var tag := (" \"%s\"" % d.label) if d.label != "" else ""
		_door_item_list.add_item("[%d] %s%s  %.1f×%.1fm" % [i, d.side, tag, d.width, d.height])
		_door_item_list.set_item_metadata(i, i)

func _on_door_select(i: int) -> void:
	if not dock.current_entity is Room3D: return
	var room := dock.current_entity as Room3D
	_current_door_idx = _door_item_list.get_item_metadata(i)
	if _current_door_idx < 0 or _current_door_idx >= room.door_list.size(): return
	var d: DoorEntry = room.door_list[_current_door_idx]
	for c in _door_props_container.get_children(): c.queue_free()
	await get_tree().process_frame
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

func _apply_door_changes() -> void:
	if not dock.current_entity is Room3D or _current_door_idx < 0:
		dock._say("No door selected."); return
	var room := dock.current_entity as Room3D
	if _current_door_idx >= room.door_list.size():
		dock._say("Door index out of range."); return
	var d: DoorEntry = room.door_list[_current_door_idx]
	var children := _door_props_container.get_children()
	var side_opt := children[0].get_child(1) as OptionButton
	d.side = side_opt.get_item_text(side_opt.selected)
	var spins: Array[SpinBox] = []
	for row in children.slice(1):
		for c in row.get_children():
			if c is SpinBox: spins.append(c)
	if spins.size() >= 4:
		d.center_u = spins[0].value; d.center_v = spins[1].value
		d.width = spins[2].value; d.height = spins[3].value
	room._queue_rebuild()
	_refresh_door_list()
	dock._say("Door %d on %s updated." % [_current_door_idx, room.name])

func _remove_selected_door() -> void:
	if not dock.current_entity is Room3D or _current_door_idx < 0:
		dock._say("No door selected."); return
	var room := dock.current_entity as Room3D
	room.remove_door(_current_door_idx)
	_refresh_door_list()
	dock._say("Removed door %d from %s." % [_current_door_idx, room.name])

func _refresh_wall_list() -> void:
	_wall_item_list.clear()
	_current_wall_side = ""
	for c in _wall_props_container.get_children(): c.queue_free()
	if not dock.current_entity is Room3D: return
	var room := dock.current_entity as Room3D
	for side in ["north", "south", "east", "west", "floor", "ceiling"]:
		var wc: WallConfig = room.cfg(side)
		var state := "on" if wc.enabled else "off"
		_wall_item_list.add_item("%s, %s (%s)" % [side, wc.surface, state])
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
	dock._say("Selected %s wall, surface: %s, %s." % [_current_wall_side, wc.surface, "enabled" if wc.enabled else "disabled"])

func _apply_wall_changes() -> void:
	if not dock.current_entity is Room3D or _current_wall_side == "":
		dock._say("No wall selected."); return
	var room := dock.current_entity as Room3D
	var wc: WallConfig = room.cfg(_current_wall_side)
	var children := _wall_props_container.get_children()
	if children.size() < 2: dock._say("Wall controls not ready."); return
	var enabled_cb := children[0] as CheckBox
	var surf_row := children[1]
	var surf_edit: LineEdit
	for c in surf_row.get_children():
		if c is LineEdit: surf_edit = c; break
	if enabled_cb == null or surf_edit == null: return
	wc.enabled = enabled_cb.button_pressed
	wc.surface = surf_edit.text.strip_edges()
	room._queue_rebuild()
	_refresh_wall_list()
	dock._say("%s wall updated, surface: %s, %s." % [_current_wall_side, wc.surface, "enabled" if wc.enabled else "disabled"])

func _build_anchor_ui() -> void:
	var anchor_lbl := Label.new()
	anchor_lbl.text = "Resize anchor:"
	add_child(anchor_lbl)

	var anchor_grid := GridContainer.new()
	anchor_grid.columns = 3
	add_child(anchor_grid)

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
	add_child(smart_btn)

	_cascade_checkbox = CheckBox.new()
	_cascade_checkbox.text = "Cascade: push connected rooms"
	_cascade_checkbox.tooltip_text = "When growing, recursively push rooms flush with the growing wall"
	add_child(_cascade_checkbox)

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

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
