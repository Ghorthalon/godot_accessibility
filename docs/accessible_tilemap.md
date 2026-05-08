# accessible_tilemap

This is an addon which attempts to make Tilemap editing accessible in Godot. It can utilize existing tilemaps, or create new tilemaps without having any tilesheet graphics. It can create a custom tilesheet for you which is 128 tiles long for now with a placeholder color filled in.

## How to use this addon

This addon will place itself in the bottom dock, where other tilemap layer editor plugins typically go. Select a tilemap layer node or resource, and it will show. You can use the [GMap Hotkeys script](https://github.com/ericrbomb/unseengodot) to focus is directly using a shortcut, or find it by tabbing past the main view of the editor, for example, the accessible_rooms view, script editor, or any other main view that might be enabled. You can also focus the signals panel and shift tab to find the bottom dock tab bar, then right or left arrow until you hear accessible tilemap.

## UI

The addon is split into 3 tabs. 

### Atlas

The atlas tab is where you define tiles and their physics, names, and so on. This is where you set what is what.

New tileset: This will create a new tileset. If you currently do not have a tileset, you should create one here.

Save tileset: If you have made any changes to the tileset, for example add or remove tiles, change physics settings, etc. you press this button to write those changes to the tileset resource.

Tileset resource path: If you want to specifically load an existing tileset resource, you can enter it's path here and press the load button. This will populate all of the data that this addon can edit in the respective lists and edit boxes.

Use selected tilemap layer's tileset: If there is a tilemap layer in the scene, this button will load the tileset from it instead of using a standalone resource.

Assign tileset to selected tilemap layer: If your scene has a tilemap layer in it, but it does not have a tileset assigned, this will assign the currently opened tileset to the selected tilemap layer automatically.

Custom data layers list: This is where you can assign custom data for the tileset. For example, the name of the surface, or any other custom data that you might want to set per tile. This is basically the metadata for each tile in your tileset. You have buttons to add a new layer, or remove the selected layer. Each layer automatically gets the name layer added by the addon, as identifying them otherwise can be very challenging. 

Physics layer list: This is the physics layer list that you can assign to each tile. Note that this only affects the tileset, and not the tilemap layer node. You can assign each physics layer you have here to a physics layer in Godot. They are separate, so you have to wire this up manually yourself in the Tileset Resources inspector. Each tileset's physics layer will show up in the inspector, and you can select which physics layer in Godot this will be mapped to. For more info about physics layers, please do read the Godot documentation. You have buttons to add a new physics layer here, or remove the selected one. Different layers are useful if you want only specific entities to be able to collide with specific tiles. 

Tileset source: This is the tileset source that you want to add and remove tiles to. This is an option button which will tell you how many tiles are defined on each source. You must have at least one source to be able to assign any tiles to the atlas. There are buttons to add an atlas source, or a scene collection source, or remove the selected one.


Tile list: This is the list of tiles defined on the current tileset and source. It will tell you the name of the tile, and where it is in the atlas. If you use the addon to programatically create this, the tiles will go from left to right in the tilesheet in a single row. If you use an existing tilesheet, it will tell you the exact coordinates at which the tile is defined in the sheet. Again, you have buttons to add a new tile here or remove it. Pressing add will ask you for it's name and then create it. You can also add a scene, if you have a scene collection source selected and not an atlas source. This is more advanced and gives you more control over what a tile actually is in your scene.

After this are the information about the current tile. You can enter a name here, and you can check whether this tile is solid or not, so whether it has collision you can assign in the tilemap layer node.

So to recap: If you want tilemaps in your game, your scene must have at least one Tilemap Layer node. This Tilemap Layer must have a tileset assigned to it. A tileset has multiple properties, for example custom data layers for things such as names, damage values for tiles that do damage, etc. as well as physics layers which you can map to physics layers within Godot's physics system. Each tileset has a source. This source defines what tiles you have in your tilesheet, where they are, and whether they have collision or not. These tiles can be defined purely inline on an atlas source, or as scenes in a scene collection source. This sounds confusing, but it gives you a lot of power.

### Map tab

This is the fun part. After you've set up your tiles in the Atlas tab, this is where you actually begin painting your world.

The editor will let you edit any tilemap layer in your scene. If this tab says no scene open but you're sure you do have one, press refresh. This will scan the scene for the tilemap layer and select it. If you have multiple, you can select which one you want to edit from that dropdown.

The palette tile is the tile you will be painting. This is a list of all the tiles you defined in the Atlas tab for the current tilemap layer.

Shift arrow step size lets you adjust how far each shift+arrow press will move the cursor. More on this below.

Grid: This is the actual editor. This is where you can begin to use keyboard shortcuts to start painting your tiles.

The following keyboard shortcuts work here:

* Arrow keys: Move the cursor cell by cell on the map.
* shift + arrows: Jump by a larger value, depending on what you set above. 
* control arrows: Jump to the next different cell in that direction. For example, if you have a large field of grass, ctrl right arrow will jump you across all of it to the next tile that is not grass.
* home and end: Jump to the first or last cell currently occupied on this tilemap row.
* Page up and down: The same but for columns. 
* Enter or space: Paint the currently selected tile at the cursor's position. 
* Delete or backspace: Delete the tile under the cursor.
* r: Set the rectangle anchor. This is the beginning of a selection. 
* F: Fill the area between the rectangle anchor and the cursor with the selected tile. 
* e: Erase any tiles between the rectangle anchor and your cursor.
* G: Jump to position. Opens a dialog with x and y position edits.
* L: Cycles between active Tilemap Layers
* T: Cycles the tile to be painted. 
* w: Reads information about which tiles are at the cursor's position across all layers.
* b: Reads the map bounds that currently have tiles painted in it.


### Spatial tab

This is not related to tilemaps, but it tries to present your nodes in the current scene spatially. So you can navigate them in relation to other nodes. However this is fairly untested. I would recommend skipping this for now, and using [Eric's unseen grid scene](https://github.com/ericrbomb/unseengodot) instead. 

## WIP

This addon is still a heavy work in progress. I've mostly focused my efforts on 3D, so I only tested to make sure this addon actually works. It was mostly a learning project for me. I want to get back to 2d development in the future, but I love first person audio experiences, so that's where most of my focus is going at the moment.

If you have any suggestions, issues, or anything else, either open an issue here, start a discussion, or come find me on the [Unseen Godot Discord Server](https://discord.gg/RmWNjcgHKx)