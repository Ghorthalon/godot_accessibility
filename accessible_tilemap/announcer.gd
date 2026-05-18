@tool
class_name AccessibleAnnouncer
extends Node

# Native TTS toggle. set USE_NATIVE_TTS = true to bypass the ARIA-live label
# and route announcements through DisplayServer.tts_speak() instead.
const USE_NATIVE_TTS: bool = false
const TTS_VOICE_ID: String = ""    # "" = pick first English voice
const TTS_VOLUME: int = 100         # 0-100
const TTS_PITCH: float = 1.0       # 0.1-2.0
const TTS_RATE: float = 1.0        # 0.1-10.0 (1.0 = normal)
const TTS_INTERRUPT: bool = true   # true = new line interrupts prior speech

enum Priority { POLITE, ASSERTIVE }

var _live_label: Label


func _ready() -> void:
	_live_label = Label.new()
	_live_label.name = "Live"
	_live_label.custom_minimum_size = Vector2.ZERO
	_live_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_live_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_live_label.modulate = Color(1, 1, 1, 0)
	_live_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _live_label.has_method(&"set_accessibility_live"):
		_live_label.call(&"set_accessibility_live", 1)
	add_child(_live_label)


func speak(text: String, priority: Priority = Priority.POLITE) -> void:
	if text.is_empty():
		return

	if USE_NATIVE_TTS:
		_tts_speak_native(text, priority == Priority.ASSERTIVE or TTS_INTERRUPT)
		return

	if _live_label != null and is_instance_valid(_live_label):
		# AccessKit only fires on a text change. If we're saying the same thing
		# twice (e.g. arrow-key spam on the same cell), append a zerowidth
		# space to force a change.
		if _live_label.text == text:
			_live_label.text = text + "\u200b"
		else:
			_live_label.text = text


func stop() -> void:
	if USE_NATIVE_TTS:
		DisplayServer.tts_stop()


func _tts_speak_native(msg: String, interrupt: bool) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	var voice_id := TTS_VOICE_ID
	if voice_id.is_empty():
		var en_voices := DisplayServer.tts_get_voices_for_language("en")
		if en_voices.size() > 0:
			voice_id = en_voices[0]
		else:
			var all_voices := DisplayServer.tts_get_voices()
			if all_voices.size() > 0:
				voice_id = String(all_voices[0].get("id", ""))
	DisplayServer.tts_speak(msg, voice_id, TTS_VOLUME, TTS_PITCH, TTS_RATE, 0, interrupt)
