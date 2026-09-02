@tool
extends EditorPlugin

## Editor-side presence for the direct touch addon.
##
## There is deliberately nothing here. The addon's whole surface is the
## [code]DirectTouchServer[/code] singleton, which the GDExtension registers
## whether or not this plugin is enabled - so the addon works even if someone
## only copies the files in. This exists so it shows up in the plugin list next
## to accessible_ui, which is where people will go looking for it.
##
## The label and hint VoiceOver reads are not settings of this addon. Whoever
## drives the surface owns those strings; accessible_ui keeps them under
## [code]accessible_ui/general/surface_label[/code] and
## [code]surface_hint[/code].
