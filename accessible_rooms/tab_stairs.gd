@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var stair_w: SpinBox
var stair_hc: SpinBox
var stair_len: SpinBox
var stair_cl: SpinBox
var stair_steps: SpinBox
var _door_w: float = 1.2
var _door_h: float = 2.5
var _standalone_dir: String = "north"
var build_walls: CheckBox
var build_ceiling: CheckBox
var build_risers: CheckBox

func _ready() -> void:
	var rl := Label.new(); rl.text = "Staircase size (m):"
	add_child(rl)

	stair_w     = _spinbox(0.5,   50.0,  0.5, 2.0)
	stair_hc    = _spinbox(0.1,   20.0,  0.1, 1.0)
	stair_len   = _spinbox(0.5,  100.0,  0.5, 4.0)
	stair_cl    = _spinbox(1.0,   10.0,  0.1, 2.4)
	stair_steps = _spinbox(0.0,  200.0,  1.0, 0.0)

	var row := HBoxContainer.new()
	for pair in [["W:", stair_w], ["Rise:", stair_hc], ["Len:", stair_len],
			["Clear:", stair_cl], ["Steps (0=auto):", stair_steps]]:
		var lbl := Label.new(); lbl.text = pair[0]
		row.add_child(lbl); row.add_child(pair[1])
	add_child(row)

	var surface_row := HBoxContainer.new()
	build_walls = CheckBox.new()
	build_walls.text = "Build walls"
	build_walls.button_pressed = true
	build_ceiling = CheckBox.new()
	build_ceiling.text = "Build ceiling"
	build_ceiling.button_pressed = false
	build_risers = CheckBox.new()
	build_risers.text = "Build risers"
	build_risers.button_pressed = true
	surface_row.add_child(build_walls)
	surface_row.add_child(build_ceiling)
	surface_row.add_child(build_risers)
	add_child(surface_row)

	add_child(HSeparator.new())
	var dl := Label.new(); dl.text = "Connecting doorway (m):"
	add_child(dl)
	var door_w_spin := _spinbox(0.5, 20.0, 0.1, 1.2)
	var door_h_spin := _spinbox(0.5, 20.0, 0.1, 2.5)
	door_w_spin.value_changed.connect(func(v): _door_w = v)
	door_h_spin.value_changed.connect(func(v): _door_h = v)
	var dr := HBoxContainer.new()
	for pair in [["W:", door_w_spin], ["H:", door_h_spin]]:
		var lbl := Label.new(); lbl.text = pair[0]
		dr.add_child(lbl); dr.add_child(pair[1])
	add_child(dr)

	add_child(HSeparator.new())
	var dir_lbl := Label.new(); dir_lbl.text = "Standalone staircase high end:"
	add_child(dir_lbl)
	var dir_btn := OptionButton.new()
	for d in ["north", "south", "east", "west"]:
		dir_btn.add_item(d)
	dir_btn.item_selected.connect(func(idx: int) -> void:
		_standalone_dir = ["north", "south", "east", "west"][idx])
	add_child(dir_btn)
	_btn("New standalone staircase at cursor", _new_standalone_stairs)

	add_child(HSeparator.new())
	for side in ["north", "south", "east", "west"]:
		_btn("Add staircase to %s of current room" % side, _add_stairs.bind(side))

	add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = ("Workflow: (1) Select a room. (2) Add staircase to a side. " +
		"(3) Place the connecting room at the far end, elevated by the Rise amount.\n" +
		"Important: do NOT place the connecting room adjacent first, the staircase needs that gap.\n" +
		"Clearance must exceed the player capsule height (default 2.0 m), use 2.6 m+ for safety.\n" +
		"Steps (0=auto) divides the rise/length into equal steps using ~18 cm ideal step height.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

func _add_stairs(side: String) -> void:
	if not dock.current_entity is Room3D:
		dock._say("No room selected. Select a Room3D first.")
		return
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return
	var room := dock.current_entity as Room3D

	var s := Stairs3D.new()
	s.name = "%s_stairs_%s" % [room.name, side]
	s.width         = stair_w.value
	s.height_change = stair_hc.value
	s.length        = stair_len.value
	s.clearance     = stair_cl.value
	s.step_count    = int(stair_steps.value)
	# HIGH end faces the same direction as the attachment side, stairs rise away from the source room.
	s.high_end = side

	var footprint: Vector3
	match side:
		"north", "south": footprint = Vector3(s.width, s.clearance, s.length)
		"east",  "west":  footprint = Vector3(s.length, s.clearance, s.width)
	var stairs_pos: Vector3 = room.position + room.neighbor_offset(side, footprint)

	var conflict: String = dock.scene_query.first_overlap(stairs_pos, _stairs_footprint(footprint), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say(("Cannot place staircase: %s already occupies the %s footprint. " +
			"Remove or move it first, or hold Shift to force.") % [conflict, side])
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	_apply_surface_settings(s)
	root.add_child(s)
	s.owner = root
	s.position = stairs_pos

	var cv: float = -room.size.y / 2.0 + _door_h / 2.0
	room.add_doorway(side, 0.0, cv, _door_w, _door_h)

	s.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	var n := s._effective_step_count()
	var hi_pos: Vector3 = s.position + s.high_end_room_offset(Vector3(4, 3, 4))
	dock._say(("Added staircase to %s of %s. " +
		"%d steps, %.0fcm rise / %.0fcm deep each. " +
		"Rises %.1fm over %.1fm (%.0f deg). " +
		"Place connecting room elevated %.1fm, centre near %s (varies with room size).") % \
		[side, room.name, n,
		 s.step_height() * 100.0, s.step_depth() * 100.0,
		 s.height_change, s.length, s.slope_degrees(),
		 s.height_change, hi_pos])

func _new_standalone_stairs() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return

	var s := Stairs3D.new()
	s.name = "Stairs%d" % (root.get_child_count() + 1)
	s.width         = stair_w.value
	s.height_change = stair_hc.value
	s.length        = stair_len.value
	s.clearance     = stair_cl.value
	s.step_count    = int(stair_steps.value)
	s.high_end      = _standalone_dir

	var footprint: Vector3
	match s.high_end:
		"north", "south": footprint = Vector3(s.width, s.height_change + s.clearance, s.length)
		"east",  "west":  footprint = Vector3(s.length, s.height_change + s.clearance, s.width)

	var conflict: String = dock.scene_query.first_overlap(dock.cursor, _stairs_footprint(footprint), root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say("Cannot place staircase: overlaps with %s. Move cursor clear first, or hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	_apply_surface_settings(s)
	root.add_child(s)
	s.owner = root
	s.position = dock.cursor
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


func _apply_surface_settings(s: Stairs3D) -> void:
	s.wall_sides_enabled = build_walls.button_pressed
	s.ceiling_enabled    = build_ceiling.button_pressed
	s.risers_enabled     = build_risers.button_pressed

func _stairs_footprint(sz: Vector3) -> Vector3:
	if build_walls.button_pressed:
		return sz
	return Vector3(sz.x, 0.01, sz.z)

func _spinbox(min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v; s.max_value = max_v
	s.step = step_v; s.value = default_v
	return s

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
