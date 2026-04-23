@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var effect_list: ItemList
var effect_type: OptionButton
var effect_props_box: VBoxContainer

var _current_eff_idx: int = -1
# Array of [prop_name: String, control: Control] for the active property panel
var _prop_controls: Array = []

# Internal property names shared by all Resources, skip these
const _SKIP_PROPS := ["script", "resource_local_to_scene", "resource_path", "resource_name"]

const EFFECT_CLASSES := [
	["Amplify", "AudioEffectAmplify"],
	["Band Limit Filter", "AudioEffectBandLimitFilter"],
	["Band Pass Filter", "AudioEffectBandPassFilter"],
	["Capture", "AudioEffectCapture"],
	["Chorus", "AudioEffectChorus"],
	["Compressor", "AudioEffectCompressor"],
	["Delay", "AudioEffectDelay"],
	["Distortion", "AudioEffectDistortion"],
	["EQ 6-band", "AudioEffectEQ6"],
	["EQ 10-band", "AudioEffectEQ10"],
	["EQ 21-band", "AudioEffectEQ21"],
	["High Pass Filter", "AudioEffectHighPassFilter"],
	["High Shelf Filter", "AudioEffectHighShelfFilter"],
	["Hard Limiter", "AudioEffectHardLimiter"],
	["Limiter", "AudioEffectLimiter"],
	["Low Pass Filter", "AudioEffectLowPassFilter"],
	["Low Shelf Filter", "AudioEffectLowShelfFilter"],
	["Notch Filter", "AudioEffectNotchFilter"],
	["Panner", "AudioEffectPanner"],
	["Phaser", "AudioEffectPhaser"],
	["Pitch Shift", "AudioEffectPitchShift"],
	["Record", "AudioEffectRecord"],
	["Reverb", "AudioEffectReverb"],
	["Spectrum Analyzer", "AudioEffectSpectrumAnalyzer"],
	["Stereo Enhance", "AudioEffectStereoEnhance"],
]

func _ready() -> void:
	var lbl := Label.new()
	lbl.text = "Effects on selected bus"
	add_child(lbl)

	effect_list = ItemList.new()
	effect_list.custom_minimum_size = Vector2(0, 150)
	effect_list.item_selected.connect(_on_effect_select)
	add_child(effect_list)

	_btn("Refresh effect list", _refresh)

	add_child(HSeparator.new())

	var add_lbl := Label.new()
	add_lbl.text = "Add effect:"
	add_child(add_lbl)

	effect_type = OptionButton.new()
	effect_type.accessibility_name = "Effect type to add"
	for pair in EFFECT_CLASSES:
		effect_type.add_item(pair[0])
	effect_type.selected = 22  # Default: Reverb
	add_child(effect_type)

	_btn("Add effect to bus", _add_effect)

	add_child(HSeparator.new())

	_btn("Remove selected effect", _remove_effect)
	_btn("Toggle selected effect on/off", _toggle_effect)

	var move_row := HBoxContainer.new()
	var up := Button.new()
	up.text = "Move effect up"
	up.pressed.connect(_move_effect_up)
	move_row.add_child(up)
	var dn := Button.new()
	dn.text = "Move effect down"
	dn.pressed.connect(_move_effect_down)
	move_row.add_child(dn)
	add_child(move_row)

	add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	effect_props_box = VBoxContainer.new()
	effect_props_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(effect_props_box)

	_refresh()

# ---------------------------------------------------------------------------
# Effect list
# ---------------------------------------------------------------------------

func _refresh() -> void:
	effect_list.clear()
	var idx: int = dock.current_bus_idx if dock else -1
	if idx < 0:
		effect_list.add_item("(No bus selected)")
		_clear_props()
		return
	var count := AudioServer.get_bus_effect_count(idx)
	if count == 0:
		effect_list.add_item("(No effects on %s)" % AudioServer.get_bus_name(idx))
		_clear_props()
		return
	for j in count:
		var eff := AudioServer.get_bus_effect(idx, j)
		var enabled := AudioServer.is_bus_effect_enabled(idx, j)
		var display := eff.get_class().trim_prefix("AudioEffect")
		effect_list.add_item("%d. %s  [%s]" % [j + 1, display, "on" if enabled else "off"])
		effect_list.set_item_metadata(effect_list.item_count - 1, j)

func _on_effect_select(i: int) -> void:
	# Items without metadata are placeholders, ignore
	var meta = effect_list.get_item_metadata(i)
	if meta == null:
		return
	_current_eff_idx = int(meta)
	_populate_effect_editor(dock.current_bus_idx, _current_eff_idx)

# ---------------------------------------------------------------------------
# Effect property editor
# ---------------------------------------------------------------------------

func _clear_props() -> void:
	_prop_controls.clear()
	_current_eff_idx = -1
	for child in effect_props_box.get_children():
		child.queue_free()

func _populate_effect_editor(bus_idx: int, eff_idx: int) -> void:
	_prop_controls.clear()
	for child in effect_props_box.get_children():
		child.queue_free()

	var eff := AudioServer.get_bus_effect(bus_idx, eff_idx)
	if eff == null:
		return

	var display := eff.get_class().trim_prefix("AudioEffect")
	var header := Label.new()
	header.text = "Properties: %s" % display
	effect_props_box.add_child(header)

	for prop in eff.get_property_list():
		var pname: String = prop["name"]
		var ptype: int = prop["type"]
		var phint: int = prop["hint"]
		var phint_str: String = prop["hint_string"]
		var pusage: int = prop["usage"]

		# Skip noneditor and internal properties
		if pusage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if pname in _SKIP_PROPS:
			continue
		if ptype == TYPE_NIL or ptype == TYPE_OBJECT:
			continue

		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = pname.replace("_", " ").capitalize() + ":"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var ctrl: Control = _make_control(ptype, phint, phint_str)
		if ctrl == null:
			continue
		ctrl.accessibility_name = pname.replace("_", " ").capitalize()

		var current_val = eff.get(pname)
		if current_val != null:
			_set_control_value(ctrl, current_val)

		row.add_child(ctrl)
		effect_props_box.add_child(row)
		_prop_controls.append([pname, ctrl])

	if _prop_controls.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(No editable properties)"
		effect_props_box.add_child(none_lbl)
		return

	var apply_btn := Button.new()
	apply_btn.text = "Apply effect properties"
	apply_btn.pressed.connect(_apply_effect_props)
	effect_props_box.add_child(apply_btn)

func _make_control(ptype: int, phint: int, phint_str: String) -> Control:
	match ptype:
		TYPE_FLOAT:
			var s := SpinBox.new()
			if phint == PROPERTY_HINT_RANGE and phint_str != "":
				var parts := phint_str.split(",")
				s.min_value = float(parts[0]) if parts.size() > 0 else -9999.0
				s.max_value = float(parts[1]) if parts.size() > 1 else 9999.0
				s.step     = float(parts[2]) if parts.size() > 2 else 0.01
			else:
				s.min_value = -9999.0
				s.max_value = 9999.0
				s.step = 0.01
			return s

		TYPE_INT:
			if phint == PROPERTY_HINT_ENUM and phint_str != "":
				var opt := OptionButton.new()
				# hint_string may be "Item1,Item2" or "Item1:0,Item2:1"
				for entry in phint_str.split(","):
					opt.add_item(entry.split(":")[0])
				return opt
			else:
				var s := SpinBox.new()
				s.min_value = -99999.0
				s.max_value = 99999.0
				s.step = 1.0
				s.rounded = true
				return s

		TYPE_BOOL:
			var cb := CheckButton.new()
			cb.text = ""
			return cb

	return null  # Unsupported type, row is skipped

func _set_control_value(ctrl: Control, value: Variant) -> void:
	if ctrl is SpinBox:
		ctrl.value = float(value)
	elif ctrl is CheckButton:
		ctrl.button_pressed = bool(value)
	elif ctrl is OptionButton:
		ctrl.selected = int(value)

func _read_control(ctrl: Control) -> Variant:
	if ctrl is SpinBox:
		return ctrl.value
	elif ctrl is CheckButton:
		return ctrl.button_pressed
	elif ctrl is OptionButton:
		return ctrl.selected
	return null

func _apply_effect_props() -> void:
	var bus_idx: int = dock.current_bus_idx
	if bus_idx < 0 or _current_eff_idx < 0:
		dock._say("No effect selected.")
		return
	var eff := AudioServer.get_bus_effect(bus_idx, _current_eff_idx)
	if eff == null:
		dock._say("Effect no longer exists.")
		return
	for pair in _prop_controls:
		var pname: String = pair[0]
		var ctrl: Control = pair[1]
		eff.set(pname, _read_control(ctrl))
	_save_layout()
	var display := eff.get_class().trim_prefix("AudioEffect")
	dock._say("Applied properties for %s." % display)

# ---------------------------------------------------------------------------
# Effect list mutations
# ---------------------------------------------------------------------------

func _add_effect() -> void:
	var bus_idx: int = dock.current_bus_idx
	if bus_idx < 0: dock._say("No bus selected."); return
	var pair: Array = EFFECT_CLASSES[effect_type.selected]
	var effect = ClassDB.instantiate(pair[1])
	if effect == null:
		dock._say("Could not create effect %s." % pair[0]); return
	AudioServer.add_bus_effect(bus_idx, effect)
	_save_layout()
	_refresh()
	dock._say("Added %s to %s." % [pair[0], AudioServer.get_bus_name(bus_idx)])

func _remove_effect() -> void:
	var bus_idx: int = dock.current_bus_idx
	if bus_idx < 0: dock._say("No bus selected."); return
	var eff_idx := _selected_effect_idx()
	if eff_idx < 0: dock._say("No effect selected."); return
	var eff := AudioServer.get_bus_effect(bus_idx, eff_idx)
	var display := eff.get_class().trim_prefix("AudioEffect")
	AudioServer.remove_bus_effect(bus_idx, eff_idx)
	_clear_props()
	_save_layout()
	_refresh()
	dock._say("Removed %s from %s." % [display, AudioServer.get_bus_name(bus_idx)])

func _toggle_effect() -> void:
	var bus_idx: int = dock.current_bus_idx
	if bus_idx < 0: dock._say("No bus selected."); return
	var eff_idx := _selected_effect_idx()
	if eff_idx < 0: dock._say("No effect selected."); return
	var currently := AudioServer.is_bus_effect_enabled(bus_idx, eff_idx)
	AudioServer.set_bus_effect_enabled(bus_idx, eff_idx, not currently)
	_save_layout()
	_refresh()
	var eff := AudioServer.get_bus_effect(bus_idx, eff_idx)
	var display := eff.get_class().trim_prefix("AudioEffect")
	dock._say("%s is now %s." % [display, "on" if not currently else "off"])

func _move_effect_up() -> void:
	var bus_idx: int = dock.current_bus_idx
	if bus_idx < 0: dock._say("No bus selected."); return
	var eff_idx := _selected_effect_idx()
	if eff_idx <= 0: dock._say("Cannot move effect further up."); return
	AudioServer.swap_bus_effects(bus_idx, eff_idx, eff_idx - 1)
	_save_layout()
	_refresh()
	effect_list.select(eff_idx - 1)
	if _current_eff_idx == eff_idx:
		_current_eff_idx = eff_idx - 1
	dock._say("Moved effect up to position %d." % eff_idx)

func _move_effect_down() -> void:
	var bus_idx: int = dock.current_bus_idx
	if bus_idx < 0: dock._say("No bus selected."); return
	var eff_idx := _selected_effect_idx()
	if eff_idx < 0: dock._say("No effect selected."); return
	if eff_idx >= AudioServer.get_bus_effect_count(bus_idx) - 1:
		dock._say("Cannot move effect further down."); return
	AudioServer.swap_bus_effects(bus_idx, eff_idx, eff_idx + 1)
	_save_layout()
	_refresh()
	effect_list.select(eff_idx + 1)
	if _current_eff_idx == eff_idx:
		_current_eff_idx = eff_idx + 1
	dock._say("Moved effect down to position %d." % (eff_idx + 2))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _selected_effect_idx() -> int:
	var sel := effect_list.get_selected_items()
	if sel.is_empty():
		return -1
	var item_idx: int = sel[0]
	var meta = effect_list.get_item_metadata(item_idx)
	if meta == null:
		return -1
	return int(meta)

func _save_layout() -> void:
	var path: String = ProjectSettings.get_setting(
		"audio/buses/default_bus_layout", "res://default_bus_layout.tres")
	ResourceSaver.save(AudioServer.generate_bus_layout(), path)

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	add_child(b)
