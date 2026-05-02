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

## Which cardinal direction is the HIGH (upper) end of the ramp.
@export_enum("north", "south", "east", "west") var high_end: String = "north": set = _set_dir

@export var surface_floor: String = "ramp": set = _set_sf
@export var surface_walls: String = "concrete": set = _set_sw
@export var surface_ceiling: String = "concrete": set = _set_sc

@export var wall_sides_enabled: bool = true: set = _set_we
@export var ceiling_enabled: bool = true: set = _set_ce

@export var rebuild_now: bool = false: set = _trigger

var _rebuild_queued := false
var _rebuild_gen := 0

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

func _queue_rebuild() -> void:
	if is_inside_tree() and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild_gen += 1
		call_deferred("rebuild")

func rebuild() -> void:
	_rebuild_queued = false
	var my_gen := _rebuild_gen
	if not Engine.is_editor_hint(): return
	for c in get_children():
		if c.has_meta("generated") or c.has_meta("ramp_area"): c.queue_free()
	await get_tree().process_frame
	if _rebuild_gen != my_gen: return
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
	# Center is at the midpoint of the slope surface.
	# In the horizontal plane it is at the ramp origin (x=0, z=0).
	# In Y it is at height_change/2 (average of low=0 and high=height_change).
	var floor_center: Vector3 = Vector3.UP * (height_change / 2.0)
	_spawn_panel("floor", surface_floor,
		floor_center, perp_dir, slope_dir,
		Rect2(-width / 2.0, -slope_length / 2.0, width, slope_length), 0)

	# ---- Ceiling ----
	if ceiling_enabled:
		# Parallel to the floor, shifted straight up by clearance.
		var ceil_center: Vector3 = floor_center + Vector3.UP * clearance
		_spawn_panel("ceiling", surface_ceiling,
			ceil_center, perp_dir, slope_dir,
			Rect2(-width / 2.0, -slope_length / 2.0, width, slope_length), 0)

	# ---- Side walls ----
	# Each side wall is a parallelogram: bu = slope_dir, bv = UP.
	# Its center sits at plus-minus(width/2) along perp_dir, half-way up in Y (floor+ceiling midpoint),
	# and at the horizontal centre of the ramp (the ramp origin in the travel direction).
	if wall_sides_enabled:
		var wall_center_y: float = (height_change + clearance) / 2.0
		for sign in [-1, 1]:
			var wall_center: Vector3 = perp_dir * (sign * width / 2.0) + Vector3.UP * wall_center_y
			_spawn_panel("wall", surface_walls,
				wall_center, slope_dir, Vector3.UP,
				Rect2(-slope_length / 2.0, -clearance / 2.0, slope_length, clearance),
				(0 if sign < 0 else 1))

func _spawn_panel(side: String, surface: String,
		center: Vector3, bu: Vector3, bv: Vector3,
		r: Rect2, idx: int) -> void:
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

	body.add_child(mi)
	body.add_child(cs)
	add_child(body)

	# Orient: local Z of the panel aligns with the surface normal.
	var normal := bu.cross(bv).normalized()
	var t := Transform3D()
	t.basis = Basis(bu, bv, normal)
	t.origin = center + bu * (r.position.x + r.size.x / 2.0) + bv * (r.position.y + r.size.y / 2.0)
	body.transform = t

	var root := get_tree().edited_scene_root
	if root:
		for n: Node in [body, mi, cs]: n.owner = root

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
## of the HIGH-end room should be placed so its floor aligns with the ramp exit.
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
## of the LOW-end room should be placed so its wall is flush with the ramp entry.
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
	var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
	return opp[high_end]

# SpatialEntity3D neighbour interface -------------------------------------------

func neighbor_offset(side: String, other_size: Vector3) -> Vector3:
	if side == high_end:
		return high_end_room_offset(other_size)
	var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
	if side == opp.get(high_end, ""):
		return low_end_room_offset(other_size)
	return Vector3.ZERO   # perpendicular side ramps only connect on two sides

func neighbor_doorway_side(side: String) -> String:
	if side == high_end:
		return room_side_at_high_end()
	var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
	if side == opp.get(high_end, ""):
		return room_side_at_low_end()
	return ""

func has_wall(_side: String) -> bool:
	return false   # ramp ends are open.  nothing to punch a doorway through
