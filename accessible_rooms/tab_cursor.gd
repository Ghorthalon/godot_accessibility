@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var step_field: SpinBox
var cursor_label: Label
var nav_control: NavControl
var _audio_preview_enabled: CheckBox

func _ready() -> void:
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
	nav_control.report_location.connect(_report_cursor)
	nav_control.new_standalone_room.connect(func(): dock.tab_rooms._new_root_room())
	nav_control.punch_door_at_cursor.connect(func(): dock.tab_rooms._punch_at_cursor())
	nav_control.room_corner_a.connect(func(): dock.tab_rooms._set_room_corner_a())
	nav_control.room_corner_b.connect(func(): dock.tab_rooms._set_room_corner_b())
	nav_control.place_room_from_corners.connect(func(): dock.tab_rooms._place_room_from_corners())
	nav_control.nudge_node_to_floor.connect(func(): dock.tab_place._nudge_to_floor())
	nav_control.snap_node_to_wall.connect(func(): dock.tab_place._snap_to_nearest_wall())
	nav_control.snap_node_to_doorway.connect(func(): dock.tab_place._snap_to_nearest_doorway())
	nav_control.center_node_ew.connect(func(): dock.tab_place._center_east_west())
	nav_control.center_node_ns.connect(func(): dock.tab_place._center_north_south())
	nav_control.zone_corner_a.connect(func(): dock.tab_place._set_zone_corner_a())
	nav_control.zone_corner_b.connect(func(): dock.tab_place._set_zone_corner_b())
	nav_control.add_zone_to_floor.connect(func(): dock.tab_place._add_floor_zone())

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
	dock.cursor = (dock.current_entity as Node3D).position + Vector3(0, 1.5, 0)
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

	var container: SpatialEntity3D = dock.scene_query.entity_containing(dock.cursor)
	parts.append("in " + dock.scene_query.entity_label(container) if container else "outside any room")

	var msg := "Cursor %.1f %.1f %.1f. %s." % [dock.cursor.x, dock.cursor.y, dock.cursor.z, ". ".join(parts)]
	cursor_label.text = msg
	dock._say(msg)
	if dock.audio_debugger and _audio_preview_enabled and _audio_preview_enabled.button_pressed:
		dock.audio_debugger.send_cursor(dock.cursor)

func _probe() -> void:
	dock._say(dock.scene_query.probe_report(dock.cursor))

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
