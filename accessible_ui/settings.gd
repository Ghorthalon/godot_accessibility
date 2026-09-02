@tool
class_name A11ySettings
extends RefCounted

## Single source of truth for every `accessible_ui/*` project setting.
##
## `plugin.gd` calls [method register] once when the addon is enabled, which
## writes the defaults into project.godot so they show up in Project Settings
## and can be tweaked per game. Runtime code reads them through [method get_value],
## which falls back to the default if the setting was never written (e.g. the
## addon files were copied in by hand without enabling the plugin).

## key -> [default, PROPERTY_HINT_*, hint_string]
const DEFAULTS: Dictionary = {
	"accessible_ui/general/default_mode": [2, PROPERTY_HINT_ENUM, "Off,Announce only,Screen reader"],
	"accessible_ui/general/auto_enable_on_mobile_only": [true, PROPERTY_HINT_NONE, ""],
	"accessible_ui/general/haptics": [true, PROPERTY_HINT_NONE, ""],
	"accessible_ui/general/verbosity": [1, PROPERTY_HINT_ENUM, "Terse,Normal,Verbose"],
	# Read by the godot_direct_touch addon on iOS. The label is what VoiceOver
	# says when its cursor lands on the game surface; the hint is the sentence
	# that tells a stuck player how to get past VoiceOver's Direct Touch gate,
	# and is also what gets announced if no touch ever reaches us.
	"accessible_ui/general/surface_label": ["Game area", PROPERTY_HINT_NONE, ""],
	"accessible_ui/general/surface_hint": [
		"Turn on Direct Touch in the VoiceOver rotor to play.", PROPERTY_HINT_NONE, ""
	],
	"accessible_ui/speech/voice_language": ["", PROPERTY_HINT_NONE, ""],
	"accessible_ui/speech/rate": [1.0, PROPERTY_HINT_RANGE, "0.1,10.0,0.05"],
	"accessible_ui/speech/pitch": [1.0, PROPERTY_HINT_RANGE, "0.1,2.0,0.05"],
	"accessible_ui/speech/volume": [100, PROPERTY_HINT_RANGE, "0,100,1"],
	"accessible_ui/gestures/swipe_min_distance": [64.0, PROPERTY_HINT_RANGE, "8.0,512.0,1.0"],
	"accessible_ui/gestures/swipe_max_duration": [0.5, PROPERTY_HINT_RANGE, "0.1,2.0,0.05"],
	"accessible_ui/gestures/double_tap_window": [0.3, PROPERTY_HINT_RANGE, "0.1,1.0,0.05"],
	"accessible_ui/gestures/explore_hold_delay": [0.15, PROPERTY_HINT_RANGE, "0.0,1.0,0.05"],
}

## Mirrors AccessibleUI.Mode. Duplicated as plain ints so this file stays
## dependency-free and usable from the editor plugin before the autoload exists.
const MODE_OFF: int = 0
const MODE_PASSIVE: int = 1
const MODE_INTERCEPT: int = 2


static func register() -> void:
	for key in DEFAULTS:
		var spec: Array = DEFAULTS[key]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, spec[0])
		ProjectSettings.set_initial_value(key, spec[0])
		ProjectSettings.add_property_info({
			"name": key,
			"type": typeof(spec[0]),
			"hint": spec[1],
			"hint_string": spec[2],
		})
	ProjectSettings.save()


static func get_value(key: String) -> Variant:
	var fallback: Variant = null
	if DEFAULTS.has(key):
		fallback = DEFAULTS[key][0]
	return ProjectSettings.get_setting(key, fallback)
