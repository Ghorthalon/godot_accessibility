@tool
extends VBoxContainer

const TimelineControlCls := preload("res://addons/accessible_animations/timeline_control.gd")

# Set from plugin.gd before _ready()
var editor_interface: EditorInterface
var editor_undo_redo: EditorUndoRedoManager

# --- Shared working state (read by timeline_control) ---
var current_player: AnimationPlayer = null
var current_animation: Animation = null
var current_animation_name: StringName = &""
var current_track: int = -1

# --- Mode ---
var _in_resource_mode: bool = false

# --- UI ---
var _announce: Label
var _player_label: Label
var _anim_row: HBoxContainer
var _anim_option: OptionButton
var _save_btn: Button
var _length_spin: SpinBox
var _loop_option: OptionButton
var _playback_row: HBoxContainer
var _play_btn: Button
var _stop_btn: Button
var _seek_spin: SpinBox
var _track_list: ItemList
var _track_settings_row: HBoxContainer
var _update_mode_option: OptionButton
var _interp_option: OptionButton
var _step_spin: SpinBox
var _timeline: Control
var _info_label: Label

var _ignore_signals: bool = false

const TRACK_TYPE_NAMES: Dictionary = {
	Animation.TYPE_VALUE: "VALUE",
	Animation.TYPE_POSITION_3D: "POSITION_3D",
	Animation.TYPE_ROTATION_3D: "ROTATION_3D",
	Animation.TYPE_SCALE_3D: "SCALE_3D",
	Animation.TYPE_BLEND_SHAPE: "BLEND_SHAPE",
	Animation.TYPE_METHOD: "METHOD",
	Animation.TYPE_BEZIER: "BEZIER",
	Animation.TYPE_AUDIO: "AUDIO",
	Animation.TYPE_ANIMATION: "ANIMATION",
}

# Track types whose path is just the node, no property subpath needed
const NODE_ONLY_TYPES: Array = [
	Animation.TYPE_POSITION_3D,
	Animation.TYPE_ROTATION_3D,
	Animation.TYPE_SCALE_3D,
	Animation.TYPE_METHOD,
	Animation.TYPE_AUDIO,
	Animation.TYPE_ANIMATION,
]


func _say(msg: String) -> void:
	if _announce.text == msg:
		_announce.text = msg + "​"
	else:
		_announce.text = msg


func _set_a11y(c: Control, aname: String, desc: String = "") -> void:
	if c.has_method(&"set_accessibility_name"):
		c.call(&"set_accessibility_name", aname)
	if not desc.is_empty() and c.has_method(&"set_accessibility_description"):
		c.call(&"set_accessibility_description", desc)


func _ready() -> void:
	custom_minimum_size = Vector2(320, 500)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	_build_ui()


func _btn(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	return b


func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _section(title: String) -> void:
	add_child(HSeparator.new())
	add_child(_lbl(title))


func _build_ui() -> void:
	# Announce live region
	_announce = Label.new()
	_announce.name = "Announce"
	_announce.custom_minimum_size = Vector2.ZERO
	_announce.modulate = Color(1, 1, 1, 0)
	_announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _announce.has_method(&"set_accessibility_live"):
		_announce.call(&"set_accessibility_live", 1)
	add_child(_announce)

	# Player status
	_player_label = Label.new()
	_player_label.text = "AnimationPlayer: (none selected)"
	_player_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_player_label)

	# Animation section
	_section("Animation")

	_anim_row = HBoxContainer.new()
	_anim_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_anim_row)

	_anim_option = OptionButton.new()
	_anim_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_option.disabled = true
	_set_a11y(_anim_option, "Active animation", "The animation to edit.")
	_anim_option.item_selected.connect(_on_animation_selected)
	_anim_row.add_child(_anim_option)

	var new_btn := _btn("New", _new_animation_dialog)
	_set_a11y(new_btn, "New animation", "Create a new blank animation on this AnimationPlayer.")
	_anim_row.add_child(new_btn)

	var del_anim_btn := _btn("Delete", _delete_animation)
	_set_a11y(del_anim_btn, "Delete animation", "Remove the currently selected animation.")
	_anim_row.add_child(del_anim_btn)

	_save_btn = _btn("Save Resource", _save_resource)
	_set_a11y(_save_btn, "Save animation resource", "Write changes to the .tres file on disk.")
	_save_btn.visible = false
	add_child(_save_btn)

	var meta_row := HBoxContainer.new()
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(meta_row)

	meta_row.add_child(_lbl("Length (s):"))
	_length_spin = SpinBox.new()
	_length_spin.min_value = 0.01; _length_spin.max_value = 3600.0; _length_spin.step = 0.01
	_length_spin.value = 1.0; _length_spin.editable = false
	_set_a11y(_length_spin, "Animation length in seconds", "Total duration of this animation.")
	_length_spin.value_changed.connect(_on_length_changed)
	meta_row.add_child(_length_spin)

	meta_row.add_child(_lbl("  Loop:"))
	_loop_option = OptionButton.new()
	_loop_option.add_item("None"); _loop_option.add_item("Linear"); _loop_option.add_item("Ping-Pong")
	_loop_option.disabled = true
	_set_a11y(_loop_option, "Loop mode", "None: play once. Linear: loop. Ping-Pong: reverse at end.")
	_loop_option.item_selected.connect(_on_loop_changed)
	meta_row.add_child(_loop_option)

	# Playback section
	_section("Playback")

	_playback_row = HBoxContainer.new()
	add_child(_playback_row)

	_play_btn = _btn("Play", _on_play)
	_play_btn.disabled = true
	_set_a11y(_play_btn, "Play animation", "Play the selected animation on the AnimationPlayer.")
	_playback_row.add_child(_play_btn)

	_stop_btn = _btn("Stop", _on_stop)
	_stop_btn.disabled = true
	_set_a11y(_stop_btn, "Stop animation")
	_playback_row.add_child(_stop_btn)

	_playback_row.add_child(_lbl("  Seek (s):"))
	_seek_spin = SpinBox.new()
	_seek_spin.min_value = 0.0; _seek_spin.max_value = 3600.0; _seek_spin.step = 0.001
	_seek_spin.editable = false
	_set_a11y(_seek_spin, "Seek time in seconds", "Jump the animation and timeline cursor to this time.")
	_seek_spin.value_changed.connect(_on_seek_changed)
	_playback_row.add_child(_seek_spin)

	# Tracks section
	_section("Tracks")

	_track_list = ItemList.new()
	_track_list.custom_minimum_size = Vector2(0, 120)
	_track_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_track_list, "Animation tracks",
		"Tracks in the active animation. Select a track to edit its keyframes in the timeline.")
	_track_list.item_selected.connect(_on_track_selected)
	add_child(_track_list)

	var track_btn_row := HBoxContainer.new()
	add_child(track_btn_row)

	var add_track_btn := _btn("Add Track", _add_track_dialog)
	_set_a11y(add_track_btn, "Add track", "Create a new animation track.")
	track_btn_row.add_child(add_track_btn)

	var rm_track_btn := _btn("Remove", _remove_selected_track)
	_set_a11y(rm_track_btn, "Remove selected track", "Delete the selected track and all its keyframes.")
	track_btn_row.add_child(rm_track_btn)

	# Track settings, update mode + interpolation for VALUE/BEZIER tracks
	_track_settings_row = HBoxContainer.new()
	_track_settings_row.visible = false
	add_child(_track_settings_row)

	_track_settings_row.add_child(_lbl("Update:"))
	_update_mode_option = OptionButton.new()
	_update_mode_option.add_item("Continuous"); _update_mode_option.add_item("Discrete")
	_update_mode_option.add_item("Capture"); _update_mode_option.add_item("Trigger")
	_set_a11y(_update_mode_option, "Track update mode",
		"Continuous: interpolated each frame. Discrete: jump at keyframe time. Capture: blend from current value.")
	_update_mode_option.item_selected.connect(_on_update_mode_changed)
	_track_settings_row.add_child(_update_mode_option)

	_track_settings_row.add_child(_lbl("  Interp:"))
	_interp_option = OptionButton.new()
	_interp_option.add_item("Nearest"); _interp_option.add_item("Linear"); _interp_option.add_item("Cubic")
	_interp_option.add_item("Linear Angle"); _interp_option.add_item("Cubic Angle")
	_set_a11y(_interp_option, "Interpolation type",
		"How values are interpolated between keyframes. Linear is most common.")
	_interp_option.item_selected.connect(_on_interp_changed)
	_track_settings_row.add_child(_interp_option)

	# Timeline section
	_section("Timeline")

	var step_row := HBoxContainer.new()
	add_child(step_row)
	step_row.add_child(_lbl("Time step (s):"))
	_step_spin = SpinBox.new()
	_step_spin.min_value = 0.001; _step_spin.max_value = 10.0; _step_spin.step = 0.001
	_step_spin.value = 0.1
	_set_a11y(_step_spin, "Timeline step size",
		"How many seconds Left/Right moves the timeline cursor.")
	_step_spin.value_changed.connect(func(v: float) -> void:
		if _timeline != null: _timeline.step = v)
	step_row.add_child(_step_spin)

	_timeline = TimelineControlCls.new()
	_timeline.dock = self
	_timeline.step = 0.1
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_timeline, "Animation timeline",
		"Keyboard driven timeline. Left/Right: move by step. Ctrl+Left/Right: jump to keyframes. Space: insert keyframe. Delete: remove. Up/Down: change numeric value. Enter: type a value.")
	add_child(_timeline)

	_info_label = Label.new()
	_info_label.text = "No animation selected."
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info_label)


# AnimationPlayer detection

func _on_selection_changed() -> void:
	if editor_interface == null:
		return
	var selected := editor_interface.get_selection().get_selected_nodes()
	for node in selected:
		if node is AnimationPlayer:
			_set_player(node as AnimationPlayer)
			return
		for child in node.get_children():
			if child is AnimationPlayer:
				_set_player(child as AnimationPlayer)
				return


func _set_player(player: AnimationPlayer) -> void:
	if current_player == player:
		return
	current_player = player
	_in_resource_mode = false
	_anim_row.visible = true
	_save_btn.visible = false
	_playback_row.visible = true
	_player_label.text = "AnimationPlayer: " + str(player.get_path())
	_refresh_animations()
	_say("AnimationPlayer detected: " + player.name)


func _set_animation_resource(anim: Animation) -> void:
	if _in_resource_mode and current_animation == anim:
		return
	current_player = null
	_in_resource_mode = true
	current_animation = anim
	current_animation_name = StringName(anim.resource_path.get_file().get_basename())
	current_track = -1

	_player_label.text = "Animation Resource: " + anim.resource_path
	_anim_row.visible = false
	_save_btn.visible = true
	_playback_row.visible = false

	_ignore_signals = true
	_length_spin.editable = true
	_length_spin.value = anim.length
	_loop_option.disabled = false
	_loop_option.select(int(anim.loop_mode))
	_seek_spin.max_value = anim.length
	_ignore_signals = false

	_refresh_tracks()
	if _timeline != null:
		_timeline.current_time = 0.0
		_timeline.queue_redraw()
	_info_label.text = "Animation: %s | Length: %.3f s" % [current_animation_name, anim.length]
	_say("Animation resource loaded: " + current_animation_name)


func _save_resource() -> void:
	if current_animation == null or not _in_resource_mode:
		return
	if current_animation.resource_path.is_empty():
		_say("Cannot save: animation has no file path.")
		return
	ResourceSaver.save(current_animation)
	_say("Saved: " + current_animation.resource_path.get_file())


# Animation list

func _refresh_animations() -> void:
	_ignore_signals = true
	_anim_option.clear()
	if current_player == null:
		_anim_option.disabled = true
		_length_spin.editable = false
		_loop_option.disabled = true
		_play_btn.disabled = true
		_stop_btn.disabled = true
		_seek_spin.editable = false
		_ignore_signals = false
		return

	_anim_option.disabled = false
	var names := current_player.get_animation_list()
	for n in names:
		_anim_option.add_item(n)

	if _anim_option.item_count > 0:
		_anim_option.select(0)
		_ignore_signals = false
		_on_animation_selected(0)
	else:
		current_animation = null
		current_animation_name = &""
		_length_spin.editable = false
		_loop_option.disabled = true
		_play_btn.disabled = true
		_stop_btn.disabled = true
		_seek_spin.editable = false
		_refresh_tracks()
		_ignore_signals = false


func _on_animation_selected(idx: int) -> void:
	if _ignore_signals or current_player == null:
		return
	current_animation_name = _anim_option.get_item_text(idx)
	current_animation = current_player.get_animation(current_animation_name)
	current_track = -1

	_ignore_signals = true
	_length_spin.editable = true
	_length_spin.value = current_animation.length
	_loop_option.disabled = false
	_loop_option.select(int(current_animation.loop_mode))
	_play_btn.disabled = false
	_stop_btn.disabled = false
	_seek_spin.editable = true
	_seek_spin.max_value = current_animation.length
	_ignore_signals = false

	_refresh_tracks()
	if _timeline != null:
		_timeline.current_time = 0.0
		_timeline.queue_redraw()
	_info_label.text = "Animation: %s | Length: %.3f s" % [current_animation_name, current_animation.length]
	_say("Animation: %s. %d tracks." % [current_animation_name, current_animation.get_track_count()])


func _new_animation_dialog() -> void:
	if current_player == null:
		_say("No AnimationPlayer selected.")
		return
	var dlg := AcceptDialog.new()
	dlg.title = "New Animation"
	dlg.min_size = Vector2(300, 120)
	var vb := VBoxContainer.new()
	dlg.add_child(vb)
	var field := LineEdit.new()
	field.placeholder_text = "animation_name"
	_set_a11y(field, "Animation name", "Name for the new animation.")
	vb.add_child(field)
	dlg.get_ok_button().text = "Create"
	add_child(dlg)
	dlg.popup_centered()
	field.grab_focus()
	dlg.confirmed.connect(func() -> void:
		var aname := field.text.strip_edges()
		dlg.queue_free()
		if aname.is_empty():
			return
		var lib: AnimationLibrary
		if current_player.has_animation_library(&""):
			lib = current_player.get_animation_library(&"")
		else:
			lib = AnimationLibrary.new()
			current_player.add_animation_library(&"", lib)
		if lib.has_animation(aname):
			_say("Animation '%s' already exists." % aname)
			return
		lib.add_animation(aname, Animation.new())
		_refresh_animations()
		# Select the new animation
		for i in _anim_option.item_count:
			if _anim_option.get_item_text(i) == aname:
				_anim_option.select(i)
				_on_animation_selected(i)
				break
		_say("Created animation: " + aname)
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())


func _delete_animation() -> void:
	if current_player == null or current_animation == null:
		_say("No animation selected.")
		return
	var aname := current_animation_name
	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete Animation"
	dlg.dialog_text = "Delete animation '%s'? This cannot be undone." % aname
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		var lib := current_player.get_animation_library(&"")
		if lib == null:
			return
		lib.remove_animation(aname)
		current_animation = null
		current_animation_name = &""
		current_track = -1
		_refresh_animations()
		_say("Deleted animation: " + aname)
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())


# Animation metadata

func _on_length_changed(value: float) -> void:
	if _ignore_signals or current_animation == null:
		return
	current_animation.length = value
	_seek_spin.max_value = value
	if _timeline != null:
		_timeline.current_time = clampf(_timeline.current_time, 0.0, value)
		_timeline.queue_redraw()


func _on_loop_changed(idx: int) -> void:
	if _ignore_signals or current_animation == null:
		return
	current_animation.loop_mode = idx as Animation.LoopMode


# Playback

func _on_play() -> void:
	if current_player == null or current_animation_name == &"":
		return
	current_player.play(current_animation_name)
	_say("Playing: " + current_animation_name)


func _on_stop() -> void:
	if current_player == null:
		return
	current_player.stop()
	_say("Stopped.")


func _on_seek_changed(value: float) -> void:
	if _ignore_signals or current_player == null:
		return
	current_player.seek(value, true)
	if _timeline != null:
		_timeline.current_time = value
		_timeline.queue_redraw()
		_update_info_label()


# Track list

func _refresh_tracks() -> void:
	var saved_track := current_track
	_track_list.clear()
	_track_settings_row.visible = false
	current_track = -1

	if current_animation == null:
		_info_label.text = "No animation selected."
		return

	for i in current_animation.get_track_count():
		var ttype := current_animation.track_get_type(i)
		var tpath := str(current_animation.track_get_path(i))
		var kcount := current_animation.track_get_key_count(i)
		var type_name := TRACK_TYPE_NAMES.get(ttype, "UNKNOWN")
		_track_list.add_item("[%s] %s  (%d key%s)" % [type_name, tpath, kcount, "s" if kcount != 1 else ""])
		_track_list.set_item_metadata(i, i)

	if saved_track >= 0 and saved_track < current_animation.get_track_count():
		current_track = saved_track
		_track_list.select(saved_track)
		var ttype := current_animation.track_get_type(current_track)
		var show_settings := ttype == Animation.TYPE_VALUE or ttype == Animation.TYPE_BEZIER
		_track_settings_row.visible = show_settings
		if show_settings:
			_ignore_signals = true
			if ttype == Animation.TYPE_VALUE:
				_update_mode_option.select(int(current_animation.value_track_get_update_mode(current_track)))
			_interp_option.select(int(current_animation.track_get_interpolation_type(current_track)))
			_ignore_signals = false

	if _timeline != null:
		_timeline.queue_redraw()


func _on_track_selected(idx: int) -> void:
	current_track = _track_list.get_item_metadata(idx)
	if current_animation == null:
		return

	var ttype := current_animation.track_get_type(current_track)
	var show_settings := ttype == Animation.TYPE_VALUE or ttype == Animation.TYPE_BEZIER
	_track_settings_row.visible = show_settings

	if show_settings:
		_ignore_signals = true
		if ttype == Animation.TYPE_VALUE:
			_update_mode_option.select(int(current_animation.value_track_get_update_mode(current_track)))
		_interp_option.select(int(current_animation.track_get_interpolation_type(current_track)))
		_ignore_signals = false

	if _timeline != null:
		_timeline.queue_redraw()
	_update_info_label()

	var tname := TRACK_TYPE_NAMES.get(ttype, "UNKNOWN")
	var tpath := str(current_animation.track_get_path(current_track))
	_say("Track %d: [%s] %s. %d keyframes." % [
		current_track, tname, tpath,
		current_animation.track_get_key_count(current_track)
	])


func _add_track_dialog() -> void:
	if current_animation == null:
		_say("No animation selected.")
		return

	var dlg := AcceptDialog.new()
	dlg.title = "Add Track"
	dlg.min_size = Vector2(360, 220)
	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	# Track type selector
	vb.add_child(_lbl("Track type:"))
	var type_opt := OptionButton.new()
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for ttype in [
		Animation.TYPE_VALUE, Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
		Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE, Animation.TYPE_METHOD,
		Animation.TYPE_BEZIER, Animation.TYPE_AUDIO, Animation.TYPE_ANIMATION,
	]:
		type_opt.add_item(TRACK_TYPE_NAMES[ttype])
		type_opt.set_item_metadata(type_opt.item_count - 1, ttype)
	_set_a11y(type_opt, "Track type", "The kind of animation track to create.")
	vb.add_child(type_opt)

	# Node path
	vb.add_child(_lbl("Node path (relative to AnimationPlayer root):"))
	var node_field := LineEdit.new()
	node_field.placeholder_text = "e.g. Sprite2D"
	_set_a11y(node_field, "Node path", "Path to the node this track targets.")
	vb.add_child(node_field)

	# Property subpath, conditional
	var prop_label := _lbl("Property path (e.g. position:x):")
	vb.add_child(prop_label)
	var prop_field := LineEdit.new()
	prop_field.placeholder_text = "e.g. modulate:a"
	_set_a11y(prop_field, "Property path", "The property to animate. For blend shapes use: blend_shapes/ShapeName")
	vb.add_child(prop_field)

	# Show/hide property field based on selected type
	var _update_prop_visibility := func() -> void:
		var sel_type: int = type_opt.get_selected_metadata()
		var needs_prop := sel_type not in NODE_ONLY_TYPES
		prop_label.visible = needs_prop
		prop_field.visible = needs_prop
	_update_prop_visibility.call()
	type_opt.item_selected.connect(func(_i: int) -> void: _update_prop_visibility.call())

	dlg.get_ok_button().text = "Add"
	add_child(dlg)
	dlg.popup_centered()
	node_field.grab_focus()

	dlg.confirmed.connect(func() -> void:
		var sel_type: int = type_opt.get_selected_metadata()
		var node_path := node_field.text.strip_edges()
		var prop_path := prop_field.text.strip_edges()
		dlg.queue_free()

		if node_path.is_empty():
			_say("Node path is required.")
			return

		var full_path: String
		if sel_type in NODE_ONLY_TYPES:
			full_path = node_path
		else:
			if prop_path.is_empty():
				_say("Property path is required for this track type.")
				return
			full_path = node_path + ":" + prop_path

		var idx := current_animation.add_track(sel_type)
		current_animation.track_set_path(idx, NodePath(full_path))
		_refresh_tracks()
		# Select the new track
		_track_list.select(idx)
		_on_track_selected(idx)
		_say("Added %s track: %s" % [TRACK_TYPE_NAMES[sel_type], full_path])
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())


func _remove_selected_track() -> void:
	if current_animation == null or current_track < 0:
		_say("No track selected.")
		return
	var tpath := str(current_animation.track_get_path(current_track))
	var dlg := ConfirmationDialog.new()
	dlg.title = "Remove Track"
	dlg.dialog_text = "Remove track '%s' and all its keyframes?" % tpath
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func() -> void:
		dlg.queue_free()
		current_animation.remove_track(current_track)
		current_track = -1
		_refresh_tracks()
		if _timeline != null:
			_timeline.queue_redraw()
		_say("Track removed.")
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())


# Track settings

func _on_update_mode_changed(idx: int) -> void:
	if _ignore_signals or current_animation == null or current_track < 0:
		return
	if current_animation.track_get_type(current_track) == Animation.TYPE_VALUE:
		current_animation.value_track_set_update_mode(current_track, idx as Animation.UpdateMode)


func _on_interp_changed(idx: int) -> void:
	if _ignore_signals or current_animation == null or current_track < 0:
		return
	current_animation.track_set_interpolation_type(current_track, idx as Animation.InterpolationType)


# Info label, called by timeline_control too

func _update_info_label() -> void:
	if current_animation == null:
		_info_label.text = "No animation selected."
		return
	if _timeline == null:
		return
	var t: float = _timeline.current_time
	var val_str := "(no track selected)"
	if current_track >= 0:
		val_str = _get_value_string_at(current_track, t)
	_info_label.text = "Track: %d | Time: %.3f s | Value: %s" % [current_track, t, val_str]


func _get_value_string_at(track_idx: int, time: float) -> String:
	var anim := current_animation
	var key_idx := anim.track_find_key(track_idx, time, Animation.FIND_MODE_APPROX)
	if key_idx < 0:
		return "(no keyframe here)"
	var ttype := anim.track_get_type(track_idx)
	match ttype:
		Animation.TYPE_VALUE:
			return str(anim.track_get_key_value(track_idx, key_idx))
		Animation.TYPE_BEZIER:
			return "%.4f" % anim.bezier_track_get_key_value(track_idx, key_idx)
		Animation.TYPE_BLEND_SHAPE:
			return "%.4f" % (anim.track_get_key_value(track_idx, key_idx) as float)
		Animation.TYPE_POSITION_3D:
			var v: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
		Animation.TYPE_ROTATION_3D:
			var q: Quaternion = anim.track_get_key_value(track_idx, key_idx)
			var e: Vector3 = q.get_euler()
			return "Euler(%.2f°, %.2f°, %.2f°)" % [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]
		Animation.TYPE_SCALE_3D:
			var v: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
		Animation.TYPE_METHOD:
			var method_name := anim.method_track_get_name(track_idx, key_idx)
			var params := anim.method_track_get_params(track_idx, key_idx)
			return "%s(%s)" % [method_name, ", ".join(params.map(func(p): return str(p)))]
		Animation.TYPE_AUDIO:
			var stream := anim.audio_track_get_key_stream(track_idx, key_idx)
			return stream.resource_path if stream != null else "(null)"
		Animation.TYPE_ANIMATION:
			return str(anim.animation_track_get_key_animation(track_idx, key_idx))
	return "(unknown)"
