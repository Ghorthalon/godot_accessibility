extends Node

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
	return false
