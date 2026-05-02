@tool
class_name SceneQuery
extends Node

var plugin: EditorPlugin
var dock  # dock.gd  sometimes null

func edited_root() -> Node:
	return plugin.get_editor_interface().get_edited_scene_root()

## Returns the node that new children should be added to.
## When dock.use_selected_node is true and a node is selected, returns that node
## otherwise returns the edited scene root.
func placement_parent() -> Node:
	if dock != null and dock.use_selected_node:
		var sel := plugin.get_editor_interface().get_selection().get_selected_nodes()
		if sel.size() > 0:
			var node := sel[0]
			if node is SpatialEntity3D:
				var parent := node.get_parent()
				if parent != null: return parent
			else:
				return node
	return edited_root()

## All nongenerated entities: SpatialEntity3D nodes and userplaced PhysicsBody3D nodes.
## Stops recursing into an entity once found, avoiding generated wall/surface children.
func entities_in_scene() -> Array[Node]:
	var root := edited_root()
	if root == null: return []
	var result: Array[Node] = []
	_collect(root, result)
	return result

func _collect(node: Node, out: Array[Node]) -> void:
	if node.has_meta("generated"): return
	if node is SpatialEntity3D or node is PhysicsBody3D:
		out.append(node); return
	for child in node.get_children():
		_collect(child, out)

func entity_position(entity: Node) -> Vector3:
	return (entity as Node3D).global_position if entity is Node3D else Vector3.ZERO

func entity_label(entity: Node) -> String:
	if entity is SpatialEntity3D:
		return (entity as SpatialEntity3D).entity_label()
	# Fallback for userplaced PhysicsBody3D and other nodes.
	var root := edited_root()
	var parent := entity.get_parent()
	if parent != null and parent != root and not parent.has_meta("generated"):
		return "%s / %s" % [parent.name, entity.name]
	return entity.name

## Returns the first SpatialEntity3D whose contains_point() returns true for p.
## Replaces the former specific room_containing() / ramp_containing() pair
## works for any current or future SpatialEntity3D subclass automatically. Hopefully. Maybe. Until it doesn't.
func entity_containing(p: Vector3) -> SpatialEntity3D:
	var root := edited_root()
	if root == null: return null
	return _entity_containing_recursive(root, p)

func _entity_containing_recursive(node: Node, p: Vector3) -> SpatialEntity3D:
	if node.has_meta("generated"): return null
	if node is SpatialEntity3D:
		if (node as SpatialEntity3D).contains_point(p):
			return node as SpatialEntity3D
		return null
	for child in node.get_children():
		var found := _entity_containing_recursive(child, p)
		if found != null: return found
	return null

## Returns all SpatialEntity3D instances that contain p, sorted smallest volume first.
## Use this instead of entity_containing() when you want the most specific container.
func entities_containing_sorted(p: Vector3) -> Array[SpatialEntity3D]:
	var root := edited_root()
	if root == null: return []
	var found: Array[SpatialEntity3D] = []
	_collect_containing(root, p, found)
	found.sort_custom(func(a: SpatialEntity3D, b: SpatialEntity3D) -> bool:
		return a.bounding_volume() < b.bounding_volume()
	)
	return found

func _collect_containing(node: Node, p: Vector3, out: Array[SpatialEntity3D]) -> void:
	if node.has_meta("generated"): return
	if node is SpatialEntity3D:
		if (node as SpatialEntity3D).contains_point(p):
			out.append(node as SpatialEntity3D)
	for child in node.get_children():
		_collect_containing(child, p, out)

## Returns the innermost Node3D whose center should be used for the inside.wav sound.
## Combines SpatialEntity3D geometric containment with physics-based solid object containment,
## returning whichever container has the smallest volume.
func innermost_container_node(p: Vector3) -> Node3D:
	var entities := entities_containing_sorted(p)
	var solid   := _innermost_solid_container(p)
	if entities.is_empty() and solid == null: return null
	if solid == null:    return entities[0] as Node3D
	if entities.is_empty(): return solid
	var entity_vol := (entities[0] as SpatialEntity3D).bounding_volume()
	var solid_vol  := _physics_body_volume(solid)
	return solid if solid_vol < entity_vol else entities[0] as Node3D

## Returns the smallest solid non-entity physics body that contains p, or null.
## Excludes generated room/ramp bodies and SpatialEntity3D nodes themselves.
func _innermost_solid_container(p: Vector3) -> Node3D:
	var root := edited_root()
	if root == null or not root is Node3D: return null
	var space := (root as Node3D).get_world_3d().direct_space_state
	var params := PhysicsPointQueryParameters3D.new()
	params.position = p
	var hits := space.intersect_point(params)
	var best: Node3D = null
	var best_vol := INF
	for hit in hits:
		var collider: Node = hit.get("collider")
		if collider == null or not collider is Node3D: continue
		if collider.has_meta("generated"): continue   # room/ramp wall/floor
		if collider is SpatialEntity3D: continue       # handled geometrically
		var body := collider as Node3D
		var vol := _physics_body_volume(body)
		if vol < best_vol:
			best_vol = vol
			best = body
	return best

func _physics_body_volume(body: Node3D) -> float:
	for child in body.get_children():
		if not child is CollisionShape3D: continue
		var shape: Shape3D = (child as CollisionShape3D).shape
		if shape == null: continue
		if shape is BoxShape3D:
			var s: Vector3 = (shape as BoxShape3D).size
			return s.x * s.y * s.z
		if shape is SphereShape3D:
			var r: float = (shape as SphereShape3D).radius
			return (4.0 / 3.0) * PI * r * r * r
		if shape is CapsuleShape3D:
			var cs := shape as CapsuleShape3D
			return PI * cs.radius * cs.radius * (cs.height + (4.0 / 3.0) * cs.radius)
		return 0.001  # unknown shape — treat as very small
	return INF

# Returns readable labels for all physics shapes that contain point p.
# Uses Jolt broadphase and should be safe to call on every cursor move even in large scenes.
func overlapping_at(p: Vector3) -> Array[String]:
	var root := edited_root()
	if root == null or not root is Node3D: return []
	var space := (root as Node3D).get_world_3d().direct_space_state
	var params := PhysicsPointQueryParameters3D.new()
	params.position = p
	var hits := space.intersect_point(params)
	var labels: Array[String] = []
	for hit in hits:
		var collider := hit["collider"] as Node
		if collider == null: continue
		if collider.has_meta("generated") and collider.get_parent() is SpatialEntity3D:
			var side := collider.name.split("_")[0]
			var surface: String = collider.get_meta("surface", "wall")
			labels.append("%s of %s (%s)" % [side, collider.get_parent().name, surface])
		else:
			labels.append(entity_label(collider))
	return labels

# Nonspatial entities within radius meters of p (i.e. user-placed objects, not rooms/ramps).
func entities_near_point(p: Vector3, radius: float) -> Array[Node]:
	var result: Array[Node] = []
	for entity in entities_in_scene():
		if entity is SpatialEntity3D: continue
		if entity_position(entity).distance_to(p) <= radius:
			result.append(entity)
	return result

# Nearest entity in the forward half space of dir from the given position.
func nearest_in_direction(from: Vector3, dir: Vector3) -> Node:
	var best: Node = null
	var best_dist := INF
	var dir_n := dir.normalized()
	for entity in entities_in_scene():
		var to_e := entity_position(entity) - from
		if to_e.dot(dir_n) <= 0.01: continue
		var d := to_e.length()
		if d < best_dist:
			best_dist = d; best = entity
	return best

# Raycast probe in all 6 directions. reports surface type for walls, entity name otherwise.
func probe_report(from: Vector3) -> String:
	var root := edited_root()
	if root == null or not root is Node3D: return "Need a 3D scene."
	var space := (root as Node3D).get_world_3d().direct_space_state
	var dirs := {"east": Vector3.RIGHT, "west": Vector3.LEFT,
				 "up": Vector3.UP, "down": Vector3.DOWN,
				 "south": Vector3.BACK, "north": Vector3.FORWARD}
	var parts: Array[String] = []
	for dir_name in dirs:
		var params := PhysicsRayQueryParameters3D.create(from, from + dirs[dir_name] * 100.0)
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			parts.append("%s open" % dir_name)
		else:
			var dist := from.distance_to(hit.position)
			var label: String
			if hit.collider.has_meta("surface"):
				label = hit.collider.get_meta("surface")
			else:
				label = entity_label(hit.collider as Node)
			parts.append("%s %.1fm %s" % [dir_name, dist, label])
	return ", ".join(parts) + "."

## Raycast probe in all 6 directions. Returns hit positions only (open directions omitted).
func probe_positions(from: Vector3) -> Array[Vector3]:
	var root := edited_root()
	if root == null or not root is Node3D: return []
	var space := (root as Node3D).get_world_3d().direct_space_state
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
				 Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var result: Array[Vector3] = []
	for dir in dirs:
		var params := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
		var hit := space.intersect_ray(params)
		if not hit.is_empty():
			result.append(hit.position)
	return result

## Cast downward from from, return the Y of the first surface hit, or null if none.
func raycast_down(from: Vector3) -> Variant:
	var space := _get_space()
	if space == null: return null
	var params := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -50, 0))
	var hit := space.intersect_ray(params)
	return hit["position"].y if hit else null

## Cast from from in dir (max_dist meters) return the hit position Vector3, or null.
func raycast_direction(from: Vector3, dir: Vector3, max_dist := 50.0) -> Variant:
	var space := _get_space()
	if space == null: return null
	var params := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * max_dist)
	var hit := space.intersect_ray(params)
	return hit["position"] if hit else null

func _get_space() -> PhysicsDirectSpaceState3D:
	var root := edited_root()
	if root == null or not root is Node3D: return null
	return (root as Node3D).get_world_3d().direct_space_state

## Returns the name of the first SpatialEntity3D in root whose footprint overlaps
## the proposed placement at pos with the given footprint size. Returns "" if clear.
## Pass exclude to skip a node (e.g. the node being moved, to avoid selfcollision).
func first_overlap(pos: Vector3, footprint: Vector3, root: Node, exclude: Node = null) -> String:
	for child in root.get_children():
		if child == exclude: continue
		if not child is SpatialEntity3D: continue
		var child_fp := _entity_footprint(child as SpatialEntity3D)
		if child_fp == Vector3.ZERO: continue
		if aabbs_overlap(pos, footprint, (child as Node3D).position, child_fp):
			return child.name
	return ""

## Returns all Room3D nodes in root whose opposite wall is flush with room's side wall
## and whose footprint overlaps on the perpendicular axis.
func rooms_flush_with_wall(room: Room3D, side: String, root: Node) -> Array[Room3D]:
	var opp := _opposite_side(side)
	var plane := Room3D._wall_plane_coord(room, side)
	var result: Array[Room3D] = []
	for child in root.get_children():
		if child == room or not child is Room3D: continue
		var other := child as Room3D
		if absf(Room3D._wall_plane_coord(other, opp) - plane) > SpatialEntity3D.EPSILON: continue
		if not _rooms_share_wall_footprint(room, side, other): continue
		result.append(other)
	return result

func _opposite_side(side: String) -> String:
	match side:
		"north": return "south"
		"south": return "north"
		"east":  return "west"
		"west":  return "east"
	return ""

func _rooms_share_wall_footprint(a: Room3D, side: String, b: Room3D) -> bool:
	match side:
		"north", "south":
			var a_lo := a.position.x - a.size.x / 2.0
			var a_hi := a.position.x + a.size.x / 2.0
			var b_lo := b.position.x - b.size.x / 2.0
			var b_hi := b.position.x + b.size.x / 2.0
			return a_hi > b_lo + SpatialEntity3D.EPSILON and b_hi > a_lo + SpatialEntity3D.EPSILON
		"east", "west":
			var a_lo := a.position.z - a.size.z / 2.0
			var a_hi := a.position.z + a.size.z / 2.0
			var b_lo := b.position.z - b.size.z / 2.0
			var b_hi := b.position.z + b.size.z / 2.0
			return a_hi > b_lo + SpatialEntity3D.EPSILON and b_hi > a_lo + SpatialEntity3D.EPSILON
	return false

## Returns the axis aligned bounding footprint of a SpatialEntity3D.
## x/z are centred on position, y extends upward from position.y (floor level).
func _entity_footprint(entity: SpatialEntity3D) -> Vector3:
	if entity is Room3D:
		return (entity as Room3D).size
	if entity is Ramp3D:
		var r := entity as Ramp3D
		match r.high_end:
			"north", "south": return Vector3(r.width, r.height_change + r.clearance, r.length)
			"east",  "west":  return Vector3(r.length, r.height_change + r.clearance, r.width)
	return Vector3.ZERO

## Cast in dir, return hit Vector3 or null. 
func raycast_horizontal(from: Vector3, dir: Vector3, max_dist := 30.0) -> Variant:
	return raycast_direction(from, dir, max_dist)

## Cast in dir and -dir, return {hit_a, hit_b, midpoint, gap} or {} if either misses.
func wall_gap(from: Vector3, dir: Vector3, max_dist := 30.0) -> Dictionary:
	var ha = raycast_direction(from, dir, max_dist)
	var hb = raycast_direction(from, -dir, max_dist)
	if ha == null or hb == null: return {}
	return {"hit_a": ha, "hit_b": hb, "midpoint": ((ha as Vector3) + (hb as Vector3)) / 2.0, "gap": (ha as Vector3).distance_to(hb as Vector3)}

## Returns {side, world_pos, width, height} for the nearest doorway opening to near_pos, or {}.
## Searches all walls of the room containing near_pos.
func nearest_doorway(near_pos: Vector3) -> Dictionary:
	var room := entity_containing(near_pos) as Room3D
	if room == null: return {}
	var best := {}
	var best_dist := INF
	for side in ["north", "south", "east", "west"]:
		var wall_cfg: WallConfig = room.cfg(side)
		if wall_cfg == null: continue
		for opening: Rect2 in wall_cfg.openings:
			var cu := opening.position.x + opening.size.x / 2.0
			var cv := opening.position.y + opening.size.y / 2.0
			var wpos := _doorway_world_pos(room, side, cu, cv)
			var d := near_pos.distance_to(wpos)
			if d < best_dist:
				best_dist = d
				best = {"side": side, "world_pos": wpos, "width": opening.size.x, "height": opening.size.y}
	return best

## Returns distances in all 6 cardinal directions from from as a Dictionary.
func measure_space(from: Vector3, max_dist := 30.0) -> Dictionary:
	var dirs := {"north": Vector3.FORWARD, "south": Vector3.BACK,
				 "east": Vector3.RIGHT, "west": Vector3.LEFT,
				 "up": Vector3.UP, "down": Vector3.DOWN}
	var result := {}
	for d in dirs:
		var hit = raycast_direction(from, dirs[d], max_dist)
		result[d] = from.distance_to(hit as Vector3) if hit != null else max_dist
	return result

## Convert walllocal (cu, cv) to world position for a doorway on a given room side.
## Coordinate convention matches _punch_at_cursor in tab_rooms.gd:
##   north/south: bu = RIGHT (+X), east/west: bu = BACK (-Z)
func _doorway_world_pos(room: Room3D, side: String, cu: float, cv: float) -> Vector3:
	var wall_center: Vector3
	var bu: Vector3
	match side:
		"north": wall_center = Vector3(0, room.size.y / 2.0, -room.size.z / 2.0); bu = Vector3.RIGHT
		"south": wall_center = Vector3(0, room.size.y / 2.0,  room.size.z / 2.0); bu = Vector3.RIGHT
		"east":  wall_center = Vector3( room.size.x / 2.0, room.size.y / 2.0, 0); bu = Vector3.FORWARD
		"west":  wall_center = Vector3(-room.size.x / 2.0, room.size.y / 2.0, 0); bu = Vector3.FORWARD
	return room.position + wall_center + bu * cu + Vector3.UP * cv

## Walks node and its descendants to find the first CollisionShape3D.
func find_collision_shape(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node as CollisionShape3D
	for child in node.get_children():
		var found := find_collision_shape(child)
		if found != null:
			return found
	return null

func _collect_body_rids(node: Node, out: Array[RID]) -> void:
	if node is PhysicsBody3D:
		out.append((node as PhysicsBody3D).get_rid())
	for child in node.get_children():
		_collect_body_rids(child, out)

## Checks whether placing node so its origin is at target_pos would cause a collision.
## Returns {collides: bool, collider_name: String}.
## If no CollisionShape3D is found returns collides=false, collider_name="no shape".
func check_placement(node: Node3D, target_pos: Vector3) -> Dictionary:
	var shape_node := find_collision_shape(node)
	if shape_node == null or shape_node.shape == null:
		return {"collides": false, "collider_name": "no shape"}
	var space := _get_space()
	if space == null:
		return {"collides": false, "collider_name": ""}
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape_rid = shape_node.shape.get_rid()
	var shape_local_offset := shape_node.global_position - node.global_position
	params.transform = Transform3D(node.global_transform.basis, target_pos + shape_local_offset)
	var rids: Array[RID] = []
	_collect_body_rids(node, rids)
	params.exclude = rids
	var hits := space.intersect_shape(params, 1)
	if hits.is_empty():
		return {"collides": false, "collider_name": ""}
	var collider = hits[0].get("collider", null)
	var collider_name := ""
	if collider is Node:
		collider_name = entity_label(collider as Node)
	return {"collides": true, "collider_name": collider_name}

static func aabbs_overlap(a_pos: Vector3, a_size: Vector3, b_pos: Vector3, b_size: Vector3) -> bool:
	return (a_pos.x - a_size.x/2) < (b_pos.x + b_size.x/2) and \
		   (a_pos.x + a_size.x/2) > (b_pos.x - b_size.x/2) and \
		   a_pos.y < (b_pos.y + b_size.y) and \
		   (a_pos.y + a_size.y) > b_pos.y and \
		   (a_pos.z - a_size.z/2) < (b_pos.z + b_size.z/2) and \
		   (a_pos.z + a_size.z/2) > (b_pos.z - b_size.z/2)
