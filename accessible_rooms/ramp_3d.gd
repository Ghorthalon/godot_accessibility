@tool
class_name Ramp3D
extends SpatialEntity3D

## A sloped connector between two rooms at different floor heights.
##
## Origin: centre of the TOTAL footprint at y = 0 = the LOW end's room base
## level (the source room's position.y). The total footprint spans ±length/2
## along travel_dir; the low landing occupies the first landing_depth_low along
## travel, the high landing the last landing_depth_high, and the slope fills
## the middle. Low-end walking surface sits at y = floor_thickness, high-end
## walking surface at y = floor_thickness + height_change, each flush with its
## adjacent room's floor top.
##
## The ramp is one self-contained object: connecting rooms attach flush to
## the low or high end face and only need a normal-height doorway, because
## all climbing happens inside the ramp's own walls and clearance volume.
##
## high_end names the direction toward the UPPER end of the ramp.
## Example: high_end = "north" means the ramp rises as you travel north (-Z).

## Label prefix used by apply_doors_to_rooms() to namespace ramp-owned
## doorway entries it pushes onto adjacent room.door_list arrays.
const DOOR_LABEL_PREFIX := "ramp:"

@export var width: float = 2.0: set = _set_width
@export var length: float = 4.0: set = _set_length   # TOTAL horizontal footprint (landings + slope)
@export var height_change: float = 1.0: set = _set_hc  # vertical rise low-high
@export var clearance: float = 2.4: set = _set_cl    # vertical clearance floor-ceiling
@export var floor_thickness: float = 0.1: set = _set_ft  # matches connecting room's floor slab

## Which cardinal direction is the high end of the ramp.
@export_enum("north", "south", "east", "west") var high_end: String = "north": set = _set_dir

@export var surface_floor: String = "ramp": set = _set_sf
@export var surface_walls: String = "concrete": set = _set_sw
@export var surface_ceiling: String = "concrete": set = _set_sc

@export var wall_sides_enabled: bool = true: set = _set_we
@export var ceiling_enabled: bool = true: set = _set_ce

## Flat landing slabs at each end of the ramp, carved out of the total
## length footprint. The slope occupies the middle (length - landing_depth_low
## - landing_depth_high). Set to 0 to omit that landing. the slope then runs
## flush to that end of the footprint.
@export var landing_depth_low:  float = 0.5: set = _set_lld
@export var landing_depth_high: float = 0.5: set = _set_ldh

## Doorways this ramp owns. Each entry's `side` is "low" or "high".
## apply_doors_to_rooms() mirrors them onto the connected rooms' door_lists.
@export var door_list: Array[DoorEntry] = []

@export var rebuild_now: bool = false: set = _trigger

func _set_width(v):  width = v;          _queue_rebuild()
func _set_length(v): length = v;         _queue_rebuild()
func _set_hc(v):     height_change = v;  _queue_rebuild()
func _set_cl(v):     clearance = v;      _queue_rebuild()
func _set_ft(v):     floor_thickness = v; _queue_rebuild()
func _set_dir(v):    high_end = v;       _queue_rebuild()
func _set_sf(v):     surface_floor = v;  _queue_rebuild()
func _set_sw(v):     surface_walls = v;  _queue_rebuild()
func _set_sc(v):     surface_ceiling = v; _queue_rebuild()
func _set_we(v):     wall_sides_enabled = v; _queue_rebuild()
func _set_ce(v):     ceiling_enabled = v;    _queue_rebuild()
func _set_lld(v):    landing_depth_low = v;  _queue_rebuild()
func _set_ldh(v):    landing_depth_high = v; _queue_rebuild()
func _trigger(_v):   rebuild()

func rebuild() -> void:
	_rebuild_queued = false
	var my_gen := _rebuild_gen
	if not Engine.is_editor_hint(): return
	for c in get_children():
		if c.has_meta("generated") or c.has_meta("ramp_area"):
			remove_child(c)
			c.queue_free()
	if _check_rebuild_stale(my_gen): return
	_build_ramp()
	_build_ramp_area()
	apply_doors_to_rooms()

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

## Returns (travel_dir, perp_dir) as horizontal unit vectors.
## travel_dir points from the LOW end toward the HIGH end.
## perp_dir is perpendicular to travel in the horizontal plane used as bu for floor/ceiling.
func _get_dirs() -> Array[Vector3]:
	match high_end:
		"north": return [Vector3(0, 0, -1), Vector3(1, 0, 0)]   # travel -Z, perp +X
		"south": return [Vector3(0, 0,  1), Vector3(1, 0, 0)]   # travel +Z, perp +X
		"east":  return [Vector3(1, 0,  0), Vector3(0, 0, 1)]   # travel +X, perp +Z
		"west":  return [Vector3(-1, 0, 0), Vector3(0, 0, 1)]   # travel -X, perp +Z
	return [Vector3(0, 0, -1), Vector3(1, 0, 0)]

func _build_ramp() -> void:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var perp_dir: Vector3   = dirs[1]
	var ft: float = floor_thickness
	var ld_low: float = maxf(0.0, landing_depth_low)
	var ld_high: float = maxf(0.0, landing_depth_high)
	var half_total: float = length / 2.0

	# Slope occupies the middle of the total footprint, with landings carved
	# out of each end. If asymmetric landings, the slope shifts toward the
	# smaller-landing side.
	var slope_length_h: float = _slope_length_h()
	var slope_center_off: float = (ld_low - ld_high) / 2.0

	# slope_dir: unit vector from the low end to the high end along the surface.
	var slope_dir: Vector3 = (travel_dir * slope_length_h + Vector3.UP * height_change).normalized()
	var slope_hyp: float = sqrt(slope_length_h * slope_length_h + height_change * height_change)

	# ---- Sloped floor (lifted by floor_thickness so walking surfaces align with rooms) ----
	var floor_center: Vector3 = travel_dir * slope_center_off + Vector3.UP * (ft + height_change / 2.0)
	var floor_sz := Vector3(width, slope_hyp, WALL_THICKNESS)
	var floor_normal := perp_dir.cross(slope_dir).normalized()
	var landing_normal := perp_dir.cross(travel_dir).normalized()  # = UP
	_spawn_box(self, "floor_0", Transform3D(Basis(perp_dir, slope_dir, floor_normal), floor_center), floor_sz, surface_floor)

	# ---- Sloped ceiling ----
	if ceiling_enabled:
		var ceil_center: Vector3 = floor_center + Vector3.UP * clearance
		_spawn_box(self, "ceiling_0", Transform3D(Basis(perp_dir, slope_dir, floor_normal), ceil_center), floor_sz, surface_ceiling)

	# ---- Landings: walking surfaces inside the total footprint at each end ----
	# Set landing_depth_low/high = 0 to omit (slope then runs to that edge).
	if ld_low > 0.0:
		var low_landing_sz := Vector3(width, ld_low, ft)
		var low_landing_center: Vector3 = \
			travel_dir * (-half_total + ld_low / 2.0) + Vector3.UP * (ft / 2.0)
		_spawn_box(self, "landing_low",
			Transform3D(Basis(perp_dir, travel_dir, landing_normal), low_landing_center), low_landing_sz, surface_floor)
		if ceiling_enabled:
			var low_ceil_sz := Vector3(width, ld_low, WALL_THICKNESS)
			var low_ceil_center: Vector3 = \
				travel_dir * (-half_total + ld_low / 2.0) + Vector3.UP * (ft + clearance)
			_spawn_box(self, "ceiling_low",
				Transform3D(Basis(perp_dir, travel_dir, landing_normal), low_ceil_center), low_ceil_sz, surface_ceiling)

	if ld_high > 0.0:
		var high_landing_sz := Vector3(width, ld_high, ft)
		var high_landing_center: Vector3 = \
			travel_dir * (half_total - ld_high / 2.0) + Vector3.UP * (height_change + ft / 2.0)
		_spawn_box(self, "landing_high",
			Transform3D(Basis(perp_dir, travel_dir, landing_normal), high_landing_center), high_landing_sz, surface_floor)
		if ceiling_enabled:
			var high_ceil_sz := Vector3(width, ld_high, WALL_THICKNESS)
			var high_ceil_center: Vector3 = \
				travel_dir * (half_total - ld_high / 2.0) + Vector3.UP * (ft + height_change + clearance)
			_spawn_box(self, "ceiling_high",
				Transform3D(Basis(perp_dir, travel_dir, landing_normal), high_ceil_center), high_ceil_sz, surface_ceiling)

	# ---- Side walls: parallelogram over the slope, flat extensions over each landing ----
	if wall_sides_enabled:
		var slope_wall_center_y: float = ft + (height_change + clearance) / 2.0
		var slope_wall_sz := Vector3(slope_hyp, clearance, WALL_THICKNESS)
		var slope_wall_normal := slope_dir.cross(Vector3.UP).normalized()
		var landing_wall_normal := travel_dir.cross(Vector3.UP).normalized()
		for sign in [-1, 1]:
			var slope_wall_center: Vector3 = perp_dir * (sign * width / 2.0) + \
				travel_dir * slope_center_off + Vector3.UP * slope_wall_center_y
			_spawn_box(self, "wall_%d" % (0 if sign < 0 else 1),
				Transform3D(Basis(slope_dir, Vector3.UP, slope_wall_normal), slope_wall_center), slope_wall_sz, surface_walls)
			if ld_low > 0.0:
				var low_wall_sz := Vector3(ld_low, clearance, WALL_THICKNESS)
				var low_wall_center: Vector3 = perp_dir * (sign * width / 2.0) + \
					travel_dir * (-half_total + ld_low / 2.0) + \
					Vector3.UP * (ft + clearance / 2.0)
				_spawn_box(self, "wall_low_%d" % (0 if sign < 0 else 1),
					Transform3D(Basis(travel_dir, Vector3.UP, landing_wall_normal), low_wall_center), low_wall_sz, surface_walls)
			if ld_high > 0.0:
				var high_wall_sz := Vector3(ld_high, clearance, WALL_THICKNESS)
				var high_wall_center: Vector3 = perp_dir * (sign * width / 2.0) + \
					travel_dir * (half_total - ld_high / 2.0) + \
					Vector3.UP * (ft + height_change + clearance / 2.0)
				_spawn_box(self, "wall_high_%d" % (0 if sign < 0 else 1),
					Transform3D(Basis(travel_dir, Vector3.UP, landing_wall_normal), high_wall_center), high_wall_sz, surface_walls)

func _build_ramp_area() -> void:
	var area := Area3D.new()
	area.set_meta("ramp_area", true)
	area.name = "RampArea"
	var perp_dir: Vector3 = _get_dirs()[1]
	var total_h: float = floor_thickness + height_change + clearance
	var aabb_size := Vector3(
		width  if absf(perp_dir.x) > 0.5 else length,
		total_h,
		width  if absf(perp_dir.z) > 0.5 else length
	)
	match high_end:
		"east", "west":
			aabb_size = Vector3(length, total_h, width)
	area.position = Vector3(0, total_h / 2.0, 0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb_size
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
	return "%s (ramp, %.1fm wide, %.1fm long, rises %.1fm toward %s, %.0f deg)" % \
		[name, width, length, height_change, high_end, slope_degrees()]

func contains_point(p: Vector3) -> bool:
	var lp := p - position
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var perp_dir: Vector3 = dirs[1]
	var lp_travel: float = lp.dot(travel_dir)
	var lp_perp: float = lp.dot(perp_dir)
	var half_w: float = width / 2.0
	var half_l: float = length / 2.0
	var max_y: float = floor_thickness + height_change + clearance
	if lp.y < 0.0 or lp.y > max_y: return false
	if absf(lp_perp) > half_w: return false
	if absf(lp_travel) > half_l: return false
	return true

func bounding_volume() -> float:
	return width * length * (floor_thickness + height_change + clearance)

func populate_properties_ui(c: VBoxContainer) -> void:
	_add_spinbox(c, "W:",         0.5,  50.0,  0.5,  width)
	_add_spinbox(c, "Len:",       0.5, 100.0,  0.5,  length)
	_add_spinbox(c, "Rise:",      0.1,  20.0,  0.1,  height_change)
	_add_spinbox(c, "Clear:",     1.0,  10.0,  0.1,  clearance)
	_add_spinbox(c, "Floor t:",   0.0,   1.0,  0.05, floor_thickness)
	_add_spinbox(c, "Land low:",  0.0,  10.0,  0.1,  landing_depth_low)
	_add_spinbox(c, "Land high:", 0.0,  10.0,  0.1,  landing_depth_high)

func apply_properties_ui(c: VBoxContainer) -> void:
	var spins: Array[SpinBox] = []
	for row in c.get_children():
		for child in row.get_children():
			if child is SpinBox: spins.append(child as SpinBox)
	if spins.size() >= 7:
		width              = spins[0].value
		length             = spins[1].value
		height_change      = spins[2].value
		clearance          = spins[3].value
		floor_thickness    = spins[4].value
		landing_depth_low  = spins[5].value
		landing_depth_high = spins[6].value

# ---------------------------------------------------------------------------
# Placement helpers (used by tab_rooms.gd)
# ---------------------------------------------------------------------------

## Horizontal length of the sloped section, with the landings carved out of `length`.
func _slope_length_h() -> float:
	return maxf(0.01, length - maxf(0.0, landing_depth_low) - maxf(0.0, landing_depth_high))

## Slope angle in degrees. Useful for accessibility announcements.
func slope_degrees() -> float:
	return rad_to_deg(atan2(height_change, _slope_length_h()))

## Returns the worldspace offset from this ramp's position to where the centre
## of the high end room should be placed so its wall is flush with the ramp's
## high-end face and its floor aligns with the top landing.
func high_end_room_offset(other_size: Vector3) -> Vector3:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var travel_depth: float = _travel_depth(other_size)
	return travel_dir * (length / 2.0 + travel_depth / 2.0) + Vector3.UP * height_change

## Returns the worldspace offset from this ramp's position to where the centre
## of the low end room should be placed so its wall is flush with the ramp entry.
func low_end_room_offset(other_size: Vector3) -> Vector3:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var travel_depth: float = _travel_depth(other_size)
	return -travel_dir * (length / 2.0 + travel_depth / 2.0)

## Given a room size, return the depth of that room in the ramp's travel direction.
func _travel_depth(room_size: Vector3) -> float:
	match high_end:
		"north", "south": return room_size.z
		"east",  "west":  return room_size.x
	return room_size.z

## The wall side on the room that faces the LOW end of this ramp.
## Used to punch the connecting doorway.
func room_side_at_low_end() -> String:
	match high_end:
		"north": return "north"   # ramp travels north; connects to the north wall of the source room
		"south": return "south"
		"east":  return "east"
		"west":  return "west"
	return "north"

## The wall side on the room that faces the HIGH end of this ramp.
func room_side_at_high_end() -> String:
	return CardinalDir.opposite(high_end)

# SpatialEntity3D neighbour interface -------------------------------------------

func neighbor_offset(side: String, other_size: Vector3) -> Vector3:
	if side == high_end:
		return high_end_room_offset(other_size)
	if side == CardinalDir.opposite(high_end):
		return low_end_room_offset(other_size)
	return Vector3.ZERO   # perpendicular side ramps only connect on two sides

func neighbor_doorway_side(side: String) -> String:
	if side == high_end:
		return room_side_at_high_end()
	if side == CardinalDir.opposite(high_end):
		return room_side_at_low_end()
	return ""

func has_wall(_side: String) -> bool:
	return false   # ramp ends are open.  nothing to punch a doorway through

func connection_probe_points() -> Array[Dictionary]:
	var travel_dir: Vector3 = _get_dirs()[0]
	var ft: float = floor_thickness
	var low_center  := position + (-travel_dir * (length / 2.0)) + Vector3.UP * (ft + clearance / 2.0)
	var high_center := position + ( travel_dir * (length / 2.0)) + Vector3.UP * (ft + height_change + clearance / 2.0)
	return [
		{"label": "low end",  "normal": -travel_dir,
		 "probe_world": low_center  + (-travel_dir) * 0.05,
		 "face_center_world": low_center,  "face_width": width, "face_height": clearance},
		{"label": "high end", "normal": travel_dir,
		 "probe_world": high_center + travel_dir * 0.05,
		 "face_center_world": high_center, "face_width": width, "face_height": clearance},
	]

# ---------------------------------------------------------------------------
# Doorway ownership: mirror our door_list onto the connected rooms
# ---------------------------------------------------------------------------

## Mirrors entries in `door_list` to the connected source / destination rooms.
## See Stairs3D.apply_doors_to_rooms() for the namespacing convention.
func apply_doors_to_rooms() -> void:
	if not is_inside_tree(): return
	if get_tree() == null: return
	var my_prefix := DOOR_LABEL_PREFIX + name + ":"
	var low_room := _find_connected_room(true)
	var high_room := _find_connected_room(false)
	var rooms_to_rebuild: Array[Room3D] = []
	for r_any in [low_room, high_room]:
		if r_any == null: continue
		var room: Room3D = r_any
		var before := room.door_list.size()
		room.door_list = room.door_list.filter(func(d: DoorEntry) -> bool:
			return d == null or not d.label.begins_with(my_prefix))
		if room.door_list.size() != before and room not in rooms_to_rebuild:
			rooms_to_rebuild.append(room)
	for d in door_list:
		if d == null: continue
		var target_room: Room3D
		var room_side: String
		if d.side == "low":
			target_room = low_room
			room_side = room_side_at_low_end()
		elif d.side == "high":
			target_room = high_room
			room_side = room_side_at_high_end()
		else:
			continue
		if target_room == null: continue
		var mirror := DoorEntry.new()
		mirror.side = room_side
		mirror.center_u = d.center_u
		mirror.center_v = d.center_v
		mirror.width = d.width
		mirror.height = d.height
		mirror.label = my_prefix + d.side
		if d.label != "":
			mirror.label += " (" + d.label + ")"
		mirror.scene_path = d.scene_path
		target_room.door_list.append(mirror)
		if target_room not in rooms_to_rebuild:
			rooms_to_rebuild.append(target_room)
	for room in rooms_to_rebuild:
		room._queue_rebuild()

func _find_connected_room(at_low_end: bool) -> Room3D:
	if not is_inside_tree(): return null
	var travel_dir: Vector3 = _get_dirs()[0]
	var room_side: String
	var ramp_floor_y: float
	var edge_pos: Vector3
	if at_low_end:
		room_side = room_side_at_low_end()
		ramp_floor_y = position.y
		edge_pos = position + (-travel_dir * (length / 2.0))
	else:
		room_side = room_side_at_high_end()
		ramp_floor_y = position.y + height_change
		edge_pos = position + ( travel_dir * (length / 2.0))
	var ramp_min: float
	var ramp_max: float
	match room_side:
		"north", "south":
			ramp_min = position.x - width / 2.0
			ramp_max = position.x + width / 2.0
		"east", "west":
			ramp_min = position.z - width / 2.0
			ramp_max = position.z + width / 2.0
		_: return null
	for node in get_tree().get_nodes_in_group("accessible_rooms_rooms"):
		if not node is Room3D: continue
		var room := node as Room3D
		var room_plane: float = Room3D._wall_plane_coord(room, room_side)
		var ramp_plane: float
		match room_side:
			"north", "south": ramp_plane = edge_pos.z
			"east", "west":   ramp_plane = edge_pos.x
		if absf(room_plane - ramp_plane) > EPSILON: continue
		if absf(room.position.y - ramp_floor_y) > EPSILON: continue
		var room_min: float
		var room_max: float
		match room_side:
			"north", "south":
				room_min = room.position.x - room.size.x / 2.0
				room_max = room.position.x + room.size.x / 2.0
			"east", "west":
				room_min = room.position.z - room.size.z / 2.0
				room_max = room.position.z + room.size.z / 2.0
		if ramp_min < room_min - EPSILON: continue
		if ramp_max > room_max + EPSILON: continue
		return room
	return null

func _exit_tree() -> void:
	var tree := get_tree()
	if tree == null: return
	var prefix := DOOR_LABEL_PREFIX + name + ":"
	for node in tree.get_nodes_in_group("accessible_rooms_rooms"):
		if not node is Room3D: continue
		var room := node as Room3D
		var before := room.door_list.size()
		room.door_list = room.door_list.filter(func(d: DoorEntry) -> bool:
			return d == null or not d.label.begins_with(prefix))
		if room.door_list.size() != before:
			room._queue_rebuild()
