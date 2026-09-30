# OAR Commands

Console commands for **One-armed robber**: a `bind` that actually works, `summon <name> [count]`
that works on any map, `dupe` for whatever you are looking at, and reference lists of every
console command, every spawnable object and every Blueprint class in the game.

**Download `OAR-Commands-Installer.exe` from the [Releases](../../releases) page.**

> Not affiliated with or endorsed by the makers of One-armed robber. This uses
> [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), a third-party mod loader that runs inside the
> game. Use cheats solo or in lobbies you host where everyone is fine with it. As a client in
> someone else's lobby, cheats only change your own screen.

## Contents

- [Install](#install)
- [Commands the mod adds](#commands-the-mod-adds)
- [Game commands that work](#game-commands-that-work)
- [What the installer changes](#what-the-installer-changes)
- [Reference lists](#reference-lists)
- [Tools](#tools)
- [Building](#building)
- [Credits and license](#credits-and-license)

## Install

1. Close One-armed robber.
2. Run `OAR-Commands-Installer.exe`. It finds the game through Steam. If it cannot, click
   **Browse** and pick the game folder (the one with `OAR.exe`).
3. Click **Install / Update**. It takes about a second.
4. Start the game and press **~** to open the console.

To remove everything, run the installer again and click **Uninstall**. It deletes only the files
it installed. Other UE4SS mods you have are left alone.

Notes:

- The exe needs nothing extra: it is a .NET Framework 4.8 program, which Windows 10 and 11
  already have. UE4SS and the mod are packed inside it, so it works offline.
- It is not code-signed, so Windows SmartScreen may warn. Click **More info**, then **Run anyway**.
- Some antivirus programs flag UE4SS's `dwmapi.dll`, because it loads code into the game. It is
  the file from the official UE4SS 3.0.1 release (zip SHA-256
  `4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec`).
- It asks for admin rights only if the game folder is not writable (for example a Steam library
  under Program Files).
- If you used the earlier `BindCommand` version, installing moves your saved binds over.
- If the game ever fails to start, delete `dwmapi.dll` from `OAR\Binaries\Win64`. That turns UE4SS
  off completely.

## Commands the mod adds

| Command | What it does |
|---|---|
| `bind <key> <command>` | Put a command on a key, e.g. `bind x destroytarget` |
| `bind <key> "<a> \| <b>"` | Several commands on one key, e.g. `bind f1 "god \| fly"` |
| `bind` | List your binds |
| `bind <key>` | Show what one key does |
| `unbind <key>` / `unbindall` | Remove one bind / all binds |
| `summon <name> [count]` | Spawn something, e.g. `summon goldbar 10` |
| `spawn <name> [count]` | Same as `summon` |
| `dupe [count]` | Spawn copies of whatever is under your crosshair |
| `summonstop` | Stop summon batches that are still spawning |

### bind

- Binds are saved in `OAR\Binaries\Win64\Mods\OARCommands\binds.txt` and come back every time you
  start the game.
- A bind only fires when the key actually reaches the game, so typing in the console or a chat
  box does not trigger it.
- Keys: letters, `f1` to `f24`, digits `0` to `9`, `numpad0` to `numpad9`, `space`, `enter`,
  `tab`, `esc`, `up` `down` `left` `right`, `mouse4`, `mouse5`, and the rest of UE4SS's key names
  (for example `PAGE_UP`, `OEM_THREE`).
- The game's own `SetBind` is compiled out of the shipping build: it saves binds but never runs them.

### summon

- Loads the object first, so it works on any map, not just the one it belongs to. The game's
  own `summon` only finds objects that are already loaded and needs the exact class name.
- Names are forgiving, checked in this order:
  1. the exact name, with or without `_C`, any capitals: `goldbar`, `Goldbar_C`
  2. a unique start of a name: `duffel` finds `Duffelbag_C`
  3. a unique part of a name: `rocketlauncher` finds `BP_Valuable_Rocketlauncher_C`
  4. a full path: `/Game/BP/Items/Valuables/Goldbar.Goldbar_C`
  5. if several things match (`summon valuable_wine`), it lists them and spawns nothing
  6. names it does not know go straight to the engine, so `summon PointLight` still works
- `count` spawns that many copies 0.15 seconds apart (at most 500 per command).
- Everything spawns about 1.5 m in front of you, facing where you look.
- Every name is in [lists/OAR_Spawn_Commands.txt](lists/OAR_Spawn_Commands.txt).

### dupe

- Traces from your camera to whatever is under the crosshair and summons more of that object's
  type, by its full path, so objects that share a short name cannot get mixed up.
- It copies the type, not that exact object: a duplicated gold bar gets a fresh value like any
  newly spawned one.
- Plain level geometry (walls and floors that are just part of the map) is refused rather than
  spawning an empty object.

### Cheat manager

Cheat commands (`summon`, `destroytarget`, `god` and so on) need a cheat manager. The shipping
game only makes one in solo play. The mod creates one whenever it is missing, which also covers
games you host.

## Game commands that work

Short list; the full, verified list is in
[lists/OAR_Working_Commands.txt](lists/OAR_Working_Commands.txt).

| Command | What it does |
|---|---|
| `god` | Invincible |
| `ghost` / `fly` / `walk` | Noclip / fly / back to normal |
| `teleport` | Go to where you are aiming |
| `slomo 0.3` | Slow motion (`slomo 1` is normal) |
| `destroytarget` | Delete what you are looking at |
| `destroyall <Class>` | Delete every object of a class, e.g. `destroyall NPC_Police_base_C` (police only exist after the alarm; guards are `NPC_Guard_C`) |
| `playersonly` | Freeze all AI and physics (again to unfreeze) |
| `toggledebugcamera` | Free camera (again to exit) |
| `changesize 3` | Giant (`changesize 1` is normal) |
| `stat fps` | FPS counter |
| `open <map>` | Load a map in solo play; the map names are in the command list |

Cheats only really apply when you host or play solo. As a client the server overrides you.

Worth knowing from the full list:

- `deletecloudfiles` exists and deletes Steam Cloud files. This game keeps progress in Steam Cloud.
  Do not run it.
- `DoubleFreeFinderCrash` crashes the game on purpose.
- `obj`, `ke`, `help` and the debug view modes are not compiled into this build.

## What the installer changes

Everything goes into `OAR\Binaries\Win64`. The game's own exe and pak files are never modified.

- **UE4SS 3.0.1**: `dwmapi.dll`, `UE4SS.dll`, `UE4SS-settings.ini`, `UE4SS-LICENSE.txt` and the
  stock `Mods` folder.
- **`Mods\OARCommands`**: this project's mod (`main.lua` and `spawnables.lua`, the name table for
  `summon`).
- **Console key stays on ~**: stock UE4SS's `ConsoleEnablerMod` moves the console to F10. The
  installed copy keeps it on the tilde key.
- **`mods.txt` without a byte-order mark**: the stock UE4SS 3.0.1 `mods.txt` starts with an
  invisible byte-order mark, which makes UE4SS skip the first mod in the list,
  `CheatManagerEnablerMod`. Without it no cheat manager exists and every cheat silently does
  nothing. The installer writes the file without it and keeps any other mods you listed.
- **`ConsoleCommandsMod`**: its `summon_unloaded_assets` handler is switched off, because the
  mod's `summon` replaces it (and handles counts and friendly names).
- `Mods\OARCommands\installed-files.txt` records what was installed, so uninstall removes exactly
  that.

## Reference lists

All four were generated from the game's files and apply to anyone's copy of the game
(Unreal Engine 4.27 shipping build from 23 August 2026).

| File | What is in it |
|---|---|
| [OAR_Working_Commands.txt](lists/OAR_Working_Commands.txt) | Every cheat and exec command with its parameters, every engine text command compiled into the exe (161 words, grouped, with a do-not-use section), handy settings, all 353 console commands and all 2,976 console variables, the maps in the game (including unreleased test maps like `CheatLevel` and `Map_NewsStation`) |
| [OAR_Spawn_Commands.txt](lists/OAR_Spawn_Commands.txt) | All 1,052 spawnable Blueprints as `summon` lines, grouped: loot, tools, explosives, NPCs, police gear, vehicles, casino props, security and heist objects, guns, attachments, cosmetics, shop displays, buildings |
| [OAR_Full_Object_List.txt](lists/OAR_Full_Object_List.txt) | All 1,277 Blueprint classes with parent classes, components, variables and functions (with parameters and Server/Client/Multicast markers), which maps each class is placed on, what every map contains, and the game's structs |
| [OAR_All_Assets.txt](lists/OAR_All_Assets.txt) | All 15,741 assets in the game, grouped by type |

How "works" was decided for the command list:

- Each cheat function's machine code was read in a running copy of the game. Only 8 are empty
  stubs in this build, and those are listed as not working.
- Engine text commands were taken from the exe: every word it passes to the engine's command
  parser (`FParse::Command`).
- Console variables and commands come from a UE4SS/UUU dump, minus the one cheat-flagged
  variable the shipping build blocks.

## Tools

The Python scripts in `tools/` produced the lists and the mod's name table. They run on Windows
with the game installed and read its files; nothing in the game is changed.

```
pip install -r requirements.txt
python tools/oar_objects.py        # lists/OAR_Full_Object_List.txt and OAR_All_Assets.txt
python tools/build_lists.py        # lists/OAR_Working_Commands.txt and OAR_Spawn_Commands.txt
python tools/make_spawnables.py    # mod/Mods/OARCommands/Scripts/spawnables.lua
```

- The game folder is found through Steam. Set `OAR_GAME_DIR` to override it.
- `build_lists.py` also needs a UUU object and console variable dump (`UUU_ObjectsDump.txt`,
  `UUU_CVarsDump.json`) in `OAR\Binaries\Win64`, for the engine's own classes and settings.
- `oar_pak.py` reads the game's pak (v11). Zlib entries use Python's zlib. Oodle entries use the
  Oodle decoder that is built into the game's own exe: the exe is mapped into the Python process
  (never into the running game) and its decoder is called directly. Its address
  (`OODLE_DECOMPRESS_RVA`) belongs to the 23 August 2026 build and may move after a game update.
- `oar_registry.py` reads the cooked asset registry, `oar_package.py` reads cooked packages
  (classes, functions, properties), `oar_exe_commands.py` pulls the engine's command words out of
  the exe.

## Building

The installer (needs Python 3 and the .NET SDK 6 or newer):

```
python tools/make_payload.py
cd installer
dotnet build -c Release
```

`make_payload.py` downloads the official UE4SS 3.0.1 zip once (checked against its SHA-256),
lays `mod/` over it and writes `build/payload.zip`, which the installer embeds. The result is
`dist/OAR-Commands-Installer.exe`.

Tests:

```
python tools/test_oarcommands.py      # the Lua mod against stubbed UE4SS functions (needs lupa)
cd installer && dotnet build -c Debug && cd ..
python tools/test_installer.py        # the installer against fake game folders
```

## Credits and license

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) by the UE4SS team, MIT license
  ([third_party/UE4SS-LICENSE.txt](third_party/UE4SS-LICENSE.txt)). The installer bundles an
  unmodified UE4SS 3.0.1 plus small edits to two of its stock Lua mods, described above.
- The original object and console variable dumps were made with UUU (Universal Unreal Engine
  Unlocker) by Otis_Inf.
- This project: MIT license, see [LICENSE](LICENSE).
