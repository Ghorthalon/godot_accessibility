@tool
class_name Stairs3D
extends SpatialEntity3D

## Pure climbing geometry: treads, risers, and landings.
##
## A Stairs3D is meant to live as a child of a Room3D. the parent room owns
## walls/ceiling/floor and auto-cuts a ceiling opening when the stair pokes
## through. Without a parent room, the stair is just naked treads in world space.
##
## Origin: centre of the TOTAL footprint at y = 0 (the stair's local base).
## The total footprint spans ±length/2 along travel_dir; the low landing
## occupies the first landing_depth_low along travel, the high landing the
## last landing_depth_high, and the sloped section fills the middle. Low-end
## walking surface sits at y = floor_thickness, high-end walking surface at
## y = floor_thickness + height_change.
##
## high_end names the direction toward the UPPER end of the staircase.
## Example: high_end = "north" means the staircase rises as you travel north (-Z).

@export var width: float = 2.0: set = _set_width
@export var height_change: float = 1.0: set = _set_hc  # total vertical rise low→high
@export var length: float = 4.0: set = _set_length      # TOTAL horizontal footprint (landings + slope)
@export var clearance: float = 2.4: set = _set_cl       # headroom above top step
@export var floor_thickness: float = 0.1: set = _set_ft  # matches connecting room's floor slab

## Which cardinal direction is the upper end of the staircase.
@export_enum("north", "south", "east", "west") var high_end: String = "north": set = _set_dir

## Number of steps. 0 = autocompute from ideal ~18 cm step height.
@export var step_count: int = 0: set = _set_sc

@export var surface_floor: String = "concrete": set = _set_sf

@export var risers_enabled: bool = true: set = _set_re

## Flat landing slabs at each end of the staircase, carved out of the total
## length footprint. The slope occupies the middle (length - landing_depth_low
## - landing_depth_high). Set to 0 to omit that landing. the slope then runs
## flush to that end of the footprint.
@export var landing_depth_low:  float = 0.5: set = _set_lld
@export var landing_depth_high: float = 0.5: set = _set_ldh

@export var rebuild_now: bool = false: set = _trigger

func _set_width(v):  width = v;           _queue_rebuild()
func _set_hc(v):     height_change = v;   _queue_rebuild()
func _set_length(v): length = v;          _queue_rebuild()
func _set_cl(v):     clearance = v;       _queue_rebuild()
func _set_ft(v):     floor_thickness = v; _queue_rebuild()
func _set_dir(v):    high_end = v;        _queue_rebuild()
func _set_sc(v):     step_count = v;      _queue_rebuild()
func _set_sf(v):     surface_floor = v;   _queue_rebuild()
func _set_re(v):     risers_enabled = v;  _queue_rebuild()
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
		if c.has_meta("generated") or c.has_meta("stairs_area"):
			remove_child(c)
			c.queue_free()
	if _check_rebuild_stale(my_gen): return
	_build_stairs()
	_build_stairs_area()

# Computed helpers

func _effective_step_count() -> int:
	if step_count > 0: return step_count
	return max(2, roundi(height_change / 0.18))

## Horizontal length of the sloped section, with the landings carved out of `length`.
func _slope_length_h() -> float:
	return maxf(0.01, length - maxf(0.0, landing_depth_low) - maxf(0.0, landing_depth_high))

func step_height() -> float:
	return height_change / float(_effective_step_count())

func step_depth() -> float:
	return _slope_length_h() / float(_effective_step_count())

func slope_degrees() -> float:
	return rad_to_deg(atan2(height_change, _slope_length_h()))

# Geometry

## Returns (travel_dir, perp_dir) as horizontal unit vectors.
## travel_dir points from the LOW end toward the HIGH end.
func _get_dirs() -> Array[Vector3]:
	match high_end:
		"north": return [Vector3(0, 0, -1), Vector3(1, 0, 0)]
		"south": return [Vector3(0, 0,  1), Vector3(1, 0, 0)]
		"east":  return [Vector3(1, 0,  0), Vector3(0, 0, 1)]
		"west":  return [Vector3(-1, 0, 0), Vector3(0, 0, 1)]
	return [Vector3(0, 0, -1), Vector3(1, 0, 0)]

func _build_stairs() -> void:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var perp_dir: Vector3   = dirs[1]

	var n := _effective_step_count()
	var sh := step_height()
	var ft: float = floor_thickness
	var ld_low: float = maxf(0.0, landing_depth_low)
	var ld_high: float = maxf(0.0, landing_depth_high)
	var half_total: float = length / 2.0

	var slope_length_h: float = _slope_length_h()
	var slope_half: float = slope_length_h / 2.0
	var slope_center_off: float = (ld_low - ld_high) / 2.0
	var sd: float = slope_length_h / float(n)

	# Treads and risers (lifted by floor_thickness so walking surface aligns with source room floor top)
	var tread_normal := perp_dir.cross(travel_dir).normalized()
	var tread_sz := Vector3(width, sd, WALL_THICKNESS)
	var riser_normal := perp_dir.cross(Vector3.UP).normalized()
	var riser_sz := Vector3(width, sh, WALL_THICKNESS)
	for i in n:
		var tread_center: Vector3 = \
			travel_dir * (slope_center_off + (-slope_half + (i + 0.5) * sd)) + \
			Vector3.UP * (ft + (i + 1) * sh)
		_spawn_box(self, "tread_%d" % i,
			Transform3D(Basis(perp_dir, travel_dir, tread_normal), tread_center), tread_sz, surface_floor)

		if risers_enabled:
			var riser_center: Vector3 = \
				travel_dir * (slope_center_off + (-slope_half + i * sd)) + \
				Vector3.UP * (ft + (i + 0.5) * sh)
			_spawn_box(self, "riser_%d" % i,
				Transform3D(Basis(perp_dir, Vector3.UP, riser_normal), riser_center), riser_sz, surface_floor)

	# Landings: walking surfaces inside the total footprint at each end,
	# flush in height with the adjacent room's floor top.
	if ld_low > 0.0:
		var low_landing_sz := Vector3(width, ld_low, ft)
		var low_landing_center: Vector3 = \
			travel_dir * (-half_total + ld_low / 2.0) + Vector3.UP * (ft / 2.0)
		_spawn_box(self, "landing_low",
			Transform3D(Basis(perp_dir, travel_dir, tread_normal), low_landing_center), low_landing_sz, surface_floor)

	if ld_high > 0.0:
		var high_landing_sz := Vector3(width, ld_high, ft)
		var high_landing_center: Vector3 = \
			travel_dir * (half_total - ld_high / 2.0) + Vector3.UP * (height_change + ft / 2.0)
		_spawn_box(self, "landing_high",
			Transform3D(Basis(perp_dir, travel_dir, tread_normal), high_landing_center), high_landing_sz, surface_floor)

func _build_stairs_area() -> void:
	var area := Area3D.new()
	area.set_meta("stairs_area", true)
	area.name = "StairsArea"
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

## Footprint AABB in this stair's local frame. The room uses this to compute
## a ceiling cutout when the stair pokes through.
func footprint_local() -> AABB:
	var perp_dir: Vector3 = _get_dirs()[1]
	var total_h: float = floor_thickness + height_change + clearance
	var sx: float = width if absf(perp_dir.x) > 0.5 else length
	var sz: float = width if absf(perp_dir.z) > 0.5 else length
	return AABB(Vector3(-sx/2.0, 0.0, -sz/2.0), Vector3(sx, total_h, sz))

## True if this stair's clearance volume exceeds a horizontal plane at world Y = ceiling_y,
## assuming the stair sits at world-Y = global_position.y.
func pokes_through_ceiling(ceiling_y: float) -> bool:
	return global_position.y + floor_thickness + height_change + clearance > ceiling_y + EPSILON

## Ceiling cutout in the parent room's ceiling-local 2D coords (u = room-local X,
## v = -room-local Z). Covers slope + high landing only, the low landing stays
## under the existing ceiling. Assumes the stair has no rotation relative to its parent.
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

# SpatialEntity3D interface

func entity_label() -> String:
	var n := _effective_step_count()
	return "%s (stairs, %d steps, %.1fm wide, rises %.1fm toward %s, %.0f deg, step %.0fcm rise / %.0fcm deep)" % \
		[name, n, width, height_change, high_end, slope_degrees(),
		 step_height() * 100.0, step_depth() * 100.0]

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
	_add_spinbox(c, "W:",            0.5,   50.0,  0.5,  width)
	_add_spinbox(c, "Rise:",         0.1,   20.0,  0.1,  height_change)
	_add_spinbox(c, "Len:",          0.5,  100.0,  0.5,  length)
	_add_spinbox(c, "Clear:",        1.0,   10.0,  0.1,  clearance)
	_add_spinbox(c, "Floor t:",      0.0,    1.0,  0.05, floor_thickness)
	_add_spinbox(c, "Land low:",     0.0,   10.0,  0.1,  landing_depth_low)
	_add_spinbox(c, "Land high:",    0.0,   10.0,  0.1,  landing_depth_high)
	_add_spinbox(c, "Steps(0=auto):", 0.0,  200.0, 1.0,  float(step_count))

func apply_properties_ui(c: VBoxContainer) -> void:
	var spins: Array[SpinBox] = []
	for row in c.get_children():
		for child in row.get_children():
			if child is SpinBox: spins.append(child as SpinBox)
	if spins.size() >= 8:
		width              = spins[0].value
		height_change      = spins[1].value
		length             = spins[2].value
		clearance          = spins[3].value
		floor_thickness    = spins[4].value
		landing_depth_low  = spins[5].value
		landing_depth_high = spins[6].value
		step_count         = int(spins[7].value)

func has_wall(_side: String) -> bool:
	return false

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
