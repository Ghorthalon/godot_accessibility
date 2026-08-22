@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var step_field: SpinBox
var cursor_label: Label
var nav_control: NavControl
var _audio_preview_enabled: CheckBox

func _ready() -> void:
	var nav_lbl := Label.new(); nav_lbl.text = "Keyboard navigation:"
	add_child(nav_lbl)
	nav_control = NavControl.new()
	add_child(nav_control)
	nav_control.move_cursor.connect(_move_cursor)
	nav_control.jump_entity.connect(_jump_to_entity)
	nav_control.step_up.connect(_on_step_up)
	nav_control.step_down.connect(_on_step_down)
	nav_control.snap_floor.connect(_snap_to_floor)
	nav_control.snap_wall.connect(_snap_to_wall)
	nav_control.snap_room.connect(_snap_to_room)
	nav_control.probe.connect(_probe)
	nav_control.scan_nearby.connect(_scan_nearby)
	nav_control.report_location.connect(_report_cursor)
	nav_control.new_standalone_room.connect(func(): dock.tab_rooms._new_root_room())
	nav_control.punch_door_at_cursor.connect(func(): dock.tab_rooms._punch_at_cursor())
	nav_control.corner_a.connect(func(): dock.corner_selector._set_corner_a())
	nav_control.corner_b.connect(func(): dock.corner_selector._set_corner_b())
	nav_control.place_room_from_corners.connect(func(): dock.tab_rooms._place_room_from_corners())
	nav_control.place_stairs_from_corners.connect(func(): dock.tab_stairs._place_stairs_from_corners())
	nav_control.place_ramps_from_corners.connect(func(): dock.tab_ramps._place_ramps_from_corners())
	nav_control.nudge_node_to_floor.connect(func(): dock.tab_place._nudge_to_floor())
	nav_control.snap_node_to_wall.connect(func(): dock.tab_place._snap_to_nearest_wall())
	nav_control.snap_node_to_doorway.connect(func(): dock.tab_place._snap_to_nearest_doorway())
	nav_control.center_node_ew.connect(func(): dock.tab_place._center_east_west())
	nav_control.center_node_ns.connect(func(): dock.tab_place._center_north_south())
	nav_control.add_zone_to_floor.connect(func(): dock.tab_place._add_floor_zone())
	dock.cursor_jumped.connect(_report_cursor)

	var h := HBoxContainer.new()
	var sl := Label.new(); sl.text = "Step (m):"
	step_field = SpinBox.new()
	step_field.min_value = 0.1; step_field.max_value = 20.0
	step_field.step = 0.1; step_field.value = 1.0
	step_field.value_changed.connect(func(v): dock.step = v; dock._say("Step %.1f meters." % v))
	h.add_child(sl); h.add_child(step_field)
	add_child(h)

	cursor_label = Label.new()
	cursor_label.accessibility_live = 1  # ACCESSIBILITY_LIVE_POLITE
	add_child(cursor_label)

	for d in [["West", "-x"], ["East", "+x"], ["Down", "-y"], ["Up", "+y"],
			  ["North", "-z"], ["South", "+z"]]:
		_btn("Move %s" % d[0], _move_cursor.bind(d[1]))
	_btn("Snap cursor to current room", _snap_to_room)
	_btn("Probe distances (6 directions)", _probe)
	_btn("Scan nearby objects (5x step)", _scan_nearby)
	_btn("Report cursor location", _report_cursor)

	add_child(HSeparator.new())
	var snap_lbl := Label.new(); snap_lbl.text = "Snap cursor to geometry:"
	add_child(snap_lbl)
	var snap_row := HBoxContainer.new()
	for pair in [["Floor (F)", _snap_to_floor], ["North", _snap_to_wall.bind("north")],
				 ["South", _snap_to_wall.bind("south")], ["East", _snap_to_wall.bind("east")],
				 ["West", _snap_to_wall.bind("west")]]:
		var b := Button.new(); b.text = pair[0]; b.pressed.connect(pair[1])
		snap_row.add_child(b)
	add_child(snap_row)

	add_child(HSeparator.new())
	var cs_lbl := Label.new(); cs_lbl.text = "Corner selection:"
	add_child(cs_lbl)
	var corner_selector := CornerSelector.new()
	corner_selector.dock = dock
	add_child(corner_selector)
	dock.corner_selector = corner_selector

	add_child(HSeparator.new())
	_audio_preview_enabled = CheckBox.new()
	_audio_preview_enabled.text = "Audio preview (hear scene from cursor)"
	_audio_preview_enabled.button_pressed = false
	_audio_preview_enabled.toggled.connect(_on_audio_preview_toggled)
	add_child(_audio_preview_enabled)

	add_child(HSeparator.new())
	var jl := Label.new(); jl.text = "Jump to entity:"
	add_child(jl)
	for d in [["Jump West", "-x"], ["Jump East", "+x"], ["Jump Down", "-y"],
			  ["Jump Up", "+y"], ["Jump North", "-z"], ["Jump South", "+z"]]:
		_btn(d[0], _jump_to_entity.bind(d[1]))

# --- Cursor movement ---

func _move_cursor(axis: String) -> void:
	var c: Vector3 = dock.cursor
	match axis:
		"-x": c.x -= dock.step
		"+x": c.x += dock.step
		"-y": c.y -= dock.step
		"+y": c.y += dock.step
		"-z": c.z -= dock.step
		"+z": c.z += dock.step
	dock.cursor = c
	_report_cursor()

func _snap_to_room() -> void:
	if dock.current_entity == null: dock._say("No current entity."); return
	dock.cursor = (dock.current_entity as Node3D).global_position + Vector3(0, 1.5, 0)
	_report_cursor()

func _snap_to_floor() -> void:
	var y = dock.scene_query.raycast_down(dock.cursor)
	if y == null: dock._say("Nothing below cursor."); return
	var c: Vector3 = dock.cursor
	c.y = y
	dock.cursor = c
	_report_cursor()

func _snap_to_wall(side: String) -> void:
	var dirs := {"north": Vector3(0,0,-1), "south": Vector3(0,0,1),
				 "east": Vector3(1,0,0), "west": Vector3(-1,0,0)}
	var hit = dock.scene_query.raycast_direction(dock.cursor, dirs[side])
	if hit == null: dock._say("No wall to the %s." % side); return
	dock.cursor = hit
	_report_cursor()

func _report_cursor() -> void:
	var parts: Array[String] = []

	var overlapping: Array[String] = dock.scene_query.overlapping_at(dock.cursor)
	if overlapping.is_empty():
		parts.append("empty space")
	else:
		parts.append("inside: " + ", ".join(overlapping))

	var containers: Array[SpatialEntity3D] = dock.scene_query.entities_containing_sorted(dock.cursor)
	var container: SpatialEntity3D = containers[0] if not containers.is_empty() else null
	parts.append("in " + dock.scene_query.entity_label(container) if container else "outside any room")
	# Height above the floor SURFACE, not above the room origin: the floor slab
	# grows inward, so those differ by the floor thickness and only the former
	# tells you whether something placed here would be sitting in the ground.
	if container is Room3D:
		var room := container as Room3D
		var above: float = dock.cursor.y - room.floor_surface_y()
		if absf(above) < 0.005:
			parts.append("exactly on the floor surface")
		elif above < 0.0:
			parts.append("%.2fm BELOW the floor surface, inside the ground" % -above)
		else:
			parts.append("%.2fm above the floor surface, %.2fm headroom" % 					[above, room.ceiling_surface_y() - dock.cursor.y])

	var nearby: Array[Node3D] = dock.scene_query.nearby_point_nodes(dock.cursor, dock.step)
	if not nearby.is_empty():
		var entries: Array[String] = []
		var limit := mini(nearby.size(), 4)
		for i in limit:
			var n := nearby[i]
			var d: float = n.global_position.distance_to(dock.cursor)
			entries.append("%s (%.1fm)" % [dock.scene_query.entity_label(n), d])
		var tail := "" if nearby.size() <= limit else ", and %d more" % (nearby.size() - limit)
		parts.append("near: " + ", ".join(entries) + tail)

	var msg := "Cursor %.1f %.1f %.1f. %s." % [dock.cursor.x, dock.cursor.y, dock.cursor.z, ". ".join(parts)]
	cursor_label.text = msg
	dock._say(msg)
	var audio_node: Node3D = dock.scene_query.innermost_container_node(dock.cursor)
	if audio_node != null:
		dock.play_audio_3d("inside", audio_node.global_position)
	if dock.audio_debugger and _audio_preview_enabled and _audio_preview_enabled.button_pressed:
		dock.audio_debugger.send_cursor(dock.cursor)

func _probe() -> void:
	dock._say(dock.scene_query.probe_report(dock.cursor))
	var positions: Array[Vector3] = dock.scene_query.probe_positions(dock.cursor)
	if not positions.is_empty():
		dock.play_audio_staggered("distance", positions)

func _scan_nearby() -> void:
	var radius: float = dock.step * 5.0
	var nodes: Array[Node3D] = dock.scene_query.nearby_placeable_nodes(dock.cursor, radius)
	if nodes.is_empty():
		dock._say("Nothing within %.1f meters." % radius)
		return
	var positions: Array[Vector3] = []
	for n in nodes:
		positions.append(n.global_position)
	dock.play_audio_staggered("object", positions)
	var entries: Array[String] = []
	var limit := mini(nodes.size(), 6)
	for i in limit:
		var n := nodes[i]
		var offset := SceneQuery.describe_offset(n.global_position - dock.cursor)
		entries.append("%s %s" % [dock.scene_query.entity_label(n), offset])
	var tail := "" if nodes.size() <= limit else "; and %d more" % (nodes.size() - limit)
	dock._say("%d within %.1f meters: %s%s." % [nodes.size(), radius, "; ".join(entries), tail])

# --- Jump to entity ---

func _jump_to_entity(axis: String) -> void:
	var entity: Node = dock.scene_query.nearest_in_direction(dock.cursor, _axis_to_dir(axis))
	if entity == null: dock._say("Nothing in that direction."); return
	dock.cursor = dock.scene_query.entity_position(entity)
	var sel: EditorSelection = dock.plugin.get_editor_interface().get_selection()
	sel.clear(); sel.add_node(entity)
	dock._say("Jumped to %s." % dock.scene_query.entity_label(entity))
	_report_cursor()

func _axis_to_dir(axis: String) -> Vector3:
	match axis:
		"-x": return Vector3.LEFT
		"+x": return Vector3.RIGHT
		"-y": return Vector3.DOWN
		"+y": return Vector3.UP
		"-z": return Vector3.FORWARD
		"+z": return Vector3.BACK
	return Vector3.ZERO

# --- Step size ---

func _on_step_up() -> void:
	step_field.value = clampf(step_field.value * 2.0, step_field.min_value, step_field.max_value)

func _on_step_down() -> void:
	step_field.value = clampf(step_field.value / 2.0, step_field.min_value, step_field.max_value)

# --- Audio preview ---

func _on_audio_preview_toggled(pressed: bool) -> void:
	if not pressed:
		if dock.audio_debugger:
			dock.audio_debugger.send_release()
		dock._say("Audio preview off.")
		return
	if dock.audio_debugger and not dock.audio_debugger.has_active_session():
		dock._say("Audio preview on, but no game session is active. Run the project (F5) first.")
	else:
		if dock.audio_debugger:
			dock.audio_debugger.send_cursor(dock.cursor)
		dock._say("Audio preview on.")

# --- Helpers ---

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
