@tool
class_name A11yElementTree
extends RefCounted

## Flattens the live [Control] tree into the ordered list a screen reader
## swipes through.
##
## Order is depth-first in child order, which for every standard container is
## also visual reading order. Scope is the topmost open [Window] or [Popup] if
## there is one, otherwise the current scene - so a modal dialog traps the
## cursor the way it does under VoiceOver, and you cannot swipe onto the
## buttons behind it.
##
## Per-node opt-in metadata (all optional; the defaults work with no changes):
##
## [codeblock]
## node.set_meta("a11y_label", "Play")      # override the spoken name
## node.set_meta("a11y_hint", "Starts a new run")  # extra detail, verbose mode
## node.set_meta("a11y_role", "banner")     # override the spoken role
## node.set_meta("a11y_hidden", true)       # skip this node and its children
## node.set_meta("a11y_group", "Audio")     # name a section; children stay reachable
## node.set_meta("a11y_collapse", true)     # speak a subtree as one element
## node.set_meta("a11y_order", 3)           # sort key among its siblings
## [/codeblock]
##
## [b]Groups and collapsing are separate on purpose.[/b] A group is a signpost:
## it is announced when the cursor crosses into it and it is the unit the
## three-finger swipe jumps between, but every control inside stays
## individually focusable - the cursor never stops on the group itself, because
## there is nothing to do to it. Collapsing removes the children from the tree
## entirely, so it is only correct when the subtree is one thing to the user -
## a star rating, a "3 of 5 lives" readout - and never for a row of buttons.


## Every element currently reachable, in swipe order.
static func collect(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	if root == null or not is_instance_valid(root):
		return out
	_walk(root, out)
	return out


## The window the cursor should be scoped to: the topmost visible embedded or
## native [Window] child of [param tree]'s root, else the current scene.
static func scope_of(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var root := tree.root
	var scope: Node = tree.current_scene
	if scope == null:
		scope = root
	# Later children draw on top, so the last visible Window wins.
	for i in range(root.get_child_count() - 1, -1, -1):
		var child := root.get_child(i)
		if child is Window and child.visible:
			scope = child
			break
	# Embedded popups (OptionButton dropdowns, AcceptDialog with embedding on)
	# live under the viewport instead, so look inside whatever we landed on -
	# a menu opened from a dialog is a window inside a window.
	var embedded := _topmost_embedded_window(scope)
	if embedded != null:
		return embedded
	return scope


## Topmost element whose rect contains [param global_pos] - explore by touch.
static func element_at(elements: Array[Control], global_pos: Vector2) -> Control:
	for i in range(elements.size() - 1, -1, -1):
		var c := elements[i]
		if is_instance_valid(c) and c.get_global_rect().has_point(global_pos):
			return c
	return null


## Is [param node] a named section? Any non-empty `a11y_group` says yes, which
## lets `false` and `""` turn an inherited marker back off.
static func is_group(node: Node) -> bool:
	if node == null or not node.has_meta("a11y_group"):
		return false
	var value: Variant = node.get_meta("a11y_group")
	if value is String or value is StringName:
		return not String(value).strip_edges().is_empty()
	return bool(value)


## Should [param node] and its subtree be spoken as a single element?
static func is_collapsed(node: Node) -> bool:
	return node != null and bool(node.get_meta("a11y_collapse", false))


## The nearest ancestor section, used to announce section changes and by the
## three-finger jump. Collapsed widgets are not sections in themselves - mark
## one with `a11y_group` as well if it should also be a jump target.
static func group_of(c: Node) -> Node:
	var n: Node = c
	while n != null:
		if is_group(n):
			return n
		n = n.get_parent()
	return null


## A named section is a signpost, not a destination: there is nothing to do to
## it, so stopping on it would spend a swipe saying "Audio, group" and nothing
## else. Its name is spoken as a heading on the first element inside instead.
## An operable widget that also carries `a11y_group` is exempt - skipping it
## would cost the user a control they can actually press.
static func _is_signpost_only(c: Control) -> bool:
	return is_group(c) and not is_collapsed(c) and not is_leaf(c)


static func _walk(node: Node, out: Array[Control]) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_meta("a11y_hidden") and bool(node.get_meta("a11y_hidden")):
		return
	if node is Control:
		var c := node as Control
		if not c.is_visible_in_tree():
			return
		if is_collapsed(c):
			# The whole subtree speaks as one element, so stop descending.
			out.append(c)
			return
		# Scroll bars and split handles are focusable, so they would otherwise
		# read as sliders sitting in the middle of a menu.
		if c is ScrollBar or c.get_class() == "SplitContainerDragger":
			return
		if is_element(c) and not _is_signpost_only(c):
			out.append(c)
			if is_leaf(c):
				# A SpinBox owns a LineEdit, an OptionButton owns a PopupMenu.
				# Those parts are already covered by how we describe the widget,
				# so descending would announce the same control twice.
				return
	elif node is Window:
		if not (node as Window).visible:
			return
		if node is PopupMenu:
			# Nothing here to descend into - see menu_of().
			var stand_in := _menu_stand_in(node as PopupMenu)
			if stand_in != null:
				out.append(stand_in)
			return

	for child in _ordered_children(node):
		_walk(child, out)


## The [PopupMenu] a control stands in for, or null if it is only itself.
##
## A menu's entries are not nodes - they are rows of data the menu draws by
## itself - so the walk has nothing to descend into and an open menu would read
## as one nameless element with nothing inside. The popup's own panel is put in
## the list instead and described as the whole menu, which is the shape an
## [ItemList] already gets here: one adjustable element, swipe up and down to
## move through the entries, double tap to pick one. Godot exposes no rect for
## an individual entry, so one element per entry could not be explored by touch
## even if we built it.
static func menu_of(c: Control) -> PopupMenu:
	if c == null or not is_instance_valid(c):
		return null
	return c.get_parent() as PopupMenu


## The entries a reader can stop on. Separators are signposts drawn between
## items rather than items, and a disabled entry cannot be chosen, so the arrow
## keys step over both and so do we.
static func menu_items(menu: PopupMenu) -> PackedInt32Array:
	var out := PackedInt32Array()
	if menu == null or not is_instance_valid(menu):
		return out
	for i in menu.get_item_count():
		if not menu.is_item_separator(i) and not menu.is_item_disabled(i):
			out.append(i)
	return out


## The entry the cursor is on, or -1. A menu opened by touch starts with
## nothing focused; an [OptionButton]'s dropdown is the one case where there is
## still an obvious answer, which is the value it is currently showing.
static func menu_current_item(menu: PopupMenu) -> int:
	if menu == null or not is_instance_valid(menu):
		return -1
	var focused := menu.get_focused_item()
	if focused >= 0:
		return focused
	var opener := menu.get_parent()
	if opener is OptionButton:
		return (opener as OptionButton).selected
	return -1


## The menu an entry opens, if it opens one. Submenus can be attached as a node
## or by name, and only the node form has a direct getter.
static func menu_submenu_of(menu: PopupMenu, index: int) -> PopupMenu:
	if menu == null or not is_instance_valid(menu):
		return null
	if index < 0 or index >= menu.get_item_count():
		return null
	var node := menu.get_item_submenu_node(index)
	if node != null:
		return node
	var by_name := menu.get_item_submenu(index)
	if by_name.is_empty():
		return null
	return menu.get_node_or_null(NodePath(by_name)) as PopupMenu


## The child that stands in for a whole [PopupMenu]: its panel, which covers
## the popup, so exploring by touch anywhere inside the menu finds it.
static func _menu_stand_in(menu: PopupMenu) -> Control:
	for child in menu.get_children(true):
		if child.has_meta("a11y_hidden") and bool(child.get_meta("a11y_hidden")):
			continue
		if child is Control and (child as Control).is_visible_in_tree():
			return child as Control
	return null


## Is this control worth stopping on? Anything focusable, anything that says
## something, and anything the developer explicitly labelled.
static func is_element(c: Control) -> bool:
	if c.has_meta("a11y_label"):
		return true
	if c.focus_mode != Control.FOCUS_NONE:
		return true
	if not c.accessibility_name.is_empty():
		return true
	if c is Label or c is RichTextLabel:
		return not String(c.text).strip_edges().is_empty()
	return false


## Can this control take real keyboard focus? Godot 4.7 also has an
## accessibility-only focus mode, which exists so screen readers can see a node
## - calling grab_focus() on one of those warns and does nothing.
static func can_focus(c: Control) -> bool:
	return c.focus_mode == Control.FOCUS_ALL or c.focus_mode == Control.FOCUS_CLICK


## Widgets that own their internals. We describe the whole thing as one
## element, so the walk stops here.
static func is_leaf(c: Control) -> bool:
	return (c is BaseButton or c is Range or c is LineEdit or c is TextEdit
		or c is ItemList or c is Tree or c is TabBar
		or c is Label or c is RichTextLabel)


static func _ordered_children(node: Node) -> Array:
	# Internal children included: a dialog's OK/Cancel buttons and a
	# TabContainer's TabBar are internal, and skipping them would leave a
	# dialog with nothing to press.
	var children := node.get_children(true)
	var has_order := false
	for child in children:
		if child.has_meta("a11y_order"):
			has_order = true
			break
	if not has_order:
		return children
	# Stable-ish: unordered nodes keep their index as their key, so an explicit
	# a11y_order only pulls a node past siblings it actually outranks.
	var keyed: Array = []
	for i in children.size():
		var child: Node = children[i]
		var key: float = float(child.get_meta("a11y_order", i))
		keyed.append([key, i, child])
	keyed.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array = []
	for entry in keyed:
		out.append(entry[2])
	return out


static func _topmost_embedded_window(scope: Node) -> Window:
	if scope == null:
		return null
	var found: Window = null
	for child in scope.get_children(true):
		if child is Window and (child as Window).visible:
			found = child
		var deeper := _topmost_embedded_window(child)
		if deeper != null:
			found = deeper
	return found
