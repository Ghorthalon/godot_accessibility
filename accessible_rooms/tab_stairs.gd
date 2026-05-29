@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var stair_w: SpinBox
var stair_hc: SpinBox
var stair_len: SpinBox
var stair_cl: SpinBox
var stair_steps: SpinBox
var stair_landing_low: SpinBox
var stair_landing_high: SpinBox
var _standalone_dir: String = "north"
var build_risers: CheckBox

func _ready() -> void:
	var rl := Label.new(); rl.text = "Staircase size (m):"
	add_child(rl)

	stair_w            = _spinbox(0.5,   50.0,  0.5, 2.0)
	stair_hc           = _spinbox(0.1,   20.0,  0.1, 1.0)
	stair_len          = _spinbox(0.5,  100.0,  0.5, 4.0)
	stair_cl           = _spinbox(1.0,   10.0,  0.1, 2.4)
	stair_steps        = _spinbox(0.0,  200.0,  1.0, 0.0)
	stair_landing_low  = _spinbox(0.0,   10.0,  0.1, 0.5)
	stair_landing_high = _spinbox(0.0,   10.0,  0.1, 0.5)

	var row := HBoxContainer.new()
	for pair in [["W:", stair_w], ["Rise:", stair_hc], ["Len:", stair_len],
			["Clear:", stair_cl], ["Steps (0=auto):", stair_steps]]:
		var lbl := Label.new(); lbl.text = pair[0]
		row.add_child(lbl); row.add_child(pair[1])
	add_child(row)

	var landing_row := HBoxContainer.new()
	for pair in [["Land Low:", stair_landing_low], ["Land High:", stair_landing_high]]:
		var lbl := Label.new(); lbl.text = pair[0]
		landing_row.add_child(lbl); landing_row.add_child(pair[1])
	add_child(landing_row)

	build_risers = CheckBox.new()
	build_risers.text = "Build risers"
	build_risers.button_pressed = true
	add_child(build_risers)

	add_child(HSeparator.new())
	var dir_lbl := Label.new(); dir_lbl.text = "Staircase high end:"
	add_child(dir_lbl)
	var dir_btn := OptionButton.new()
	for d in ["north", "south", "east", "west"]:
		dir_btn.add_item(d)
	dir_btn.item_selected.connect(func(idx: int) -> void:
		_standalone_dir = ["north", "south", "east", "west"][idx])
	add_child(dir_btn)

	add_child(HSeparator.new())
	var inside_lbl := Label.new(); inside_lbl.text = "Place inside selected room:"
	add_child(inside_lbl)
	_btn("Place staircase in current room at cursor", _place_in_room_at_cursor)
	_btn("Place staircase in current room from corners", _place_in_room_from_corners)

	add_child(HSeparator.new())
	var standalone_lbl := Label.new(); standalone_lbl.text = "Place standalone (no parent room):"
	add_child(standalone_lbl)
	_btn("New standalone staircase at cursor", _new_standalone_stairs)
	_btn("Place standalone staircase from corners", _place_stairs_from_corners)

	add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = ("Workflow: (1) Build a room. (2) Select it. (3) Place a staircase inside.\n" +
		"If the stair's clearance (rise + clearance value) exceeds the room ceiling, " +
		"the room auto-cuts a hole in its ceiling over the slope + high landing.\n" +
		"For a connecting upper room: place a second room above with floor aligned to " +
		"the stair top, then punch a matching hole in its floor.\n" +
		"Len is the TOTAL footprint (low landing + slope + high landing). " +
		"Clearance must exceed the player capsule height (default 2.0m), use 2.6m+ for safety.\n" +
		"Steps (0=auto) divides the rise/slope_length into equal steps using ~18 cm ideal step height.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

func _build_stair_node() -> Stairs3D:
	var s := Stairs3D.new()
	s.width         = stair_w.value
	s.height_change = stair_hc.value
	s.length        = stair_len.value
	s.clearance     = stair_cl.value
	s.step_count    = int(stair_steps.value)
	s.landing_depth_low  = stair_landing_low.value
	s.landing_depth_high = stair_landing_high.value
	s.high_end      = _standalone_dir
	s.risers_enabled = build_risers.button_pressed
	return s

func _place_in_room_at_cursor() -> void:
	if not dock.current_entity is Room3D:
		dock._say_err("No room selected. Select a Room3D first."); return
	var room := dock.current_entity as Room3D
	var s := _build_stair_node()
	s.floor_thickness = room.wall_floor.thickness if room.wall_floor else 0.0
	s.name = "%s_stairs%d" % [room.name, room.get_child_count() + 1]
	room.add_child(s)
	s.owner = dock.scene_query.edited_root()
	s.position = room.to_local(dock.cursor)
	s.rebuild()
	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()
	var n := s._effective_step_count()
	dock._say_ok(("Placed staircase in %s at cursor, high end %s. " +
		"%d steps, %.0fcm rise / %.0fcm deep each. " +
		"Rises %.1fm over %.1fm (%.0f deg).") % \
		[room.name, s.high_end, n,
		 s.step_height() * 100.0, s.step_depth() * 100.0,
		 s.height_change, s.length, s.slope_degrees()])

func _place_in_room_from_corners() -> void:
	if not dock.current_entity is Room3D:
		dock._say_err("No room selected. Select a Room3D first."); return
	var room := dock.current_entity as Room3D
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

	var s := _build_stair_node()
	s.floor_thickness = room.wall_floor.thickness if room.wall_floor else 0.0
	s.width  = w_axis
	s.length = l_axis
	s.height_change = aabb.size.y
	s.name = "%s_stairs%d" % [room.name, room.get_child_count() + 1]

	var world_pos := Vector3(
		aabb.position.x + aabb.size.x / 2.0,
		aabb.position.y,
		aabb.position.z + aabb.size.z / 2.0)
	room.add_child(s)
	s.owner = dock.scene_query.edited_root()
	s.position = room.to_local(world_pos)
	s.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()
	var n := s._effective_step_count()
	dock._say_ok(("Placed staircase in %s from corners, high end %s. " +
		"%d steps, %.0fcm rise / %.0fcm deep each. " +
		"Rises %.1fm over %.1fm (%.0f deg).") % \
		[room.name, s.high_end, n,
		 s.step_height() * 100.0, s.step_depth() * 100.0,
		 s.height_change, s.length, s.slope_degrees()])

func _new_standalone_stairs() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return

	var s := _build_stair_node()
	s.name = "Stairs%d" % (root.get_child_count() + 1)

	var footprint: Vector3
	match s.high_end:
		"north", "south": footprint = Vector3(s.width, s.height_change + s.clearance, s.length)
		"east",  "west":  footprint = Vector3(s.length, s.height_change + s.clearance, s.width)

	var conflict: String = dock.scene_query.first_overlap(dock.cursor, footprint, root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say("Cannot place staircase: overlaps with %s. Move cursor clear first, or hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	root.add_child(s)
	s.owner = dock.scene_query.edited_root()
	s.global_position = dock.cursor
	s.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	var n := s._effective_step_count()
	dock._say(("Placed standalone staircase at cursor, high end %s. " +
		"%d steps, %.0fcm rise / %.0fcm deep each. " +
		"Rises %.1fm over %.1fm (%.0f deg).") % \
		[s.high_end, n,
		 s.step_height() * 100.0, s.step_depth() * 100.0,
		 s.height_change, s.length, s.slope_degrees()])

func _place_stairs_from_corners() -> void:
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

	var s := _build_stair_node()
	s.width  = w_axis
	s.length = l_axis
	s.height_change = aabb.size.y
	s.name = "Stairs%d" % (root.get_child_count() + 1)

	var footprint: Vector3
	match s.high_end:
		"north", "south": footprint = Vector3(s.width, s.height_change + s.clearance, s.length)
		"east",  "west":  footprint = Vector3(s.length, s.height_change + s.clearance, s.width)

	var pos := Vector3(
		aabb.position.x + aabb.size.x / 2.0,
		aabb.position.y,
		aabb.position.z + aabb.size.z / 2.0)

	var conflict: String = dock.scene_query.first_overlap(pos, footprint, root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say("Cannot place staircase: overlaps with %s. Hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	root.add_child(s)
	s.owner = dock.scene_query.edited_root()
	s.global_position = pos
	s.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	var n := s._effective_step_count()
	dock._say(("Placed staircase from corners, high end %s. " +
		"%d steps, %.0fcm rise / %.0fcm deep each. " +
		"Rises %.1fm over %.1fm (%.0f deg).") % \
		[s.high_end, n,
		 s.step_height() * 100.0, s.step_depth() * 100.0,
		 s.height_change, s.length, s.slope_degrees()])

func _spinbox(min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v; s.max_value = max_v
	s.step = step_v; s.value = default_v
	return s

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
