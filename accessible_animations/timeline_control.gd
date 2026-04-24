@tool
extends Control

# Set by dock.gd before add_child().
# Typed as variant so we avoid a circular preload, but all property accesses
# below use explicit type annotations so GDScript can infer dependent types.
var dock
var step: float = 0.1
var current_time: float = 0.0

const VALUE_STEP := 0.1  # base increment for Up/Down on floats


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, 64)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


# Drawing. I have no idea what I'm doing here but I did it for the other plugins as well, so might as well give it a go.

func _draw() -> void:
	var w := size.x
	var h := size.y

	draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.12, 0.12, 1.0), true)
	if has_focus():
		draw_rect(Rect2(0, 0, w, h), Color(0.2, 0.5, 1.0, 0.08), true)

	if dock == null or dock.current_animation == null:
		var font := get_theme_default_font()
		if font:
			draw_string(font, Vector2(8, h * 0.5 + 6), "No animation. Click to focus.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_default_font_size(), Color(0.7, 0.7, 0.7))
		return

	var anim: Animation = dock.current_animation
	var anim_len := maxf(anim.length, 0.001)
	var base_y := h * 0.65

	draw_line(Vector2(0.0, base_y), Vector2(w, base_y), Color(0.4, 0.4, 0.4), 1.0)

	var track: int = dock.current_track
	if track >= 0 and track < anim.get_track_count():
		var kcount := anim.track_get_key_count(track)
		for ki in kcount:
			var t := anim.track_get_key_time(track, ki)
			var x := (t / anim_len) * w
			draw_line(Vector2(x, base_y - 10.0), Vector2(x, base_y + 4.0),
				Color(1.0, 0.8, 0.2), 2.0)

	var cx := (current_time / anim_len) * w
	draw_line(Vector2(cx, 0.0), Vector2(cx, h), Color(1.0, 0.3, 0.3), 2.0)

	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	if font:
		var time_str := "%.3f s" % current_time
		var label_x := clampf(cx + 4.0, 4.0, w - 56.0)
		draw_string(font, Vector2(label_x, 14.0), time_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, 0.9))
		draw_string(font, Vector2(4.0, h - 4.0),
			"Click to focus, then use keyboard",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, Color(0.6, 0.6, 0.6, 0.6))


# Input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		accept_event()
		return
	if not (event is InputEventKey and event.pressed):
		return
	if _handle_key(event as InputEventKey):
		accept_event()


func _handle_key(event: InputEventKey) -> bool:
	var kc := event.keycode
	var shift := event.shift_pressed
	var ctrl := event.ctrl_pressed or event.meta_pressed

	if dock == null or dock.current_animation == null:
		return false

	var anim: Animation = dock.current_animation
	var anim_len := maxf(anim.length, 0.001)

	match kc:
		KEY_LEFT:
			if ctrl:
				_jump_to_keyframe(-1)
			else:
				current_time = maxf(0.0, current_time - step)
				_on_time_changed()
			return true
		KEY_RIGHT:
			if ctrl:
				_jump_to_keyframe(1)
			else:
				current_time = minf(anim_len, current_time + step)
				_on_time_changed()
			return true
		KEY_SPACE:
			_insert_keyframe_dialog()
			return true
		KEY_DELETE, KEY_BACKSPACE:
			_delete_keyframe_at_current_time()
			return true
		KEY_UP:
			_adjust_value(1.0, shift, ctrl)
			return true
		KEY_DOWN:
			_adjust_value(-1.0, shift, ctrl)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			_edit_value_dialog()
			return true
	return false


func _on_time_changed() -> void:
	queue_redraw()
	dock._update_info_label()
	dock._say(_announce_time())
	var old: bool = dock._ignore_signals
	dock._ignore_signals = true
	dock._seek_spin.value = current_time
	dock._ignore_signals = old


func _announce_time() -> String:
	var base := "Time: %.3f s." % current_time
	if dock.current_track >= 0:
		var cur_anim: Animation = dock.current_animation
		var cur_track: int = dock.current_track
		var vi := cur_anim.track_find_key(cur_track, current_time, Animation.FIND_MODE_APPROX)
		if vi >= 0:
			return base + " Keyframe: " + dock._get_value_string_at(cur_track, current_time)
	return base


# Jump to prev/next keyframe

func _jump_to_keyframe(direction: int) -> void:
	if dock.current_track < 0:
		dock._say("No track selected.")
		return
	var anim: Animation = dock.current_animation
	var track: int = dock.current_track
	var kcount := anim.track_get_key_count(track)
	if kcount == 0:
		dock._say("Track has no keyframes.")
		return

	var times: Array[float] = []
	for ki in kcount:
		times.append(anim.track_get_key_time(track, ki))
	times.sort()

	const EPS := 0.0001
	if direction > 0:
		for t: float in times:
			if t > current_time + EPS:
				current_time = t
				_on_time_changed()
				return
		dock._say("No keyframe after current time.")
	else:
		var found := -1.0
		for t: float in times:
			if t < current_time - EPS:
				found = t
		if found >= 0.0:
			current_time = found
			_on_time_changed()
		else:
			dock._say("No keyframe before current time.")


# Delete keyframe

func _delete_keyframe_at_current_time() -> void:
	if dock.current_track < 0:
		dock._say("No track selected.")
		return
	var anim: Animation = dock.current_animation
	var track: int = dock.current_track
	var key_idx := anim.track_find_key(track, current_time, Animation.FIND_MODE_APPROX)
	if key_idx < 0:
		dock._say("No keyframe at current time.")
		return

	var actual_time := anim.track_get_key_time(track, key_idx)
	var val: Variant = _get_track_key_value(anim, track, key_idx)
	var trans := anim.track_get_key_transition(track, key_idx)

	if dock.editor_undo_redo != null:
		dock.editor_undo_redo.create_action("Remove keyframe")
		dock.editor_undo_redo.add_do_method(anim, &"track_remove_key", track, key_idx)
		dock.editor_undo_redo.add_undo_method(anim, &"track_insert_key", track, actual_time, val, trans)
		dock.editor_undo_redo.commit_action()
	else:
		anim.track_remove_key(track, key_idx)

	queue_redraw()
	dock._refresh_tracks()
	dock._update_info_label()
	dock._say("Keyframe deleted at %.3f s." % actual_time)


# Adjust numeric value with Up/Down

func _adjust_value(sign: float, shift: bool, ctrl: bool) -> void:
	if dock.current_track < 0:
		return
	var anim: Animation = dock.current_animation
	var track: int = dock.current_track
	var key_idx := anim.track_find_key(track, current_time, Animation.FIND_MODE_APPROX)
	if key_idx < 0:
		dock._say("No keyframe at current time.")
		return

	var ttype := anim.track_get_type(track)
	var inc := VALUE_STEP
	if ctrl: inc *= 0.1
	elif shift: inc *= 10.0
	inc *= sign

	match ttype:
		Animation.TYPE_BEZIER:
			var old_v := anim.bezier_track_get_key_value(track, key_idx)
			var new_v := old_v + inc
			if dock.editor_undo_redo != null:
				dock.editor_undo_redo.create_action("Adjust bezier value")
				dock.editor_undo_redo.add_do_method(anim, &"bezier_track_set_key_value", track, key_idx, new_v)
				dock.editor_undo_redo.add_undo_method(anim, &"bezier_track_set_key_value", track, key_idx, old_v)
				dock.editor_undo_redo.commit_action()
			else:
				anim.bezier_track_set_key_value(track, key_idx, new_v)
			dock._update_info_label()
			dock._say("Value: %.4f" % new_v)

		Animation.TYPE_BLEND_SHAPE:
			var old_v: float = anim.track_get_key_value(track, key_idx)
			var new_v: float = old_v + inc
			var t := anim.track_get_key_time(track, key_idx)
			var trans := anim.track_get_key_transition(track, key_idx)
			if dock.editor_undo_redo != null:
				dock.editor_undo_redo.create_action("Adjust blend shape value")
				dock.editor_undo_redo.add_do_method(anim, &"track_remove_key", track, key_idx)
				dock.editor_undo_redo.add_do_method(anim, &"track_insert_key", track, t, new_v, trans)
				dock.editor_undo_redo.add_undo_method(anim, &"track_remove_key_at_time", track, t)
				dock.editor_undo_redo.add_undo_method(anim, &"track_insert_key", track, t, old_v, trans)
				dock.editor_undo_redo.commit_action()
			else:
				anim.track_remove_key(track, key_idx)
				anim.track_insert_key(track, t, new_v, trans)
			queue_redraw()
			dock._update_info_label()
			dock._say("Value: %.4f" % new_v)

		Animation.TYPE_VALUE:
			var old_v: Variant = anim.track_get_key_value(track, key_idx)
			var new_v: Variant = _increment_variant(old_v, inc, sign)
			if new_v == null:
				dock._say("Use Enter to edit this value type.")
				return
			if dock.editor_undo_redo != null:
				dock.editor_undo_redo.create_action("Adjust keyframe value")
				dock.editor_undo_redo.add_do_method(anim, &"track_set_key_value", track, key_idx, new_v)
				dock.editor_undo_redo.add_undo_method(anim, &"track_set_key_value", track, key_idx, old_v)
				dock.editor_undo_redo.commit_action()
			else:
				anim.track_set_key_value(track, key_idx, new_v)
			dock._update_info_label()
			dock._say("Value: %s" % str(new_v))

		_:
			dock._say("Use Enter to edit this track type.")


func _increment_variant(val: Variant, inc: float, sign: float) -> Variant:
	match typeof(val):
		TYPE_FLOAT: return val + inc
		TYPE_INT:   return val + int(sign)
		TYPE_BOOL:  return not bool(val)
	return null


# Edit value via dialog

func _edit_value_dialog() -> void:
	if dock.current_track < 0:
		dock._say("No track selected.")
		return
	var anim: Animation = dock.current_animation
	var track: int = dock.current_track
	var key_idx := anim.track_find_key(track, current_time, Animation.FIND_MODE_APPROX)
	if key_idx < 0:
		dock._say("No keyframe at current time. Press Space to insert one.")
		return
	_open_value_editor(anim, track, key_idx, false)


# Insert keyframe via dialog

func _insert_keyframe_dialog() -> void:
	if dock.current_track < 0:
		dock._say("No track selected.")
		return
	var anim: Animation = dock.current_animation
	var track: int = dock.current_track
	var existing := anim.track_find_key(track, current_time, Animation.FIND_MODE_APPROX)
	if existing >= 0:
		dock._say("Keyframe already exists. Editing it.")
		_open_value_editor(anim, track, existing, false)
		return
	_open_value_editor(anim, track, -1, true)


# Generic value editor dialog

func _open_value_editor(anim: Animation, track: int, key_idx: int, is_insert: bool) -> void:
	var ttype := anim.track_get_type(track)
	var title := "Insert Keyframe" if is_insert else "Edit Keyframe"

	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.min_size = Vector2(320, 160)
	var vb := VBoxContainer.new()
	dlg.add_child(vb)
	dlg.get_ok_button().text = "Insert" if is_insert else "Set"

	match ttype:
		Animation.TYPE_VALUE:
			_build_value_track_editor(vb, dlg, anim, track, key_idx, is_insert)
			return  # _build_value_track_editor owns dialog lifecycle

		Animation.TYPE_BEZIER:
			var cur := 0.0
			if key_idx >= 0:
				cur = anim.bezier_track_get_key_value(track, key_idx)
			var row := HBoxContainer.new()
			vb.add_child(row)
			row.add_child(dock._lbl("Value:"))
			var field := LineEdit.new()
			field.text = str(cur)
			dock._set_a11y(field, "Bezier value")
			row.add_child(field)
			dock.add_child(dlg)
			dlg.popup_centered()
			field.grab_focus()
			dlg.confirmed.connect(func() -> void:
				var new_v := float(field.text)
				dlg.queue_free()
				if is_insert:
					_commit_insert(anim, track, new_v)
				else:
					_commit_bezier_value(anim, track, key_idx, new_v)
			)

		Animation.TYPE_BLEND_SHAPE:
			var cur := 0.0
			if key_idx >= 0:
				cur = anim.track_get_key_value(track, key_idx)
			var row := HBoxContainer.new()
			vb.add_child(row)
			row.add_child(dock._lbl("Amount (0.0-1.0):"))
			var field := LineEdit.new()
			field.text = str(cur)
			dock._set_a11y(field, "Blend shape amount", "0.0 = no blend, 1.0 = full blend.")
			row.add_child(field)
			dock.add_child(dlg)
			dlg.popup_centered()
			field.grab_focus()
			dlg.confirmed.connect(func() -> void:
				var new_v := float(field.text)
				dlg.queue_free()
				_commit_insert(anim, track, new_v)
			)

		Animation.TYPE_POSITION_3D:
			var cur := Vector3.ZERO
			if key_idx >= 0:
				cur = anim.track_get_key_value(track, key_idx)
			var fields := _vec3_dialog(vb, cur, "X", "Y", "Z")
			dock.add_child(dlg)
			dlg.popup_centered()
			dlg.confirmed.connect(func() -> void:
				var v := fields.call()
				dlg.queue_free()
				_commit_insert(anim, track, v)
			)

		Animation.TYPE_ROTATION_3D:
			var cur := Quaternion.IDENTITY
			if key_idx >= 0:
				cur = anim.track_get_key_value(track, key_idx)
			var e := cur.get_euler()
			var fields := _vec3_dialog(vb,
				Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)),
				"X°", "Y°", "Z°")
			dock.add_child(dlg)
			dlg.popup_centered()
			dlg.confirmed.connect(func() -> void:
				var ev: Vector3 = fields.call()
				dlg.queue_free()
				_commit_insert(anim, track,
					Quaternion.from_euler(Vector3(
						deg_to_rad(ev.x), deg_to_rad(ev.y), deg_to_rad(ev.z))))
			)

		Animation.TYPE_SCALE_3D:
			var cur := Vector3.ONE
			if key_idx >= 0:
				cur = anim.track_get_key_value(track, key_idx)
			var fields := _vec3_dialog(vb, cur, "X", "Y", "Z")
			dock.add_child(dlg)
			dlg.popup_centered()
			dlg.confirmed.connect(func() -> void:
				var v: Vector3 = fields.call()
				dlg.queue_free()
				_commit_insert(anim, track, v)
			)

		Animation.TYPE_METHOD:
			var cur_name := &""
			var cur_args: Array = []
			if key_idx >= 0:
				cur_name = anim.method_track_get_name(track, key_idx)
				cur_args = anim.method_track_get_params(track, key_idx)
			vb.add_child(dock._lbl("Method name:"))
			var name_field := LineEdit.new()
			name_field.text = str(cur_name)
			dock._set_a11y(name_field, "Method name")
			vb.add_child(name_field)
			vb.add_child(dock._lbl("Arguments (one per line):"))
			var args_edit := TextEdit.new()
			args_edit.custom_minimum_size = Vector2(0, 60)
			args_edit.text = "\n".join(cur_args.map(func(a: Variant) -> String: return str(a)))
			dock._set_a11y(args_edit, "Method arguments", "One argument per line.")
			vb.add_child(args_edit)
			dlg.min_size = Vector2(320, 240)
			dock.add_child(dlg)
			dlg.popup_centered()
			name_field.grab_focus()
			dlg.confirmed.connect(func() -> void:
				var mname: StringName = name_field.text.strip_edges()
				var lines := args_edit.text.split("\n", false)
				var params: Array = []
				for line: String in lines:
					var s := line.strip_edges()
					if not s.is_empty():
						params.append(s)
				dlg.queue_free()
				_commit_insert(anim, track, {"method": mname, "args": params})
			)

		Animation.TYPE_AUDIO:
			var cur_path := ""
			if key_idx >= 0:
				var stream := anim.audio_track_get_key_stream(track, key_idx)
				if stream != null:
					cur_path = stream.resource_path
			vb.add_child(dock._lbl("Audio stream path (res://...):"))
			var field := LineEdit.new()
			field.text = cur_path
			dock._set_a11y(field, "Audio stream path", "Full resource path to the AudioStream.")
			vb.add_child(field)
			dock.add_child(dlg)
			dlg.popup_centered()
			field.grab_focus()
			dlg.confirmed.connect(func() -> void:
				var path := field.text.strip_edges()
				dlg.queue_free()
				var stream: AudioStream = null
				if not path.is_empty() and ResourceLoader.exists(path):
					stream = load(path)
				_commit_insert(anim, track, {"stream": stream, "start_offset": 0.0, "end_offset": 0.0})
			)

		Animation.TYPE_ANIMATION:
			var cur_aname := &""
			if key_idx >= 0:
				cur_aname = anim.animation_track_get_key_animation(track, key_idx)
			vb.add_child(dock._lbl("Animation name:"))
			var field := LineEdit.new()
			field.text = str(cur_aname)
			dock._set_a11y(field, "Animation name")
			vb.add_child(field)
			dock.add_child(dlg)
			dlg.popup_centered()
			field.grab_focus()
			dlg.confirmed.connect(func() -> void:
				var anim_name: StringName = field.text.strip_edges()
				dlg.queue_free()
				_commit_insert(anim, track, anim_name)
			)

	dlg.canceled.connect(func() -> void: dlg.queue_free())


# TYPE_VALUE has many subtypes; build dynamically from the existing key's value.
func _build_value_track_editor(vb: VBoxContainer, dlg: AcceptDialog,
		anim: Animation, track: int, key_idx: int, is_insert: bool) -> void:
	var cur_val: Variant = null
	if key_idx >= 0:
		cur_val = anim.track_get_key_value(track, key_idx)
	elif anim.track_get_key_count(track) > 0:
		cur_val = anim.track_get_key_value(track, 0)

	if cur_val is bool:
		var opt := OptionButton.new()
		opt.add_item("false"); opt.add_item("true")
		if bool(cur_val): opt.select(1)
		dock._set_a11y(opt, "Boolean value")
		vb.add_child(opt)
		dock.add_child(dlg); dlg.popup_centered(); opt.grab_focus()
		dlg.confirmed.connect(func() -> void:
			dlg.queue_free()
			_commit_value(anim, track, key_idx, bool(opt.selected), is_insert))
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		return

	if cur_val is Vector2:
		var fields := _vec2_dialog(vb, cur_val)
		dock.add_child(dlg); dlg.popup_centered()
		dlg.confirmed.connect(func() -> void:
			dlg.queue_free()
			_commit_value(anim, track, key_idx, fields.call(), is_insert))
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		return

	if cur_val is Vector3:
		var fields := _vec3_dialog(vb, cur_val, "X", "Y", "Z")
		dock.add_child(dlg); dlg.popup_centered()
		dlg.confirmed.connect(func() -> void:
			dlg.queue_free()
			_commit_value(anim, track, key_idx, fields.call(), is_insert))
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		return

	if cur_val is Color:
		var cv := cur_val as Color
		var fr := _spin_field(vb, "R:", cv.r, 0.0, 1.0, 0.001)
		var fg := _spin_field(vb, "G:", cv.g, 0.0, 1.0, 0.001)
		var fb := _spin_field(vb, "B:", cv.b, 0.0, 1.0, 0.001)
		var fa := _spin_field(vb, "A:", cv.a, 0.0, 1.0, 0.001)
		dock.add_child(dlg); dlg.popup_centered()
		dlg.confirmed.connect(func() -> void:
			dlg.queue_free()
			_commit_value(anim, track, key_idx, Color(fr.value, fg.value, fb.value, fa.value), is_insert))
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		return

	# Generic: float, int, String, or unknown
	var field := LineEdit.new()
	field.text = str(cur_val) if cur_val != null else "0"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock._set_a11y(field, "Value", "Enter the keyframe value.")
	vb.add_child(field)
	dock.add_child(dlg); dlg.popup_centered(); field.grab_focus()
	dlg.confirmed.connect(func() -> void:
		var raw := field.text.strip_edges()
		dlg.queue_free()
		var parsed: Variant
		if cur_val is float or cur_val == null:
			parsed = float(raw)
		elif cur_val is int:
			parsed = int(raw)
		else:
			parsed = raw
		_commit_value(anim, track, key_idx, parsed, is_insert)
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())


# Commit helpers

func _commit_insert(anim: Animation, track: int, value: Variant) -> void:
	if dock.editor_undo_redo != null:
		dock.editor_undo_redo.create_action("Insert keyframe")
		dock.editor_undo_redo.add_do_method(anim, &"track_insert_key", track, current_time, value)
		dock.editor_undo_redo.add_undo_method(anim, &"track_remove_key_at_time", track, current_time)
		dock.editor_undo_redo.commit_action()
	else:
		anim.track_insert_key(track, current_time, value)
	queue_redraw()
	dock._refresh_tracks()
	dock._update_info_label()
	dock._say("Keyframe inserted at %.3f s." % current_time)


func _commit_value(anim: Animation, track: int, key_idx: int,
		value: Variant, is_insert: bool) -> void:
	if is_insert:
		_commit_insert(anim, track, value)
		return
	var old_v: Variant = anim.track_get_key_value(track, key_idx)
	if dock.editor_undo_redo != null:
		dock.editor_undo_redo.create_action("Set keyframe value")
		dock.editor_undo_redo.add_do_method(anim, &"track_set_key_value", track, key_idx, value)
		dock.editor_undo_redo.add_undo_method(anim, &"track_set_key_value", track, key_idx, old_v)
		dock.editor_undo_redo.commit_action()
	else:
		anim.track_set_key_value(track, key_idx, value)
	queue_redraw()
	dock._update_info_label()
	dock._say("Value set to: %s" % str(value))


func _commit_bezier_value(anim: Animation, track: int, key_idx: int, value: float) -> void:
	var old_v := anim.bezier_track_get_key_value(track, key_idx)
	if dock.editor_undo_redo != null:
		dock.editor_undo_redo.create_action("Set bezier value")
		dock.editor_undo_redo.add_do_method(anim, &"bezier_track_set_key_value", track, key_idx, value)
		dock.editor_undo_redo.add_undo_method(anim, &"bezier_track_set_key_value", track, key_idx, old_v)
		dock.editor_undo_redo.commit_action()
	else:
		anim.bezier_track_set_key_value(track, key_idx, value)
	queue_redraw()
	dock._update_info_label()
	dock._say("Value set to: %.4f" % value)


# Dialog field helpers

func _vec2_dialog(vb: VBoxContainer, cur: Vector2) -> Callable:
	var fx := _spin_field(vb, "X:", cur.x, -1e9, 1e9, 0.001)
	var fy := _spin_field(vb, "Y:", cur.y, -1e9, 1e9, 0.001)
	return func() -> Vector2: return Vector2(fx.value, fy.value)


func _vec3_dialog(vb: VBoxContainer, cur: Vector3,
		xlabel: String, ylabel: String, zlabel: String) -> Callable:
	var fx := _spin_field(vb, xlabel + ":", cur.x, -1e9, 1e9, 0.001)
	var fy := _spin_field(vb, ylabel + ":", cur.y, -1e9, 1e9, 0.001)
	var fz := _spin_field(vb, zlabel + ":", cur.z, -1e9, 1e9, 0.001)
	return func() -> Vector3: return Vector3(fx.value, fy.value, fz.value)


func _spin_field(parent: Control, label_text: String,
		init: float, lo: float, hi: float, step_val: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	row.add_child(lbl)
	var sp := SpinBox.new()
	sp.min_value = lo; sp.max_value = hi; sp.step = step_val
	sp.value = init; sp.allow_greater = true; sp.allow_lesser = true
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock._set_a11y(sp, label_text.rstrip(":"))
	row.add_child(sp)
	return sp


# Helper: read key value for any track type

func _get_track_key_value(anim: Animation, track: int, key_idx: int) -> Variant:
	return anim.track_get_key_value(track, key_idx)
