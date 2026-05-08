# accessible_animations

This is a simple interface for dealing with animations inside Godot.

Animations are timelines which can change any value of any object. This goes for things such as position, any other kind of value available on your node like health or similar, but it can also call methods, play sounds, start other animations, etc.

## How to use this addon

You have two methods of working with animations that this addon supports. Either you add an animation player node to your object, and assign an animation to it from the inspector. Navigating to any node which contains an animation player with an animation set on it will automatically enable the dock tab for the animation. Alternatively, you can create and select an animation resource from the filesystem. Pressing enter/opening it inside the filesystem will also enable it. You can use the [GMap Hotkeys script](https://github.com/ericrbomb/unseengodot) to focus is directly using a shortcut, or find it by tabbing past the main view of the editor, for example, the accessible_rooms view, script editor, or any other main view that might be enabled. You can also focus the signals panel and shift tab to find the bottom dock tab bar, then right arrow until you hear accessible anim.

## UI

Active animation: This is the active animation to edit. An animation player can have multiple animations within it, and this is what let's you select which one is being edited.

New animation: This allows you to add a new animation. After creating it, it will be automatically selected, and also show up in the list above.

Delete animation: This allows you to delete an animatino from the animation list.

Animation length: The amount in seconds for how long this animation should play for.

Loop mode: Determines how the animation should loop, or whether it should play once and then stop.

Play animation: Will play the animation in the editor.

Stop animation: Will stop the animation if it is currently playing.

Seek: This allows you to move the cursor manually to any time you enter here.

Animationt rack list: This is the list of tracks currently in the animation. It will tell you the track number, what kind of animation it is, what value is being animated, and how many key frames exist. A key is basically an automation point at which a value should reach a specific point, or a method will be called, audio will be played, etc.

Add track: Creates a new track. This will open a dialog with options for the new track:

* Track type: The kind of track to create. Choosing different things here will modify the rest of the dialog, enabling and disabling different items depending on what the track type actually supports. If you want more information on how the different animation track types actually work, please consult the Godot documentation.
* node path: The path to the node relative to the animation, or a full path from your scene root.
* Property path: The path of the property to edit. If you have multiple object levels deep, you can separate them by colon. For example position:x to animate the x position. This field might be hidden if your track type does not require or support a property path, for example for position3d.

Escape closes the dialog, and the add button adds the track to the animation.

Remove selected track: This will remove the currently selected track in the track list from the animation.

Timeline step: This is basically your zoom level. Making this smaller makes the cursor move in smaller increments. 

Animation timeline: This is where you actually use the timeline with the keyboard to edit the currently selected track. Everything you do here will be announced by the screen reader. The following keyboard shortcuts exist:

* left and right arrow: Move the cursor by the timeline step size left and right through the timeline. If you land on a keyframe, it will announce it, as well as what the value it will be set to.
* Control left and right: Jump to the next or previous keyframe.
* Space: Insert a new keyframe at the cursor
* Delete or backspace: Delete the keyframe under the cursor
* up and down arrow: Adjust the keyframe value of the keyframe under the cursor. Shift moves by larger increments, control moves by smaller increments.
* Enter: Edit the value of the keyframe under the cursor.

That's it. It's a very simple plugin but I hope it is still useful. If you have any suggestions, issues, or anything else, either open an issue here, start a discussion, or come find me on the [Unseen Godot Discord Server](https://discord.gg/RmWNjcgHKx)