@tool
extends VBoxContainer

# Key bindings (when the grid has focus):
#   Arrow keys          Move cursor by 1 cell.
#   Shift + Arrows      Move by 10 cells (configurable).
#   Ctrl + Arrows       Jump to the next content boundary in that direction
#                       (the next cell whose tile differs from the current).
#   Home / End          Jump to cursor x=0 / to the rightmost used cell on this row.
#   Page Up / Page Down Jump to topmost / bottommost used cell on this column.
#   Enter or Space      Place the currently-selected palette tile at the cursor.
#   Delete or Backspace Erase the cell at the cursor.
#   R                   Set rectangle anchor at cursor.
#   F                   Fill rectangle between anchor and cursor with the palette tile.
#   E                   Erase rectangle between anchor and cursor.
#   G                   Prompt for "x,y" coordinates to jump to.
#   L                   Cycle active layer.
#   T                   Cycle through palette tiles (same as the palette dropdown).
#   W                   "What's here" - verbose read of the current cell across all layers.
#   B                   Read map bounds (used rectangle).

var announcer: AccessibleAnnouncer
var editor_interface: EditorInterface
var editor_undo_redo: EditorUndoRedoManager

# UI
var _layer_option: OptionButton
var _refresh_button: Button
var _palette_option: OptionButton
var _coord_label: Label
var _grid: Control
var _status: RichTextLabel
var _step_spin: SpinBox

# State
var _layers: Array[TileMapLayer] = []
var _active_layer: TileMapLayer = null
var _cursor: Vector2i = Vector2i.ZERO
var _anchor: Vector2i = Vector2i.ZERO
var _palette_source_id: int = -1
var _palette_coords: Vector2i = Vector2i.ZERO  # for atlas sources
var _palette_alt: int = 0
var _palette_tiles: Array = []  # Array of {source_id, coords, alt, label}
var _bookmarks: Dictionary = {}  # int slot (0–9) -> Vector2i
var atlas_tab  # set by dock.gd, used to auto-assign TileSet when layer has none


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_refresh_layers()


func grab_entry_focus() -> void:
	if _grid != null:
		_grid.grab_focus()


# ----- UI -----

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	# Top row: layer + refresh
	_make_label(self, "TileMapLayer:")
	var row1 := HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row1)

	_layer_option = OptionButton.new()
	_layer_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_layer_option, "Active TileMapLayer",
		"The TileMapLayer this tab edits. Populated from the currently edited scene.")
	_layer_option.item_selected.connect(_on_layer_selected)
	row1.add_child(_layer_option)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_set_a11y(_refresh_button, "Refresh layer list",
		"Re-scan the edited scene for TileMapLayer nodes.")
	_refresh_button.pressed.connect(_refresh_layers)
	row1.add_child(_refresh_button)

	# Palette row
	_make_label(self, "Palette tile (placed on Enter):")
	_palette_option = OptionButton.new()
	_palette_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_palette_option, "Palette tile",
		"The tile to place at the cursor when you press Enter.")
	_palette_option.item_selected.connect(_on_palette_selected)
	add_child(_palette_option)

	# Step size
	var step_row := HBoxContainer.new()
	add_child(step_row)
	_make_label(step_row, "Big-step size (Shift+Arrow):")
	_step_spin = SpinBox.new()
	_step_spin.min_value = 2
	_step_spin.max_value = 100
	_step_spin.value = 10
	_set_a11y(_step_spin, "Shift arrow step size",
		"How many cells Shift+Arrow moves the cursor.")
	step_row.add_child(_step_spin)

	# Cursor label
	_coord_label = Label.new()
	_coord_label.text = "Cursor: (0, 0)"
	add_child(_coord_label)

	# The grid a focusable Control that captures all keyboard input.
	_grid = Control.new()
	_grid.custom_minimum_size = Vector2(0, 120)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.focus_mode = Control.FOCUS_ALL
	_set_a11y(_grid, "Map grid",
		"Use arrow keys to move the cursor. Enter to place. Delete to erase. F to fill rectangle. G to go to coordinates. W for verbose read. B for map bounds.")
	_grid.gui_input.connect(_on_grid_input)
	_grid.focus_entered.connect(func(): announcer.speak("Grid focused. " + _announce_current_cell()))
	# Draw a focus hint so sighted collaborators see where the cursor is.
	_grid.draw.connect(_draw_grid)
	add_child(_grid)

	# Status / detail
	_status = RichTextLabel.new()
	_status.custom_minimum_size = Vector2(0, 80)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.fit_content = true
	_status.selection_enabled = true
	_status.bbcode_enabled = false
	_set_a11y(_status, "Cell status", "Detail on the current cell.")
	add_child(_status)


func _draw_grid() -> void:
	# Simple sighted-helper rendering: a focus-tinted panel with cursor text.
	var theme := get_theme()
	var color := Color(0.2, 0.5, 1.0, 0.2) if _grid.has_focus() else Color(0.2, 0.2, 0.2, 0.15)
	_grid.draw_rect(Rect2(Vector2.ZERO, _grid.size), color, true)
	var text := "Cursor: (%d, %d)\nLayer: %s\nFocus here, then use arrow keys." % [
		_cursor.x, _cursor.y,
		_active_layer.name if _active_layer != null else "(none)"
	]
	var font := get_theme_default_font()
	if font != null:
		var size := get_theme_default_font_size()
		_grid.draw_string(font, Vector2(8, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)


# ----- Layer population -----

func _refresh_layers() -> void:
	_layers.clear()
	_layer_option.clear()
	_active_layer = null

	var root: Node = null
	if editor_interface != null:
		root = editor_interface.get_edited_scene_root()

	if root == null:
		_layer_option.add_item("(no scene open)")
		_layer_option.disabled = true
		announcer.speak("No scene open in the editor.")
		return

	_collect_layers_recursive(root)
	if _layers.is_empty():
		_layer_option.add_item("(no TileMapLayer in scene)")
		_layer_option.disabled = true
		announcer.speak("No TileMapLayer nodes found in the edited scene.")
		return

	_layer_option.disabled = false
	for l in _layers:
		_layer_option.add_item(l.name)
	_layer_option.select(0)
	_on_layer_selected(0)
	announcer.speak("Found %d TileMapLayer(s)." % _layers.size())


func _collect_layers_recursive(node: Node) -> void:
	if node is TileMapLayer:
		_layers.append(node)
	for c in node.get_children():
		_collect_layers_recursive(c)


func _on_layer_selected(idx: int) -> void:
	if idx < 0 or idx >= _layers.size():
		return
	_active_layer = _layers[idx]
	_refresh_palette()
	_grid.queue_redraw()
	announcer.speak("Active layer %s." % _active_layer.name)
	_update_status()


# ----- Palette -----

func _refresh_palette() -> void:
	_palette_option.clear()
	_palette_tiles.clear()
	if _active_layer == null:
		_palette_option.add_item("(no active layer)")
		return

	# Autoassign from Atlas tab if this layer has no TileSet yet.
	if _active_layer.tile_set == null and atlas_tab != null and is_instance_valid(atlas_tab) \
			and atlas_tab._tileset != null:
		if editor_undo_redo != null:
			editor_undo_redo.create_action("Assign TileSet to %s" % _active_layer.name)
			editor_undo_redo.add_do_property(_active_layer, "tile_set", atlas_tab._tileset)
			editor_undo_redo.add_undo_property(_active_layer, "tile_set", null)
			editor_undo_redo.commit_action()
		else:
			_active_layer.tile_set = atlas_tab._tileset
		announcer.speak("TileSet auto-assigned to layer %s from Atlas tab." % _active_layer.name,
			AccessibleAnnouncer.Priority.ASSERTIVE)

	if _active_layer.tile_set == null:
		_palette_option.add_item("(no tileset, load one in the Atlas tab, then press Refresh)")
		announcer.speak("No TileSet available. Load or create a TileSet in the Atlas tab first, then press Refresh here.",
			AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var ts := _active_layer.tile_set
	for si in ts.get_source_count():
		var sid := ts.get_source_id(si)
		var src := ts.get_source(sid)
		if src is TileSetAtlasSource:
			var atlas := src as TileSetAtlasSource
			for t in atlas.get_tiles_count():
				var coords := atlas.get_tile_id(t)
				var label := _palette_label_for_atlas(ts, atlas, sid, coords)
				_palette_tiles.append({
					"source_id": sid, "coords": coords, "alt": 0, "label": label
				})
				_palette_option.add_item(label)
		elif src is TileSetScenesCollectionSource:
			var sc := src as TileSetScenesCollectionSource
			for t in sc.get_tiles_count():
				var scene_id := sc.get_scene_tile_id(t)
				var packed: PackedScene = sc.get_scene_tile_scene(scene_id)
				var path := packed.resource_path if packed != null else "(unset)"
				var label := "Scene %d: %s" % [scene_id, path.get_file()]
				_palette_tiles.append({
					"source_id": sid,
					"coords": Vector2i(scene_id, 0),
					"alt": 0,
					"label": label,
					"is_scene": true
				})
				_palette_option.add_item(label)
	if _palette_tiles.size() > 0:
		_palette_option.select(0)
		_on_palette_selected(0)


func _palette_label_for_atlas(ts: TileSet, atlas: TileSetAtlasSource, sid: int, coords: Vector2i) -> String:
	var layer_idx := -1
	for i in ts.get_custom_data_layers_count():
		if ts.get_custom_data_layer_name(i) == "name":
			layer_idx = i
			break
	if layer_idx >= 0:
		var data := atlas.get_tile_data(coords, 0)
		if data != null:
			var val = data.get_custom_data_by_layer_id(layer_idx)
			if val != null and str(val) != "":
				return "%s  [src %d, (%d,%d)]" % [str(val), sid, coords.x, coords.y]
	return "Source %d, (%d, %d)" % [sid, coords.x, coords.y]


func _on_palette_selected(idx: int) -> void:
	if idx < 0 or idx >= _palette_tiles.size():
		_palette_source_id = -1
		return
	var pt = _palette_tiles[idx]
	_palette_source_id = pt["source_id"]
	_palette_coords = pt["coords"]
	_palette_alt = pt["alt"]
	announcer.speak("Palette: %s" % pt["label"])


# ----- Keyboard handling -----

func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_key(event):
			_grid.accept_event()
	elif event is InputEventKey and event.pressed and event.echo:
		# Allow key repeat for arrow keys specifically.
		if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			if _handle_key(event):
				_grid.accept_event()


func _handle_key(event: InputEventKey) -> bool:
	var kc := event.keycode
	var shift := event.shift_pressed
	var ctrl := event.ctrl_pressed or event.meta_pressed

	var step := 1
	if shift:
		step = int(_step_spin.value)

	match kc:
		KEY_LEFT:
			if ctrl: _jump_content(Vector2i(-1, 0))
			else: _move_cursor(Vector2i(-step, 0))
			return true
		KEY_RIGHT:
			if ctrl: _jump_content(Vector2i(1, 0))
			else: _move_cursor(Vector2i(step, 0))
			return true
		KEY_UP:
			if ctrl: _jump_content(Vector2i(0, -1))
			else: _move_cursor(Vector2i(0, -step))
			return true
		KEY_DOWN:
			if ctrl: _jump_content(Vector2i(0, 1))
			else: _move_cursor(Vector2i(0, step))
			return true
		KEY_HOME:
			_jump_to_row_edge(-1)
			return true
		KEY_END:
			_jump_to_row_edge(1)
			return true
		KEY_PAGEUP:
			_jump_to_col_edge(-1)
			return true
		KEY_PAGEDOWN:
			_jump_to_col_edge(1)
			return true
		KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
			_place_at_cursor()
			return true
		KEY_DELETE, KEY_BACKSPACE:
			_erase_at_cursor()
			return true
		KEY_R:
			_anchor = _cursor
			announcer.speak("Anchor set at (%d, %d)." % [_anchor.x, _anchor.y],
				AccessibleAnnouncer.Priority.ASSERTIVE)
			return true
		KEY_F:
			_fill_rect(false)
			return true
		KEY_E:
			_fill_rect(true)
			return true
		KEY_G:
			_prompt_goto()
			return true
		KEY_L:
			_cycle_layer()
			return true
		KEY_T:
			_cycle_palette()
			return true
		KEY_W:
			announcer.speak(_verbose_read_current_cell(), AccessibleAnnouncer.Priority.ASSERTIVE)
			return true
		KEY_B:
			_announce_bounds()
			return true
		KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, \
		KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var slot := kc - KEY_0
			if ctrl:
				_set_bookmark(slot)
			else:
				_jump_bookmark(slot)
			return true
	return false


# ----- Cursor motions -----

func _move_cursor(delta: Vector2i) -> void:
	_cursor += delta
	_coord_label.text = "Cursor: (%d, %d)" % [_cursor.x, _cursor.y]
	_grid.queue_redraw()
	announcer.speak(_announce_current_cell())
	_update_status()


func _jump_content(direction: Vector2i) -> void:
	# Step one cell at a time until the tile differs from the starting cell,
	# or until we step 256 cells.
	if _active_layer == null:
		return
	var start_src := _active_layer.get_cell_source_id(_cursor)
	var start_coords := _active_layer.get_cell_atlas_coords(_cursor)
	var probe := _cursor
	for i in 256:
		probe += direction
		var psrc := _active_layer.get_cell_source_id(probe)
		var pcoords := _active_layer.get_cell_atlas_coords(probe)
		if psrc != start_src or pcoords != start_coords:
			_cursor = probe
			_coord_label.text = "Cursor: (%d, %d)" % [_cursor.x, _cursor.y]
			_grid.queue_redraw()
			announcer.speak("Jumped to boundary. " + _announce_current_cell())
			_update_status()
			return
	announcer.speak("No boundary found within 256 cells.",
		AccessibleAnnouncer.Priority.ASSERTIVE)


func _jump_to_row_edge(direction: int) -> void:
	if _active_layer == null:
		return
	var used := _active_layer.get_used_rect()
	if used.size == Vector2i.ZERO:
		announcer.speak("Layer is empty.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var target_x: int
	if direction < 0:
		target_x = used.position.x
	else:
		target_x = used.position.x + used.size.x - 1
	_cursor.x = target_x
	_coord_label.text = "Cursor: (%d, %d)" % [_cursor.x, _cursor.y]
	_grid.queue_redraw()
	announcer.speak(_announce_current_cell())
	_update_status()


func _jump_to_col_edge(direction: int) -> void:
	if _active_layer == null:
		return
	var used := _active_layer.get_used_rect()
	if used.size == Vector2i.ZERO:
		announcer.speak("Layer is empty.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var target_y: int
	if direction < 0:
		target_y = used.position.y
	else:
		target_y = used.position.y + used.size.y - 1
	_cursor.y = target_y
	_coord_label.text = "Cursor: (%d, %d)" % [_cursor.x, _cursor.y]
	_grid.queue_redraw()
	announcer.speak(_announce_current_cell())
	_update_status()


# ----- Edits -----

func _place_at_cursor() -> void:
	if _active_layer == null:
		announcer.speak("No active layer.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	if _palette_source_id < 0:
		announcer.speak("No palette tile selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var old_src := _active_layer.get_cell_source_id(_cursor)
	var old_coords := _active_layer.get_cell_atlas_coords(_cursor)
	var old_alt := _active_layer.get_cell_alternative_tile(_cursor)
	_do_set_cell(_cursor, _palette_source_id, _palette_coords, _palette_alt,
		old_src, old_coords, old_alt, "Place tile")
	announcer.speak("Placed at (%d, %d)." % [_cursor.x, _cursor.y])


func _erase_at_cursor() -> void:
	if _active_layer == null:
		return
	var old_src := _active_layer.get_cell_source_id(_cursor)
	if old_src < 0:
		announcer.speak("Already empty.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var old_coords := _active_layer.get_cell_atlas_coords(_cursor)
	var old_alt := _active_layer.get_cell_alternative_tile(_cursor)
	_do_set_cell(_cursor, -1, Vector2i(-1, -1), 0,
		old_src, old_coords, old_alt, "Erase tile")
	announcer.speak("Erased at (%d, %d)." % [_cursor.x, _cursor.y])


func _do_set_cell(
	pos: Vector2i,
	new_src: int, new_coords: Vector2i, new_alt: int,
	old_src: int, old_coords: Vector2i, old_alt: int,
	action_name: String
) -> void:
	if editor_undo_redo != null:
		editor_undo_redo.create_action(action_name)
		editor_undo_redo.add_do_method(_active_layer, "set_cell", pos, new_src, new_coords, new_alt)
		editor_undo_redo.add_undo_method(_active_layer, "set_cell", pos, old_src, old_coords, old_alt)
		editor_undo_redo.commit_action()
	else:
		_active_layer.set_cell(pos, new_src, new_coords, new_alt)
	_grid.queue_redraw()
	_update_status()


func _fill_rect(erase: bool) -> void:
	if _active_layer == null:
		return
	var r := Rect2i(
		Vector2i(mini(_anchor.x, _cursor.x), mini(_anchor.y, _cursor.y)),
		Vector2i(absi(_cursor.x - _anchor.x) + 1, absi(_cursor.y - _anchor.y) + 1)
	)
	if r.size.x * r.size.y > 10000:
		announcer.speak("Refusing to fill more than 10000 cells. Move cursor closer.",
			AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	if not erase and _palette_source_id < 0:
		announcer.speak("No palette tile selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return

	var verb := "Erase rectangle" if erase else "Fill rectangle"
	if editor_undo_redo != null:
		editor_undo_redo.create_action(verb)
	var cells_changed := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var p := Vector2i(x, y)
			var os := _active_layer.get_cell_source_id(p)
			var oc := _active_layer.get_cell_atlas_coords(p)
			var oa := _active_layer.get_cell_alternative_tile(p)
			if erase:
				if os < 0:
					continue
				if editor_undo_redo != null:
					editor_undo_redo.add_do_method(_active_layer, "set_cell", p, -1, Vector2i(-1, -1), 0)
					editor_undo_redo.add_undo_method(_active_layer, "set_cell", p, os, oc, oa)
				else:
					_active_layer.set_cell(p, -1, Vector2i(-1, -1), 0)
			else:
				if editor_undo_redo != null:
					editor_undo_redo.add_do_method(_active_layer, "set_cell", p,
						_palette_source_id, _palette_coords, _palette_alt)
					editor_undo_redo.add_undo_method(_active_layer, "set_cell", p, os, oc, oa)
				else:
					_active_layer.set_cell(p, _palette_source_id, _palette_coords, _palette_alt)
			cells_changed += 1
	if editor_undo_redo != null:
		editor_undo_redo.commit_action()
	_grid.queue_redraw()
	announcer.speak("%s: %d cells changed from (%d, %d) to (%d, %d)." % [
		verb, cells_changed, r.position.x, r.position.y,
		r.position.x + r.size.x - 1, r.position.y + r.size.y - 1
	], AccessibleAnnouncer.Priority.ASSERTIVE)
	_update_status()


# ----- Goto dialog -----

func _prompt_goto() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Go to coordinates"
	dlg.min_size = Vector2(300, 140)

	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	var lbl := Label.new()
	lbl.text = "Enter coordinates as x,y (e.g. 12,5):"
	vb.add_child(lbl)

	var field := LineEdit.new()
	field.placeholder_text = "12,5"
	_set_a11y(field, "Coordinates", "Target cell coordinates as x comma y.")
	vb.add_child(field)

	dlg.get_ok_button().text = "Go"
	add_child(dlg)
	dlg.popup_centered()
	field.grab_focus()

	dlg.confirmed.connect(func():
		var text := field.text.strip_edges()
		var parts := text.split(",")
		if parts.size() != 2:
			announcer.speak("Invalid coordinates.", AccessibleAnnouncer.Priority.ASSERTIVE)
			dlg.queue_free()
			return
		_cursor = Vector2i(int(parts[0]), int(parts[1]))
		_coord_label.text = "Cursor: (%d, %d)" % [_cursor.x, _cursor.y]
		_grid.queue_redraw()
		announcer.speak(_announce_current_cell())
		_update_status()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())


# ----- Layer / palette cycling -----

func _cycle_layer() -> void:
	if _layer_option.item_count == 0:
		return
	var next := (_layer_option.selected + 1) % _layer_option.item_count
	_layer_option.select(next)
	_on_layer_selected(next)


func _cycle_palette() -> void:
	if _palette_option.item_count == 0:
		return
	var next := (_palette_option.selected + 1) % _palette_option.item_count
	_palette_option.select(next)
	_on_palette_selected(next)


# ----- Announcements -----

func _announce_current_cell() -> String:
	if _active_layer == null:
		return "No active layer. Cursor at (%d, %d)." % [_cursor.x, _cursor.y]
	var src := _active_layer.get_cell_source_id(_cursor)
	if src < 0:
		return "(%d, %d) empty." % [_cursor.x, _cursor.y]
	var coords := _active_layer.get_cell_atlas_coords(_cursor)
	var label := _describe_tile_short(src, coords)
	return "(%d, %d) %s." % [_cursor.x, _cursor.y, label]


func _verbose_read_current_cell() -> String:
	# Reads every TileMapLayer at the current cursor cell, plus custom data.
	var lines: Array[String] = []
	lines.append("Cell (%d, %d)." % [_cursor.x, _cursor.y])
	for l in _layers:
		var src := l.get_cell_source_id(_cursor)
		if src < 0:
			lines.append("Layer %s: empty." % l.name)
			continue
		var coords := l.get_cell_atlas_coords(_cursor)
		var parts: Array[String] = []
		parts.append(_describe_tile_short(src, coords))
		# Custom data
		var ts := l.tile_set
		if ts != null:
			var atlas := ts.get_source(src)
			if atlas is TileSetAtlasSource:
				var data := (atlas as TileSetAtlasSource).get_tile_data(coords, 0)
				if data != null:
					for i in ts.get_custom_data_layers_count():
						var lname := ts.get_custom_data_layer_name(i)
						var val = data.get_custom_data_by_layer_id(i)
						if val != null and str(val) != "":
							parts.append("%s=%s" % [lname, str(val)])
		lines.append("Layer %s: %s" % [l.name, ", ".join(parts)])
	return " ".join(lines)


func _describe_tile_short(source_id: int, coords: Vector2i) -> String:
	if _active_layer == null or _active_layer.tile_set == null:
		return "src %d, (%d, %d)" % [source_id, coords.x, coords.y]
	var ts := _active_layer.tile_set
	var src := ts.get_source(source_id)
	if src is TileSetAtlasSource:
		var atlas := src as TileSetAtlasSource
		var layer_idx := -1
		for i in ts.get_custom_data_layers_count():
			if ts.get_custom_data_layer_name(i) == "name":
				layer_idx = i
				break
		if layer_idx >= 0:
			var data := atlas.get_tile_data(coords, 0)
			if data != null:
				var val = data.get_custom_data_by_layer_id(layer_idx)
				if val != null and str(val) != "":
					return str(val)
		return "src %d (%d,%d)" % [source_id, coords.x, coords.y]
	elif src is TileSetScenesCollectionSource:
		return "scene tile %d" % coords.x
	return "src %d" % source_id


func _announce_bounds() -> void:
	if _active_layer == null:
		announcer.speak("No active layer.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var r := _active_layer.get_used_rect()
	if r.size == Vector2i.ZERO:
		announcer.speak("Layer %s is empty." % _active_layer.name,
			AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	announcer.speak("Layer %s bounds: (%d, %d) to (%d, %d), size %d by %d." % [
		_active_layer.name, r.position.x, r.position.y,
		r.position.x + r.size.x - 1, r.position.y + r.size.y - 1,
		r.size.x, r.size.y
	], AccessibleAnnouncer.Priority.ASSERTIVE)


func _update_status() -> void:
	if _active_layer == null:
		_status.text = "No active layer."
		return
	var r := _active_layer.get_used_rect()
	var used_count := _active_layer.get_used_cells().size()
	var lines: Array[String] = []
	lines.append("Layer: %s" % _active_layer.name)
	if r.size != Vector2i.ZERO:
		lines.append("Used rect: (%d, %d) to (%d, %d)" % [
			r.position.x, r.position.y,
			r.position.x + r.size.x - 1, r.position.y + r.size.y - 1
		])
	else:
		lines.append("Used rect: (empty)")
	lines.append("Used cells: %d" % used_count)
	lines.append("Cursor: (%d, %d)" % [_cursor.x, _cursor.y])
	lines.append("Anchor: (%d, %d)" % [_anchor.x, _anchor.y])
	if _bookmarks.is_empty():
		lines.append("Bookmarks: none")
	else:
		var bm_parts: Array[String] = []
		var slots := _bookmarks.keys()
		slots.sort()
		for s in slots:
			var v: Vector2i = _bookmarks[s]
			bm_parts.append("%d=(%d,%d)" % [s, v.x, v.y])
		lines.append("Bookmarks: " + "  ".join(bm_parts))
	_status.text = "\n".join(lines)


# ----- Bookmarks -----

func _set_bookmark(slot: int) -> void:
	_bookmarks[slot] = _cursor
	announcer.speak("Bookmark %d set at (%d, %d)." % [slot, _cursor.x, _cursor.y],
		AccessibleAnnouncer.Priority.ASSERTIVE)
	_update_status()


func _jump_bookmark(slot: int) -> void:
	if not _bookmarks.has(slot):
		announcer.speak("Bookmark %d not set." % slot,
			AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	_cursor = _bookmarks[slot]
	_coord_label.text = "Cursor: (%d, %d)" % [_cursor.x, _cursor.y]
	_grid.queue_redraw()
	announcer.speak("Jumped to bookmark %d. " % slot + _announce_current_cell(),
		AccessibleAnnouncer.Priority.ASSERTIVE)
	_update_status()


# ----- Helpers -----

func _make_label(parent: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l


func _set_a11y(c: Control, name: String, desc: String = "") -> void:
	if c.has_method(&"set_accessibility_name"):
		c.call(&"set_accessibility_name", name)
	if not desc.is_empty() and c.has_method(&"set_accessibility_description"):
		c.call(&"set_accessibility_description", desc)
