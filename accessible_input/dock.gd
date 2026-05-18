@tool
extends VBoxContainer

# Native TTS toggle. set USE_NATIVE_TTS = true to bypass the live label
# and route announcements through DisplayServer.tts_speak() instead.
const USE_NATIVE_TTS: bool = false
const TTS_VOICE_ID: String = ""    # "" = pick first English voice
const TTS_VOLUME: int = 100         # 0-100
const TTS_PITCH: float = 1.0       # 0.1-2.0
const TTS_RATE: float = 1.0        # 0.1-10.0 (1.0 = normal)
const TTS_INTERRUPT: bool = true   # true = new line interrupts prior speech

var plugin: EditorPlugin

var current_action: StringName = &""

var announce: Label
var tab_actions

func _ready() -> void:
	name = "Input"

	announce = Label.new()
	announce.accessibility_live = 1  # ACCESSIBILITY_LIVE_POLITE
	announce.custom_minimum_size = Vector2.ZERO
	announce.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	announce.modulate = Color(1, 1, 1, 0)
	announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(announce)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	tab_actions = preload("res://addons/accessible_input/tab_actions.gd").new()
	tab_actions.name = "Actions"
	tab_actions.dock = self
	tabs.add_child(tab_actions)

func _tts_speak_native(msg: String) -> void:
	if msg.is_empty():
		return
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
	DisplayServer.tts_speak(msg, voice_id, TTS_VOLUME, TTS_PITCH, TTS_RATE, 0, TTS_INTERRUPT)


func _say(msg: String) -> void:
	if USE_NATIVE_TTS:
		_tts_speak_native(msg)
		return
	if announce.text == msg:
		announce.text = msg + "​"
	else:
		announce.text = msg
