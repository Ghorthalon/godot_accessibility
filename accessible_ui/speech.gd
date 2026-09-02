@tool
class_name A11ySpeech
extends Node

## Queued speech output for [AccessibleUI].
##
## Three backends
## 1. [b]VoiceOver[/b], when the godot_direct_touch addon is installed and
##    VoiceOver is running. Announcements go to VoiceOver itself, so they come
##    out in the player's own voice, at their own rate, and reach their braille
##    display. This is strictly better than talking over VoiceOver with a
##    second synthesiser, which is what backend 2 would be doing on iOS.
## 2. Native TTS via [DisplayServer] when the platform reports
##    FEATURE_TEXT_TO_SPEECH. The Android path, and the iOS path when VoiceOver
##    is off - neither has an AccessKit bridge, but both have a system voice.
## 3. A hidden live-region [Label] otherwise, so a desktop screen reader still
##    picks announcements up through AccessKit.
##

signal spoken(text: String)

enum Priority { POLITE, ASSERTIVE }

enum Backend { LIVE_LABEL, NATIVE_TTS, VOICEOVER }

## Native TTS reports "still speaking" for a beat after an utterance ends.
## Waiting this long before starting the next one stops the queue from
## running two utterances together.
const _DRAIN_INTERVAL: float = 0.05

## Native singleton published by the godot_direct_touch addon. Looked up by
## name so this addon keeps working with that one absent.
const _DIRECT_TOUCH := "DirectTouchServer"

var _backend: int = Backend.LIVE_LABEL
var _voice_id: String = ""
var _queue: Array[String] = []
var _live_label: Label
var _drain_accum: float = 0.0
var _direct_touch: Object = null


func _ready() -> void:
	if Engine.has_singleton(_DIRECT_TOUCH):
		_direct_touch = Engine.get_singleton(_DIRECT_TOUCH)
		if _direct_touch.is_supported():
			# VoiceOver can be switched on and off mid-session, and which
			# backend is correct flips with it.
			_direct_touch.screen_reader_changed.connect(_on_screen_reader_changed)
		else:
			_direct_touch = null

	# A platform can advertise TTS and still ship zero voices (some Linux
	# setups, Android without a TTS engine installed), so an empty voice id is
	# what actually decides whether the native backend is usable.
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		_voice_id = _pick_voice()
	if _voice_id.is_empty():
		_make_live_label()

	_pick_backend()


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	_drain_accum += delta
	if _drain_accum < _DRAIN_INTERVAL:
		return
	_drain_accum = 0.0
	if DisplayServer.tts_is_speaking() or DisplayServer.tts_is_paused():
		return
	_speak_now(_queue.pop_front())


## Which backend is currently in use.
func backend() -> int:
	return _backend


func backend_name() -> String:
	match _backend:
		Backend.VOICEOVER:
			return "VoiceOver"
		Backend.NATIVE_TTS:
			return "System text to speech"
		_:
			return "Live region"


func _pick_backend() -> void:
	var previous := _backend
	if _direct_touch != null and _direct_touch.is_screen_reader_active():
		_backend = Backend.VOICEOVER
	elif not _voice_id.is_empty():
		_backend = Backend.NATIVE_TTS
	else:
		_backend = Backend.LIVE_LABEL

	if _backend == previous:
		return

	# Whatever the old backend had queued is stale the moment the player's
	# screen reader changes underneath us.
	_queue.clear()
	if previous == Backend.NATIVE_TTS:
		DisplayServer.tts_stop()
	# Only the native queue needs draining; VoiceOver keeps its own.
	set_process(_backend == Backend.NATIVE_TTS)


func _on_screen_reader_changed(_active: bool) -> void:
	_pick_backend()


## Say [param text]. ASSERTIVE clears anything pending and interrupts.
func speak(text: String, priority: Priority = Priority.POLITE) -> void:
	var msg := text.strip_edges()
	if msg.is_empty():
		return
	spoken.emit(msg)
	match _backend:
		Backend.VOICEOVER:
			_speak_voiceover(msg, priority)
		Backend.NATIVE_TTS:
			if priority == Priority.ASSERTIVE:
				_queue.clear()
				DisplayServer.tts_stop()
				_speak_now(msg)
			else:
				_queue.append(msg)
		_:
			_speak_live_label(msg)


## Drop everything queued and cut off the current utterance.
##
## [b]Partial on the VoiceOver backend.[/b] iOS exposes no way to cancel a
## pending announcement, so this interrupts what is being said right now but
## cannot flush what VoiceOver has already queued behind it.
func stop() -> void:
	_queue.clear()
	match _backend:
		Backend.VOICEOVER:
			_direct_touch.interrupt_speech()
		Backend.NATIVE_TTS:
			DisplayServer.tts_stop()


func _speak_voiceover(msg: String, priority: Priority) -> void:
	# DirectTouchServer.Priority: 0 LOW, 1 DEFAULT, 2 HIGH - and the obvious
	# mapping is the wrong one. Apple's HIGH interrupts existing speech and then
	# *cannot itself be interrupted*, so swiping quickly through a dialog makes
	# the first utterance lock out every one behind it and they all queue up.
	#
	# DEFAULT is the screen-reader cursor behaviour: interrupt what is speaking,
	# and give way to the next swipe. LOW is the one that actually means polite,
	# i.e. wait your turn. HIGH is reserved for things that must not be cut off
	# and is deliberately not used here.
	_direct_touch.announce(msg, 1 if priority == Priority.ASSERTIVE else 0)


func _speak_now(msg: String) -> void:
	DisplayServer.tts_speak(
		msg,
		_voice_id,
		int(A11ySettings.get_value("accessible_ui/speech/volume")),
		float(A11ySettings.get_value("accessible_ui/speech/pitch")),
		float(A11ySettings.get_value("accessible_ui/speech/rate")),
		0,
		true
	)


func _speak_live_label(msg: String) -> void:
	if _live_label == null or not is_instance_valid(_live_label):
		return
	# AccessKit only fires on a text change, so repeating an identical string
	# (swiping back onto the same control) needs a zero-width space to force it.
	if _live_label.text == msg:
		_live_label.text = msg + "​"
	else:
		_live_label.text = msg


func _make_live_label() -> void:
	_live_label = Label.new()
	_live_label.name = "Live"
	_live_label.modulate = Color(1, 1, 1, 0)
	_live_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_label.focus_mode = Control.FOCUS_NONE
	_live_label.custom_minimum_size = Vector2.ZERO
	_live_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_live_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_live_label.accessibility_live = AccessibilityServer.LIVE_ASSERTIVE
	add_child(_live_label)


func _pick_voice() -> String:
	var lang := String(A11ySettings.get_value("accessible_ui/speech/voice_language"))
	if lang.is_empty():
		lang = OS.get_locale_language()
	var voices := DisplayServer.tts_get_voices_for_language(lang)
	if voices.size() > 0:
		return voices[0]
	voices = DisplayServer.tts_get_voices_for_language("en")
	if voices.size() > 0:
		return voices[0]
	var all_voices := DisplayServer.tts_get_voices()
	if all_voices.size() > 0:
		return String(all_voices[0].get("id", ""))
	return ""
