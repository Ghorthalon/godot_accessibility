extends Node

## Runtime screen reader for in-game UI. Autoloaded as `AccessibleUI`.
##
## Godot 4.5+ bridges [Control] nodes to desktop screen readers through
## AccessKit, but this is not available on iOS. This layer stands in until that feature is implemented in Godot natively. it walks the live control tree, speaks each element through
## the platform's own voice, and maps VoiceOver's touch vocabulary onto Godot
## input.
##
## Three modes:
##
## - [b]Off[/b] - completely inert. No speech, no input touched.
## - [b]Announce only[/b] - speaks whatever gains focus, never swallows input.
##   Use this alongside a desktop screen reader, or for sighted players who
##   want spoken menus.
## - [b]Screen reader[/b] - touches belong to this layer. Swipe to move, double
##   tap to activate, exactly like VoiceOver.
##
## Defaults to Screen reader on mobile and Off elsewhere, because on desktop
## AccessKit already works and doubling up means hearing everything twice.
## The choice is remembered in `user://accessible_ui.cfg`.
##
## [b]On iOS, install the godot_direct_touch addon alongside this one.[/b]
## Without it VoiceOver eats every touch before Godot sees it, so this layer
## only works with VoiceOver switched off - which also leaves the system
## keyboard and every other native control unreadable. That addon hands the
## game surface to VoiceOver as a direct touch area, after which the two run
## together: gestures land here, and everything outside the game surface stays
## VoiceOver's. This layer detects it automatically and needs no configuration.
##
## Game code can talk to it directly:
##
## [codeblock]
## AccessibleUI.speak("Wave 3 incoming")
## AccessibleUI.announce_screen("Settings")
## AccessibleUI.focus_element($Menu/PlayButton)
## AccessibleUI.set_mode(AccessibleUI.Mode.OFF)
## [/codeblock]

signal element_focused(element: Control)
signal mode_changed(mode: int)

enum Mode { OFF, PASSIVE, INTERCEPT }

const CONFIG_PATH := "user://accessible_ui.cfg"
const TOGGLE_ACTION := &"a11y_toggle"

var _mode: int = Mode.OFF
var _speech: A11ySpeech
var _gestures: A11yGestureRecognizer
var _root_capture: A11yInputCapture
var _scope_capture: A11yInputCapture
var _relaxed_window: Window = null
var _relaxed_window_exclusive: bool = false

var _elements: Array[Control] = []
var _dirty: bool = true
var _cursor: int = -1
var _scope: Node = null
var _suppress_focus_echo: bool = false

## Native singleton published by the godot_direct_touch addon, or null when
## that addon is absent or the platform is not iOS. Looked up by name so this
## addon carries no hard dependency on it.
var _direct_touch: Object = null
var _nudged_about_direct_touch: bool = false
var _last_touch_msec: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS

	_speech = A11ySpeech.new()
	_speech.name = "Speech"
	add_child(_speech)

	_gestures = A11yGestureRecognizer.new()
	_gestures.name = "Gestures"
	add_child(_gestures)
	_gestures.tap.connect(_on_tap)
	_gestures.double_tap.connect(_on_double_tap)
	_gestures.swipe.connect(_on_swipe)
	_gestures.explore.connect(_on_explore)
	_gestures.two_finger_tap.connect(_on_two_finger_tap)
	_gestures.escape_scrub.connect(_on_escape_scrub)
	_gestures.three_finger_swipe.connect(_on_three_finger_swipe)
	_gestures.cycle_mode.connect(_on_cycle_mode)

	# The root is still setting up its children while autoloads run, so the
	# first install has to wait a frame.
	_sync_captures.call_deferred()

	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	for window in get_tree().root.find_children("*", "Window", true, false):
		_watch_window(window)
	if not get_tree().root.gui_focus_changed.is_connected(_on_focus_changed):
		get_tree().root.gui_focus_changed.connect(_on_focus_changed)

	_setup_direct_touch()

	set_mode(_initial_mode(), false)


func _unhandled_input(event: InputEvent) -> void:
	# The toggle stays live in every mode, including Off, otherwise a player
	# who turned it off has no way back other than the pause menu.
	if InputMap.has_action(TOGGLE_ACTION) and event.is_action_pressed(TOGGLE_ACTION):
		_on_cycle_mode()
		get_viewport().set_input_as_handled()


# --- public API ---------------------------------------------------------

func speak(text: String, priority: A11ySpeech.Priority = A11ySpeech.Priority.POLITE) -> void:
	if _mode == Mode.OFF or _speech == null:
		return
	_speech.speak(text, priority)


## Announce a new screen or menu and park the cursor at its first element.
func announce_screen(title: String) -> void:
	if _mode == Mode.OFF:
		return
	_dirty = true
	_refresh()
	_speech.speak(title, A11ySpeech.Priority.ASSERTIVE)
	_cursor = -1
	if not _elements.is_empty():
		_move_to(0)


## Move the cursor onto a specific control and speak it.
func focus_element(element: Control) -> void:
	if _mode == Mode.OFF or element == null:
		return
	_refresh()
	var index := _elements.find(element)
	if index == -1:
		# Not in the current scope (a hidden tab, etc). Speak it anyway rather
		# than silently doing nothing, since the caller asked explicitly.
		_speech.speak(A11yDescriber.describe(element, _verbosity()), A11ySpeech.Priority.ASSERTIVE)
		return
	_move_to(index)


func set_mode(mode: int, announce: bool = true) -> void:
	mode = clampi(mode, Mode.OFF, Mode.INTERCEPT)
	if mode == _mode:
		return
	_mode = mode
	if _gestures != null:
		_gestures.reset()
	_apply_mode()
	_save_config()
	mode_changed.emit(_mode)
	if _mode == Mode.OFF and _speech != null:
		_speech.stop()
	if announce and _speech != null:
		# Said even when switching to Off, so the player hears the switch land.
		_speech.speak(mode_name(_mode), A11ySpeech.Priority.ASSERTIVE)


func get_mode() -> int:
	return _mode


func is_active() -> bool:
	return _mode != Mode.OFF


func mode_name(mode: int) -> String:
	match mode:
		Mode.PASSIVE:
			return "Screen reader, announce only"
		Mode.INTERCEPT:
			return "Screen reader on"
		_:
			return "Screen reader off"


## The control the cursor is currently on, or null.
func get_focused_element() -> Control:
	if _cursor < 0 or _cursor >= _elements.size():
		return null
	var c := _elements[_cursor]
	return c if is_instance_valid(c) else null


# --- input capture and mode ---------------------------------------------

## Keep one capture on the root and, when a dialog is open, a second one inside
## it. 
func _sync_captures() -> void:
	var root := get_tree().root
	if _root_capture == null or not is_instance_valid(_root_capture):
		_root_capture = _make_capture()
		root.add_child(_root_capture)
	else:
		root.move_child(_root_capture, root.get_child_count() - 1)

	var window: Window = _scope as Window if _scope is Window else null
	if _scope_capture != null and is_instance_valid(_scope_capture):
		if _scope_capture.get_parent() == window:
			return
		_scope_capture.queue_free()
	_scope_capture = null
	_restore_exclusivity()
	if window != null:
		_scope_capture = _make_capture()
		window.add_child(_scope_capture)
		_relax_exclusivity(window)


## An exclusive [Window] throws away
## every touch that lands outside its own bounds, so a swipe next to a small
## dialog would reach nobody. In screen-reader mode we are already
## consuming those touches ourselves, so nothing can be pressed by accident;
## dropping exclusivity for the duration just lets the swipe be heard. The
## window's own setting is put back the moment it closes.
func _relax_exclusivity(window: Window) -> void:
	if _mode != Mode.INTERCEPT or not window.exclusive:
		return
	_relaxed_window = window
	_relaxed_window_exclusive = window.exclusive
	window.exclusive = false


func _restore_exclusivity() -> void:
	if _relaxed_window != null and is_instance_valid(_relaxed_window):
		_relaxed_window.exclusive = _relaxed_window_exclusive
	_relaxed_window = null


func _make_capture() -> A11yInputCapture:
	var capture := A11yInputCapture.new()
	capture.touch.connect(_on_touch)
	capture.intercept = _mode == Mode.INTERCEPT
	capture.mouse_filter = Control.MOUSE_FILTER_STOP if capture.intercept else Control.MOUSE_FILTER_IGNORE
	return capture


func _for_each_capture(action: Callable) -> void:
	for capture in [_root_capture, _scope_capture]:
		if capture != null and is_instance_valid(capture):
			action.call(capture)


func _apply_mode() -> void:
	var intercept := _mode == Mode.INTERCEPT
	if not intercept:
		_restore_exclusivity()
	_for_each_capture(func(c: A11yInputCapture):
		c.intercept = intercept
		c.mouse_filter = Control.MOUSE_FILTER_STOP if intercept else Control.MOUSE_FILTER_IGNORE)
	_dirty = true
	_apply_direct_touch()


func _on_touch(event: InputEvent) -> void:
	# Recorded before the mode check, because the only thing this timestamp is
	# used for is proving that touches reach us at all.
	_last_touch_msec = Time.get_ticks_msec()
	if _mode != Mode.INTERCEPT:
		return
	_gestures.handle(event)


func _initial_mode() -> int:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK and config.has_section_key("accessible_ui", "mode"):
		return int(config.get_value("accessible_ui", "mode", Mode.OFF))
	var configured := int(A11ySettings.get_value("accessible_ui/general/default_mode"))
	if bool(A11ySettings.get_value("accessible_ui/general/auto_enable_on_mobile_only")) and not _is_mobile():
		return Mode.OFF
	return configured


func _save_config() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value("accessible_ui", "mode", _mode)
	config.save(CONFIG_PATH)


static func _is_mobile() -> bool:
	return OS.get_name() in ["Android", "iOS"]


# --- element list -------------------------------------------------------

func _mark_dirty(_node: Node = null) -> void:
	_dirty = true


func _on_node_added(node: Node) -> void:
	_dirty = true
	if node is Window:
		_watch_window(node as Window)


func _on_node_removed(node: Node) -> void:
	_dirty = true
	if node is Window:
		_rescope.call_deferred()


## A dialog opening or closing changes which viewport owns input, and we have
## to follow it before the next touch - otherwise the capture is still on the
## old window and the gesture that would tell us to move never arrives.
func _watch_window(window: Window) -> void:
	if not window.visibility_changed.is_connected(_rescope):
		window.visibility_changed.connect(_rescope)


func _rescope() -> void:
	if _mode == Mode.OFF:
		return
	_dirty = true
	_refresh()


## Rebuild only when something actually changed, and only when someone asks -
## a game with a busy scene tree would otherwise pay for this every frame.
func _refresh() -> void:
	var scope := A11yElementTree.scope_of(get_tree())
	if scope != _scope:
		_scope = scope
		_dirty = true
		_cursor = -1
		_sync_captures()
	if not _dirty:
		return
	_dirty = false
	var previous := get_focused_element()
	_elements = A11yElementTree.collect(_scope)
	if previous != null:
		# Keep the cursor on the same control across a rebuild where we can.
		_cursor = _elements.find(previous)
	_cursor = clampi(_cursor, -1, _elements.size() - 1)


func _move_to(index: int) -> void:
	if index < 0 or index >= _elements.size():
		return
	# Read the section we are leaving before the cursor moves, so crossing into
	# a new one can be announced ahead of the element itself.
	var previous_group: Node = null
	if _cursor >= 0 and _cursor < _elements.size() and is_instance_valid(_elements[_cursor]):
		previous_group = A11yElementTree.group_of(_elements[_cursor])
	_cursor = index
	var c := _elements[_cursor]
	if not is_instance_valid(c):
		return
	if A11yElementTree.can_focus(c):
		# Grab real focus too, so the visual focus ring follows the cursor and
		# keyboard players and screen reader players stay on the same element.
		_suppress_focus_echo = true
		c.grab_focus()
		_suppress_focus_echo = false
	element_focused.emit(c)
	var sentence := A11yDescriber.describe(c, _verbosity())
	var group := A11yElementTree.group_of(c)
	if group != previous_group:
		# Leaving a section for ungrouped content is the one move with no new
		# heading to announce, so say what we left instead of going quiet.
		if group == null and previous_group != null and _verbosity() > A11yDescriber.Verbosity.TERSE:
			var leaving := A11yDescriber.group_name_of(previous_group)
			if not leaving.is_empty():
				sentence = "Out of %s. %s" % [leaving, sentence]
		# `group == c` is an operable widget that names its own section; its
		# own description already carries the name.
		elif group != null and group != c:
			var heading := A11yDescriber.describe_group(group, _verbosity())
			if not heading.is_empty():
				sentence = heading + " " + sentence
	_speech.speak(sentence, A11ySpeech.Priority.ASSERTIVE)


func _step_cursor(delta: int) -> void:
	_refresh()
	if _elements.is_empty():
		_speech.speak("Nothing to read.", A11ySpeech.Priority.ASSERTIVE)
		return
	var next := _cursor + delta
	if _cursor == -1:
		next = 0 if delta > 0 else _elements.size() - 1
	if next < 0 or next >= _elements.size():
		# No wrapping: hitting an edge should tell you where you are, not
		# teleport you to the other end of the screen.
		_speech.speak("First item." if delta < 0 else "Last item.", A11ySpeech.Priority.ASSERTIVE)
		_haptic()
		return
	_move_to(next)
	_haptic()


func _verbosity() -> int:
	return int(A11ySettings.get_value("accessible_ui/general/verbosity"))


func _haptic() -> void:
	if bool(A11ySettings.get_value("accessible_ui/general/haptics")):
		Input.vibrate_handheld(20)


# --- gesture handlers ---------------------------------------------------

func _on_swipe(direction: String) -> void:
	match direction:
		"right":
			_step_cursor(1)
		"left":
			_step_cursor(-1)
		"up":
			_on_adjust(1)
		"down":
			_on_adjust(-1)


func _on_adjust(delta: int) -> void:
	var c := get_focused_element()
	if c == null:
		return
	if not A11yDescriber.is_adjustable(c):
		_speech.speak("Not adjustable.", A11ySpeech.Priority.ASSERTIVE)
		return
	var result := A11yActions.adjust(c, delta)
	if result.is_empty():
		return
	_speech.speak(result, A11ySpeech.Priority.ASSERTIVE)
	_haptic()


func _on_tap(position: Vector2) -> void:
	_speak_at(position)


func _on_explore(position: Vector2) -> void:
	_speak_at(position, true)


func _speak_at(position: Vector2, only_on_change: bool = false) -> void:
	_refresh()
	var c := A11yElementTree.element_at(_elements, position)
	if c == null:
		if not only_on_change:
			_speech.speak("Nothing here.", A11ySpeech.Priority.ASSERTIVE)
		return
	var index := _elements.find(c)
	if only_on_change and index == _cursor:
		return
	_move_to(index)
	_haptic()


func _on_double_tap() -> void:
	var c := get_focused_element()
	if c == null:
		return
	# The captures are sitting on top swallowing input, a synthesized press has
	# to reach the control underneath, so they stand aside for the one call.
	_for_each_capture(func(cap: A11yInputCapture): cap.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	A11yActions.activate(c)
	_apply_mode()
	_haptic()
	# Whatever the press did - toggled, opened a dialog, changed a label - the
	# element list is stale now.
	_dirty = true
	call_deferred("_announce_after_activate", c)


func _announce_after_activate(c: Control) -> void:
	if not is_instance_valid(c):
		return
	_refresh()
	if _scope is Window and not _elements.is_empty() and _elements.find(c) == -1:
		# Activation opened a dialog: read it and start at its first element.
		var w := _scope as Window
		# A menu is one element that already says its own name, so announcing
		# the window as well would say it twice.
		if not (w is PopupMenu):
			_speech.speak(A11yDescriber.window_title_of(w), A11ySpeech.Priority.ASSERTIVE)
		_move_to(0)
		return
	var closed_menu := A11yElementTree.menu_of(c)
	if closed_menu != null and not closed_menu.visible:
		# An entry was picked and the menu closed behind it. Park the cursor on
		# whatever opened it, so the next swipe carries on from there instead of
		# from the top of the screen
		var opener := closed_menu.get_parent() as Control
		var opener_index := _elements.find(opener) if opener != null else -1
		if opener_index != -1:
			_move_to(opener_index)
			return
	var state := A11yDescriber.state_of(c)
	if not state.is_empty():
		_speech.speak(state, A11ySpeech.Priority.ASSERTIVE)


func _on_two_finger_tap() -> void:
	_speech.stop()


func _on_escape_scrub() -> void:
	_refresh()
	var result := A11yActions.escape(_scope)
	if result.is_empty():
		_speech.speak("Nothing to close.", A11ySpeech.Priority.ASSERTIVE)
		return
	_speech.speak(result, A11ySpeech.Priority.ASSERTIVE)
	_dirty = true
	_cursor = -1


func _on_three_finger_swipe(direction: String) -> void:
	_refresh()
	if _elements.is_empty():
		return
	var step := 1 if direction == "right" or direction == "down" else -1
	var focused := get_focused_element()
	var current_group: Node = A11yElementTree.group_of(focused) if focused != null else null
	var index := _cursor
	if index < 0:
		# Cursor never placed: the first jump should land on the first section,
		# not step over it.
		_move_to(0 if step > 0 else _elements.size() - 1)
		_haptic()
		return
	while true:
		index += step
		if index < 0 or index >= _elements.size():
			_speech.speak("First group." if step < 0 else "Last group.", A11ySpeech.Priority.ASSERTIVE)
			return
		var group := A11yElementTree.group_of(_elements[index])
		if group != current_group:
			_move_to(index)
			_haptic()
			return


func _on_cycle_mode() -> void:
	set_mode((_mode + 1) % 3)


func _on_focus_changed(control: Control) -> void:
	# Keyboard, gamepad and game code all move focus without telling us.
	if _mode == Mode.OFF or _suppress_focus_echo or control == null:
		return
	_refresh()
	var index := _elements.find(control)
	if index == -1 or index == _cursor:
		return
	_cursor = index
	element_focused.emit(control)
	_speech.speak(A11yDescriber.describe(control, _verbosity()), A11ySpeech.Priority.ASSERTIVE)


# --- iOS direct touch ---------------------------------------------------
#
# VoiceOver consumes every touch before Godot sees it, which is why this addon
# otherwise has to be used with VoiceOver off. The godot_direct_touch addon
# marks the Godot surface as a direct touch area so VoiceOver passes touches
# straight through, and everything outside it - the system keyboard above all -
# stays readable. None of this is required: with that addon absent, the block
# below is inert and behaviour is exactly as it was.

## How long to wait after handing the surface to VoiceOver before assuming the
## player has not found the Direct Touch switch. Long enough not to talk over
## someone who is simply reading the screen first.
const _DIRECT_TOUCH_NUDGE_DELAY: float = 6.0

const _DIRECT_TOUCH_SINGLETON := "DirectTouchServer"


func _setup_direct_touch() -> void:
	if not Engine.has_singleton(_DIRECT_TOUCH_SINGLETON):
		return
	var server: Object = Engine.get_singleton(_DIRECT_TOUCH_SINGLETON)
	if not server.is_supported():
		return
	_direct_touch = server
	_direct_touch.set_surface_label(String(A11ySettings.get_value("accessible_ui/general/surface_label")))
	_direct_touch.set_surface_hint(String(A11ySettings.get_value("accessible_ui/general/surface_hint")))
	_direct_touch.screen_reader_changed.connect(_on_screen_reader_changed)


## Hand the surface to VoiceOver whenever this layer is doing anything, 
func _apply_direct_touch() -> void:
	if _direct_touch == null:
		return
	var wanted := _mode != Mode.OFF
	if _direct_touch.is_surface_enabled() == wanted:
		return
	_direct_touch.set_surface_enabled(wanted)
	if wanted:
		_nudged_about_direct_touch = false
		_schedule_direct_touch_nudge()


func _on_screen_reader_changed(active: bool) -> void:
	if active and _mode != Mode.OFF:
		_nudged_about_direct_touch = false
		_schedule_direct_touch_nudge()


func _schedule_direct_touch_nudge() -> void:
	if _direct_touch == null or not _direct_touch.is_screen_reader_active():
		return
	get_tree().create_timer(_DIRECT_TOUCH_NUDGE_DELAY).timeout.connect(
		_maybe_nudge_about_direct_touch, CONNECT_ONE_SHOT
	)


## iOS gates direct touch per app and offers no way to ask whether the player
## has enabled it. But the state is observable from here: if VoiceOver is
## running and no touch has ever reached us, VoiceOver is still swallowing them.
##
## The nudge goes out as a VoiceOver announcement rather than through
## [member _speech], because announcements are not themselves gated by direct
## touch - so this is one of the few things that can still be said to a player
## who is stuck.
func _maybe_nudge_about_direct_touch() -> void:
	if _direct_touch == null or _nudged_about_direct_touch:
		return
	if _mode == Mode.OFF or not _direct_touch.is_screen_reader_active():
		return
	if _last_touch_msec > 0:
		return
	_nudged_about_direct_touch = true
	_direct_touch.announce(
		String(A11ySettings.get_value("accessible_ui/general/surface_hint")), 1
	)
