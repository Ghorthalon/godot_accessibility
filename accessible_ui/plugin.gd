@tool
extends EditorPlugin

## Installs the runtime screen reader.
##
## Unlike the other addons here, this one has no editor UI at all - everything
## it does happens in the running game. Enabling the plugin registers the
## `AccessibleUI` autoload, writes the `accessible_ui/*` project settings so
## they are editable in Project Settings, and adds a keyboard toggle action so
## the layer can be exercised on desktop without a touchscreen.

const AUTOLOAD_NAME := "AccessibleUI"
const AUTOLOAD_PATH := "res://addons/accessible_ui/accessible_ui.gd"
const TOGGLE_ACTION := "a11y_toggle"
const TOGGLE_SETTING := "input/" + TOGGLE_ACTION


func _enter_tree() -> void:
	A11ySettings.register()
	_register_toggle_action()
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


## Ctrl+Alt+A cycles the mode. Left in the project's input map rather than
## hardcoded so a game can rebind or remove it; we never overwrite an existing
## action of the same name.
func _register_toggle_action() -> void:
	if ProjectSettings.has_setting(TOGGLE_SETTING):
		return
	var event := InputEventKey.new()
	event.keycode = KEY_A
	event.ctrl_pressed = true
	event.alt_pressed = true
	ProjectSettings.set_setting(TOGGLE_SETTING, {
		"deadzone": 0.5,
		"events": [event],
	})
	ProjectSettings.save()
