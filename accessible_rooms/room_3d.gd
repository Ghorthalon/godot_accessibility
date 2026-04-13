@tool
class_name Room3D
extends Node3D

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

var _rebuild_queued := false

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
	# Safety net: ensure signals are wired after scene load or tree re-entry.
	for s in SIDES:
		var c := cfg(s)
		if c and not c.changed.is_connected(_queue_rebuild):
			c.changed.connect(_queue_rebuild)

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
		call_deferred("rebuild")

func rebuild() -> void:
	_rebuild_queued = false
	if not Engine.is_editor_hint(): return
	for c in get_children():
		if c.has_meta("generated"): c.queue_free()
	await get_tree().process_frame
	for side in SIDES:
		var wall_cfg := cfg(side)
		if wall_cfg == null or not wall_cfg.enabled: continue
		_build_wall(side)

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

	var rects := _slice([Rect2(-u/2, -v/2, u, v)], wall_cfg.openings)
	for i in rects.size():
		_spawn_quad(side, wall_cfg.surface, center, basis_u, basis_v, rects[i], i)

	# Zone overlays: offset slightly along the wall normal to prevent z-fighting.
	var zone_off: Vector3 = NORMALS[side] * 0.001
	for i in wall_cfg.zones.size():
		var zone: Dictionary = wall_cfg.zones[i]
		_spawn_quad(side, zone.get("surface", "concrete"),
				center + zone_off, basis_u, basis_v, zone["rect"], rects.size() + i)

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
				if piece.size.x > 0.001 and piece.size.y > 0.001:
					out.append(piece)
		rects = out
	return rects

func _spawn_quad(side: String, surface: String, center: Vector3, bu: Vector3, bv: Vector3, r: Rect2, idx: int) -> void:
	var body := StaticBody3D.new()
	body.set_meta("generated", true)
	body.set_meta("surface", surface)
	body.name = "%s_%d" % [side, idx]
	var thickness := 0.1
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

func neighbor_offset(side: String, other_size: Vector3) -> Vector3:
	# Where to place a neighbour room so its opposite wall is flush with mine.
	match side:
		"north": return Vector3(0, 0, -(size.z/2 + other_size.z/2))
		"south": return Vector3(0, 0,  (size.z/2 + other_size.z/2))
		"east":  return Vector3( (size.x/2 + other_size.x/2), 0, 0)
		"west":  return Vector3(-(size.x/2 + other_size.x/2), 0, 0)
	return Vector3.ZERO

func punch_doorway(side: String, width := 1.2, height := 2.1) -> void:
	## Replaces all openings on this wall with a single centred floor-level doorway.
	cfg(side).openings.clear()
	add_doorway(side, 0.0, -size.y / 2.0 + height / 2.0, width, height)

func add_doorway(side: String, center_u: float, center_v: float, width := 1.2, height := 2.1) -> void:
	## Appends an opening at a specific wall-local position without replacing existing ones.
	## center_u/v are in wall-local 2D coordinates (metres, origin = wall centre).
	cfg(side).openings.append(Rect2(center_u - width/2, center_v - height/2, width, height))
	_queue_rebuild()
