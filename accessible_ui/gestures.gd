@tool
class_name A11yGestureRecognizer
extends Node

## Recognises the VoiceOver-style touch vocabulary from raw
## [InputEventScreenTouch] / [InputEventScreenDrag] events.
##
## The gesture map:
##
## [codeblock]
## swipe right / left        next / previous element
## swipe up / down           increase / decrease an adjustable element
## single tap                speak the element you touched, move the cursor to it
## drag (slow)               explore by touch - speaks each element you cross
## double tap                activate the element at the cursor
## two-finger tap            stop speaking
## two-finger scrub          go back / close the open dialog
## three-finger swipe        jump to the previous / next group
## three-finger triple tap   cycle the screen reader mode
## [/codeblock]
##
## Timings and distances come from project settings so a game with big
## touch targets or a slower audience can loosen them.
##
## Everything is decided on release, not on press: a fast short stroke is a
## swipe, a slow one is exploration, and the finger count is whatever was
## highest during the gesture (fingers rarely land on the exact same frame).

signal tap(position: Vector2)
signal double_tap()
signal swipe(direction: String)
signal explore(position: Vector2)
signal two_finger_tap()
signal escape_scrub()
signal three_finger_swipe(direction: String)
signal cycle_mode()

## A "tap" is allowed to wobble this far, in pixels, before it counts as a drag.
const TAP_SLOP: float = 24.0
## How far the two-finger centroid must travel each way for a reversal to
## count as part of a scrub, rather than a wobble.
const SCRUB_LEG: float = 40.0
const SCRUB_LEGS_REQUIRED: int = 3

var _touches: Dictionary = {}
var _max_fingers: int = 0
var _start_time: float = 0.0
var _primary_index: int = -1
var _explored: bool = false
var _scrub_dir: int = 0
var _scrub_legs: int = 0
var _scrub_anchor: float = 0.0

var _pending_taps: int = 0
var _pending_fingers: int = 0
var _pending_pos: Vector2 = Vector2.ZERO
var _pending_deadline: float = 0.0


func _process(_delta: float) -> void:
	if _pending_taps == 0:
		return
	if _now() < _pending_deadline:
		return
	_flush_taps()


## Feed one input event in. Returns true if it was a touch event we consumed.
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_press(t)
		else:
			_on_release(t)
		return true
	if event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
		return true
	return false


## Forget any half-finished gesture (mode switch, scene change).
func reset() -> void:
	_touches.clear()
	_max_fingers = 0
	_primary_index = -1
	_explored = false
	_scrub_legs = 0
	_scrub_dir = 0
	_pending_taps = 0


func _on_press(t: InputEventScreenTouch) -> void:
	if _touches.is_empty():
		_start_time = _now()
		_max_fingers = 0
		_explored = false
		_scrub_legs = 0
		_scrub_dir = 0
		_scrub_anchor = t.position.x
		_primary_index = t.index
	_touches[t.index] = {"start": t.position, "pos": t.position}
	_max_fingers = maxi(_max_fingers, _touches.size())


func _on_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		return
	_touches[d.index]["pos"] = d.position

	if _max_fingers == 1 and _touches.size() == 1:
		# A finger that has been down longer than the hold delay is exploring,
		# not swiping. Once exploring starts, release will not fire a swipe.
		if _now() - _start_time >= _setting("explore_hold_delay"):
			_explored = true
			explore.emit(d.position)
	elif _max_fingers == 2 and _touches.size() == 2:
		_track_scrub()


func _on_release(t: InputEventScreenTouch) -> void:
	if not _touches.has(t.index):
		return
	_touches[t.index]["pos"] = t.position
	if _touches.size() > 1:
		# Wait for the last finger; the gesture is not over yet.
		_touches.erase(t.index)
		return

	var record: Dictionary = _touches[_primary_index] if _touches.has(_primary_index) else _touches[t.index]
	var start: Vector2 = record["start"]
	var end: Vector2 = record["pos"]
	var travel := end - start
	var duration := _now() - _start_time
	var fingers := _max_fingers
	_touches.clear()

	if fingers == 2 and _scrub_legs >= SCRUB_LEGS_REQUIRED:
		escape_scrub.emit()
		return

	var is_swipe := travel.length() >= _setting("swipe_min_distance") and duration <= _setting("swipe_max_duration")
	if is_swipe and not (_explored and fingers == 1):
		var dir := _direction(travel)
		match fingers:
			1:
				swipe.emit(dir)
			3:
				three_finger_swipe.emit(dir)
		return

	if _explored:
		# Exploration already spoke everything it crossed; lifting off is not
		# a tap, or every explore would end by re-announcing.
		return

	if travel.length() <= TAP_SLOP and duration <= _setting("swipe_max_duration"):
		_register_tap(fingers, end)


func _register_tap(fingers: int, position: Vector2) -> void:
	if fingers != _pending_fingers:
		_flush_taps()
		_pending_fingers = fingers
	_pending_taps += 1
	_pending_pos = position
	_pending_deadline = _now() + _setting("double_tap_window")

	# Fire the gestures that cannot be extended into a longer tap run as soon
	# as they complete, so activation feels immediate.
	if _pending_fingers == 1 and _pending_taps == 2:
		double_tap.emit()
		_pending_taps = 0
	elif _pending_fingers == 3 and _pending_taps == 3:
		cycle_mode.emit()
		_pending_taps = 0


func _flush_taps() -> void:
	var count := _pending_taps
	var fingers := _pending_fingers
	var position := _pending_pos
	_pending_taps = 0
	if count == 0:
		return
	if fingers == 1 and count == 1:
		tap.emit(position)
	elif fingers == 2 and count == 1:
		two_finger_tap.emit()


func _track_scrub() -> void:
	var x := 0.0
	for index in _touches:
		x += _touches[index]["pos"].x
	x /= float(_touches.size())
	var offset := x - _scrub_anchor
	if absf(offset) < SCRUB_LEG:
		return
	var dir := int(signf(offset))
	if dir != _scrub_dir:
		_scrub_dir = dir
		_scrub_legs += 1
	_scrub_anchor = x


static func _direction(travel: Vector2) -> String:
	if absf(travel.x) >= absf(travel.y):
		return "right" if travel.x > 0.0 else "left"
	return "down" if travel.y > 0.0 else "up"


static func _setting(name: String) -> float:
	return float(A11ySettings.get_value("accessible_ui/gestures/" + name))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
