@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var new_w: SpinBox; var new_h: SpinBox; var new_d: SpinBox
var resize_w: SpinBox; var resize_h: SpinBox; var resize_d: SpinBox
var door_w: SpinBox; var door_h: SpinBox
var room_list: ItemList

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

	add_child(HSeparator.new())
	var dl := Label.new(); dl.text = "Doorway size (m):"
	add_child(dl)
	door_w = _spinbox(0.5, 20.0, 0.1, 1.2)
	door_h = _spinbox(0.5, 20.0, 0.1, 2.1)
	var dr := HBoxContainer.new()
	for pair in [["W:", door_w], ["H:", door_h]]:
		var lbl := Label.new(); lbl.text = pair[0]
		dr.add_child(lbl); dr.add_child(pair[1])
	add_child(dr)
	add_child(HSeparator.new())

	_btn("New standalone room", _new_root_room)
	for side in ["north", "south", "east", "west"]:
		_btn("Add room to %s of current" % side, _add_neighbor.bind(side))
		_btn("Punch doorway %s on current" % side, _punch.bind(side))
	_btn("Punch door at cursor (on nearest wall)", _punch_at_cursor)

	room_list = ItemList.new()
	room_list.custom_minimum_size = Vector2(0, 200)
	room_list.item_selected.connect(_on_select)
	add_child(room_list)
	_btn("Refresh room list", _refresh)
	add_child(HSeparator.new())
	_btn("Bake scene (replace Room3Ds with plain nodes)", _bake_scene)

	add_child(HSeparator.new())
	var rl := Label.new(); rl.text = "Resize current room (m):"
	add_child(rl)
	resize_w = _spinbox(1.0, 200.0, 1.0, 6.0)
	resize_h = _spinbox(1.0, 100.0, 0.5, 3.0)
	resize_d = _spinbox(1.0, 200.0, 1.0, 6.0)
	var rr := HBoxContainer.new()
	for pair in [["W:", resize_w], ["H:", resize_h], ["D:", resize_d]]:
		var lbl := Label.new(); lbl.text = pair[0]
		rr.add_child(lbl); rr.add_child(pair[1])
	add_child(rr)
	_btn("Apply resize", _apply_resize)

	_refresh()

# --- Room management ---

func _new_root_room() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var r := Room3D.new()
	r.name = "Room%d" % (root.get_child_count() + 1)
	r.size = Vector3(new_w.value, new_h.value, new_d.value)
	r.position = dock.cursor
	root.add_child(r); r.owner = root; r.rebuild()
	dock.current_room = r
	_refresh()
	dock._say("Created %s, %.1f by %.1f by %.1f meters." % [r.name, r.size.x, r.size.y, r.size.z])

func _add_neighbor(side: String) -> void:
	if dock.current_room == null: dock._say("No current room."); return
	var root: Node = dock.scene_query.placement_parent()
	var r := Room3D.new()
	r.name = "%s_%s" % [dock.current_room.name, side]
	r.size = Vector3(new_w.value, new_h.value, new_d.value)
	root.add_child(r); r.owner = root
	r.position = dock.current_room.position + dock.current_room.neighbor_offset(side, r.size)
	r.rebuild()
	var opp: String = {"north": "south", "south": "north", "east": "west", "west": "east"}[side]
	# Punch at the center of the overlap region so doors align even for different-size rooms.
	var u_off := _overlap_center_u(dock.current_room, r, side)
	# Anchor doorway to the floor on each room's wall (center_v = floor + half door height).
	var cv_cur: float = -dock.current_room.size.y / 2.0 + door_h.value / 2.0
	var cv_new: float = -r.size.y / 2.0 + door_h.value / 2.0
	dock.current_room.add_doorway(side, u_off, cv_cur, door_w.value, door_h.value)
	r.add_doorway(opp, u_off, cv_new, door_w.value, door_h.value)
	_refresh()
	dock._say("Added room to %s, connected by doorway." % side)

func _punch(side: String) -> void:
	if dock.current_room == null: dock._say("No current room."); return
	dock.current_room.punch_doorway(side, door_w.value, door_h.value)
	dock._say("Doorway punched on %s wall (%.1fm × %.1fm)." % [side, door_w.value, door_h.value])

func _apply_resize() -> void:
	if dock.current_room == null: dock._say("No current room selected."); return
	var new_size := Vector3(resize_w.value, resize_h.value, resize_d.value)
	var root: Node = dock.scene_query.placement_parent()
	if root:
		for c in root.get_children():
			if c is Room3D and c != dock.current_room:
				if SceneQuery.aabbs_overlap(dock.current_room.position, new_size, c.position, c.size):
					dock._say("Cannot resize: would collide with %s." % c.name); return
	dock.current_room.size = new_size
	_refresh()
	dock._say("Resized %s to %.1f by %.1f by %.1f meters." % \
		[dock.current_room.name, new_size.x, new_size.y, new_size.z])

func _refresh() -> void:
	room_list.clear()
	var root: Node = dock.scene_query.placement_parent() if dock.scene_query else null
	if root == null: return
	for c in root.get_children():
		if c is Room3D:
			var door_sides: Array[String] = []
			for s in ["north", "south", "east", "west"]:
				if c.cfg(s).openings.size() > 0:
					door_sides.append(s[0].to_upper())
			var door_str := ("  [%s]" % " ".join(door_sides)) if door_sides.size() > 0 else ""
			room_list.add_item("%s  pos %s  size %s%s" % [c.name, c.position, c.size, door_str])
			room_list.set_item_metadata(room_list.item_count - 1, c)

func _on_select(i: int) -> void:
	dock.current_room = room_list.get_item_metadata(i)
	resize_w.value = dock.current_room.size.x
	resize_h.value = dock.current_room.size.y
	resize_d.value = dock.current_room.size.z
	dock._say("Selected %s." % dock.current_room.name)

func _bake_scene() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var rooms: Array = []
	for c in root.get_children():
		if c is Room3D:
			rooms.append(c)
	if rooms.is_empty(): dock._say("No Room3D nodes found."); return
	for room in rooms:
		var wrapper := Node3D.new()
		wrapper.name = room.name
		wrapper.transform = room.transform
		root.add_child(wrapper)
		wrapper.owner = root

		# Group generated quad bodies by surface name; pass non-generated children through.
		var by_surface: Dictionary = {}
		for child in room.get_children():
			if child.has_meta("generated"):
				var surf: String = child.get_meta("surface", "concrete")
				if not by_surface.has(surf):
					by_surface[surf] = []
				by_surface[surf].append(child)
			else:
				room.remove_child(child)
				wrapper.add_child(child)
				child.owner = root
				for gc in child.get_children():
					gc.owner = root

		# Merge visual meshes  one ArrayMesh per surface type.
		for surf in by_surface:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for body in by_surface[surf]:
				var mi: MeshInstance3D = body.get_child(0)
				st.append_from(mi.mesh, 0, body.transform)
			var merged_mi := MeshInstance3D.new()
			merged_mi.name = surf
			merged_mi.mesh = st.commit()
			wrapper.add_child(merged_mi)
			merged_mi.owner = root

		# Build triangle soup for a single ConcavePolygonShape3D.
		var all_tris := PackedVector3Array()
		for surf in by_surface:
			for body in by_surface[surf]:
				var mi: MeshInstance3D = body.get_child(0)
				var arrays: Array = mi.mesh.surface_get_arrays(0)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for i in range(0, verts.size(), 3):
						all_tris.append(body.transform * verts[i])
						all_tris.append(body.transform * verts[i + 1])
						all_tris.append(body.transform * verts[i + 2])
				else:
					for i in range(0, indices.size(), 3):
						all_tris.append(body.transform * verts[indices[i]])
						all_tris.append(body.transform * verts[indices[i + 1]])
						all_tris.append(body.transform * verts[indices[i + 2]])

		# Single StaticBody3D with trimesh collision for the whole room.
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

		root.remove_child(room)
		room.queue_free()
	dock.current_room = null
	_refresh()
	dock._say("Baked %d room(s) with merged meshes and optimised collision." % rooms.size())

# --- Helpers ---

func _spinbox(min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v; s.max_value = max_v
	s.step = step_v; s.value = default_v
	return s

func _punch_at_cursor() -> void:
	if dock.current_room == null: dock._say("No current room."); return
	var room: Room3D = dock.current_room
	var cur: Vector3 = dock.cursor
	var side: String = _closest_wall(room, cur)
	# Convert cursor world position to wall-local 2D coordinates (origin = wall center).
	var local_v: float = cur.y - (room.position.y + room.size.y / 2.0)
	var local_u: float
	match side:
		"north", "south":
			local_u = cur.x - room.position.x
		"east", "west":
			local_u = room.position.z - cur.z  # basis_u = FORWARD = -z
	room.add_doorway(side, local_u, local_v, door_w.value, door_h.value)
	_refresh()
	dock._say("Door punched on %s wall at offset %.1f, %.1f (%.1fm × %.1fm)." % [side, local_u, local_v, door_w.value, door_h.value])

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
	# Returns the wall-local U offset (relative to room A center) of the shared overlap center.
	if side in ["north", "south"]:
		var lo := maxf(a.position.x - a.size.x/2, b.position.x - b.size.x/2)
		var hi := minf(a.position.x + a.size.x/2, b.position.x + b.size.x/2)
		return ((lo + hi) / 2.0) - a.position.x
	else:  # east/west: basis_u = FORWARD = -z, so u = room_z - world_z
		var lo := maxf(a.position.z - a.size.z/2, b.position.z - b.size.z/2)
		var hi := minf(a.position.z + a.size.z/2, b.position.z + b.size.z/2)
		return a.position.z - ((lo + hi) / 2.0)

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
