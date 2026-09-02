@tool
class_name A11yInputCapture
extends Control

## The surface that consumes touches in screen-reader mode.
##
## It has to live inside whatever [Viewport] is currently in charge. An
## embedded [Window] so any dialog or popup routes input to its own subtree,
## so a capture parked on the scene root would go deaf the moment a dialog
## opened. [AccessibleUI]
## moves this node to follow the active window.

signal touch(event: InputEvent)

## While false the node is inert: events are seen but nothing is consumed.
var intercept: bool = false


func _init() -> void:
	name = "AccessibleUICapture"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Never an element in our own element list.
	set_meta("a11y_hidden", true)


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	touch.emit(event)
	if intercept:
		# Real presses only ever happen because we synthesized one on a double
		# tap. That is the reason of screen-reader mode, and the reason
		# a stray finger cannot fire a button by accident.
		get_viewport().set_input_as_handled()
