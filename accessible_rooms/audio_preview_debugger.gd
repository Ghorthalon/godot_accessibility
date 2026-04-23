@tool
extends EditorDebuggerPlugin

var _active_session: EditorDebuggerSession = null

func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		push_warning("AudioPreviewDebugger: get_session(%d) returned null" % session_id)
		return
	_active_session = session
	session.stopped.connect(_on_session_stopped.bind(session))
	print("AudioPreviewDebugger: session %d started" % session_id)

func _on_session_stopped(session: EditorDebuggerSession) -> void:
	if _active_session == session:
		_active_session = null

func _has_capture(capture: String) -> bool:
	return capture == "audio_preview"

func _capture(message: String, data: Array, session_id: int) -> bool:
	return false  # game never sends messages back to the editor

func has_active_session() -> bool:
	return _active_session != null and is_instance_valid(_active_session) and _active_session.is_active()

func send_cursor(pos: Vector3) -> void:
	if _active_session == null or not is_instance_valid(_active_session):
		push_warning("AudioPreviewDebugger: no active session. Is a game running?")
		return
	if not _active_session.is_active():
		push_warning("AudioPreviewDebugger: session exists but is_active() == false")
		return
	_active_session.send_message("audio_preview:move", [pos.x, pos.y, pos.z])

func send_release() -> void:
	if _active_session == null or not is_instance_valid(_active_session):
		return
	if not _active_session.is_active():
		return
	_active_session.send_message("audio_preview:release", [])
