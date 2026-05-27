@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var ramp_w: SpinBox
var ramp_len: SpinBox
var ramp_hc: SpinBox
var ramp_cl: SpinBox
var ramp_landing_low: SpinBox
var ramp_landing_high: SpinBox
var _standalone_dir: String = "north"

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

	add_child(HSeparator.new())
	var dir_lbl := Label.new(); dir_lbl.text = "Ramp high end:"
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
	_btn("Place ramp in current room at cursor", _place_in_room_at_cursor)
	_btn("Place ramp in current room from corners", _place_in_room_from_corners)

	add_child(HSeparator.new())
	var standalone_lbl := Label.new(); standalone_lbl.text = "Place standalone (no parent room):"
	add_child(standalone_lbl)
	_btn("New standalone ramp at cursor", _new_standalone_ramp)
	_btn("Place standalone ramp from corners", _place_ramps_from_corners)

	add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = ("Workflow: (1) Build a room. (2) Select it. (3) Place a ramp inside.\n" +
		"If the ramp's clearance (rise + clearance value) exceeds the room ceiling, " +
		"the room auto-cuts a hole in its ceiling over the slope + high landing.\n" +
		"For a connecting upper room: place a second room above with floor aligned to " +
		"the ramp top, then punch a matching hole in its floor.\n" +
		"Clearance must exceed the player capsule height (default 2.0m), use 2.6m+ for safety.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

func _build_ramp_node() -> Ramp3D:
	var r := Ramp3D.new()
	r.width         = ramp_w.value
	r.length        = ramp_len.value
	r.height_change = ramp_hc.value
	r.clearance     = ramp_cl.value
	r.landing_depth_low  = ramp_landing_low.value
	r.landing_depth_high = ramp_landing_high.value
	r.high_end      = _standalone_dir
	return r

func _place_in_room_at_cursor() -> void:
	if not dock.current_entity is Room3D:
		dock._say_err("No room selected. Select a Room3D first."); return
	var room := dock.current_entity as Room3D
	var r := _build_ramp_node()
	r.floor_thickness = room.wall_floor.thickness if room.wall_floor else 0.0
	r.name = "%s_ramp%d" % [room.name, room.get_child_count() + 1]
	room.add_child(r)
	r.owner = dock.scene_query.edited_root()
	r.position = room.to_local(dock.cursor)
	r.rebuild()
	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()
	dock._say_ok(("Placed ramp in %s at cursor, high end %s. " +
		"Rise %.1fm over %.1fm (%.0f deg).") % \
		[room.name, r.high_end, r.height_change, r.length, r.slope_degrees()])

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

	var r := _build_ramp_node()
	r.floor_thickness = room.wall_floor.thickness if room.wall_floor else 0.0
	r.width  = w_axis
	r.length = l_axis
	r.height_change = aabb.size.y
	r.name = "%s_ramp%d" % [room.name, room.get_child_count() + 1]

	var world_pos := Vector3(
		aabb.position.x + aabb.size.x / 2.0,
		aabb.position.y,
		aabb.position.z + aabb.size.z / 2.0)
	room.add_child(r)
	r.owner = dock.scene_query.edited_root()
	r.position = room.to_local(world_pos)
	r.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()
	dock._say_ok(("Placed ramp in %s from corners, high end %s. " +
		"Rise %.1fm over %.1fm (%.0f deg).") % \
		[room.name, r.high_end, r.height_change, r.length, r.slope_degrees()])

func _new_standalone_ramp() -> void:
	var root: Node = dock.scene_query.placement_parent()
	if root == null: dock._say("No scene open."); return

	var r := _build_ramp_node()
	r.name = "Ramp%d" % (root.get_child_count() + 1)

	var footprint: Vector3
	match r.high_end:
		"north", "south": footprint = Vector3(r.width, r.height_change + r.clearance, r.length)
		"east",  "west":  footprint = Vector3(r.length, r.height_change + r.clearance, r.width)

	var conflict: String = dock.scene_query.first_overlap(dock.cursor, footprint, root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say("Cannot place ramp: overlaps with %s. Move cursor clear first, or hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	root.add_child(r)
	r.owner = dock.scene_query.edited_root()
	r.position = dock.cursor
	r.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	dock._say(("Placed standalone ramp at cursor, high end %s. " +
		"Rise %.1fm over %.1fm (%.0f deg).") % \
		[r.high_end, r.height_change, r.length, r.slope_degrees()])

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

	var r := _build_ramp_node()
	r.width  = w_axis
	r.length = l_axis
	r.height_change = aabb.size.y
	r.name = "Ramp%d" % (root.get_child_count() + 1)

	var footprint: Vector3
	match r.high_end:
		"north", "south": footprint = Vector3(r.width, r.height_change + r.clearance, r.length)
		"east",  "west":  footprint = Vector3(r.length, r.height_change + r.clearance, r.width)

	var pos := Vector3(
		aabb.position.x + aabb.size.x / 2.0,
		aabb.position.y,
		aabb.position.z + aabb.size.z / 2.0)

	var conflict: String = dock.scene_query.first_overlap(pos, footprint, root)
	if conflict != "" and not Input.is_key_pressed(KEY_SHIFT):
		dock._say("Cannot place ramp: overlaps with %s. Hold Shift to force." % conflict)
		return
	elif conflict != "":
		dock._say("Warning: overlaps with %s, placing anyway (Shift held)." % conflict)

	root.add_child(r)
	r.owner = dock.scene_query.edited_root()
	r.position = pos
	r.rebuild()

	for tab in get_parent().get_children():
		if tab.has_method("_refresh"): tab._refresh()

	dock._say(("Placed ramp from corners, high end %s. " +
		"Rise %.1fm over %.1fm (%.0f deg).") % \
		[r.high_end, r.height_change, r.length, r.slope_degrees()])

func _spinbox(min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v; s.max_value = max_v
	s.step = step_v; s.value = default_v
	return s

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new(); b.text = label; b.pressed.connect(cb); add_child(b)
