@tool
class_name ConnectionInfo
extends RefCounted

enum Status { OPEN, BLOCKED }

var from_label: String = ""       # "north wall", "low end", "high end"
var to_entity: SpatialEntity3D    # entity on the other side
var to_wall_side: String = ""     # which wall of to_entity faces us, "" = interior or not a room
var status: Status = Status.BLOCKED
