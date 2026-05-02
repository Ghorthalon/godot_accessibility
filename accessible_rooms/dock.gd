@tool
extends VBoxContainer

const SND_OBJECT   := preload("res://addons/accessible_rooms/sounds/object.wav")
const SND_INSIDE   := preload("res://addons/accessible_rooms/sounds/inside.wav")
const SND_SUCCESS  := preload("res://addons/accessible_rooms/sounds/success.wav")
const SND_ERROR    := preload("res://addons/accessible_rooms/sounds/error.wav")
const SND_DISTANCE := preload("res://addons/accessible_rooms/sounds/distance.wav")

var plugin: EditorPlugin
var audio_debugger  # AudioPreviewDebugger instance, set by plugin.gd

# Shared state read/written by tabs
var cursor: Vector3 = Vector3.ZERO
var step: float = 1.0
var current_entity: SpatialEntity3D
var scene_query: SceneQuery

var use_selected_node: bool = false
var follow_selection: bool = false
var last_placed_node: Node3D
var corner_selector: CornerSelector  # shared selection, set by tab_cursor

signal cursor_jumped

var tab_rooms  # set in _ready exposes room actions to other tabs
var tab_place  # set in _ready exposes place actions to other tabs

var announce: Label
var _snd_object:   AudioStreamPlayer
var _snd_inside:   AudioStreamPlayer
var _snd_success:  AudioStreamPlayer
var _snd_error:    AudioStreamPlayer
var _snd_distance: AudioStreamPlayer
var _editor_listener: AudioListener3D = null

func _ready() -> void:
	name = "Rooms"

	announce = Label.new()
	announce.accessibility_live = 1  # ACCESSIBILITY_LIVE_POLITE
	add_child(announce)

	_snd_object   = _make_player(SND_OBJECT)
	_snd_inside   = _make_player(SND_INSIDE)
	_snd_success  = _make_player(SND_SUCCESS)
	_snd_error    = _make_player(SND_ERROR)
	_snd_distance = _make_player(SND_DISTANCE)

	scene_query = SceneQuery.new()
	scene_query.plugin = plugin
	scene_query.dock = self
	add_child(scene_query)

	var toggle := CheckButton.new()
	toggle.text = "Use selected node as parent"
	toggle.tooltip_text = "When on, rooms and placed nodes are added as children of the currently selected node instead of the scene root."
	toggle.toggled.connect(func(on: bool) -> void:
		use_selected_node = on
		_say("Parent: %s." % ("selected node" if on else "scene root"))
	)
	add_child(toggle)

	var follow_toggle := CheckButton.new()
	follow_toggle.text = "Move cursor to selected object"
	follow_toggle.tooltip_text = "When on, the cursor jumps to any node you select in the viewport or scene tree."
	follow_toggle.toggled.connect(func(on: bool) -> void:
		follow_selection = on
		_say("Follow selection: %s." % ("on" if on else "off"))
	)
	add_child(follow_toggle)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	tab_rooms = preload("res://addons/accessible_rooms/tab_rooms.gd").new()
	tab_rooms.name = "Rooms"
	tab_rooms.dock = self
	tabs.add_child(tab_rooms)

	var tab_ramps = preload("res://addons/accessible_rooms/tab_ramps.gd").new()
	tab_ramps.name = "Ramps"
	tab_ramps.dock = self
	tabs.add_child(tab_ramps)

	var tab_cursor = preload("res://addons/accessible_rooms/tab_cursor.gd").new()
	tab_cursor.name = "Cursor"
	tab_cursor.dock = self
	tabs.add_child(tab_cursor)

	tab_place = preload("res://addons/accessible_rooms/tab_place.gd").new()
	tab_place.name = "Place"
	tab_place.dock = self
	tabs.add_child(tab_place)

	var tab_objects = preload("res://addons/accessible_rooms/tab_objects.gd").new()
	tab_objects.name = "Objects"
	tab_objects.dock = self
	tabs.add_child(tab_objects)

	var tab_scene = preload("res://addons/accessible_rooms/tab_scene.gd").new()
	tab_scene.name = "Scene"
	tab_scene.dock = self
	tabs.add_child(tab_scene)

func get_target_node() -> Node3D:
	var sel: Array = plugin.get_editor_interface().get_selection().get_selected_nodes()
	for n in sel:
		if n is Node3D: return n as Node3D
	if last_placed_node != null and is_instance_valid(last_placed_node):
		return last_placed_node
	_say("No node selected. Insert a node or select one first.")
	return null

func move_cursor_to(pos: Vector3) -> void:
	cursor = pos
	cursor_jumped.emit()

func _say(msg: String) -> void:
	announce.text = msg

func _say_ok(msg: String) -> void:
	_say(msg)
	play_audio_2d("success")

func _say_err(msg: String) -> void:
	_say(msg)
	play_audio_2d("error")

func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p

func _stream_for(snd_name: String) -> AudioStreamPlayer:
	match snd_name:
		"object":   return _snd_object
		"inside":   return _snd_inside
		"success":  return _snd_success
		"error":    return _snd_error
		"distance": return _snd_distance
	return null

func play_audio_2d(snd_name: String) -> void:
	if audio_debugger != null and audio_debugger.has_active_session():
		audio_debugger.send_play_2d(snd_name)
		return
	var p := _stream_for(snd_name)
	if p != null:
		p.play()

func play_audio_3d(snd_name: String, source_pos: Vector3) -> void:
	if audio_debugger != null and audio_debugger.has_active_session():
		audio_debugger.send_play_3d(snd_name, cursor, source_pos)
		return
	_play_editor_3d(snd_name, source_pos)

func play_audio_staggered(snd_name: String, positions: Array) -> void:
	if positions.is_empty(): return
	if audio_debugger != null and audio_debugger.has_active_session():
		audio_debugger.send_play_staggered(snd_name, cursor, positions)
		return
	var vp := _get_editor_viewport()
	if vp == null:
		var p := _stream_for(snd_name)
		if p != null: p.play()
		return
	var listener := _ensure_editor_listener(vp)
	listener.global_position = cursor
	listener.make_current()
	var stream: AudioStream = _stream_for(snd_name).stream
	for i in positions.size():
		var src_pos: Vector3 = positions[i]
		get_tree().create_timer(i * 0.075).timeout.connect(
			func() -> void:
				var player := AudioStreamPlayer3D.new()
				player.stream = stream
				player.global_position = src_pos
				vp.add_child(player)
				player.play()
				player.finished.connect(player.queue_free)
		)

func _get_editor_viewport() -> SubViewport:
	if not plugin: return null
	var vp: SubViewport = plugin.get_editor_interface().get_editor_viewport_3d(0)
	if vp == null: return null
	vp.audio_listener_enable_3d = true
	return vp

func _ensure_editor_listener(vp: SubViewport) -> AudioListener3D:
	if _editor_listener != null and is_instance_valid(_editor_listener):
		return _editor_listener
	_editor_listener = AudioListener3D.new()
	_editor_listener.name = "EditorAudioListener"
	vp.add_child(_editor_listener)
	return _editor_listener

func _play_editor_3d(snd_name: String, source_pos: Vector3) -> void:
	var vp := _get_editor_viewport()
	if vp == null:
		var p := _stream_for(snd_name)
		if p != null: p.play()
		return
	var listener := _ensure_editor_listener(vp)
	listener.global_position = cursor
	listener.make_current()
	var player := AudioStreamPlayer3D.new()
	player.stream = _stream_for(snd_name).stream
	player.global_position = source_pos
	vp.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _exit_tree() -> void:
	if _editor_listener != null and is_instance_valid(_editor_listener):
		_editor_listener.queue_free()
		_editor_listener = null
