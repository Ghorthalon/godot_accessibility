#include "register_types.h"

#include "direct_touch_server.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static DirectTouchServer *direct_touch_server = nullptr;

void initialize_direct_touch_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DirectTouchServer);
	direct_touch_server = memnew(DirectTouchServer);
	// Registered under DirectTouchServer, not DirectTouch: the addon's GDScript
	// facade owns that name, and accessible_ui soft-depends on this addon with
	// Engine.has_singleton("DirectTouchServer") rather than a hard reference.
	Engine::get_singleton()->register_singleton("DirectTouchServer", direct_touch_server);
}

void uninitialize_direct_touch_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("DirectTouchServer");
	if (direct_touch_server != nullptr) {
		memdelete(direct_touch_server);
		direct_touch_server = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT direct_touch_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_direct_touch_module);
	init_obj.register_terminator(uninitialize_direct_touch_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
