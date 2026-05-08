# accessible_audio

This is a very simple and self explanatory dock plugin which helps make the audio mixer just a little bit more accessible.

## How to use this addon:

This addon will dock itself to the bottom dock bar. You can use the [GMap Hotkeys script](https://github.com/ericrbomb/unseengodot) to focus is directly using a shortcut, or find it by tabbing past the main view of the editor, for example, the accessible_rooms view, script editor, or any other main view that might be enabled. You can also focus the signals panel and shift tab to find the bottom dock tab bar, then right arrow until you hear accessible audio.

## UI

I won't go into too much detail here since the plugin is very self explanatory and I tried to add hints to every control explaining what it does.

You have two tabs. The first tab is the bus tab. This has a list of all the buses that are currently defined in your projects default layout. You can select one to edit it or remove it. The refresh button will force a refresh in case things get out of sync.

You can set the volume of the bus output in DB. Mute will mute the bus entirely, solo solo the bus. Send bus output to, let's you chain buses together. If you've made any changes, press the apply changes button to write the changes back out.

After that are controls to add a new bus, and remove the bus selected. Name is for the name of the new bus to add. Type it in, and press add bus. It will then show up in the list.

Remove selected bus will do what you'd expect. Move bus up and down moves the selected bus up or down in the bus list, and rename will rename the currently selected bus with the name you entered in the name field.

The second tab is the effects tab. This will list all of the effects that are assigned to the bus you have selected in the bus tab. You have a refresh button to sync the list in case things get out of sync.

Then you have controls to select a new type of effect to add, or remove the effect you have selected in the list. Then you have a bypass button to enable or disable the effect you have selected. Move up and down moves the currently selected effect up or down in the list. This is actually useful, since effects apply in order, so you can select whether a sound gets distorted before going into reverb, or whether the reverb itself should be distorted, as an example. 

After that are a whole bunch of controls depending on the effect you have selected here. You can adjust the properties of all effects accessibly.

That's it. It's a very simple plugin but I hope it is still useful. If you have any suggestions, issues, or anything else, either open an issue here, start a discussion, or come find me on the [Unseen Godot Discord Server](https://discord.gg/RmWNjcgHKx)