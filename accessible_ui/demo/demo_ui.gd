extends Control

## A sample screen covering every control type accessible_ui knows how to
## describe and operate. Set it as the main scene of a test project (or add it
## to your own) to hear what the layer sounds like.
##
## It is also the manual on-device check: export this to a phone, cycle the
## mode with a three-finger triple tap, and swipe through.

var _log: Array[String] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "Accessible UI demo"
	root.add_child(title)

	var play := Button.new()
	play.name = "PlayButton"
	play.text = "Start game"
	play.set_meta("a11y_hint", "Begins a new run")
	play.pressed.connect(func(): _note("play pressed"))
	root.add_child(play)

	var locked := Button.new()
	locked.text = "Continue"
	locked.disabled = true
	root.add_child(locked)

	var fullscreen := CheckBox.new()
	fullscreen.text = "Fullscreen"
	fullscreen.toggled.connect(func(on: bool): _note("fullscreen %s" % on))
	root.add_child(fullscreen)

	var subtitles := CheckButton.new()
	subtitles.text = "Subtitles"
	root.add_child(subtitles)

	# A section, not a collapse: the cursor announces "Audio, group" on the way
	# in, the three-finger swipe jumps past it, and every control inside is
	# still reachable one swipe at a time.
	var volume_group := VBoxContainer.new()
	volume_group.set_meta("a11y_group", "Audio")
	volume_group.add_child(_labelled("Music volume"))
	var volume := HSlider.new()
	volume.name = "MusicVolume"
	volume.min_value = 0.0
	volume.max_value = 100.0
	volume.step = 5.0
	volume.value = 70.0
	volume.set_meta("a11y_label", "Music volume")
	volume.value_changed.connect(func(v: float): _note("volume %s" % v))
	volume_group.add_child(volume)
	root.add_child(volume_group)

	# A collapse, and the case it is actually for: three stars are one rating
	# to the player, so swiping through them individually would say nothing.
	var rating := HBoxContainer.new()
	rating.set_meta("a11y_collapse", true)
	rating.set_meta("a11y_label", "Difficulty rating, 2 of 3 stars")
	for i in 3:
		var star := Label.new()
		star.text = "*" if i < 2 else "-"
		rating.add_child(star)
	volume_group.add_child(rating)

	var lives := SpinBox.new()
	lives.min_value = 1
	lives.max_value = 9
	lives.value = 3
	lives.set_meta("a11y_label", "Starting lives")
	root.add_child(lives)

	var difficulty := OptionButton.new()
	difficulty.set_meta("a11y_label", "Difficulty")
	for name in ["Relaxed", "Normal", "Brutal"]:
		difficulty.add_item(name)
	difficulty.select(1)
	difficulty.item_selected.connect(func(i: int): _note("difficulty %d" % i))
	root.add_child(difficulty)

	var player_name := LineEdit.new()
	player_name.placeholder_text = "Player name"
	root.add_child(player_name)

	var tabs := TabBar.new()
	tabs.set_meta("a11y_label", "Settings section")
	for name in ["Audio", "Video", "Controls"]:
		tabs.add_tab(name)
	root.add_child(tabs)

	var saves := ItemList.new()
	saves.set_meta("a11y_label", "Save slots")
	saves.custom_minimum_size = Vector2(0, 120)
	for i in 3:
		saves.add_item("Slot %d" % (i + 1))
	saves.select(0)
	root.add_child(saves)

	# Decoration is not spoken
	var spacer := ColorRect.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	spacer.set_meta("a11y_hidden", true)
	root.add_child(spacer)

	var about := Button.new()
	about.name = "AboutButton"
	about.text = "About"
	root.add_child(about)

	var dialog := AcceptDialog.new()
	dialog.title = "About this demo"
	dialog.dialog_text = "A sample screen for the accessible_ui addon."
	add_child(dialog)
	about.pressed.connect(func(): dialog.popup_centered(Vector2i(320, 160)))


	var diagnostics := Button.new()
	diagnostics.name = "DiagnosticsButton"
	diagnostics.text = "Read status"
	diagnostics.set_meta("a11y_hint", "Speaks the screen reader backend in use")
	diagnostics.pressed.connect(_read_status)
	root.add_child(diagnostics)


## The autoload, looked up by path rather than by its global identifier.
##
## Turning the addon's editor plugin off strips the `AccessibleUI` autoload line
## out of project.godot, and every script naming that identifier then fails to
## parse which takes the whole project down. Reaching for
## the node instead keeps this file compiling either way.
func _reader() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/AccessibleUI")


func _read_status() -> void:
	var reader := _reader()
	if reader != null:
		reader.speak(status_line(), A11ySpeech.Priority.ASSERTIVE)


## One spoken sentence describing how the reader is currently wired up.
##
## On iOS this is how you tell the two working configurations apart without
## being able to see the screen: "VoiceOver" means godot_direct_touch is
## installed and VoiceOver is running, so speech is going through the player's
## own voice; "System text to speech" means it is not, and VoiceOver must be off
## for the gestures to work at all.
func status_line() -> String:
	var parts: Array[String] = []

	var reader := _reader()
	if reader == null:
		return "Accessible UI autoload is not registered."
	parts.append("Mode, %s" % reader.mode_name(reader.get_mode()))

	var speech := reader.get_node_or_null("Speech")
	if speech != null and speech.has_method("backend_name"):
		parts.append("speech, %s" % speech.backend_name())

	if Engine.has_singleton("DirectTouchServer"):
		var dt: Object = Engine.get_singleton("DirectTouchServer")
		if dt.is_supported():
			parts.append("direct touch surface, %s" % ("on" if dt.is_surface_enabled() else "off"))
			parts.append("VoiceOver, %s" % ("running" if dt.is_screen_reader_active() else "off"))
		else:
			parts.append("direct touch, not supported on this platform")
	else:
		parts.append("direct touch addon, not installed")

	return ". ".join(parts) + "."



func get_log() -> Array[String]:
	return _log


func _note(entry: String) -> void:
	_log.append(entry)
	print("[demo] ", entry)


func _labelled(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
