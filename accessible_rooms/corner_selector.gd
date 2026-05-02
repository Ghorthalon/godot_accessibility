@tool
class_name CornerSelector
extends VBoxContainer

enum Mode { XYZ, XZ }

var dock
var mode: Mode = Mode.XYZ
var corner_a: Vector3 = Vector3.ZERO
var corner_b: Vector3 = Vector3.ZERO

var _label_a: Label
var _label_b: Label

func _ready() -> void:
	var btn_row := HBoxContainer.new()
	var btn_a := Button.new()
	btn_a.text = "Set corner A (cursor)"
	btn_a.pressed.connect(_set_corner_a)
	var btn_b := Button.new()
	btn_b.text = "Set corner B (cursor)"
	btn_b.pressed.connect(_set_corner_b)
	btn_row.add_child(btn_a)
	btn_row.add_child(btn_b)
	add_child(btn_row)
	var lbl_row := HBoxContainer.new()
	_label_a = Label.new(); _label_a.text = "A: "
	_label_b = Label.new(); _label_b.text = "B: "
	lbl_row.add_child(_label_a)
	lbl_row.add_child(_label_b)
	add_child(lbl_row)

func _set_corner_a() -> void:
	corner_a = dock.cursor
	_label_a.text = "A: " + _format(corner_a)
	dock._say("Corner A set at %s." % _format(corner_a))

func _set_corner_b() -> void:
	corner_b = dock.cursor
	_label_b.text = "B: " + _format(corner_b)
	dock._say("Corner B set at %s." % _format(corner_b))

func _format(pos: Vector3) -> String:
	if mode == Mode.XZ:
		return "%.1f, %.1f" % [pos.x, pos.z]
	return "x=%.1f y=%.1f z=%.1f" % [pos.x, pos.y, pos.z]

func get_aabb() -> AABB:
	var min_p := corner_a.min(corner_b)
	var max_p := corner_a.max(corner_b)
	return AABB(min_p, max_p - min_p)

func get_rect2_xz() -> Rect2:
	return Rect2(
		minf(corner_a.x, corner_b.x),
		minf(corner_a.z, corner_b.z),
		absf(corner_b.x - corner_a.x),
		absf(corner_b.z - corner_a.z))
