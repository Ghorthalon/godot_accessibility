@tool
extends VBoxContainer

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

func _say(msg: String) -> void:
	if announce.text == msg:
		announce.text = msg + "​"
	else:
		announce.text = msg
