@tool
class_name DirectTouch
extends RefCounted

## Safe GDScript facade over the [code]DirectTouchServer[/code] native singleton.
##
## Every method here is a no-op that returns a sane default when the native
## library is missing or the platform is not iOS, so callers never need to
## guard. Prefer this over reaching for the singleton directly.
##
## [b]The one thing this cannot do[/b] is turn Direct Touch on for the player.
## Since iOS 14 VoiceOver gates it per app: the first time focus lands on the
## surface it says "Direct touch area. Use the rotor to enable direct touch for
## this app." There is no API to pre-enable it, and no API to ask whether it is
## currently enabled. See [method is_probably_engaged] for the workaround.

## Name the native library registers itself under. Deliberately not
## "DirectTouch" so this facade can own the friendlier identifier.
const SINGLETON := "DirectTouchServer"

## Mirrors [code]UIAccessibilityDirectTouchOptions[/code] (iOS 17+). Kept here
## so callers can name the flags without the singleton being present.
enum Option {
	NONE = 0,
	## Suppress VoiceOver audio while the surface is being touched. Intended for
	## apps that make their own sound on touch. Verify on device before using -
	## it may also swallow [method announce].
	SILENT_ON_TOUCH = 1,
	## Require a double tap on the surface before passthrough starts, instead of
	## starting as soon as it takes focus.
	REQUIRES_ACTIVATION = 2,
}

## Mirrors [code]UIAccessibilityPriority[/code] (iOS 17+). Apple's semantics,
## which are easy to assume backwards:
##
## - [b]LOW[/b] queues behind whatever is speaking. This is the polite one.
## - [b]DEFAULT[/b] interrupts what is speaking, and is itself interruptible.
##   This is what a screen reader cursor wants.
## - [b]HIGH[/b] interrupts what is speaking and then cannot be interrupted.
##
## Do not reach for HIGH to mean "urgent". Because a HIGH announcement refuses
## to be cut off, firing them in quick succession like swiping through a dialog,
## for example makes the first one lock out all the rest, and they queue instead of
## replacing each other. Use DEFAULT for that and keep HIGH for the rare thing
## that must be heard to the end.
enum Priority {
	LOW = 0,
	DEFAULT = 1,
	HIGH = 2,
}


## The native singleton, or [code]null[/code] where the library did not load.
static func server() -> Object:
	if not Engine.has_singleton(SINGLETON):
		return null
	return Engine.get_singleton(SINGLETON)


## True when this build can actually install a direct touch surface, i.e. iOS
## with the native library present. False everywhere else.
static func is_supported() -> bool:
	var s := server()
	return s != null and bool(s.is_supported())


## True while VoiceOver is running.
static func is_screen_reader_active() -> bool:
	var s := server()
	return s != null and bool(s.is_screen_reader_active())


## Install or remove the direct touch element over the Godot view.
static func set_surface_enabled(enabled: bool) -> void:
	var s := server()
	if s != null:
		s.set_surface_enabled(enabled)


static func is_surface_enabled() -> bool:
	var s := server()
	return s != null and bool(s.is_surface_enabled())


## What VoiceOver reads when the surface takes focus. Keep it short - the hint
## carries the instructions.
static func set_surface_label(text: String) -> void:
	var s := server()
	if s != null:
		s.set_surface_label(text)


static func set_surface_hint(text: String) -> void:
	var s := server()
	if s != null:
		s.set_surface_hint(text)


## Bitwise-or of [enum Option] values.
static func set_surface_options(flags: int) -> void:
	var s := server()
	if s != null:
		s.set_surface_options(flags)


## Ask VoiceOver to move its cursor onto the surface.
static func focus_surface() -> void:
	var s := server()
	if s != null:
		s.focus_surface()


## Speak [param text] through VoiceOver itself, using the player's own voice,
## rate and braille display.
##
## Announcements are not gated by Direct Touch, so this still reaches the player
## before they have enabled it - which is what makes the nudge in
## [method is_probably_engaged] possible.
static func announce(text: String, priority: Priority = Priority.DEFAULT) -> void:
	var s := server()
	if s != null:
		s.announce(text, int(priority))


## Cut off whatever the screen reader is saying right now.
##
## Best effort - iOS has no "stop speaking" API, so this interrupts the current
## utterance but cannot flush anything already queued behind it.
static func interrupt_speech() -> void:
	var s := server()
	if s != null:
		s.interrupt_speech()


## Best guess at whether passthrough is actually live.
##
## iOS exposes no way to ask. But the behaviour is observable: if VoiceOver is
## running and touch events are still arriving, they can only be arriving
## because passthrough let them through. [param seconds_since_last_touch] is how
## long it has been since the caller last saw an [InputEventScreenTouch].
static func is_probably_engaged(seconds_since_last_touch: float) -> bool:
	if not is_supported():
		return false
	if not is_screen_reader_active():
		# No VoiceOver means nothing is intercepting; touches arrive regardless.
		return true
	return is_surface_enabled() and seconds_since_last_touch < 1.0
