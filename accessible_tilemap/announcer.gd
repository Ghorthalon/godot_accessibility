@tool
class_name AccessibleAnnouncer
extends Node

enum Priority { POLITE, ASSERTIVE }

var _live_label: Label
var _use_tts: bool = true


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

	if _live_label != null and is_instance_valid(_live_label):
		# AccessKit only fires on a text change. If we're saying the same thing
		# twice (e.g. arrow-key spam on the same cell), append a zero-width
		# space to force a change.
		if _live_label.text == text:
			_live_label.text = text + "\u200b"
		else:
			_live_label.text = text


func stop() -> void:
	pass


func set_tts_enabled(enabled: bool) -> void:
	_use_tts = enabled
