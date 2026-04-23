@tool
class_name WallConfig
extends Resource

## Whether this surface is generated.
@export var enabled: bool = true
## Acoustic/visual surface material identifier.
@export var surface: String = "concrete"
## Rectangular openings cut into this surface.
## Coords are wall local 2D (metres), origin = wall centre.
@export var openings: Array[Rect2] = []
## Subregion overlays with a different surface material.
## Each entry: {rect: Rect2, surface: String}
@export var zones: Array[Dictionary] = []
