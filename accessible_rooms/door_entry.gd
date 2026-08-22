@tool
class_name DoorEntry
extends Resource

## A doorway opening on a Room3D wall, now with scenes!
##
## Convention for door scenes referenced by scene_path: the scene's root Node3D
## sits at the doorway's center matches SceneQuery.wall_facing_transform with
## local -Z facing into the room. Choose a hinge side and stick with it across
## your door scenes so they swing consistently.

## Stable identity, independent of position. Door placeholders are matched to
## their DoorEntry by this rather than by comparing float coordinates: a float
## match orphans the placeholder for good the moment a door is edited outside
## the sync path (inspector edits, a partially applied cascade fixup), leaving
## a node that can never be found, moved or removed again.
## Empty on doors authored before ids existed; ensure_id() fills those in.
@export var id: String = ""

@export var side: String = "north"
@export var center_u: float = 0.0
@export var center_v: float = 0.0
@export var width: float = 1.2
@export var height: float = 2.1
@export var label: String = ""
@export_file("*.tscn") var scene_path: String = ""

static var _id_counter: int = 0

## Returns this door's id, assigning one first if it does not have it yet.
## duplicate() copies the id, which is what undo snapshots need: a restored
## door_list still points at the same placeholders.
func ensure_id() -> String:
	if id.is_empty():
		_id_counter += 1
		id = "door_%d_%d" % [Time.get_ticks_usec(), _id_counter]
	return id
