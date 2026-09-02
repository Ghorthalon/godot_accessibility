@tool
class_name A11yActions
extends RefCounted

## Operating a control without seeing or touching it.
##
## Everything here goes through the control's normal path the signal Godot itself
## would emit - so game code that listens for `pressed` or `item_selected`
## keeps working with no changes. Nothing here reaches into a game's own
## callbacks.

## Double-tap: activate the element under the cursor.
static func activate(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	if c is BaseButton and c.disabled:
		return

	var menu := A11yElementTree.menu_of(c)
	if menu != null:
		_activate_menu_item(menu)
		return

	if c is LineEdit or c is TextEdit:
		c.grab_focus()
		var existing := String(c.text)
		DisplayServer.virtual_keyboard_show(existing, Rect2i(), DisplayServer.KEYBOARD_TYPE_DEFAULT, -1, existing.length())
		return

	if A11yElementTree.can_focus(c):
		# Preferred path: focus it and send ui_accept, which is exactly what a
		# keyboard player pressing Enter does. It runs the control's own
		# handling and unlike a synthesized click does not depend on there
		# being a real pointer - so it works on a touch-only device.
		c.grab_focus()
		_send_accept(c)
		return
	# Not focusable (a clickable Panel with an a11y_label for example). Nothing listens
	# for ui_accept there, so fall back to a real click at its centre.
	_synth_click(c)


## Swipe up (+1) / swipe down (-1) on an adjustable element.
## Returns what should be spoken back, or "" if the element does not adjust.
static func adjust(c: Control, delta: int) -> String:
	if c == null or not is_instance_valid(c) or delta == 0:
		return ""

	var menu := A11yElementTree.menu_of(c)
	if menu != null:
		return _adjust_menu(menu, delta)

	if c is Range and not c is ProgressBar:
		var r := c as Range
		var step := r.step
		if is_zero_approx(step):
			step = maxf((r.max_value - r.min_value) * 0.01, 0.01)
		r.value = clampf(r.value + step * delta, r.min_value, r.max_value)
		return A11yDescriber.value_text(r)

	if c is OptionButton:
		var ob := c as OptionButton
		if ob.item_count == 0:
			return ""
		var next := _step_index(ob.selected, delta, ob.item_count)
		# Disabled and separator entries are skipped the way arrow keys do.
		var guard := ob.item_count
		while (ob.is_item_disabled(next) or ob.is_item_separator(next)) and guard > 0:
			next = _step_index(next, delta, ob.item_count)
			guard -= 1
		ob.select(next)
		ob.item_selected.emit(next)
		return ob.get_item_text(next)

	if c is TabBar:
		var tb := c as TabBar
		if tb.tab_count == 0:
			return ""
		tb.current_tab = _step_index(tb.current_tab, delta, tb.tab_count)
		tb.tab_changed.emit(tb.current_tab)
		return "%s, %d of %d" % [tb.get_tab_title(tb.current_tab), tb.current_tab + 1, tb.tab_count]

	if c is ItemList:
		var il := c as ItemList
		if il.item_count == 0:
			return ""
		var sel := il.get_selected_items()
		var current: int = sel[0] if not sel.is_empty() else -1
		var index := _step_index(current, delta, il.item_count)
		il.select(index)
		il.ensure_current_is_visible()
		il.item_selected.emit(index)
		return "%s, %d of %d" % [il.get_item_text(index), index + 1, il.item_count]

	if c is Tree:
		var t := c as Tree
		var item := t.get_selected()
		var target: TreeItem = null
		if item == null:
			target = t.get_root()
		elif delta > 0:
			target = item.get_next_visible()
		else:
			target = item.get_prev_visible()
		if target == null:
			return ""
		target.select(maxi(t.get_selected_column(), 0))
		t.ensure_cursor_is_visible()
		return target.get_text(maxi(t.get_selected_column(), 0))

	return ""


## Two-finger scrub: back out of whatever is open.
## Returns what was closed, or "" if there was nothing to close.
static func escape(scope: Node) -> String:
	if scope is Window and scope != scope.get_tree().root:
		var w := scope as Window
		var title := A11yDescriber.window_title_of(w)
		if w is Popup:
			(w as Popup).hide()
		else:
			w.hide()
		return "Closed %s" % title
	return ""


## Swipe up and down inside an open menu. This moves the entry Godot itself
## calls focused, so the highlight follows the reader and anyone watching the
## screen sees the same row - and an [OptionButton] hears its own `id_focused`
## exactly as it would from the arrow keys.
static func _adjust_menu(menu: PopupMenu, delta: int) -> String:
	var items := A11yElementTree.menu_items(menu)
	if items.is_empty():
		return ""
	var pos := items.find(A11yElementTree.menu_current_item(menu))
	if pos == -1:
		pos = 0 if delta > 0 else items.size() - 1
	else:
		pos = clampi(pos + delta, 0, items.size() - 1)
	var index := items[pos]
	menu.set_focused_item(index)
	menu.scroll_to_item(index)
	menu.id_focused.emit(menu.get_item_id(index))
	return A11yDescriber.menu_item_text(menu, index)


## Double-tap inside an open menu picks the entry the cursor is on, doing what
## a click on it does: open its submenu if it has one, otherwise close the menus
## that asked to close and emit both signals, id first. A checkable entry is
## left untouched on purpose - Godot does not tick it either, the game does that
## in its own handler, and ticking it here would tick it twice.
static func _activate_menu_item(menu: PopupMenu) -> void:
	var index := A11yElementTree.menu_current_item(menu)
	if index < 0 or index >= menu.get_item_count():
		return
	if menu.is_item_separator(index) or menu.is_item_disabled(index):
		return

	var submenu := A11yElementTree.menu_submenu_of(menu, index)
	if submenu != null:
		if not submenu.visible:
			_open_submenu(menu, submenu)
		return

	var id := menu.get_item_id(index)
	if _hides_on_select(menu, index, menu):
		# Parent menus chained above this one close with it, the way picking
		# something in a submenu closes the menu it was opened from.
		var ancestor := menu.get_parent()
		while ancestor is PopupMenu and _hides_on_select(ancestor as PopupMenu, index, menu):
			(ancestor as PopupMenu).hide()
			ancestor = ancestor.get_parent()
		menu.hide()
	menu.id_pressed.emit(id)
	menu.index_pressed.emit(index)


## Whether picking entry [param index] of [param kind_owner] closes
## [param menu]. Which of the three switches applies depends on the kind of
## entry, and Godot asks the question of every menu in the chain.
static func _hides_on_select(menu: PopupMenu, index: int, kind_owner: PopupMenu) -> bool:
	if kind_owner.is_item_checkable(index) or kind_owner.is_item_radio_checkable(index):
		return menu.hide_on_checkable_item_selection
	if kind_owner.get_item_multistate_max(index) > 0:
		return menu.hide_on_state_item_selection
	return menu.hide_on_item_selection


## Godot places a submenu against the entry that opens it, from item geometry
## no script can see; beside the parent is close enough, since the reader is
## not looking at it. The parent may close itself once the submenu takes focus,
## which costs nothing here - the cursor has already followed the submenu, and
## the scrub gesture backs out of it either way.
static func _open_submenu(menu: PopupMenu, submenu: PopupMenu) -> void:
	submenu.exclusive = false
	submenu.reset_size()
	submenu.position = menu.position + Vector2i(menu.size.x, 0)
	# The same courtesy Godot does a submenu opened from the keyboard: land on
	# something pickable rather than on an empty highlight.
	var items := A11yElementTree.menu_items(submenu)
	if not items.is_empty():
		submenu.set_focused_item(items[0])
	submenu.popup()


static func _step_index(current: int, delta: int, count: int) -> int:
	if count <= 0:
		return -1
	if current < 0:
		return 0 if delta > 0 else count - 1
	return clampi(current + delta, 0, count - 1)


static func _send_accept(c: Control) -> void:
	var viewport := c.get_viewport()
	if viewport == null:
		return
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"ui_accept"
		ev.pressed = pressed
		viewport.push_input(ev)


## The same trick accessible_focus uses to open a context menu: build a real
## mouse press/release at the control's centre and push it into the viewport,
## so the control runs its own normal press handling.
static func _synth_click(c: Control) -> void:
	var viewport := c.get_viewport()
	if viewport == null:
		return
	var pos := c.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		viewport.push_input(ev, true)
