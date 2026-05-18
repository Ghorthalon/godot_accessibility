@tool
class_name DoorEntry
extends Resource

## A doorway opening on a Room3D wall, now with scenes!
##
## Convention for door scenes referenced by scene_path: the scene's root Node3D
## sits at the doorway's center matches SceneQuery.wall_facing_transform with
## local -Z facing into the room. Choose a hinge side and stick with it across
## your door scenes so they swing consistently.

@export var side: String = "north"
@export var center_u: float = 0.0
@export var center_v: float = 0.0
@export var width: float = 1.2
@export var height: float = 2.1
@export var label: String = ""
@export_file("*.tscn") var scene_path: String = ""
