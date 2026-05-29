@tool
class_name Ramp3D
extends SpatialEntity3D

## Pure climbing geometry: sloped floor with optional landings.
##
## A Ramp3D is meant to live as a child of a Room3D. the parent room owns
## walls/ceiling/floor and auto-cuts a ceiling opening when the ramp pokes
## through. Without a parent room, the ramp is just a naked slope in world space.
##
## Origin: centre of the TOTAL footprint at y = 0 (the ramp's local base).
## The total footprint spans ±length/2 along travel_dir; the low landing
## occupies the first landing_depth_low along travel, the high landing the
## last landing_depth_high, and the slope fills the middle. Low-end walking
## surface sits at y = floor_thickness, high-end walking surface at
## y = floor_thickness + height_change.
##
## high_end names the direction toward the UPPER end of the ramp.
## Example: high_end = "north" means the ramp rises as you travel north (-Z).

@export var width: float = 2.0: set = _set_width
@export var length: float = 4.0: set = _set_length   # TOTAL horizontal footprint (landings + slope)
@export var height_change: float = 1.0: set = _set_hc  # vertical rise low-high
@export var clearance: float = 2.4: set = _set_cl    # vertical clearance floor-ceiling
@export var floor_thickness: float = 0.1: set = _set_ft  # matches connecting room's floor slab

## Which cardinal direction is the high end of the ramp.
@export_enum("north", "south", "east", "west") var high_end: String = "north": set = _set_dir

@export var surface_floor: String = "ramp": set = _set_sf

## Flat landing slabs at each end of the ramp, carved out of the total
## length footprint. The slope occupies the middle (length - landing_depth_low
## - landing_depth_high). Set to 0 to omit that landing. the slope then runs
## flush to that end of the footprint.
@export var landing_depth_low:  float = 0.5: set = _set_lld
@export var landing_depth_high: float = 0.5: set = _set_ldh

@export var rebuild_now: bool = false: set = _trigger

func _set_width(v):  width = v;          _queue_rebuild()
func _set_length(v): length = v;         _queue_rebuild()
func _set_hc(v):     height_change = v;  _queue_rebuild()
func _set_cl(v):     clearance = v;      _queue_rebuild()
func _set_ft(v):     floor_thickness = v; _queue_rebuild()
func _set_dir(v):    high_end = v;       _queue_rebuild()
func _set_sf(v):     surface_floor = v;  _queue_rebuild()
func _set_lld(v):    landing_depth_low = v;  _queue_rebuild()
func _set_ldh(v):    landing_depth_high = v; _queue_rebuild()
func _trigger(_v):   rebuild()

func _enter_tree() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_rebuild()

func _queue_rebuild() -> void:
	super._queue_rebuild()
	var p := get_parent()
	if p is Room3D:
		(p as Room3D)._queue_rebuild()

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

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

## Returns (travel_dir, perp_dir) as horizontal unit vectors.
## travel_dir points from the LOW end toward the HIGH end.
## perp_dir is perpendicular to travel in the horizontal plane.
func _get_dirs() -> Array[Vector3]:
	match high_end:
		"north": return [Vector3(0, 0, -1), Vector3(1, 0, 0)]
		"south": return [Vector3(0, 0,  1), Vector3(1, 0, 0)]
		"east":  return [Vector3(1, 0,  0), Vector3(0, 0, 1)]
		"west":  return [Vector3(-1, 0, 0), Vector3(0, 0, 1)]
	return [Vector3(0, 0, -1), Vector3(1, 0, 0)]

func _build_ramp() -> void:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var perp_dir: Vector3   = dirs[1]
	var ft: float = floor_thickness
	var ld_low: float = maxf(0.0, landing_depth_low)
	var ld_high: float = maxf(0.0, landing_depth_high)
	var half_total: float = length / 2.0

	var slope_length_h: float = _slope_length_h()
	var slope_center_off: float = (ld_low - ld_high) / 2.0

	var slope_dir: Vector3 = (travel_dir * slope_length_h + Vector3.UP * height_change).normalized()
	var slope_hyp: float = sqrt(slope_length_h * slope_length_h + height_change * height_change)

	# Sloped floor (lifted by floor_thickness so walking surfaces align with rooms)
	var floor_center: Vector3 = travel_dir * slope_center_off + Vector3.UP * (ft + height_change / 2.0)
	var floor_sz := Vector3(width, slope_hyp, WALL_THICKNESS)
	var floor_normal := perp_dir.cross(slope_dir).normalized()
	var landing_normal := perp_dir.cross(travel_dir).normalized()  # = UP
	_spawn_box(self, "floor_0", Transform3D(Basis(perp_dir, slope_dir, floor_normal), floor_center), floor_sz, surface_floor)

	# Landings: walking surfaces inside the total footprint at each end.
	if ld_low > 0.0:
		var low_landing_sz := Vector3(width, ld_low, ft)
		var low_landing_center: Vector3 = \
			travel_dir * (-half_total + ld_low / 2.0) + Vector3.UP * (ft / 2.0)
		_spawn_box(self, "landing_low",
			Transform3D(Basis(perp_dir, travel_dir, landing_normal), low_landing_center), low_landing_sz, surface_floor)

	if ld_high > 0.0:
		var high_landing_sz := Vector3(width, ld_high, ft)
		var high_landing_center: Vector3 = \
			travel_dir * (half_total - ld_high / 2.0) + Vector3.UP * (height_change + ft / 2.0)
		_spawn_box(self, "landing_high",
			Transform3D(Basis(perp_dir, travel_dir, landing_normal), high_landing_center), high_landing_sz, surface_floor)

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

## Footprint AABB in this ramp's local frame. The room uses this to compute
## a ceiling cutout when the ramp pokes through.
func footprint_local() -> AABB:
	var perp_dir: Vector3 = _get_dirs()[1]
	var total_h: float = floor_thickness + height_change + clearance
	var sx: float = width if absf(perp_dir.x) > 0.5 else length
	var sz: float = width if absf(perp_dir.z) > 0.5 else length
	return AABB(Vector3(-sx/2.0, 0.0, -sz/2.0), Vector3(sx, total_h, sz))

## True if this ramp's clearance volume exceeds a horizontal plane at world Y = ceiling_y.
func pokes_through_ceiling(ceiling_y: float) -> bool:
	return global_position.y + floor_thickness + height_change + clearance > ceiling_y + EPSILON

## Ceiling cutout in the parent room's ceiling-local 2D coords (u = room-local X,
## v = -room-local Z). Covers slope + high landing only, the low landing stays
## under the existing ceiling. Assumes the ramp has no rotation relative to its parent.
func ceiling_cutout_rect() -> Rect2:
	var ld_low: float = maxf(0.0, landing_depth_low)
	var half_total: float = length / 2.0
	var cut_len: float = length - ld_low
	var center_offset: float = ld_low / 2.0
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var local_center: Vector3 = travel_dir * center_offset
	var has_x_travel: bool = absf(travel_dir.x) > 0.5
	var sx: float = cut_len if has_x_travel else width
	var sz: float = width if has_x_travel else cut_len
	var cx: float = position.x + local_center.x
	var cz: float = position.z + local_center.z
	return Rect2(cx - sx / 2.0, -(cz + sz / 2.0), sx, sz)

# ---------------------------------------------------------------------------
# SpatialEntity3D interface
# ---------------------------------------------------------------------------

func entity_label() -> String:
	return "%s (ramp, %.1fm wide, %.1fm long, rises %.1fm toward %s, %.0f deg)" % \
		[name, width, length, height_change, high_end, slope_degrees()]

func contains_point(p: Vector3) -> bool:
	var lp := p - global_position
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

## Horizontal length of the sloped section, with the landings carved out of `length`.
func _slope_length_h() -> float:
	return maxf(0.01, length - maxf(0.0, landing_depth_low) - maxf(0.0, landing_depth_high))

## Slope angle in degrees. Useful for accessibility announcements.
func slope_degrees() -> float:
	return rad_to_deg(atan2(height_change, _slope_length_h()))

func has_wall(_side: String) -> bool:
	return false

func connection_probe_points() -> Array[Dictionary]:
	var travel_dir: Vector3 = _get_dirs()[0]
	var ft: float = floor_thickness
	var low_center  := global_position + (-travel_dir * (length / 2.0)) + Vector3.UP * (ft + clearance / 2.0)
	var high_center := global_position + ( travel_dir * (length / 2.0)) + Vector3.UP * (ft + height_change + clearance / 2.0)
	return [
		{"label": "low end",  "normal": -travel_dir,
		 "probe_world": low_center  + (-travel_dir) * 0.05,
		 "face_center_world": low_center,  "face_width": width, "face_height": clearance},
		{"label": "high end", "normal": travel_dir,
		 "probe_world": high_center + travel_dir * 0.05,
		 "face_center_world": high_center, "face_width": width, "face_height": clearance},
	]
