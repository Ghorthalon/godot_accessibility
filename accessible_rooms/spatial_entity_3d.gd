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
