@tool
class_name Stairs3D
extends SpatialEntity3D

## A staircase connector between two rooms at different floor heights.
##
## Origin matches Ramp3D: centre of the horizontal footprint at y = 0,
## the LOW end's floor level.
##
## high_end names the direction toward the UPPER end of the staircase.
## Example: high_end = "north" means the staircase rises as you travel north (-Z).

@export var width: float = 2.0: set = _set_width
@export var height_change: float = 1.0: set = _set_hc  # total vertical rise low→high
@export var length: float = 4.0: set = _set_length      # total horizontal distance low→high
@export var clearance: float = 2.4: set = _set_cl       # headroom above top step

## Which cardinal direction is the upper end of the staircase.
@export_enum("north", "south", "east", "west") var high_end: String = "north": set = _set_dir

## Number of steps. 0 = autocompute from ideal ~18 cm step height.
@export var step_count: int = 0: set = _set_sc

@export var surface_floor: String = "concrete": set = _set_sf
@export var surface_walls: String = "concrete": set = _set_sw
@export var surface_ceiling: String = "concrete": set = _set_sce

@export var wall_sides_enabled: bool = true: set = _set_we
@export var ceiling_enabled: bool = false: set = _set_ce
@export var risers_enabled: bool = true: set = _set_re

@export var rebuild_now: bool = false: set = _trigger

var _rebuild_queued := false
var _rebuild_gen := 0

func _set_width(v):  width = v;           _queue_rebuild()
func _set_hc(v):     height_change = v;   _queue_rebuild()
func _set_length(v): length = v;          _queue_rebuild()
func _set_cl(v):     clearance = v;       _queue_rebuild()
func _set_dir(v):    high_end = v;        _queue_rebuild()
func _set_sc(v):     step_count = v;      _queue_rebuild()
func _set_sf(v):     surface_floor = v;   _queue_rebuild()
func _set_sw(v):     surface_walls = v;   _queue_rebuild()
func _set_sce(v):    surface_ceiling = v; _queue_rebuild()
func _set_we(v):     wall_sides_enabled = v; _queue_rebuild()
func _set_ce(v):     ceiling_enabled = v;    _queue_rebuild()
func _set_re(v):     risers_enabled = v;     _queue_rebuild()
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
		if c.has_meta("generated") or c.has_meta("stairs_area"): c.queue_free()
	await get_tree().process_frame
	if _rebuild_gen != my_gen: return
	_build_stairs()
	_build_stairs_area()

# Computed helpers

func _effective_step_count() -> int:
	if step_count > 0: return step_count
	return max(2, roundi(height_change / 0.18))

func step_height() -> float:
	return height_change / float(_effective_step_count())

func step_depth() -> float:
	return length / float(_effective_step_count())

func slope_degrees() -> float:
	return rad_to_deg(atan2(height_change, length))

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
	var sd := step_depth()
	var half_len := length / 2.0

	var slope_dir: Vector3 = (travel_dir * length + Vector3.UP * height_change).normalized()
	var slope_length: float = sqrt(length * length + height_change * height_change)

	# Treads and risers 
	for i in n:
		# Tread, horizontal flat box, top face at (i+1)*sh above low floor.
		var tread_center: Vector3 = \
			travel_dir * (-half_len + (i + 0.5) * sd) + \
			Vector3.UP * ((i + 1) * sh)
		_spawn_panel("tread", surface_floor,
			tread_center, perp_dir, travel_dir,
			Rect2(-width / 2.0, -sd / 2.0, width, sd), i)

		# Riser, vertical face connecting tread i-1 to tread i.
		if risers_enabled:
			var riser_center: Vector3 = \
				travel_dir * (-half_len + i * sd) + \
				Vector3.UP * ((i + 0.5) * sh)
			_spawn_panel("riser", surface_floor,
				riser_center, perp_dir, Vector3.UP,
				Rect2(-width / 2.0, -sh / 2.0, width, sh), i)

	# Side walls, parallelogram matching average slope, same as Ramp3D
	if wall_sides_enabled:
		var wall_center_y: float = (height_change + clearance) / 2.0
		for sign in [-1, 1]:
			var wall_center: Vector3 = perp_dir * (sign * width / 2.0) + Vector3.UP * wall_center_y
			_spawn_panel("wall", surface_walls,
				wall_center, slope_dir, Vector3.UP,
				Rect2(-slope_length / 2.0, -clearance / 2.0, slope_length, clearance),
				(0 if sign < 0 else 1))

	# Ceiling, sloped panel parallel to average slope
	if ceiling_enabled:
		var ceil_center: Vector3 = Vector3.UP * (height_change / 2.0 + clearance)
		_spawn_panel("ceiling", surface_ceiling,
			ceil_center, perp_dir, slope_dir,
			Rect2(-width / 2.0, -slope_length / 2.0, width, slope_length), 0)

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

	var normal := bu.cross(bv).normalized()
	var t := Transform3D()
	t.basis = Basis(bu, bv, normal)
	t.origin = center + bu * (r.position.x + r.size.x / 2.0) + bv * (r.position.y + r.size.y / 2.0)
	body.transform = t

	var root := get_tree().edited_scene_root
	if root:
		for nd: Node in [body, mi, cs]: nd.owner = root

func _build_stairs_area() -> void:
	var area := Area3D.new()
	area.set_meta("stairs_area", true)
	area.name = "StairsArea"
	var dirs := _get_dirs()
	var perp_dir: Vector3 = dirs[1]
	var aabb_size := Vector3(
		width  if absf(perp_dir.x) > 0.5 else length,
		height_change + clearance,
		width  if absf(perp_dir.z) > 0.5 else length
	)
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


# SpatialEntity3D interface

func entity_label() -> String:
	var n := _effective_step_count()
	return "%s (stairs, %d steps, %.1fm wide, rises %.1fm toward %s, %.0f deg, step %.0fcm rise / %.0fcm deep)" % \
		[name, n, width, height_change, high_end, slope_degrees(),
		 step_height() * 100.0, step_depth() * 100.0]

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
	_add_spinbox(c, "W:",          0.5,   50.0,  0.5, width)
	_add_spinbox(c, "Rise:",       0.1,   20.0,  0.1, height_change)
	_add_spinbox(c, "Len:",        0.5,  100.0,  0.5, length)
	_add_spinbox(c, "Clear:",      1.0,   10.0,  0.1, clearance)
	_add_spinbox(c, "Steps(0=auto):", 0.0, 200.0, 1.0, float(step_count))

func apply_properties_ui(c: VBoxContainer) -> void:
	var spins: Array[SpinBox] = []
	for row in c.get_children():
		for child in row.get_children():
			if child is SpinBox: spins.append(child as SpinBox)
	if spins.size() >= 5:
		width         = spins[0].value
		height_change = spins[1].value
		length        = spins[2].value
		clearance     = spins[3].value
		step_count    = int(spins[4].value)

# Placement helpers (parallel to ramp_3d.gd)

## Returns the worldspace offset from this staircase's position to where the
## centre of the HIGH-end room should be placed so its floor aligns with the top step.
func high_end_room_offset(other_size: Vector3) -> Vector3:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var travel_depth: float = _travel_depth(other_size)
	return travel_dir * (length / 2.0 + travel_depth / 2.0) + Vector3.UP * height_change

## Returns the worldspace offset from this staircase's position to where the
## centre of the LOW-end room should be placed so its wall is flush with the stair entry.
func low_end_room_offset(other_size: Vector3) -> Vector3:
	var dirs := _get_dirs()
	var travel_dir: Vector3 = dirs[0]
	var travel_depth: float = _travel_depth(other_size)
	return -travel_dir * (length / 2.0 + travel_depth / 2.0)

func _travel_depth(room_size: Vector3) -> float:
	match high_end:
		"north", "south": return room_size.z
		"east",  "west":  return room_size.x
	return room_size.z

## The wall side on the room that faces the LOW end of this staircase.
func room_side_at_low_end() -> String:
	match high_end:
		"north": return "north"
		"south": return "south"
		"east":  return "east"
		"west":  return "west"
	return "north"

## The wall side on the room that faces the HIGH end of this staircase.
func room_side_at_high_end() -> String:
	var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
	return opp[high_end]

# SpatialEntity3D neighbour interface

func neighbor_offset(side: String, other_size: Vector3) -> Vector3:
	if side == high_end:
		return high_end_room_offset(other_size)
	var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
	if side == opp.get(high_end, ""):
		return low_end_room_offset(other_size)
	return Vector3.ZERO

func neighbor_doorway_side(side: String) -> String:
	if side == high_end:
		return room_side_at_high_end()
	var opp := {"north": "south", "south": "north", "east": "west", "west": "east"}
	if side == opp.get(high_end, ""):
		return room_side_at_low_end()
	return ""

func has_wall(_side: String) -> bool:
	return false

func connection_probe_points() -> Array[Dictionary]:
	var travel_dir: Vector3 = _get_dirs()[0]
	var low_center  := position + (-travel_dir * length / 2.0) + Vector3.UP * (clearance / 2.0)
	var high_center := position + ( travel_dir * length / 2.0) + Vector3.UP * (height_change + clearance / 2.0)
	return [
		{"label": "low end",  "probe_world": low_center  + (-travel_dir) * 0.05,
		 "face_center_world": low_center,  "face_width": width, "face_height": clearance},
		{"label": "high end", "probe_world": high_center + travel_dir * 0.05,
		 "face_center_world": high_center, "face_width": width, "face_height": clearance},
	]
