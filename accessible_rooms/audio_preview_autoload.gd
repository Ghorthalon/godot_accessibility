extends Node

const SND_OBJECT   := preload("res://addons/accessible_rooms/sounds/object.wav")
const SND_INSIDE   := preload("res://addons/accessible_rooms/sounds/inside.wav")
const SND_SUCCESS  := preload("res://addons/accessible_rooms/sounds/success.wav")
const SND_ERROR    := preload("res://addons/accessible_rooms/sounds/error.wav")
const SND_DISTANCE := preload("res://addons/accessible_rooms/sounds/distance.wav")

var _listener: AudioListener3D = null

func _ready() -> void:
	if not OS.has_feature("editor"):
		return  # no-op in exported builds
	if not EngineDebugger.is_active():
		return
	EngineDebugger.register_message_capture("audio_preview", _on_message)
	# Create listener but do NOT make_current(). player's listener stays active
	# until explicitly enables audio preview in the dock.
	_listener = AudioListener3D.new()
	_listener.name = "AudioPreviewListener"
	get_tree().root.add_child(_listener)

func _stream_for(name: String) -> AudioStream:
	match name:
		"object":   return SND_OBJECT
		"inside":   return SND_INSIDE
		"success":  return SND_SUCCESS
		"error":    return SND_ERROR
		"distance": return SND_DISTANCE
	push_warning("AudioPreviewAutoload: unknown sound '%s'" % name)
	return null

func _on_message(cmd: String, data: Array) -> bool:
	if cmd == "release":
		if _listener != null and is_instance_valid(_listener):
			_listener.queue_free()
			_listener = null
		return true
	if cmd == "move":
		if data.size() < 3:
			return false
		# Recreate if previously released.
		if _listener == null or not is_instance_valid(_listener):
			_listener = AudioListener3D.new()
			_listener.name = "AudioPreviewListener"
			get_tree().root.add_child(_listener)
		_listener.global_position = Vector3(float(data[0]), float(data[1]), float(data[2]))
		_listener.make_current()
		return true
	if cmd == "play_3d":
		# data: [name, lx, ly, lz, sx, sy, sz]
		if data.size() < 7: return false
		var stream := _stream_for(str(data[0]))
		if stream == null: return true
		if _listener == null or not is_instance_valid(_listener):
			_listener = AudioListener3D.new()
			_listener.name = "AudioPreviewListener"
			get_tree().root.add_child(_listener)
		_listener.global_position = Vector3(float(data[1]), float(data[2]), float(data[3]))
		_listener.make_current()
		var player := AudioStreamPlayer3D.new()
		player.stream = stream
		player.global_position = Vector3(float(data[4]), float(data[5]), float(data[6]))
		get_tree().root.add_child(player)
		player.play()
		player.finished.connect(player.queue_free)
		return true
	if cmd == "play_2d":
		# data: [name]
		if data.size() < 1: return false
		var stream := _stream_for(str(data[0]))
		if stream == null: return true
		var player := AudioStreamPlayer.new()
		player.stream = stream
		get_tree().root.add_child(player)
		player.play()
		player.finished.connect(player.queue_free)
		return true
	if cmd == "play_staggered":
		# data: [name, lx, ly, lz, count, sx0, sy0, sz0, ...]
		if data.size() < 5: return false
		var stream := _stream_for(str(data[0]))
		if stream == null: return true
		var n_count: int = int(data[4])
		if data.size() < 5 + n_count * 3: return false
		if _listener == null or not is_instance_valid(_listener):
			_listener = AudioListener3D.new()
			_listener.name = "AudioPreviewListener"
			get_tree().root.add_child(_listener)
		_listener.global_position = Vector3(float(data[1]), float(data[2]), float(data[3]))
		_listener.make_current()
		for i in n_count:
			var base := 5 + i * 3
			var src_pos := Vector3(float(data[base]), float(data[base + 1]), float(data[base + 2]))
			get_tree().create_timer(i * 0.075).timeout.connect(
				func() -> void:
					var p := AudioStreamPlayer3D.new()
					p.stream = stream
					p.global_position = src_pos
					get_tree().root.add_child(p)
					p.play()
					p.finished.connect(p.queue_free)
			)
		return true
	return false
