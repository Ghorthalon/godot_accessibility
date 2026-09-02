/**
 * DirectTouchServer - hands the Godot surface to VoiceOver as a direct touch area.
 *
 * Godot's iOS view (GDTView) sets no accessibility properties at all, and
 * AccessKit is not compiled for iOS, so the engine is invisible to VoiceOver.
 * That is why a GDScript screen reader currently has to run with VoiceOver
 * switched off - VoiceOver would otherwise eat every touch before Godot saw it.
 *
 * The fix iOS provides is UIAccessibilityTraitAllowsDirectInteraction: mark a
 * region as an accessibility element with that trait and VoiceOver passes raw
 * touches through instead of consuming them. This class installs exactly one
 * such element over the Godot view. Everything outside it - notably the system
 * keyboard, which lives in a separate UIWindow - keeps working under VoiceOver.
 *
 * The whole implementation is in direct_touch_ios.mm behind the platform hooks
 * declared at the bottom of this header. On every other platform those hooks
 * compile to stubs and the class is inert.
 */

#ifndef DIRECT_TOUCH_SERVER_H
#define DIRECT_TOUCH_SERVER_H

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class DirectTouchServer : public Object {
	GDCLASS(DirectTouchServer, Object)

public:
	/// Mirrors UIAccessibilityDirectTouchOptions (iOS 17+).
	enum Option {
		OPTION_NONE = 0,
		OPTION_SILENT_ON_TOUCH = 1,
		OPTION_REQUIRES_ACTIVATION = 2,
	};

	/// Mirrors UIAccessibilityPriority (iOS 17+). The names are Apple's and so
	/// are the semantics, which are easy to get backwards:
	///
	/// - LOW queues behind whatever is speaking.
	/// - DEFAULT interrupts what is speaking, and is itself interruptible.
	/// - HIGH interrupts what is speaking and then cannot be interrupted.
	///
	/// A screen reader cursor wants DEFAULT, not HIGH: swiping quickly through
	/// a dialog should cut each utterance off with the next one. HIGH makes the
	/// first announcement lock out every one behind it, so they queue instead.
	enum Priority {
		PRIORITY_LOW = 0,
		PRIORITY_DEFAULT = 1,
		PRIORITY_HIGH = 2,
	};

private:
	static DirectTouchServer *singleton;

	// Mirrored in C++ so the getters answer without crossing into UIKit, and so
	// the desired state survives the view being torn down and re-resolved.
	bool surface_enabled = false;
	String surface_label = "Game area";
	String surface_hint;
	int surface_options = OPTION_NONE;

protected:
	static void _bind_methods();

public:
	static DirectTouchServer *get_singleton();

	DirectTouchServer();
	~DirectTouchServer();

	bool is_supported() const;
	bool is_screen_reader_active() const;

	void set_surface_enabled(bool p_enabled);
	bool is_surface_enabled() const;

	void set_surface_label(const String &p_text);
	String get_surface_label() const;

	void set_surface_hint(const String &p_text);
	String get_surface_hint() const;

	void set_surface_options(int p_flags);
	int get_surface_options() const;

	void focus_surface();

	void announce(const String &p_text, int p_priority = PRIORITY_DEFAULT);

	/// Cut off whatever the screen reader is currently saying.
	///
	/// Best effort: iOS has no "stop speaking" API, so this posts an
	/// interrupting announcement with nothing worth saying in it. Anything
	/// already queued behind the current utterance still gets read.
	void interrupt_speech();

	// Called from the platform layer when UIKit posts a notification. Both
	// deferred onto the main loop before they reach script.
	void _notify_screen_reader_changed(bool p_active);
	void _notify_surface_focused(bool p_focused);
	void _notify_announcement_finished(const String &p_text, bool p_success);
};

} // namespace godot

VARIANT_ENUM_CAST(godot::DirectTouchServer::Option);
VARIANT_ENUM_CAST(godot::DirectTouchServer::Priority);

// Platform hooks. Implemented in direct_touch_ios.mm on iOS, and by the inert
// fallbacks in direct_touch_server.cpp everywhere else.
namespace direct_touch_platform {

bool is_supported();
bool is_screen_reader_active();
void start_observing();
void stop_observing();
/// Push the full desired surface state at UIKit. Idempotent, so callers can
/// simply re-apply after any change rather than tracking deltas.
void apply_surface(bool p_enabled, const godot::String &p_label, const godot::String &p_hint, int p_options);
void focus_surface();
void announce(const godot::String &p_text, int p_priority);
void interrupt_speech();

} // namespace direct_touch_platform

#endif // DIRECT_TOUCH_SERVER_H
