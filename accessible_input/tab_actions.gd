@tool
extends VBoxContainer

var dock

var show_builtins_check: CheckBox
var action_list: ItemList

var event_list: ItemList

var action_name_edit: LineEdit
var deadzone_spin: SpinBox

var event_type_option: OptionButton


var keyboard_section: VBoxContainer
var listen_btn: Button
var capture_panel: Panel
var capture_label: Label
var captured_key_label: Label
var ctrl_check: CheckBox
var shift_check: CheckBox
var alt_check: CheckBox
var meta_check: CheckBox
var _captured_physical_keycode: Key = KEY_NONE
var _listening: bool = false


var mouse_section: VBoxContainer
var mouse_button_option: OptionButton


var joypad_btn_section: VBoxContainer
var joypad_button_option: OptionButton


var joypad_axis_section: VBoxContainer
var joypad_axis_option: OptionButton
var joypad_axis_dir_option: OptionButton

const MOUSE_BUTTONS := [
	["Left",        MOUSE_BUTTON_LEFT],
	["Right",       MOUSE_BUTTON_RIGHT],
	["Middle",      MOUSE_BUTTON_MIDDLE],
	["Wheel Up",    MOUSE_BUTTON_WHEEL_UP],
	["Wheel Down",  MOUSE_BUTTON_WHEEL_DOWN],
	["Wheel Left",  MOUSE_BUTTON_WHEEL_LEFT],
	["Wheel Right", MOUSE_BUTTON_WHEEL_RIGHT],
	["Extra 1",     MOUSE_BUTTON_XBUTTON1],
	["Extra 2",     MOUSE_BUTTON_XBUTTON2],
]


const JOYPAD_BUTTONS := [
	["A / Cross",         0],
	["B / Circle",        1],
	["X / Square",        2],
	["Y / Triangle",      3],
	["L1",                4],
	["R1",                5],
	["L2 (digital)",      6],
	["R2 (digital)",      7],
	["Left Stick Click",  8],
	["Right Stick Click", 9],
	["Back / Select",    10],
	["Start",            11],
	["D-Pad Up",         12],
	["D-Pad Down",       13],
	["D-Pad Left",       14],
	["D-Pad Right",      15],
	["Guide / Home",     16],
	["Misc 1",           17],
]

const JOYPAD_AXES := [
	["Left Stick X",  0],
	["Left Stick Y",  1],
	["Right Stick X", 2],
	["Right Stick Y", 3],
	["L2 Analog",     4],
	["R2 Analog",     5],
]

func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var al_lbl := Label.new()
	al_lbl.text = "Input Actions"
	body.add_child(al_lbl)

	show_builtins_check = CheckBox.new()
	show_builtins_check.text = "Show built-in actions (ui_accept etc.)"
	show_builtins_check.toggled.connect(_on_show_builtins_toggled)
	body.add_child(show_builtins_check)

	action_list = ItemList.new()
	action_list.custom_minimum_size = Vector2(0, 180)
	action_list.accessibility_name = "Action list"
	action_list.item_selected.connect(_on_action_selected)
	body.add_child(action_list)

	_btn_in(body, "Refresh action list", _refresh_actions)

	body.add_child(HSeparator.new())

	var el_lbl := Label.new()
	el_lbl.text = "Events on selected action:"
	body.add_child(el_lbl)

	event_list = ItemList.new()
	event_list.custom_minimum_size = Vector2(0, 100)
	event_list.accessibility_name = "Event list"
	body.add_child(event_list)

	_btn_in(body, "Remove selected event", _remove_event)

	body.add_child(HSeparator.new())

	var am_lbl := Label.new()
	am_lbl.text = "Action name:"
	body.add_child(am_lbl)

	action_name_edit = LineEdit.new()
	action_name_edit.placeholder_text = "e.g. jump, attack"
	action_name_edit.accessibility_name = "Action name"
	body.add_child(action_name_edit)

	var dz_row := HBoxContainer.new()
	var dz_lbl := Label.new()
	dz_lbl.text = "Deadzone:"
	dz_row.add_child(dz_lbl)
	deadzone_spin = SpinBox.new()
	deadzone_spin.min_value = 0.0
	deadzone_spin.max_value = 1.0
	deadzone_spin.step = 0.01
	deadzone_spin.value = 0.5
	deadzone_spin.accessibility_name = "Deadzone, zero to one"
	dz_row.add_child(deadzone_spin)
	body.add_child(dz_row)

	_btn_in(body, "Add new action", _add_action)
	_btn_in(body, "Remove selected action", _remove_action)

	body.add_child(HSeparator.new())

	var aev_lbl := Label.new()
	aev_lbl.text = "Add event to selected action:"
	body.add_child(aev_lbl)

	var et_row := HBoxContainer.new()
	var et_lbl := Label.new()
	et_lbl.text = "Event type:"
	et_row.add_child(et_lbl)
	event_type_option = OptionButton.new()
	event_type_option.accessibility_name = "Event type"
	event_type_option.add_item("Keyboard")
	event_type_option.add_item("Mouse Button")
	event_type_option.add_item("Joypad Button")
	event_type_option.add_item("Joypad Axis")
	event_type_option.item_selected.connect(_on_event_type_changed)
	et_row.add_child(event_type_option)
	body.add_child(et_row)

	keyboard_section = VBoxContainer.new()
	body.add_child(keyboard_section)

	listen_btn = Button.new()
	listen_btn.text = "Listen for key"
	listen_btn.pressed.connect(_start_listen)
	keyboard_section.add_child(listen_btn)

	capture_panel = Panel.new()
	capture_panel.focus_mode = Control.FOCUS_ALL
	capture_panel.custom_minimum_size = Vector2(0, 36)
	capture_panel.visible = false
	capture_panel.accessibility_name = "Key capture area, press any key"
	capture_panel.gui_input.connect(_on_capture_gui_input)
	keyboard_section.add_child(capture_panel)

	capture_label = Label.new()
	capture_label.text = "Press any key. Escape to cancel."
	capture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capture_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capture_panel.add_child(capture_label)
	capture_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	captured_key_label = Label.new()
	captured_key_label.text = "(no key captured)"
	keyboard_section.add_child(captured_key_label)

	var mod_lbl := Label.new()
	mod_lbl.text = "Modifiers:"
	keyboard_section.add_child(mod_lbl)

	var mod_row := HBoxContainer.new()
	ctrl_check = CheckBox.new()
	ctrl_check.text = "Ctrl"
	mod_row.add_child(ctrl_check)
	shift_check = CheckBox.new()
	shift_check.text = "Shift"
	mod_row.add_child(shift_check)
	alt_check = CheckBox.new()
	alt_check.text = "Alt"
	mod_row.add_child(alt_check)
	meta_check = CheckBox.new()
	meta_check.text = "Meta"
	mod_row.add_child(meta_check)
	keyboard_section.add_child(mod_row)

	_btn_in(keyboard_section, "Add keyboard event", _add_keyboard_event)

	mouse_section = VBoxContainer.new()
	mouse_section.visible = false
	body.add_child(mouse_section)

	var mb_row := HBoxContainer.new()
	var mb_lbl := Label.new()
	mb_lbl.text = "Mouse button:"
	mb_row.add_child(mb_lbl)
	mouse_button_option = OptionButton.new()
	mouse_button_option.accessibility_name = "Mouse button"
	for pair in MOUSE_BUTTONS:
		mouse_button_option.add_item(pair[0])
	mb_row.add_child(mouse_button_option)
	mouse_section.add_child(mb_row)

	_btn_in(mouse_section, "Add mouse button event", _add_mouse_event)

	joypad_btn_section = VBoxContainer.new()
	joypad_btn_section.visible = false
	body.add_child(joypad_btn_section)

	var jb_row := HBoxContainer.new()
	var jb_lbl := Label.new()
	jb_lbl.text = "Joypad button:"
	jb_row.add_child(jb_lbl)
	joypad_button_option = OptionButton.new()
	joypad_button_option.accessibility_name = "Joypad button"
	for pair in JOYPAD_BUTTONS:
		joypad_button_option.add_item(pair[0])
	jb_row.add_child(joypad_button_option)
	joypad_btn_section.add_child(jb_row)

	_btn_in(joypad_btn_section, "Add joypad button event", _add_joypad_button_event)

	joypad_axis_section = VBoxContainer.new()
	joypad_axis_section.visible = false
	body.add_child(joypad_axis_section)

	var ja_row := HBoxContainer.new()
	var ja_lbl := Label.new()
	ja_lbl.text = "Axis:"
	ja_row.add_child(ja_lbl)
	joypad_axis_option = OptionButton.new()
	joypad_axis_option.accessibility_name = "Joypad axis"
	for pair in JOYPAD_AXES:
		joypad_axis_option.add_item(pair[0])
	ja_row.add_child(joypad_axis_option)
	joypad_axis_section.add_child(ja_row)

	var jad_row := HBoxContainer.new()
	var jad_lbl := Label.new()
	jad_lbl.text = "Direction:"
	jad_row.add_child(jad_lbl)
	joypad_axis_dir_option = OptionButton.new()
	joypad_axis_dir_option.accessibility_name = "Axis direction"
	joypad_axis_dir_option.add_item("Positive (+)")
	joypad_axis_dir_option.add_item("Negative (-)")
	jad_row.add_child(joypad_axis_dir_option)
	joypad_axis_section.add_child(jad_row)

	_btn_in(joypad_axis_section, "Add joypad axis event", _add_joypad_axis_event)

	_refresh_actions()


func _refresh_actions() -> void:
	InputMap.load_from_project_settings()
	action_list.clear()
	var actions: Array = InputMap.get_actions()
	actions.sort()
	for action in actions:
		var s := String(action)
		var setting := "input/" + s
		var is_project: bool = ProjectSettings.has_setting(setting) \
				and ProjectSettings.property_get_revert(setting) == null
		if not show_builtins_check.button_pressed and not is_project:
			continue
		var tag := "" if is_project else " [built-in]"
		var ev_count: int = InputMap.action_get_events(action).size()
		action_list.add_item("%s%s  dz:%.2f  %d event(s)" % [
			s, tag, InputMap.action_get_deadzone(action), ev_count])
		action_list.set_item_metadata(action_list.item_count - 1, s)

func _on_show_builtins_toggled(_on: bool) -> void:
	_refresh_actions()
	var mode_str := "all actions" if _on else "project actions only"
	dock._say("Showing %s." % mode_str)

func _on_action_selected(i: int) -> void:
	var s: String = action_list.get_item_metadata(i)
	dock.current_action = StringName(s)
	action_name_edit.text = s
	deadzone_spin.value = InputMap.action_get_deadzone(dock.current_action)
	_refresh_events()
	# dock._say("Selected action: %s." % s)


func _refresh_events() -> void:
	event_list.clear()
	if dock.current_action == &"":
		event_list.add_item("(No action selected)")
		return
	var events: Array = InputMap.action_get_events(dock.current_action)
	if events.is_empty():
		event_list.add_item("(No events bound)")
		return
	for i in events.size():
		event_list.add_item("%d. %s" % [i + 1, events[i].as_text()])
		event_list.set_item_metadata(event_list.item_count - 1, i)

func _remove_event() -> void:
	if dock.current_action == &"":
		dock._say("No action selected."); return
	var sel := event_list.get_selected_items()
	if sel.is_empty():
		dock._say("No event selected."); return
	var meta = event_list.get_item_metadata(sel[0])
	if meta == null:
		dock._say("Select an event item."); return
	var events: Array = InputMap.action_get_events(dock.current_action)
	var ev_idx := int(meta)
	if ev_idx >= events.size():
		dock._say("Event index out of range."); return
	var ev: InputEvent = events[ev_idx]
	var ev_text := ev.as_text()
	InputMap.action_erase_event(dock.current_action, ev)
	_save_action(dock.current_action)
	_refresh_events()
	_refresh_actions()
	dock._say("Removed event: %s from %s." % [ev_text, String(dock.current_action)])



func _add_action() -> void:
	var s := action_name_edit.text.strip_edges()
	if s.is_empty():
		dock._say("Enter an action name."); return
	if InputMap.has_action(s):
		dock._say("Action already exists: %s." % s); return
	var dz: float = deadzone_spin.value
	ProjectSettings.set_setting("input/" + s, {"deadzone": dz, "events": []})
	ProjectSettings.save()
	InputMap.load_from_project_settings()
	_refresh_actions()
	dock._say("Added action: %s (deadzone %.2f)." % [s, dz])

func _remove_action() -> void:
	if dock.current_action == &"":
		dock._say("No action selected."); return
	var s := String(dock.current_action)
	if not ProjectSettings.has_setting("input/" + s):
		dock._say("Cannot remove built-in action: %s." % s); return
	ProjectSettings.set_setting("input/" + s, null)
	ProjectSettings.save()
	InputMap.load_from_project_settings()
	dock.current_action = &""
	action_name_edit.text = ""
	_refresh_actions()
	_refresh_events()
	dock._say("Removed action: %s." % s)



func _save_action(action: StringName) -> void:
	var s := String(action)
	if not ProjectSettings.has_setting("input/" + s):
		return  # built-in
	var dz: float = InputMap.action_get_deadzone(action)
	var events: Array = InputMap.action_get_events(action)
	ProjectSettings.set_setting("input/" + s, {"deadzone": dz, "events": events})
	ProjectSettings.save()
	InputMap.load_from_project_settings()


func _on_event_type_changed(idx: int) -> void:
	keyboard_section.visible    = (idx == 0)
	mouse_section.visible       = (idx == 1)
	joypad_btn_section.visible  = (idx == 2)
	joypad_axis_section.visible = (idx == 3)
	const NAMES := ["Keyboard", "Mouse Button", "Joypad Button", "Joypad Axis"]
	dock._say("Event type: %s." % NAMES[idx])

func _start_listen() -> void:
	if dock.current_action == &"":
		dock._say("Select an action first."); return
	_listening = true
	_captured_physical_keycode = KEY_NONE
	captured_key_label.text = "(no key captured)"
	capture_panel.visible = true
	call_deferred("_grab_capture_focus")
	dock._say("Listening. Press any key, or Escape to cancel.")

func _grab_capture_focus() -> void:
	if is_instance_valid(capture_panel) and capture_panel.visible:
		capture_panel.grab_focus()

func _on_capture_gui_input(event: InputEvent) -> void:
	if not _listening:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	const MODS: Array[Key] = [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META,
	                          KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]
	if key.keycode in MODS:
		return
	if key.keycode == KEY_ESCAPE:
		capture_panel.accept_event()
		_listening = false
		capture_panel.visible = false
		listen_btn.grab_focus()
		_captured_physical_keycode = KEY_NONE
		captured_key_label.text = "(no key captured)"
		dock._say("Key capture cancelled.")
		return
	capture_panel.accept_event()
	_listening = false
	_captured_physical_keycode = key.physical_keycode
	capture_panel.visible = false
	listen_btn.grab_focus()
	var kname := OS.get_keycode_string(_captured_physical_keycode)
	captured_key_label.text = "Captured: %s" % kname
	dock._say("Captured: %s. Set modifiers if needed, then press Add keyboard event." % kname)


func _add_keyboard_event() -> void:
	if dock.current_action == &"":
		dock._say("Select an action first."); return
	if _captured_physical_keycode == KEY_NONE:
		dock._say("Press Listen for key first, then press a key."); return
	var ev := InputEventKey.new()
	ev.physical_keycode = _captured_physical_keycode
	ev.ctrl_pressed     = ctrl_check.button_pressed
	ev.shift_pressed    = shift_check.button_pressed
	ev.alt_pressed      = alt_check.button_pressed
	ev.meta_pressed     = meta_check.button_pressed
	if _already_bound(ev):
		dock._say("That key combination is already bound to %s." % String(dock.current_action)); return
	InputMap.action_add_event(dock.current_action, ev)
	_save_action(dock.current_action)
	_refresh_events()
	_refresh_actions()
	var ev_text := ev.as_text()
	_captured_physical_keycode = KEY_NONE
	captured_key_label.text = "(no key captured)"
	ctrl_check.button_pressed  = false
	shift_check.button_pressed = false
	alt_check.button_pressed   = false
	meta_check.button_pressed  = false
	dock._say("Added: %s to %s." % [ev_text, String(dock.current_action)])

func _add_mouse_event() -> void:
	if dock.current_action == &"":
		dock._say("Select an action first."); return
	var pair: Array = MOUSE_BUTTONS[mouse_button_option.selected]
	var ev := InputEventMouseButton.new()
	ev.button_index = pair[1]
	if _already_bound(ev):
		dock._say("That mouse button is already bound to %s." % String(dock.current_action)); return
	InputMap.action_add_event(dock.current_action, ev)
	_save_action(dock.current_action)
	_refresh_events()
	_refresh_actions()
	dock._say("Added mouse button: %s to %s." % [pair[0], String(dock.current_action)])

func _add_joypad_button_event() -> void:
	if dock.current_action == &"":
		dock._say("Select an action first."); return
	var pair: Array = JOYPAD_BUTTONS[joypad_button_option.selected]
	var ev := InputEventJoypadButton.new()
	ev.button_index = pair[1]
	if _already_bound(ev):
		dock._say("That joypad button is already bound to %s." % String(dock.current_action)); return
	InputMap.action_add_event(dock.current_action, ev)
	_save_action(dock.current_action)
	_refresh_events()
	_refresh_actions()
	dock._say("Added joypad button: %s to %s." % [pair[0], String(dock.current_action)])

func _add_joypad_axis_event() -> void:
	if dock.current_action == &"":
		dock._say("Select an action first."); return
	var axis_pair: Array = JOYPAD_AXES[joypad_axis_option.selected]
	var dir: float = 1.0 if joypad_axis_dir_option.selected == 0 else -1.0
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis_pair[1]
	ev.axis_value = dir
	if _already_bound(ev):
		dock._say("That axis binding is already bound to %s." % String(dock.current_action)); return
	InputMap.action_add_event(dock.current_action, ev)
	_save_action(dock.current_action)
	_refresh_events()
	_refresh_actions()
	var dir_str := "positive" if dir > 0 else "negative"
	dock._say("Added joypad axis: %s %s to %s." % [axis_pair[0], dir_str, String(dock.current_action)])


func _already_bound(ev: InputEvent) -> bool:
	for existing in InputMap.action_get_events(dock.current_action):
		if ev is InputEventJoypadMotion and existing is InputEventJoypadMotion:
			var e := existing as InputEventJoypadMotion
			var n := ev as InputEventJoypadMotion
			if e.axis == n.axis and sign(e.axis_value) == sign(n.axis_value):
				return true
			continue
		if existing.is_match(ev, false):
			return true
	return false

func _btn_in(container: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	container.add_child(b)
