@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var _nudge_dist: SpinBox
var _floor_offset: SpinBox
var _wall_offset: SpinBox
var _door_inset: SpinBox

func _ready() -> void:
	# --- Selected object ---
	var obj_lbl := Label.new(); obj_lbl.text = "Selected object:"
	add_child(obj_lbl)

	var obj_row := HBoxContainer.new()
	_btn_h(obj_row, "Report position", _report_position)
	_btn_h(obj_row, "Measure distances", _measure_distances)
	add_child(obj_row)

	add_child(HSeparator.new())

	# --- Move to cursor ---
	var move_lbl := Label.new(); move_lbl.text = "Move to cursor:"
	add_child(move_lbl)

	var move_row := HBoxContainer.new()
	_btn_h(move_row, "Check if cursor is clear", _check_cursor)
	_btn_h(move_row, "Move to cursor", _move_to_cursor)
	add_child(move_row)

	add_child(HSeparator.new())

	# --- Nudge ---
	var nudge_lbl := Label.new(); nudge_lbl.text = "Nudge (collision-aware):"
	add_child(nudge_lbl)

	var nudge_step_row := HBoxContainer.new()
	var nudge_step_lbl := Label.new(); nudge_step_lbl.text = "Distance (m):"
	_nudge_dist = SpinBox.new()
	_nudge_dist.min_value = 0.01; _nudge_dist.max_value = 5.0
	_nudge_dist.step = 0.05; _nudge_dist.value = 0.5
	nudge_step_row.add_child(nudge_step_lbl); nudge_step_row.add_child(_nudge_dist)
	add_child(nudge_step_row)

	var ns_row := HBoxContainer.new()
	_btn_h(ns_row, "North", _nudge.bind(Vector3.FORWARD))
	_btn_h(ns_row, "South", _nudge.bind(Vector3.BACK))
	add_child(ns_row)

	var ew_row := HBoxContainer.new()
	_btn_h(ew_row, "East", _nudge.bind(Vector3.RIGHT))
	_btn_h(ew_row, "West", _nudge.bind(Vector3.LEFT))
	add_child(ew_row)

	var ud_row := HBoxContainer.new()
	_btn_h(ud_row, "Up", _nudge.bind(Vector3.UP))
	_btn_h(ud_row, "Down", _nudge.bind(Vector3.DOWN))
	add_child(ud_row)

	add_child(HSeparator.new())

	# --- Snap ---
	var snap_lbl := Label.new(); snap_lbl.text = "Snap:"
	add_child(snap_lbl)

	var floor_row := HBoxContainer.new()
	var floor_lbl := Label.new(); floor_lbl.text = "Floor offset (m):"
	_floor_offset = SpinBox.new()
	_floor_offset.min_value = -10.0; _floor_offset.max_value = 10.0
	_floor_offset.step = 0.05; _floor_offset.value = 0.0
	_btn_h(floor_row, "Snap to floor", _snap_to_floor)
	floor_row.add_child(floor_lbl); floor_row.add_child(_floor_offset)
	add_child(floor_row)

	var wall_row := HBoxContainer.new()
	var wall_lbl := Label.new(); wall_lbl.text = "Wall offset (m):"
	_wall_offset = SpinBox.new()
	_wall_offset.min_value = 0.0; _wall_offset.max_value = 5.0
	_wall_offset.step = 0.05; _wall_offset.value = 0.0
	_btn_h(wall_row, "Snap to nearest wall", _snap_to_nearest_wall)
	wall_row.add_child(wall_lbl); wall_row.add_child(_wall_offset)
	add_child(wall_row)

	var center_row := HBoxContainer.new()
	_btn_h(center_row, "Center E\u2194W", _center_east_west)
	_btn_h(center_row, "Center N\u2194S", _center_north_south)
	add_child(center_row)

	var door_row := HBoxContainer.new()
	var door_lbl := Label.new(); door_lbl.text = "Door inset (m):"
	_door_inset = SpinBox.new()
	_door_inset.min_value = 0.0; _door_inset.max_value = 2.0
	_door_inset.step = 0.05; _door_inset.value = 0.05
	_btn_h(door_row, "Snap to nearest doorway", _snap_to_nearest_doorway)
	door_row.add_child(door_lbl); door_row.add_child(_door_inset)
	add_child(door_row)

# --- Object info ---

func _report_position() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var p: Vector3 = n.global_position
	dock._say("%s is at %.2f, %.2f, %.2f." % [n.name, p.x, p.y, p.z])

func _measure_distances() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	dock._say("%s: %s" % [n.name, dock.scene_query.probe_report(n.global_position)])

# --- Move to cursor ---

func _check_cursor() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var result: Dictionary = dock.scene_query.check_placement(n, dock.cursor)
	if result["collider_name"] == "no shape":
		dock._say("No collision shape on %s, cannot check." % n.name)
	elif result["collides"]:
		dock._say("Placing %s at cursor would be blocked by %s." % [n.name, result["collider_name"]])
	else:
		dock._say("Cursor position is clear.")

func _move_to_cursor() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var result: Dictionary = dock.scene_query.check_placement(n, dock.cursor)
	if result["collider_name"] == "no shape":
		n.global_position = dock.cursor
		dock._say("Moved %s to cursor (no collision shape to check)." % n.name)
	elif result["collides"]:
		dock._say("Cannot move %s, blocked by %s." % [n.name, result["collider_name"]])
	else:
		n.global_position = dock.cursor
		dock._say("Moved %s to cursor at %.2f, %.2f, %.2f." % [n.name, dock.cursor.x, dock.cursor.y, dock.cursor.z])

# --- Nudge ---

func _nudge(dir: Vector3) -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var amount := _nudge_dist.value
	var target: Vector3 = n.global_position + dir * amount
	var result: Dictionary = dock.scene_query.check_placement(n, target)
	var dir_name := _dir_name(dir)
	if result["collider_name"] == "no shape":
		n.global_position = target
		dock._say("Nudged %s %s %.2fm (no collision shape to check)." % [n.name, dir_name, amount])
	elif result["collides"]:
		dock._say("Cannot nudge %s %s, blocked by %s." % [n.name, dir_name, result["collider_name"]])
	else:
		n.global_position = target
		dock._say("Nudged %s %s %.2fm." % [n.name, dir_name, amount])

func _dir_name(dir: Vector3) -> String:
	if dir == Vector3.FORWARD: return "north"
	if dir == Vector3.BACK:    return "south"
	if dir == Vector3.RIGHT:   return "east"
	if dir == Vector3.LEFT:    return "west"
	if dir == Vector3.UP:      return "up"
	if dir == Vector3.DOWN:    return "down"
	return "in direction"

# --- Snap ---

func _snap_to_floor() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var floor_y = dock.scene_query.raycast_down(n.global_position)
	if floor_y == null: dock._say("No floor found below %s." % n.name); return
	var shape_node: CollisionShape3D = dock.scene_query.find_collision_shape(n)
	var origin_above_bottom := 0.0
	if shape_node != null and shape_node.shape is BoxShape3D:
		origin_above_bottom = (shape_node.shape as BoxShape3D).size.y / 2.0 - shape_node.position.y
	n.global_position.y = floor_y + origin_above_bottom + _floor_offset.value
	dock._say("Snapped %s to floor (y=%.2f)." % [n.name, n.global_position.y])

func _snap_to_nearest_wall() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var dirs := {"north": Vector3.FORWARD, "south": Vector3.BACK,
				 "east": Vector3.RIGHT, "west": Vector3.LEFT}
	var best_hit: Vector3
	var best_dir: Vector3
	var best_side := ""
	var best_dist := INF
	for side in dirs:
		var hit = dock.scene_query.raycast_direction(n.global_position, dirs[side])
		if hit == null: continue
		var d: float = n.global_position.distance_to(hit)
		if d < best_dist:
			best_dist = d; best_hit = hit; best_dir = dirs[side]; best_side = side
	if best_side == "":
		dock._say("No wall found in any direction."); return
	var shape_node: CollisionShape3D = dock.scene_query.find_collision_shape(n)
	var origin_to_face := 0.0
	if shape_node != null and shape_node.shape is BoxShape3D:
		var sz: Vector3 = (shape_node.shape as BoxShape3D).size
		var abs_dir := Vector3(absf(best_dir.x), absf(best_dir.y), absf(best_dir.z))
		origin_to_face = sz.dot(abs_dir) / 2.0 + shape_node.position.dot(best_dir)
	n.global_position = best_hit - best_dir * (origin_to_face + _wall_offset.value)
	dock._say("Snapped %s to %s wall (%.1fm away)." % [n.name, best_side, best_dist])

func _center_east_west() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var gap: Dictionary = dock.scene_query.wall_gap(n.global_position, Vector3.RIGHT)
	if gap.is_empty(): dock._say("Could not find walls on both east and west sides."); return
	n.global_position.x = (gap["midpoint"] as Vector3).x
	dock._say("Centered %s east-west (gap %.1fm)." % [n.name, gap["gap"]])

func _center_north_south() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var gap: Dictionary = dock.scene_query.wall_gap(n.global_position, Vector3.BACK)
	if gap.is_empty(): dock._say("Could not find walls on both north and south sides."); return
	n.global_position.z = (gap["midpoint"] as Vector3).z
	dock._say("Centered %s north-south (gap %.1fm)." % [n.name, gap["gap"]])

func _snap_to_nearest_doorway() -> void:
	var n: Node3D = dock.get_target_node()
	if n == null: return
	var info: Dictionary = dock.scene_query.nearest_doorway(n.global_position)
	if info.is_empty(): dock._say("No doorway found nearby. Is the node inside a room?"); return
	var wpos: Vector3 = info["world_pos"]
	var inward_normals := {"north": Vector3.BACK, "south": Vector3.FORWARD,
						   "east": Vector3.LEFT, "west": Vector3.RIGHT}
	var inward: Vector3 = inward_normals.get(info["side"], Vector3.ZERO)
	n.global_position = wpos + inward * _door_inset.value
	dock._say("Snapped %s to %s doorway (%.1fm \u00d7 %.1fm)." % [n.name, info["side"], info["width"], info["height"]])

# --- Helpers ---

func _btn_h(container: HBoxContainer, label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); container.add_child(b)
