# Godot Accessibility Playground

Hey. Thanks for checking out my Godot addons.

I'm a blind gamedev and needed some help with the Godot editor in the state it is currently in. I am beyond grateful for everyone who works on accessibility on Godot, and it is thanks to you that this ist arting to become reality.

That said, there are still some gaps, and these addons are me trying to fill them for myself. 

If you're not blind, I assume nothing will be of use for you here. Most of this is replacement docks and panels for areas in which Godot currently, or might never, have accessible alternatives for, or currently lacks support in some way. Below is a list of all of the addons, with links to short documentation explaining what each plugin does and how it's used.

Keep in mind that it is still very early days. These addons change constantly, Godot might change, and at times, the documentation might be out of date. I will do my best to keep things updated, but I might forget. If something is confusing, not explained well or just... wrong, feel free to poke me about it.

## Before you start

If you're a blind game dev trying to use Godot, you might notice that a lot of things inside the editor are still quite sharp edged. Luckily, we have a fix for most of it. Eric from [Unseen Godot](https://unseen-godot.com/) and [some really fun games](https://ericbomb.itch.io/) and the host of the Games for Blind Gamers game jams has made some truly lifesaving [addons for Godot](https://github.com/EricRBomb/UnseenGodot) which you should be using. They will help you a lot and fix some of the currently still quite rough focus and navigation issues inside the Godot editor. In fact, if you're completely new to Godot, check out the Unseen Godot page first, and work through some of the tutorials on that page. These addons are for when you're done with them and need access to some of Godot's more powerful stuff.

## The addons

I have the following addons for you:

* [accessible_rooms](./accessible_rooms.md) - My most ambitious addon, which aims to give you a more blind friendly interface for building and managing 3d scenes using concepts such as rooms, ramps, stairs and zones. They're freely configurable and can be molded into almost any rectangular blocky 3d game world you might want by connecting any of these concepts to others, rooms to rooms, rooms to stairs to rooms, rooms to ramps, rooms within rooms, stairs within rooms that lead to other rooms within rooms, so on. Rooms can have toggleable walls and ceilings, so you can also use them to build outdoor areas. Only floors are necessary. Room might be a bit of a misnomer, but I'm sticking with it, because it makes conceptual sense. Think of it kind of like building a mud, just a lot more spatial, ,3d, and advanced.
* [accessible_tilemap](./accessible_tilemap.md) - an accessible tilemap layer editor. This let's you edit atlas data, define tiles, set physics and other metadata on it, and provides a spreadsheet-style map editor with things such as paint, fill, jumping to specific spots and so on. I have not actually done much 2d work myself in Godot, so this is more untested than other plugins, but I do eventually plan to come back to this. It should work though from the limited testing I have done!
* [accessible_animations](./accessible_animations.md) - an accessible panel for animations. This let's you animate properties, call methods, play sounds, etc. using a timeline. If you're familiar with reaper or other such software, it is very similar to how you might edit automation in those kinds of software using OSARA or whatever. 
* [accessible_audio](./accessible_audio.md) - a small addon which gives you a more accessible version of the mixer. This let's you create and edit buses, assign effects to them, and edit all effect values and move them around and such.
* [accessible_input](./accessible_input.md) - a small plugin to make editing input actions more easily. The default input editor does kinda sorta work, but it is quite annoying. This is easier. 

That's all I got for you for now. I really hope you find any of these useful. If you do, and especially if you make something in Godot using these, let me know about it! I wanna play your games!