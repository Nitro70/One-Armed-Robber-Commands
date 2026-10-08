# OAR Commands

Console commands for **One-armed robber**: a `bind` that actually works, `summon <name> [count]`
that works on any map and knows every different object (not just `artwork`, but `mona lisa`,
`artwork nefertiti` or `vault keycard`), `dupe` that copies whatever you are looking at with its
look and values, a real `noclip`, `revive`,
commands that set your cash, level and skills and save them, `selectmap` and `forcemap` to pick
a heist from the console and start it without the ready-up, **command sharing** so friends who
also have the mod can run commands through your game when you host, and reference lists of every
console command, every spawnable object and every Blueprint class in the game.

Every command's values and full code sit in one file, **`config.lua`**, which you can edit and
load again in the running game with `reloadconfig`. **`opengui`** opens an in-game menu with all
of it on tabs, including a searchable list of everything you can spawn.

**Download an installer from the [Releases](../../releases) page:**

- **`OAR-Commands-Online-Installer.exe`**: downloads the newest version from GitHub every time
  you click Install / Update, so you keep this one exe and never download an installer again.
- **`OAR-Commands-Offline-Installer.exe`**: has its version built in and needs no internet.

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
2. Run the installer. It finds the game through Steam. If it cannot, click **Browse** and pick
   the game folder (the one with `OAR.exe`).
3. Click **Install / Update**. The offline installer takes about a second; the online one first
   downloads the newest release (about 6 MB) from GitHub.
4. Start the game and press **~** to open the console.

To remove everything, run the installer again and click **Uninstall**. It deletes only the files
it installed, plus the mod's own folder with your binds and `config.lua`. Other UE4SS mods you
have are left alone. Installing again puts the default `config.lua` back.

Notes:

- The exe needs nothing extra: it is a .NET Framework 4.8 program, which Windows 10 and 11
  already have. The offline installer has UE4SS and the mod packed inside it. The online
  installer downloads the same files (`OAR-Commands-Payload.zip`) from the latest release at
  every Install / Update and checks them against the release's SHA-256
  (`OAR-Commands-Payload.zip.sha256`) before it changes anything; Uninstall needs no internet.
- When you play together, everyone should have the same version: as a guest, the host's copy of
  the mod runs the world commands. The online installer is the easy way to stay current.
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
| `opengui` | Open the in-game menu; again to close it (see [The menu](#the-menu-opengui)). `bind f1 opengui` puts it on F1 |
| `esp` / `esp on` / `esp off` | Mark guards, police and players through walls (see [ESP](#esp)). `bind f2 esp` puts it on F2 |
| `bind <key> <command>` | Put a command on a key, e.g. `bind x destroytarget` |
| `bind <key> "<a> \| <b>"` | Several commands on one key, e.g. `bind f1 "god \| ghost"` |
| `bind` | List your binds |
| `bind <key>` | Show what one key does |
| `unbind <key>` / `unbindall` | Remove one bind / all binds |
| `summon <name> [count]` | Spawn something, e.g. `summon goldbar 10` or `summon mona lisa` |
| `spawn <name> [count]` | Same as `summon` |
| `dupe [count]` | Spawn copies of whatever is under your crosshair, with its look and values |
| `summonstop` | Stop summon batches that are still spawning |
| `setmoney <amount>` | Set your cash, e.g. `setmoney 5000000` |
| `addmoney <amount>` | Add cash (a negative amount removes it) |
| `setlevel <level>` | Set your level; XP starts at 0 in that level |
| `setxp <amount>` | Set your XP within the current level (below what it needs to level up) |
| `setxp all <amount>` | Host, during a heist: every player gains that much XP on the win screen |
| `maxskills` | Every skill owned and researched to its top tier |
| `unlockall` | Every weapon, weapon mod, tool and armor that costs cash |
| `setammo <amount>` | Every gun you carry gets that much spare ammo, the one in your hand a full magazine |
| `truckmoney` | Show the money in the getaway truck |
| `truckmoney set <amount>` / `add <amount>` / `reset` | Host, during a heist: put exactly that much in the truck / add to it / back to 0 |
| `infiniteammo` | Your magazine refills after every shot; again to turn it off |
| `reviveall` | Host: revive every downed player |
| `healall` | Host: everyone back to full health and armor |
| `godall [on\|off]` | Host: nobody takes damage |
| `alarm [off\|on\|trigger]` | Show the alarm; host: `off` uses the alarm box, `on` switches it back on, `trigger` makes it go off |
| `cops [wave\|specials\|clear]` | Show the police; host: send a wave, a special wave, or remove all police |
| `cameras [off\|destroy]` | Show the security cameras; host: `off` removes them all (guards do not notice), `destroy` breaks them as shooting does |
| `codes [open]` | Every keypad's code, nearest first; host: `codes open` unlocks them all |
| `bringloot` | Host: every loose valuable into the getaway truck |
| `escape` | Host: win the heist now with what is in the truck, nobody has to be in it |
| `doors` | How many doors are locked and open, and whether the vault is open |
| `doors unlock` / `doors unlock all` | Host: unlock the door you are looking at / every door; they stay shut |
| `doors open [all]` / `doors close [all]` | Host: open or close the door you are looking at / every door |
| `doors lock` / `doors lock all` | Host: lock the door you are looking at / every door again, closing it first |
| `doors vault open` | Host: open the vault. It cannot be closed again (the game has no way to) |
| `guards` | How many guards are alive, alert and down, and the phones ringing |
| `guards kill [all]` | Host: kill the guard you are looking at / every guard, as if shot (a phone rings unless they were alert) |
| `guards remove [all]` | Host: take the guard you are looking at / every guard and body out of the heist (no body, no phone) |
| `guards phones answer` / `remove` | Host: answer every ringing guard phone as a scanner does (no alarm) / take the phones away |
| `noclip` | Fly through walls: WASD, Space up, Ctrl down, Shift twice as fast; again to land |
| `notarget` | Guards, cameras and civilians ignore you (only you); again to turn it off |
| `civilians` / `civilians tie [all]` | Host: tie up the civilian you look at, or every civilian, the game's way |
| `civilians kill [all]` / `civilians remove [all]` | Host: kill (counts as a civilian killed) or remove the civilian you look at, or all |
| `revive` | Get back up with full health |
| `selectmap [heist]` | Host: pick the heist from the console; with no name, list the heists |
| `forcemap [map]` | Host: start a map now for everyone, with no ready-up and no countdown |
| `commandsharing [0-3]` | Host: let guests with the mod run commands through your game (see [Command sharing](#command-sharing)) |
| `host <command>` | Guest: send any command to the host (for sharing level 3) |
| `reloadconfig` | Load `config.lua` again after you edited it (see [config.lua](#configlua-change-any-command)) |
| `reloadconfig default` | Load the untouched copy, `config.default.lua`, without changing your file |

### The menu (opengui)

`opengui` opens a window inside the game (**One-Armed-Menu**); type it again, press your key for
it, Escape or the X at the top to close it. To put it on a key: `bind f1 opengui`. It works in
heists and in the lobby.

- **Tabs** on the left, each with only its own commands, in groups: **Player** (noclip, ghost,
  fly, teleport, revive, god mode, ammo, copy or delete what you look at), **Spawn**, **Heist**
  (alarm, cameras, keypads, police, guards and their phones, the team, XP for everyone, truck
  money, loot, escape),
  **Doors** (the door you look at, every door, the vault), **ESP** (see [ESP](#esp)), **Progress** (cash, level, XP, skills,
  gear), **World** (game speed, size, freeze, free camera, FPS), **Lobby** (pick or start a
  heist), **Binds**, **Settings** and, with Advanced on, **Code**.
- **Settings**: your own settings, saved in `settings.lua` next to `config.lua` so they stay after
  a restart (and after an update). Change the boxes, then **Save and apply**; **Default** on a
  line puts that one back, **Reset everything** all of them.
  - **Commands**: noclip speed and noclip speed while holding Shift, the time between spawned
    copies, the most copies one spawn makes, the most spare ammo `setammo` gives, how close to a
    door or a guard you must aim, the command sharing level every game starts with, and two switches
    (revives finishing with the bar, guests seeing the look of copies).
  - **Menu look**: an accent colour (six calm presets), every colour of the window typed as
    `#rrggbb` with a sample next to it, the title and its font, every text size, the window's
    normal size, the tab list and line widths, how dark the game gets behind the window, filled or
    outlined buttons, a filled or barred tab highlight, and animations on or off. The defaults
    are the look the menu comes with; anyone can make it their own.
  - Also there: command sharing, putting the window back in the middle, and reloading
    `config.lua`.
- Only one menu window is ever open: opening it takes any other one off the screen (one left
  over from before a `reloadconfig` or from the free camera, for example).
- **Binds**: type a key and a command and press **Bind it** (or pick one of the ideas), change or
  remove any of your binds. The same binds as the `bind` command, saved in `binds.txt`.
- **Code** (only with **Advanced** on): `config.lua` editable in the menu. **Full file** at the
  top opens all of it; below it, every part (one per command or group of commands) A to Z, with
  the commands a part makes named next to its title (the search box finds a part by a command in
  it too). Nothing is left out: a part is the lines between two of the file's title comments, so a
  command can also use values at the top of the file and helpers in "Things several commands
  use". **Find** finds any text (any case) in the open part or the full file, also in your
  unsaved edits: it marks the line, scrolls to it and says "2 of 5, line 340"; **Next** and
  **Previous** go round the places. **Check** looks for mistakes, **Save and reload** writes
  `config.lua` and loads it at once, **Undo changes** goes back to the file. An edit with a typo is
  not saved, and one that fails when it runs is taken back out again, so `config.lua` stays
  working. Before the first save of a game session your file is copied to `config.backup.lua`.
  Values saved in **Settings** win over the same values in the file.
- **Spawn** lists everything `summon` knows, in groups that open and close with a click
  (Valuables, Tools and items, Guns, Gun attachments, Armor and explosives, Police and people,
  Heist gear, Props). Click a name to spawn it in front of you; **How many** sets the count.
  Each name shows its class name on the right.
- **Search all items** at the top of the Spawn tab searches every group, also the advanced ones,
  as you type: every word you type must be somewhere in a name, its class name, its path or its
  group, in any order (`bar gold` finds Gold bar, `valuables goldbar_c` too).
- **Search** in the title bar does the same for the tab you are on (also in closed groups).
- **Move it** by dragging the title bar, and **resize it** with the grip in the bottom right
  corner. It stays where you put it, at that size, until the game closes (it is not saved to a
  file); Settings > **Back to normal** puts it back in the middle.
- **Advanced** shows the rarely used spawn groups (player gear, building pieces, menu scenery),
  the other map files, and the console line each button runs. **Full names** shows class and
  object names (what you would type) instead of readable names.
- Lines with an amount box use what you type there (`setammo 999`, `truckmoney set 1000000`...).
  Buttons that cannot be undone (open the vault, set off the alarm, escape, start a heist) ask
  first: click them twice.
- Results show at the bottom of the window, including the host's answers when you are a guest.
- Every button runs the same command as the console, so it behaves exactly as typing it: as a
  guest, host commands go to the host through command sharing.
- While the menu is open the game gets no keys or mouse (they go to the menu), so you do not walk
  or shoot while clicking. Other binds do nothing then; only your `opengui` key works, to close it.
- The game clears the screen when a map loads, when you die and on the win screen; the menu then
  closes by itself and gives the game its keys back.
- It fades in and out, the window slides into place, a new tab's lines fade in, and the list
  scrolls smoothly. These only run for a fraction of a second, so they cost nothing while you
  play (`animate = false` in `Menu = {}` turns them off).
- What the menu shows is in the `opengui` section at the end of `config.lua` (`MenuTabs`), and
  its colours and sizes in `Menu = {}` at the top (any value of `Kit.DefaultStyle` in
  `Scripts\gui.lua`, which builds the window).

### bind

- Binds are saved in `OAR\Binaries\Win64\Mods\OARCommands\binds.txt` and come back every time you
  start the game.
- A bind only fires when the key actually reaches the game, so typing in the console or a chat
  box does not trigger it.
- The usual keys (letters, digits, F1 to F24, the numpad, arrows, mouse 3 to 5...) are watched from
  the start, so a new bind made in the middle of a game is only a change of its command.
- Keys: letters, `f1` to `f24`, digits `0` to `9`, `numpad0` to `numpad9`, `space`, `enter`,
  `tab`, `esc`, `up` `down` `left` `right`, `mouse4`, `mouse5`, and the rest of UE4SS's key names
  (for example `PAGE_UP`, `OEM_THREE`).
- The game's own `SetBind` is compiled out of the shipping build: it saves binds but never runs them.

### summon

- Loads the object first, so it works on any map, not just the one it belongs to. The game's
  own `summon` only finds objects that are already loaded and needs the exact class name.
- **Three kinds of names**, all in [lists/OAR_Spawn_Commands.txt](lists/OAR_Spawn_Commands.txt):
  - **A class:** `goldbar`, `Goldbar_C`, `statue_museum`.
  - **An object:** one class with its own look and values. Every Artwork in the game is the
    class `Statue_museum_C`; what makes one a painting and another a statue is the mesh,
    material, size and value it was placed with. Each different one has its own name:
    `mona lisa`, `artwork nefertiti`, `artwork icarus`, `vault keycard`, `cash money roll`...
    The mod spawns the class and then puts that data on the copy.
  - **An item's in-game name** (the text you see when you look at it): `artwork`, `gold bar`,
    `training data`. That is the plain class with its default look.
- Names are forgiving. Capitals, spaces and underscores do not matter (`summon gold bar` is
  `summon goldbar`), and they are checked in this order:
  1. the exact name: `goldbar`, `Goldbar_C`, `mona lisa`
  2. a unique start of a class name: `duffel` finds `Duffelbag_C`
  3. a unique start of an object name: `mona` finds `mona_lisa`
  4. a unique part of a name: `rocketlauncher` finds `BP_Valuable_Rocketlauncher_C`
  5. a full path: `/Game/BP/Items/Valuables/Goldbar.Goldbar_C`
  6. if several things match (`summon artw`), it lists them and spawns nothing
  7. names it does not know go straight to the engine, so `summon PointLight` still works
- `count` is the last word when it is a number: `summon mona lisa 3`. It spawns that many copies
  0.15 seconds apart (at most 500 per command).
- Everything spawns about 1.5 m in front of you, facing where you look.
- **Which objects there are:** every different look of everything you can pick up (valuables,
  keycards, tools), plus pushable furniture, loose physics props and balloons, exactly as they
  are placed in the game's maps. `tools/make_objects.py` reads them out of the map files.

### dupe

- Traces from your camera to whatever is under the crosshair and spawns copies of it **with its
  data**, so a painting copies as that painting and not as the class's default statue.
- What is copied:
  - every Blueprint variable that is a number, a yes/no, text, a name, a reference to an asset or
    class, or a struct of plain numbers (vector, rotation, colour): the value, a keycard's name,
    a wall's mesh choice...;
  - for every mesh component: its mesh, its materials and its size;
  - the same variables on the object's Blueprint components (the look-at text, for example).
- What is not copied: references to other objects in the map, lists, and the engine's own
  properties (position, owner, network state). The copy appears in front of you.
- The data is read once, when you type `dupe`. The copies still get it if the original is gone
  by the time a long batch finishes.
- Things that build their look from variables when they spawn (walls, doors, buildings) may not
  rebuild after the variables are copied; their mesh components are copied directly, which
  covers most of them.
- Plain level geometry (walls and floors that are just part of the map) is refused rather than
  spawning an empty object.

### Looks in multiplayer

- When you host, a copy with a different mesh shows that mesh for everyone: the host marks the
  mesh component to be sent over the network (`CopyLookToGuests` in `config.lua`).
- The engine never sends materials. Guests see the right mesh but possibly in its normal
  colours.
- As a guest, `summon` and `dupe` go through the host with
  [command sharing](#command-sharing) as before, and the host copies the data.

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
  nothing in the game; `maxskills` repairs that too. Healing Touch brings out a game bug when you
  revive someone as a guest: see [Reviving a teammate with Healing Touch](#reviving-a-teammate-with-healing-touch).
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
- `setxp all <amount>` gives every player in the heist, you included, that much extra XP. Only
  each player's own game can change their XP, so it uses the one thing the game sends to everyone:
  the escape van's own XP call. Every player's game adds it to their heist XP, and the win screen
  pays and saves it when the heist is won, like the heist's own XP. Guests do not need the mod.
  - Only the host can use it, and only during a heist.
  - A lost heist pays nothing, as in the game.
  - At most 100,000 extra XP per player per heist (`SetXPAllMax` in `config.lua`), about 75
    levels for a new player. The game levels up one level at a time with a function that calls
    itself, so far more could crash a low-level player's game on the win screen. The win screen
    also counts each level up for a few seconds.
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

### civilians

- `civilians` shows how many civilians are here, how many are tied up or scared, and how many
  are down.
- `civilians tie` ties up the civilian you are looking at, the way pressing E on one does: they
  are tied up, stop walking, and never flee, run to a guard or call the police.
  `civilians tie all` ties up every civilian in the map.
- `civilians kill` (or `kill all`) kills them as if shot. Each one counts as a civilian killed,
  so the win screen takes the same penalty off the take as when you shoot one.
- `civilians remove` (or `remove all`) takes them out of the heist: no body and nothing counted.
  `remove all` also takes the bodies.
- As a guest these go to the host (command sharing level 2 or 3), aimed from your own camera.
  They are also in the menu's Heist tab.

### notarget

- `notarget` hides you from the guards, the security cameras and civilians; `notarget` again (or
  `notarget off`) turns it off. Only the player who turns it on is hidden: everyone else is seen as
  usual. It is also a switch in the menu's Player tab.
- Guards do not see you at all (no spotting meter, no warning, no escort or arrest) and do not
  shoot at you; cameras look straight through you; civilians do not see you either: while you
  are in front of one, its sight ends just short of you (so it can miss someone right behind you
  for that moment). Your gunshots and footsteps make no noise, NPC bullets pass
  through you, and a guard or police officer that picks you as its target after someone else set
  off the alarm drops it.
- All the game's AI runs on the host, so the host's mod does it. As a guest, `notarget` goes to
  the host by itself (command sharing at 1 or more), and the host's guards then ignore you.
- It does not stop alarms you set off yourself (glass, lasers, keypads, C4, a knocked out
  guard's phone), and bodies or loot are still seen.

### noclip

- `noclip` turns it on, `noclip` again lands you.
- **Controls:**
  - WASD moves forward, back, left and right, the game's own movement.
  - Space goes up, Ctrl goes down.
  - Hold Shift to go faster: twice as fast, or the Shift speed you set (menu Settings > Commands,
    or `NoclipFastSpeed` in `config.lua`). The normal speed is `NoclipSpeed` (0 = your walking
    speed). Changed speeds apply at once, also while you fly.
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

### setammo

- `setammo 999` gives every gun you carry 999 spare bullets, and the gun in your hand a full
  magazine. Reloading takes from the spare bullets as usual.
- Ammo is counted on each player's own game, so it works the same when you host and when you are
  a guest, and nobody else needs the mod. It only changes your own guns.
- At most 999,999 per gun (`AmmoMax` in `config.lua`).

### truckmoney

Put money straight into the getaway truck instead of summoning thousands of gold bars.

- `truckmoney` shows the truck's money, how much of it is loot and how much is from `truckmoney`,
  and the minimum the truck needs before you can leave.
- `truckmoney set 1000000` makes the truck hold exactly that. Loot you throw in afterwards still
  adds on top.
- `truckmoney add 50000` adds to it. A negative amount takes money away, never below 0.
- `truckmoney reset` puts it back to 0, for when something went wrong.
- **Every player gets the whole truck** on the win screen, not a share: that is how the game pays.
- Host only, during a heist. A guest can look with `truckmoney` but not change it.
- How it works: the truck keeps its take in one number that everyone's game copies from the host.
  The mod changes that number the way the game does. When the escape button is pressed, the game
  counts the money again from the loot inside; the mod puts its change back on top right after.
  Loading a new map forgets the change.
- At most 100,000,000 (`TruckMoneyMax` in `config.lua`). Cash is a 32-bit number in this game, and
  a bigger payout could overflow someone's cash.
- To leave, the game still needs the minimum take and everyone in the truck. If you were already
  standing in the truck when you used `set`, step out and back in so it checks again.
- The take counts toward your Steam "cash" stat, the same as real or summoned loot does.

### Heist commands for the host

The game decides these things on the host, so these commands use the game's own functions there,
and the game sends the result to every player. Guests do not need the mod.

As a guest you can type them too. They go to the host when the host has OAR Commands with
[command sharing](#command-sharing) at 2 or 3, and the host's answer shows in your console.
Otherwise they say that only the host can. The "show" forms (`alarm`, `cops`, `cameras`, `codes`,
`doors`, `guards`, `guards phones`) work on your own game.

- `reviveall`, `healall`: every downed player up again / everyone back to full health, and full
  armor for those wearing some. The same steps as a teammate's revive.
- `godall`: the game's own damage immunity for everyone, the one it gives for a few seconds after
  some events. While it is on, everyone's screen shows the immunity glow. It covers the players in
  the heist when you type it: type `godall on` again after someone joins or a new heist starts.
- `alarm off` uses the alarm box for you: in every heist that box is a lever wired to the alarm,
  and the command runs the same click event, so the lever swings for everyone and the alarm is
  disabled (guards can no longer raise it). Once the alarm has already gone off, switching it off
  does not send the police home.
- `alarm on` switches the alarm back on and makes the box usable again (the lever stays down).
- `alarm trigger` makes the alarm go off: the heist goes loud.
- `alarm` on its own says whether it is ON or OFF and whether it has gone off.
- `cops wave` and `cops specials` make the police spawner send a wave now. `cops clear` removes
  every police officer in the map, the way the game clears everyone at the escape. While the heist
  is loud, the spawner keeps sending new waves.
- `cameras off` removes every security camera, broken ones too, the way `destroytarget` removes
  a thing: there is no broken camera left for guards to notice. If someone is looking through a
  camera from the security room, their camera view closes and they are back in their character
  first.
- `cameras destroy` breaks the working cameras the way shooting them does (the head drops, they
  stop spotting). Guards may notice those.
- `codes` lists every keypad's code with how far away it is. `codes open` unlocks every keypad the
  way hacking one does.
- `bringloot` drops every loose valuable into the truck's cargo hold, where it lands and counts the
  game's own way. The pieces are spread over the hold's floor in the truck's own directions, middle
  first, and dropped one layer at a time from just above the floor, so each layer lands before the
  next one comes down and nothing ends up on the roof. Each piece is picked up and let go the game's
  way first, so pieces that only move once a player picked them up fall instead of floating, and
  guests see them move. A very big haul that does not fit at once
  is reported: type `bringloot` again once the first lot has landed. Every time it looks for the
  loot again, so new loot (from a container you opened, or spawned) comes along on the next
  click. Loot still sitting in a container is taken out of it first, as picking it up does. It
  leaves alone what a player is holding, what is in a bag, and what is already in the truck. The layout is set in
  `config.lua` (`BringLootSpacing`, `BringLootMargin`, `BringLootFloorGap`, `BringLootLayerHeight`,
  `BringLootMaxHeight`, `BringLootWaveMs`).
- `escape` presses the escape button for you, even when not everyone is in the truck or the
  minimum take is not there: everyone gets the win screen with what is in the truck.

### doors

- `doors unlock` unlocks the door you are looking at and leaves it shut. Looking at its lock, its
  frame or the wall right beside it counts too. `doors unlock all` unlocks every door in the map:
  lock-picked doors, keycard and hacked doors, hand-scanner doors, and doors that lock once the
  alarm goes off. It uses the door's own unlock, so every player sees it, and unlike picking an
  alarm lock it sets nothing off.
- `doors lock` locks the door you are looking at again, and `doors lock all` locks every door in
  the map (also the ones that were never locked). The game has no lock of its own, so the mod puts
  back what a locked door starts the heist with: nobody can open it with E, it is named
  "Door (locked)", and on a padlock door both padlocks can be picked or cut again (the spot the
  grinder, drill and C4 work on comes back). An open door is closed first; one that is swinging
  open is closed once it stops. `doors unlock` (or `unlock all`) undoes it.
- What a lock does not do: guards and police still open locked doors, as they do in the game. A
  keypad that only works once does not open its door again after a keycard or a hack already
  used it (the game keeps that inside the keypad, out of the mod's reach); hand scanners and
  keypads that reset themselves work again. Players who join later see the door's old name.
- `doors open` and `doors close` (with `all` for every door) swing doors open or shut. The game's
  own open is a toggle, so the command leaves a door alone that is already where you want it or
  still swinging. Opening unlocks the door first. No guard is alerted.
- `doors vault open` opens the vault the way hacking or drilling it does, and the police waves
  pause for 30 seconds as in the game. **The vault cannot be closed again**: the game has no way
  to close it, so the command warns you, and `doors vault close` says so. Players who join after
  it opened see it shut but can walk through, the same as in the game.
- `door` is the same command as `doors`.
- As a guest, `doors unlock` (and open, close, lock) sends your camera position along, so the host's
  mod unlocks the door **you** are looking at.

### guards

- `guards kill` kills the guard you are looking at the game's own way, as if you shot them with
  all of their health: every player sees them fall, they drop their gun, you get the game's XP for
  it, and other guards can find the body. A guard who was not alert drops a phone, as any guard
  you take down does. `guards kill all` does every guard.
- `guards remove` takes the guard you are looking at out of the heist: no body and no phone. A
  keycard on their belt drops to the floor first, and a player they were escorting out is let go.
  Looking at the floor right beside a guard or a body counts too. `guards remove all` takes every
  guard and every body.
- A guard's phone rings for 15 seconds (more with the skill) and then alerts every guard ("Guard
  did not check in"). `guards phones answer` checks every ringing phone in, the same as carrying
  it to a scanner, without using up a scanner. `guards phones remove` takes the phones away; one a
  player is holding is answered instead and stays in their hands.
- `guards` on its own shows how many guards are alive, alert and down, and the phones ringing.
- As a guest, `guards kill` and `guards remove` send your camera along, so the host's mod acts on
  the guard **you** are looking at.

### ESP

`esp` (or the **ESP** tab of the menu) marks guards, police, civilians and the other players on
your screen, also through walls. It is only on your own screen and works the same as a guest.

- **Groups**, each with its own settings: Guards, Police (every type: regular, helmet, SWAT,
  shield, blinding shield, juggernaut), Police specials (the interceptor and the powerbox
  defuser), Cameras (security cameras, marked at their head; it says when one is blinded,
  EMP'd, watched or spotting someone), Civilians (off at first) and Other players.
- **ESP type** per group: **Box** (a box around them), **Silhouette** (their body outlined
  through walls) or **Both**.
- **Per group**: show or hide, which silhouette colour (the ESP's or the game's white), a box, corners only or
  no box, a colour for the box, names and lines (typed like `#ffb329`), a see-through fill, the
  name (the kind of guard or police, or the player's name), the distance, a health bar, a head
  dot, a line from the bottom, middle or top of the screen, a warning colour (a guard that is
  alert or searching, a hostage or scared civilian, a downed player) and a range in metres.
- **Look**: line thickness, text size, how solid the fill is, the most targets shown at once
  (the nearest), and what to do with targets you can see directly: show, dim or hide them (so
  only the ones behind walls are marked).
- **Silhouettes through walls**: the game's own outline effect around the bodies themselves. It
  has two colours: the game's white, which it uses for phones, keypads, locks and downed
  teammates and which the ESP leaves alone, and a second one that becomes the ESP's colour (each
  group picks the ESP's colour or white). Then the style (**Outline** around the body, or
  **Filled**: a thick band inside it, which looks solid on people further away), thickness and
  brightness. While any silhouettes are on, the game's red outline on someone spotting you takes
  the ESP's colour, and thickness, brightness and style apply to the game's outlines too (the
  defaults match the game's). Only in heist maps.
- Every change is used at once and saved in `settings.lua`; **Reset ESP** goes back to the
  defaults, which are `V.Esp` in `config.lua`.
- Dead and tied-up NPCs are not marked (the game stops their updates).

### infiniteammo

- Your magazine is full again after every shot, so you never reload. `infiniteammo` again turns
  it off. Ammo is counted on your own game, so it works as a guest too. Only your own guns.

### Reviving a teammate with Healing Touch

- **A bug in the game:** your revive bar fills in *your* revive time (5 s, or 4, 3.5 or 3 s with
  the Healing Touch skill, which `maxskills` gives you). The host finishes the revive after the
  *downed player's* revive time, and only if you still hold the mouse button then. So with
  Healing Touch the bar is full before the revive is, and letting go at that moment cancels it.
- **When you host, the mod fixes it:** a revive finishes when the reviver's bar does. It sets the
  downed player's revive time to the reviver's just while the game starts its revive timer, then
  puts it back. A revive is never made slower than the game makes it. `ReviveMatchesBar` in
  `config.lua` turns this off.
- **As a guest** the host's game decides: keep holding until your teammate stands up.

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
  every `reloadconfig` too: `spawnables.lua` and `objects.lua` (`summon`), `unlockables.lua`
  (`maxskills`, `unlockall`) and `maps.lua` (`selectmap`, `forcemap`). You can add your own
  objects to `objects.lua`: a name, the class, and the meshes, materials, size and values.
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
| `2` | Level 1 plus world commands: `destroyall`, `slomo`, `playersonly`, `changesize`, `doors`, `reviveall`, `healall`, `godall`, `alarm`, `cops`, `cameras`, `codes`, `bringloot`, `guards`, `civilians` |
| `3` | Any console command except the block list below (guests use `host <command>` for commands the mod does not know) |

`commandsharing` with no number shows the current level. Only the host's setting counts.

**How a guest sends a command.** The mod's own commands (`summon`, `dupe`, `noclip`, `revive`,
the heist commands, `doors`...) go to the host by themselves. For the game's own cheats (`god`, `ghost`, `fly`, `walk`,
`teleport`, `destroytarget`...) type `host god`, `host ghost` and so on. There is a shortcut that
sends a typed `god` to the host by itself (`ShareEngineCheatShortcuts` in `config.lua`), but it is
off: it registers 20 more console commands, and UE4SS 3.0.1 only has room for about 45 per mod.
With more than that the game crashed at random, even at startup.

**Always blocked**, at every level:

- **Anything that would close, move or cut off your game:** `exit`, `quit`, `open`, `travel`,
  `servertravel`, `disconnect`, `reconnect`, `switchlevel`, `restartlevel`, `streammap`,
  `demoplay`, `demorec`, `selectmap`, `forcemap`.
- **Anything that touches your files or crashes the game:** `exec`, `deletecloudfiles`,
  `DoubleFreeFinderCrash`, `MallocFrameProfiler`, `purchase`, `debug`.
- **The mod's commands that stay on each player's own game and save:** `setmoney`, `addmoney`,
  `setlevel`, `setxp`, `maxskills`, `unlockall`, `bind`, `unbind`, `unbindall`,
  `commandsharing`, `host`, `reloadconfig`, `setammo`, `infiniteammo`.

**What runs where.** A guest's command runs as that guest, on the host's game:

- `summon` and `spawn` put things in front of the **guest**.
- `god`, `ghost`, `walk`, `revive` and `noclip` act on the **guest's** character.
- `destroytarget`, `dupe`, `teleport`, `doors`, `guards` and `civilians` act on what the **guest** is looking at: the
  guest's mod sends its exact camera position and angle, and the host's mod aims from there.
- The heist commands (`alarm off`, `cops wave`, `bringloot`...) change the heist for everyone,
  the same as when the host types them.
  `destroytarget` from a guest leaves other players alone.
- The host's own commands are unchanged: when you (the host) type `destroytarget`, it destroys
  what **you** are looking at.

The host's console shows every guest command, for example `[OAR] Friend ran: summon goldbar 5`.
The guest sees the host's answer, for example `[OAR host] ... ok Summoning Goldbar_C x5` or
`[OAR host] ... ok Unlocked the door (it stays shut)`.

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
  - `Scripts\spawnables.lua`, the class names for `summon`;
  - `Scripts\objects.lua`, the object names for `summon` (one class, different data);
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
python tools/make_objects.py       # mod/Mods/OARCommands/Scripts/objects.lua
python tools/make_unlockables.py   # mod/Mods/OARCommands/Scripts/unlockables.lua
python tools/make_maps.py          # mod/Mods/OARCommands/Scripts/maps.lua
```

After a game update, run all six again (`make_objects.py` before `build_lists.py`): new heists, loot and items then show up in the lists,
in `summon` and in `selectmap`.

- `make_unlockables.py` reads each shop item's and skill's default values (`CashCost`,
  `CoinCost`, `SteamItemDefID`, `SkillComponent`) from the pak and refuses to write a table that
  contains anything with a coin price or a Steam item ID.
- `make_objects.py` reads every map in the pak and collects, for each item class, the different
  meshes, materials, sizes and values its placed copies have. Each gets a name from the item's
  in-game name plus its mesh or text (`artwork_nefertiti`, `vault_keycard`).
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

The installers (needs Python 3 and the .NET SDK 6 or newer):

```
python tools/make_payload.py
cd installer
dotnet build -c Release
dotnet build -c Release -p:Edition=Online
```

`make_payload.py` downloads the official UE4SS 3.0.1 zip once (checked against its SHA-256),
lays `mod/` over it and writes `build/payload.zip`, which the offline installer embeds, plus
`dist/OAR-Commands-Payload.zip` and its `.sha256` for the online installer. The results are
`dist/OAR-Commands-Offline-Installer.exe` and `dist/OAR-Commands-Online-Installer.exe` (the same
code; the online edition carries no files). A release must include all four files in `dist`:
the online installer looks for the zip and its checksum in the latest release.

Tests:

```
python tools/test_oarcommands.py      # the Lua mod against stubbed UE4SS functions (needs lupa)
cd installer && dotnet build -c Debug && dotnet build -c Debug -p:Edition=Online && cd ..
python tools/test_installer.py        # both installers against fake game folders and a fake release
```

## Credits and license

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) by the UE4SS team, MIT license
  ([third_party/UE4SS-LICENSE.txt](third_party/UE4SS-LICENSE.txt)). The installer bundles an
  unmodified UE4SS 3.0.1 plus small edits to two of its stock Lua mods, described above.
- The original object and console variable dumps were made with UUU (Universal Unreal Engine
  Unlocker) by Otis_Inf.
- This project: MIT license, see [LICENSE](LICENSE).
