@tool
extends EditorPlugin

const Dock := preload("res://addons/accessible_rooms/dock.tscn")
const AudioPreviewDebugger := preload("res://addons/accessible_rooms/audio_preview_debugger.gd")

var dock
var _audio_debugger: EditorDebuggerPlugin

const _AUTOLOAD_NAME := "AudioPreviewAutoload"
const _AUTOLOAD_PATH := "res://addons/accessible_rooms/audio_preview_autoload.gd"
const _AUTOLOAD_KEY := "autoload/AudioPreviewAutoload"

func _enter_tree():
    add_custom_type("Room3D", "Node3D",
        preload("res://addons/accessible_rooms/room_3d.gd"), null)
    add_custom_type("Ramp3D", "Node3D",
        preload("res://addons/accessible_rooms/ramp_3d.gd"), null)
    _audio_debugger = AudioPreviewDebugger.new()
    add_debugger_plugin(_audio_debugger)

    add_autoload_singleton(_AUTOLOAD_NAME, _AUTOLOAD_PATH)
    
    dock = Dock.instantiate()
    dock.plugin = self
    dock.audio_debugger = _audio_debugger
    add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

func _exit_tree():
    remove_control_from_docks(dock)
    dock.queue_free()
    remove_custom_type("Room3D")
    remove_custom_type("Ramp3D")
    remove_debugger_plugin(_audio_debugger)
    remove_autoload_singleton(_AUTOLOAD_NAME)
