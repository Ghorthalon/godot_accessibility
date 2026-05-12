@tool
class_name BakeEngine

## Bakes SpatialEntity3D procedural geometry into optimised static meshes.
## Both public methods delegate per entity work to _bake_entity_into().

## Bake all entities in place on the live scene tree. Returns the entity count.
static func bake_in_place(entities: Array[SpatialEntity3D], root: Node) -> int:
	for entity in entities:
		var original_name := entity.name
		entity.name = entity.name + "__bake_temp"
		var wrapper := Node3D.new()
		wrapper.name = original_name
		wrapper.transform = (entity as Node3D).transform
		root.add_child(wrapper); wrapper.owner = root
		_bake_entity_into(entity, wrapper, root)
		root.remove_child(entity); entity.queue_free()
	return entities.size()

## Duplicate root, bake the copy, and return it as a PackedScene.
## The original root is not modified. Returns null on pack failure.
static func bake_to_packed_scene(entities_root: Node) -> PackedScene:
	var dup := entities_root.duplicate()
	_set_owners_recursive(dup, dup)
	var entities: Array[SpatialEntity3D] = []
	for c in dup.get_children():
		if c is SpatialEntity3D: entities.append(c as SpatialEntity3D)
	for entity in entities:
		var original_name := entity.name
		entity.name = entity.name + "__bake_temp"
		var wrapper := Node3D.new()
		wrapper.name = original_name
		wrapper.transform = (entity as Node3D).transform
		dup.add_child(wrapper); wrapper.owner = dup
		_bake_entity_into(entity, wrapper, dup)
		dup.remove_child(entity); entity.free()
	var packed := PackedScene.new()
	var err := packed.pack(dup); dup.free()
	return packed if err == OK else null

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _bake_entity_into(entity: SpatialEntity3D, wrapper: Node3D, owner: Node) -> void:
	var bodies: Array[StaticBody3D] = entity.generated_bodies()
	var by_surface: Dictionary = {}
	for body in bodies:
		var surf: String = body.get_meta("surface", "concrete")
		if not by_surface.has(surf): by_surface[surf] = []
		by_surface[surf].append(body)

	# Move nongenerated children to wrapper.
	for child in entity.get_children():
		if not child.has_meta("generated"):
			entity.remove_child(child); wrapper.add_child(child)
			_set_owners_recursive(child, owner)

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
		wrapper.add_child(merged); merged.owner = owner

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
		phys_body.owner = owner; cshape.owner = owner

static func _set_owners_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner; _set_owners_recursive(child, owner)
