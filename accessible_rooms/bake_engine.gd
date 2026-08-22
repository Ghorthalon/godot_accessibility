@tool
class_name BakeEngine

## Bakes SpatialEntity3D procedural geometry into optimised static meshes.
## Both public methods delegate mesh merging to _build_merged_into().

## Collects every SpatialEntity3D under root, recursing into containers so
## nested entities (e.g. stairs inside a room, rooms grouped under a Node3D)
## are included. Skips generated subtrees.
static func collect_entities(root: Node) -> Array[SpatialEntity3D]:
	var out: Array[SpatialEntity3D] = []
	_collect_entities(root, out)
	return out

static func _collect_entities(node: Node, out: Array[SpatialEntity3D]) -> void:
	if node.has_meta("generated"): return
	if node is SpatialEntity3D:
		out.append(node as SpatialEntity3D)
	for child in node.get_children():
		_collect_entities(child, out)

## Bake all entities in place on the live scene tree, as ONE undoable action.
##
## Baking destroys the authoring representation -- sizes, door lists, wall
## configs -- so it must be reversible. Authoring nodes are detached rather than
## freed and held alive by the undo stack, and restoring one re-triggers its
## _queue_rebuild, so an undo brings back fully working rooms.
##
## Each entity's wrapper is added to the entity's own parent (entities may be
## nested); owners are set to root so baked nodes survive saving.
## Returns the entity count.
static func bake_in_place(entities: Array[SpatialEntity3D], root: Node, ops: EditOps) -> int:
	var n := entities.size()
	if not ops.begin("Bake %d spatial entit%s into meshes" % [n, "ies" if n != 1 else "y"]):
		return 0
	for entity in entities:
		var parent := entity.get_parent()
		if parent == null: continue
		var original_name := entity.name
		var wrapper := Node3D.new()
		wrapper.name = original_name
		wrapper.transform = (entity as Node3D).transform
		# Meshes are built now, from the live generated bodies, and travel with
		# the wrapper as a finished subtree.
		_build_merged_into(entity, wrapper)
		# Free the name before the wrapper claims it, or the two collide and
		# Godot silently renames the wrapper.
		ops.prop(entity, "name", original_name + "__baked_source")
		for child in entity.get_children():
			if _is_generated(child): continue
			ops.reparent(child, entity, wrapper)
		ops.add_child_node(parent, wrapper)
		ops.remove_child_node(entity)
	ops.commit()
	return n

## True for nodes the entity generates and owns, which bake replaces wholesale.
## Everything else is the user's and must be carried over to the wrapper.
static func _is_generated(node: Node) -> bool:
	if node.has_meta("generated"): return true
	if node.has_meta("room_area"): return true
	if node.has_meta("ramp_area"): return true
	return node.has_meta("stairs_area")

## Duplicate root, bake the copy, and return it as a PackedScene.
## The original root is not modified. Returns null on pack failure.
static func bake_to_packed_scene(entities_root: Node) -> PackedScene:
	var dup := entities_root.duplicate()
	_set_owners_recursive(dup, dup)
	var entities: Array[SpatialEntity3D] = collect_entities(dup)
	for entity in entities:
		var parent := entity.get_parent()
		var original_name := entity.name
		entity.name = entity.name + "__bake_temp"
		var wrapper := Node3D.new()
		wrapper.name = original_name
		wrapper.transform = (entity as Node3D).transform
		parent.add_child(wrapper); wrapper.owner = dup
		for child in entity.get_children():
			if _is_generated(child): continue
			entity.remove_child(child); wrapper.add_child(child)
			_set_owners_recursive(child, dup)
			child.owner = dup
		_build_merged_into(entity, wrapper)
		_set_owners_recursive(wrapper, dup)
		parent.remove_child(entity); entity.free()
	var packed := PackedScene.new()
	var err := packed.pack(dup); dup.free()
	return packed if err == OK else null

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Builds merged meshes and one trimesh collider for entity's generated bodies
## and adds them to wrapper. Does NOT move the user's own children or set
## owners: bake_in_place records those as undoable operations instead.
static func _build_merged_into(entity: SpatialEntity3D, wrapper: Node3D) -> void:
	var bodies: Array[StaticBody3D] = entity.generated_bodies()
	var by_surface: Dictionary = {}
	for body in bodies:
		var surf: String = body.get_meta("surface", "concrete")
		if not by_surface.has(surf): by_surface[surf] = []
		by_surface[surf].append(body)

	# Merge visual meshes, one ArrayMesh per surface type.
	for surf in by_surface:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for body in by_surface[surf]:
			var mi: MeshInstance3D
			for ch in body.get_children():
				if ch is MeshInstance3D: mi = ch; break
			if mi: st.append_from(mi.mesh, 0, body.transform)
		var merged := MeshInstance3D.new()
		merged.name = wrapper.name + "_" + surf + "_mesh"
		merged.mesh = st.commit()
		wrapper.add_child(merged)

	# Single StaticBody3D with trimesh collision covering all surfaces.
	var all_tris := PackedVector3Array()
	for surf in by_surface:
		for body in by_surface[surf]:
			var mi: MeshInstance3D
			for ch in body.get_children():
				if ch is MeshInstance3D: mi = ch; break
			if mi == null: continue
			var arrays := mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for idx in range(0, verts.size(), 3):
					all_tris.append(body.transform * verts[idx])
					all_tris.append(body.transform * verts[idx + 1])
					all_tris.append(body.transform * verts[idx + 2])
			else:
				for idx in range(0, indices.size(), 3):
					all_tris.append(body.transform * verts[indices[idx]])
					all_tris.append(body.transform * verts[indices[idx + 1]])
					all_tris.append(body.transform * verts[indices[idx + 2]])

	if all_tris.size() > 0:
		var phys_body := StaticBody3D.new(); phys_body.name = "Collision"
		var cshape := CollisionShape3D.new()
		var trimesh := ConcavePolygonShape3D.new(); trimesh.set_faces(all_tris)
		cshape.shape = trimesh
		phys_body.add_child(cshape); wrapper.add_child(phys_body)

static func _set_owners_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner; _set_owners_recursive(child, owner)
