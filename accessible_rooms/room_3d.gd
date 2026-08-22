@tool
class_name Room3D
extends SpatialEntity3D

const SIDES := ["north", "south", "east", "west", "floor", "ceiling"]
# +Z = south, -Z = north, +X = east, -X = west (Godot convention)
const NORMALS := {
	"north": Vector3(0,0,-1), "south": Vector3(0,0,1),
	"east":  Vector3(1,0,0),  "west":  Vector3(-1,0,0),
	"floor": Vector3(0,-1,0), "ceiling": Vector3(0,1,0),
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
	# Deep-copy Resources so Ctrl+D duplicates don't share door_list or WallConfigs.
	_set_n(wall_north.duplicate() if wall_north else WallConfig.new())
	_set_s(wall_south.duplicate() if wall_south else WallConfig.new())
	_set_e(wall_east.duplicate() if wall_east else WallConfig.new())
	_set_w(wall_west.duplicate() if wall_west else WallConfig.new())
	_set_fl(wall_floor.duplicate() if wall_floor else WallConfig.new())
	_set_cl(wall_ceiling.duplicate() if wall_ceiling else WallConfig.new())
	var _dl: Array[DoorEntry] = []
	for _d in door_list: _dl.append(_d.duplicate() as DoorEntry)
	door_list = _dl
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

var _prev_bounds: AABB = AABB()
var _prev_bounds_valid: bool = false

## Rebuilds only the rooms whose wall suppression could actually have changed.
##
## Wall suppression is decided by coplanar, overlapping walls, so a room can
## only be affected if its bounds touch ours. Rebuilding every room in the
## scene instead (the old behaviour) made a single nudge an O(n^2) storm and
## churned every generated node in the level.
##
## Skipped entirely outside the editor: at runtime rooms are static and each
## one builds once as it enters the tree, so scene load stays O(n).
func _queue_rebuild_siblings() -> void:
	if not is_inside_tree(): return
	if not Engine.is_editor_hint(): return
	# The union of where this room is and where it just was: a room that moves
	# away must also rebuild the neighbours it left, or they keep the hole its
	# wall used to suppress.
	var my_bounds := _world_bounds()
	var affected := my_bounds.merge(_prev_bounds) if _prev_bounds_valid else my_bounds
	_prev_bounds = my_bounds
	_prev_bounds_valid = true
	for node in get_tree().get_nodes_in_group("accessible_rooms_rooms"):
		if node == self or not node is Room3D: continue
		var other := node as Room3D
		if affected.intersects(other._world_bounds()):
			other._queue_rebuild()

## World-space AABB grown by EPSILON, so rooms that merely touch (the flush
## case that drives suppression) count as intersecting.
func _world_bounds() -> AABB:
	var half := Vector3(size.x / 2.0, 0.0, size.z / 2.0)
	return AABB(global_position - half - Vector3.ONE * EPSILON,
			Vector3(size.x, size.y, size.z) + Vector3.ONE * EPSILON * 2.0)

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

func _sync_doors_to_openings() -> void:
	for s in SIDES:
		cfg(s).openings.clear()
	for d in door_list:
		cfg(d.side).openings.append(
			Rect2(d.center_u - d.width/2, d.center_v - d.height/2, d.width, d.height))

func rebuild() -> void:
	if not is_inside_tree(): return
	_rebuild_queued = false
	var my_gen := _rebuild_gen
	_sync_doors_to_openings()
	for c in get_children():
		if c.has_meta("generated") or c.has_meta("room_area"):
			remove_child(c)
			c.queue_free()
	if not is_inside_tree(): return
	if _check_rebuild_stale(my_gen): return
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

	var rects := _slice([Rect2(-u/2, -v/2, u, v)], wall_cfg.openings + _get_overlap_suppressions(side) + _get_child_connector_cutouts(side))
	var normal := basis_u.cross(basis_v).normalized()
	var inward: Vector3 = -NORMALS[side]
	var thickness: float = wall_cfg.thickness
	var inward_offset: Vector3 = inward * (thickness * 0.5)
	for i in rects.size():
		var r: Rect2 = rects[i]
		var box_sz := Vector3(r.size.x, r.size.y, thickness)
		var origin := center + inward_offset + basis_u * (r.position.x + r.size.x / 2.0) + basis_v * (r.position.y + r.size.y / 2.0)
		_spawn_box(self, _slice_name(side, r), Transform3D(Basis(basis_u, basis_v, normal), origin), box_sz, wall_cfg.surface)

	# Zone overlays: nudged past the wall's interior face to prevent z-fighting.
	var zone_off: Vector3 = inward * (thickness * 0.5 + EPSILON)
	for i in wall_cfg.zones.size():
		var zone: Dictionary = wall_cfg.zones[i]
		var r: Rect2 = zone["rect"]
		var zone_center := center + zone_off
		var box_sz := Vector3(r.size.x, r.size.y, thickness)
		var origin := zone_center + basis_u * (r.position.x + r.size.x / 2.0) + basis_v * (r.position.y + r.size.y / 2.0)
		_spawn_box(self, "%s_zone_%d" % [side, i], Transform3D(Basis(basis_u, basis_v, normal), origin), box_sz, zone.get("surface", "concrete"))

## Names a wall slice by where it sits on the wall, in centimetres, rather than
## by its index in the slice array. Punching a doorway re-slices the wall and
## would otherwise renumber every piece, silently breaking any NodePath a user
## stored to a wall body. A name now identifies a location.
static func _slice_name(side: String, r: Rect2) -> String:
	return "%s_u%d_v%d" % [side, roundi(r.position.x * 100.0), roundi(r.position.y * 100.0)]

static func _wall_plane_coord(room: Room3D, side: String) -> float:
	match side:
		"north": return room.global_position.z - room.size.z / 2.0
		"south": return room.global_position.z + room.size.z / 2.0
		"east":  return room.global_position.x + room.size.x / 2.0
		"west":  return room.global_position.x - room.size.x / 2.0
	return 0.0

func _compute_wall_local_overlap(side: String, other: Room3D) -> Rect2:
	# Actual Y overlap in world space (rooms may have different floor heights).
	var world_y_lo := maxf(global_position.y, other.global_position.y)
	var world_y_hi := minf(global_position.y + size.y, other.global_position.y + other.size.y)
	if world_y_hi - world_y_lo <= EPSILON: return Rect2()
	# Convert to wall-local v (basis_v = UP, wall centre is at global_position.y + size.y/2).
	var wall_centre_y := global_position.y + size.y / 2.0
	var v_lo := world_y_lo - wall_centre_y
	var v_hi := world_y_hi - wall_centre_y
	match side:
		"north", "south":
			var x_lo := maxf(global_position.x - size.x/2.0, other.global_position.x - other.size.x/2.0)
			var x_hi := minf(global_position.x + size.x/2.0, other.global_position.x + other.size.x/2.0)
			if x_hi - x_lo <= EPSILON: return Rect2()
			return Rect2(x_lo - global_position.x, v_lo, x_hi - x_lo, v_hi - v_lo)
		"east", "west":
			var z_lo := maxf(global_position.z - size.z/2.0, other.global_position.z - other.size.z/2.0)
			var z_hi := minf(global_position.z + size.z/2.0, other.global_position.z + other.size.z/2.0)
			if z_hi - z_lo <= EPSILON: return Rect2()
			# basis_u = FORWARD = -Z, so u = global_position.z - world_z (reversed)
			return Rect2(global_position.z - z_hi, v_lo, z_hi - z_lo, v_hi - v_lo)
	return Rect2()

func _get_overlap_suppressions(side: String) -> Array[Rect2]:
	if not is_inside_tree(): return []
	var opp := neighbor_doorway_side(side)
	if opp.is_empty(): return []
	var result: Array[Rect2] = []
	for node in get_tree().get_nodes_in_group("accessible_rooms_rooms"):
		if node == self or not node is Room3D: continue
		var other := node as Room3D
		# Opposite-facing pair: other's opp wall is coplanar with self's side wall.
		if absf(_wall_plane_coord(self, side) - _wall_plane_coord(other, opp)) <= EPSILON:
			var overlap := _compute_wall_local_overlap(side, other)
			if overlap.size.x > EPSILON and overlap.size.y > EPSILON:
				if not _wins_overlap_against(other, side, opp):
					var other_wall := other.cfg(opp)
					if other_wall != null and other_wall.enabled:
						result.append(overlap)
		# Same-facing pair: both walls face the same direction on the same plane.
		# The lower-priority/smaller room suppresses its wall to avoid z-fighting.
		elif absf(_wall_plane_coord(self, side) - _wall_plane_coord(other, side)) <= EPSILON:
			var overlap := _compute_wall_local_overlap(side, other)
			if overlap.size.x > EPSILON and overlap.size.y > EPSILON:
				if not _wins_overlap_against(other, side, side):
					var other_wall := other.cfg(side)
					if other_wall != null and other_wall.enabled:
						result.append(overlap)
	return result

## For side == "ceiling", returns cutout Rect2s from child Stairs3D/Ramp3D nodes
## whose clearance volume exceeds this room's ceiling height. Each child contributes
## a Rect2 in ceiling-local 2D coords (u = room-local X, v = -room-local Z).
## Returns [] for other sides. floor cutouts for downward connectors are TODO.
func _get_child_connector_cutouts(side: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if side != "ceiling": return result
	var world_ceiling_y: float = global_position.y + size.y
	for c in get_children():
		if c is Stairs3D:
			var s := c as Stairs3D
			if s.pokes_through_ceiling(world_ceiling_y):
				result.append(s.ceiling_cutout_rect())
		elif c is Ramp3D:
			var r := c as Ramp3D
			if r.pokes_through_ceiling(world_ceiling_y):
				result.append(r.ceiling_cutout_rect())
	return result

# Returns true if self's wall should win (and other should suppress).
# Tiebreak order: WallConfig.priority (higher wins), then bounding_volume (bigger wins), then nodepath (lower wins).
func _wins_overlap_against(other: Room3D, side: String, opp: String) -> bool:
	var my_cfg := cfg(side)
	var other_cfg := other.cfg(opp)
	var my_pri: int = my_cfg.priority if my_cfg else 0
	var other_pri: int = other_cfg.priority if other_cfg else 0
	if my_pri != other_pri: return my_pri > other_pri
	var my_vol := bounding_volume()
	var other_vol := other.bounding_volume()
	if my_vol != other_vol: return my_vol > other_vol
	return str(get_path()) < str(other.get_path())

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

# ---------------------------------------------------------------------------
# SpatialEntity3D interface
# ---------------------------------------------------------------------------

## Thickness of a side's slab, or 0 when that side is not built.
## Walls grow INWARD, so every enabled side eats into the usable volume while
## the room's declared footprint stays exactly what you asked for. That is what
## keeps rooms tiling at whole-number coordinates, but it means the numbers you
## author against and the numbers you stand on are not the same, so the helpers
## below expose both.
func side_thickness(side: String) -> float:
	var c := cfg(side)
	return c.thickness if c != null and c.enabled else 0.0

## World Y of the surface you actually stand on: the top of the floor slab.
## This, not global_position.y, is where a character's feet belong.
func floor_surface_y() -> float:
	return global_position.y + side_thickness("floor")

## World Y of the underside of the ceiling slab.
func ceiling_surface_y() -> float:
	return global_position.y + size.y - side_thickness("ceiling")

## Clear space inside the walls: what actually fits, as opposed to `size`,
## which is the outer footprint the room occupies in the world.
func interior_size() -> Vector3:
	return Vector3(
		maxf(0.0, size.x - side_thickness("east") - side_thickness("west")),
		maxf(0.0, ceiling_surface_y() - floor_surface_y()),
		maxf(0.0, size.z - side_thickness("north") - side_thickness("south")))

## The usable volume in world space, floor surface upward.
func interior_aabb() -> AABB:
	var isize := interior_size()
	return AABB(Vector3(
			global_position.x - isize.x / 2.0 + (side_thickness("west") - side_thickness("east")) / 2.0,
			floor_surface_y(),
			global_position.z - isize.z / 2.0 + (side_thickness("north") - side_thickness("south")) / 2.0),
		isize)

## One line describing the difference between declared and usable space, for
## announcements where the user is about to author a coordinate by hand.
func interior_report() -> String:
	var isize := interior_size()
	return "stand at y %.2f, interior %.1f by %.1f by %.1f m" % 			[floor_surface_y(), isize.x, isize.y, isize.z]

func entity_label() -> String:
	# The floor height is included because it is the number you need whenever you
	# place something by hand, and it is never equal to the room's own y.
	return "%s (room, %.0fx%.0fx%.0f m, floor y %.2f)" % 			[name, size.x, size.y, size.z, floor_surface_y()]

func contains_point(p: Vector3) -> bool:
	var lp := p - global_position
	return absf(lp.x) <= size.x / 2.0 and lp.y >= 0 and lp.y <= size.y and absf(lp.z) <= size.z / 2.0

func bounding_volume() -> float:
	return size.x * size.y * size.z

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
	return CardinalDir.opposite(side)

func has_wall(_side: String) -> bool:
	return true

func connection_probe_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for side in ["north", "south", "east", "west"]:
		var wall_cfg := cfg(side)
		if wall_cfg == null or not wall_cfg.enabled: continue
		result.append(_wall_face_dict(side))
	return result

## Includes all 4 cardinal walls regardless of enabled state, so gap detection
## still flags misaligned outdoor zones whose walls have been disabled.
func boundary_faces() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for side in ["north", "south", "east", "west"]:
		result.append(_wall_face_dict(side))
	return result

func _wall_face_dict(side: String) -> Dictionary:
	var normal: Vector3 = NORMALS[side]
	var face_center_world := global_position + _face_center_local(side)
	var face_width: float = size.x if side in ["north", "south"] else size.z
	return {
		"label": side + " wall",
		"normal": normal,
		"probe_world": face_center_world + normal * 0.05,
		"face_center_world": face_center_world,
		"face_width": face_width,
		"face_height": size.y,
	}

func _face_center_local(side: String) -> Vector3:
	match side:
		"north": return Vector3(0, size.y / 2.0, -size.z / 2.0)
		"south": return Vector3(0, size.y / 2.0,  size.z / 2.0)
		"east":  return Vector3( size.x / 2.0, size.y / 2.0, 0)
		"west":  return Vector3(-size.x / 2.0, size.y / 2.0, 0)
	return Vector3.ZERO

func punch_doorway(side: String, width := 1.2, height := 2.1) -> void:
	## Appends a centred doorway sitting on top of the floor slab.
	var floor_thickness: float = wall_floor.thickness if wall_floor else 0.0
	add_doorway(side, 0.0, -size.y / 2.0 + height / 2.0 + floor_thickness, width, height)

func punch_hole(side: String, center_u: float, center_v: float, width := 0.9, height := 0.9) -> void:
	## Appends a hole centred at (center_u, center_v) in wall local metres. Suitable for windows.
	add_doorway(side, center_u, center_v, width, height)

func add_doorway(side: String, center_u: float, center_v: float, width := 1.2, height := 2.1, label := "") -> void:
	## Appends a doorway at a walllocal position. center_u/v in metres, origin = wall centre.
	var d := DoorEntry.new()
	d.side = side; d.center_u = center_u; d.center_v = center_v
	d.width = width; d.height = height; d.label = label
	d.ensure_id()
	door_list.append(d)
	_queue_rebuild()

func remove_door(idx: int) -> void:
	if idx >= 0 and idx < door_list.size():
		door_list.remove_at(idx)
		_queue_rebuild()

## Replaces the whole door list and rebuilds. This is the single entry point
## used by undo/redo (EditOps.swap_doors): swapping the array wholesale avoids
## the index-shift hazards of undoing individual door additions or removals.
func apply_door_list(list: Array[DoorEntry]) -> void:
	door_list = list
	_queue_rebuild()
