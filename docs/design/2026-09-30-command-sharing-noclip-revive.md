# Command sharing, noclip and revive

Design for OAR Commands 1.2.0. Status: waiting for approval.

## Goals

1. **`revive`**: gets the player who ran it back up.
2. **`noclip`**: real noclip. WASD moves, Space goes up, Ctrl goes down, Shift doubles the speed.
3. **`commandsharing 0-3`**: a host lets guests who also have the mod run commands through the
   host's game. It is off every time the game starts.
4. **Failsafe**: when sharing is not available (off, no mod on the host, solo, you are the host,
   or the relay breaks), every command runs locally exactly as it does today.
5. **Aim**: a guest's `destroytarget` or `dupe` acts on what the guest is looking at. The host's
   own commands keep acting on what the host is looking at.

## Facts the design rests on

All read from this build (UE 4.27 shipping, 23 August 2026):

- **Guest to host channel.** `PlayerController.ServerExecRPC(string)` is a reliable
  client-to-server call on the player's own controller. In the running game its `Validate` is
  `return true` and its `Implementation` is an empty `ret`. A guest's mod can send any text to the
  host, and it has no effect in the game unless the host's mod listens for it.
- **Host to guest channel.** `PlayerController.ClientMessage(string)` is a reliable
  server-to-client call. It prints the text in the guest's console, so replies are readable even
  without the mod.
- **Replication.** Push-model replication is compiled out (no `net.IsPushModelEnabled` in the
  exe). Property writes on the host replicate normally.
- **Movement.** The character moves with `AddMovementInput(GetActorForwardVector / RightVector)`.
  Both are level, and there is no up or down input.
- **Per-frame hook.** The character's `InpAxisEvt_MoveForward` event runs every frame through
  `ProcessEvent` while the player has control, so UE4SS can hook it.
- **Revive.** When a teammate's revive finishes, the game (PlayerCharacter event graph):
  1. sets `Health = MaxHealth` and `Downed? = false`;
  2. calls `ReviveClient()` on the downed player's machine (camera colour back, pitch limit
     back, highlight off).
- **UE4SS 3.0.1 limits.** Lists cannot be grown from Lua, and a class cannot be put into a struct
  from a Lua table. This design needs neither.

## Commands

### revive

- **Runs on the machine in charge of the character,** which is the host for everyone:
  1. `Health = MaxHealth`
  2. `Downed? = false`
  3. `ReviveClient()`
- **Not downed:** health is topped up, and it says you were not downed.
- **Guest:** the command goes through sharing (level 1 and up). Without sharing it still runs
  locally. That only changes the guest's own screen, because the host decides who is downed.

### noclip

- **A toggle.** Turning it on:
  - collision off (`SetActorEnableCollision(false)`);
  - movement mode Flying;
  - `bCheatFlying` on, so you stop dead when you let go of the keys;
  - `MaxFlySpeed` set to your walk speed.
- **Every frame** (hook on your own character's `MoveForward` event):
  - Space adds up input and Ctrl adds down input.
  - `MaxFlySpeed` is twice the base speed while Shift is held, otherwise the base speed.
  - The game's own WASD handling does forward, back, left and right.
- **Turning it off:** collision on, movement mode Falling (you drop and land normally), flying
  off, and the old `MaxFlySpeed` restored.
- **Ends by itself** when your character changes: death, respawn, or level change.
- **Multiplayer:**
  - **Host:** the host's character is authoritative, so everyone sees the host fly.
  - **Guest with sharing:** the guest's mod turns noclip on locally (so movement prediction
    agrees) and asks the host to do the same to the guest's character on the host. Speed changes
    from Shift are sent too, so both sides use the same speed.
  - **Guest without sharing:** local only, and the host pulls the guest back, the same as the
    built-in `ghost`.
- **Game controls:** the game's own jump, crouch and sprint still run on Space, Ctrl and Shift.
  Jumping does nothing while flying. The game's crouch may lower the camera while Ctrl is held.

### commandsharing [0-3]

- **Host only.** With no number it shows the current level. It is not saved: every launch starts
  at 0.
- **The host's console lists every guest request,** for example
  `[OAR] <player> ran: summon goldbar 5`.

| Level | Guests may run |
|---|---|
| 0 | nothing (off) |
| 1 | player commands: `summon`, `spawn`, `summonstop`, `dupe`, `revive`, `noclip`, `god`, `ghost`, `fly`, `walk`, `teleport`, `destroytarget` |
| 2 | level 1 plus world commands: `destroyall`, `slomo`, `playersonly`, `changesize` |
| 3 | any console command except the block list |

**Always blocked**, at every level:

- **Would close, move or damage the host's game:** `exit`, `quit`, `open`, `travel`,
  `servertravel`, `disconnect`, `reconnect`.
- **Would touch the host's files or crash:** `exec`, `deletecloudfiles`, `DoubleFreeFinderCrash`,
  and the engine's other crash and debug-break commands.
- **The mod's local commands:** `setmoney`, `addmoney`, `setlevel`, `setxp`, `maxskills`,
  `unlockall`, `bind`, `unbind`, `unbindall`, `commandsharing`. These always run on your own game
  and save and never go to the host.

## How a guest's command travels

**Guest side.** This applies to every command in the level lists: the mod's own commands, and a
thin UE4SS handler for each engine cheat in the lists.

1. **Not a guest** (solo, host, or no network): run locally, the same code path as today.
2. **Send** `oar1 <id> <command line>` with `ServerExecRPC` on your own controller:
   - For `destroytarget` and `dupe`, append your camera position and angle:
     `@x,y,z,pitch,yaw`, rounded.
   - Messages are kept under 120 characters. A longer command runs locally.
3. **Wait** up to 1.5 seconds for the host's reply: a `ClientMessage` starting `[OAR host] <id>`.
   - **`ok`:** done, and the host's summary is shown.
   - **`off`, `not allowed`, or no reply:** run locally as today, and say why.

For engine cheats, "run locally" means handing the command to the engine unchanged. A guard flag
stops the mod's own handler from catching it a second time. If the relay ever breaks, commands
behave as if the mod had no relay at all.

**Host side.** Hook `PlayerController:ServerExecRPC`, then:

1. **Ignore** anything that does not start with `oar1`, and anything from the host's own
   controller.
2. **Check** the sharing level, the level lists and the block list. If refused, reply `off` or
   `not allowed`.
3. **Run the command as that guest,** using the guest's controller on the host:
   - **`summon` / `spawn`:** the mod's summon code, with the guest's cheat manager. Objects
     appear in front of the guest.
   - **`summonstop`:** stops every summon batch running on the host, the host's own included.
   - **`destroytarget` / `dupe`:** trace from the camera pose the guest sent (ignoring the guest's
     own character). Destroy or copy what the guest is looking at.
   - **`revive` / `noclip`:** act on the guest's character.
   - **Engine cheats** (`god`, `teleport`, `walk`...): create a cheat manager for the guest's
     controller if missing, then `ExecuteConsoleCommand` on the guest's controller. The cheat
     acts on the guest's character.
4. **Reply** `[OAR host] <id> ok: <summary>` with `ClientMessage`.

The `oar1` prefix versions the protocol, so a later format can live next to this one.

## Failsafes

- **Errors:** every relay step runs inside `pcall`. Any error means "run locally".
- **Host without the mod:** no reply, so the command runs locally after 1.5 seconds.
- **Host with sharing at 0:** the reply `off` comes at once, and the command runs locally.
- **Solo and host:** never touch the relay.
- **Game start:** sharing is back to 0 every time.

## Testing

- **Lua tests with the fake UE4SS** (lupa):
  - message encoding and decoding;
  - level lists and the block list;
  - the host running a command on the guest's controller;
  - aim pose parsing;
  - guest fallback on `off`, `not allowed` and timeout;
  - the guard flag (no loops);
  - noclip per-frame logic (keys to up/down input and speed);
  - revive steps on the right character.
- **In game:** a host and a guest, both with the mod. This needs two players.
  - `commandsharing` at 0, 1, 2 and 3.
  - `summon` from the guest appears in front of the guest.
  - The guest's `destroytarget` destroys what the guest looks at.
  - `revive` and `noclip` work for both players and are seen by both.
  - Unplugging the relay (host at 0) falls back to local.

## Documentation and release

- **README:** new sections for `revive`, `noclip` and command sharing:
  - the levels table and the block list;
  - what runs where;
  - the failsafe;
  - that the guest also needs the mod.
- **Release:** version 1.2.0 on GitHub. It includes the unreleased 1.0.1 and 1.1.0 changes (debug
  camera fix, value commands, fly note) after they are confirmed in game.
