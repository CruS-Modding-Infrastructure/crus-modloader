# CRUELTY SQUAD MOD LOADER

**IMPORTANT**: This is just the mod *loader*. For custom map support, in-game mod UI and more install the [CruS Mod Base](https://github.com/crustyrashky/crus-modbase) mod after this.

## Installing the loader

1. Download the [latest release](https://github.com/CruS-Modding-Infrastructure/crus-modloader/releases)
2. Extract the contents of the zip into your Cruelty Squad game folder. You can access this folder from Steam by right clicking the game in your library, then clicking Manage > Browse local files
3. Run `_install_modloader.bat`
4. Start the game, if you now have a `mods` folder under `%appdata%\Godot\app_userdata\Cruelty Squad\` it worked

## Uninstalling the loader

1. Right-click the game in steam
2. Go to Properties > Local Files
3. Verify integrity of game files

## Installing mods

1. Drag/extract mod folder into this directory `%appdata%\Godot\app_userdata\Cruelty Squad\mods`
2. Launch the game
3. If it didn't work, make a post in #modifications in the discord with the contents of `%appdata%\Godot\app_userdata\Cruelty Squad\logs\mods.log`

## Uninstalling mods

1. Remove the mod folder from `%appdata%\Godot\app_userdata\Cruelty Squad\mods`

## Credits

Made for [Cruelty Squad](https://store.steampowered.com/app/1388770/Cruelty_Squad/)

Uses [GodotPckTool](https://github.com/hhyyrylainen/GodotPckTool) to install
