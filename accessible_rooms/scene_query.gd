@tool
class_name SceneQuery
extends Node

var plugin: EditorPlugin

func edited_root() -> Node:
	return plugin.get_editor_interface().get_edited_scene_root()

# All non-generated entities: Room3D nodes and user-placed PhysicsBody3D nodes.
# Stops recursing into an entity once found, avoiding generated wall children.
func entities_in_scene() -> Array[Node]:
	var root := edited_root()
	if root == null: return []
	var result: Array[Node] = []
	_collect(root, result)
	return result

func _collect(node: Node, out: Array[Node]) -> void:
	if node.has_meta("generated"): return
	if node is Room3D or node is PhysicsBody3D:
		out.append(node); return
	for child in node.get_children():
		_collect(child, out)

func entity_position(entity: Node) -> Vector3:
	return (entity as Node3D).global_position if entity is Node3D else Vector3.ZERO

func entity_label(entity: Node) -> String:
	if entity is Room3D:
		var r := entity as Room3D
		return "%s (room, %.0fx%.0fx%.0f m)" % [r.name, r.size.x, r.size.y, r.size.z]
	var root := edited_root()
	var parent := entity.get_parent()
	if parent != null and parent != root and not parent.has_meta("generated"):
		return "%s / %s" % [parent.name, entity.name]
	return entity.name

func room_containing(p: Vector3) -> Room3D:
	var root := edited_root()
	if root == null: return null
	for c in root.get_children():
		if c is Room3D:
			var lp: Vector3 = p - c.position
			var s: Vector3 = c.size
			if absf(lp.x) <= s.x/2 and lp.y >= 0 and lp.y <= s.y and absf(lp.z) <= s.z/2:
				return c
	return null

# Returns readable labels for all physics shapes that contain point p.
# Uses Jolt broadphase  should be safe to call on every cursor move even in large scenes.
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
		if collider.has_meta("generated") and collider.get_parent() is Room3D:
			var side := collider.name.split("_")[0]
			var surface: String = collider.get_meta("surface", "wall")
			labels.append("%s of %s (%s)" % [side, collider.get_parent().name, surface])
		else:
			labels.append(entity_label(collider))
	return labels

# Non-room entities within radius meters of p.
func entities_near_point(p: Vector3, radius: float) -> Array[Node]:
	var result: Array[Node] = []
	for entity in entities_in_scene():
		if entity is Room3D: continue
		if entity_position(entity).distance_to(p) <= radius:
			result.append(entity)
	return result

# Nearest entity in the forward half-space of dir from the given position.
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

# Raycast probe in all 6 directions; reports surface type for walls, entity name otherwise.
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

## Cast downward from `from`; return the Y of the first surface hit, or null if none.
func raycast_down(from: Vector3) -> Variant:
	var space := _get_space()
	if space == null: return null
	var params := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -50, 0))
	var hit := space.intersect_ray(params)
	return hit["position"].y if hit else null

## Cast from `from` in `dir` (max_dist meters); return the hit position Vector3, or null.
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

static func aabbs_overlap(a_pos: Vector3, a_size: Vector3, b_pos: Vector3, b_size: Vector3) -> bool:
	return (a_pos.x - a_size.x/2) < (b_pos.x + b_size.x/2) and \
		   (a_pos.x + a_size.x/2) > (b_pos.x - b_size.x/2) and \
		   a_pos.y < (b_pos.y + b_size.y) and \
		   (a_pos.y + a_size.y) > b_pos.y and \
		   (a_pos.z - a_size.z/2) < (b_pos.z + b_size.z/2) and \
		   (a_pos.z + a_size.z/2) > (b_pos.z - b_size.z/2)
