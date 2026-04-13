This repository contains plugins to help with some things inside the Godot editor which are currently not accessible, namely the 2d and 3d editors.

The 2d editor is in accessible_tilemap.
Create, edit, remove tiles in atlas, assign to tilemap layer, draw, fill, check tiles at coordinates.

The 3d editor is in accessible_rooms.

It's a node based system where you create rooms, assign them with doorways to other rooms. Everything is created using static bodies. You can edit these, you can remove parts of them, for example if you don't want walls or ceilings for outdoor spaces, you can create rooms at arbitrary positions for building rooms within rooms or houses ontop of a village square, things like that. Then at the end once you're done you press the bake button which unifies all of the collision shapes into one and optimizes the meshes a bit. This creates extremely basic maps, but it should definitely help get started. You can also place nodes at cursor positions. 

Sorry for the very sparse documentation. This is still very early days and I don't want to spend more time writing docs when I don't even know where this will end up. Check the .gd sources, there might be relevant comments at the top of the files for keyboard shortcuts and such. Otherwise, find me on the Unseen Engines discord. https://unseen-godot.com/
