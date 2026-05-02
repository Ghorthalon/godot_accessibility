@tool
class_name NavControl
extends Panel

## Focusable keyboard navigation widget for the spatial cursor.
## focus, then use:
##   Arrow keys              move cursor West/East/North/South
##   A / Z                   move cursor Up / Down
##   Ctrl + above            jump cursor to nearest entity in that direction
##   Shift+A / Shift+Z       increase / decrease step size
##   Shift+Arrow             snap cursor to wall in that direction
##   F                       snap cursor to floor
##   R                       snap cursor to current room
##   P                       probe distances (6 directions)
##   L                       report cursor location
##   Ctrl+R                  new standalone room at cursor
##   Ctrl+D                  punch door at cursor (nearest wall)
##   Ctrl+1 / Ctrl+2 / Ctrl+3   set corner A / B / place room from corners
##   Shift+F                 nudge selected node to floor
##   Shift+W                 snap selected node to nearest wall
##   Shift+D                 snap selected node to nearest doorway
##   Shift+C                 center selected node E W
##   Shift+V                 center selected node N S
##   Ctrl+Shift+3            add zone to floor

signal move_cursor(axis: String)   # "-x" "+x" "-y" "+y" "-z" "+z"
signal jump_entity(axis: String)
signal step_up
signal step_down
signal snap_floor
signal snap_wall(side: String)     # "north" "south" "east" "west"
signal snap_room
signal probe
signal report_location
signal new_standalone_room
signal punch_door_at_cursor
signal corner_a
signal corner_b
signal place_room_from_corners
signal nudge_node_to_floor
signal snap_node_to_wall
signal snap_node_to_doorway
signal center_node_ew
signal center_node_ns
signal add_zone_to_floor

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, 40)
	var lbl := Label.new()
	lbl.text = "Keyboard nav (click to focus)"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(lbl)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.4, 0.8, 0.15)
	add_theme_stylebox_override("panel", style)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	var key := event as InputEventKey

	# Ctrl+Shift actions
	if key.ctrl_pressed and key.shift_pressed:
		match key.keycode:
			KEY_1: accept_event(); corner_a.emit()
			KEY_2: accept_event(); corner_b.emit()
			KEY_3: accept_event(); add_zone_to_floor.emit()
		return

	# Shift  step size (A/Z), snap to wall (arrow keys), node snap (F/W/D/C/V), no Ctrl
	if key.shift_pressed and not key.ctrl_pressed:
		match key.keycode:
			KEY_A:     accept_event(); step_up.emit()
			KEY_Z:     accept_event(); step_down.emit()
			KEY_LEFT:  accept_event(); snap_wall.emit("west")
			KEY_RIGHT: accept_event(); snap_wall.emit("east")
			KEY_UP:    accept_event(); snap_wall.emit("north")
			KEY_DOWN:  accept_event(); snap_wall.emit("south")
			KEY_F:     accept_event(); nudge_node_to_floor.emit()
			KEY_W:     accept_event(); snap_node_to_wall.emit()
			KEY_D:     accept_event(); snap_node_to_doorway.emit()
			KEY_C:     accept_event(); center_node_ew.emit()
			KEY_V:     accept_event(); center_node_ns.emit()
		return

	# Ctrl  jump to entity, room creation, door punching (no Shift)
	if key.ctrl_pressed and not key.shift_pressed:
		match key.keycode:
			KEY_LEFT:  accept_event(); jump_entity.emit("-x")
			KEY_RIGHT: accept_event(); jump_entity.emit("+x")
			KEY_UP:    accept_event(); jump_entity.emit("-z")
			KEY_DOWN:  accept_event(); jump_entity.emit("+z")
			KEY_A:     accept_event(); jump_entity.emit("+y")
			KEY_Z:     accept_event(); jump_entity.emit("-y")
			KEY_R:     accept_event(); new_standalone_room.emit()
			KEY_D:     accept_event(); punch_door_at_cursor.emit()
			KEY_1:     accept_event(); corner_a.emit()
			KEY_2:     accept_event(); corner_b.emit()
			KEY_3:     accept_event(); place_room_from_corners.emit()
		return

	# Plain keys  move cursor, snap to floor/room, probe, report location
	if not key.ctrl_pressed and not key.shift_pressed:
		match key.keycode:
			KEY_LEFT:  accept_event(); move_cursor.emit("-x")
			KEY_RIGHT: accept_event(); move_cursor.emit("+x")
			KEY_UP:    accept_event(); move_cursor.emit("-z")
			KEY_DOWN:  accept_event(); move_cursor.emit("+z")
			KEY_A:     accept_event(); move_cursor.emit("+y")
			KEY_Z:     accept_event(); move_cursor.emit("-y")
			KEY_F:     accept_event(); snap_floor.emit()
			KEY_R:     accept_event(); snap_room.emit()
			KEY_P:     accept_event(); probe.emit()
			KEY_L:     accept_event(); report_location.emit()
