@tool
class_name EditOps
extends RefCounted

## Undo/redo facade for every scene mutation the addon performs.
##
## Every button in the dock must route its scene changes through here so that
## Ctrl+Z works exactly as it does for Godot's own editing tools. Direct writes
## to the scene tree are a bug: they leave the user with no way back.
##
## Typical single-step use:
##     dock.ops.add_node(parent, room, "Create room %s" % room.name, pos)
##
## Multi-step use, committed as ONE undo entry:
##     dock.ops.begin("Move %s and 6 connected rooms" % room.name)
##     dock.ops.prop(room, "global_position", new_pos)
##     for m in cascade: dock.ops.prop(m.room, "global_position", m.new_pos)
##     dock.ops.commit()

var plugin: EditorPlugin

var _ur: EditorUndoRedoManager
var _open: bool = false

func _init(p: EditorPlugin) -> void:
	plugin = p

## The manager, fetched lazily: the plugin isn't fully wired at dock _ready time.
func _mgr() -> EditorUndoRedoManager:
	if _ur == null and plugin != null:
		_ur = plugin.get_undo_redo()
	return _ur

func _root() -> Node:
	if plugin == null: return null
	return plugin.get_editor_interface().get_edited_scene_root()

# ---------------------------------------------------------------------------
# Explicit transactions
# ---------------------------------------------------------------------------

## Opens a transaction. Every prop/method/add/remove call until commit() lands
## in one undo entry. Passing the edited scene root as the action context files
## the entry in that scene's own history rather than the global one.
func begin(action_name: String) -> bool:
	var ur := _mgr()
	if ur == null: return false
	if _open:
		push_warning("EditOps.begin() called while '%s' was still open; committing it first." % action_name)
		commit()
	ur.create_action(action_name, UndoRedo.MERGE_DISABLE, _root())
	_open = true
	return true

func commit() -> void:
	if not _open: return
	_open = false
	var ur := _mgr()
	if ur != null: ur.commit_action()

## Bails out of an open transaction for an error path. UndoRedo has no cancel
## API, so this commits without executing: the recorded operations never run,
## but a do-nothing entry is left on the undo stack. Prefer validating
## everything BEFORE begin() so this is never needed.
func abort() -> void:
	if not _open: return
	_open = false
	var ur := _mgr()
	if ur != null: ur.commit_action(false)

func is_open() -> bool:
	return _open

# ---------------------------------------------------------------------------
# Operations (valid only inside begin/commit)
# ---------------------------------------------------------------------------

## Records a property change, capturing the current value for the undo side.
func prop(obj: Object, property: StringName, value: Variant) -> void:
	if not _open or obj == null: return
	var ur := _mgr()
	ur.add_do_property(obj, property, value)
	ur.add_undo_property(obj, property, obj.get(property))

## Records several property changes on one object.
func props(obj: Object, values: Dictionary) -> void:
	for k in values: prop(obj, k, values[k])

## Records a method call plus the call that reverses it.
func method(obj: Object, do_method: StringName, do_args: Array,
		undo_obj: Object, undo_method: StringName, undo_args: Array) -> void:
	if not _open: return
	var ur := _mgr()
	ur.callv("add_do_method", [obj, do_method] + do_args)
	ur.callv("add_undo_method", [undo_obj, undo_method] + undo_args)

## Records a call that runs on both do and undo, e.g. a rebuild that must happen
## in either direction after the surrounding property swaps.
func refresh(obj: Object, method_name: StringName, args: Array = []) -> void:
	if not _open: return
	var ur := _mgr()
	ur.callv("add_do_method", [obj, method_name] + args)
	ur.callv("add_undo_method", [obj, method_name] + args)

## Adds a freshly constructed node to the tree. Configure the node fully BEFORE
## calling this (size, wall configs, door list) so only one rebuild runs.
##
## placement is applied after the node enters the tree, where global space is
## meaningful. Pass a Vector3 for a position, a Transform3D for a full
## orientation (door placeholders need this), or null to leave it alone.
## Owners are set across the whole subtree so multi-node helpers -- a
## placeholder and its MeshInstance3D -- all survive a scene save.
func add_child_node(parent: Node, node: Node, placement: Variant = null) -> void:
	if not _open or parent == null or node == null: return
	var ur := _mgr()
	var root := _root()
	ur.add_do_method(parent, "add_child", node)
	ur.add_do_method(self, "_own_subtree", node, root)
	if node is Node3D:
		if placement is Transform3D:
			ur.add_do_property(node, "global_transform", placement)
		elif placement is Vector3:
			ur.add_do_property(node, "global_position", placement)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)

## Sets owner on node and every descendant. Called as an undo/redo operation,
## so it must be an instance method rather than a static one.
func _own_subtree(node: Node, root: Node) -> void:
	if root == null or node == null: return
	node.owner = root
	for child in node.get_children():
		_own_subtree(child, root)

## Records a metadata change, capturing the current value for the undo side.
## Door placeholders carry their identity in metas, so these must be undoable
## alongside the door_list swap or the two drift apart.
func meta(obj: Object, key: String, value: Variant) -> void:
	if not _open or obj == null: return
	var ur := _mgr()
	var had: bool = obj.has_meta(key)
	var old_value: Variant = obj.get_meta(key) if had else null
	ur.add_do_method(obj, "set_meta", key, value)
	if had:
		ur.add_undo_method(obj, "set_meta", key, old_value)
	else:
		ur.add_undo_method(obj, "remove_meta", key)

## Removes a node, keeping it alive on the undo side so it can come back with
## its properties and children intact.
func remove_child_node(node: Node) -> void:
	if not _open or node == null: return
	var parent := node.get_parent()
	if parent == null: return
	var ur := _mgr()
	var index := node.get_index()
	var node_owner := node.owner
	ur.add_do_method(parent, "remove_child", node)
	ur.add_undo_method(parent, "add_child", node)
	ur.add_undo_method(parent, "move_child", node, index)
	ur.add_undo_method(node, "set_owner", node_owner)
	ur.add_undo_reference(node)

## Moves a node from one parent to another. Owners are NOT set on the do side:
## the caller is expected to add the destination via add_child_node(), whose
## _own_subtree pass covers everything underneath it. The undo side does set
## them, because by then the original parent is back in the tree.
##
## Local transforms are left alone. Callers that reparent between nodes with
## different transforms must fix the transform themselves; bake relies on the
## wrapper sharing the entity's transform exactly.
func reparent(child: Node, from_parent: Node, to_parent: Node) -> void:
	if not _open or child == null or from_parent == null or to_parent == null: return
	var ur := _mgr()
	var root := _root()
	var index := child.get_index()
	ur.add_do_method(from_parent, "remove_child", child)
	ur.add_do_method(to_parent, "add_child", child)
	ur.add_undo_method(to_parent, "remove_child", child)
	ur.add_undo_method(from_parent, "add_child", child)
	ur.add_undo_method(from_parent, "move_child", child, index)
	ur.add_undo_method(self, "_own_subtree", child, root)

# ---------------------------------------------------------------------------
# One-shot convenience wrappers (open and commit their own transaction)
# ---------------------------------------------------------------------------

func add_node(parent: Node, node: Node, action_name: String, global_pos: Variant = null) -> void:
	if not begin(action_name): return
	add_child_node(parent, node, global_pos)
	commit()

func remove_node(node: Node, action_name: String) -> void:
	if not begin(action_name): return
	remove_child_node(node)
	commit()

func set_prop(obj: Object, property: StringName, value: Variant, action_name: String) -> void:
	if not begin(action_name): return
	prop(obj, property, value)
	commit()

# ---------------------------------------------------------------------------
# Room-specific helpers
# ---------------------------------------------------------------------------

## Deep-copies a room's door list so it can be restored wholesale. Swapping the
## entire array is deliberate: it is immune to the index shifts that make
## per-door undo fragile when doors are added or removed.
static func copy_doors(room: Room3D) -> Array[DoorEntry]:
	var out: Array[DoorEntry] = []
	for d in room.door_list:
		out.append(d.duplicate() as DoorEntry)
	return out

## Records a door-list replacement on room, rebuilding in both directions.
## Capture `before` with copy_doors() BEFORE mutating room.door_list.
func swap_doors(room: Room3D, before: Array[DoorEntry], after: Array[DoorEntry]) -> void:
	if not _open or room == null: return
	var ur := _mgr()
	ur.add_do_method(room, "apply_door_list", after)
	ur.add_undo_method(room, "apply_door_list", before)
