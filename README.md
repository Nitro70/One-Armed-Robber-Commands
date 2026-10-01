# OAR Commands

Console commands for **One-armed robber**: a `bind` that actually works, `summon <name> [count]`
that works on any map, `dupe` for whatever you are looking at, a real `noclip`, `revive`,
commands that set your cash, level and skills and save them, `selectmap` and `forcemap` to pick
a heist from the console and start it without the ready-up, **command sharing** so friends who
also have the mod can run commands through your game when you host, and reference lists of every
console command, every spawnable object and every Blueprint class in the game.

Every command's values and full code sit in one file, **`config.lua`**, which you can edit and
load again in the running game with `reloadconfig`.

**Download `OAR-Commands-Installer.exe` from the [Releases](../../releases) page.**

> Not affiliated with or endorsed by the makers of One-armed robber. This uses
> [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), a third-party mod loader that runs inside the
> game. Use cheats solo or in lobbies you host where everyone is fine with it. As a client in
> someone else's lobby, cheats only change your own screen, unless the host has the mod too and
> turns on [command sharing](#command-sharing).

## Contents

- [Install](#install)
- [Commands the mod adds](#commands-the-mod-adds)
- [config.lua: change any command](#configlua-change-any-command)
- [Command sharing](#command-sharing)
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
it installed, plus the mod's own folder with your binds and `config.lua`. Other UE4SS mods you
have are left alone. Installing again puts the default `config.lua` back.

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
| `bind <key> "<a> \| <b>"` | Several commands on one key, e.g. `bind f1 "god \| ghost"` |
| `bind` | List your binds |
| `bind <key>` | Show what one key does |
| `unbind <key>` / `unbindall` | Remove one bind / all binds |
| `summon <name> [count]` | Spawn something, e.g. `summon goldbar 10` |
| `spawn <name> [count]` | Same as `summon` |
| `dupe [count]` | Spawn copies of whatever is under your crosshair |
| `summonstop` | Stop summon batches that are still spawning |
| `setmoney <amount>` | Set your cash, e.g. `setmoney 5000000` |
| `addmoney <amount>` | Add cash (a negative amount removes it) |
| `setlevel <level>` | Set your level; XP starts at 0 in that level |
| `setxp <amount>` | Set your XP within the current level (below what it needs to level up) |
| `maxskills` | Every skill owned and researched to its top tier |
| `unlockall` | Every weapon, weapon mod, tool and armor that costs cash |
| `noclip` | Fly through walls: WASD, Space up, Ctrl down, Shift twice as fast; again to land |
| `revive` | Get back up with full health |
| `selectmap [heist]` | Host: pick the heist from the console; with no name, list the heists |
| `forcemap [map]` | Host: start a map now for everyone, with no ready-up and no countdown |
| `commandsharing [0-3]` | Host: let guests with the mod run commands through your game (see [Command sharing](#command-sharing)) |
| `host <command>` | Guest: send any command to the host (for sharing level 3) |
| `reloadconfig` | Load `config.lua` again after you edited it (see [config.lua](#configlua-change-any-command)) |
| `reloadconfig default` | Load the untouched copy, `config.default.lua`, without changing your file |

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

### Cash, level and skills

- Each command changes your own values and then saves them with the game's own save functions
  (`SaveCash`, `SaveLevel`, `AddInventoryItem`). Those write the one thing the game checks when
  it loads a save (that it belongs to your Steam account) and upload to Steam Cloud themselves, so
  the change sticks after a restart and on other PCs.
- Every change is written to `%LOCALAPPDATA%\OAR\Saved\SaveGames\OARCommands-changes.log` with
  the old value (for example `setmoney: cash 1003718128 -> 24000000`), so you can undo it with the
  same command. The saves themselves are not copied: they are named after your SteamID, which UE4SS
  3.0.1 cannot read.
- Cash is capped at 2,000,000,000: the game stores it as a 32-bit number, and the gap keeps a heist
  payout from overflowing it.
- `maxskills` gives you all 17 skills at their top tier (3), including ones you never bought, and
  clears the research queue. Skills you have are raised in place. Skills you don't have are added
  the way the game adds a skill when its research finishes: the skill goes into the research queue
  as finished and the game's own `ProgressSkills` moves it into your skills. Skills apply when your
  character spawns, so they take effect from the next heist. A skill saved above its top tier does
  nothing in the game; `maxskills` repairs that too.
- `unlockall` adds every one of the 254 cash-bought items you don't have, each through the game's
  own `AddInventoryItem`, which saves after every item. With many items missing that takes a few
  seconds; the main menu is the best place to run it.
- Anything added to a list (skills, items) goes through the game's own code. UE4SS 3.0.1 cannot
  grow a list from Lua safely: indexing one past the end does not grow it but still writes there,
  outside the list's memory.
- Coins and everything bought with coins (emotes, most masks and outfits, and the maps sold for
  coins) are never touched. Those live in your Steam Inventory and cost real money.
- `setxp` only takes amounts below what your level needs to level up. More would make the game
  level you up one level at a time on your next XP gain; use `setlevel` to jump levels.
- They work from binds too, e.g. `bind f5 addmoney 100000`.

### Cheat manager

Cheat commands (`summon`, `destroytarget`, `god` and so on) need a cheat manager. The shipping
game only makes one in solo play. The mod creates one whenever it is missing, which also covers
games you host.

### Debug camera

`toggledebugcamera` moves you to a separate debug-camera controller. In a game you host, the engine
gives that controller no cheat manager, so typing `toggledebugcamera` again did nothing and you
were stuck in the free camera. The mod gives the debug camera a cheat manager as it spawns, so the
same command takes you back. Binds also follow you into the debug camera, so a key bound to
`toggledebugcamera` works both ways.

`teleport` moves your character to what your character is aiming at, not to the debug camera, so
it cannot bring you to where the free camera is.

### noclip

- `noclip` turns it on, `noclip` again lands you.
- **Controls:**
  - WASD moves forward, back, left and right, the game's own movement.
  - Space goes up, Ctrl goes down.
  - Hold Shift to go twice as fast.
  - Let go of everything and you stop dead instead of drifting.
- **What it does:** collision off, the engine's flying movement, and your walking speed as the
  normal speed. The game has no up or down input of its own, so the mod adds Space and Ctrl every
  frame from a hook on your character's movement input.
- **Game controls on the same keys:** the game's own jump, crouch and sprint still run. Jumping
  does nothing while flying; the game's crouch may lower your camera while you hold Ctrl.
- **Where Space and Ctrl work:** in heists. In the main menu the character Blueprint may not be
  loaded yet; noclip then still works with WASD and says so.
- **When it ends:** dying or respawning ends it (it belongs to that body). If the game ends
  flying some other way, typing `noclip` turns it back on.
- **In multiplayer:**
  - When you host, everyone sees you fly.
  - As a guest with [command sharing](#command-sharing) on at the host, the host flies your
    character too, including the Shift speed, so it syncs.
  - As a guest without sharing, the host pulls you back, like the built-in `ghost`.

### revive

- `revive` does what the game does when a teammate finishes reviving you: health back to full,
  no longer downed, and your camera colour and look limits restored.
- If you were not downed it just refills your health.
- It has to run on the host (the host decides who is downed): it does when you host or play solo,
  and as a guest it goes through [command sharing](#command-sharing).

### selectmap and forcemap

Both are for the host (or solo play).

- **`selectmap`** lists the heists with their short names and marks the selected one.
- **`selectmap <heist>`** picks the heist, the same way the map screen does. Everyone sees the
  new heist in the lobby, readies up, and the countdown runs as usual.
- **`forcemap <map>`** picks it and starts it at once for everyone: no ready-up, no countdown.
- **`forcemap`** alone starts the heist that is already selected.

```
selectmap museum
forcemap data center
```

- **Names:** the short name from the list (`datacenter`), the heist's title (`data center`) or
  its map file (`map_aidatacenter`). A unique start is enough (`forcemap muse`).
- **Other maps:** `forcemap` also takes every other map file in the game, for example
  `forcemap testmap`, `forcemap tutorial_loud` or `forcemap mainmenu` (back to the lobby). Their
  names are in the command list. Test and demo maps are unfinished; expect some to be empty.
- **From inside a heist:** `forcemap <map>` goes straight to the other map with everyone.
  `selectmap` needs the lobby.
- **Heists sold for coins** are only picked or started when the game itself counts them as
  yours (in your Steam inventory, the same test the map screen uses). `selectmap` shows which
  ones those are. Level requirements are not checked.
- **How it works:**
  - In the lobby the host's menu starts a heist by waiting until everyone is ready, counting
    down, and then running its own start function, which closes the lobby to new players and
    travels with `servertravel`.
  - `forcemap` marks every lobby player as ready on the host and calls that same function, so
    the game's own start runs without the wait.
  - Outside the lobby it uses `servertravel` directly, the command the game itself uses to bring
    everyone back to the lobby after a heist.
- Guests cannot use them, and [command sharing](#command-sharing) never passes them to the host.

## config.lua: change any command

Everything the mod's commands do is written in one file you can edit:

```
OAR\Binaries\Win64\Mods\OARCommands\config.lua
```

It is not a list of simple switches. It is the mod itself, in Lua:

1. **Values at the top.** One table, `V`, with the numbers, keys, lists and names the commands
   use. For example:
   - `SummonDelayMs` and `SummonMax`: how fast and how many `summon` spawns;
   - `NoclipKeysUp`, `NoclipKeysDown`, `NoclipKeysFast`, `NoclipFastMultiplier`, `NoclipSpeed`;
   - `MaxCashAndLevel`: the cap for `setmoney` and `setlevel`;
   - `ShareLevelAtStart`, `ShareTimeoutMs`, and the lists of what each sharing level allows
     and what is always blocked;
   - `KeyAliases`: extra spellings for keys in `bind`.
2. **The complete code of every command below that**, one section each, with the explanation of
   how it works: `bind`, `summon`, `dupe`, the value commands, `noclip`, `revive`, `selectmap`,
   `forcemap`, command sharing and the debug camera fix. Change it, remove it, or add your own
   command with `Core.Command("name", function(FullCommand, Parameters, Ar) ... return true end)`.

After saving, type **`reloadconfig`** in the console. The change applies at once, with no
restart.

- **Mistakes are safe to make.**
  - If the file has an error, `reloadconfig` prints the error with its line number and the
    commands that were loaded before keep working.
  - If one command fails while it runs, the console shows `<command> failed: <error>`.
  - If the file is already broken when the game starts, only `reloadconfig` exists until you fix
    it.
- **Going back to the default:**
  - `reloadconfig default` loads `config.default.lua`, the untouched copy next to your file,
    until the next `reloadconfig` or restart. Your file is not changed.
  - To reset for good, copy `config.default.lua` over `config.lua`, or uninstall and install
    again: uninstalling removes `config.lua`, installing writes the default.
- **Updates:** a newer OAR Commands keeps your edited `config.lua` when its default config did
  not change. When the default did change, your file is saved as `config.old.lua` and the new
  default is installed, because the config holds the commands' code and an old one would miss
  what the new version added. Copy your changes over from `config.old.lua`.
- **What survives `reloadconfig`:** your binds, the command sharing level, noclip, and running
  summon batches. A game restart resets everything except the binds.
- **The name tables** are separate files in `Mods\OARCommands\Scripts` and are read again on
  every `reloadconfig` too: `spawnables.lua` (`summon`), `unlockables.lua` (`maxskills`,
  `unlockall`) and `maps.lua` (`selectmap`, `forcemap`).
- **`Scripts\main.lua`** is only the loader: it registers each command, key and hook with UE4SS
  once and looks up the current code from `config.lua` every time one runs. UE4SS cannot take a
  registration back, which is why they live there and not in the config.
- The top of `config.lua` lists what the loader offers (`Core.Command`, `Core.Hook`,
  `Core.KeyBind`, `Core.State`...) and the UE4SS 3.0.1 limits worth knowing before changing
  code. The commands that change your save go through the game's own save functions; keep it
  that way.

## Command sharing

When you host and your friends also have OAR Commands, you can let them run commands through your
game, where they actually take effect for everyone. It is off every time the game starts.

```
commandsharing 1
```

| Level | What guests can run through the host |
|---|---|
| `0` | Nothing (off). This is the setting after every game start. |
| `1` | Player commands: `summon`, `spawn`, `summonstop`, `dupe`, `revive`, `noclip`, `god`, `ghost`, `fly`, `walk`, `teleport`, `destroytarget` |
| `2` | Level 1 plus world commands: `destroyall`, `slomo`, `playersonly`, `changesize` |
| `3` | Any console command except the block list below (guests use `host <command>` for commands the mod does not know) |

`commandsharing` with no number shows the current level. Only the host's setting counts.

**Always blocked**, at every level:

- **Anything that would close, move or cut off your game:** `exit`, `quit`, `open`, `travel`,
  `servertravel`, `disconnect`, `reconnect`, `switchlevel`, `restartlevel`, `streammap`,
  `demoplay`, `demorec`, `selectmap`, `forcemap`.
- **Anything that touches your files or crashes the game:** `exec`, `deletecloudfiles`,
  `DoubleFreeFinderCrash`, `MallocFrameProfiler`, `purchase`, `debug`.
- **The mod's commands that stay on each player's own game and save:** `setmoney`, `addmoney`,
  `setlevel`, `setxp`, `maxskills`, `unlockall`, `bind`, `unbind`, `unbindall`,
  `commandsharing`, `host`, `reloadconfig`.

**What runs where.** A guest's command runs as that guest, on the host's game:

- `summon` and `spawn` put things in front of the **guest**.
- `god`, `ghost`, `walk`, `revive` and `noclip` act on the **guest's** character.
- `destroytarget`, `dupe` and `teleport` act on what the **guest** is looking at: the guest's mod
  sends its exact camera position and angle, and the host's mod aims from there.
  `destroytarget` from a guest leaves other players alone.
- The host's own commands are unchanged: when you (the host) type `destroytarget`, it destroys
  what **you** are looking at.

The host's console shows every guest command, for example `[OAR] Friend ran: summon goldbar 5`.
The guest sees the host's answer, for example `[OAR host] ... ok Summoning Goldbar_C x5`.

**Failsafe.** A command only goes to the host when you are a guest. It runs on your own game
exactly as it would without this feature when:

- you play solo or you are the host;
- the host has sharing at `0`, or at a level that does not include the command;
- the host does not have the mod, or does not answer within 1.5 seconds. After a host stays
  silent, commands run on your game straight away for the next minute.

If sharing ever stops working, commands simply behave as they did before it existed.

**How it works.**

- **Guest to host:** the engine has a client-to-server call, `PlayerController.ServerExecRPC`, that
  this shipping build accepts and then ignores (its check always passes and its body is empty). A
  guest's mod sends `oar1 <id> <command>` through it, and only the host's mod reads it.
- **Host to guest:** the reply comes back with `ClientMessage`, which also prints it in the guest's
  console.
- **The full design:** [docs/design/2026-09-30-command-sharing-noclip-revive.md](docs/design/2026-09-30-command-sharing-noclip-revive.md).

Both players need OAR Commands installed. Guests without the mod are not affected at all.

## Game commands that work

Short list; the full, verified list is in
[lists/OAR_Working_Commands.txt](lists/OAR_Working_Commands.txt).

| Command | What it does |
|---|---|
| `god` | Invincible |
| `ghost` / `walk` | Walk through walls at your current height / back to normal (see `fly` below) |
| `teleport` | Go to where you are aiming |
| `slomo 0.3` | Slow motion (`slomo 1` is normal) |
| `destroytarget` | Delete what you are looking at |
| `destroyall <Class>` | Delete every object of a class, e.g. `destroyall NPC_Police_base_C` (police only exist after the alarm; guards are `NPC_Guard_C`) |
| `playersonly` | Freeze all AI and physics (again to unfreeze) |
| `toggledebugcamera` | Free camera (again to exit) |
| `changesize 3` | Giant (`changesize 1` is normal) |
| `stat fps` | FPS counter |
| `open <map>` | Load a map in solo play; the map names are in the command list |

Cheats only really apply when you host or play solo. As a client the server overrides you,
unless the host shares commands with you (see [Command sharing](#command-sharing)).

`fly` prints "You feel much lighter" but barely changes anything in this game. It switches your
character to the engine's flying movement, which only turns gravity off. One-armed robber moves
you along your body's forward and right directions, which are always level, and has no up or
down input, so you cannot climb: you hover at the height you were at, and walking off a ledge
leaves you floating instead of falling. Jumping does nothing while flying. `ghost` is the same
plus no collision, so it lets you walk through walls at your current height. `walk` turns both
off.

Worth knowing from the full list:

- `deletecloudfiles` exists and deletes Steam Cloud files. This game keeps progress in Steam Cloud.
  Do not run it.
- `DoubleFreeFinderCrash` crashes the game on purpose.
- `obj`, `ke`, `help` and the debug view modes are not compiled into this build.

## What the installer changes

Everything goes into `OAR\Binaries\Win64`. The game's own exe and pak files are never modified.

- **UE4SS 3.0.1**: `dwmapi.dll`, `UE4SS.dll`, `UE4SS-settings.ini`, `UE4SS-LICENSE.txt` and the
  stock `Mods` folder.
- **`Mods\OARCommands`**: this project's mod:
  - `config.lua`, the values and the code of every command (see
    [config.lua](#configlua-change-any-command)), and `config.default.lua`, its untouched copy;
  - `Scripts\main.lua`, the loader;
  - `Scripts\spawnables.lua`, the name table for `summon`;
  - `Scripts\unlockables.lua`, the skills and cash items for `maxskills` and `unlockall`;
  - `Scripts\maps.lua`, the heists and map files for `selectmap` and `forcemap`;
  - `binds.txt`, your binds, once you make one.
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
(Unreal Engine 4.27 shipping build from 23 August 2026, game files from the Data Center heist
update of 1 October 2026, which left the exe unchanged).

| File | What is in it |
|---|---|
| [OAR_Working_Commands.txt](lists/OAR_Working_Commands.txt) | Every cheat and exec command with its parameters, every engine text command compiled into the exe (161 words, grouped, with a do-not-use section), handy settings, all 353 console commands and all 2,976 console variables, the maps in the game (including unreleased test maps like `CheatLevel` and `Map_NewsStation`) |
| [OAR_Spawn_Commands.txt](lists/OAR_Spawn_Commands.txt) | All 1,058 spawnable Blueprints as `summon` lines, grouped: loot, tools, explosives, NPCs, police gear, vehicles, casino props, security and heist objects, guns, attachments, cosmetics, shop displays, buildings |
| [OAR_Full_Object_List.txt](lists/OAR_Full_Object_List.txt) | All 1,283 Blueprint classes with parent classes, components, variables and functions (with parameters and Server/Client/Multicast markers), which maps each class is placed on, what every map contains, and the game's structs |
| [OAR_All_Assets.txt](lists/OAR_All_Assets.txt) | All 15,809 assets in the game, grouped by type |

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
python tools/make_unlockables.py   # mod/Mods/OARCommands/Scripts/unlockables.lua
python tools/make_maps.py          # mod/Mods/OARCommands/Scripts/maps.lua
```

After a game update, run all five again: new heists, loot and items then show up in the lists,
in `summon` and in `selectmap`.

- `make_unlockables.py` reads each shop item's and skill's default values (`CashCost`,
  `CoinCost`, `SteamItemDefID`, `SkillComponent`) from the pak and refuses to write a table that
  contains anything with a coin price or a Steam item ID.
- `make_maps.py` reads the lobby's heist entries (title, map file, coin price, Steam item ID)
  and lists every other map file in the pak. A heist sold for coins is never put in the plain
  map list, so `forcemap` always checks that you own it.

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
