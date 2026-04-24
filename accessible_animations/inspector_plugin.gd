@tool
extends EditorInspectorPlugin

signal animation_selected(anim: Animation)


func _can_handle(object: Object) -> bool:
	return object is Animation


func _parse_begin(object: Object) -> void:
	emit_signal("animation_selected", object as Animation)
