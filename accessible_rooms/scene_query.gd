# This file is becoming unwieldly and I keep adding to it at random. I need to fix this, but I might have to do a lot of refactoring when I switch from only rectangular rooms to custom shapes, so until then, I think this will be OK.

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
	if node is PhysicsBody3D:
		out.append(node); return  # treat a placed body as a unit, don't recurse
	if node is SpatialEntity3D:
		# Collect the container, but keep descending: objects placed inside a room
		# (door scenes, props, nested stairs) must also be reachable by jump/nav.
		# Generated walls/floor carry the "generated" meta and are skipped above.
		out.append(node)
		for child in node.get_children():
			_collect(child, out)
		return
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

## Returns the innermost SpatialEntity3D that contains p, or null.
func innermost_entity_containing(p: Vector3) -> SpatialEntity3D:
	var found := entities_containing_sorted(p)
	return found[0] if not found.is_empty() else null

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
		return 0.001  # unknown shape, treat as very small
	return INF

# Returns readable labels for all physics shapes that contain point p.
# Uses Jolt broadphase and should be safe to call on every cursor move even in large scenes.
func overlapping_at(p: Vector3) -> Array[String]:
	var root := edited_root()
	if root == null or not root is Node3D: return []
	var space := (root as Node3D).get_world_3d().direct_space_state
	var params := PhysicsPointQueryParameters3D.new()
	params.position = p
	params.collide_with_areas = true   # so Area3Ds (triggers, zones) get announced too
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

## other Node3D classes for example SteamAudio / Resonance Audio sources can
## use the cursor's proximity tail and the nearby scan by using the
## accessible_rooms_announce group
const GROUP_ANNOUNCE := "accessible_rooms_announce"

## User placed point Node3Ds without collision shape within radius metres of p,
## sorted nearest first. Skips SpatialEntity3D containers, handled by
## entities_containing_sorted, and CollisionObject3D, handled by overlapping_at
## so the cursor report doesn't announce them twice.
## other classes can join in via the accessible_rooms_announce group.
func nearby_point_nodes(p: Vector3, radius: float) -> Array[Node3D]:
	var root := edited_root()
	if root == null: return []
	var result: Array[Node3D] = []
	_collect_nearby(root, p, radius, root, result, false)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(p) < b.global_position.distance_to(p))
	return result

## Superset of nearby_point_nodes that also includes CollisionObject3D
## (PhysicsBody3D, Area3D). Used by the cursor scan feature sorted nearest first.
## SpatialEntity3D containers stay excluded, their centres aren't useful sound sources.
## At some point this should probably be cleaned up, it looks to me like there's a lot of duplicated code. But I'd rather make it right, then make it nice. 
func nearby_placeable_nodes(p: Vector3, radius: float) -> Array[Node3D]:
	var root := edited_root()
	if root == null: return []
	var result: Array[Node3D] = []
	_collect_nearby(root, p, radius, root, result, true)
	result.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(p) < b.global_position.distance_to(p))
	return result

func _collect_nearby(node: Node, p: Vector3, radius: float,
		root: Node, out: Array[Node3D], include_collision: bool) -> void:
	if node.has_meta("generated"): return
	if node is SpatialEntity3D:
		# Don't collect the container itself, do recurse so placed children are found.
		for child in node.get_children():
			_collect_nearby(child, p, radius, root, out, include_collision)
		return
	if node != root and node is Node3D and _is_placeable(node, root, include_collision):
		var n3 := node as Node3D
		if n3.global_position.distance_to(p) <= radius:
			out.append(n3)
		return  # Treat the placed node as a unit, don't recurse into its subtree.
	for child in node.get_children():
		_collect_nearby(child, p, radius, root, out, include_collision)

func _is_placeable(node: Node, root: Node, include_collision: bool) -> bool:
	if node.is_in_group(GROUP_ANNOUNCE): return true
	if node is CollisionObject3D:
		return include_collision
	if node is AudioStreamPlayer3D: return true
	if node is Marker3D: return true
	if node is Light3D: return true
	if node is GPUParticles3D: return true
	# Generic Node3D placed at the scene root or inside a SpatialEntity3D.
	# Catches user inserted Node3D and PackedScene roots.
	var parent := node.get_parent()
	return parent == root or parent is SpatialEntity3D

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
		var child_pos := (child as Node3D).global_position
		if not aabbs_overlap(pos, footprint, child_pos, child_fp): continue
		# Full containment means no geometry can actually intersect, not a conflict.
		if aabb_contains(pos, footprint, child_pos, child_fp): continue
		if aabb_contains(child_pos, child_fp, pos, footprint): continue
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
	if entity is Stairs3D:
		var s := entity as Stairs3D
		match s.high_end:
			"north", "south": return Vector3(s.width, s.height_change + s.clearance, s.length)
			"east",  "west":  return Vector3(s.length, s.height_change + s.clearance, s.width)
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

## Returns {room, side, world_pos, width, height, cu, cv} for the nearest doorway
## opening to near_pos, or {}. Searches all walls of the room containing near_pos.
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
				best = {"room": room, "side": side, "world_pos": wpos,
						"width": opening.size.x, "height": opening.size.y,
						"cu": cu, "cv": cv}
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
	return room.global_position + wall_center + bu * cu + Vector3.UP * cv

## Returns a world Transform3D for the wall point at (cu, cv) on the named side of room.
## Position is the wall-local point; -Z (Godot's local forward) faces into the room interior.
## Generic primitive for placing any wall-aligned scene: doors, windows, paintings,
## light switches, signs. Pair with nearest_doorway() or any (room, side, cu, cv) source.
func wall_facing_transform(room: Room3D, side: String, cu: float, cv: float) -> Transform3D:
	var origin: Vector3 = _doorway_world_pos(room, side, cu, cv)
	var inward: Vector3
	match side:
		"north": inward = Vector3.BACK
		"south": inward = Vector3.FORWARD
		"east":  inward = Vector3.LEFT
		"west":  inward = Vector3.RIGHT
		_: return Transform3D(Basis(), origin)
	return Transform3D(Basis.looking_at(inward, Vector3.UP), origin)

## Returns the cardinal side of room whose wall plane is closest to p.
## Generic helper for wall-aligned operations.
func nearest_wall_side(room: Room3D, p: Vector3) -> String:
	var dists := {
		"north": absf(p.z - (room.global_position.z - room.size.z / 2.0)),
		"south": absf(p.z - (room.global_position.z + room.size.z / 2.0)),
		"east":  absf(p.x - (room.global_position.x + room.size.x / 2.0)),
		"west":  absf(p.x - (room.global_position.x - room.size.x / 2.0)),
	}
	var best := "north"
	for s in dists:
		if dists[s] < dists[best]: best = s
	return best

## Returns (cu, cv) for an arbitrary world point projected onto the named wall of room.
## Inverse of _doorway_world_pos's (cu, cv) → world map.
func wall_uv_from_world(room: Room3D, side: String, p: Vector3) -> Vector2:
	var cu: float = 0.0
	match side:
		"north", "south": cu = p.x - room.global_position.x
		"east", "west":   cu = room.global_position.z - p.z
	var cv: float = p.y - (room.global_position.y + room.size.y / 2.0)
	return Vector2(cu, cv)

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

## Searches for a nearby position where node's collision shape fits without overlap.
## Returns the chosen Vector3 or null if no clearance found within max_radius metres.
## Strategy: try floor-snap first (handles air-floating), then expanding cardinal shells,
## then their floor-snapped variants (handles "embedded in a wall above floor").
## node may or may not be in the tree; check_placement works in both states.
func find_fit_position(node: Node3D, start_pos: Vector3, max_radius: float = 5.0) -> Variant:
	if not check_placement(node, start_pos).get("collides", false):
		return start_pos
	var candidates: Array[Vector3] = []
	var floor_y = raycast_down(start_pos)
	if floor_y != null:
		candidates.append(Vector3(start_pos.x, floor_y, start_pos.z))
	var dirs := [Vector3.UP, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.DOWN]
	var step := 0.25
	while step <= max_radius:
		for dir: Vector3 in dirs:
			candidates.append(start_pos + dir * step)
		step *= 2.0
	for c: Vector3 in candidates:
		if not check_placement(node, c).get("collides", false):
			return c
		var cf = raycast_down(c)
		if cf != null:
			var cfp := Vector3(c.x, cf, c.z)
			if not check_placement(node, cfp).get("collides", false):
				return cfp
	return null

## Describes delta as a short cardinal phrase ("1.5m east, 0.5m up"). For UI/audio messages.
static func describe_offset(delta: Vector3) -> String:
	var parts: Array[String] = []
	if absf(delta.x) >= 0.05:
		parts.append("%.1fm %s" % [absf(delta.x), "east" if delta.x > 0.0 else "west"])
	if absf(delta.z) >= 0.05:
		parts.append("%.1fm %s" % [absf(delta.z), "south" if delta.z > 0.0 else "north"])
	if absf(delta.y) >= 0.05:
		parts.append("%.1fm %s" % [absf(delta.y), "up" if delta.y > 0.0 else "down"])
	return ", ".join(parts) if not parts.is_empty() else "same spot"

static func aabbs_overlap(a_pos: Vector3, a_size: Vector3, b_pos: Vector3, b_size: Vector3) -> bool:
	return (a_pos.x - a_size.x/2) < (b_pos.x + b_size.x/2) and \
		   (a_pos.x + a_size.x/2) > (b_pos.x - b_size.x/2) and \
		   a_pos.y < (b_pos.y + b_size.y) and \
		   (a_pos.y + a_size.y) > b_pos.y and \
		   (a_pos.z - a_size.z/2) < (b_pos.z + b_size.z/2) and \
		   (a_pos.z + a_size.z/2) > (b_pos.z - b_size.z/2)

## Returns true when inner is fully enclosed by outer (boundaries may touch within EPSILON).
static func aabb_contains(outer_pos: Vector3, outer_size: Vector3,
		inner_pos: Vector3, inner_size: Vector3) -> bool:
	return (inner_pos.x - inner_size.x / 2) >= (outer_pos.x - outer_size.x / 2) - SpatialEntity3D.EPSILON and \
		   (inner_pos.x + inner_size.x / 2) <= (outer_pos.x + outer_size.x / 2) + SpatialEntity3D.EPSILON and \
		   inner_pos.y >= outer_pos.y - SpatialEntity3D.EPSILON and \
		   (inner_pos.y + inner_size.y) <= (outer_pos.y + outer_size.y) + SpatialEntity3D.EPSILON and \
		   (inner_pos.z - inner_size.z / 2) >= (outer_pos.z - outer_size.z / 2) - SpatialEntity3D.EPSILON and \
		   (inner_pos.z + inner_size.z / 2) <= (outer_pos.z + outer_size.z / 2) + SpatialEntity3D.EPSILON

# ---------------------------------------------------------------------------
# Connection detection
# ---------------------------------------------------------------------------

## Face must be within this distance of a room wall to trigger a door check.
## Faces farther away are treated as interior connections (no wall in the way).
const ADJACENCY_TOLERANCE := 0.2

## Returns a ConnectionInfo for each connectable face of entity that has
## another SpatialEntity3D on the other side.
func find_connections(entity: SpatialEntity3D) -> Array[ConnectionInfo]:
	var result: Array[ConnectionInfo] = []
	for face in entity.connection_probe_points():
		var probe: Vector3 = face["probe_world"]
		var candidates := entities_containing_sorted(probe)
		var neighbor: SpatialEntity3D = null
		for c in candidates:
			if c != entity: neighbor = c; break
		if neighbor == null: continue
		var info := ConnectionInfo.new()
		info.from_label = face["label"]
		info.to_entity = neighbor
		if neighbor is Room3D:
			var room := neighbor as Room3D
			var wall_side := _nearest_room_wall(room, face["face_center_world"])
			info.to_wall_side = wall_side
			if wall_side == "":
				info.status = ConnectionInfo.Status.OPEN  # interior, no wall in the way
			else:
				info.status = _wall_open_status(room, wall_side,
					face["face_center_world"], face["face_width"], face["face_height"])
		else:
			info.to_wall_side = ""
			info.status = ConnectionInfo.Status.OPEN  # ramps/stairs have open ends
		result.append(info)
	return result

## Returns the cardinal wall side of room whose plane is closest to face_center_world,
## or "" if all walls are farther than ADJACENCY_TOLERANCE (face is in the room interior).
func _nearest_room_wall(room: Room3D, face_center_world: Vector3) -> String:
	var checks := {
		"north": absf(face_center_world.z - (room.global_position.z - room.size.z / 2.0)),
		"south": absf(face_center_world.z - (room.global_position.z + room.size.z / 2.0)),
		"east":  absf(face_center_world.x - (room.global_position.x + room.size.x / 2.0)),
		"west":  absf(face_center_world.x - (room.global_position.x - room.size.x / 2.0)),
	}
	var best_side := ""
	var best_dist := INF
	for side in checks:
		if checks[side] < best_dist:
			best_dist = checks[side]; best_side = side
	return best_side if best_dist <= ADJACENCY_TOLERANCE else ""

## Projects face_center_world into room's wall UV frame and checks whether any
## door opening in door_list intersects the face rectangle. Returns OPEN if yes.
## UV conventions match _build_wall() and _doorway_world_pos():
##   north/south: bu=RIGHT(+X), bv=UP  →  u = face.x - room.position.x
##   east/west:   bu=FORWARD(-Z), bv=UP →  u = room.position.z - face.z
func _wall_open_status(room: Room3D, side: String,
		face_center_world: Vector3, face_width: float, face_height: float) -> ConnectionInfo.Status:
	var wall_cfg := room.cfg(side)
	if wall_cfg == null or not wall_cfg.enabled:
		return ConnectionInfo.Status.OPEN
	var wall_center_y: float = room.global_position.y + room.size.y / 2.0
	var u: float
	var v: float = face_center_world.y - wall_center_y
	match side:
		"north", "south": u = face_center_world.x - room.global_position.x
		"east",  "west":  u = room.global_position.z - face_center_world.z
		_: return ConnectionInfo.Status.BLOCKED
	var face_rect := Rect2(u - face_width / 2.0, v - face_height / 2.0, face_width, face_height)
	for d: DoorEntry in room.door_list:
		if d.side != side: continue
		var door_rect := Rect2(d.center_u - d.width / 2.0, d.center_v - d.height / 2.0, d.width, d.height)
		if face_rect.intersects(door_rect):
			return ConnectionInfo.Status.OPEN
	return ConnectionInfo.Status.BLOCKED

# ---------------------------------------------------------------------------
# Gap detection
# ---------------------------------------------------------------------------

## Scans all SpatialEntity3D pairs for gaps between wall planes.
## Returns an array of dicts: {entity_a, entity_b, wall_a, wall_b, gap_distance, midpoint}.
## Only reports gaps where 0 < gap <= max_gap_distance and wall faces overlap.
func detect_gaps(max_gap_distance: float) -> Array[Dictionary]:
	var entities: Array[SpatialEntity3D] = []
	for e in entities_in_scene():
		if e is SpatialEntity3D:
			entities.append(e as SpatialEntity3D)
	var results: Array[Dictionary] = []
	for i in entities.size():
		for j in range(i + 1, entities.size()):
			var a := entities[i]
			var b := entities[j]
			for fa in a.boundary_faces():
				var ga := _face_geometry(fa)
				for fb in b.boundary_faces():
					var gb := _face_geometry(fb)
					if ga["axis"] != gb["axis"]: continue
					if ga["normal_sign"] == gb["normal_sign"]: continue
					# The face with normal_sign -1 lies on the higher plane coord side of the gap.
					var neg := ga if ga["normal_sign"] == -1 else gb
					var pos := gb if ga["normal_sign"] == -1 else ga
					var gap: float = (neg["plane_pos"] as float) - (pos["plane_pos"] as float)
					if gap <= SpatialEntity3D.EPSILON or gap > max_gap_distance: continue
					if not _faces_overlap_perp(neg, pos): continue
					if not _ranges_overlap(
						neg["y_lo"] as float, neg["y_hi"] as float,
						pos["y_lo"] as float, pos["y_hi"] as float): continue
					results.append({
						"entity_a": a, "entity_b": b,
						"wall_a": fa["label"], "wall_b": fb["label"],
						"gap_distance": gap,
						"midpoint": _gap_midpoint(neg, pos, gap),
					})
	return results

## Projects a connection_probe_points() face dict into axis-aligned scalar
## extents used by gap detection: axis ("x" or "z"), normal_sign (+/-1),
## plane_pos, perp_lo/hi along the non-vertical perpendicular axis, and y_lo/y_hi.
func _face_geometry(face: Dictionary) -> Dictionary:
	var normal: Vector3 = face["normal"]
	var center: Vector3 = face["face_center_world"]
	var fw: float = face["face_width"]
	var fh: float = face["face_height"]
	var axis: String
	var normal_sign: int
	var plane_pos: float
	var perp_lo: float
	var perp_hi: float
	if absf(normal.x) > 0.5:
		axis = "x"
		normal_sign = 1 if normal.x > 0.0 else -1
		plane_pos = center.x
		perp_lo = center.z - fw / 2.0
		perp_hi = center.z + fw / 2.0
	else:
		axis = "z"
		normal_sign = 1 if normal.z > 0.0 else -1
		plane_pos = center.z
		perp_lo = center.x - fw / 2.0
		perp_hi = center.x + fw / 2.0
	return {
		"axis": axis, "normal_sign": normal_sign, "plane_pos": plane_pos,
		"perp_lo": perp_lo, "perp_hi": perp_hi,
		"y_lo": center.y - fh / 2.0, "y_hi": center.y + fh / 2.0,
	}

## Returns true when two perpendicular extents overlap.
func _faces_overlap_perp(a: Dictionary, b: Dictionary) -> bool:
	return (a["perp_hi"] as float) > (b["perp_lo"] as float) + SpatialEntity3D.EPSILON and \
		   (b["perp_hi"] as float) > (a["perp_lo"] as float) + SpatialEntity3D.EPSILON

## Returns true when two 1D ranges overlap.
func _ranges_overlap(a_lo: float, a_hi: float, b_lo: float, b_hi: float) -> bool:
	return a_hi > b_lo + SpatialEntity3D.EPSILON and b_hi > a_lo + SpatialEntity3D.EPSILON

## Computes the world-space midpoint of the gap between two facing walls.
func _gap_midpoint(neg_face: Dictionary, pos_face: Dictionary, gap: float) -> Vector3:
	var perp_center: float = ((neg_face["perp_lo"] as float + neg_face["perp_hi"] as float) / 2.0 + \
						(pos_face["perp_lo"] as float + pos_face["perp_hi"] as float) / 2.0) / 2.0
	var y_center: float = (minf(neg_face["y_lo"] as float, pos_face["y_lo"] as float) + \
					 maxf(neg_face["y_hi"] as float, pos_face["y_hi"] as float)) / 2.0
	var gap_center: float = (pos_face["plane_pos"] as float) + gap / 2.0
	match neg_face["axis"]:
		"x":
			return Vector3(gap_center, y_center, perp_center)
		"z":
			return Vector3(perp_center, y_center, gap_center)
	return Vector3.ZERO
