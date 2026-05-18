@tool
class_name Ramp3D
extends SpatialEntity3D

## A sloped connector between two rooms at different floor heights.
##
## Position match Room3D: origin is at the centre of the horizontal
## footprint at y = 0 the LOW end's floor level.
##
## high_end names the direction toward the UPPER end of the ramp.
## Example: high_end = "north" means the ramp rises as you travel north (-Z).

@export var width: float = 2.0: set = _set_width
@export var length: float = 4.0: set = _set_length   # horizontal ground distance
@export var height_change: float = 1.0: set = _set_hc  # vertical rise low-high
@export var clearance: float = 2.4: set = _set_cl    # vertical clearance floor-ceiling

## Which cardinal direction is the high end of the ramp.
@export_enum("north", "south", "east", "west") var high_end: String = "north": set = _set_dir

@export var surface_floor: String = "ramp": set = _set_sf
@export var surface_walls: String = "concrete": set = _set_sw
@export var surface_ceiling: String = "concrete": set = _set_sc

@export var wall_sides_enabled: bool = true: set = _set_we
@export var ceiling_enabled: bool = true: set = _set_ce

@export var rebuild_now: bool = false: set = _trigger

func _set_width(v):  width = v;          _queue_rebuild()
func _set_length(v): length = v;         _queue_rebuild()
func _set_hc(v):     height_change = v;  _queue_rebuild()
func _set_cl(v):     clearance = v;      _queue_rebuild()
func _set_dir(v):    high_end = v;       _queue_rebuild()
func _set_sf(v):     surface_floor = v;  _queue_rebuild()
func _set_sw(v):     surface_walls = v;  _queue_rebuild()
func _set_sc(v):     surface_ceiling = v; _queue_rebuild()
func _set_we(v):     wall_sides_enabled = v; _queue_rebuild()
func _set_ce(v):     ceiling_enabled = v;    _queue_rebuild()
func _trigger(_v):   rebuild()

func rebuild() -> void:
	_rebuild_queued = false
	var my_gen := _rebuild_gen
	if not Engine.is_editor_hint(): return
	for c in get_children():
		if c.has_meta("generated") or c.has_meta("ramp_area"): c.queue_free()
	await get_tree().process_frame
	if _check_rebuild_stale(my_gen): return
	_build_ramp()
	_build_ramp_area()

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

	# slope_dir: unit vector that goes from the low end to the high end along the surface.
	var slope_dir: Vector3 = (travel_dir * length + Vector3.UP * height_change).normalized()
	var slope_length: float = sqrt(length * length + height_change * height_change)

	# ---- Floor ----
	var floor_center: Vector3 = Vector3.UP * (height_change / 2.0)
	var floor_sz := Vector3(width, slope_length, WALL_THICKNESS)
	var floor_normal := perp_dir.cross(slope_dir).normalized()
	_spawn_box(self, "floor_0", Transform3D(Basis(perp_dir, slope_dir, floor_normal), floor_center), floor_sz, surface_floor)

	# ---- Ceiling ----
	if ceiling_enabled:
		var ceil_center: Vector3 = floor_center + Vector3.UP * clearance
		_spawn_box(self, "ceiling_0", Transform3D(Basis(perp_dir, slope_dir, floor_normal), ceil_center), floor_sz, surface_ceiling)

	# ---- Side walls ----
	if wall_sides_enabled:
		var wall_center_y: float = (height_change + clearance) / 2.0
		var wall_sz := Vector3(slope_length, clearance, WALL_THICKNESS)
		var wall_normal := slope_dir.cross(Vector3.UP).normalized()
		for sign in [-1, 1]:
			var wall_center: Vector3 = perp_dir * (sign * width / 2.0) + Vector3.UP * wall_center_y
			_spawn_box(self, "wall_%d" % (0 if sign < 0 else 1),
				Transform3D(Basis(slope_dir, Vector3.UP, wall_normal), wall_center), wall_sz, surface_walls)

func _build_ramp_area() -> void:
	var area := Area3D.new()
	area.set_meta("ramp_area", true)
	area.name = "RampArea"
	# AABB enclosing the ramp volume: full horizontal footprint, full vertical extent.
	var dirs := _get_dirs()
	var perp_dir: Vector3 = dirs[1]
	# The AABB bounding box in world space (axis-aligned).
	var aabb_size := Vector3(
		width  if absf(perp_dir.x) > 0.5 else length,
		height_change + clearance,
		width  if absf(perp_dir.z) > 0.5 else length
	)
	# For east/west ramps the horizontal dimensions swap.
	match high_end:
		"east", "west":
			aabb_size = Vector3(length, height_change + clearance, width)
	area.position = Vector3(0, (height_change + clearance) / 2.0, 0)
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
	var half_w := width / 2.0
	var half_l := length / 2.0
	match high_end:
		"north", "south":
			return absf(lp.x) <= half_w and lp.y >= 0 and \
				lp.y <= height_change + clearance and absf(lp.z) <= half_l
		"east", "west":
			return absf(lp.z) <= half_w and lp.y >= 0 and \
				lp.y <= height_change + clearance and absf(lp.x) <= half_l
	return false

func bounding_volume() -> float:
	return width * length * (height_change + clearance)

func populate_properties_ui(c: VBoxContainer) -> void:
	_add_spinbox(c, "W:",     0.5, 50.0,  0.5, width)
	_add_spinbox(c, "Len:",   0.5, 100.0, 0.5, length)
	_add_spinbox(c, "Rise:",  0.1, 20.0,  0.1, height_change)
	_add_spinbox(c, "Clear:", 1.0, 10.0,  0.1, clearance)

func apply_properties_ui(c: VBoxContainer) -> void:
	var spins: Array[SpinBox] = []
	for row in c.get_children():
		for child in row.get_children():
			if child is SpinBox: spins.append(child as SpinBox)
	if spins.size() >= 4:
		width         = spins[0].value
		length        = spins[1].value
		height_change = spins[2].value
		clearance     = spins[3].value

# ---------------------------------------------------------------------------
# Placement helpers (used by tab_rooms.gd)
# ---------------------------------------------------------------------------

## Slope angle in degrees. Useful for accessibility announcements.
func slope_degrees() -> float:
	return rad_to_deg(atan2(height_change, length))

## Returns the worldspace offset from this ramp's position to where the centre
## of the high end room should be placed so its floor aligns with the ramp exit.
##
## other_size is the size of the room being placed at the high end.
func high_end_room_offset(other_size: Vector3) -> Vector3:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	# Move half the ramp length + half the other room's depth along travel direction,
	# and rise by height_change.
	var travel_depth: float = _travel_depth(other_size)
	return travel_dir * (length / 2.0 + travel_depth / 2.0) + Vector3.UP * height_change

## Returns the worldspace offset from this ramp's position to where the centre
## of the low end room should be placed so its wall is flush with the ramp entry.
##
## other_size is the size of the room being placed at the low end.
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
	var low_center  := position + (-travel_dir * length / 2.0) + Vector3.UP * (clearance / 2.0)
	var high_center := position + ( travel_dir * length / 2.0) + Vector3.UP * (height_change + clearance / 2.0)
	return [
		{"label": "low end",  "normal": -travel_dir,
		 "probe_world": low_center  + (-travel_dir) * 0.05,
		 "face_center_world": low_center,  "face_width": width, "face_height": clearance},
		{"label": "high end", "normal": travel_dir,
		 "probe_world": high_center + travel_dir * 0.05,
		 "face_center_world": high_center, "face_width": width, "face_height": clearance},
	]
