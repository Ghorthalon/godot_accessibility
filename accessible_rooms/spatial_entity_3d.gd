@tool
## Base class for all spatial entities
##
## Extend this class for any new spatial type. Room3D,
## Ramp3D, or future types (stairs, portals, whatever.).  Once a type extends
## SpatialEntity3D and implements the five virtual methods below, it
## automatically participates in
##   - scene_query entity collection and labelling
##   - cursor "you are inside X" reports
##   - the entity list and resize UI in the Rooms tab
##   - the bake step
##
## checklist for a new type:
##   1. extends SpatialEntity3D and implement the five virtual methods
##   2. plugin.gd  add_custom_type() 
##   3. tab_<mytype>.gd if a new tab is required for organization
##   4. dock.gd  one preload/add_child line to add the creation tab
class_name SpatialEntity3D
extends Node3D

const EPSILON := 0.001       # geometric tolerance: overlap/adjacency checks, z-fighting offset
const WALL_THICKNESS := 0.1  # generated collision-body depth for walls, floors, ceilings, ramps

# ---------------------------------------------------------------------------
# Virtual interface, override in subclasses
# ---------------------------------------------------------------------------

## Returns a human readable description for screen reader announcements
## and the entity list.  Should include type, name, and key dimensions.
func entity_label() -> String:
	return name

## Returns true if worldspace point p is "inside" this entity's volume.
## Used by the cursor "you are in X" report and entity_containing().
func contains_point(_p: Vector3) -> bool:
	return false

## Returns the approximate bounding volume in cubic metres.
## Used to pick the smallest container when the cursor is inside multiple entities.
## Subclasses should override with their actual volume formula.
func bounding_volume() -> float:
	return INF

## Regenerate all procedural geometry.  Called after any property changes.
func rebuild() -> void:
	pass

## Returns all StaticBody3D children that should be included in the bake step.
## The default implementation collects every child that has the "generated"
## meta tag set.
func generated_bodies() -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for c in get_children():
		if c.has_meta("generated") and c is StaticBody3D:
			out.append(c as StaticBody3D)
	return out

## Populate container with resize/edit controls for this entity.
## Called each time the entity is selected in the entity list.
## The container is cleared before this is called.
func populate_properties_ui(_container: VBoxContainer) -> void:
	pass

## Read values back from the controls added by populate_properties_ui()
## and apply them to this entity's properties.
func apply_properties_ui(_container: VBoxContainer) -> void:
	pass

## Returns the worldspace offset from this entity's position to where the centre
## of a new neighbouring room should be placed when attached on side.
## Returns Vector3.ZERO for sides that cannot have a neighbour for example perpendicular
## ramp sides. Subclasses override this, Room3D provides a flat flush offset,
## Ramp3D returns an offset that includes the correct elevation change, etc.
func neighbor_offset(_side: String, _other_size: Vector3) -> Vector3:
	return Vector3.ZERO

## Returns the wall side of the NEW neighbour room that faces this entity when
## attached on side. Used by tab_rooms to punch the connecting doorway.
func neighbor_doorway_side(_side: String) -> String:
	return ""

## Returns true if this entity has a physical wall on side that needs a
## doorway punched when a neighbour is attached there.
func has_wall(_side: String) -> bool:
	return false

# Returns descriptors for each connectable face. Each dict has
##   label: String ~ "north wall", "low end", "high end"
##   normal: Vector3, outward unit normal of the face
##   probe_world: Vector3, world point 0.05m outside the face center
##   face_center_world: Vector3
##   face_width: float, face extent perpendicular to the outward normal
##   face_height: float, face extent in the vertical direction
## Faces are assumed to be axis-aligned (normal points along ±X or ±Z, height along Y).
## Used by scene_query.find_connections. A connectable face is one a doorway could
## be punched through, subclasses may filter out walls that aren't physically present
## ( for example Room3D skips sides where wall_cfg.enabled is false).
func connection_probe_points() -> Array[Dictionary]:
	return []

## Returns the entity's geometric boundary faces, regardless of whether they have
## physical walls. Used by scene_query.detect_gaps to find misalignments between
## adjacent entities, including outdoor rooms where every wall is disabled.
## Same dict schema as connection_probe_points(). Defaults to that method so
## subclasses with no enabled/disabled distinction don't need override.
func boundary_faces() -> Array[Dictionary]:
	return connection_probe_points()

# ---------------------------------------------------------------------------
# Shared UI helper (available to all subclasses)
# ---------------------------------------------------------------------------

## Add a labelled SpinBox row to c and return the SpinBox.
static func _add_spinbox(c: VBoxContainer, lbl: String,
		mn: float, mx: float, step_v: float, val: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = lbl
	var spin := SpinBox.new()
	spin.min_value = mn
	spin.max_value = mx
	spin.step = step_v
	spin.value = val
	row.add_child(label)
	row.add_child(spin)
	c.add_child(row)
	return spin

# ---------------------------------------------------------------------------
# Rebuild queue
# ---------------------------------------------------------------------------

var _rebuild_queued := false
var _rebuild_gen    := 0

## Builds geometry synchronously as soon as the whole tree is available.
##
## Outside the editor this is mandatory, not an optimisation: _enter_tree only
## QUEUES a deferred rebuild, which does not run until the end of the first
## frame, so the first physics tick would find no floor and a character standing
## on it would drop straight through. _ready is the earliest safe point -- every
## node is in the tree by now, so wall suppression between neighbouring rooms
## still resolves against a complete scene.
##
## In the editor the deferred path is kept, so a burst of property edits still
## coalesces into one rebuild.
func _ready() -> void:
	if not Engine.is_editor_hint():
		rebuild()

func _queue_rebuild() -> void:
	if is_inside_tree() and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild_gen   += 1
		call_deferred("_deferred_rebuild")

## Deferred entry point. Skips the work when something already rebuilt
## synchronously in the meantime (rebuild() clears _rebuild_queued), so the
## _ready build above does not get duplicated a frame later.
func _deferred_rebuild() -> void:
	if not _rebuild_queued: return
	rebuild()

## Returns true when the queued rebuild has been superseded by a newer one.
## Call after await get_tree().process_frame inside each subclass rebuild
##   var my_gen := _rebuild_gen
##   await get_tree().process_frame
##   if _check_rebuild_stale(my_gen): return
func _check_rebuild_stale(gen: int) -> bool:
	return _rebuild_gen != gen

# ---------------------------------------------------------------------------
# Shared geometry helper
# ---------------------------------------------------------------------------

## Creates StaticBody3D -> MeshInstance3D(BoxMesh) -> CollisionShape3D(BoxShape3D)
## tagged "generated" + "surface", oriented by xform, added to parent.
##
## Deliberately does NOT set owner: generated geometry is derived data, rebuilt
## from the entity's properties whenever it enters the tree, in the editor and
## at runtime alike. Leaving it unowned keeps it out of the .tscn entirely, so
## a scene file stays a short list of rooms instead of thousands of boxes, and
## nudging one room no longer rewrites the whole file.
static func _spawn_box(parent: Node3D, body_name: String,
		xform: Transform3D, sz: Vector3, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("generated", true)
	body.set_meta("surface", surface)
	body.name = body_name
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = sz; mi.mesh = bm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = sz; cs.shape = bs
	body.add_child(mi); body.add_child(cs)
	parent.add_child(body)
	body.transform = xform
	return body
