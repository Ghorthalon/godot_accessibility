#include "direct_touch_server.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

DirectTouchServer *DirectTouchServer::singleton = nullptr;

DirectTouchServer *DirectTouchServer::get_singleton() {
	return singleton;
}

DirectTouchServer::DirectTouchServer() {
	singleton = this;
	direct_touch_platform::start_observing();
}

DirectTouchServer::~DirectTouchServer() {
	// Take the surface back down on the way out. Leaving a direct touch element
	// installed on a view Godot is about to destroy would strand VoiceOver on a
	// dead element.
	direct_touch_platform::apply_surface(false, surface_label, surface_hint, surface_options);
	direct_touch_platform::stop_observing();
	if (singleton == this) {
		singleton = nullptr;
	}
}

bool DirectTouchServer::is_supported() const {
	return direct_touch_platform::is_supported();
}

bool DirectTouchServer::is_screen_reader_active() const {
	return direct_touch_platform::is_screen_reader_active();
}

void DirectTouchServer::set_surface_enabled(bool p_enabled) {
	surface_enabled = p_enabled;
	direct_touch_platform::apply_surface(surface_enabled, surface_label, surface_hint, surface_options);
}

bool DirectTouchServer::is_surface_enabled() const {
	return surface_enabled;
}

void DirectTouchServer::set_surface_label(const String &p_text) {
	surface_label = p_text;
	direct_touch_platform::apply_surface(surface_enabled, surface_label, surface_hint, surface_options);
}

String DirectTouchServer::get_surface_label() const {
	return surface_label;
}

void DirectTouchServer::set_surface_hint(const String &p_text) {
	surface_hint = p_text;
	direct_touch_platform::apply_surface(surface_enabled, surface_label, surface_hint, surface_options);
}

String DirectTouchServer::get_surface_hint() const {
	return surface_hint;
}

void DirectTouchServer::set_surface_options(int p_flags) {
	surface_options = p_flags;
	direct_touch_platform::apply_surface(surface_enabled, surface_label, surface_hint, surface_options);
}

int DirectTouchServer::get_surface_options() const {
	return surface_options;
}

void DirectTouchServer::focus_surface() {
	direct_touch_platform::focus_surface();
}

void DirectTouchServer::announce(const String &p_text, int p_priority) {
	if (p_text.strip_edges().is_empty()) {
		return;
	}
	direct_touch_platform::announce(p_text, p_priority);
}

// The platform layer calls these from UIKit notification callbacks. Those fire
// on the main thread, which is also Godot's iOS main loop thread, but the frame
// may be mid-iteration - so hop to an idle frame before touching script.
void DirectTouchServer::_notify_screen_reader_changed(bool p_active) {
	call_deferred("emit_signal", "screen_reader_changed", p_active);
}

void DirectTouchServer::_notify_surface_focused(bool p_focused) {
	call_deferred("emit_signal", "surface_focused", p_focused);
}

void DirectTouchServer::_notify_announcement_finished(const String &p_text, bool p_success) {
	call_deferred("emit_signal", "announcement_finished", p_text, p_success);
}

void DirectTouchServer::interrupt_speech() {
	direct_touch_platform::interrupt_speech();
}

void DirectTouchServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_supported"), &DirectTouchServer::is_supported);
	ClassDB::bind_method(D_METHOD("is_screen_reader_active"), &DirectTouchServer::is_screen_reader_active);

	ClassDB::bind_method(D_METHOD("set_surface_enabled", "enabled"), &DirectTouchServer::set_surface_enabled);
	ClassDB::bind_method(D_METHOD("is_surface_enabled"), &DirectTouchServer::is_surface_enabled);

	ClassDB::bind_method(D_METHOD("set_surface_label", "text"), &DirectTouchServer::set_surface_label);
	ClassDB::bind_method(D_METHOD("get_surface_label"), &DirectTouchServer::get_surface_label);

	ClassDB::bind_method(D_METHOD("set_surface_hint", "text"), &DirectTouchServer::set_surface_hint);
	ClassDB::bind_method(D_METHOD("get_surface_hint"), &DirectTouchServer::get_surface_hint);

	ClassDB::bind_method(D_METHOD("set_surface_options", "flags"), &DirectTouchServer::set_surface_options);
	ClassDB::bind_method(D_METHOD("get_surface_options"), &DirectTouchServer::get_surface_options);

	ClassDB::bind_method(D_METHOD("focus_surface"), &DirectTouchServer::focus_surface);
	ClassDB::bind_method(D_METHOD("announce", "text", "priority"), &DirectTouchServer::announce, DEFVAL(PRIORITY_DEFAULT));
	ClassDB::bind_method(D_METHOD("interrupt_speech"), &DirectTouchServer::interrupt_speech);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "surface_enabled"), "set_surface_enabled", "is_surface_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "surface_label"), "set_surface_label", "get_surface_label");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "surface_hint"), "set_surface_hint", "get_surface_hint");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "surface_options", PROPERTY_HINT_FLAGS, "Silent On Touch,Requires Activation"), "set_surface_options", "get_surface_options");

	ADD_SIGNAL(MethodInfo("screen_reader_changed", PropertyInfo(Variant::BOOL, "active")));
	ADD_SIGNAL(MethodInfo("surface_focused", PropertyInfo(Variant::BOOL, "focused")));
	ADD_SIGNAL(MethodInfo("announcement_finished", PropertyInfo(Variant::STRING, "text"), PropertyInfo(Variant::BOOL, "success")));

	BIND_ENUM_CONSTANT(OPTION_NONE);
	BIND_ENUM_CONSTANT(OPTION_SILENT_ON_TOUCH);
	BIND_ENUM_CONSTANT(OPTION_REQUIRES_ACTIVATION);

	BIND_ENUM_CONSTANT(PRIORITY_LOW);
	BIND_ENUM_CONSTANT(PRIORITY_DEFAULT);
	BIND_ENUM_CONSTANT(PRIORITY_HIGH);
}

// Inert fallbacks for every platform that is not iOS. Keeping them here rather
// than in #ifdefs at each call site means the class body reads the same
// everywhere and only one file ever mentions UIKit.
#ifndef IOS_ENABLED

namespace direct_touch_platform {

bool is_supported() {
	return false;
}

bool is_screen_reader_active() {
	return false;
}

void start_observing() {}
void stop_observing() {}
void apply_surface(bool, const String &, const String &, int) {}
void focus_surface() {}
void announce(const String &, int) {}
void interrupt_speech() {}

} // namespace direct_touch_platform

#endif // !IOS_ENABLED
