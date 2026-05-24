@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var ramp_w: SpinBox
var ramp_len: SpinBox
var ramp_hc: SpinBox
var ramp_cl: SpinBox
var ramp_landing_low: SpinBox
var ramp_landing_high: SpinBox
var door_w_ref: SpinBox  # mirrors dock's door_w, set via tab_rooms if needed
var _door_w: float = 1.2
var _door_h: float = 2.8
var _standalone_dir: String = "north"
var build_walls: CheckBox
var build_ceiling: CheckBox

func _ready() -> void:
	var rl := Label.new(); rl.text = "Ramp size (m):"
	add_child(rl)

	ramp_w            = _spinbox(0.5,  50.0,  0.5, 2.0)
	ramp_len          = _spinbox(0.5,  100.0, 0.5, 4.0)
	ramp_hc           = _spinbox(0.1,  20.0,  0.1, 1.0)
	ramp_cl           = _spinbox(1.0,  10.0,  0.1, 2.4)
	ramp_landing_low  = _spinbox(0.0,  10.0,  0.1, 0.5)
	ramp_landing_high = _spinbox(0.0,  10.0,  0.1, 0.5)

	var row := HBoxContainer.new()
	for pair in [["W:", ramp_w], ["Len:", ramp_len], ["Rise:", ramp_hc], ["Clear:", ramp_cl]]:
		var lbl := Label.new(); lbl.text = pair[0]
		row.add_child(lbl); row.add_child(pair[1])
	add_child(row)

	var landing_row := HBoxContainer.new()
	for pair in [["Land Low:", ramp_landing_low], ["Land High:", ramp_landing_high]]:
		var lbl := Label.new(); lbl.text = pair[0]
		landing_row.add_child(lbl); landing_row.add_child(pair[1])
	add_child(landing_row)

	var surface_row := HBoxContainer.new()
	build_walls = CheckBox.new()
	build_walls.text = "Build walls"
	build_walls.button_pressed = true
	build_ceiling = CheckBox.new()
	build_ceiling.text = "Build ceiling"
	build_ceiling.button_pressed = true
	surface_row.add_child(build_walls)
	surface_row.add_child(build_ceiling)
	add_child(surface_row)

	add_child(HSeparator.new())
	var dl := Label.new(); dl.text = "Connecting doorway (m):"
	add_child(dl)
	var door_w_spin := _spinbox(0.5, 20.0, 0.1, 1.2)
	var door_h_spin := _spinbox(0.5, 20.0, 0.1, 2.8)
	door_w_spin.value_changed.connect(func(v): _door_w = v)
	door_h_spin.value_changed.connect(func(v): _door_h = v)
	var dr := HBoxContainer.new()
	for pair in [["W:", door_w_spin], ["H:", door_h_spin]]:
		var lbl := Label.new(); lbl.text = pair[0]
		dr.add_child(lbl); dr.add_child(pair[1])
	add_child(dr)

	add_child(HSeparator.new())
	var dir_lbl := Label.new(); dir_lbl.text = "Standalone ramp high end:"
	add_child(dir_lbl)
	var dir_btn := OptionButton.new()
	for d in ["north", "south", "east", "west"]:
		dir_btn.add_item(d)
	dir_btn.item_selected.connect(func(idx: int) -> void:
		_standalone_dir = ["north", "south", "east", "west"][idx])
	add_child(dir_btn)
	_btn("New standalone ramp at cursor", _new_standalone_ramp)
	_btn("Place ramp from corners", _place_ramps_from_corners)

	add_child(HSeparator.new())
	for side in ["north", "south", "east", "west"]:
		_btn("Add ramp to %s of current room" % side, _add_ramp.bind(side))

	add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = ("Workflow: (1) Select a room. (2) Add ramp to a side. " +
		"(3) Place the connecting room at the far end, elevated by the Rise amount.\n" +
		"Important: do NOT place the connecting room adjacent first, the ramp needs that gap.\n" +
		"Clearance must exceed the player capsule height (default 2.0 m), use 2.6 m+ for safety.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

# ---------------------------------------------------------------------------

func _add_ramp(side: String) -> void:
	if not dock.current_entity is Room3D:
		dock._say("No room selected. Select a Room3D first.")
		return
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var room := dock.current_entity as Room3D
	var floor_t: float = room.wall_floor.thickness if room.wall_floor else 0.0

	var clearance_safety := 0.05
	if _door_h + floor_t > ramp_cl.value - clearance_safety:
		dock._say_err(("Cannot place ramp: door height %.2fm + floor thickness %.2fm exceeds " +
			"clearance %.2fm. Lower door height (≤%.2fm) or raise clearance (≥%.2fm).") % \
			[_door_h, floor_t, ramp_cl.value,
			 ramp_cl.value - floor_t - clearance_safety,
			 _door_h + floor_t + clearance_safety])
		return

	var r := Ramp3D.new()
	r.name = "%s_ramp_%s" % [room.name, side]
	r.width         = ramp_w.value
	r.length        = ramp_len.value
	r.height_change = ramp_hc.value
	r.clearance     = ramp_cl.value
	r.floor_thickness = floor_t
	r.landing_depth_low  = ramp_landing_low.value
	r.landing_depth_high = ramp_landing_high.value
	# HIGH end faces the same direction as the attachment side, ramp rises away from the source room.
	r.high_end = side

	var footprint: Vector3
	match side:
		"north", "south": footprint = Vector3(r.width, r.clearance, r.length)
		"east",  "west":  footprint = Vector3(r.length, r.clearance, r.width)
	var ramp_pos: Vector3 = room.position + room.neighbor_offset(side, footprint)

	var conflict: String = dock.scene_query.first_overlap(ramp_pos, _ramp_footprint(footprint), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say(("Cannot place ramp: %s already occupies the %s footprint. " +
			"Remove or move it first, or hold Shift to force.") % [conflict, side])
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	_apply_surface_settings(r)
	root.add_child(r)
	r.owner = dock.scene_query.edited_root()
	r.position = ramp_pos

	var cv: float = -room.size.y / 2.0 + _door_h / 2.0 + floor_t
	var d_low := DoorEntry.new()
	d_low.side = "low"; d_low.center_u = 0.0; d_low.center_v = cv
	d_low.width = _door_w; d_low.height = _door_h
	r.door_list.append(d_low)
	var d_high := DoorEntry.new()
	d_high.side = "high"; d_high.center_u = 0.0; d_high.center_v = cv
	d_high.width = _door_w; d_high.height = _door_h
	r.door_list.append(d_high)

	r.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	var angle: float = r.slope_degrees()
	var hi_pos: Vector3 = r.position + r.high_end_room_offset(Vector3(4, 3, 4))
	dock._say(("Added ramp to %s of %s. " +
		"Rises %.1fm over %.1fm (%.0f deg). " +
		"Place connecting room elevated %.1fm, centre near %s (varies with room size).") % \
		[side, room.name, r.height_change, r.length, angle, r.height_change, hi_pos])

# ---------------------------------------------------------------------------

func _new_standalone_ramp() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return

	var r := Ramp3D.new()
	r.name = "Ramp%d" % (root.get_child_count() + 1)
	r.width         = ramp_w.value
	r.length        = ramp_len.value
	r.height_change = ramp_hc.value
	r.clearance     = ramp_cl.value
	r.landing_depth_low  = ramp_landing_low.value
	r.landing_depth_high = ramp_landing_high.value
	r.high_end      = _standalone_dir

	var footprint: Vector3
	match r.high_end:
		"north", "south": footprint = Vector3(r.width, r.height_change + r.clearance, r.length)
		"east",  "west":  footprint = Vector3(r.length, r.height_change + r.clearance, r.width)

	var conflict: String = dock.scene_query.first_overlap(dock.cursor, _ramp_footprint(footprint), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say("Cannot place ramp: overlaps with %s. Move cursor clear first, or hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	_apply_surface_settings(r)
	root.add_child(r)
	r.owner = dock.scene_query.edited_root()
	r.position = dock.cursor
	r.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	dock._say(("Placed standalone ramp at cursor, high end %s. " +
		"Rise %.1fm over %.1fm (%.0f deg).") % \
		[r.high_end, r.height_change, r.length, r.slope_degrees()])

# ---------------------------------------------------------------------------

func _place_ramps_from_corners() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say_err("No scene open."); return
	var aabb: AABB = dock.corner_selector.get_aabb()

	var w_axis: float
	var l_axis: float
	match _standalone_dir:
		"north", "south":
			w_axis = aabb.size.x; l_axis = aabb.size.z
		"east", "west":
			w_axis = aabb.size.z; l_axis = aabb.size.x
		_:
			w_axis = aabb.size.x; l_axis = aabb.size.z
	if w_axis < 0.5 or l_axis < 0.5 or aabb.size.y < 0.1:
		dock._say_err("Corners too close: need at least 0.5m width, 0.5m length, and 0.1m rise. Set corner A and corner B first."); return

	var r := Ramp3D.new()
	r.name = "Ramp%d" % (root.get_child_count() + 1)
	r.width         = w_axis
	r.length        = l_axis
	r.height_change = aabb.size.y
	r.clearance     = ramp_cl.value
	r.landing_depth_low  = ramp_landing_low.value
	r.landing_depth_high = ramp_landing_high.value
	r.high_end      = _standalone_dir

	var footprint: Vector3
	match r.high_end:
		"north", "south": footprint = Vector3(r.width, r.height_change + r.clearance, r.length)
		"east",  "west":  footprint = Vector3(r.length, r.height_change + r.clearance, r.width)

	var pos := Vector3(
		aabb.position.x + aabb.size.x / 2.0,
		aabb.position.y,
		aabb.position.z + aabb.size.z / 2.0)

	var conflict: String = dock.scene_query.first_overlap(pos, _ramp_footprint(footprint), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say("Cannot place ramp: overlaps with %s. Hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	_apply_surface_settings(r)
	root.add_child(r)
	r.owner = dock.scene_query.edited_root()
	r.position = pos
	r.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	dock._say(("Placed ramp from corners, high end %s. " +
		"Rise %.1fm over %.1fm (%.0f deg).") % \
		[r.high_end, r.height_change, r.length, r.slope_degrees()])

# ---------------------------------------------------------------------------

func _apply_surface_settings(r: Ramp3D) -> void:
	if not build_walls.button_pressed:
		r.wall_sides_enabled = false
	if not build_ceiling.button_pressed:
		r.ceiling_enabled = false

func _ramp_footprint(s: Vector3) -> Vector3:
	if build_walls.button_pressed:
		return s
	return Vector3(s.x, 0.01, s.z)

func _spinbox(min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v; s.max_value = max_v
	s.step = step_v; s.value = default_v
	return s

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
