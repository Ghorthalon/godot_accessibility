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
## Per-side config: {enabled:bool, surface:String, openings:Array[Rect2]}
## Rect2 is in wall-local 2D coords (meters), origin = wall center.
@export var walls: Dictionary = _default_walls(): set = _set_walls
@export var rebuild_now: bool = false: set = _trigger

static func _default_walls() -> Dictionary:
    var d := {}
    for s in SIDES:
        d[s] = {"enabled": true, "surface": "concrete", "openings": []}
    d["ceiling"]["enabled"] = true
    d["floor"]["zones"] = []
    return d

func _set_size(v): size = v; _queue_rebuild()
func _set_walls(v): walls = v; _queue_rebuild()
func _trigger(_v): rebuild()
func _queue_rebuild():
    if is_inside_tree(): call_deferred("rebuild")

func rebuild() -> void:
    if not Engine.is_editor_hint(): return
    for c in get_children():
        if c.has_meta("generated"): c.queue_free()
    await get_tree().process_frame
    for side in SIDES:
        var cfg: Dictionary = walls.get(side, {})
        if not cfg.get("enabled", false): continue
        _build_wall(side, cfg)

func _build_wall(side: String, cfg: Dictionary) -> void:
    # Wall plane dimensions in its local 2D frame (u,v):
    var u := size.x; var v := size.z  # floor/ceiling
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
    # Slice wall around openings  list of Rect2 quads in (u,v) space.
    var rects := _slice([Rect2(-u/2, -v/2, u, v)], cfg.get("openings", []))
    for r in rects:
        _spawn_quad(side, cfg, center, basis_u, basis_v, r)

    if side == "floor":
        var zone_center := center + Vector3(0, 0.001, 0)
        for zone in cfg.get("zones", []):
            var zone_cfg := {"surface": zone.get("surface", "concrete"), "openings": []}
            _spawn_quad(side, zone_cfg, zone_center, basis_u, basis_v, zone["rect"])

func _slice(rects: Array, openings: Array) -> Array:
    # Simple iterative rectangle subtraction. Good enough for doorways I think. For now.
    for hole in openings:
        var out := []
        for r in rects:
            if not r.intersects(hole): out.append(r); continue
            # Split r into up-to-4 strips around hole.
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

func _spawn_quad(side, cfg, center, bu: Vector3, bv: Vector3, r: Rect2) -> void:
    var body := StaticBody3D.new()
    body.set_meta("generated", true)
    body.set_meta("surface", cfg.get("surface", "concrete"))
    body.name = "%s_%d" % [side, get_child_count()]
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
    # Orient: local z of the quad should align with wall normal.
    var normal := bu.cross(bv).normalized()
    var t := Transform3D()
    t.basis = Basis(bu, bv, normal)
    t.origin = center + bu * (r.position.x + r.size.x/2) + bv * (r.position.y + r.size.y/2)
    body.transform = t
    var root := get_tree().edited_scene_root
    if root:
        for n in [body, mi, cs]: n.owner = root

func neighbor_offset(side: String, other_size: Vector3) -> Vector3:
    # Where to place a neighbor room so its opposite wall is flush with mine.
    match side:
        "north": return Vector3(0, 0, -(size.z/2 + other_size.z/2))
        "south": return Vector3(0, 0,  (size.z/2 + other_size.z/2))
        "east":  return Vector3( (size.x/2 + other_size.x/2), 0, 0)
        "west":  return Vector3(-(size.x/2 + other_size.x/2), 0, 0)
    return Vector3.ZERO

func punch_doorway(side: String, width := 1.2, height := 2.1) -> void:
    var cfg: Dictionary = walls[side]
    # Centered doorway on the wall. For floor/ceiling you'd use XZ instead.
    cfg["openings"] = [Rect2(-width/2, -size.y/2, width, height)]
    walls[side] = cfg
    rebuild()

func add_doorway(side: String, center_u: float, center_v: float, width := 1.2, height := 2.1) -> void:
    # Appends an opening at a specific wall-local position (does not replace existing ones).
    # center_u/v are in wall-local 2D coordinates (meters, origin = wall center).
    var cfg: Dictionary = walls[side]
    cfg["openings"].append(Rect2(center_u - width/2, center_v - height/2, width, height))
    walls[side] = cfg
    rebuild()
