@tool
extends AcceptDialog

# Reusable polygon editor for tile collision and navigation polygons.
# Construct, configure (mode/tile_size/polygons/announcer), then call
# add_child(dlg); dlg.popup_centered(). Connect polygons_committed to receive
# the array on OK.

signal polygons_committed(polygons: Array)

enum Mode { COLLISION, NAVIGATION }

var editor_mode: int = Mode.COLLISION
var tile_size: Vector2i = Vector2i(16, 16)
var polygons: Array = []  # Array[PackedVector2Array]
var announcer

var _polygon_option: OptionButton
var _polygon_row: HBoxContainer
var _add_polygon_btn: Button
var _remove_polygon_btn: Button
var _point_list: ItemList
var _x_spin: SpinBox
var _y_spin: SpinBox
var _update_btn: Button
var _add_point_btn: Button
var _remove_point_btn: Button
var _rect_preset_btn: Button
var _active_polygon: int = 0
var _suppress_spin_announce: bool = false


func _ready() -> void:
	if title.is_empty():
		if editor_mode == Mode.NAVIGATION:
			title = "Edit navigation polygon"
		else:
			title = "Edit collision polygons"
	min_size = Vector2(440, 460)
	get_ok_button().text = "Save"
	add_cancel_button("Cancel")

	if polygons.is_empty() and editor_mode == Mode.NAVIGATION:
		polygons = [PackedVector2Array()]

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	_polygon_row = HBoxContainer.new()
	_polygon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_polygon_row)

	var poly_lbl := Label.new()
	poly_lbl.text = "Polygon:"
	poly_lbl.custom_minimum_size = Vector2(70, 0)
	_polygon_row.add_child(poly_lbl)

	_polygon_option = OptionButton.new()
	_polygon_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_polygon_option, "Polygon index",
		"Which polygon on this layer is being edited.")
	_polygon_option.item_selected.connect(_on_polygon_selected)
	_polygon_row.add_child(_polygon_option)

	_add_polygon_btn = Button.new()
	_add_polygon_btn.text = "Add polygon"
	_set_a11y(_add_polygon_btn, "Add polygon",
		"Append a new empty polygon to this layer.")
	_add_polygon_btn.pressed.connect(_on_add_polygon_pressed)
	_polygon_row.add_child(_add_polygon_btn)

	_remove_polygon_btn = Button.new()
	_remove_polygon_btn.text = "Remove polygon"
	_set_a11y(_remove_polygon_btn, "Remove polygon",
		"Remove the currently selected polygon from this layer.")
	_remove_polygon_btn.pressed.connect(_on_remove_polygon_pressed)
	_polygon_row.add_child(_remove_polygon_btn)

	# Navigation mode treats the polygon as a single outline.
	if editor_mode == Mode.NAVIGATION:
		_polygon_row.visible = false

	var preset_row := HBoxContainer.new()
	vb.add_child(preset_row)
	var preset_lbl := Label.new()
	preset_lbl.text = "Preset:"
	preset_lbl.custom_minimum_size = Vector2(70, 0)
	preset_row.add_child(preset_lbl)

	_rect_preset_btn = Button.new()
	_rect_preset_btn.text = "Rectangle (full tile)"
	_set_a11y(_rect_preset_btn, "Rectangle preset",
		"Replace the active polygon with a full-tile rectangle.")
	_rect_preset_btn.pressed.connect(_on_rectangle_preset_pressed)
	preset_row.add_child(_rect_preset_btn)

	var points_lbl := Label.new()
	points_lbl.text = "Points:"
	vb.add_child(points_lbl)

	_point_list = ItemList.new()
	_point_list.custom_minimum_size = Vector2(0, 140)
	_point_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_set_a11y(_point_list, "Polygon points",
		"Points in the active polygon.")
	_point_list.item_selected.connect(_on_point_selected)
	vb.add_child(_point_list)

	var point_btn_row := HBoxContainer.new()
	vb.add_child(point_btn_row)

	_add_point_btn = Button.new()
	_add_point_btn.text = "Add point"
	_set_a11y(_add_point_btn, "Add point",
		"Append a new point at (0, 0) and focus the X field to edit it.")
	_add_point_btn.pressed.connect(_on_add_point_pressed)
	point_btn_row.add_child(_add_point_btn)

	_remove_point_btn = Button.new()
	_remove_point_btn.text = "Remove selected point"
	_set_a11y(_remove_point_btn, "Remove point",
		"Remove the selected point from the active polygon.")
	_remove_point_btn.pressed.connect(_on_remove_point_pressed)
	point_btn_row.add_child(_remove_point_btn)

	var edit_lbl := Label.new()
	edit_lbl.text = "Edit selected point:"
	vb.add_child(edit_lbl)

	var edit_row := HBoxContainer.new()
	vb.add_child(edit_row)

	var x_lbl := Label.new()
	x_lbl.text = "X:"
	edit_row.add_child(x_lbl)

	_x_spin = SpinBox.new()
	_x_spin.min_value = -1024
	_x_spin.max_value = 1024
	_x_spin.step = 1
	_x_spin.allow_greater = true
	_x_spin.allow_lesser = true
	_set_a11y(_x_spin, "Point X",
		"X coordinate of the selected point. Press Enter or click Update to commit.")
	edit_row.add_child(_x_spin)

	var y_lbl := Label.new()
	y_lbl.text = "Y:"
	edit_row.add_child(y_lbl)

	_y_spin = SpinBox.new()
	_y_spin.min_value = -1024
	_y_spin.max_value = 1024
	_y_spin.step = 1
	_y_spin.allow_greater = true
	_y_spin.allow_lesser = true
	_set_a11y(_y_spin, "Point Y",
		"Y coordinate of the selected point. Press Enter or click Update to commit.")
	edit_row.add_child(_y_spin)

	_update_btn = Button.new()
	_update_btn.text = "Update point"
	_set_a11y(_update_btn, "Update point",
		"Write the X and Y values back into the selected point.")
	_update_btn.pressed.connect(_on_update_point_pressed)
	edit_row.add_child(_update_btn)

	confirmed.connect(_on_confirmed)

	_refresh_polygon_option()
	if polygons.size() > 0:
		_active_polygon = 0
		_polygon_option.select(0)
	_refresh_point_list()
	_refresh_edit_row()


func _on_polygon_selected(idx: int) -> void:
	_active_polygon = idx
	_refresh_point_list()
	_refresh_edit_row()
	_announce("Polygon %d selected, %d point(s)." % [idx, _active_points().size()])


func _on_add_polygon_pressed() -> void:
	polygons.append(PackedVector2Array())
	_active_polygon = polygons.size() - 1
	_refresh_polygon_option()
	_polygon_option.select(_active_polygon)
	_refresh_point_list()
	_refresh_edit_row()
	_announce("Added polygon %d." % _active_polygon)


func _on_remove_polygon_pressed() -> void:
	if polygons.is_empty():
		_announce("No polygon to remove.")
		return
	var removed := _active_polygon
	polygons.remove_at(_active_polygon)
	if _active_polygon >= polygons.size():
		_active_polygon = polygons.size() - 1
	_refresh_polygon_option()
	if _active_polygon >= 0:
		_polygon_option.select(_active_polygon)
	_refresh_point_list()
	_refresh_edit_row()
	_announce("Removed polygon %d. %d polygon(s) remaining." % [removed, polygons.size()])


func _on_rectangle_preset_pressed() -> void:
	if polygons.is_empty():
		polygons.append(PackedVector2Array())
		_active_polygon = 0
		_refresh_polygon_option()
		_polygon_option.select(0)
	var hw: float = float(tile_size.x) / 2.0
	var hh: float = float(tile_size.y) / 2.0
	polygons[_active_polygon] = PackedVector2Array([
		Vector2(-hw, -hh),
		Vector2(hw, -hh),
		Vector2(hw, hh),
		Vector2(-hw, hh),
	])
	_refresh_point_list()
	_refresh_edit_row()
	_announce("Set polygon %d to full-tile rectangle." % _active_polygon)


func _on_point_selected(idx: int) -> void:
	_refresh_edit_row()
	var pts := _active_points()
	if idx >= 0 and idx < pts.size():
		var p := pts[idx]
		_announce("Point %d: %s, %s." % [idx, _fmt(p.x), _fmt(p.y)])


func _on_add_point_pressed() -> void:
	if polygons.is_empty():
		polygons.append(PackedVector2Array())
		_active_polygon = 0
		_refresh_polygon_option()
		_polygon_option.select(0)
	var pts := _active_points()
	pts.append(Vector2.ZERO)
	polygons[_active_polygon] = pts
	var new_idx := pts.size() - 1
	_refresh_point_list()
	_point_list.select(new_idx)
	_refresh_edit_row()
	_announce("Added point %d at 0, 0." % new_idx)
	_x_spin.get_line_edit().grab_focus()


func _on_remove_point_pressed() -> void:
	var sel := _point_list.get_selected_items()
	if sel.is_empty():
		_announce("No point selected.")
		return
	var idx: int = sel[0]
	var pts := _active_points()
	if idx < 0 or idx >= pts.size():
		return
	pts.remove_at(idx)
	polygons[_active_polygon] = pts
	_refresh_point_list()
	if pts.size() > 0:
		var new_sel: int = mini(idx, pts.size() - 1)
		_point_list.select(new_sel)
	_refresh_edit_row()
	_announce("Removed point %d. %d point(s) remaining." % [idx, pts.size()])


func _on_update_point_pressed() -> void:
	var sel := _point_list.get_selected_items()
	if sel.is_empty():
		_announce("No point selected.")
		return
	var idx: int = sel[0]
	var pts := _active_points()
	if idx < 0 or idx >= pts.size():
		return
	var new_pt := Vector2(_x_spin.value, _y_spin.value)
	pts[idx] = new_pt
	polygons[_active_polygon] = pts
	_refresh_point_list()
	_point_list.select(idx)
	_announce("Updated point %d to %s, %s." % [idx, _fmt(new_pt.x), _fmt(new_pt.y)])


func _on_confirmed() -> void:
	# Strip empty polygons so callers don't get junk entries.
	var cleaned: Array = []
	for p in polygons:
		if p is PackedVector2Array and (p as PackedVector2Array).size() >= 3:
			cleaned.append(p)
	emit_signal("polygons_committed", cleaned)


# ----- view refresh helpers -----

func _refresh_polygon_option() -> void:
	if _polygon_option == null:
		return
	_polygon_option.clear()
	for i in polygons.size():
		_polygon_option.add_item("Polygon %d (%d pts)" % [i, (polygons[i] as PackedVector2Array).size()])
	if polygons.is_empty():
		_polygon_option.add_item("(no polygons)")
		_polygon_option.disabled = true
	else:
		_polygon_option.disabled = false


func _refresh_point_list() -> void:
	_point_list.clear()
	var pts := _active_points()
	for i in pts.size():
		_point_list.add_item("Point %d: (%s, %s)" % [i, _fmt(pts[i].x), _fmt(pts[i].y)])


func _refresh_edit_row() -> void:
	var sel := _point_list.get_selected_items()
	var pts := _active_points()
	if sel.is_empty() or sel[0] >= pts.size():
		_set_spin_values(0.0, 0.0)
		_x_spin.editable = false
		_y_spin.editable = false
		_update_btn.disabled = true
		return
	var p := pts[sel[0]]
	_set_spin_values(p.x, p.y)
	_x_spin.editable = true
	_y_spin.editable = true
	_update_btn.disabled = false


func _set_spin_values(x: float, y: float) -> void:
	_suppress_spin_announce = true
	_x_spin.value = x
	_y_spin.value = y
	_suppress_spin_announce = false


func _active_points() -> PackedVector2Array:
	if _active_polygon < 0 or _active_polygon >= polygons.size():
		return PackedVector2Array()
	return polygons[_active_polygon] as PackedVector2Array


func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.0001:
		return "%d" % int(roundf(v))
	return "%.2f" % v


func _announce(msg: String) -> void:
	if announcer != null and announcer.has_method(&"speak"):
		announcer.call(&"speak", msg)


func _set_a11y(c: Control, n: String, desc: String = "") -> void:
	if c.has_method(&"set_accessibility_name"):
		c.call(&"set_accessibility_name", n)
	if not desc.is_empty() and c.has_method(&"set_accessibility_description"):
		c.call(&"set_accessibility_description", desc)
