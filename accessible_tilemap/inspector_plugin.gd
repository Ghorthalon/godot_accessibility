@tool
extends EditorInspectorPlugin

signal tileset_selected(ts: TileSet)


func _can_handle(object: Object) -> bool:
	return object is TileSet


func _parse_begin(object: Object) -> void:
	emit_signal("tileset_selected", object as TileSet)
