@tool
class_name ConfirmBar
extends HBoxContainer

## A keyboard-first, screen-reader-first "are you sure?" bar.
##
## Every operation that would overlap geometry, break a doorway connection, or
## destroy work routes through here instead of acting immediately. The addon
## deliberately has no hidden force modifier: if an action is risky, the user
## hears why and presses Proceed, or presses Cancel and nothing happened.
##
##     confirm.ask("Room5 would overlap Kitchen.", "Place anyway",
##             func(): _really_place(...))
##
## The bar is hidden until asked, so it costs nothing in the tab order when
## there is no pending decision.

var dock  # dock.gd, for announcements

var _label: Label
var _proceed_btn: Button
var _cancel_btn: Button
var _on_proceed: Callable
var _pending: bool = false

func _init() -> void:
	visible = false
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)
	_proceed_btn = Button.new()
	_proceed_btn.text = "Proceed"
	_proceed_btn.pressed.connect(_on_proceed_pressed)
	add_child(_proceed_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	add_child(_cancel_btn)

## Shows the bar, announces the reason, and parks focus on Proceed so the
## decision is one keypress away in either direction.
## proceed_label names the consequence ("Place anyway", "Bake and replace"),
## never a bare "OK" -- the button text is what a screen reader reads back.
func ask(message: String, proceed_label: String, on_proceed: Callable) -> void:
	_on_proceed = on_proceed
	_pending = true
	_label.text = message
	_proceed_btn.text = proceed_label
	visible = true
	_proceed_btn.call_deferred("grab_focus")
	if dock != null:
		dock._say_err("%s Choose %s, or Cancel." % [message, proceed_label])

## Hides the bar and drops any pending action. Call when the selection changes
## or the user navigates away, so a stale question can never be answered.
func dismiss() -> void:
	_pending = false
	_on_proceed = Callable()
	visible = false

func has_pending() -> bool:
	return _pending

func _on_proceed_pressed() -> void:
	if not _pending: return
	var cb := _on_proceed
	dismiss()
	if cb.is_valid(): cb.call()

func _on_cancel_pressed() -> void:
	if not _pending: return
	dismiss()
	if dock != null: dock._say("Cancelled, nothing was changed.")
