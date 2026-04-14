@tool
extends VBoxContainer

var plugin: EditorPlugin

# Shared state read/written by tabs
var current_bus_idx: int = -1

var announce: Label
var tab_buses
var tab_effects

func _ready() -> void:
	name = "Accessible Audio"

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

	tab_buses = preload("res://addons/accessible_audio/tab_buses.gd").new()
	tab_buses.name = "Buses"
	tab_buses.dock = self
	tabs.add_child(tab_buses)

	tab_effects = preload("res://addons/accessible_audio/tab_effects.gd").new()
	tab_effects.name = "Effects"
	tab_effects.dock = self
	tabs.add_child(tab_effects)

	AudioServer.bus_layout_changed.connect(_on_layout_changed)

func _on_layout_changed() -> void:
	if is_instance_valid(tab_buses):
		tab_buses._refresh()
	if is_instance_valid(tab_effects):
		tab_effects._refresh()

func _say(msg: String) -> void:
	# Force a change even when text repeats (AccessKit only fires on diff)
	if announce.text == msg:
		announce.text = msg + "\u200b"
	else:
		announce.text = msg
