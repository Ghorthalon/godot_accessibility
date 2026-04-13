@tool
class_name NavControl
extends Panel

## Focusable keyboard navigation widget for the spatial cursor.
## focus, then use:
##   Arrow keys         move cursor West/East/North/South
##   A / Z              move cursor Up / Down
##   Ctrl + above       jump cursor to nearest entity in that direction
##   Shift+A / Shift+Z  increase / decrease step size
##   Shift+Arrow        snap cursor to wall in that direction
##   F                  snap cursor to floor

signal move_cursor(axis: String)   # "-x" "+x" "-y" "+y" "-z" "+z"
signal jump_entity(axis: String)
signal step_up
signal step_down
signal snap_floor
signal snap_wall(side: String)     # "north" "south" "east" "west"

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

	# Shift → step size (A/Z) or snap to wall (arrow keys), no Ctrl
	if key.shift_pressed and not key.ctrl_pressed:
		match key.keycode:
			KEY_A:     accept_event(); step_up.emit()
			KEY_Z:     accept_event(); step_down.emit()
			KEY_LEFT:  accept_event(); snap_wall.emit("west")
			KEY_RIGHT: accept_event(); snap_wall.emit("east")
			KEY_UP:    accept_event(); snap_wall.emit("north")
			KEY_DOWN:  accept_event(); snap_wall.emit("south")
		return

	# Ctrl+direction → jump to entity (no Shift)
	if key.ctrl_pressed and not key.shift_pressed:
		match key.keycode:
			KEY_LEFT:  accept_event(); jump_entity.emit("-x")
			KEY_RIGHT: accept_event(); jump_entity.emit("+x")
			KEY_UP:    accept_event(); jump_entity.emit("-z")
			KEY_DOWN:  accept_event(); jump_entity.emit("+z")
			KEY_A:     accept_event(); jump_entity.emit("+y")
			KEY_Z:     accept_event(); jump_entity.emit("-y")
		return

	# Plain direction keys → move cursor; F → snap to floor
	if not key.ctrl_pressed and not key.shift_pressed:
		match key.keycode:
			KEY_LEFT:  accept_event(); move_cursor.emit("-x")
			KEY_RIGHT: accept_event(); move_cursor.emit("+x")
			KEY_UP:    accept_event(); move_cursor.emit("-z")
			KEY_DOWN:  accept_event(); move_cursor.emit("+z")
			KEY_A:     accept_event(); move_cursor.emit("+y")
			KEY_Z:     accept_event(); move_cursor.emit("-y")
			KEY_F:     accept_event(); snap_floor.emit()
