@tool
extends VBoxContainer

const _LAYER_TYPES: Array = [
	["String", TYPE_STRING],
	["Bool",   TYPE_BOOL],
	["Int",    TYPE_INT],
	["Float",  TYPE_FLOAT],
]

var announcer: AccessibleAnnouncer
var editor_interface: EditorInterface
var editor_undo_redo: EditorUndoRedoManager

var _tileset: TileSet
var _tileset_path: String = ""

# UI controls
var _status_label: Label
var _load_path_field: LineEdit
var _load_button: Button
var _pull_selection_button: Button
var _layer_list: ItemList
var _source_option: OptionButton
var _tile_list: ItemList
var _tile_info_label: RichTextLabel
var _custom_data_container: VBoxContainer
var _physics_layer_list: ItemList
var _collision_container: VBoxContainer
var _add_scene_tile_button: Button
var _remove_tile_button: Button

# Tracked for announcements
var _source_ids: Array[int] = []


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_build_ui()
	_refresh_status()


func grab_entry_focus() -> void:
	if _source_option != null:
		_source_option.grab_focus()


# ----- UI construction -----

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)

	# --- TileSet lifecycle ---
	_make_label(root, "TileSet:")
	var ts_row := HBoxContainer.new()
	ts_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(ts_row)

	var new_ts_btn := Button.new()
	new_ts_btn.text = "New TileSet..."
	_set_a11y(new_ts_btn, "New TileSet",
		"Create a new empty TileSet and save it to a .tres path.")
	new_ts_btn.pressed.connect(_on_new_tileset_pressed)
	ts_row.add_child(new_ts_btn)

	var save_ts_btn := Button.new()
	save_ts_btn.text = "Save TileSet"
	_set_a11y(save_ts_btn, "Save TileSet",
		"Save the current TileSet back to its .tres file on disk.")
	save_ts_btn.pressed.connect(_on_save_tileset_pressed)
	ts_row.add_child(save_ts_btn)

	_status_label = _make_label(root, "No TileSet loaded.")
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Load controls
	_make_label(root, "Load existing TileSet from path (.tres):")
	var load_row := HBoxContainer.new()
	load_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(load_row)

	_load_path_field = LineEdit.new()
	_load_path_field.placeholder_text = "res://path/to/your_tileset.tres"
	_load_path_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_load_path_field, "TileSet resource path",
		"Absolute project path to a TileSet .tres file.")
	_load_path_field.text_submitted.connect(_on_load_path_submitted)
	load_row.add_child(_load_path_field)

	_load_button = Button.new()
	_load_button.text = "Load"
	_set_a11y(_load_button, "Load TileSet",
		"Load the TileSet resource from the path above.")
	_load_button.pressed.connect(_on_load_pressed)
	load_row.add_child(_load_button)

	_pull_selection_button = Button.new()
	_pull_selection_button.text = "Use TileSet from selected TileMapLayer"
	_set_a11y(_pull_selection_button, "Use selected TileMapLayer's TileSet",
		"Take the TileSet from whichever TileMapLayer is currently selected in the scene.")
	_pull_selection_button.pressed.connect(_on_pull_selection_pressed)
	root.add_child(_pull_selection_button)

	var assign_btn := Button.new()
	assign_btn.text = "Assign this TileSet to selected TileMapLayer"
	_set_a11y(assign_btn, "Assign TileSet to selected TileMapLayer",
		"Set the currently loaded TileSet onto whichever TileMapLayer is selected in the scene. Required before the Map tab can use it.")
	assign_btn.pressed.connect(_on_assign_to_layer_pressed)
	root.add_child(assign_btn)

	# --- Custom data layers ---
	_make_label(root, "Custom data layers:")
	_layer_list = ItemList.new()
	_layer_list.custom_minimum_size = Vector2(0, 80)
	_layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_layer_list, "Custom data layer list",
		"Layers defined on this TileSet. Each tile can store a value per layer.")
	root.add_child(_layer_list)

	var layer_buttons := HBoxContainer.new()
	root.add_child(layer_buttons)

	var add_layer_btn := Button.new()
	add_layer_btn.text = "Add layer..."
	_set_a11y(add_layer_btn, "Add custom data layer",
		"Add a new named custom data layer to this TileSet. Prompts for name and type.")
	add_layer_btn.pressed.connect(_on_add_layer_pressed)
	layer_buttons.add_child(add_layer_btn)

	var remove_layer_btn := Button.new()
	remove_layer_btn.text = "Remove layer"
	_set_a11y(remove_layer_btn, "Remove selected custom data layer",
		"Remove the selected custom data layer from this TileSet.")
	remove_layer_btn.pressed.connect(_on_remove_layer_pressed)
	layer_buttons.add_child(remove_layer_btn)

	# --- Physics layers ---
	_make_label(root, "Physics layers:")
	_physics_layer_list = ItemList.new()
	_physics_layer_list.custom_minimum_size = Vector2(0, 60)
	_physics_layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_physics_layer_list, "Physics layer list",
		"Physics layers defined on this TileSet. Each tile can have collision polygons per layer.")
	root.add_child(_physics_layer_list)

	var phys_buttons := HBoxContainer.new()
	root.add_child(phys_buttons)

	var add_phys_btn := Button.new()
	add_phys_btn.text = "Add physics layer"
	_set_a11y(add_phys_btn, "Add physics layer",
		"Add a new physics layer to this TileSet. Tiles can then have collision polygons on it.")
	add_phys_btn.pressed.connect(_on_add_physics_layer_pressed)
	phys_buttons.add_child(add_phys_btn)

	var remove_phys_btn := Button.new()
	remove_phys_btn.text = "Remove physics layer"
	_set_a11y(remove_phys_btn, "Remove selected physics layer",
		"Remove the selected physics layer from this TileSet. All tile collision data on it is lost.")
	remove_phys_btn.pressed.connect(_on_remove_physics_layer_pressed)
	phys_buttons.add_child(remove_phys_btn)

	# --- Source chooser ---
	_make_label(root, "Source:")
	_source_option = OptionButton.new()
	_source_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(_source_option, "TileSet source",
		"The source within the TileSet to browse. Sources can be atlas-based or scene-collection-based.")
	_source_option.item_selected.connect(_on_source_selected)
	root.add_child(_source_option)

	var source_buttons := HBoxContainer.new()
	root.add_child(source_buttons)

	var add_atlas_src_btn := Button.new()
	add_atlas_src_btn.text = "Add atlas source..."
	_set_a11y(add_atlas_src_btn, "Add atlas source",
		"Add a new TileSetAtlasSource to this TileSet. Prompts for tile size. Texture is optional.")
	add_atlas_src_btn.pressed.connect(_on_add_atlas_source_pressed)
	source_buttons.add_child(add_atlas_src_btn)

	var remove_src_btn := Button.new()
	remove_src_btn.text = "Remove source"
	_set_a11y(remove_src_btn, "Remove selected source",
		"Remove the currently selected source from this TileSet.")
	remove_src_btn.pressed.connect(_on_remove_source_pressed)
	source_buttons.add_child(remove_src_btn)

	# --- Tile list ---
	_make_label(root, "Tiles:")
	_tile_list = ItemList.new()
	_tile_list.custom_minimum_size = Vector2(0, 180)
	_tile_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_list.auto_height = false
	_set_a11y(_tile_list, "Tile list",
		"Tiles in the selected source. Use arrow keys to navigate.")
	_tile_list.item_selected.connect(_on_tile_selected)
	root.add_child(_tile_list)

	var tile_buttons := HBoxContainer.new()
	root.add_child(tile_buttons)

	var add_atlas_tile_btn := Button.new()
	add_atlas_tile_btn.text = "Add atlas tile..."
	_set_a11y(add_atlas_tile_btn, "Add tile to atlas source",
		"Add a new tile to the current atlas source. Coordinates are auto-assigned. Prompts for a name.")
	add_atlas_tile_btn.pressed.connect(_on_add_atlas_tile_pressed)
	tile_buttons.add_child(add_atlas_tile_btn)

	_add_scene_tile_button = Button.new()
	_add_scene_tile_button.text = "Add scene tile..."
	_set_a11y(_add_scene_tile_button, "Add scene to scene-collection source",
		"Only valid when the current source is a scene collection. Prompts for a scene path.")
	_add_scene_tile_button.pressed.connect(_on_add_scene_tile_pressed)
	tile_buttons.add_child(_add_scene_tile_button)

	_remove_tile_button = Button.new()
	_remove_tile_button.text = "Remove tile"
	_set_a11y(_remove_tile_button, "Remove selected tile",
		"Remove the selected tile from the current source (works for atlas and scene-collection sources).")
	_remove_tile_button.pressed.connect(_on_remove_tile_pressed)
	tile_buttons.add_child(_remove_tile_button)

	# --- Tile detail ---
	_make_label(root, "Details:")
	_tile_info_label = RichTextLabel.new()
	_tile_info_label.custom_minimum_size = Vector2(0, 80)
	_tile_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_info_label.bbcode_enabled = false
	_tile_info_label.fit_content = true
	_tile_info_label.selection_enabled = true
	_set_a11y(_tile_info_label, "Tile details",
		"Summary of the selected tile's metadata and custom data.")
	root.add_child(_tile_info_label)

	# --- Custom data editor ---
	_make_label(root, "Custom data (edits apply on Enter):")
	_custom_data_container = VBoxContainer.new()
	_custom_data_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_custom_data_container)

	# --- Collision editor ---
	_make_label(root, "Collision (per physics layer):")
	_collision_container = VBoxContainer.new()
	_collision_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_collision_container)


# ----- TileSet lifecycle -----

func _on_new_tileset_pressed() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "New TileSet"
	dlg.min_size = Vector2(420, 140)

	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	var lbl := Label.new()
	lbl.text = "Save path for the new TileSet (.tres):"
	vb.add_child(lbl)

	var field := LineEdit.new()
	field.placeholder_text = "res://tilesets/my_tileset.tres"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(field, "New TileSet save path",
		"Project path where the new TileSet .tres will be written. Must end in .tres.")
	vb.add_child(field)

	dlg.get_ok_button().text = "Create"
	add_child(dlg)
	dlg.popup_centered()
	field.grab_focus()

	dlg.confirmed.connect(func():
		var path := field.text.strip_edges()
		if path.is_empty() or not path.ends_with(".tres"):
			announcer.speak("Path must end in .tres.", AccessibleAnnouncer.Priority.ASSERTIVE)
			dlg.queue_free()
			return
		var ts := TileSet.new()
		var err := ResourceSaver.save(ts, path)
		if err != OK:
			announcer.speak("Failed to save TileSet (error %d)." % err,
				AccessibleAnnouncer.Priority.ASSERTIVE)
			dlg.queue_free()
			return
		_tileset = ts
		_tileset_path = path
		announcer.speak("Created and loaded new TileSet at %s." % path.get_file(),
			AccessibleAnnouncer.Priority.ASSERTIVE)
		_refresh_all()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())


func _on_save_tileset_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	if _tileset_path.is_empty():
		announcer.speak("TileSet has no path. Load it from a file first.",
			AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var err := ResourceSaver.save(_tileset, _tileset_path)
	if err != OK:
		announcer.speak("Save failed (error %d)." % err, AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	announcer.speak("Saved TileSet to %s." % _tileset_path.get_file(),
		AccessibleAnnouncer.Priority.ASSERTIVE)


# ----- TileSet loading -----

func _on_load_pressed() -> void:
	_load_from_path(_load_path_field.text.strip_edges())


func _on_load_path_submitted(text: String) -> void:
	_load_from_path(text.strip_edges())


func _load_from_path(path: String) -> void:
	if path.is_empty():
		announcer.speak("No path entered.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	if not ResourceLoader.exists(path):
		announcer.speak("Path not found: %s" % path, AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var res := load(path)
	if not (res is TileSet):
		announcer.speak("Resource at %s is not a TileSet." % path, AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	_tileset = res
	_tileset_path = path
	announcer.speak("Loaded TileSet %s." % path.get_file(), AccessibleAnnouncer.Priority.ASSERTIVE)
	_refresh_all()


func _on_pull_selection_pressed() -> void:
	if editor_interface == null:
		announcer.speak("No editor interface available.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var selection := editor_interface.get_selection()
	var nodes := selection.get_selected_nodes()
	for n in nodes:
		if n is TileMapLayer and n.tile_set != null:
			_tileset = n.tile_set
			_tileset_path = n.tile_set.resource_path
			announcer.speak("Loaded TileSet from %s." % n.name, AccessibleAnnouncer.Priority.ASSERTIVE)
			_refresh_all()
			return
	announcer.speak("No TileMapLayer with a TileSet is currently selected.",
		AccessibleAnnouncer.Priority.ASSERTIVE)


func _on_assign_to_layer_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	if editor_interface == null:
		announcer.speak("No editor interface available.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var selection := editor_interface.get_selection()
	var nodes := selection.get_selected_nodes()
	for n in nodes:
		if n is TileMapLayer:
			var layer := n as TileMapLayer
			var old_ts := layer.tile_set
			if editor_undo_redo != null:
				editor_undo_redo.create_action("Assign TileSet to %s" % n.name)
				editor_undo_redo.add_do_property(layer, "tile_set", _tileset)
				editor_undo_redo.add_undo_property(layer, "tile_set", old_ts)
				editor_undo_redo.commit_action()
			else:
				layer.tile_set = _tileset
			announcer.speak("Assigned TileSet to %s. Press Refresh in the Map tab to update the palette." % n.name,
				AccessibleAnnouncer.Priority.ASSERTIVE)
			return
	announcer.speak("No TileMapLayer is currently selected in the scene.",
		AccessibleAnnouncer.Priority.ASSERTIVE)


# ----- Custom data layer management -----

func _refresh_layer_list() -> void:
	_layer_list.clear()
	if _tileset == null:
		return
	for i in _tileset.get_custom_data_layers_count():
		var lname := _tileset.get_custom_data_layer_name(i)
		var ltype := _tileset.get_custom_data_layer_type(i)
		var type_label := _type_label(ltype)
		_layer_list.add_item("%s (%s)" % [lname, type_label])


func _type_label(type: int) -> String:
	for entry in _LAYER_TYPES:
		if entry[1] == type:
			return entry[0]
	return "type %d" % type


func _on_add_layer_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return

	var dlg := AcceptDialog.new()
	dlg.title = "Add custom data layer"
	dlg.min_size = Vector2(380, 180)

	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = "Layer name (e.g. name, blocks, footstep, damage):"
	vb.add_child(name_lbl)

	var name_field := LineEdit.new()
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(name_field, "Layer name", "The identifier for this custom data layer.")
	vb.add_child(name_field)

	var type_lbl := Label.new()
	type_lbl.text = "Type:"
	vb.add_child(type_lbl)

	var type_opt := OptionButton.new()
	for entry in _LAYER_TYPES:
		type_opt.add_item(entry[0])
	_set_a11y(type_opt, "Layer type", "The data type tiles will store for this layer.")
	vb.add_child(type_opt)

	dlg.get_ok_button().text = "Add"
	add_child(dlg)
	dlg.popup_centered()
	name_field.grab_focus()

	dlg.confirmed.connect(func():
		var lname := name_field.text.strip_edges()
		if lname.is_empty():
			announcer.speak("Layer name cannot be empty.", AccessibleAnnouncer.Priority.ASSERTIVE)
			dlg.queue_free()
			return
		var ltype: int = _LAYER_TYPES[type_opt.selected][1]
		_tileset.add_custom_data_layer()
		var idx := _tileset.get_custom_data_layers_count() - 1
		_tileset.set_custom_data_layer_name(idx, lname)
		_tileset.set_custom_data_layer_type(idx, ltype)
		announcer.speak("Added custom data layer '%s' of type %s." % [lname, _LAYER_TYPES[type_opt.selected][0]],
			AccessibleAnnouncer.Priority.ASSERTIVE)
		_refresh_all()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())


func _on_remove_layer_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var selected := _layer_list.get_selected_items()
	if selected.is_empty():
		announcer.speak("No layer selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var idx: int = selected[0]
	var lname := _tileset.get_custom_data_layer_name(idx)
	_tileset.remove_custom_data_layer(idx)
	announcer.speak("Removed layer '%s'." % lname, AccessibleAnnouncer.Priority.ASSERTIVE)
	_refresh_all()


# ----- Source management -----

func _on_add_atlas_source_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return

	var dlg := AcceptDialog.new()
	dlg.title = "Add atlas source"
	dlg.min_size = Vector2(400, 220)

	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	var sz_lbl := Label.new()
	sz_lbl.text = "Tile width and height in pixels (default 16):"
	vb.add_child(sz_lbl)

	var size_row := HBoxContainer.new()
	vb.add_child(size_row)

	var w_field := LineEdit.new()
	w_field.text = "16"
	w_field.custom_minimum_size = Vector2(60, 0)
	_set_a11y(w_field, "Tile width", "Width of each tile in pixels.")
	size_row.add_child(w_field)

	var x_lbl := Label.new()
	x_lbl.text = " × "
	size_row.add_child(x_lbl)

	var h_field := LineEdit.new()
	h_field.text = "16"
	h_field.custom_minimum_size = Vector2(60, 0)
	_set_a11y(h_field, "Tile height", "Height of each tile in pixels.")
	size_row.add_child(h_field)

	var tex_lbl := Label.new()
	tex_lbl.text = "Texture path (optional,  leave blank for datafirst workflow):"
	tex_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tex_lbl)

	var tex_field := LineEdit.new()
	tex_field.placeholder_text = "res://textures/tiles.png  (or leave blank)"
	tex_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(tex_field, "Texture path",
		"Optional path to a PNG spritesheet. Leave blank if you have no texture yet.")
	vb.add_child(tex_field)

	dlg.get_ok_button().text = "Add"
	add_child(dlg)
	dlg.popup_centered()
	w_field.grab_focus()

	dlg.confirmed.connect(func():
		var tw := int(w_field.text.strip_edges()) if w_field.text.strip_edges().is_valid_int() else 16
		var th := int(h_field.text.strip_edges()) if h_field.text.strip_edges().is_valid_int() else 16
		tw = maxi(tw, 1)
		th = maxi(th, 1)

		var src := TileSetAtlasSource.new()
		src.texture_region_size = Vector2i(tw, th)

		var tex_path := tex_field.text.strip_edges()
		if not tex_path.is_empty():
			if ResourceLoader.exists(tex_path):
				var tex := load(tex_path)
				if tex is Texture2D:
					src.texture = tex as Texture2D
				else:
					announcer.speak("Warning: resource at texture path is not a Texture2D. Using placeholder.",
						AccessibleAnnouncer.Priority.POLITE)
					src.texture = _make_placeholder_texture(tw, th)
			else:
				announcer.speak("Warning: texture path not found. Using placeholder.",
					AccessibleAnnouncer.Priority.POLITE)
				src.texture = _make_placeholder_texture(tw, th)
		else:
			# No texture supplied. Create an inmemory placeholder so the
			# atlas has nonzero dimensions and tiles can be created.
			# The ImageTexture embeds in the .tres on save.
			src.texture = _make_placeholder_texture(tw, th)

		var new_sid := _tileset.add_source(src)
		announcer.speak("Added atlas source %d, tile size %d by %d." % [new_sid, tw, th],
			AccessibleAnnouncer.Priority.ASSERTIVE)
		_refresh_all()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())


func _on_remove_source_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var idx := _source_option.selected
	if idx < 0 or idx >= _source_ids.size():
		announcer.speak("No source selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var sid := _source_ids[idx]
	_tileset.remove_source(sid)
	announcer.speak("Removed source %d." % sid, AccessibleAnnouncer.Priority.ASSERTIVE)
	_refresh_all()


# ----- Refreshing views -----

func _refresh_all() -> void:
	_refresh_status()
	_refresh_layer_list()
	_refresh_physics_layer_list()
	_refresh_sources()


func _refresh_status() -> void:
	if _tileset == null:
		_status_label.text = "No TileSet loaded. Use 'New TileSet' to create one, or enter a path above and press Load."
	else:
		var name := _tileset_path if not _tileset_path.is_empty() else "(embedded)"
		_status_label.text = "TileSet: %s  |  %d source(s)  |  %d custom data layer(s)" % [
			name, _tileset.get_source_count(), _tileset.get_custom_data_layers_count()
		]


func _refresh_sources() -> void:
	_source_option.clear()
	_source_ids.clear()
	if _tileset == null:
		_tile_list.clear()
		_tile_info_label.text = ""
		return
	for i in _tileset.get_source_count():
		var sid := _tileset.get_source_id(i)
		_source_ids.append(sid)
		var src := _tileset.get_source(sid)
		var label := _source_label(sid, src)
		_source_option.add_item(label, sid)
	if _source_option.item_count > 0:
		_source_option.select(0)
		_on_source_selected(0)


func _source_label(sid: int, src: TileSetSource) -> String:
	var kind := "Unknown"
	if src is TileSetAtlasSource:
		kind = "Atlas"
	elif src is TileSetScenesCollectionSource:
		kind = "Scene collection"
	return "Source %d (%s, %d tiles)" % [sid, kind, src.get_tiles_count()]


func _on_source_selected(idx: int) -> void:
	_tile_list.clear()
	_tile_info_label.text = ""
	_clear_custom_data_fields()
	_clear_collision_fields()
	if _tileset == null or idx < 0 or idx >= _source_ids.size():
		return
	var sid := _source_ids[idx]
	var src := _tileset.get_source(sid)
	if src == null:
		return

	var is_scene_collection := src is TileSetScenesCollectionSource
	_add_scene_tile_button.disabled = not is_scene_collection

	for t in src.get_tiles_count():
		var label := _tile_list_label(src, t)
		_tile_list.add_item(label)

	announcer.speak("Selected source %d, %d tiles." % [sid, src.get_tiles_count()])


func _tile_list_label(src: TileSetSource, index: int) -> String:
	if src is TileSetAtlasSource:
		var atlas := src as TileSetAtlasSource
		var coords := atlas.get_tile_id(index)
		var base := "Tile %d at (%d, %d)" % [index, coords.x, coords.y]
		# Prefix with a "name" custom-data value if one exists.
		var tile_name := _lookup_tile_name(atlas, coords)
		if not tile_name.is_empty():
			return "%s  [%s]" % [tile_name, base]
		return base
	elif src is TileSetScenesCollectionSource:
		var sc := src as TileSetScenesCollectionSource
		var scene_id := sc.get_scene_tile_id(index)
		var packed: PackedScene = sc.get_scene_tile_scene(scene_id)
		var path := packed.resource_path if packed != null else "(unset)"
		return "Scene tile %d: %s" % [scene_id, path]
	return "Tile %d" % index


func _lookup_tile_name(atlas: TileSetAtlasSource, coords: Vector2i) -> String:
	# Looks for a custom data layer called "name" and returns its value for
	# the tile at coords, falling back to empty string.
	if _tileset == null:
		return ""
	var layer_idx := _find_custom_data_layer_index("name")
	if layer_idx < 0:
		return ""
	var data := atlas.get_tile_data(coords, 0)
	if data == null:
		return ""
	var value = data.get_custom_data_by_layer_id(layer_idx)
	return str(value) if value != null else ""


func _find_custom_data_layer_index(layer_name: String) -> int:
	if _tileset == null:
		return -1
	for i in _tileset.get_custom_data_layers_count():
		if _tileset.get_custom_data_layer_name(i) == layer_name:
			return i
	return -1


# ----- Tile selection / detail -----

func _on_tile_selected(idx: int) -> void:
	_clear_custom_data_fields()
	_clear_collision_fields()
	var src_idx := _source_option.selected
	if _tileset == null or src_idx < 0 or src_idx >= _source_ids.size():
		return
	var sid := _source_ids[src_idx]
	var src := _tileset.get_source(sid)
	if src == null:
		return

	if src is TileSetAtlasSource:
		var atlas := src as TileSetAtlasSource
		var coords := atlas.get_tile_id(idx)
		_show_atlas_tile_detail(atlas, coords)
	elif src is TileSetScenesCollectionSource:
		var sc := src as TileSetScenesCollectionSource
		var scene_id := sc.get_scene_tile_id(idx)
		_show_scene_tile_detail(sc, scene_id)


func _show_atlas_tile_detail(atlas: TileSetAtlasSource, coords: Vector2i) -> void:
	var data := atlas.get_tile_data(coords, 0)
	if data == null:
		_tile_info_label.text = "No tile data at (%d, %d)." % [coords.x, coords.y]
		return
	var lines: Array[String] = []
	lines.append("Atlas coords: (%d, %d)" % [coords.x, coords.y])
	lines.append("Probability: %.2f" % data.probability)
	lines.append("Z-index: %d" % data.z_index)
	lines.append("Y-sort origin: %d" % data.y_sort_origin)

	var ncd := _tileset.get_custom_data_layers_count()
	lines.append("%d custom data layer(s):" % ncd)
	for i in ncd:
		var lname := _tileset.get_custom_data_layer_name(i)
		var lval = data.get_custom_data_by_layer_id(i)
		lines.append("  %s = %s" % [lname, str(lval)])
		_add_custom_data_editor(atlas, coords, i, lname, lval)

	_tile_info_label.text = "\n".join(lines)
	announcer.speak(_short_announce_for_atlas(atlas, coords, data))

	_clear_collision_fields()
	var nphys := _tileset.get_physics_layers_count()
	for i in nphys:
		_add_collision_editor(atlas, coords, i)


func _physics_polygon_summary(data: TileData, nphys: int) -> String:
	var parts: Array[String] = []
	for i in nphys:
		parts.append(str(data.get_collision_polygons_count(i)))
	return ", ".join(parts)


# ----- Physics layer management -----

func _refresh_physics_layer_list() -> void:
	_physics_layer_list.clear()
	if _tileset == null:
		return
	for i in _tileset.get_physics_layers_count():
		_physics_layer_list.add_item("Layer %d" % i)


func _on_add_physics_layer_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	_tileset.add_physics_layer()
	var idx := _tileset.get_physics_layers_count() - 1
	_refresh_physics_layer_list()
	announcer.speak("Added physics layer %d." % idx, AccessibleAnnouncer.Priority.ASSERTIVE)


func _on_remove_physics_layer_pressed() -> void:
	if _tileset == null:
		announcer.speak("No TileSet loaded.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var selected := _physics_layer_list.get_selected_items()
	if selected.is_empty():
		announcer.speak("No physics layer selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var idx: int = selected[0]
	_tileset.remove_physics_layer(idx)
	_refresh_physics_layer_list()
	_clear_collision_fields()
	var src_idx := _source_option.selected
	if src_idx >= 0 and src_idx < _source_ids.size():
		var tile_selected := _tile_list.get_selected_items()
		if not tile_selected.is_empty():
			_on_tile_selected(tile_selected[0])
	announcer.speak("Removed physics layer %d." % idx, AccessibleAnnouncer.Priority.ASSERTIVE)


# ----- Collision editing -----

func _clear_collision_fields() -> void:
	for c in _collision_container.get_children():
		c.queue_free()


func _add_collision_editor(atlas: TileSetAtlasSource, coords: Vector2i, layer_idx: int) -> void:
	var data := atlas.get_tile_data(coords, 0)
	if data == null:
		return
	var has_collision := data.get_collision_polygons_count(layer_idx) > 0

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collision_container.add_child(row)

	var lbl := Label.new()
	lbl.text = "Layer %d:" % layer_idx
	lbl.custom_minimum_size = Vector2(70, 0)
	row.add_child(lbl)

	var cb := CheckBox.new()
	cb.text = "Solid (full tile)"
	cb.button_pressed = has_collision
	_set_a11y(cb, "Collision layer %d" % layer_idx,
		"Check to add a full-tile collision rectangle on physics layer %d; uncheck to remove it." % layer_idx)
	cb.toggled.connect(func(checked: bool) -> void:
		_on_collision_toggled(checked, atlas, coords, layer_idx)
	)
	row.add_child(cb)


func _on_collision_toggled(checked: bool, atlas: TileSetAtlasSource, coords: Vector2i, layer_idx: int) -> void:
	var data := atlas.get_tile_data(coords, 0)
	if data == null:
		return
	var count := data.get_collision_polygons_count(layer_idx)
	for i in range(count - 1, -1, -1):
		data.remove_collision_polygon(layer_idx, i)
	if checked:
		data.add_collision_polygon(layer_idx)
		data.set_collision_polygon_points(layer_idx, 0, _make_full_tile_rect(atlas))
		announcer.speak("Layer %d collision enabled." % layer_idx, AccessibleAnnouncer.Priority.ASSERTIVE)
	else:
		announcer.speak("Layer %d collision disabled." % layer_idx, AccessibleAnnouncer.Priority.ASSERTIVE)


func _make_full_tile_rect(atlas: TileSetAtlasSource) -> PackedVector2Array:
	var hw := atlas.texture_region_size.x / 2.0
	var hh := atlas.texture_region_size.y / 2.0
	return PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh),
		Vector2(hw, hh), Vector2(-hw, hh),
	])


func _short_announce_for_atlas(atlas: TileSetAtlasSource, coords: Vector2i, data: TileData) -> String:
	var parts: Array[String] = []
	var tname := _lookup_tile_name(atlas, coords)
	if not tname.is_empty():
		parts.append(tname)
	parts.append("tile %d comma %d" % [coords.x, coords.y])
	# Announce up to two custom data values for quick orientation.
	var ncd: int = min(2, _tileset.get_custom_data_layers_count())
	for i in ncd:
		var lname := _tileset.get_custom_data_layer_name(i)
		var val = data.get_custom_data_by_layer_id(i)
		if val != null and str(val) != "":
			parts.append("%s %s" % [lname, str(val)])
	return ", ".join(parts)


func _show_scene_tile_detail(sc: TileSetScenesCollectionSource, scene_id: int) -> void:
	var packed: PackedScene = sc.get_scene_tile_scene(scene_id)
	var path := packed.resource_path if packed != null else "(unset)"
	_tile_info_label.text = "Scene tile id %d\nScene: %s" % [scene_id, path]
	_clear_collision_fields()
	announcer.speak("Scene tile %d, %s" % [scene_id, path.get_file()])


# ----- Atlas tile add -----

func _next_free_atlas_coords(atlas: TileSetAtlasSource) -> Vector2i:
	# Scan row 0 left to right until we find an unused slot.
	var x := 0
	while atlas.has_tile(Vector2i(x, 0)):
		x += 1
	return Vector2i(x, 0)


func _on_add_atlas_tile_pressed() -> void:
	var src_idx := _source_option.selected
	if _tileset == null or src_idx < 0 or src_idx >= _source_ids.size():
		announcer.speak("No atlas source selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var sid := _source_ids[src_idx]
	var src := _tileset.get_source(sid)
	if not (src is TileSetAtlasSource):
		announcer.speak("Selected source is not an atlas source.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return

	var atlas := src as TileSetAtlasSource

	var dlg := AcceptDialog.new()
	dlg.title = "Add atlas tile"
	dlg.min_size = Vector2(380, 140)

	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	var lbl := Label.new()
	lbl.text = "Tile name (e.g. grass, dirt, stone):"
	vb.add_child(lbl)

	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(field, "Tile name",
		"Human-readable name for this tile. Auto-creates the 'name' custom data layer if needed.")
	vb.add_child(field)

	dlg.get_ok_button().text = "Add tile"
	add_child(dlg)
	dlg.popup_centered()
	field.grab_focus()

	dlg.confirmed.connect(func():
		var coords := _next_free_atlas_coords(atlas)
		atlas.create_tile(coords)
		var tile_name := field.text.strip_edges()
		if not tile_name.is_empty():
			# Autocreate the "name" layer if it doesn't exist yet.
			var nlayer_idx := _find_custom_data_layer_index("name")
			if nlayer_idx < 0:
				_tileset.add_custom_data_layer()
				nlayer_idx = _tileset.get_custom_data_layers_count() - 1
				_tileset.set_custom_data_layer_name(nlayer_idx, "name")
				_tileset.set_custom_data_layer_type(nlayer_idx, TYPE_STRING)
			var data := atlas.get_tile_data(coords, 0)
			if data != null:
				data.set_custom_data_by_layer_id(nlayer_idx, tile_name)
		var total := atlas.get_tiles_count()
		var display := tile_name if not tile_name.is_empty() else "unnamed"
		announcer.speak("Added tile '%s' at slot (%d, 0). %d tile(s) total." % [
			display, coords.x, total
		], AccessibleAnnouncer.Priority.ASSERTIVE)
		_refresh_all()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())


# ----- Scene collection add -----

func _on_add_scene_tile_pressed() -> void:
	var src_idx := _source_option.selected
	if src_idx < 0 or _tileset == null:
		announcer.speak("No source selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var sid := _source_ids[src_idx]
	var src := _tileset.get_source(sid)
	if not (src is TileSetScenesCollectionSource):
		announcer.speak("Selected source is not a scene collection.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return

	var dlg := AcceptDialog.new()
	dlg.title = "Add scene tile"
	dlg.min_size = Vector2(420, 160)

	var vb := VBoxContainer.new()
	dlg.add_child(vb)

	var lbl := Label.new()
	lbl.text = "Enter the path to a .tscn file (e.g. res://scenes/enemy.tscn):"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)

	var field := LineEdit.new()
	field.placeholder_text = "res://scenes/my_scene.tscn"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(field, "Scene path", "Path to the PackedScene .tscn file to add. Press Enter or click Add.")
	vb.add_child(field)

	dlg.get_ok_button().text = "Add"
	add_child(dlg)
	dlg.popup_centered()
	field.grab_focus()

	var sc := src as TileSetScenesCollectionSource

	dlg.confirmed.connect(func():
		var path := field.text.strip_edges()
		if path.is_empty():
			announcer.speak("No path entered.", AccessibleAnnouncer.Priority.ASSERTIVE)
			dlg.queue_free()
			return
		if not ResourceLoader.exists(path):
			announcer.speak("Path not found: %s" % path, AccessibleAnnouncer.Priority.ASSERTIVE)
			dlg.queue_free()
			return
		var res := load(path)
		if not (res is PackedScene):
			announcer.speak("Resource at %s is not a PackedScene." % path, AccessibleAnnouncer.Priority.ASSERTIVE)
			dlg.queue_free()
			return
		var new_id := sc.create_scene_tile(res as PackedScene)
		announcer.speak("Added scene tile %d from %s." % [new_id, path.get_file()],
			AccessibleAnnouncer.Priority.ASSERTIVE)
		_on_source_selected(src_idx)
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())


# ----- Tile removal (atlas + scene collection) -----

func _on_remove_tile_pressed() -> void:
	var src_idx := _source_option.selected
	var tile_idx_arr := _tile_list.get_selected_items()
	if src_idx < 0 or tile_idx_arr.is_empty() or _tileset == null:
		announcer.speak("No tile selected.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return
	var sid := _source_ids[src_idx]
	var src := _tileset.get_source(sid)
	var tile_idx: int = tile_idx_arr[0]

	if src is TileSetAtlasSource:
		var atlas := src as TileSetAtlasSource
		var coords := atlas.get_tile_id(tile_idx)
		var tname := _lookup_tile_name(atlas, coords)
		atlas.remove_tile(coords)
		var display := tname if not tname.is_empty() else "tile at (%d, %d)" % [coords.x, coords.y]
		announcer.speak("Removed %s." % display, AccessibleAnnouncer.Priority.ASSERTIVE)
	elif src is TileSetScenesCollectionSource:
		var sc := src as TileSetScenesCollectionSource
		var scene_id := sc.get_scene_tile_id(tile_idx)
		sc.remove_scene_tile(scene_id)
		announcer.speak("Removed scene tile %d." % scene_id, AccessibleAnnouncer.Priority.ASSERTIVE)
	else:
		announcer.speak("Cannot remove tile from this source type.", AccessibleAnnouncer.Priority.ASSERTIVE)
		return

	_on_source_selected(src_idx)


# ----- Custom data editing -----

func _clear_custom_data_fields() -> void:
	for c in _custom_data_container.get_children():
		c.queue_free()


func _add_custom_data_editor(
	atlas: TileSetAtlasSource, coords: Vector2i, layer_id: int,
	layer_name: String, current_value: Variant
) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_data_container.add_child(row)

	var lbl := Label.new()
	lbl.text = layer_name + ":"
	lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl)

	var field := LineEdit.new()
	field.text = str(current_value) if current_value != null else ""
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_a11y(field, "Custom data %s" % layer_name,
		"Value for custom data layer %s. Press Enter to commit." % layer_name)
	field.text_submitted.connect(
		func(new_text: String) -> void:
			_commit_custom_data(atlas, coords, layer_id, layer_name, new_text)
	)
	row.add_child(field)


func _commit_custom_data(
	atlas: TileSetAtlasSource, coords: Vector2i, layer_id: int,
	layer_name: String, new_text: String
) -> void:
	var data := atlas.get_tile_data(coords, 0)
	if data == null:
		return
	var layer_type := _tileset.get_custom_data_layer_type(layer_id)
	var converted := _coerce_value(new_text, layer_type)

	if editor_undo_redo != null:
		editor_undo_redo.create_action("Set custom data '%s'" % layer_name)
		var old_value = data.get_custom_data_by_layer_id(layer_id)
		editor_undo_redo.add_do_method(data, "set_custom_data_by_layer_id", layer_id, converted)
		editor_undo_redo.add_undo_method(data, "set_custom_data_by_layer_id", layer_id, old_value)
		editor_undo_redo.commit_action()
	else:
		data.set_custom_data_by_layer_id(layer_id, converted)

	announcer.speak("Set %s to %s." % [layer_name, str(converted)],
		AccessibleAnnouncer.Priority.ASSERTIVE)


func _coerce_value(text: String, type: int) -> Variant:
	# Variant.Type ints  converting to the typed layer expects native type.
	match type:
		TYPE_BOOL:
			return text.to_lower() in ["true", "1", "yes", "y"]
		TYPE_INT:
			return int(text)
		TYPE_FLOAT:
			return float(text)
		TYPE_STRING, TYPE_STRING_NAME:
			return text
		_:
			return text


# ----- Helpers -----

func _make_placeholder_texture(tile_w: int, tile_h: int) -> ImageTexture:
	# Creates a 128 tile wide solid colour image so the atlas source has
	# nonzero dimensions. Tiles can then be created without a real spritesheet.
	# The ImageTexture is embedded in the .tres when the TileSet is saved.
	var img := Image.create(tile_w * 128, tile_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.0, 0.5, 1.0))  # solid magenta obvious placeholder maybe? idk
	return ImageTexture.create_from_image(img)


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
