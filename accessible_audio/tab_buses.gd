@tool
extends VBoxContainer

var dock  # reference to parent dock (dock.gd)

var bus_list: ItemList
var vol_spin: SpinBox
var mute_btn: Button
var solo_btn: Button
var send_option: OptionButton
var bus_name_edit: LineEdit

func _ready() -> void:
	var lbl := Label.new()
	lbl.text = "Audio Buses"
	add_child(lbl)

	bus_list = ItemList.new()
	bus_list.custom_minimum_size = Vector2(0, 200)
	bus_list.item_selected.connect(_on_select)
	add_child(bus_list)

	_btn("Refresh bus list", _refresh)

	add_child(HSeparator.new())

	var ctl_lbl := Label.new()
	ctl_lbl.text = "Selected bus controls:"
	add_child(ctl_lbl)

	var vol_row := HBoxContainer.new()
	var vol_lbl := Label.new()
	vol_lbl.text = "Volume (dB):"
	vol_row.add_child(vol_lbl)
	vol_spin = SpinBox.new()
	vol_spin.min_value = -80.0
	vol_spin.max_value = 6.0
	vol_spin.step = 0.5
	vol_spin.value = 0.0
	vol_spin.accessibility_name = "Volume in decibels"
	vol_row.add_child(vol_spin)
	add_child(vol_row)

	var ms_row := HBoxContainer.new()
	mute_btn = Button.new()
	mute_btn.text = "Mute"
	mute_btn.toggle_mode = true
	mute_btn.accessibility_name = "Mute selected bus"
	ms_row.add_child(mute_btn)
	solo_btn = Button.new()
	solo_btn.text = "Solo"
	solo_btn.toggle_mode = true
	solo_btn.accessibility_name = "Solo selected bus"
	ms_row.add_child(solo_btn)
	add_child(ms_row)

	var send_row := HBoxContainer.new()
	var send_lbl := Label.new()
	send_lbl.text = "Send to:"
	send_row.add_child(send_lbl)
	send_option = OptionButton.new()
	send_option.accessibility_name = "Send bus output to"
	send_row.add_child(send_option)
	add_child(send_row)

	_btn("Apply changes", _apply)

	add_child(HSeparator.new())

	var name_lbl := Label.new()
	name_lbl.text = "Bus name (for add / rename):"
	add_child(name_lbl)
	bus_name_edit = LineEdit.new()
	bus_name_edit.placeholder_text = "e.g. Music, SFX, Ambient"
	bus_name_edit.accessibility_name = "Bus name"
	add_child(bus_name_edit)

	_btn("Add bus", _add_bus)
	_btn("Remove selected bus", _remove_bus)

	var move_row := HBoxContainer.new()
	var up := Button.new()
	up.text = "Move bus up"
	up.pressed.connect(_move_bus_up)
	move_row.add_child(up)
	var dn := Button.new()
	dn.text = "Move bus down"
	dn.pressed.connect(_move_bus_down)
	move_row.add_child(dn)
	add_child(move_row)

	_btn("Rename selected bus", _rename_bus)

	_refresh()

# --- List ---

func _refresh() -> void:
	bus_list.clear()
	for i in AudioServer.bus_count:
		var name_str := AudioServer.get_bus_name(i)
		var vol := AudioServer.get_bus_volume_db(i)
		var flags := ""
		if AudioServer.is_bus_mute(i):
			flags += " [MUTE]"
		if AudioServer.is_bus_solo(i):
			flags += " [SOLO]"
		var send_str := AudioServer.get_bus_send(i)
		var send_display := (" → %s" % send_str) if send_str != "" else ""
		bus_list.add_item("%s  vol: %.1f dB%s%s" % [name_str, vol, flags, send_display])
		bus_list.set_item_metadata(bus_list.item_count - 1, i)

	# Keep the previously selected bus selected if it still exists
	if dock.current_bus_idx >= 0 and dock.current_bus_idx < AudioServer.bus_count:
		bus_list.select(dock.current_bus_idx)

func _on_select(i: int) -> void:
	dock.current_bus_idx = bus_list.get_item_metadata(i)
	_populate_controls(dock.current_bus_idx)
	dock._say("Selected bus: %s." % AudioServer.get_bus_name(dock.current_bus_idx))
	# Notify the effects tab to refresh
	if is_instance_valid(dock.tab_effects):
		dock.tab_effects._refresh()

func _populate_controls(idx: int) -> void:
	vol_spin.value = AudioServer.get_bus_volume_db(idx)
	mute_btn.button_pressed = AudioServer.is_bus_mute(idx)
	solo_btn.button_pressed = AudioServer.is_bus_solo(idx)

	send_option.clear()
	var current_send := AudioServer.get_bus_send(idx)
	var sel := 0
	for j in AudioServer.bus_count:
		if j == idx:
			continue
		var bname := AudioServer.get_bus_name(j)
		send_option.add_item(bname)
		if bname == current_send:
			sel = send_option.item_count - 1
	send_option.selected = sel

# --- Mutations ---

func _apply() -> void:
	var idx: int = dock.current_bus_idx
	if idx < 0: dock._say("No bus selected."); return
	AudioServer.set_bus_volume_db(idx, vol_spin.value)
	AudioServer.set_bus_mute(idx, mute_btn.button_pressed)
	AudioServer.set_bus_solo(idx, solo_btn.button_pressed)
	if send_option.item_count > 0:
		AudioServer.set_bus_send(idx, send_option.get_item_text(send_option.selected))
	_save_layout()
	_refresh()
	var mute_str := " muted" if mute_btn.button_pressed else ""
	var solo_str := " solo" if solo_btn.button_pressed else ""
	dock._say("Applied: %s, %.1f dB%s%s." % [
		AudioServer.get_bus_name(idx), vol_spin.value, mute_str, solo_str])

func _add_bus() -> void:
	var bus_name := bus_name_edit.text.strip_edges()
	if bus_name.is_empty(): dock._say("Enter a name for the new bus."); return
	AudioServer.add_bus(-1)
	var new_idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(new_idx, bus_name)
	_save_layout()
	_refresh()
	dock._say("Added bus: %s." % bus_name)

func _remove_bus() -> void:
	var idx: int = dock.current_bus_idx
	if idx < 0: dock._say("No bus selected."); return
	if idx == 0: dock._say("Cannot remove the Master bus."); return
	var removed_name := AudioServer.get_bus_name(idx)
	AudioServer.remove_bus(idx)
	dock.current_bus_idx = -1
	_save_layout()
	_refresh()
	dock._say("Removed bus: %s." % removed_name)

func _move_bus_up() -> void:
	var idx: int = dock.current_bus_idx
	if idx <= 0: dock._say("Cannot move bus further up."); return
	AudioServer.move_bus(idx, idx - 1)
	dock.current_bus_idx = idx - 1
	_save_layout()
	_refresh()
	bus_list.select(dock.current_bus_idx)
	dock._say("Moved bus up: now position %d." % dock.current_bus_idx)

func _move_bus_down() -> void:
	var idx: int = dock.current_bus_idx
	if idx < 0 or idx >= AudioServer.bus_count - 1:
		dock._say("Cannot move bus further down."); return
	AudioServer.move_bus(idx, idx + 1)
	dock.current_bus_idx = idx + 1
	_save_layout()
	_refresh()
	bus_list.select(dock.current_bus_idx)
	dock._say("Moved bus down: now position %d." % dock.current_bus_idx)

func _rename_bus() -> void:
	var idx: int = dock.current_bus_idx
	if idx < 0: dock._say("No bus selected."); return
	var new_name := bus_name_edit.text.strip_edges()
	if new_name.is_empty(): dock._say("Enter the new name in the bus name field."); return
	var old_name := AudioServer.get_bus_name(idx)
	AudioServer.set_bus_name(idx, new_name)
	_save_layout()
	_refresh()
	dock._say("Renamed bus from %s to %s." % [old_name, new_name])

# --- Helpers ---

func _save_layout() -> void:
	var path: String = ProjectSettings.get_setting(
		"audio/buses/default_bus_layout", "res://default_bus_layout.tres")
	ResourceSaver.save(AudioServer.generate_bus_layout(), path)

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	add_child(b)
