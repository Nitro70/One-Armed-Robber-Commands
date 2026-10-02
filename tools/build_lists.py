"""Build One-armed robber console command lists from UUU dumps.

Reads UUU_ObjectsDump.txt and UUU_CVarsDump.json from the game's Binaries\\Win64 folder
and writes two files next to this script:

    OAR_Working_Commands.txt   every console command / cvar that works in this build
    OAR_Spawn_Commands.txt     every "summon <Class>" you can use, grouped by what it is

Re-dump with UUU on another map and run this again to get that map's spawn list
(summon only finds classes that are loaded at the time).

The STUBBED set below was found on 2026-09-27 by reading each exec function's machine
code out of the running game (UE 4.27 shipping build, OAR-Win64-Shipping.exe dated
2026-08-23). If the game updates, those may change.
"""
import json
import os
import re
from collections import OrderedDict, defaultdict

import oar_exe_commands
import make_objects
import oar_pak
import oar_registry
from oar_engine_command_info import COVERED_ELSEWHERE, ENGINE_COMMANDS
from oar_paths import game_dir

GAME_BIN = os.path.join(game_dir(), "OAR", "Binaries", "Win64")
OBJ_DUMP = os.path.join(GAME_BIN, "UUU_ObjectsDump.txt")
CVAR_DUMP = os.path.join(GAME_BIN, "UUU_CVarsDump.json")
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lists")

FUNC_EXEC = 0x200

# Exec functions whose body is an empty "ret" in this shipping build.
STUBBED = {
    "DebugRemovePlayer", "DebugCreatePlayer", "SetBandwidthLimit", "SendToConsole",
    "ToggleAILogging", "TestCollisionDistance", "SSSwapControllers", "SetConsoleTarget",
}
# Exec functions on classes the game never routes console input to.
NOT_ROUTED = {
    "Engine.GameMode": "the game mode (RobberGM_C) is a GameModeBase, not a GameMode",
    "Engine.GameInstance": "stubbed in this build",
    "Engine.HealthSnapshotBlueprintLibrary": "function library, not in the console's command chain",
}

DESC = {
    # CheatManager
    "God": "Toggle invincibility",
    "Fly": "No gravity only: you hover at your height, cannot go up or down (walk to stop)",
    "Ghost": "Like fly plus no collision: walk through walls at your height (walk to stop)",
    "Walk": "Back to normal walking after fly/ghost",
    "teleport": "Teleport to whatever your crosshair is pointing at",
    "Summon": "Spawn an actor in front of you. See OAR_Spawn_Commands.txt",
    "Slomo": "Game speed. 1 = normal, 0.5 = half, 3 = triple",
    "ChangeSize": "Scale your character. 1 = normal, 2 = double, 0.5 = half",
    "DestroyTarget": "Delete the thing you are looking at",
    "DamageTarget": "Damage the thing you are looking at by this amount",
    "DestroyAll": "Delete every actor of a class, e.g. DestroyAll NPC_Police_base_C",
    "DestroyPawns": "Delete every non-player pawn of a class, e.g. DestroyPawns NPC_Guard_C",
    "DestroyAllPawnsExceptTarget": "Delete every AI pawn except the one you look at",
    "PlayersOnly": "Freeze everything except players (AI, physics). Run again to undo",
    "FreezeFrame": "Pause the game after this many seconds",
    "ToggleDebugCamera": "Detached free camera; your character stays put. Run again to exit",
    "ViewSelf": "Camera back to your own character",
    "ViewPlayer": "Spectate another player by name",
    "ViewActor": "Put the camera on a named actor (names are in the objects dump)",
    "ViewClass": "Cycle the camera through actors of a class, e.g. ViewClass NPC_Guard_C",
    "BugIt": "Log your exact position/rotation (BugItGo line) to the log",
    "BugItGo": "Teleport to coordinates: BugItGo X Y Z Pitch Yaw Roll",
    "LogLoc": "Print your location to the log",
    "StreamLevelIn": "Stream a sub-level in by package name",
    "OnlyLoadLevel": "Load a streaming sub-level without making it visible",
    "StreamLevelOut": "Stream a sub-level out by package name",
    "InvertMouse": "Toggle inverted mouse Y",
    "SetMouseSensitivityToDefault": "Reset mouse sensitivity",
    "FlushLog": "Write the log to disk now",
    "CheatScript": "Run a [CheatScript.Name] command list from the game ini",
    "SetWorldOrigin": "Rebase the world origin to your position (debug)",
    "UpdateSafeArea": "Refresh the UI safe-zone (debug)",
    "DumpChatState": "Log chat state (debug)",
    "DumpOnlineSessionState": "Log online session state (debug)",
    "DumpPartyState": "Log party state (debug)",
    "DumpVoiceMutingState": "Log voice mute state (debug)",
    "SpawnServerStatReplicator": "Net stats replicator (debug)",
    "DestroyServerStatReplicator": "Net stats replicator (debug)",
    "ToggleServerStatReplicatorClientOverwrite": "Net stats replicator (debug)",
    "ToggleServerStatReplicatorUpdateStatNet": "Net stats replicator (debug)",
    "DebugCapsuleSweep": "Draw a debug capsule trace from your view (debug)",
    "DebugCapsuleSweepSize": "Set debug capsule size: HalfHeight Radius",
    "DebugCapsuleSweepChannel": "Set debug capsule trace channel",
    "DebugCapsuleSweepComplex": "Toggle complex collision for debug capsule",
    "DebugCapsuleSweepCapture": "Capture the current debug capsule trace",
    "DebugCapsuleSweepPawn": "Toggle continuous debug capsule sweep from your pawn",
    "DebugCapsuleSweepClear": "Clear debug capsule drawings",
    "BugItStringCreator": "Helper used by BugIt (no visible effect)",
    # PlayerController
    "EnableCheats": "Create the cheat manager if god/fly/summon say 'Command not recognized'",
    "FOV": "Set field of view, e.g. FOV 110 (the game may reset it)",
    "Pause": "Pause / unpause",
    "RestartLevel": "Reload the current map (host)",
    "LocalTravel": "Travel to a map URL locally",
    "SwitchLevel": "Switch to a map URL",
    "SetName": "Change your player name",
    "Camera": "Camera style: Camera FreeCam / ThirdPerson / FirstPerson / Default (game camera may override)",
    "ToggleSpeaking": "Toggle voice chat transmit",
    "StartFire": "Fire the current weapon",
    "ConsoleKey": "Simulate a key press by name",
    "ServerExec": "Ask the server to run a command (host must allow it)",
    "TestServerLevelVisibilityChange": "Net debug",
    # HUD / viewport / input / AI
    "ShowHUD": "Toggle the engine HUD (the game's own UI widgets may stay)",
    "ShowDebug": "Debug overlay: ShowDebug, ShowDebug Camera, ShowDebug Collision, ShowDebug Physics",
    "NextDebugTarget": "Next ShowDebug target",
    "PreviousDebugTarget": "Previous ShowDebug target",
    "ShowDebugToggleSubCategory": "Toggle a ShowDebug sub-category",
    "ShowDebugForReticleTargetToggle": "ShowDebug whatever is under the crosshair",
    "ShowTitleSafeArea": "Draw the TV safe-area frame",
    "ShowDebugSelectedInfo": "In debug camera: show info on the selected actor",
    "SetBind": "Saves a key bind that this shipping build never runs. Use the mod's bind instead",
    "SetMouseSensitivity": "Set mouse sensitivity",
    "InvertAxis": "Invert an input axis by name",
    "InvertAxisKey": "Invert an input axis key",
    "ClearSmoothing": "Reset mouse smoothing",
    "AIIgnorePlayers": "Engine 'AI ignores players' toggle. The game's own guard logic may not check it",
    "AILoggingVerbose": "Verbose AI logging",
}

CLASS_TITLES = OrderedDict([
    ("Engine.CheatManager", "CHEATS (CheatManager)"),
    ("Engine.PlayerController", "PLAYER CONTROLLER"),
    ("AIModule.AISystem", "AI"),
    ("Engine.PlayerInput", "INPUT / KEYBINDS"),
    ("Engine.HUD", "HUD / DEBUG OVERLAY"),
    ("Engine.GameViewportClient", "VIEWPORT"),
    ("Engine.DebugCameraController", "DEBUG CAMERA (only while ToggleDebugCamera is on)"),
])

QUICK_START = [
    ("god", "invincible"),
    ("ghost / fly / walk", "through walls / no gravity (no up or down in this game) / normal"),
    ("teleport", "go to where you are aiming"),
    ("slomo 0.3", "slow motion (slomo 1 = normal)"),
    ("summon goldbar 5", "spawn things (mod; full list: OAR_Spawn_Commands.txt)"),
    ("summon mona lisa", "an object: one class with its own look and values (mod; OBJECTS in OAR_Spawn_Commands.txt)"),
    ("dupe", "copy what you are looking at, with its look and values (mod)"),
    ("bind x destroytarget", "put any command on a key (mod; the game's own SetBind is dead)"),
    ("setmoney 5000000", "set your cash and save it (mod; also addmoney, setlevel, setxp)"),
    ("maxskills / unlockall", "every skill at top tier / every cash-bought weapon, mod, tool, armor (mod)"),
    ("noclip", "fly through walls: WASD, Space up, Ctrl down, Shift faster; again to land (mod)"),
    ("revive", "get back up with full health (mod)"),
    ("selectmap museum", "host: pick the heist from the console; selectmap alone lists them (mod)"),
    ("forcemap museum", "host: start a map now for everyone, no ready-up or countdown (mod)"),
    ("reloadconfig", "load Mods\\OARCommands\\config.lua again after editing it: every command's values and code (mod)"),
    ("commandsharing 1", "host: guests with the mod can run commands through your game (mod; 0-3)"),
    ("DestroyTarget", "delete what you are looking at"),
    ("DestroyAll NPC_Police_base_C", "delete every cop on the map"),
    ("PlayersOnly", "freeze all AI and physics (again to unfreeze)"),
    ("ToggleDebugCamera", "free camera (again to exit)"),
    ("ChangeSize 3", "giant robber (ChangeSize 1 = normal)"),
    ("stat fps", "FPS counter"),
    ("open CheatLevel", "load a leftover dev map called CheatLevel (solo, untested)"),
]

USEFUL_CVARS = [
    "t.MaxFPS", "r.ScreenPercentage", "r.VSync", "r.MotionBlurQuality", "r.DepthOfFieldQuality",
    "r.Fog", "r.ViewDistanceScale", "r.Tonemapper.Sharpen", "r.DefaultFeature.AntiAliasing",
    "r.PostProcessAAQuality", "r.BloomQuality", "r.LensFlareQuality", "r.SceneColorFringeQuality",
    "r.EyeAdaptationQuality", "r.Shadow.MaxResolution", "r.SSR.Quality", "r.AmbientOcclusionLevels",
    "r.MipMapLODBias", "r.StaticMeshLODDistanceScale", "r.Streaming.PoolSize", "foliage.LODDistanceScale",
    "sg.ViewDistanceQuality", "sg.ShadowQuality", "sg.PostProcessQuality", "sg.AntiAliasingQuality",
    "r.SetNearClipPlane", "ShowFlag.Fog", "ShowFlag.PostProcessing", "ShowFlag.MotionBlur",
    "ShowFlag.DepthOfField", "ShowFlag.Vignette", "ShowFlag.Bloom", "ShowFlag.Decals",
    "ShowFlag.Particles", "ShowFlag.Collision", "ShowFlag.Navigation",
]

# Commands that are registered but you should leave alone.
AVOID = {
    "c.ToggleGPUCrashedFlagDbg": "tells the engine the GPU crashed",
    "CreateDummyFileInPersistentStorage": "writes junk to disk",
    "r.d3d11.dumpliveobjects": "D3D11 only, game runs D3D12/D3D11 debug",
    "r.RecompileRenderer": "long hitch",
    "ReloadGlobalShaders": "long hitch / possible crash",
    "ShrinkUObjectHashTables": "hitch",
    "SynthBenchmark": "runs a benchmark and changes quality settings",
    "net.SimulateConnections": "spawns fake network clients",
    "Net.CreateBandwidthGenerator": "floods the network",
    "Net.GenerateConstantBandwidth": "floods the network",
    "Net.GeneratePeriodicBandwidthSpike": "floods the network",
}

TOP = re.compile(r'^\[(\d+)\] \[([0-9A-F]+)\] ([0-9A-F]+) (\S+) (\S+)(?: -> (.*))?$')
FN = re.compile(r'^\t\[(\d+)\] \[[0-9A-F]+\] ([0-9A-F]+) Function (\S+)\t \| Flags: 0x([0-9A-F]+) \| Func: ([0-9A-F]+)')
PROP = re.compile(r'^\t\t[0-9A-F]+ (\S+) (\S+)\t')


def parse_objects():
    objs, cur, curfn = [], None, None
    with open(OBJ_DUMP, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\r\n")
            m = TOP.match(line)
            if m:
                cur = dict(type=m[4], name=m[5], parents=m[6].split(" -> ") if m[6] else [], funcs=[])
                objs.append(cur)
                curfn = None
                continue
            m = FN.match(line)
            if m and cur is not None:
                curfn = dict(name=m[3], flags=int(m[4], 16), params=[])
                cur["funcs"].append(curfn)
                continue
            m = PROP.match(line)
            if m and curfn is not None:
                curfn["params"].append((m[1], m[2]))
            elif line.startswith("\tChild properties") or line.startswith("//"):
                curfn = None
    return objs


PARAM_KIND = {"StrProperty": "text", "NameProperty": "name", "FloatProperty": "number",
              "IntProperty": "number", "ByteProperty": "number", "BoolProperty": "0/1",
              "ClassProperty": "class", "StructProperty": "struct", "ObjectProperty": "object"}


def fmt_params(params):
    return " ".join(f"<{pname}:{PARAM_KIND.get(ptype, ptype)}>" for ptype, pname in params if pname != "ReturnValue")


def row(usage, desc, width=44):
    """One command line; long usages put the description on the next line."""
    if len(usage) <= width:
        return [f"  {usage:<{width}} {desc}".rstrip()]
    return [f"  {usage}", f"  {'':<{width}} {desc}"]


def first_line(text, width=150):
    line = (text or "").strip().splitlines()[0].strip() if (text or "").strip() else ""
    return line if len(line) <= width else line[: width - 3] + "..."


def build_commands(objs, cvars, maps, engine_words):
    L = []
    w = L.append
    w("ONE-ARMED ROBBER: CONSOLE COMMANDS THAT WORK")
    w("=" * 78)
    w("Game build : Unreal Engine 4.27 shipping (OAR-Win64-Shipping.exe, 2026-08-23)")
    w("Game files : the Data Center heist update of 2026-10-01 (the exe did not change)")
    w("Console    : opened with ~ once the OARCommands installer (UE4SS) is in, or with UUU")
    w("Built from : a UUU object + console variable dump, the game's exe and its pak files")
    w("Commands are not case-sensitive. Spawning is in OAR_Spawn_Commands.txt.")
    w("")
    w("HOW 'WORKS' WAS DECIDED")
    w("  * Cheat/exec commands: each one's code was read out of the running game.")
    w("    The ones that are empty in this build are listed in section 5 (DOES NOTHING).")
    w("  * Console variables + commands (sections 6 and 7): everything the game registered,")
    w("    minus the one Cheat-flagged cvar (blocked in shipping) and 13 'Unregistered' ini")
    w("    leftovers that do nothing.")
    w("  * Gameplay cheats only really apply when you are HOST or SOLO. As a client the")
    w("    server overrides you: god won't stop damage, ghost rubber-bands, summons are only")
    w("    on your screen.")
    w("  * Cheats need a cheat manager. The OARCommands install creates one for you; without it,")
    w("    type  EnableCheats  (works in solo play only).")
    w("  * The mod adds: bind / unbind / unbindall, summon <name> [count], summonstop, dupe [count],")
    w("    setmoney / addmoney / setlevel / setxp / maxskills / unlockall, noclip, revive,")
    w("    selectmap / forcemap, commandsharing / host, reloadconfig. All of their values and code are in")
    w("    Mods\\OARCommands\\config.lua, which you can edit. See the project README.")
    w("")
    w("QUICK START")
    w("-" * 78)
    for usage, desc in QUICK_START:
        L.extend(row(usage, desc, 32))
    w("")

    by_name = {o["name"]: o for o in objs if o["type"] == "Class"}
    order = list(DESC)
    for i, (cls, title) in enumerate(CLASS_TITLES.items()):
        o = by_name.get(cls)
        fns = [f for f in (o["funcs"] if o else []) if f["flags"] & FUNC_EXEC and f["name"] not in STUBBED]
        if not fns:
            continue
        w("")
        if i == 0:
            w(f"1. {title}")
            w("-" * 78)
        else:
            if i == 1:
                w("2. OTHER COMMANDS")
                w("-" * 78)
            w(f"  [{title}]")
        fns.sort(key=lambda f: order.index(f["name"]) if f["name"] in order else 999)
        for f in fns:
            L.extend(row((f["name"] + " " + fmt_params(f["params"])).strip(), DESC.get(f["name"], "")))
    w("")
    words = {x.upper() for ws in engine_words.values() for x in ws}
    w("3. ENGINE TEXT COMMANDS  (complete: every command word compiled into this game's exe)")
    w("-" * 78)
    used = set(COVERED_ELSEWHERE)
    for title, entries in ENGINE_COMMANDS:
        present = [(k, u, d_) for k, u, d_ in entries if k in words]
        if not present:
            continue
        w(f"  [{title}]")
        for key, usage, desc in present:
            used.add(key)
            L.extend(row(usage, desc))
        w("")
    rest = sorted(x for x in words - used if re.fullmatch(r"[A-Z][A-Z0-9_.]{2,}", x))
    if rest:
        w("  [ALSO RECOGNISED  (sub-options of the commands above, e.g. stat budget, log list)]")
        for i in range(0, len(rest), 6):
            w("    " + "  ".join(x.lower() for x in rest[i:i + 6]))
    if maps:
        w("")
        w("  Maps in the game's pak (open <name> in solo, servertravel <name> as host).")
        w("  Includes unreleased / test maps; those may be empty or broken:")
        colw = max(len(m) for m in maps) + 2
        for i in range(0, len(maps), 3):
            w("    " + "".join(f"{m:<{colw}}" for m in maps[i:i + 3]).rstrip())

    w("")
    w("4. HANDY SETTINGS (type the name alone to see its current value)")
    w("-" * 78)
    lower = {k.lower(): k for k in cvars}
    for name in USEFUL_CVARS:
        k = lower.get(name.lower())
        if not k:
            continue
        v = cvars[k]
        cur = "" if v["type"] == "Command" else f"= {v.get('value')}"
        w(f"  {k:<34} {cur:<10} {first_line(v.get('Helptext'), 110)}")
    w("  (ShowFlag.X takes 0 = off, 1 = on, 2 = default)")

    w("")
    w("5. DOES NOTHING IN THIS BUILD (compiled out or not reachable)")
    w("-" * 78)
    for cls in ["Engine.GameInstance", "Engine.GameMode", "Engine.PlayerController", "Engine.CheatManager",
                "Engine.GameViewportClient", "Engine.HealthSnapshotBlueprintLibrary"]:
        o = by_name.get(cls)
        if not o:
            continue
        for f in o["funcs"]:
            if not f["flags"] & FUNC_EXEC:
                continue
            why = None
            if f["name"] in STUBBED:
                why = "empty function in shipping build"
            elif cls in NOT_ROUTED:
                why = NOT_ROUTED[cls]
            if why:
                L.extend(row(f["name"], why))
    for name, why in [("obj ... / ke ... / help / DumpConsoleCommands", "not compiled into this exe"),
                      ("viewmode shadercomplexity (and other debug view modes)", "blocked in shipping"),
                      ("r.Shaders.SkipCompression", "Cheat-flagged cvar, blocked in shipping")]:
        L.extend(row(name, why))
    w("")
    w("  Registered but best left alone:")
    for name, why in AVOID.items():
        w(f"    {name:<42} {why}")

    usable = {k: v for k, v in cvars.items()
              if "Unregistered" not in v.get("Flags", []) and "Cheat" not in v.get("Flags", [])}
    cmds = {k: v for k, v in usable.items() if v["type"] == "Command"}
    vars_ = {k: v for k, v in usable.items() if v["type"] != "Command"}

    def grouped(d):
        g = defaultdict(list)
        for k in d:
            g[k.split(".")[0].lower() if "." in k else "(no prefix)"].append(k)
        return sorted(g.items(), key=lambda kv: kv[0])

    w("")
    w(f"6. ALL CONSOLE COMMANDS FROM THE CVAR DUMP ({len(cmds)})")
    w("-" * 78)
    for grp, keys in grouped(cmds):
        w(f"  [{grp}]")
        for k in sorted(keys, key=str.lower):
            w(f"    {k:<52} {first_line(cmds[k].get('Helptext'), 100)}")

    w("")
    w(f"7. ALL CONSOLE VARIABLES ({len(vars_)})  usage: <name> <value>   or just <name> to read it")
    w("-" * 78)
    w("  Format: name = current value [type]  first line of help. Full help: UUU_CVarsDump.txt")
    for grp, keys in grouped(vars_):
        w(f"  [{grp}]")
        for k in sorted(keys, key=str.lower):
            v = vars_[k]
            val = v.get("value")
            if isinstance(val, float):
                val = f"{val:g}"
            w(f"    {k} = {val} [{v['type']}]  {first_line(v.get('Helptext'), 110)}")
    return "\n".join(L) + "\n", len(cmds), len(vars_)


# ---------------------------------------------------------------- spawn list

SYSTEM = {
    "RobberGM_C", "RobberGameState_C", "RobberPlayerState_C", "RobberController_C", "RobberCameraManager_C",
    "CameraController_C", "LobbyManager_C", "Guardmanager_C", "BP_CrateManager_C", "PoliceWaveSpawner_C",
    "BP_AmbienceSoundController_C", "BP_AmbientSoundZone_C", "BP_AreaBoundsBlockingVolume_C",
    "RestrictedAreaVolume_C", "PlayerSpawnSpot_C", "PoliceSpawnLocation_C", "GuardEscortPoint_C",
    "GuardPatrolPoint_C", "GuardScanPoint_C", "WeaponBagSpawnPoint_C", "BP_ThumbnailGenerator_SkySphere_C",
    "MagicLeapARPinInfoActor_C", "BP_Sky_Sphere_C", "SensingActor_C", "UnlockCollision_C", "BP_TowSpline_C",
    "Instruction_WineStore_C", "Instruction_base_C", "Setup3DWidgetBP_C", "MenuCamera_C", "MainMenuPlayer_C",
    "MenuPlayerPreview_C", "CameraSpectator_C", "BP_CarValueOverlapper_C", "EndOfTruckBase_C",
    "EndOfTruck_Default_C", "ToolSpot_C", "ToolSpotMesh_C", "BulletCasing_C", "BulletTrace_C",
    "LaserBeamVisual_C", "LeaveButton_C", "ShopItemPreview_C", "MenuWeaponBoard_C", "GunBase_C",
    "PoliceGunBase_C", "AttachmentBase_C", "PickupItem_base_C",
}

def _under(path, *folders):
    return bool(path) and path.startswith(tuple(f"/Game/{f}/" for f in folders))


# Each test gets (name, parent chain incl. native classes, full class path or "").
CATEGORIES = [
    ("LOOT AND VALUABLES (pickup items: grab and bag them)",
     lambda n, p, path: "Money_base_C" in p or "BP_draggable_militaryCrate_C" in p
     or n in {"Money_base_C", "Duffelbag_C", "BP_draggable_militaryCrate_C"}),
    ("EXPLOSIVES", lambda n, p, path: n.startswith(("BP_Explosive", "BP_Explodable", "BP_DraggableExplosive",
                                                   "Explosive_"))),
    ("TOOLS AND EQUIPMENT (mostly pickup items)",
     lambda n, p, path: "PickupItem_base_C" in p or n in {"NPC_ammopack_C", "WeaponBag_C"}),
    ("NPCS AND CHARACTERS (may stand idle if the game does not give them AI)",
     lambda n, p, path: "Character" in p and n != "MainMenuPlayer_C"),
    ("POLICE GEAR AND TRAPS",
     lambda n, p, path: n.startswith("PoliceGun_") or n in {"PoliceShield_C", "PoliceHelmet_C", "BlindingShield_C",
                                                           "PoliceTrap_BarbedWire_C"}),
    ("VEHICLES", lambda n, p, path: n in {"TowableCar_C", "TowableCarFront_C", "RobberTruck_C", "BP_HitchHook_C",
                                         "BP_Tugboat_Preset_C"}
     or "RobberTruck_C" in p or n.endswith(("_Vehicle_C", "_Vehicles_C"))),
    ("CRATES AND BOXES", lambda n, p, path: "BP_Crate_Base_C" in p or n == "BP_Crate_Base_C"),
    ("CASINO PROPS (slot machines, roulette, fountains...)", lambda n, p, path: "/PolygonCasino/" in path),
    ("SECURITY, DOORS, PUZZLES AND HEIST OBJECTS",
     lambda n, p, path: n in {"AlarmBP_C", "CameraBP_C", "LaserBeams_C", "Lock_C", "Lock_Alarm_C", "VaultDoor_C",
                              "Vault_DoorRectangle_C", "GarageDoor_C", "Window_Openable_C", "BreakableDisplaycase_C",
                              "BP_DestroyedDoor_C", "BP_HackingPoint_C", "BP_Powerbox_C", "BP_PowerboxSwitch_C",
                              "BP_PowerSwitch_C", "BP_switchbox_C", "BP_switchbox_switch_C", "BP_Switchbox_button_C",
                              "SecurityTagDetector_C", "SecurityTag_C", "JewelryStand_C", "PushableItem_C"}
     or n.startswith(("DoorBP", "BreakableGlass", "DisplayBreakableGlass"))
     or any(c in p for c in ("VaultDoor_C", "AlarmBP_C", "Powerbox_C", "DoorBP_C"))
     or _under(path, "BP/Puzzle", "BP/Utility", "BP/Setups", "BP/Hacking")),
    ("GUNS (world models, most are display models rather than pickups)",
     lambda n, p, path: "GunBase_C" in p or n.startswith("AttachedBackGun_")),
    ("WEAPON ATTACHMENT MODELS",
     lambda n, p, path: "AttachmentBase_C" in p or "Mag_C" in p or n == "Mag_C"),
    ("ARMOR, MASKS AND CLOTHES (cosmetic models)",
     lambda n, p, path: n.startswith(("Armor_", "Mask_", "NPCClothing_", "NPC_hair_"))),
    ("CHARMS AND EMOTE PROPS", lambda n, p, path: n.startswith(("BP_Charm_", "EmoteBPBase"))),
    ("LOBBY SHOP / MENU DISPLAY OBJECTS (spawn the shop display, not the item)",
     lambda n, p, path: n.startswith(("ShopItem_", "MenuShelf_", "Equipmentshelf_", "Shop_Skill", "Shop_skill", "Setup_",
                                      "TutorialShopItem_", "TutorialEqipmentShelf_", "TutorialEquipmentShelf_"))
     or n in {"EquipmentShelf_shelf_C", "ShopEquipmentShelf_C"}),
    ("BUILDINGS, ROADS AND STREET PROPS (big: step back first)",
     lambda n, p, path: n.startswith(("Aps_", "Apartment", "Office", "OldOffice", "Road_", "Park_", "Wall", "Block_",
                                      "Shop_Block", "Floor_", "RoofBase", "HouseBase", "Closebuilding"))
     or n in {"ParkingLot_C", "BP_Wall_C", "Sign_C"}
     or any(f in path for f in ("/BPBuildingTools/", "/BuildingBPS/", "/PolygonNightClubs/"))),
]

SYSTEM_NATIVES = {"GameModeBase", "PlayerController", "PlayerCameraManager", "GameStateBase", "PlayerState",
                  "SpectatorPawn", "MagicLeapARPinInfoActorBase"}
SYSTEM_WORDS = ("Manager", "Spawner", "Overlapper", "Instruction", "SpawnLocation", "SpawnPoint", "MacroLibrary",
                "Preview", "Skill3dWidget", "SkinIconActor", "patrolRoute", "OutfitTester", "BlurActorTest",
                "menuLoadPawn", "CinemaIKtarget", "ValuableCounter", "Ambiance")

# Native parents a Blueprint can have, expanded to their engine class chain.
NATIVE_CHAINS = {
    "Actor": ["Actor"], "StaticMeshActor": ["StaticMeshActor", "Actor"], "Pawn": ["Pawn", "Actor"],
    "Character": ["Character", "Pawn", "Actor"], "SpectatorPawn": ["SpectatorPawn", "DefaultPawn", "Pawn", "Actor"],
    "GameModeBase": ["GameModeBase", "Info", "Actor"], "GameStateBase": ["GameStateBase", "Info", "Actor"],
    "PlayerState": ["PlayerState", "Info", "Actor"], "PlayerController": ["PlayerController", "Controller", "Actor"],
    "PlayerCameraManager": ["PlayerCameraManager", "Actor"],
    "MagicLeapARPinInfoActorBase": ["MagicLeapARPinInfoActorBase", "Actor"],
}

NATIVE_PICKS = [
    ("DefaultPawn", "a floating sphere pawn"),
    ("PointLight", "a light bulb, lights up the area"),
    ("SpotLight", "a spotlight pointing where you face"),
    ("RectLight", "a rectangular area light"),
    ("TextRenderActor", "3D text that says 'Text'"),
    ("CableActor", "a dangling physics cable"),
    ("ExponentialHeightFog", "adds a second layer of fog"),
    ("CameraActor", "a camera (look through it with ViewActor <its name>)"),
]



def spawnable_classes(objs):
    """Every Blueprint actor class: from the pak's asset registry when readable, else the dump.

    Returns (records, from_registry). A record is dict(name, path, parents, loaded).
    """
    loaded = {o["name"].split(".")[-1]: o for o in objs
              if o["type"] == "BlueprintGeneratedClass" and "Actor" in o["parents"]}
    try:
        bps = oar_registry.blueprint_classes()
    except (OSError, ValueError) as e:
        print(f"asset registry not readable ({e}); spawn list limited to the dump")
        return [dict(name=n, path="", parents=o["parents"], loaded=True) for n, o in loaded.items()], False

    by_name = {b["name"]: b for b in bps}
    records = []
    for b in bps:
        chain, cur, seen = [], b, set()
        while cur["name"] not in seen:
            seen.add(cur["name"])
            parent = cur["parent"]
            if parent in by_name and parent not in seen:
                chain.append(parent)
                cur = by_name[parent]
            else:
                chain += NATIVE_CHAINS.get(cur["native"], [cur["native"]])
                break
        if "Actor" not in chain:
            continue
        records.append(dict(name=b["name"], path=b["path"], parents=chain, loaded=b["name"] in loaded))
    known = {r["name"] for r in records}
    for n, o in loaded.items():                 # anything loaded that the registry lacks
        if n not in known:
            records.append(dict(name=n, path="", parents=o["parents"], loaded=True))
    return records, True


def spawn_line(rec, dupes):
    n = rec["name"]
    line = f"summon {n}"
    if n in dupes:
        line += "   (two classes share this name; you may get the other one)"
    return "  " + line


def build_spawn(objs):
    records, from_registry = spawnable_classes(objs)
    native_names = {o["name"].split(".")[-1].lower() for o in objs if o["type"] == "Class" and "Actor" in o["parents"]}
    counts = defaultdict(int)
    for r in records:
        counts[r["name"]] += 1
    dupes = {n for n, c in counts.items() if c > 1}

    buckets = OrderedDict((t, []) for t, _ in CATEGORIES)
    system, other = [], []
    for r in records:
        n, p, path = r["name"], r["parents"], r["path"]
        if n in SYSTEM or any(x in p for x in SYSTEM_NATIVES) or any(word in n for word in SYSTEM_WORDS):
            system.append(r)
            continue
        for title, test in CATEGORIES:
            if test(n, p, path):
                buckets[title].append(r)
                break
        else:
            other.append(r)

    L = []
    w = L.append
    w("ONE-ARMED ROBBER: SPAWN COMMANDS")
    w("=" * 78)
    if from_registry:
        w(f"All {len(records)} spawnable Blueprints in the game, read from the game's asset registry.")
    else:
        w("Only the Blueprints loaded in the object dump (the asset registry could not be read).")
    w("")
    w("HOW TO USE (with the OARCommands mod installed)")
    w("  summon <name> [count]     e.g.  summon Goldbar_C   or   summon goldbar 10")
    w("    Works on any map: the mod loads the thing first. You can drop the _C, use a unique")
    w("    start of the name (gold), or a full /Game/... path. count copies spawn 0.15 s apart.")
    w("    Capitals, spaces and underscores do not matter:  summon gold bar  is  summon goldbar.")
    w("  summon <object> [count]   e.g.  summon mona lisa   or   summon vault keycard")
    w("    One class with its own look and values; the names are in the OBJECTS section below.")
    w("  dupe [count]              copy whatever is under your crosshair, with its look and values")
    w("  summonstop                stop a batch that is still spawning")
    w("")
    w("  Without the mod, the game's own summon needs the exact class name (Goldbar_C) and only")
    w("  finds things that are already loaded on the current map.")
    w("")
    w("RULES")
    w("  * Host or solo only. As a client the spawn exists on your screen only.")
    w("  * Remove something: look at it and type  DestroyTarget   (all copies:  DestroyAll <Name_C>)")
    w("  * Names ending in _base_C / Base_C are templates: they often spawn blank or broken.")
    w("  * Things built for one heist (keypads, containers, elevators) may need that map's")
    w("    other pieces to actually work.")
    w("  * OAR_Full_Object_List.txt shows which maps each thing is placed on.")

    objects, object_maps = make_objects.build(oar_pak.Pak())
    with_data = [e for e in objects if e[4]]
    plain_names = [e for e in objects if not e[4]]
    w("")
    w("")
    w(f"OBJECTS: ONE CLASS WITH ITS OWN LOOK AND VALUES  [{len(with_data)}]")
    w("-" * 78)
    w("  Many items are one class placed with different data. Every Artwork is a Statue_museum_C;")
    w("  the mod spawns the class and then gives the copy that object's mesh, materials, size and")
    w("  values. These are all the different ones placed in the game's maps.")
    w("")
    by_class = defaultdict(list)
    for key, cls, _path, label, _data in with_data:
        by_class[cls].append((key, label))
    for cls in sorted(by_class, key=str.lower):
        w(f"  {cls}")
        for key, label in sorted(by_class[cls]):
            where = ", ".join(object_maps.get(key, []))
            w(f"    summon {key:<44} {label}" + (f"   [{where}]" if where else ""))
    w("")
    w(f"  IN-GAME NAMES of plain classes (the text you see when you look at the item)  [{len(plain_names)}]")
    for key, cls, _path, label, _data in sorted(plain_names):
        w(f"    summon {key:<44} {cls}")

    def section(title, recs):
        if not recs:
            return
        w("")
        w("")
        w(f"{title}  [{len(recs)}]")
        w("-" * 78)
        for r in sorted(recs, key=lambda r: (r["name"].lower(), r["path"])):
            w(spawn_line(r, dupes))

    for title, recs in buckets.items():
        section(title, recs)
    section("OTHER / MISC", other)
    w("")
    w("")
    w("UNREAL ENGINE BUILT-IN ACTORS (always loaded, plain summon works)")
    w("-" * 78)
    for n, desc in NATIVE_PICKS:
        if n.lower() in native_names:
            w(f"  summon {n:<34} {desc}")
    section("BEHIND-THE-SCENES CLASSES (they spawn, but do nothing useful or can break the round)", system)
    total = sum(len(v) for v in buckets.values()) + len(other) + len(system)
    return "\n".join(L) + "\n", total, len(records)


PAK = oar_pak.PAK


def pak_maps():
    """Map names from the pak's file index (plain text in this 4.27 pak)."""
    found, tail = set(), b""
    pat = re.compile(rb"([A-Za-z0-9_-]{2,60})\.umap")
    try:
        with open(PAK, "rb") as f:
            while True:
                chunk = f.read(64 << 20)
                if not chunk:
                    break
                buf = tail + chunk
                found.update(m.decode() for m in pat.findall(buf))
                tail = buf[-80:]
    except OSError:
        return []
    return sorted(found, key=str.lower)


def main():
    objs = parse_objects()
    maps = pak_maps()
    with open(CVAR_DUMP, encoding="utf-8") as f:
        cvars = json.load(f)
    cmd_text, n_cmds, n_vars = build_commands(objs, cvars, maps, oar_exe_commands.engine_commands())
    spawn_text, n_listed, n_bp = build_spawn(objs)
    assert n_listed == n_bp, (n_listed, n_bp)
    with open(os.path.join(OUT_DIR, "OAR_Working_Commands.txt"), "w", encoding="utf-8") as f:
        f.write(cmd_text)
    with open(os.path.join(OUT_DIR, "OAR_Spawn_Commands.txt"), "w", encoding="utf-8") as f:
        f.write(spawn_text)
    print(f"commands: {n_cmds} console commands, {n_vars} cvars; spawn: {n_listed} blueprint actors")


if __name__ == "__main__":
    main()
