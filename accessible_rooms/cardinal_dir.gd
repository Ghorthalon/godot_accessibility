@tool
class_name CardinalDir

const ALL: Array[String] = ["north", "south", "east", "west"]

const OPPOSITE: Dictionary = {
	"north": "south", "south": "north",
	"east":  "west",  "west":  "east",
}

## Outward facing Vector3 per cardinal direction
const VECTOR: Dictionary = {
	"north": Vector3(0, 0, -1), "south": Vector3(0, 0,  1),
	"east":  Vector3(1, 0,  0), "west":  Vector3(-1, 0, 0),
}

static func opposite(side: String) -> String: return OPPOSITE.get(side, "")
static func vector(side: String)   -> Vector3: return VECTOR.get(side, Vector3.ZERO)
