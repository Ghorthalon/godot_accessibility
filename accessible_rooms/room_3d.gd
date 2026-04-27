@tool
class_name Room3D
extends SpatialEntity3D

const SIDES := ["north", "south", "east", "west", "floor", "ceiling"]
# +Z = south, -Z = north, +X = east, -X = west (Godot convention)
const NORMALS := {
	"north": Vector3(0,0,-1), "south": Vector3(0,0,1),
	"east":  Vector3(1,0,0),  "west":  Vector3(-1,0,0),
	"floor": Vector3(0,1,0),  "ceiling": Vector3(0,-1,0),
}

@export var size: Vector3 = Vector3(6, 3, 6): set = _set_size
@export var wall_north:   WallConfig = WallConfig.new(): set = _set_n
@export var wall_south:   WallConfig = WallConfig.new(): set = _set_s
@export var wall_east:    WallConfig = WallConfig.new(): set = _set_e
@export var wall_west:    WallConfig = WallConfig.new(): set = _set_w
@export var wall_floor:   WallConfig = WallConfig.new(): set = _set_fl
@export var wall_ceiling: WallConfig = WallConfig.new(): set = _set_cl
@export var rebuild_now:  bool = false: set = _trigger
@export var door_list: Array[DoorEntry] = []

var _rebuild_queued := false
var _rebuild_gen := 0

func _set_size(v):  size = v;                                   _queue_rebuild()
func _set_n(v):    _rewire(wall_north,   v); wall_north = v;   _queue_rebuild()
func _set_s(v):    _rewire(wall_south,   v); wall_south = v;   _queue_rebuild()
func _set_e(v):    _rewire(wall_east,    v); wall_east = v;    _queue_rebuild()
func _set_w(v):    _rewire(wall_west,    v); wall_west = v;    _queue_rebuild()
func _set_fl(v):   _rewire(wall_floor,   v); wall_floor = v;   _queue_rebuild()
func _set_cl(v):   _rewire(wall_ceiling, v); wall_ceiling = v; _queue_rebuild()
func _trigger(_v): rebuild()

func _rewire(old: WallConfig, new_cfg: WallConfig) -> void:
	if is_instance_valid(old) and old.changed.is_connected(_queue_rebuild):
		old.changed.disconnect(_queue_rebuild)
	if new_cfg and not new_cfg.changed.is_connected(_queue_rebuild):
		new_cfg.changed.connect(_queue_rebuild)

func _enter_tree() -> void:
	add_to_group("accessible_rooms_rooms")
	set_notify_transform(true)
	
	for s in SIDES:
		var c := cfg(s)
		if c and not c.changed.is_connected(_queue_rebuild):
			c.changed.connect(_queue_rebuild)

func _exit_tree() -> void:
	remove_from_group("accessible_rooms_rooms")
	_queue_rebuild_siblings()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_rebuild()
		_queue_rebuild_siblings()

func _queue_rebuild_siblings() -> void:
	if not is_inside_tree(): return
	for node in get_tree().get_nodes_in_group("accessible_rooms_rooms"):
		if node != self and node is Room3D:
			(node as Room3D)._queue_rebuild()

## Returns the WallConfig for the given side name.
func cfg(side: String) -> WallConfig:
	match side:
		"north":   return wall_north
		"south":   return wall_south
		"east":    return wall_east
		"west":    return wall_west
		"floor":   return wall_floor
		"ceiling": return wall_ceiling
	return null

func _queue_rebuild() -> void:
	if is_inside_tree() and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild_gen += 1
		call_deferred("rebuild")

func _sync_doors_to_openings() -> void:
	for s in SIDES:
		cfg(s).openings.clear()
	for d in door_list:
		cfg(d.side).openings.append(
			Rect2(d.center_u - d.width/2, d.center_v - d.height/2, d.width, d.height))

func rebuild() -> void:
	_rebuild_queued = false
	var my_gen := _rebuild_gen
	_sync_doors_to_openings()
	if not Engine.is_editor_hint(): return
	for c in get_children():
		if c.has_meta("generated") or c.has_meta("room_area"): c.queue_free()
	if not is_inside_tree(): return
	await get_tree().process_frame
	if _rebuild_gen != my_gen: return
	for side in SIDES:
		var wall_cfg := cfg(side)
		if wall_cfg == null or not wall_cfg.enabled: continue
		_build_wall(side)
	_build_room_area()

func _build_wall(side: String) -> void:
	var wall_cfg := cfg(side)
	# Wall plane dimensions in its local 2D frame (u, v).
	var u := size.x; var v := size.z  # floor/ceiling defaults
	var center := Vector3.ZERO
	var basis_u := Vector3.RIGHT; var basis_v := Vector3.FORWARD
	match side:
		"floor":   center = Vector3(0, 0, 0)
		"ceiling": center = Vector3(0, size.y, 0)
		"north":
			u = size.x; v = size.y
			center = Vector3(0, size.y/2, -size.z/2)
			basis_u = Vector3.RIGHT; basis_v = Vector3.UP
		"south":
			u = size.x; v = size.y
			center = Vector3(0, size.y/2, size.z/2)
			basis_u = Vector3.RIGHT; basis_v = Vector3.UP
		"east":
			u = size.z; v = size.y
			center = Vector3(size.x/2, size.y/2, 0)
			basis_u = Vector3.FORWARD; basis_v = Vector3.UP
		"west":
			u = size.z; v = size.y
			center = Vector3(-size.x/2, size.y/2, 0)
			basis_u = Vector3.FORWARD; basis_v = Vector3.UP

	var rects := _slice([Rect2(-u/2, -v/2, u, v)], wall_cfg.openings + _get_overlap_suppressions(side))
	for i in rects.size():
		_spawn_quad(side, wall_cfg.surface, center, basis_u, basis_v, rects[i], i)

	# Zone overlays: offset slightly along the wall normal to prevent z-fighting.
	var zone_off: Vector3 = NORMALS[side] * EPSILON
	for i in wall_cfg.zones.size():
		var zone: Dictionary = wall_cfg.zones[i]
		_spawn_quad(side, zone.get("surface", "concrete"),
				center + zone_off, basis_u, basis_v, zone["rect"], rects.size() + i)

static func _wall_plane_coord(room: Room3D, side: String) -> float:
	match side:
		"north": return room.position.z - room.size.z / 2.0
		"south": return room.position.z + room.size.z / 2.0
		"east":  return room.position.x + room.size.x / 2.0
		"west":  return room.position.x - room.size.x / 2.0
	return 0.0

func _compute_wall_local_overlap(side: String, other: Room3D) -> Rect2:
	# Actual Y overlap in world space (rooms may have different floor heights).
	var world_y_lo := maxf(position.y, other.position.y)
	var world_y_hi := minf(position.y + size.y, other.position.y + other.size.y)
	if world_y_hi - world_y_lo <= EPSILON: return Rect2()
	# Convert to wall-local v (basis_v = UP, wall centre is at position.y + size.y/2).
	var wall_centre_y := position.y + size.y / 2.0
	var v_lo := world_y_lo - wall_centre_y
	var v_hi := world_y_hi - wall_centre_y
	match side:
		"north", "south":
			var x_lo := maxf(position.x - size.x/2.0, other.position.x - other.size.x/2.0)
			var x_hi := minf(position.x + size.x/2.0, other.position.x + other.size.x/2.0)
			if x_hi - x_lo <= EPSILON: return Rect2()
			return Rect2(x_lo - position.x, v_lo, x_hi - x_lo, v_hi - v_lo)
		"east", "west":
			var z_lo := maxf(position.z - size.z/2.0, other.position.z - other.size.z/2.0)
			var z_hi := minf(position.z + size.z/2.0, other.position.z + other.size.z/2.0)
			if z_hi - z_lo <= EPSILON: return Rect2()
			# basis_u = FORWARD = -Z, so u = position.z - world_z (reversed)
			return Rect2(position.z - z_hi, v_lo, z_hi - z_lo, v_hi - v_lo)
	return Rect2()

func _get_overlap_suppressions(side: String) -> Array[Rect2]:
	if not is_inside_tree(): return []
	var opp := neighbor_doorway_side(side)
	if opp.is_empty(): return []
	var result: Array[Rect2] = []
	for node in get_tree().get_nodes_in_group("accessible_rooms_rooms"):
		if node == self or not node is Room3D: continue
		var other := node as Room3D
		if absf(_wall_plane_coord(self, side) - _wall_plane_coord(other, opp)) > EPSILON:
			continue
		var overlap := _compute_wall_local_overlap(side, other)
		if overlap.size.x <= EPSILON or overlap.size.y <= EPSILON: continue
		# Lower node path wins. higher path suppresses its geometry in the overlap.
		if str(get_path()) < str(other.get_path()): continue
		result.append(overlap)
	return result

func _slice(rects: Array, openings: Array) -> Array:
	for hole in openings:
		var out := []
		for r in rects:
			if not r.intersects(hole): out.append(r); continue
			# Split r into up to 4 strips around the hole.
			var left := Rect2(r.position.x, r.position.y, hole.position.x - r.position.x, r.size.y)
			var right_x: float = hole.position.x + hole.size.x
			var right := Rect2(right_x, r.position.y, r.end.x - right_x, r.size.y)
			var mid_x := maxf(r.position.x, hole.position.x)
			var mid_w := minf(r.end.x, hole.end.x) - mid_x
			var bottom := Rect2(mid_x, r.position.y, mid_w, hole.position.y - r.position.y)
			var top_y: float = hole.position.y + hole.size.y
			var top := Rect2(mid_x, top_y, mid_w, r.end.y - top_y)
			for piece in [left, right, bottom, top]:
				if piece.size.x > EPSILON and piece.size.y > EPSILON:
					out.append(piece)
		rects = out
	return rects

func _spawn_quad(side: String, surface: String, center: Vector3, bu: Vector3, bv: Vector3, r: Rect2, idx: int) -> void:
	var body := StaticBody3D.new()
	body.set_meta("generated", true)
	body.set_meta("surface", surface)
	body.name = "%s_%d" % [side, idx]
	var thickness := WALL_THICKNESS
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r.size.x, r.size.y, thickness)
	mi.mesh = bm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(mi); body.add_child(cs)
	add_child(body)
	# Orient: local Z of the quad aligns with the wall normal.
	var normal := bu.cross(bv).normalized()
	var t := Transform3D()
	t.basis = Basis(bu, bv, normal)
	t.origin = center + bu * (r.position.x + r.size.x/2) + bv * (r.position.y + r.size.y/2)
	body.transform = t
	var root := get_tree().edited_scene_root
	if root:
		for n in [body, mi, cs]: n.owner = root

func _build_room_area() -> void:
	var area := Area3D.new()
	area.set_meta("room_area", true)
	area.name = "RoomArea"
	area.position = Vector3(0, size.y / 2.0, 0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	area.add_child(cs)
	add_child(area)
	var root := get_tree().edited_scene_root
	if root:
		area.owner = root
		cs.owner = root

# ---------------------------------------------------------------------------
# SpatialEntity3D interface
# ---------------------------------------------------------------------------

func entity_label() -> String:
	return "%s (room, %.0fx%.0fx%.0f m)" % [name, size.x, size.y, size.z]

func contains_point(p: Vector3) -> bool:
	var lp := p - position
	return absf(lp.x) <= size.x / 2.0 and lp.y >= 0 and lp.y <= size.y and absf(lp.z) <= size.z / 2.0

func populate_properties_ui(c: VBoxContainer) -> void:
	_add_spinbox(c, "W:", 1.0, 200.0, 1.0, size.x)
	_add_spinbox(c, "H:", 1.0, 100.0, 0.5, size.y)
	_add_spinbox(c, "D:", 1.0, 200.0, 1.0, size.z)

func apply_properties_ui(c: VBoxContainer) -> void:
	var spins: Array[SpinBox] = []
	for row in c.get_children():
		for child in row.get_children():
			if child is SpinBox: spins.append(child as SpinBox)
	if spins.size() >= 3:
		self.size = Vector3(spins[0].value, spins[1].value, spins[2].value)

func neighbor_offset(side: String, other_size: Vector3) -> Vector3:
	# Where to place a neighbour room so its opposite wall is flush with mine.
	match side:
		"north": return Vector3(0, 0, -(size.z/2 + other_size.z/2))
		"south": return Vector3(0, 0,  (size.z/2 + other_size.z/2))
		"east":  return Vector3( (size.x/2 + other_size.x/2), 0, 0)
		"west":  return Vector3(-(size.x/2 + other_size.x/2), 0, 0)
	return Vector3.ZERO

func neighbor_doorway_side(side: String) -> String:
	var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
	return opp.get(side, "")

func has_wall(_side: String) -> bool:
	return true

func punch_doorway(side: String, width := 1.2, height := 2.1) -> void:
	## Appends a centred floorlevel doorway without removing existing ones.
	add_doorway(side, 0.0, -size.y / 2.0 + height / 2.0, width, height)

func punch_hole(side: String, center_u: float, center_v: float, width := 0.9, height := 0.9) -> void:
	## Appends a hole centred at (center_u, center_v) in wall-local metres. Suitable for windows.
	add_doorway(side, center_u, center_v, width, height)

func add_doorway(side: String, center_u: float, center_v: float, width := 1.2, height := 2.1, label := "") -> void:
	## Appends a doorway at a walllocal position. center_u/v in metres, origin = wall centre.
	var d := DoorEntry.new()
	d.side = side; d.center_u = center_u; d.center_v = center_v
	d.width = width; d.height = height; d.label = label
	door_list.append(d)
	_queue_rebuild()

func remove_door(idx: int) -> void:
	if idx >= 0 and idx < door_list.size():
		door_list.remove_at(idx)
		_queue_rebuild()
