@tool
class_name A11yDescriber
extends RefCounted

## Turns a [Control] into the sentence a screen reader user hears.
##
## Word order follows VoiceOver: **label, role, state, position, hint**.
## "Start game, button." / "Music volume, slider, 70 percent, adjustable."
##
## Composite widgets (tab bars, item lists) are described as one adjustable
## element with their current selection, rather than exploding into one
## element per tab or row. Swiping up/down moves inside them - the same shape
## VoiceOver uses for pickers.

enum Verbosity { TERSE, NORMAL, VERBOSE }

## Nodes whose text is content rather than a control to operate.
const _STATIC_CLASSES: Array[String] = ["Label", "RichTextLabel"]


## Full announcement for [param c].
static func describe(c: Control, verbosity: int = Verbosity.NORMAL) -> String:
	if c == null or not is_instance_valid(c):
		return ""
	var parts: Array[String] = []
	var label := name_of(c)
	if not label.is_empty():
		parts.append(label)

	if verbosity > Verbosity.TERSE:
		var r := role_of(c)
		if not r.is_empty():
			parts.append(r)

	var state := state_of(c)
	if not state.is_empty():
		parts.append(state)

	if is_adjustable(c):
		parts.append("adjustable")

	if verbosity >= Verbosity.VERBOSE:
		var hint := String(c.get_meta("a11y_hint", ""))
		if hint.is_empty():
			hint = c.tooltip_text
		if not hint.is_empty() and hint != label:
			parts.append(hint)

	if c is BaseButton and c.disabled:
		parts.append("dimmed")

	return ", ".join(parts) + "."


## The spoken name, in the order a developer would expect to be able to
## override it: explicit meta, then Godot's own accessibility name, then
## whatever visible text the control carries, then the node name.
static func name_of(c: Control) -> String:
	var explicit := String(c.get_meta("a11y_label", ""))
	if not explicit.is_empty():
		return explicit
	var menu := A11yElementTree.menu_of(c)
	if menu != null:
		return menu_name_of(menu)
	if not c.accessibility_name.is_empty():
		return c.accessibility_name
	if c is OptionButton:
		# `text` here is the current selection, which belongs in the state, not
		# the name. Only a tooltip or meta can name one. A MenuButton is not the
		# same case - its text is its own label, so it falls through below.
		pass
	elif "text" in c and not String(c.text).is_empty():
		return String(c.text)
	if c is LineEdit and not c.placeholder_text.is_empty():
		return c.placeholder_text
	if c is TextEdit and not c.placeholder_text.is_empty():
		return c.placeholder_text
	if not c.accessibility_description.is_empty():
		return c.accessibility_description
	if not c.tooltip_text.is_empty():
		return c.tooltip_text
	return humanize(c.name)


## What the cursor says when it crosses into a section: the `a11y_group`
## string if there is one, else the node's usual name.
static func group_name_of(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	var value: Variant = node.get_meta("a11y_group", "")
	if (value is String or value is StringName) and not String(value).strip_edges().is_empty():
		return String(value).strip_edges()
	var explicit := String(node.get_meta("a11y_label", ""))
	if not explicit.is_empty():
		return explicit
	if node is Control:
		return name_of(node as Control)
	return humanize(node.name)


## The sentence spoken ahead of the first element of a newly entered section.
static func describe_group(node: Node, verbosity: int = Verbosity.NORMAL) -> String:
	var label := group_name_of(node)
	if label.is_empty():
		return ""
	if verbosity <= Verbosity.TERSE:
		return label + "."
	return label + ", group."


static func role_of(c: Control) -> String:
	var explicit := String(c.get_meta("a11y_role", ""))
	if not explicit.is_empty():
		return explicit
	if A11yElementTree.menu_of(c) != null:
		return "menu"
	if A11yElementTree.is_group(c) or A11yElementTree.is_collapsed(c):
		return "group"
	if c is CheckBox:
		return "checkbox"
	if c is CheckButton:
		return "toggle"
	if c is OptionButton:
		return "pop-up button"
	if c is MenuButton:
		return "menu"
	if c is LinkButton:
		return "link"
	if c is BaseButton:
		return "button"
	if c is LineEdit:
		return "secure text field" if c.secret else "text field"
	if c is TextEdit:
		return "text area"
	if c is SpinBox:
		return "stepper"
	if c is ProgressBar:
		return "progress"
	if c is Range:
		return "slider"
	if c is TabBar:
		return "tab bar"
	if c is ItemList or c is Tree:
		return "list"
	if c.get_class() in _STATIC_CLASSES:
		return "text"
	return ""


## Everything that can change without the node being replaced: checked state,
## current value, selected row. Spoken again on its own after an adjustment.
static func state_of(c: Control) -> String:
	var menu := A11yElementTree.menu_of(c)
	if menu != null:
		return menu_state_of(menu)
	if c is CheckBox:
		return "checked" if c.button_pressed else "unchecked"
	if c is CheckButton:
		return "on" if c.button_pressed else "off"
	if c is OptionButton:
		# Before the generic toggle check below: an OptionButton is a toggle
		# button under the hood, but "not pressed" is not what it means.
		if c.selected < 0:
			return "nothing selected"
		return "%s, %d of %d" % [c.get_item_text(c.selected), c.selected + 1, c.item_count]
	if c is MenuButton:
		return ""
	if c is BaseButton and c.toggle_mode:
		return "pressed" if c.button_pressed else "not pressed"
	if c is LineEdit:
		if c.secret:
			return "%d characters" % c.text.length() if not c.text.is_empty() else "empty"
		return c.text if not c.text.is_empty() else "empty"
	if c is TextEdit:
		return c.text if not c.text.is_empty() else "empty"
	if c is Range:
		return value_text(c)
	if c is TabBar:
		if c.tab_count == 0:
			return "no tabs"
		return "%s, %d of %d" % [c.get_tab_title(c.current_tab), c.current_tab + 1, c.tab_count]
	if c is ItemList:
		var sel: PackedInt32Array = c.get_selected_items()
		if sel.is_empty():
			return "%d items, nothing selected" % c.item_count
		return "%s, %d of %d" % [c.get_item_text(sel[0]), sel[0] + 1, c.item_count]
	if c is Tree:
		var item: TreeItem = c.get_selected()
		if item == null:
			return "nothing selected"
		return item.get_text(maxi(c.get_selected_column(), 0))
	return ""


## What a [PopupMenu] is called. Menus almost never carry a title of their own,
## so the thing that opened it is the answer: the label on a
## [MenuButton], the name of the [OptionButton] it drops out of, the entry a
## submenu hangs off, etc.
static func menu_name_of(menu: PopupMenu) -> String:
	if menu == null or not is_instance_valid(menu):
		return ""
	var explicit := String(menu.get_meta("a11y_label", ""))
	if not explicit.is_empty():
		return explicit
	if not menu.title.is_empty():
		return menu.title
	var opener := menu.get_parent()
	if opener is MenuButton and not String((opener as MenuButton).text).is_empty():
		# `text` is the button's own label here rather than a selection, so
		# unlike the rule in name_of() it is exactly what to call the menu.
		return String((opener as MenuButton).text)
	if opener is PopupMenu:
		var parent_menu := opener as PopupMenu
		for i in parent_menu.get_item_count():
			if A11yElementTree.menu_submenu_of(parent_menu, i) == menu:
				return parent_menu.get_item_text(i)
	if opener is Control:
		return name_of(opener as Control)
	return "Menu"


## Where the cursor is inside an open menu, or how much is in there when it has
## not moved onto an entry yet.
static func menu_state_of(menu: PopupMenu) -> String:
	var items := A11yElementTree.menu_items(menu)
	if items.is_empty():
		return "empty"
	var current := A11yElementTree.menu_current_item(menu)
	if items.find(current) == -1:
		return "%d %s, nothing selected" % [items.size(), "entry" if items.size() == 1 else "entries"]
	return menu_item_text(menu, current)


## One entry, read the way VoiceOver reads a menu row:
## "Autosave, checked, 2 of 4."
static func menu_item_text(menu: PopupMenu, index: int) -> String:
	if menu == null or not is_instance_valid(menu):
		return ""
	if index < 0 or index >= menu.get_item_count():
		return ""
	var parts: Array[String] = []
	var label := menu.get_item_text(index).strip_edges()
	parts.append(label if not label.is_empty() else "unnamed")
	# Every entry in an OptionButton's dropdown is a radio item with the current
	# one ticked, so a tick here would only repeat what "2 of 3" and the button's
	# own readout already say. 
	var is_dropdown := menu.get_parent() is OptionButton
	if not is_dropdown and (menu.is_item_checkable(index) or menu.is_item_radio_checkable(index)):
		parts.append("checked" if menu.is_item_checked(index) else "unchecked")
	var states := menu.get_item_multistate_max(index)
	if states > 1:
		parts.append("state %d of %d" % [menu.get_item_multistate(index) + 1, states])
	if A11yElementTree.menu_submenu_of(menu, index) != null:
		parts.append("submenu")
	var items := A11yElementTree.menu_items(menu)
	var pos := items.find(index)
	if pos >= 0:
		parts.append("%d of %d" % [pos + 1, items.size()])
	return ", ".join(parts)


## What a window is called when it opens or closes. A [PopupMenu] is named
## after whatever opened it; anything else has a title bar to borrow from.
static func window_title_of(w: Window) -> String:
	if w == null or not is_instance_valid(w):
		return ""
	if w is PopupMenu:
		return menu_name_of(w as PopupMenu)
	var explicit := String(w.get_meta("a11y_label", ""))
	if not explicit.is_empty():
		return explicit
	return w.title if not w.title.is_empty() else humanize(w.name)


## How a [Range] reads out. A 0..100 range is spoken as a percentage because
## that is what it almost always is; anything else gets "N of MAX".
static func value_text(r: Range) -> String:
	var value := _trim_number(r.value)
	if is_equal_approx(r.min_value, 0.0) and is_equal_approx(r.max_value, 100.0):
		return "%s percent" % value
	return "%s of %s" % [value, _trim_number(r.max_value)]


static func is_adjustable(c: Control) -> bool:
	if c is ProgressBar:
		return false
	if A11yElementTree.menu_of(c) != null:
		return true
	return c is Range or c is OptionButton or c is TabBar or c is ItemList or c is Tree


## "start_game_button" / "StartGameButton" -> "start game button"
static func humanize(raw: StringName) -> String:
	var s := String(raw).replace("_", " ").strip_edges()
	var out := ""
	for i in s.length():
		var ch := s[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower() and s[i - 1] != " ":
			out += " "
		out += ch
	return out.to_lower()


static func _trim_number(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.2f" % v
