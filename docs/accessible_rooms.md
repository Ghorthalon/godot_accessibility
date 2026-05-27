# accessible_rooms

accessible_rooms is a Godot addon which helps blind devs create and manage 3d scenes. It let's you place rooms, ramps, stairs, nodes, scenes and move them around. You get spoken information through your screen reader for all operations, which tell you what happened, and why. It also plays sounds depending on what you're doing. For example, while moving around using its cursor, it plays a sound at the center of any object that you're currently in, so you can immediately know exactly where you are in relation to the exact center of the entity. 

## Concepts

The way this addon works is by using conceptual building blocks which let you map out your 3d world. You place these either by themselves, or within other building blocks. You can also connect them to each other directly, so you don't have to manually figure out where walls need to be split and what the height differences need to be, the addon can figure this out for you.

This leads to very basic but workable geometry. It is very rectangular, right now I don't really have anything written for non-rectangular geometry, but there's no real reason why that couldn't work. This was conceptually much easier to implement and should already cover a large amount of usecases except for circular and spherical environments. This is a limitation, but it does also mean that things are much easier to reason about in your head. I am definitely open for suggestions here though on how to make non-rectangular geometry more accessible. One of my ideas for example is to have more of a voxel style editor. I've played with those in other game engine projects and they seem to work well, but they have other issues, quantization being the big one. Doing 3d accessibly is inherently difficult, and I wanted it to be as easy as possible here to figure out what you're doing. 

### Rooms

The most often used building block is the room. A room is a rectangular entity which has a floor, and optionally walls and ceiling. You set the width, height and depth, move the cursor to the center of where you want the room to exist, and place it. Alternatively, you create a selection using the cursor, and then place a room from selection, which fills the entire selection with the room. so the floor is at the bottom part of the selection, the ceiling is at the top part of the selection, and the walls surround the selection.

### Ramps

Ramps are basically tilted rooms. You tell it the clearance, so the distance between ramp floor and ceiling, the direction it should go, and it's width and length. It will then create a room which is tilted/slanted to match the figures you put in. This is useful for connecting different levels together, or in outdoor areas by disabling the walls and ceiling.

### Stairs

They're exactly what you think they'd be. They can also optionally have walls and ceilings, but are also not required. You define how long, wide, and high the steps should go, and optionally how many steps you want the stairs to have, and which direction they should face. It can also automatically calculate how many steps are required to get you from the bottom to the top.

## How to use this addon

You find the addon's interface in the top main toolbar as a main view of the Godot editor. 
One of the ways of getting there is to find the menu bar, then tab ahead until you hear "rooms". Press the button so it's toggled on. 

This means in the tab order it will show up right after your file system. If you're using [Eric's addons](https://github.com/EricRBomb/unseengodot) there will be a key which will jump you to the main view, I believe it is ctrl 4. The key for the menu bar is ctrl 6 (?).

### Addon UI

I will go through each part of the UI and explain what it does. By the end of this you should have a fairly clear understanding of how this addon works. If things are unclear or I could improve these docs, feel free to let me know.

#### Global controls

* Use selected node as parent: this will change the root node that the addon uses for all of its operations. For example, if you're editing a level but want all of it's nodes to go into a specific node, you would toggle this on. If you have this off, it will do all of it's operations on the root node of the current scene you have open.
* Move cursor to selected object: If you use any of the lists inside the addon to select a different room, in any of the tabs we will get to shortly, or by moving inside the scene tree, this will automatically move the cursor to the entity you have selected, whether that's a room, ramp, or any node3d or subclass of node3d at all in the scene tree.

#### Rooms tab

This is where you create rooms. The rooms tab is divided into a few subtabs, as it has a lot of controls.

##### Rooms subtab

* Room list: This is the list of rooms that the addon has found in the current placement parent. If use selected node is checked, it will scan the selected node. If it is not checked, it will scan the root node of the scene you have open. It will tell you the room name and it's dimensions. Selecting it here will also select it for any future operations on rooms. For example, you will select a room here, then the buttons above will operate on the room selected here. 
* Refresh entity list: This will rescan the scene tree manually. If your room list is empty but you know you have nodes, this will fix it.
* Resize anchor:
    * NW, N, NE, E, SE, S, SW, W: When you resize a room, the room will usually be resized from it's center. This is problematic if you already have rooms connecting to other rooms, because they will be pulled away from the connecting room as they shrink inward. These anchors will let you set from which point the room will grow or shrink. For example, if you set the anchor to NE, then the northeast corner will stay exactly where it is, and the room will shrink inward, or grow outward, from the most northeastern point. Similarly, if you set this to south, then the room will grow and shrink towards the top and sides, while the southern edge remains exactly where it is.
    * Smart anchor: This will scan the room to figure out which sides are connected to sides of other surrounding spatial entities, and set the smart anchor to those. If you have something already built, this is usually what you want. This way, it will only shrink or grow the the room in the direction which does not have something on that side, while keeping the sides which do connect to something untouched.
* Cascade: When you resize a room, this option will make sure to move every other room which is in the way as well so that the room can be resized. It will check any room which is connected to the current one, and every room connected to those, until no more rooms are connected. Then it will push everything out of the way so the resize can happen while still keeping everything connected.
* W, H, D: If you have a room selected in the list, these 3 spin boxes will let you set the size to resize the room for. If you do not have a room selected, these boxes are disabled. 
* Apply changes: This will actually perform the room resize
* Measure space at cursor: This will scan the surrounding geometry and tell you how much free space you have in any direction.
* Resize:
    * Resize room to fill E->W, resize room to fill N->S: These two controls will measure the current free space at the cursor and expand the room you have selected to fill it. This is useful if you have two rooms which are currently not connected, but want to connect them using another room, hallway, etc.
* Move room to:
    * x: The x coordinate to move the currently selected room to. This will make sure that walls still line up and openings between rooms are kept in tact.
    * y: The y coordinate to move the selected room to.
    * z: The z coordinate to move the current room to.
    * Cascade: When moving rooms, moves all other connected rooms with it so your geometry stays in tact. Good for moving an entire section of map.
    * set from cursor: Sets the x, y, and z values to where your cursor is.
    * apply move: Applies the move. If any connections would be broken, it tells you. HOld shift to force the move anyway and break them.
* w: The width of the room to create
* h: the height of the room to create
* d: the depth of the room to create
* Build walls: If checked, walls will surround the created room. If unchecked, they won't. Useful for creating larger rooms out of smaller ones, or for outdoor areas. 
* Build ceiling: The exact same as walls but for ceilings.
* New standalone room: This places a room at the current cursor position. We will get to the cursor in a moment. The room will be placed so that the room's exact center is at the cursor, so the room will surround it.
* Place room from corners: If you made a selection using the cursor, again, more on this below, this will fill the selection that you made with the room.
* Add room to north of current: This will add a room to the north of the currently selected room. It takes the width, depth and height you have selected, positions the room so that its middle lines up with the middle of the northern wall, and automatically punches a doorway if build walls is enabled.
* Add room to south, east and west of current: Exactly the same as north, except in any of the 3 remaining directions.
* Gap detection:
    * max gap: Gap detection let's you check if you have geometry which *should* connect but it isn't. This is how far of a gap it should still flag as a connection issue.
    * Check gaps: This checks the placement parent for any rooms which are within max distance of another room, with openings that would allow you to walk through. This potentially let's players fall through the map. If this is desired, you can ignore this, but if it is not, you can fix them here. 

##### Doors & Walls subtab

* Doorway size:
    * w: The width of any doorways to create. Doorways are always created locally to the wall they are placed on. So width will always mean the space along the wall, no matter which direction the wall is facing. 
    * h: the height of any doorway to create
* Create door placeholders at new doorways: If checked, it will create a simple node3d where the door should go. You can reparent this or change it to your door scene, or remove it entirely and place your actual doors manually. Or you can also just keep it open if you don't actually want any doors.
* Punch doorway north on current: This punches a doorway in the middle of the northern wall. Useful if you have a room there which does not have a connection to this room yet, or if you plan to build something else there later by hand.
* Punch doorway at cursor (on nearest wall): This will punch a doorway using the entered dimensions at the nearest wall to the cursor.
* Punch doorway on north, south, east, or west of current room: Adds a doorway at the middle of the selected side of the room's wall. The door will always start level with the floor.
* Punch hole at cursor (on nearest wall): Doorways are always placed at the bottom or floor or a room. If your door height is sufficiently small, this button will not do this, and instead take your cursor as the center point of the hole to punch instead. This can be useful for windows, firing holes, or other such geometry.
* Doorway list: This will show you each hole / doorway that is currently present in the room. This will look something like: [0] east  U:5.00 V:-1.25  2.0×2.5m. This means: 0 is the index, U is the horizontal position along the wall from left to right, V is the vertical position along the wall from top to bottom, and the size. The wall local coordinates start in the middle of the wall, so the exact center middle is 0,0.
* If you have a door selected, the next fields are:
    * Name: A name for the doorway, useful for keeping track of many of them in one room
    * side: The wall that this door is placed on,
    * U: The horizontal position on the wall
    * V: The vertical position on the wall
    * w: The width of the door
    * h: The height of the door
    * Apply door changes: This will reconfigure the door using the values you have set here. Again, keep in mind that the horizontal, vertical, width and height are wall local. This means that the width will always be along the wall, no matter which direction the wall is facing. If you set a 2m wide doorway, the doorway will always face through the wall. It is impossible to create a doorway which faces the wrong way.
    * remove selected door: This will remove the door you have selected here and will fill it with wall.
* Walls on selected room: This is a list of all of the walls that this room is made up of. You have all of the cardinal directions, as well as floor and ceiling. This is where you can set the surface metadata which is written to each object, and disable any of the individual walls, floor, or ceiling.
    * enabled: Whether this wall is constructed or not.
    * Surface: The surface string which is available on get_meta("surface") on the object. Useful for things like footsteps. 
    * Apply wall changes: Reconfigure the wall with the settings you have set here.

##### Bake subtab

* Bake scene: this takes all of the addon created rooms, ramps, and other geometry, and compiles it into plain Godot nodes instead. It also merges the geometry into single meshes where possible, while keeping any custom data you might have entered for surfaces and so on. This will improve performance a lot especially for larger worlds. This also allows you to place scripts and such on your room geometry yourself, as before all of this would be taken up by the addon's scripts instead and you would need to subclass from the addon's authoring scripts. There are two buttons. One of them will replace your current scene, so it will delete the nodes within it and replace them with the baked versions. The other one will bake it to a new scene. This is recommended. I usually have a dev scene which I exclude from being shipped, which is where I do all my editing. I then save it to a world baked scene when it's time to ship or I'm actually done with the environment. I always keep them around however in case I need to make edits.

#### Ramps:

Ramps are tilted sections of floor. They don't have walls or ceilings by themselves, so if they should have those, you should put them inside a room.

* W: The width of the ramp
* len: The length of the ramp
* rise: How high the ramp should go.
* clear: The clearance between the ramp's floor and the ramp's ceiling. This has to be at least slightly taller than your character. This can automatically cut a hole out of the ceiling of it's parent room based on the clearance factor.
* Land Low: The length of a section of flat floor placed at the bottom part of a ramp.
* Land High: The same, except at the top end.
* Standalone ramp high end: When placing a standalone ramp and not one based on corner selection, this selects which direction the ramp will slope up towards.
* Place ramp in current room at cursor: This places a ramp with the cursor as the mid point inside the current room. This uses the settings you've set above.
* Place ramp in current room from corners: This uses the current selection from the cursor tab to determine how wide, long, and high the ramp should be. Depending on where your selection points are set, it will also figure out which way the ramp should tilt. You can still override this of course.
* New standalone ramp at cursor: Exactly the same as new standalone room at cursor. This places the ramp where your cursor is, with it's center where the cursor is, and does not parent it to the current room.
* Place standalone ramp from corners: Same as the cursor method above, except it uses the corner selection to figure out all of its details.

#### Stairs:

These are basically the same as ramps, except they're not smooth and have actual steps.

* W: The width of the stairs
* rise: How high up the stairs will go
* len: The length of the stairs
* clear: The clearance between each step and the ceiling. Must be at least a little bit higher than your character body.
* steps (0=auto): the amount of steps to create. If set to 0, it will try to find a reasonable amount of steps so your character can walk it. If you have a specific number of steps you want this to create, you can enter them here. Note that your steps can absolutely be too tall for your character to clear, so be careful.
* Land Low: A flat bit of floor that gets added at the bottom part of the stairs, in units.
* Land High: The same, except at the top end.
* Build risers: Whether to build risers for these stairs. Risers are the vertical bits of geometry between each step, so nothing can fall through in the gaps.
* Standalone stairs high end: The same as ramps. When placing a standalone stairs, which direction should they go?
The next couple of buttons mirror rooms and ramps exactly.


#### Cursor

The cursor can be moved in 3d space to examine what's around. This is a very useful tool to explore and create new rooms and place entities. The cursor also has many useful keyboard shortcuts, so many things can be done from within this tab. Anything that uses the cursor or spatial positioning, like placing a standalone room or ramps or stairs, moving objects, so on, require the cursor to be moved to where you want this action to happen. 

* Step: The step size to move the cursor whenever you press any key.
* Move west, east, north, south, up, down: Move the cursor in that direction.
* Snap cursor to current room: Snaps the cursor to the middle of the current room you're in.
* Probe distances: Will scan around the cursor to determine how much free space you have around. This will also play sounds at exactly where the collisions occur, so you can audibly hear the size of free space.
* Report cursor location: Will announce the current cursor position, and any contextual information such as if you're within a room, object, or similar.
* Snap cursor to geometry:
    * floor: Snap the cursor to the floor of the current room.
    * north, south, east, west: Snap the cursor to the north, south, east or west wall of the current room.
* set corner A: Set the first corner of the selection to the current cursor position. This is usually the bottom left selection point.
* Set corner B (Cursor): Sets the second corner of the selection, usually the top right. After setting this one, you have an active selection.
* Keyboard navigation (NVDA only says payne for some reason): This is where you can move the cursor using the keyboard. Here are the keyboard shortcuts you can use.
    * Arrow keys: Move the cursor north, south, east or west.
    * A, Z: Move the cursor up and down. 
    * Control + Cursor keys/ a/z: Jump cursor to the nearest entity in that direction. Floors, walls, objects, etc.
    * shift a, shift z: Increase and decrease step size
    * shift arrows: Snap cursor to walls in that direction
    * f: Snap cursor to floor
    * r: Snap cursor to current room
    * p: Probe distances
    * l: Report cursor location
    * ctrl r: New standalone room at cursor
    * ctrl d: Punch doorway at cursor on nearest wall
    * ctrl 1, ctrl 2: Set corner a, and corner b for selection
    * ctrl 3: place room from corners
    * ctrl shift 3: Add zone to floor
    * shift f: Nudge selected node to floor
    * shift w: Snap selected node to nearest wall
    * shift d: Snap selected node to nearest doorway
    * shift c: Center selected node from east to west
    * shift v: center selected node from north to south
* audio preview: If the game is running, this will attempt to let you move the audio listener inside the game world so you can hear what your environment sounds like. You can also enable playing on audio sources inside the editor and move the cursor that way, though that might be more cumbersome.
* Jump to entity: The next buttons do what control + arrow keys do.

#### Place

This let's you place nodes or scenes in the world using the cursor.

* Place node at cursor: Select the kind of node3d you would like to place at the cursor.
* insert: Inserts the selected node at the cursor.
* Insert scene: Enter a scene path here that you want to spawn.
* insert scene: Inserts the scene at the cursor's position
* Insert physical object:
    * w, h, d: The width, height and depth of the object template to insert
    * Create physical object at cursor: This will create a static body 3d at the cursor with a box collider which is ready for you to configure.
    * create from selection: This will let you create a physical object at the position and dimensions of your selection.
* Floor zones:
    * surface: This will override the room's default surface at these coordinates. Useful for footstep variety. For example, a gravel path on grassy floor, or a carpet on wood.
    * Add zone to room floor: Adds the surface at the selection. You must have a selection for this to work.
    * Clear all zones from floor: Removes all zones from the floor.
* Snap selected node: This will take the node you have currently selected in the scene tree and allows you to move it flush with geometry of your room
    * Floor offset: How high from the ground to snap
    * Nudge to floor: Moves the selected object to the floor
    * wall offset: How much clearance to leave between wall and object
    * Snap to nearest wall: Moves the object to the nearest wall at the cursor
    * center e->w: Centers the item from east to west. 
    * center n->s: Centers the item from north to south
    * Door inset: How far the item should be pushed out of the door to not be completely flush with the wall.
    * Snap to nearest doorway: Moves the selected node to the nearest doorway to the cursor.
    * measure space at node: Tells you how much free space you have from the selected node in the scene tree

#### Objects

This tab allows you to move objects in a physics aware manner.

* Report position: This reports the center / origin position of the object selected in the scene tree.
* Measure distances: This measures the distance to the next objects in all 6 directions from the objects, and plays audio at the spots where objects are hit.
* Move to cursor: This allows you to move the object to the cursor.
    * Check if cursor is clear: This checks if you can actually move the object to the cursor. It takes any overlaps, collisions, etc. into consideration and tells you whether the object will fit where you have the cursor.
    * Move to cursor: This will move the object to the cursor location. If the object fits, pressing this button will simply move the object. If the object does not fit, it will give you a warning. If you still want to move the object even though it might not fit, you can hold shift and press this button, which will force the move to happen regardless. Keep in mind that this will lodge the object in any blocking geometry, so funny physics issues might occur if you set this up wrong.
* Nudge, collision aware:
    * distance: The distance to nudge the object by
    * North, south, east, west, up, down: Nudge the object by the distance set above in any of the directions.
* Snap to floor: This snaps the object so that it sits flush with the floor.
* Floor offset: Set the amount of clearance between the object and the floor when it is being snapped.
* Snap to nearest wall: This snaps the object to sit flush with the nearest wall.
* Wall offset: How much clearance to leave between the object and the wall when it is being snapped.
* Center e->w: Center the object from east to west along the nearest wall.
* center n->s: Center the object from north to south along the nearest wall.
* Snap to nearest doorway: This moves the object to the nearest doorway to the cursor.
* Door inset: As above, how much the object should be pushed in or out of the doorway to not be completely flush with the door geometry.

#### Scene

This is a list of all of the nodes in the current scene in a list sorted by distance from the cursor. If the list is empty but your scene actually contains items, press refresh and they will show up. Each entry in the list will tell you the object's position, dimensions, whether it is a child node of any parent node all the way up the chain, and if it is currently inside any room. It will also play a sound at the object's position, and select it if the relevant global option to select nodes when moving is enabled. This will also make it immediately editable inside the inspector.

## Status:

This addon is currently still a work in progress. Things might still change drastically from how it works now. If you have any feedback, questions, suggestions, feel free to either open an issue or discussion here, or find me on the [Unseen Godot Discord Server](https://discord.gg/RmWNjcgHKx)

I truly hope this is useful to you. Have fun building! 