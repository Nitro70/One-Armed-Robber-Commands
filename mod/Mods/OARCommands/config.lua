--[[
    OAR Commands: config.lua

    This file IS the mod. Every command OAR Commands adds to One-armed robber is written out here
    in full, and all of it can be changed:

        1. VALUES        the numbers, keys, lists and names the commands use
        2. THE COMMANDS  the complete code of every command, one section each

    After saving a change, type   reloadconfig   in the game's console (~). No restart needed.

    - A mistake does not break the game. If the file has an error, reloadconfig prints the error
      with its line number and the commands from before keep working. If one command fails while
      it runs, the console shows "<command> failed: <error>".
    - reloadconfig default   loads config.default.lua, the untouched copy next to this file,
      without changing this file. To go back for good, copy it over this file, or uninstall and
      install OAR Commands again (uninstalling removes this file, installing puts the default back).
    - An update of OAR Commands that comes with a new default config saves your edited file as
      config.old.lua and installs the new one.
    - Things that stay as they are across reloadconfig: your binds (binds.txt), the command
      sharing level, whether you are in noclip, and running summon batches. A game restart resets
      everything except the binds.
    - The big name tables are separate files in the Scripts folder and are read again on every
      reloadconfig too: spawnables.lua and objects.lua (summon), unlockables.lua (maxskills,
      unlockall) and maps.lua (selectmap, forcemap). So is gui.lua, which builds the window of
      the in-game menu (opengui); what the menu shows is in this file (its last section).

    The language is Lua 5.4, running inside UE4SS 3.0.1. What Scripts\main.lua gives this file:

        Core.Command(name, fn)       a console command; fn(FullCommand, Parameters, Ar)
        Core.Intercept(name, fn)     look at an engine command first; return true = handled
        Core.Hook(path, fn)          run fn when the game calls that function
        Core.OnNewObject(class, fn)  run fn(object) for each new object of a class
        Core.KeyBind(keyName, fn)    run fn when a key is pressed
        Core.OwnCommand(name)        the current code of one of the commands here
        Core.Data(name)              load Scripts\<name>.lua
        Core.State                   a table that survives reloadconfig
        Core.Say(Ar, text)           print to the console and to UE4SS.log
        Core.Print(text)             print to UE4SS.log only

    Good to know about UE4SS 3.0.1 before changing code:
        - It cannot grow a game list from Lua. Indexing one past the end of a list does not add
          an element, it reads or writes memory that is not the list's. Only an EMPTY list
          indexed at 1 grows correctly. Use the game's own functions to add things.
        - Setting a struct member to a Lua table that holds a class throws. Set members one by one.
        - Functions with "out" parameters want a Lua table for each of them.
        - A console command's code must finish with  return true .
--]]

local Core = ...
local State = Core.State
local Say, Print = Core.Say, Core.Print

--==================================================================================================
-- 1. VALUES
--==================================================================================================
local V = {
    ------------------------------------------------------------------------------------------
    -- bind
    ------------------------------------------------------------------------------------------
    BindCheckRetries = 6,            -- game ticks to wait for a key press to reach the game
    BindCheckDelayMs = 16,           -- time between those checks
    -- Extra spellings for keys: what you may type -> the UE4SS key name
    KeyAliases = {
        SPACEBAR = "SPACE", ENTER = "RETURN", ESC = "ESCAPE", DELETE = "DEL", INSERT = "INS",
        PAGEUP = "PAGE_UP", PGUP = "PAGE_UP", PAGEDOWN = "PAGE_DOWN", PGDN = "PAGE_DOWN",
        LEFT = "LEFT_ARROW", RIGHT = "RIGHT_ARROW", UP = "UP_ARROW", DOWN = "DOWN_ARROW",
        CAPSLOCK = "CAPS_LOCK", TILDE = "OEM_THREE", MOUSE1 = "LEFT_MOUSE_BUTTON", MOUSE2 = "RIGHT_MOUSE_BUTTON",
        MOUSE3 = "MIDDLE_MOUSE_BUTTON", MIDDLEMOUSE = "MIDDLE_MOUSE_BUTTON", MOUSE4 = "XBUTTON_ONE",
        MOUSE5 = "XBUTTON_TWO", THUMBMOUSE = "XBUTTON_ONE",
    },

    ------------------------------------------------------------------------------------------
    -- summon, spawn, dupe
    ------------------------------------------------------------------------------------------
    SummonDelayMs = 150,             -- time between two copies of a batch
    SummonMax = 500,                 -- most copies one command spawns
    -- Where an object with its own data appears: this far in front of where you look from, and
    -- this much higher (the engine's own summon uses the same two numbers).
    SummonForward = 72,
    SummonUp = 15,
    -- When a copy gets a different mesh than its class normally has, the host marks that mesh
    -- component as sent over the network, so guests see the new mesh too. Materials are never
    -- sent by the engine, so guests may see the mesh in its normal colours. false = host only.
    CopyLookToGuests = true,

    ------------------------------------------------------------------------------------------
    -- aiming: dupe, and a guest's destroytarget and teleport when the host runs them
    ------------------------------------------------------------------------------------------
    AimDistance = 50000.0,           -- how far the line from the camera reaches
    AimTraceChannel = 0,             -- 0 = Visibility (ETraceTypeQuery::TraceTypeQuery1)
    TeleportOffset = 4,              -- how far off the surface a guest's teleport lands

    ------------------------------------------------------------------------------------------
    -- setmoney, addmoney, setlevel, setxp, maxskills, unlockall
    ------------------------------------------------------------------------------------------
    MaxCashAndLevel = 2000000000,    -- the game stores both as 32-bit numbers; the gap keeps payouts from overflowing
    FinishedResearch = 1000000000.0, -- research progress far past any skill's need (150 to 450)
    -- setxp all: the most extra XP one player can get per heist. The game levels up one level at
    -- a time with a function that calls itself, so far more could crash a low-level player's game
    -- on the win screen. 100000 is about 75 levels for a new player.
    SetXPAllMax = 100000,

    ------------------------------------------------------------------------------------------
    -- setammo, truckmoney
    ------------------------------------------------------------------------------------------
    AmmoMax = 999999,                -- most spare ammo setammo gives one gun
    -- The most the truck can hold with truckmoney. Every player's win screen adds the whole take
    -- to their own cash, a 32-bit number; this leaves room even at the mod's top cash.
    TruckMoneyMax = 100000000,

    ------------------------------------------------------------------------------------------
    -- bringloot: how the loot is stacked over the truck's money area
    ------------------------------------------------------------------------------------------
    BringLootColumns = 5,            -- pieces side by side
    BringLootRows = 4,
    BringLootSpacing = 45,           -- distance between pieces
    BringLootLayerHeight = 35,       -- each further layer this much higher

    ------------------------------------------------------------------------------------------
    -- doors
    ------------------------------------------------------------------------------------------
    DoorAimRadius = 150,             -- doors unlock/open/close: a door this close to where you look counts
    GuardAimRadius = 150,            -- guards kill/remove: a guard this close to where you look counts
    DoorOpenTime = 0.6,              -- seconds a door takes to swing (the game's own speed)

    ------------------------------------------------------------------------------------------
    -- opengui: the menu's looks. Empty = the defaults in Scripts\gui.lua (Kit.DefaultStyle).
    -- Anything from there can be set here, e.g. Menu = { width = 1200, accent = { 0.3, 0.7, 1, 1 } },
    ------------------------------------------------------------------------------------------
    Menu = {},
    ChangeLog = "OAR\\Saved\\SaveGames\\OARCommands-changes.log",   -- inside your local application data folder

    ------------------------------------------------------------------------------------------
    -- noclip
    ------------------------------------------------------------------------------------------
    NoclipKeysUp = { "SpaceBar" },                         -- Unreal key names
    NoclipKeysDown = { "LeftControl", "RightControl" },
    NoclipKeysFast = { "LeftShift", "RightShift" },
    NoclipFastMultiplier = 2,        -- speed while a fast key is held, when NoclipFastSpeed is 0
    NoclipSpeed = 0,                 -- flying speed; 0 = your walking speed
    NoclipFastSpeed = 0,             -- flying speed while Shift is held; 0 = NoclipFastMultiplier times the above
    -- The event of your character that runs every frame; noclip adds up and down from it.
    NoclipFrameEvent = "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:InpAxisEvt_MoveForward_K2Node_InputAxisEvent_0",

    ------------------------------------------------------------------------------------------
    -- revive timing (when you host)
    ------------------------------------------------------------------------------------------
    -- A teammate's revive finishes when the reviver's bar does, also when the reviver has the
    -- Healing Touch skill (the game itself waits for the downed player's own revive time, so a
    -- faster bar runs out first and letting go then cancels the revive). false = the game's timing.
    ReviveMatchesBar = true,

    ------------------------------------------------------------------------------------------
    -- commandsharing, host
    ------------------------------------------------------------------------------------------
    ShareLevelAtStart = 0,           -- the sharing level every time the game starts (0 = off)
    ShareTimeoutMs = 1500,           -- guest: how long to wait for the host's answer
    ShareSilentSeconds = 60,         -- guest: after a host stays silent, skip it for this long
    ShareMaxMessage = 120,           -- longest request; a longer command runs on your own game
    -- The next three must be the same for the host and the guest, or they cannot talk.
    ShareProtocol = "oar1",
    ShareReplyPrefix = "[OAR host] ",
    ShareNoticePrefix = "[OAR] ",
    ShareLevelNames = { [0] = "off", "player commands", "player and world commands", "everything except the block list" },
    -- Level 1 and up: commands that act on the guest who typed them
    SharePlayerCommands = { "summon", "spawn", "summonstop", "dupe", "revive", "noclip", "god", "ghost", "fly", "walk",
                            "teleport", "destroytarget" },
    -- Level 2 and up: commands that change the game for everyone
    ShareWorldCommands = { "destroyall", "slomo", "playersonly", "changesize", "doors", "door", "reviveall", "healall",
                           "godall", "alarm", "cops", "cameras", "codes", "bringloot", "guards" },
    -- Never passed to the host, at any level
    ShareBlockedCommands = {
        -- would close, move or cut off the host's game
        "exit", "quit", "open", "travel", "servertravel", "disconnect", "reconnect", "switchlevel", "restartlevel",
        "streammap", "demoplay", "demorec", "selectmap", "forcemap",
        -- would touch the host's files or crash it
        "exec", "deletecloudfiles", "doublefreefindercrash", "mallocframeprofiler", "purchase", "debug",
        -- this mod's commands that always stay on your own game
        "setmoney", "addmoney", "setlevel", "setxp", "maxskills", "unlockall", "bind", "unbind", "unbindall",
        "commandsharing", "host", "reloadconfig", "setammo", "infiniteammo", "opengui",
    },
    -- Guest shortcut: typing an engine cheat below (god, ghost...) sends it to the host by itself,
    -- as if you typed "host god". OFF by default: it registers 20 more console commands with UE4SS
    -- (both spellings of each), and UE4SS 3.0.1 only has room for about 45 per mod; with 52 the
    -- game crashed at random, even at startup (2026-10-03). "host <command>" works without it.
    ShareEngineCheatShortcuts = false,
    -- Engine cheats a guest's mod passes to the host: what you type -> the engine's own spelling.
    -- Command names match exactly, so both spellings are watched.
    ShareEngineCheats = { god = "God", ghost = "Ghost", fly = "Fly", walk = "Walk", teleport = "Teleport",
                          destroytarget = "DestroyTarget", destroyall = "DestroyAll", slomo = "Slomo",
                          playersonly = "PlayersOnly", changesize = "ChangeSize" },
    -- Commands that send the guest's camera position and angle along
    ShareAimedCommands = { "destroytarget", "dupe", "teleport", "doors", "door", "guards" },
}

--==================================================================================================
-- Your settings from the menu (Settings tab): saved in settings.lua next to this file, read here
-- every time this file loads. They win over the values above, so the values above stay the
-- defaults; the menu's Default buttons and Reset everything go back to them. Two parts:
--    commands   values from the table above (noclip speeds, spawn delay...)
--    look       the menu's colours, sizes and style (see the opengui section)
--==================================================================================================
local SETTINGS_FILE = Core.ModDir .. "/settings.lua"

local function LoadSettings()
    local f = io.open(SETTINGS_FILE, "rb")
    if not f then return { look = {}, commands = {} } end
    local text = f:read("a")
    f:close()
    local chunk = load(text, "=settings.lua", "t", {})          -- data only: it can call nothing
    local ok, t = false, nil
    if chunk then ok, t = pcall(chunk) end
    if not (ok and type(t) == "table") then
        Print("settings.lua could not be read, so the defaults are used")
        t = {}
    end
    return { look = type(t.look) == "table" and t.look or {}, commands = type(t.commands) == "table" and t.commands or {} }
end
local Saved = LoadSettings()

-- The values above as this file has them (for the menu's Default buttons), then the saved ones,
-- only for names that are in the table and of the same kind.
local VDefault = {}
for k, v in pairs(V) do VDefault[k] = v end
for k, v in pairs(Saved.commands) do
    if V[k] ~= nil and type(V[k]) == type(v) then V[k] = v end
end

local function SaveSettings()
    local function value(v)
        if type(v) == "table" then
            local parts = {}
            for _, x in ipairs(v) do parts[#parts + 1] = string.format("%.4f", x) end
            return "{ " .. table.concat(parts, ", ") .. " }"
        elseif type(v) == "string" then
            return string.format("%q", v)
        end
        return tostring(v)
    end
    local function block(name, t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        local out = { "    " .. name .. " = {" }
        for _, k in ipairs(keys) do out[#out + 1] = string.format("        %s = %s,", k, value(t[k])) end
        out[#out + 1] = "    },"
        return table.concat(out, "\n")
    end
    local text = table.concat({
        "-- OAR Commands: your settings, set in the menu (opengui > Settings).",
        "-- Delete this file to go back to the defaults.",
        "return {", block("commands", Saved.commands), block("look", Saved.look), "}", "" }, "\n")
    local f = io.open(SETTINGS_FILE, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

--==================================================================================================
-- 2. THE COMMANDS
--==================================================================================================

-- The name tables (separate files in the Scripts folder, see the top of this file)
local Spawnables = Core.Data("spawnables")
local Objects = Core.Data("objects")
local Unlockables = Core.Data("unlockables")
local Maps = Core.Data("maps")

--------------------------------------------------------------------------------------------------
-- Things several commands use
--------------------------------------------------------------------------------------------------

local Share = {}          -- command sharing; filled in further down, used by most commands

local function Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

local function Valid(object)
    return object ~= nil and object:IsValid()
end

local function Number(text)
    local n = tonumber(text or "")
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

-- A name without capitals, spaces, underscores or other signs: "Gold bar" -> "goldbar"
local function Squash(text)
    return (string.lower(text):gsub("[^%w]", ""))
end

local function Words(line)
    local words = {}
    for w in line:gmatch("%S+") do words[#words + 1] = w end
    return words
end

-- The controller the local player is driving right now. While ToggleDebugCamera is on that is the
-- debug camera's own controller; the normal one is detached then and gets no input.
local function LocalPlayerController()
    local lp = FindFirstOf("LocalPlayer")
    if lp and lp:IsValid() then
        local pc = lp.PlayerController
        if pc:IsValid() then return pc end
    end
    local all = FindAllOf("PlayerController")
    if not all then return nil end
    for _, pc in pairs(all) do
        if pc:IsValid() and pc:IsLocalController() then return pc end
    end
    return nil
end

-- Your own controller. In the debug camera the local player drives the camera's controller and
-- your real one is parked in its OriginalControllerRef.
local function Robber()
    local pc = LocalPlayerController()
    if pc and pc:GetClass():GetFName():ToString() == "DebugCameraController" then
        pc = pc.OriginalControllerRef
    end
    if pc and pc:IsValid() then return pc end
    return nil
end

-- Cheat commands (summon, destroytarget, god...) need a CheatManager on the controller. Shipping
-- builds only make one in solo play, so build it ourselves when it is missing (same as UE4SS's
-- CheatManagerEnablerMod does, but on demand, so it also covers hosted games).
local function CheatManagerFor(pc)
    local cm = pc.CheatManager
    if cm:IsValid() then return cm end
    local cls = pc.CheatClass
    if not cls:IsValid() then cls = StaticFindObject("/Script/Engine.CheatManager") end
    if cls:IsValid() then
        cm = StaticConstructObject(cls, pc, 0, 0, 0, nil, false, false, nil)
        if cm:IsValid() then
            pc.CheatManager = cm
            Print("created a cheat manager")
            return cm
        end
    end
    return nil
end

local function LoadClass(path)
    local cls = StaticFindObject(path)
    if cls and cls:IsValid() then return cls end
    LoadAsset(path)
    cls = StaticFindObject(path)
    if cls and cls:IsValid() then return cls end
    return nil
end

-- Every live object of a class AND its subclasses (UE4SS FindObjects; FindAllOf only finds the one
-- class, and some maps use subclasses, such as PlayerCharacter_Rain). No class default objects.
local RF_DEFAULT_OBJECTS = 48          -- RF_ClassDefaultObject | RF_ArchetypeObject
local function AllOf(className)
    local out = {}
    local ok, found = pcall(FindObjects, 0, className, nil, 0, RF_DEFAULT_OBJECTS, false)
    if ok and type(found) == "table" then
        for _, object in ipairs(found) do
            if Valid(object) then out[#out + 1] = object end
        end
    end
    return out
end

-- Change a replicated variable the way the game's own code does, so every player's game gets it:
-- wake the actor for the network, set the value, and mark it for sending (the game uses push
-- model replication). actor: the actor that owns object, when object is a component.
local function SetReplicated(object, name, value, actor)
    pcall(function() (actor or object):FlushNetDormancy() end)
    object[name] = value
    local ok, err = pcall(function()
        local helpers = StaticFindObject("/Script/Engine.Default__NetPushModelHelpers")
        if Valid(helpers) then helpers:MarkPropertyDirty(object, FName(name)) end
    end)
    if not ok then Print("could not mark " .. name .. " for sending: " .. tostring(err)) end
end

-- A hook on a Blueprint can only be placed once that Blueprint is loaded. HookWhenLoaded(fn)
-- runs fn now and again every time a controller gets its character (ClientRestart), until fn
-- returns true. fn places its hooks with Core.Hook, which also points hooks placed before a
-- reloadconfig at the new code.
local WaitingHooks = {}
local function HookWhenLoaded(fn)
    if not fn() then WaitingHooks[#WaitingHooks + 1] = fn end
end
Core.Hook("/Script/Engine.PlayerController:ClientRestart", function()
    for i = #WaitingHooks, 1, -1 do
        if WaitingHooks[i]() then table.remove(WaitingHooks, i) end
    end
end)

-- While the host runs a guest's command (command sharing): that guest's controller and camera.
local Guest = nil

-- The controller a command acts for and its camera pose: the guest's while the host runs a
-- guest's command (so "the door you are looking at" is the guest's door), else your own.
local function Acting()
    if Guest then return Guest.pc, Guest.pose end
    return Robber(), nil
end

-- Host: returns your controller. Guest: sends FullCommand to the host and returns nil; when the
-- host does not take it, you are told that only the host can. opts: as for Share.Relay.
local function HostOnly(Ar, what, FullCommand, opts)
    local pc = Robber()
    if pc and pc:HasAuthority() then return pc end
    if FullCommand and Share.Relay(FullCommand, Ar, nil, { aim = opts and opts.aim, hostOnly = what }) then
        Say(Ar, "Asked the host to " .. what .. " (command sharing)")
        return nil
    end
    Say(Ar, "Only the host can " .. what)
    return nil
end

--------------------------------------------------------------------------------------------------
-- bind, unbind, unbindall
--
--    bind                      list your binds
--    bind <key>                show what one key does
--    bind <key> <command>      bind a key, e.g.  bind x destroytarget
--                              several commands: bind f1 "god | ghost"
--    unbind <key>              remove one bind
--    unbindall                 remove every bind
--
-- The engine's own SetBind is compiled out of this shipping build. Binds are saved in binds.txt
-- next to this file and come back after a restart. A bind only fires when the key actually
-- reached the game (not while you type in the console or a chat box). This mod's own commands
-- run directly; anything else goes through the console.
--------------------------------------------------------------------------------------------------
local BINDS_FILE = Core.ModDir .. "/binds.txt"
local Binds = {}          -- UE4SS key name -> command line

-- UE4SS key name (Key.X) -> Unreal FKey name, for asking the game whether it received the key.
local UE_KEY = {
    SPACE = "SpaceBar", RETURN = "Enter", ESCAPE = "Escape", TAB = "Tab", BACKSPACE = "BackSpace",
    DEL = "Delete", INS = "Insert", HOME = "Home", END = "End", PAGE_UP = "PageUp", PAGE_DOWN = "PageDown",
    LEFT_ARROW = "Left", RIGHT_ARROW = "Right", UP_ARROW = "Up", DOWN_ARROW = "Down",
    CAPS_LOCK = "CapsLock", OEM_THREE = "Tilde",
    LEFT_MOUSE_BUTTON = "LeftMouseButton", RIGHT_MOUSE_BUTTON = "RightMouseButton",
    MIDDLE_MOUSE_BUTTON = "MiddleMouseButton", XBUTTON_ONE = "ThumbMouseButton", XBUTTON_TWO = "ThumbMouseButton2",
    ADD = "Add", SUBTRACT = "Subtract", MULTIPLY = "Multiply", DIVIDE = "Divide", DECIMAL = "Decimal",
}
local KeyAliases = {}
for typed, key in pairs(V.KeyAliases) do KeyAliases[typed] = key end
do
    local digits = { "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }
    local digitsUE = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
    for i = 1, 10 do
        UE_KEY[digits[i]] = digitsUE[i]
        UE_KEY["NUM_" .. digits[i]] = "NumPad" .. digitsUE[i]
        KeyAliases[tostring(i - 1)] = digits[i]
        KeyAliases["NUMPAD" .. (i - 1)] = "NUM_" .. digits[i]
        KeyAliases["NUM" .. (i - 1)] = "NUM_" .. digits[i]
    end
    for c = string.byte("A"), string.byte("Z") do UE_KEY[string.char(c)] = string.char(c) end
    for n = 1, 24 do UE_KEY["F" .. n] = "F" .. n end
end

local function KeyFromText(text)
    local k = string.upper(text or "")
    k = KeyAliases[k] or k
    if Key[k] ~= nil then return k end
    return nil
end

local function SaveBinds()
    local f = io.open(BINDS_FILE, "w")
    if not f then Print("could not write " .. BINDS_FILE) return end
    for k, cmd in pairs(Binds) do f:write(k, "=", cmd, "\n") end
    f:close()
end

-- Run a bound command line. "a | b" runs both; our own commands are called directly, anything
-- else goes through the normal console path (KismetSystemLibrary::ExecuteConsoleCommand).
local function RunCommandLine(pc, line)
    for part in line:gmatch("[^|]+") do
        local text = part:match("^%s*(.-)%s*$")
        local words = Words(text)
        local name = words[1] and string.lower(table.remove(words, 1))
        local own = name and Core.OwnCommand(name)
        if own then
            local ok, problem = pcall(own, text, words, nil)
            if not ok then Print(name .. " failed: " .. tostring(problem)) end
        elseif name then
            CheatManagerFor(pc)         -- binds are usually cheat commands (destroytarget, god...)
            local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            if ksl:IsValid() then ksl:ExecuteConsoleCommand(pc, text, pc) end
        end
    end
end

local function RunBound(keyName, attempt)
    local cmd = Binds[keyName]
    if not cmd then return end
    local pc = LocalPlayerController()
    if not pc then return end
    -- While the menu (opengui) is open the game gets no keys, the menu has them, so the check
    -- below would never pass: only a key bound to opengui works then, and closes it.
    -- Not while you type in its search or amount boxes (UE4SS sees every key typed there).
    local menu = State.menu
    if menu and menu.open then
        if cmd:lower():find("opengui", 1, true) and not menu:Typing() then RunCommandLine(pc, "opengui") end
        return
    end
    local ueKey = UE_KEY[keyName]
    if ueKey then
        local fkey = { KeyName = FName(ueKey) }
        if not (pc:IsInputKeyDown(fkey) or pc:WasInputKeyJustPressed(fkey)) then
            -- Not (yet) seen by the game: either input is still on its way, or the console/a menu has it.
            if attempt < V.BindCheckRetries then
                ExecuteWithDelay(V.BindCheckDelayMs, function()
                    ExecuteInGameThread(function() RunBound(keyName, attempt + 1) end)
                end)
            end
            return
        end
    end
    RunCommandLine(pc, cmd)
end

-- A key runs its bind. While the menu (opengui) is open it has the keys instead: Escape closes
-- it, and the left mouse button is a click in it (only counted here; the menu runs the button
-- under the mouse on its next frame). This runs on UE4SS's key thread, so it never calls the game.
local function Watch(keyName, quiet)
    local shared = Core.KeyBind(keyName, function()
        local menu = State.menu
        if menu and menu.open then
            if keyName == "ESCAPE" then
                -- not while you type in the Code tab's editor (Escape there means "stop typing")
                ExecuteInGameThread(function() if menu.open and not menu:EditingCode() then menu:Close() end end)
                return
            elseif keyName == "LEFT_MOUSE_BUTTON" then
                menu.clicks = (menu.clicks or 0) + 1
                return
            end
        end
        if Binds[keyName] then
            ExecuteInGameThread(function() RunBound(keyName, 0) end)
        end
    end)
    if shared and not quiet then Print(keyName .. " is also used by another UE4SS mod") end
end

-- Every key a bind is likely to use is watched from the start. UE4SS reads its watched keys on
-- its own thread, and adding one while it reads them (bind, or the menu's Binds tab, in the
-- middle of a game) is not safe; watched from the start, a new bind only fills in its command.
-- A watched key without a bind does nothing.
local START_KEYS = { "SPACE", "RETURN", "TAB", "BACKSPACE", "DEL", "INS", "HOME", "END", "PAGE_UP", "PAGE_DOWN",
                     "LEFT_ARROW", "RIGHT_ARROW", "UP_ARROW", "DOWN_ARROW", "CAPS_LOCK", "MIDDLE_MOUSE_BUTTON",
                     "XBUTTON_ONE", "XBUTTON_TWO", "ADD", "SUBTRACT", "MULTIPLY", "DIVIDE", "DECIMAL" }
do
    for c = string.byte("A"), string.byte("Z") do START_KEYS[#START_KEYS + 1] = string.char(c) end
    for n = 1, 24 do START_KEYS[#START_KEYS + 1] = "F" .. n end
    for _, d in ipairs({ "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }) do
        START_KEYS[#START_KEYS + 1] = d
        START_KEYS[#START_KEYS + 1] = "NUM_" .. d
    end
end

local function LoadBinds()
    local f = io.open(BINDS_FILE, "r")
    if not f then return end
    for line in f:lines() do
        local k, cmd = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and cmd ~= "" and Key[k] ~= nil then
            Binds[k] = cmd
            Watch(k)
        end
    end
    f:close()
end

local function ListBinds(Ar)
    local keys = {}
    for k in pairs(Binds) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then
        Say(Ar, "No binds. Usage: bind <key> <command>   e.g.  bind x destroytarget")
        return
    end
    for _, k in ipairs(keys) do Say(Ar, string.format("%s = %s", k, Binds[k])) end
end

Core.Command("bind", function(FullCommand, Parameters, Ar)
    if #Parameters == 0 then ListBinds(Ar) return true end
    local keyName = KeyFromText(Parameters[1])
    if not keyName then
        Say(Ar, "Unknown key '" .. tostring(Parameters[1]) .. "'. Examples: x, f1, 5, numpad5, space, mouse4")
        return true
    end
    local cmd = FullCommand:match("^%s*%S+%s+%S+%s+(.-)%s*$")
    if not cmd or cmd == "" then
        Say(Ar, keyName .. " = " .. (Binds[keyName] or "(nothing)"))
        return true
    end
    cmd = cmd:gsub('^"(.*)"$', "%1")
    Binds[keyName] = cmd
    Watch(keyName)
    SaveBinds()
    Say(Ar, "Bound " .. keyName .. " to: " .. cmd)
    return true
end)

Core.Command("unbind", function(FullCommand, Parameters, Ar)
    local keyName = KeyFromText(Parameters[1])
    if not keyName then Say(Ar, "Usage: unbind <key>") return true end
    Binds[keyName] = nil
    SaveBinds()
    Say(Ar, "Unbound " .. keyName)
    return true
end)

Core.Command("unbindall", function(FullCommand, Parameters, Ar)
    Binds = {}
    SaveBinds()
    Say(Ar, "Removed every bind")
    return true
end)

--------------------------------------------------------------------------------------------------
-- An object's data: what makes one Artwork a statue and another one a painting
--
-- Many things in the game are one class with different data on each copy: its meshes and
-- materials, its size, and its Blueprint variables (its value, a keycard's name...). A plain
-- summon of the class only ever gives the class's default look. summon with a name from
-- objects.lua, and dupe, spawn the class and then put that data on the new copy.
--
--    data = { props = { { name, value }, ... },          Blueprint variables of the actor
--             comps = { [component name] = { mesh = <mesh>, skeletal = true or nil,
--                                            materials = { [slot] = <material> },
--                                            scale = { X, Y, Z }, props = { { name, value }, ... } } } }
--
-- What is copied by dupe: every Blueprint variable that is a number, a yes/no, text, a name, a
-- reference to an asset or a class, or a struct of plain numbers (vector, rotation, colour); and
-- for every mesh component its mesh, materials and size. Not copied: references to other objects
-- in the map, lists, and the engine's own properties (position, owner, network role).
--------------------------------------------------------------------------------------------------
local function EngineClass(name)
    return StaticFindObject("/Script/Engine." .. name)
end

local function IsKind(object, className)
    local cls = EngineClass(className)
    return Valid(cls) and object:IsA(cls)
end

local function IsBlueprintClass(cls)
    return Valid(cls) and cls:GetClass():GetFName():ToString() == "BlueprintGeneratedClass"
end

-- The components of an actor by name: its root and everything its Blueprint added.
local function ComponentsOf(actor)
    local out = {}
    local function add(c)
        if Valid(c) then out[c:GetFName():ToString()] = c end
    end
    pcall(function() add(actor:K2_GetRootComponent()) end)
    pcall(function()
        local list = actor.BlueprintCreatedComponents
        for i = 1, list:GetArrayNum() do add(list[i]) end
    end)
    return out
end

-- A struct made only of numbers as a Lua table (a colour, a vector, a rotation); nil for any other.
local STRUCT_SHAPES = { { "R", "G", "B", "A" }, { "X", "Y", "Z", "W" }, { "X", "Y", "Z" }, { "Pitch", "Yaw", "Roll" },
                        { "X", "Y" } }
local function PlainStruct(value)
    for _, shape in ipairs(STRUCT_SHAPES) do
        local t = {}
        local ok = pcall(function()
            for _, field in ipairs(shape) do
                local v = value[field]
                if type(v) ~= "number" then error("not a number") end
                t[field] = v
            end
        end)
        if ok then return t end
    end
    return nil
end

local COPIED_AS_IS = { "IntProperty", "Int64Property", "Int8Property", "Int16Property", "UInt16Property",
                       "UInt32Property", "UInt64Property", "FloatProperty", "DoubleProperty", "BoolProperty",
                       "ByteProperty", "EnumProperty", "NameProperty" }

local function PropertyIs(prop, typeName)
    local kind = PropertyTypes[typeName]
    return kind ~= nil and prop:IsA(kind)
end

-- An asset (a mesh, a material, a class...) kept in a batch's data is kept as its path, { ref =
-- path }, and looked up again each time it is used. A batch runs for up to a minute; the engine
-- can free the object in that time (a map change), and even asking a freed object whether it is
-- valid reads freed memory.
local function Ref(object)
    local ok, full = pcall(function() return object:GetFullName() end)
    local path = ok and type(full) == "string" and full:match("%s(%S+)$") or nil
    return path and { ref = path } or nil
end

-- The object of a Ref, loaded if it is a game asset that is not loaded; nil when it is gone. Any
-- other value comes back as it is.
local function Deref(value)
    if type(value) ~= "table" or not value.ref then return value end
    local o = StaticFindObject(value.ref)
    if not Valid(o) and value.ref:sub(1, 6) == "/Game/" and not value.ref:find(":", 1, true) then
        pcall(LoadAsset, value.ref)
        o = StaticFindObject(value.ref)
    end
    if Valid(o) then return o end
    return nil
end

-- One property's name and its value in a form that can be put on another object. Nothing for the
-- kinds that are left alone (see the top of this section).
local function CopyableValue(owner, prop)
    local name = prop:GetFName():ToString()
    if PropertyIs(prop, "ClassProperty") or PropertyIs(prop, "ObjectProperty") then
        local value = owner[name]
        if not Valid(value) or IsKind(value, "Actor") or IsKind(value, "ActorComponent") then return nil end
        return name, Ref(value)
    end
    if PropertyIs(prop, "StrProperty") then return name, owner[name]:ToString() end
    if PropertyIs(prop, "StructProperty") then
        local plain = PlainStruct(owner[name])
        if plain then return name, plain end
        return nil
    end
    for _, typeName in ipairs(COPIED_AS_IS) do
        if PropertyIs(prop, typeName) then return name, owner[name] end
    end
    return nil
end

-- Every Blueprint variable of an object that can be copied: { { name, value }, ... }.
local function CaptureProps(object)
    local props = {}
    local cls, depth = object:GetClass(), 0
    while IsBlueprintClass(cls) and depth < 32 do
        depth = depth + 1
        cls:ForEachProperty(function(prop)
            local ok, name, value = pcall(CopyableValue, object, prop)
            if ok and name ~= nil and value ~= nil then props[#props + 1] = { name, value } end
        end)
        cls = cls:GetSuperStruct()
    end
    return props
end

-- All the data of an actor that is in the map right now (for dupe).
local function CaptureData(actor)
    local data = { props = CaptureProps(actor), comps = {} }
    for name, comp in pairs(ComponentsOf(actor)) do
        local c = {}
        if IsBlueprintClass(comp:GetClass()) then c.props = CaptureProps(comp) end
        local static, skeletal = IsKind(comp, "StaticMeshComponent"), IsKind(comp, "SkeletalMeshComponent")
        if static or skeletal then
            local mesh
            if static then mesh = comp.StaticMesh else mesh = comp.SkeletalMesh end
            if Valid(mesh) then c.mesh, c.skeletal = Ref(mesh), skeletal or nil end
            c.materials = {}
            for slot = 0, comp:GetNumMaterials() - 1 do
                local material = comp:GetMaterial(slot)
                if Valid(material) then c.materials[slot] = Ref(material) end
            end
            c.scale = PlainStruct(comp.RelativeScale3D)
        end
        if c.props or c.mesh or c.materials then data.comps[name] = c end
    end
    return data
end

-- The data of a name from objects.lua (its meshes and materials as Refs, loaded when used). nil
-- for a plain class.
local function DataOf(entry)
    if not (entry.props or entry.assets or entry.comps) then return nil end
    local data = { props = {}, comps = {} }
    for name, value in pairs(entry.props or {}) do data.props[#data.props + 1] = { name, value } end
    for name, path in pairs(entry.assets or {}) do
        data.props[#data.props + 1] = { name, { ref = path } }
    end
    for name, c in pairs(entry.comps or {}) do
        local out = { skeletal = c.skeletal }
        if c.mesh then out.mesh = { ref = c.mesh } end
        if c.materials then
            out.materials = {}
            for slot, path in pairs(c.materials) do out.materials[slot] = { ref = path } end
        end
        if c.scale then out.scale = { X = c.scale[1], Y = c.scale[2], Z = c.scale[3] } end
        data.comps[name] = out
    end
    return data
end

local function SetProps(object, props)
    for _, p in ipairs(props or {}) do
        local value = Deref(p[2])
        if value ~= nil then pcall(function() object[p[1]] = value end) end
    end
end

-- Give a component another mesh. Returns true when the mesh changed.
local function SetMesh(comp, mesh, skeletal)
    if skeletal then
        comp:SetSkeletalMesh(mesh, true)
        return true
    end
    local current = comp.StaticMesh
    if Valid(current) and current:GetAddress() == mesh:GetAddress() then return false end
    if comp:SetStaticMesh(mesh) then return true end
    -- The engine refuses a component that is set to never move: make it movable for the change.
    local mobility = comp.Mobility
    comp:SetMobility(2)                         -- EComponentMobility::Movable
    comp:SetStaticMesh(mesh)
    comp:SetMobility(mobility)
    return true
end

local function ApplyData(actor, data)
    SetProps(actor, data.props)
    local comps = ComponentsOf(actor)
    for name, c in pairs(data.comps or {}) do
        local comp = comps[name]
        if comp then
            local ok, problem = pcall(function()
                SetProps(comp, c.props)
                local mesh = c.mesh and Deref(c.mesh)
                if mesh and SetMesh(comp, mesh, c.skeletal) and V.CopyLookToGuests and actor:HasAuthority() then
                    comp:SetIsReplicated(true)
                end
                for slot, ref in pairs(c.materials or {}) do
                    local material = Deref(ref)
                    if material then comp:SetMaterial(slot, material) end
                end
                if c.scale then comp:SetRelativeScale3D(c.scale) end
            end)
            if not ok then Print("could not copy the data of " .. name .. ": " .. tostring(problem)) end
        end
    end
end

-- The address of an actor's world (which map it is in), or nil.
local function WorldOf(actor)
    local ok, address = pcall(function() return actor:GetWorld():GetAddress() end)
    return ok and address or nil
end

-- Spawn one actor of a class where the engine's summon would put it, then give it the data.
local function SpawnWithData(pc, cls, data)
    local kml = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local rot = pc:GetControlRotation()
    local from = pc:GetFocalLocation()
    local forward = kml:GetForwardVector(rot)
    local location = { X = from.X + forward.X * V.SummonForward, Y = from.Y + forward.Y * V.SummonForward,
                       Z = from.Z + forward.Z * V.SummonForward + V.SummonUp }
    local actor = pc:GetWorld():SpawnActor(cls, location, { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll })
    if not Valid(actor) then return nil end
    ApplyData(actor, data)
    return actor
end

--------------------------------------------------------------------------------------------------
-- summon, spawn, summonstop
--
--    summon <thing> [count]    spawn count copies, V.SummonDelayMs apart, e.g.  summon goldbar 10
--    spawn <thing> [count]     the same
--    summonstop                cancel summon batches that are still running
--
-- Names, compared without capitals, spaces and underscores:
--    - a class from spawnables.lua:    goldbar, Goldbar_C, statue_museum
--    - an object from objects.lua:     mona lisa, artwork_nefertiti, vault keycard
--      (one class with its own mesh, materials, size and values; see the section above)
--    - an item's in-game name:         artwork, gold bar
--    - a unique start of any of them:  gold, mona
--    - a full path:                    /Game/BP/Items/Valuables/Goldbar.Goldbar_C
--
-- The thing is loaded first, so it works on any map. As a guest the host summons it, in front of
-- you (command sharing).
--------------------------------------------------------------------------------------------------
State.summonGeneration = State.summonGeneration or 0      -- summonstop raises it; running batches notice

-- Every name summon knows, squashed: { name, entry, show, object }
local SpawnNames = {}
for key, entry in pairs(Spawnables) do
    SpawnNames[#SpawnNames + 1] = { name = Squash(key), entry = entry, show = entry.name }
end
for key, entry in pairs(Objects) do
    SpawnNames[#SpawnNames + 1] = { name = Squash(key), entry = entry, show = key, object = true }
end

local function IsPlain(entry)
    return not (entry.props or entry.assets or entry.comps)
end

-- Several names for the very same thing count once (goldbar and "gold bar"); a class name wins.
local function DistinctThings(pool)
    table.sort(pool, function(a, b)
        if (a.object or false) ~= (b.object or false) then return not a.object end
        return a.show < b.show
    end)
    local out, seen = {}, {}
    for _, n in ipairs(pool) do
        local id = IsPlain(n.entry) and ("plain " .. tostring(n.entry.path)) or n.entry
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = n
        end
    end
    return out
end

local function ResolveSpawnable(text)
    if text:sub(1, 1) == "/" then                                  -- full path given
        return { name = text:match("%.([^%.]+)$") or text, path = text }
    end
    local want = Squash((string.lower(text):gsub("_c$", "")))
    if want == "" then return { name = text } end
    -- Best first: the exact name; a class that starts with it; an object that starts with it;
    -- a class that contains it; an object that contains it.
    local tiers = { {}, {}, {}, {}, {} }
    for _, n in ipairs(SpawnNames) do
        local tier
        if n.name == want then tier = 1
        elseif n.name:sub(1, #want) == want then tier = n.object and 3 or 2
        elseif n.name:find(want, 1, true) then tier = n.object and 5 or 4 end
        if tier then tiers[tier][#tiers[tier] + 1] = n end
    end
    for _, pool in ipairs(tiers) do
        if #pool > 0 then
            pool = DistinctThings(pool)
            if #pool == 1 then return pool[1].entry end
            local names = {}
            for i = 1, math.min(#pool, 8) do names[i] = pool[i].show end
            return nil, string.format("'%s' matches %d things: %s%s", text, #pool, table.concat(names, ", "),
                #pool > 8 and ", ..." or "")
        end
    end
    return { name = text }                     -- not a Blueprint we know: let the engine try (PointLight etc.)
end

-- "mona lisa 3" -> "mona lisa", 3.  The last word is the count when it is a number.
local function NameAndCount(words)
    local last, count = #words, 1
    if last > 1 and tonumber(words[last]) then
        count = math.floor(tonumber(words[last]))
        last = last - 1
    end
    return table.concat(words, " ", 1, last), math.max(1, math.min(count, V.SummonMax))
end

-- The controller with that address, from the live list (a player who left is not in it); or
-- your own when address is nil.
local function LiveController(address)
    if not address then return LocalPlayerController() end
    for _, c in pairs(FindAllOf("PlayerController") or {}) do
        if c:IsValid() and c:GetAddress() == address then return c end
    end
    return nil
end

-- entry: { name, path, label, and for an object its data (props, assets, comps) }.
-- dupe passes the data itself. target: the controller to summon for (a guest's, on the host);
-- nil for your own.
-- Between two copies the batch keeps only names and numbers: the controller's address, the map
-- (its world's address) and the class's path; each copy looks them up again. When the player has
-- left or the map changed, the batch ends.
local function SpawnBatch(entry, count, Ar, target)
    local pc = target or LocalPlayerController()
    if not pc then Say(Ar, "No local player yet") return "no local player" end
    if not CheatManagerFor(pc) then Say(Ar, "No cheat manager, cannot summon") return "no cheat manager" end
    if entry.path then LoadAsset(entry.path) end
    local data = entry.data
    if not data then
        local ok, loaded = pcall(DataOf, entry)
        if ok then data = loaded else Print("could not load the data of " .. tostring(entry.label) .. ": " .. tostring(loaded)) end
    end
    if data and not (entry.path and LoadClass(entry.path)) then data = nil end
    local targetAddress = target and target:GetAddress() or nil
    local world, classPath = WorldOf(pc), entry.path
    local generation, done = State.summonGeneration, 0
    local delay = V.SummonDelayMs
    local function step()
        if generation ~= State.summonGeneration then return end
        local p = LiveController(targetAddress)
        if not p or WorldOf(p) ~= world then return end      -- the player left, or another map
        local cm = CheatManagerFor(p)
        if not cm then return end
        local spawned = false
        local cls = data and LoadClass(classPath)
        if cls then
            local ok, actor = pcall(SpawnWithData, p, cls, data)
            spawned = ok and actor ~= nil
            if not ok then Print("spawning with its data failed: " .. tostring(actor)) end
            if not spawned then
                Share.Notice("Could not place " .. tostring(entry.label or entry.name) ..
                    " with its data here, so the plain class was summoned")
            end
        end
        if not spawned then cm:Summon(entry.name) end
        done = done + 1
        if done < count then
            ExecuteWithDelay(delay, function() ExecuteInGameThread(step) end)
        end
    end
    step()
    local summary = string.format("Summoning %s x%d%s", entry.label or entry.name, count,
        count > 1 and string.format(" (%.2fs apart, summonstop to cancel)", delay / 1000) or "")
    Say(Ar, summary)
    return summary
end

local function DoSummon(pc, words, Ar)
    if #words == 0 then
        Say(Ar, "Usage: summon <thing> [count]   e.g.  summon goldbar 10")
        return "usage: summon <thing> [count]"
    end
    local name, count = NameAndCount(words)
    local entry, err = ResolveSpawnable(name)
    if not entry then Say(Ar, err) return err end
    return SpawnBatch(entry, count, Ar, pc)
end

local function StopSummons()
    State.summonGeneration = State.summonGeneration + 1
    return "Stopped all summon batches"
end

local function SummonHandler(FullCommand, Parameters, Ar)
    if #Parameters > 0 then
        local entry, err = ResolveSpawnable((NameAndCount(Parameters)))
        if not entry then Say(Ar, err) return true end
        -- As a guest the host summons it, in front of you
        if Share.Relay(FullCommand, Ar, function() DoSummon(nil, Parameters, nil) end) then return true end
    end
    DoSummon(nil, Parameters, Ar)
    return true
end

Core.Command("summon", SummonHandler)
Core.Command("spawn", SummonHandler)

Core.Command("summonstop", function(FullCommand, Parameters, Ar)
    if Share.Relay(FullCommand, Ar, StopSummons) then return true end
    Say(Ar, StopSummons())
    return true
end)

--------------------------------------------------------------------------------------------------
-- dupe
--
--    dupe [count]     copies of whatever is under your crosshair, with its data, e.g.  dupe 5
--
-- A line trace from the camera (the same call UE4SS's LineTraceMod makes) finds the object. Each
-- copy is spawned from the object's class and then gets the object's data: its Blueprint
-- variables, and the mesh, materials and size of its components (see "An object's data" above).
-- So a painting copies as that painting, not as the class's default statue.
-- As a guest the host copies what you are looking at (your camera position goes along).
--------------------------------------------------------------------------------------------------

-- What pc is looking at. pose (from a guest's request): trace from that camera position and
-- angle instead of pc's own camera. Returns the actor and the hit result.
local function LookedAtActor(pc, pose)
    local kml = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local start, rot
    if pose then
        start = { X = pose.x, Y = pose.y, Z = pose.z }
        rot = { Pitch = pose.pitch, Yaw = pose.yaw, Roll = 0.0 }
    else
        local cam = pc.PlayerCameraManager
        if not cam:IsValid() then return nil end
        start, rot = cam:GetCameraLocation(), cam:GetCameraRotation()
    end
    local reach = kml:Multiply_VectorFloat(kml:GetForwardVector(rot), V.AimDistance)
    local finish = kml:Add_VectorVector(start, reach)
    local pawn = pc.Pawn
    local ignore = {}
    if pawn:IsValid() then ignore[1] = pawn end
    local hit = {}
    local color = { R = 0, G = 0, B = 0, A = 0 }
    local wasHit = ksl:LineTraceSingle(pawn:IsValid() and pawn or pc, start, finish, V.AimTraceChannel, true,
        ignore, 0, hit, true, color, color, 0.0)                  -- 0 = draw nothing
    if not wasHit then return nil end
    local ok, actor = pcall(function() return hit.Actor:Get() end)
    if ok and actor and actor:IsValid() then return actor, hit end
    return nil
end

local function DoDupe(pc, words, Ar, pose)
    local target = pc                      -- a guest's controller on the host; nil for your own
    pc = pc or LocalPlayerController()
    if not pc then Say(Ar, "No local player yet") return "no local player" end
    local actor = LookedAtActor(pc, pose)
    if not actor then Say(Ar, "Not looking at anything") return "not looking at anything" end
    local cls = actor:GetClass()
    local className = cls:GetFName():ToString()
    if cls:GetClass():GetFName():ToString() ~= "BlueprintGeneratedClass" then
        local msg = string.format("That is %s, a plain part of the map; dupe only copies game objects", className)
        Say(Ar, msg)
        return msg
    end
    local path = cls:GetFullName():match("%s(%S+)$") or className   -- "BlueprintGeneratedClass /Game/..X_C"
    local count = math.floor(tonumber(words[1] or "1") or 1)
    count = math.max(1, math.min(count, V.SummonMax))
    -- Its data is read once, now; the copies get it even if the original is gone by then.
    local ok, data = pcall(CaptureData, actor)
    if not ok then
        Print("dupe: could not read the object's data, copying the plain class: " .. tostring(data))
        data = nil
    end
    return SpawnBatch({ name = path, path = path, label = className, data = data }, count, Ar, target)
end

Core.Command("dupe", function(FullCommand, Parameters, Ar)
    if Share.Relay(FullCommand, Ar, function() DoDupe(nil, Parameters, nil) end, { aim = true }) then
        return true
    end
    DoDupe(nil, Parameters, Ar)
    return true
end)

--------------------------------------------------------------------------------------------------
-- destroytarget and teleport for a guest (host side)
--
-- The engine's own DestroyTarget and Teleport aim from the camera of the player who runs them.
-- When the host runs them for a guest, these two aim from the camera position and angle the
-- guest's game sent along instead, so they act on what the GUEST is looking at.
--------------------------------------------------------------------------------------------------
local function IsPlayer(actor)
    local ok, player = pcall(function()
        local ps = actor.PlayerState
        return ps ~= nil and type(ps) ~= "number" and ps:IsValid()
    end)
    return ok and player
end

-- Players are left alone.
local function DestroyLookedAt(pc, pose)
    local actor = LookedAtActor(pc, pose)
    if not actor then return "nothing there" end
    if IsPlayer(actor) then return "that is a player; left alone" end
    local name = actor:GetFName():ToString()
    pcall(function()                              -- like the engine: an AI's controller goes too
        local c = actor.Controller
        if c and c:IsValid() then c:K2_DestroyActor() end
    end)
    actor:K2_DestroyActor()
    return "destroyed " .. name
end

local function TeleportToLookedAt(pc, pose)
    local pawn = pc.Pawn
    if not pawn:IsValid() then return "no character" end
    local actor, hit = LookedAtActor(pc, pose)
    if not actor then return "nothing there" end
    local n = hit.ImpactNormal or hit.Normal or { X = 0, Y = 0, Z = 0 }
    local off = V.TeleportOffset
    local loc = { X = hit.Location.X + n.X * off, Y = hit.Location.Y + n.Y * off, Z = hit.Location.Z + n.Z * off }
    pawn:K2_TeleportTo(loc, pawn:K2_GetActorRotation())
    return "teleported"
end

--------------------------------------------------------------------------------------------------
-- The value commands: what they share
--
-- Each one changes your own RobberController and then saves through the game's own functions
-- (SaveCash, SaveLevel, AddInventoryItem). Those write the save's check field (your SteamID, the
-- only thing the game verifies on load) and upload to Steam Cloud themselves, so a later launch
-- does not pull an older copy back down. Coins and anything that costs coins are never touched:
-- unlockables.lua only lists things bought with in-game cash.
--------------------------------------------------------------------------------------------------
local function Fmt(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%g", n)
end

-- Every change goes into the change log with the old value, so it can be undone with the same
-- commands. (The save files are named after your SteamID, which UE4SS 3.0.1 cannot read, so
-- copying the saves themselves is not possible from here.)
local function LogChange(text)
    pcall(function()
        local root = os.getenv("LOCALAPPDATA")
        if not root then return end
        local f = io.open(root .. "\\" .. V.ChangeLog, "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S  "), text, "\n")
            f:close()
        end
    end)
end

-- A value command: find your controller, then run the edit. fn returns false (and an optional
-- hint) to show the usage line.
local function Edit(name, usage, fn)
    Core.Command(name, function(FullCommand, Parameters, Ar)
        local pc = Robber()
        if not pc then Say(Ar, "No local player yet") return true end
        local ran, ok, err = pcall(fn, pc, Parameters or {}, Ar)
        if not ran then
            Say(Ar, name .. " failed: " .. tostring(ok))
        elseif ok == false then
            Say(Ar, "Usage: " .. usage .. (err and ("  (" .. err .. ")") or ""))
        end
        return true
    end)
end

--------------------------------------------------------------------------------------------------
-- setmoney, addmoney
--
--    setmoney <amount>     set your cash, e.g.  setmoney 5000000
--    addmoney <amount>     add cash (a negative amount removes it)
--------------------------------------------------------------------------------------------------
local function SetCash(cmd, pc, value, Ar)
    local capped = value > V.MaxCashAndLevel
    value = math.floor(math.max(0, math.min(value, V.MaxCashAndLevel)))
    LogChange(string.format("%s: cash %s -> %s", cmd, Fmt(pc.Cash), Fmt(value)))
    pc.Cash = value
    pc:SaveCash()
    pc:LoadCash()       -- the same reload the shop does before a purchase; refreshes the cash shown
    Say(Ar, string.format("Cash is now %d%s", value,
        capped and " (capped at 2,000,000,000 so heist payouts can't overflow)" or ""))
end

Edit("setmoney", "setmoney <amount>   e.g.  setmoney 5000000", function(pc, p, Ar)
    local n = Number(p[1])
    if not n then return false end
    SetCash("setmoney", pc, n, Ar)
end)

Edit("addmoney", "addmoney <amount>   e.g.  addmoney 100000  (negative removes)", function(pc, p, Ar)
    local n = Number(p[1])
    if not n then return false end
    SetCash("addmoney", pc, pc.Cash + n, Ar)
end)

--------------------------------------------------------------------------------------------------
-- setlevel, setxp
--
--    setlevel <level>     set your level; XP starts at 0 in that level
--    setxp <amount>       set your XP within the current level
--    setxp all <amount>   host, during a heist: every player gains that much XP on the win screen
--
-- setxp all: only each player's own game can change their XP, so the host cannot set a guest's
-- XP directly. What does reach everyone is the game's own XP call from the escape van's button,
-- LeaveButton.AddPlayerEXP(character, xp), a reliable multicast. Every player's game (no mod
-- needed) adds it to that character's GainedEXP, and the win screen credits and saves it when the
-- heist is won, like the heist's own XP. A lost heist pays nothing. On the host the multicast runs
-- too, so GainedEXP there counts what this heist already gave (for V.SetXPAllMax).
--------------------------------------------------------------------------------------------------
local function CharacterName(c)
    local ok, name = pcall(function() return c.PlayerState.PlayerName:ToString() end)
    return ok and name or "a player"
end

local function GiveEveryoneXP(pc, n, Ar)
    if not pc:HasAuthority() then
        Say(Ar, "Only the host can give everyone XP (each player's own game keeps their XP)")
        return
    end
    local button = FindFirstOf("LeaveButton_C")
    if not Valid(button) then
        Say(Ar, "Only during a heist: the XP goes out through the escape van and is paid on the win screen")
        return
    end
    local given, full = {}, {}
    for _, c in ipairs(AllOf("PlayerCharacter_C")) do
        if Valid(c) then
            local amount = math.floor(math.min(n, V.SetXPAllMax - (c.GainedEXP or 0)))
            if amount > 0 then
                button:FlushNetDormancy()
                button:AddPlayerEXP(c, amount)
                given[#given + 1] = CharacterName(c) .. " +" .. Fmt(amount)
            else
                full[#full + 1] = CharacterName(c)
            end
        end
    end
    if #given > 0 then
        LogChange("setxp all: " .. table.concat(given, ", "))
        Say(Ar, string.format("Gave XP to %d players: %s. Everyone gets it on the win screen when the heist is won",
            #given, table.concat(given, ", ")))
    end
    if #full > 0 then
        Say(Ar, string.format("Already at the most extra XP for this heist (%s): %s", Fmt(V.SetXPAllMax), table.concat(full, ", ")))
    end
    if #given == 0 and #full == 0 then Say(Ar, "No players found") end
end

Edit("setlevel", "setlevel <level>   e.g.  setlevel 50", function(pc, p, Ar)
    local n = Number(p[1])
    if not n or n < 1 then return false, "level 1 or higher" end
    n = math.floor(math.min(n, V.MaxCashAndLevel))
    LogChange(string.format("setlevel: level %s -> %s, xp %s -> 0", Fmt(pc.Level), Fmt(n), Fmt(pc.EXP)))
    pc.Level = n
    pc.EXP = 0
    pc:SaveLevel()
    pc:LoadLevel()
    Say(Ar, "Level is now " .. n)
end)

Edit("setxp", "setxp <amount>   e.g.  setxp 100     setxp all <amount>   every player in the heist", function(pc, p, Ar)
    if p[1] and p[1]:lower() == "all" then
        local n = Number(p[2])
        if not n or n < 1 then return false end
        GiveEveryoneXP(pc, n, Ar)
        return
    end
    local n = Number(p[1])
    if not n or n < 0 then return false end
    -- The game's GetRequiredEXP. At or above it, the next XP gain makes AddEXP call itself
    -- once per level, which a big number turns into a runaway recursion. Use setlevel instead.
    local needed = (pc.Level / 0.005) ^ 0.8
    if n >= needed then
        return false, string.format("level %d levels up at %.0f XP; use setlevel to change level", pc.Level, needed)
    end
    LogChange(string.format("setxp: xp %s -> %s", Fmt(pc.EXP), Fmt(n)))
    pc.EXP = n
    pc:SaveLevel()
    pc:LoadLevel()
    Say(Ar, "XP is now " .. Fmt(n))
end)

--------------------------------------------------------------------------------------------------
-- maxskills
--
--    maxskills     every skill owned and researched to its top tier
--
-- Adding to a game list goes through the game's own code (ProgressSkills), never through UE4SS
-- (see the note at the top of this file).
--------------------------------------------------------------------------------------------------
Edit("maxskills", "maxskills", function(pc, p, Ar)
    local F, P = Unlockables.SkillFields, Unlockables.ProgressFields
    local wanted, missing = {}, {}          -- class address -> skill; skills that would not load
    for _, s in ipairs(Unlockables.Skills) do
        local cls = LoadClass(s.path)
        if cls then wanted[cls:GetAddress()] = { skill = s, cls = cls } else missing[#missing + 1] = s.name end
    end

    -- Skills you already have: raise the tier in place (tiers above the top one do nothing in the game).
    local owned = pc.UnlockedSkills
    local have, raised = {}, {}
    for i = 1, owned:GetArrayNum() do
        local entry = owned[i]
        local cls = entry[F.skill]
        local w = cls and cls:IsValid() and wanted[cls:GetAddress()]
        if w then
            if entry[F.tier] ~= w.skill.tiers then
                raised[#raised + 1] = string.format("%s tier %s -> %d", w.skill.name, Fmt(entry[F.tier]), w.skill.tiers)
                entry[F.tier] = w.skill.tiers
            end
            have[cls:GetAddress()] = true
        end
    end

    -- Skills you don't have: added the way the game does when research finishes. Each one goes
    -- alone into the emptied research queue as finished research, and the game's ProgressSkills
    -- moves it into UnlockedSkills with its own Array_Add.
    local added, failed = {}, {}
    for address, w in pairs(wanted) do
        if not have[address] then
            local before = pc.UnlockedSkills:GetArrayNum()
            local research = pc.ResearchingSkills
            research:Empty()
            local r = research[1]                  -- the one growth UE4SS 3.0.1 gets right: empty -> 1
            -- Member by member: UE4SS 3.0.1 cannot put a class into a struct from a Lua table
            -- (its class setter looks at the wrong stack slot and throws).
            local s = r[P.skill]                   -- live view of the SkillSaveStruct inside
            s[F.skill] = w.cls
            s[F.tier] = w.skill.tiers
            r[P.progress] = V.FinishedResearch
            pc:ProgressSkills(0.0)
            if pc.UnlockedSkills:GetArrayNum() == before + 1 then
                added[#added + 1] = w.skill.name
            else
                failed[#failed + 1] = w.skill.name
            end
        end
    end
    pc.ResearchingSkills:Empty()

    LogChange(string.format("maxskills: %s; added %d skills%s", #raised > 0 and table.concat(raised, ", ") or "no tiers raised",
        #added, #added > 0 and (": " .. table.concat(added, ", ")) or ""))
    pc:SaveLevel()
    pc:LoadLevel()
    Say(Ar, string.format("Skills at top tier: %d raised, %d added. They apply from your next spawn.", #raised, #added))
    if #failed > 0 then Say(Ar, "The game did not add: " .. table.concat(failed, ", ")) end
    if #missing > 0 then Say(Ar, "Could not load: " .. table.concat(missing, ", ")) end
end)

--------------------------------------------------------------------------------------------------
-- unlockall
--
--    unlockall     every weapon, weapon mod, tool and armor that costs cash
--
-- Each item is added with the game's own AddInventoryItem, which also saves.
--------------------------------------------------------------------------------------------------
Edit("unlockall", "unlockall", function(pc, p, Ar)
    local have = {}
    local inv = pc.ItemInventory
    for i = 1, inv:GetArrayNum() do
        local cls = inv[i]
        if cls and cls:IsValid() then have[cls:GetAddress()] = true end
    end
    local added, owned, missing, failed = {}, 0, {}, {}
    for _, item in ipairs(Unlockables.Gear) do
        local cls = LoadClass(item.path)
        if not cls then
            missing[#missing + 1] = item.name
        elseif have[cls:GetAddress()] then
            owned = owned + 1
        else
            local before = pc.ItemInventory:GetArrayNum()
            pc:AddInventoryItem(cls, {})           -- the game's own: Array_Add, then SaveInventoryItems
            if pc.ItemInventory:GetArrayNum() == before + 1 then
                added[#added + 1] = item.name
                have[cls:GetAddress()] = true
            else
                failed[#failed + 1] = item.name
            end
        end
    end
    if #added > 0 then
        LogChange(string.format("unlockall: added %d items: %s", #added, table.concat(added, ", ")))
    end
    Say(Ar, string.format("Added %d cash items (%d you already had): weapons, weapon mods, tools, armor", #added, owned))
    if #failed > 0 then Say(Ar, "The game did not add: " .. table.concat(failed, ", ")) end
    if #missing > 0 then Say(Ar, "Could not load: " .. table.concat(missing, ", ")) end
end)

--------------------------------------------------------------------------------------------------
-- noclip
--
--    noclip     fly through walls: WASD as usual, Space up, Ctrl down, Shift faster.
--               Type it again to land.
--
-- It acts on the machine in charge of the character: yours when you host or play solo, the host's
-- when you are a guest (through command sharing). As a guest without sharing it still runs on
-- your game, which the host then overrides.
--
-- The game only moves you along your level forward and right, so flying needs its own up/down.
-- That is added every frame from a hook on your character's MoveForward input event.
--------------------------------------------------------------------------------------------------
local MOVE_FALLING, MOVE_FLYING = 3, 5          -- EMovementMode
local UP = { X = 0.0, Y = 0.0, Z = 1.0 }
State.noclip = State.noclip or {}               -- character address -> { on, walk, oldFly, fast, speed, localInput }

local function Decimal(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.1f", n)
end

local function KeyDown(pc, names)
    for _, n in ipairs(names) do
        if pc:IsInputKeyDown({ KeyName = FName(n) }) then return true end
    end
    return false
end

-- The flying speed now, normal or with Shift held. Read every time, so a changed setting
-- applies while you fly.
local function NoclipSpeedOf(st, fast)
    local base = V.NoclipSpeed > 0 and V.NoclipSpeed or st.walk
    if fast then return V.NoclipFastSpeed > 0 and V.NoclipFastSpeed or base * V.NoclipFastMultiplier end
    return base
end

-- Every frame while you control your character: Space/Ctrl up and down, Shift speed.
-- The keys are read from the character's own controller. Code that runs every frame must never
-- search all objects (FindFirstOf, FindAllOf, AllOf): for the first seconds after a map loads the
-- game is still creating objects on another thread, and searching then crashed the game
-- (2026-10-03, every crash 3 to 14 seconds after a map load).
local function OnNoclipFrame(pawn)
    local st = State.noclip[pawn:GetAddress()]
    if not st then return end
    if pawn.CharacterMovement.MovementMode ~= MOVE_FLYING then
        -- the game ended the flight (respawn, a reset, walk): noclip is off, Shift sends nothing
        State.noclip[pawn:GetAddress()] = nil
        return
    end
    if not (st.on and st.localInput) then return end
    local pc = pawn.Controller
    if not (pc and pc:IsValid()) then return end
    local v = (KeyDown(pc, V.NoclipKeysUp) and 1.0 or 0.0) - (KeyDown(pc, V.NoclipKeysDown) and 1.0 or 0.0)
    if v ~= 0 then pawn:AddMovementInput(UP, v, true) end
    local fast = KeyDown(pc, V.NoclipKeysFast)
    local speed = NoclipSpeedOf(st, fast)
    if fast ~= st.fast or speed ~= st.speed then
        st.fast, st.speed = fast, speed
        pawn.CharacterMovement.MaxFlySpeed = speed
        Share.Notify("noclip on " .. Decimal(speed))     -- a guest's host follows the speed
    end
end

-- The character's Blueprint must be loaded to hook it (it is in a heist, maybe not in the menu),
-- so this is tried again every time noclip turns on until it works.
local function HookNoclipFrames()
    local ok, err = Core.Hook(V.NoclipFrameEvent, function(Self) OnNoclipFrame(Self:get()) end)
    if ok then
        State.noclipHooked = true
    else
        Print("noclip: no per-frame hook yet (" .. tostring(err) .. ")")
    end
    return ok
end
if State.noclipHooked then HookNoclipFrames() end      -- after reloadconfig: point the hook at this code

-- On or off for one character. localInput: this machine reads the keys (your own character).
-- Used for your own character and, on the host, for a guest's.
local function SetNoclip(pawn, on, speed, localInput)
    if not (pawn and pawn:IsValid()) then return "no character" end
    local key = pawn:GetAddress()
    local cm = pawn.CharacterMovement
    local st = State.noclip[key]
    if on then
        if not st or cm.MovementMode ~= MOVE_FLYING then
            -- a new flight: today's walking speed (an entry the game ended is started again)
            st = { oldFly = st and st.oldFly or cm.MaxFlySpeed, walk = cm.MaxWalkSpeed, fast = false }
            State.noclip[key] = st
        end
        st.on, st.localInput = true, localInput
        pawn:SetActorEnableCollision(false)
        cm.bCheatFlying = true                  -- stop dead when the keys are let go
        cm:SetMovementMode(MOVE_FLYING, 0)
        cm.MaxFlySpeed = speed or NoclipSpeedOf(st, st.fast)
        st.speed = cm.MaxFlySpeed
        if localInput and not HookNoclipFrames() then
            return "noclip on (Space/Ctrl up and down need a heist map; WASD works)"
        end
        return "noclip on"
    end
    pawn:SetActorEnableCollision(true)
    cm.bCheatFlying = false
    cm:SetMovementMode(MOVE_FALLING, 0)
    if st then cm.MaxFlySpeed = st.oldFly end
    State.noclip[key] = nil
    return "noclip off"
end

-- On only while the character really is still flying: if the game ended it (respawn, a reset),
-- noclip counts as off and typing it turns it back on.
local function NoclipOn(pawn)
    local st = State.noclip[pawn:GetAddress()]
    return st ~= nil and st.on and pawn.CharacterMovement.MovementMode == MOVE_FLYING
end

-- `Ar` (the console's output) only lives while the command runs; results that come later, after
-- the host answered, are printed with Share.Notice instead.
local function Out(Ar, text)
    if Ar then Say(Ar, text) else Share.Notice(text) end
end

Core.Command("noclip", function(FullCommand, Parameters, Ar)
    local pc = Robber()
    local pawn = pc and pc.Pawn
    if not (pawn and pawn:IsValid()) then Say(Ar, "No character to noclip") return true end
    local on = not NoclipOn(pawn)
    local speed = V.NoclipSpeed > 0 and V.NoclipSpeed or pawn.CharacterMovement.MaxWalkSpeed
    local key = pawn:GetAddress()
    local function here(ArNow, now)
        if not now then
            -- after the host's answer: your character looked up again (it may be gone by then)
            local c = Robber()
            now = c and c.Pawn
            if not (now and now:IsValid() and now:GetAddress() == key) then
                Out(ArNow, "noclip: your character changed, type noclip again")
                return
            end
        end
        Out(ArNow, SetNoclip(now, on, on and speed or nil, true) ..
            (on and ": WASD to move, Space up, Ctrl down, Shift faster" or ""))
    end
    local line = on and ("noclip on " .. Decimal(speed)) or "noclip off"
    -- As a guest the host does it to your character too; your game does the same so both agree.
    local later = function() here(nil) end
    if Share.Relay(line, Ar, later, { onOk = later }) then return true end
    here(Ar, pawn)
    return true
end)

--------------------------------------------------------------------------------------------------
-- revive
--
--    revive     back up with full health
--
-- The same steps the game runs when a teammate's revive finishes: Health = MaxHealth,
-- Downed? = false, ReviveClient() on your machine (camera colour and look limits back).
-- The host decides who is downed, so as a guest this goes through command sharing.
--------------------------------------------------------------------------------------------------
local function ReviveCharacter(pawn)
    local down = pawn["Downed?"]
    SetReplicated(pawn, "Health", pawn.MaxHealth)
    SetReplicated(pawn, "Downed?", false)
    pawn:ReviveClient()
    return down
end

local function Revive(pc)
    local pawn = pc and pc.Pawn
    if not (pawn and pawn:IsValid()) then return "no character to revive" end
    return ReviveCharacter(pawn) and "revived" or "not downed, health refilled"
end

Core.Command("revive", function(FullCommand, Parameters, Ar)
    local function here(ArNow)
        local pc = Robber()
        Out(ArNow, pc and Revive(pc) or "No local player yet")
    end
    if Share.Relay("revive", Ar, function() here(nil) end) then return true end
    here(Ar)
    return true
end)

--------------------------------------------------------------------------------------------------
-- revive timing (when you host)
--
-- A game bug that the Healing Touch skill brings out. The reviver's bar fills in the REVIVER's
-- revive time (5 s; 4, 3.5 or 3 s with Healing Touch), but the host finishes the revive after the
-- DOWNED player's revive time, and only if the reviver still holds the mouse button then. With
-- Healing Touch the bar is full first, and letting go at that moment cancels the revive.
--
-- How the game does it on the host: the downed character's RevivePlayer stores the reviver in
-- "Assisting Player", runs the reviver's StartRevive (the bar), then starts its own timer with its
-- own ReviveTime. UE4SS runs a Blueprint hook right after the function, so this sets the downed
-- player's ReviveTime to the reviver's after StartRevive (before the timer starts) and puts it
-- back after RevivePlayer. A revive is never made slower than the game makes it.
-- As a guest the host's game decides: keep holding until your teammate stands up.
--------------------------------------------------------------------------------------------------
local REVIVE_STARTED = "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:StartRevive"
local REVIVE_TIMER_SET = "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:RevivePlayer"
State.reviveTimes = State.reviveTimes or {}    -- downed character address -> its own revive time, to put back

local function OnReviveStarted(reviver)
    if not (V.ReviveMatchesBar and Valid(reviver) and reviver:HasAuthority()) then return end
    local barTime = reviver.ReviveTime
    for _, c in ipairs(AllOf("PlayerCharacter_C")) do
        local helper = Valid(c) and c["Downed?"] and c["Assisting Player"] or nil
        if Valid(helper) and helper:GetAddress() == reviver:GetAddress() and barTime < c.ReviveTime then
            local address = c:GetAddress()
            State.reviveTimes[address] = State.reviveTimes[address] or c.ReviveTime
            c.ReviveTime = barTime
        end
    end
end

-- Only characters that are in the map right now: a character kept from earlier could have been
-- freed by the engine (a map change), and even asking it whether it is valid reads freed memory.
local function PutReviveTimesBack()
    if next(State.reviveTimes) == nil then return end
    for _, c in ipairs(AllOf("PlayerCharacter_C")) do
        local time = State.reviveTimes[c:GetAddress()]
        if time then c.ReviveTime = time end
    end
    State.reviveTimes = {}
end

HookWhenLoaded(function()
    local started = Core.Hook(REVIVE_STARTED, function(Self) OnReviveStarted(Self:get()) end)
    local timerSet = Core.Hook(REVIVE_TIMER_SET, function() PutReviveTimesBack() end)
    if started and timerSet and not State.reviveHooked then Print("revive timing: hooked") end
    State.reviveHooked = (started and timerSet) or nil
    return State.reviveHooked
end)

--------------------------------------------------------------------------------------------------
-- setammo
--
--    setammo <amount>     every gun you carry gets that much spare ammo, and the gun in your
--                         hand a full magazine
--
-- Ammo is counted on your own game only: your character keeps each weapon slot's spare ammo in
-- ReserveAmmo, and the gun in your hand counts its magazine in BulletsLeft (full = MagSize).
-- Shooting checks your own game's count and a reload takes from the spare ammo as usual, so this
-- works for the host and for guests alike and needs no one else's mod.
--------------------------------------------------------------------------------------------------
Core.Command("setammo", function(FullCommand, Parameters, Ar)
    local n = Number(Parameters and Parameters[1])
    if not n or n < 0 then Say(Ar, "Usage: setammo <amount>   e.g.  setammo 999") return true end
    n = math.floor(math.min(n, V.AmmoMax))
    local pc = Robber()
    local pawn = pc and pc.Pawn
    local ok, reserve = pcall(function() return pawn.ReserveAmmo end)
    if not (Valid(pawn) and ok and reserve and reserve.GetArrayNum) then
        Say(Ar, "No character with guns right now (in a heist, after it has loaded)")
        return true
    end
    local slots = reserve:GetArrayNum()
    for i = 1, slots do reserve[i] = n end
    local gun = pawn.HoldingGun
    local filled = ""
    if Valid(gun) and gun.BulletsLeft < gun.MagSize then
        gun.BulletsLeft = gun.MagSize
        filled = ", and a full magazine (" .. Fmt(gun.MagSize) .. ") in your hand"
    end
    Say(Ar, string.format("Spare ammo is now %s for your %d guns%s", Fmt(n), slots, filled))
    return true
end)

--------------------------------------------------------------------------------------------------
-- truckmoney  (host, during a heist)
--
--    truckmoney                  the money in the truck, and how much of it is from this command
--    truckmoney set <amount>     the truck holds exactly that much (loot put in later adds to it)
--    truckmoney add <amount>     add that much; a negative amount takes money away
--    truckmoney reset            back to 0
--
-- The getaway truck (RobberTruck_C, one in every heist) keeps the take in TotalTake. Loot going in
-- or out adds or subtracts its Value (the server events CountMoney and RemoveMoney), the truck
-- shows the number, and every player's win screen adds the WHOLE take to their own cash.
-- TotalTake is replicated, so the host's number reaches everyone. It is changed the way the game
-- changes it: FlushNetDormancy, set, then mark it for sending (push model replication).
--
-- The escape button makes the truck count TotalTake again from the loot inside (CheckAllMoney),
-- which would drop this command's change. So the change is kept as an amount next to the loot
-- (State.truckMoney.extra, with TotalTake = loot + extra) and put back by a hook right after the
-- recount, every time (the escape can be pressed more than once). After loot goes in or out the
-- take is kept between 0 and V.TruckMoneyMax. The change belongs to that truck in that world: its
-- address, its world's address and how long it has existed (a new map starts again near 0), so a
-- heist that ended without escaping does not hand it to the next one. (Not UE4SS's
-- RegisterLoadMapPostHook: in 3.0.1 it calls Lua through a stale pointer on every map load and
-- corrupts the game's memory.)
--------------------------------------------------------------------------------------------------
local TRUCK = "/Game/BP/Player/RobberTruck.RobberTruck_C"

local function Clamp(n, low, high) return math.max(low, math.min(n, high)) end

local function SetTake(truck, value) SetReplicated(truck, "TotalTake", value) end

local function AgeOf(actor)
    local ok, seconds = pcall(function() return actor:GetGameTimeSinceCreation() end)
    return ok and type(seconds) == "number" and seconds or nil
end

-- This command's change for this truck in this world, or nil.
local function TruckState(truck)
    local tm = State.truckMoney
    if not (tm and tm.truck == truck:GetAddress() and tm.world == WorldOf(truck)) then return nil end
    local age = AgeOf(truck)
    if tm.age and age and age < tm.age then return nil end       -- a newer truck at the same address
    return tm
end

local function TruckExtra(truck)
    local tm = TruckState(truck)
    return tm and tm.extra or 0
end

local function SetTruckMoney(truck, value)
    value = math.floor(Clamp(value, 0, V.TruckMoneyMax))
    local loot = truck.TotalTake - TruckExtra(truck)
    State.truckMoney = { truck = truck:GetAddress(), world = WorldOf(truck), age = AgeOf(truck), extra = value - loot }
    SetTake(truck, value)
    return value
end

-- After the escape button's recount TotalTake is the loot alone: put the change back on top.
local function AfterRecount(truck)
    if not (Valid(truck) and truck:HasAuthority()) or TruckExtra(truck) == 0 then return end
    local loot = truck.TotalTake
    local value = math.floor(Clamp(loot + TruckExtra(truck), 0, V.TruckMoneyMax))
    State.truckMoney.extra = value - loot
    SetTake(truck, value)
end

-- After loot went in or out: keep a take this command changed between 0 and the limit.
local function AfterLootMoved(truck)
    if not (Valid(truck) and truck:HasAuthority()) then return end
    local tm = TruckState(truck)
    if not tm then return end
    local take = truck.TotalTake
    local value = math.floor(Clamp(take, 0, V.TruckMoneyMax))
    if value ~= take then
        tm.extra = tm.extra + (value - take)
        SetTake(truck, value)
    end
end

-- Placed the first time truckmoney changes the take (in a heist, so the truck's Blueprint is
-- loaded), like noclip's hook, and not at startup: with these placed at startup the game crashed
-- seconds after noclip was turned on (2026-10-03).
local function HookTruck()
    local recount = Core.Hook(TRUCK .. ":CheckAllMoney", function(Self) AfterRecount(Self:get()) end)
    local counted = Core.Hook(TRUCK .. ":CountMoney", function(Self) AfterLootMoved(Self:get()) end)
    local removed = Core.Hook(TRUCK .. ":RemoveMoney", function(Self) AfterLootMoved(Self:get()) end)
    State.truckHooked = (recount and counted and removed) or nil
    return State.truckHooked
end
if State.truckHooked then HookTruck() end      -- after reloadconfig: point the hooks at this code

Core.Command("truckmoney", function(FullCommand, Parameters, Ar)
    local p = Parameters or {}
    local usage = "Usage: truckmoney   |   truckmoney set <amount>   |   truckmoney add <amount>   |   truckmoney reset"
    local verb, n = (p[1] or ""):lower(), Number(p[2])
    if not (verb == "" or verb == "reset" or ((verb == "set" or verb == "add") and n)) then
        Say(Ar, usage)
        return true
    end
    local truck = FindFirstOf("RobberTruck_C")
    if not Valid(truck) then Say(Ar, "Only during a heist: there is no getaway truck here") return true end
    local pc = Robber()
    local host = pc and pc:HasAuthority()
    if verb == "" then
        local extra = TruckExtra(truck)
        local parts = host and string.format(" (loot %s, truckmoney %s)", Fmt(truck.TotalTake - extra), Fmt(extra)) or ""
        Say(Ar, string.format("Truck money: %s%s. Needed to leave: %s", Fmt(truck.TotalTake), parts, Fmt(truck.MinimumTake)))
        return true
    end
    if not host then HostOnly(Ar, "change the truck's money", FullCommand) return true end
    local before = truck.TotalTake
    local wanted = (verb == "set" and n) or (verb == "add" and before + n) or 0
    if not State.truckHooked then HookTruck() end
    local now = SetTruckMoney(truck, wanted)
    local note = ""
    if wanted > V.TruckMoneyMax then note = " (the most is " .. Fmt(V.TruckMoneyMax) .. ")" end
    if before < truck.MinimumTake and now >= truck.MinimumTake then
        note = note .. ". Standing in the truck already? Step out and back in so it lets you leave"
    end
    Say(Ar, string.format("Truck money: %s (was %s)%s. Every player gets the whole take on the win screen",
        Fmt(now), Fmt(before), note))
    return true
end)

--------------------------------------------------------------------------------------------------
-- Heist commands for the host
--
--    reviveall              revive every downed player
--    healall                everyone back to full health and full armor
--    godall [on|off]        nobody takes damage (the game's own damage immunity)
--    alarm [off|on]         switch the alarm off (as hacking its box does) or set it off
--    cops [wave|specials|clear]   a new police wave, a special police wave, or remove all police
--    cameras off|destroy    remove every security camera (guards do not notice) / break them
--    codes [open]           every keypad's code; open = unlock them all (as hacking one does)
--    bringloot              every loose valuable into the getaway truck
--    escape                 win the heist now, with what is in the truck
--
-- The game decides these on the host, so they use the game's own functions and variables there,
-- and the game sends the result to every player. Guests do not need the mod. As a guest these
-- go to the host when the host has OARCommands with command sharing at 2 or 3 (you get the
-- host's answer in your console); otherwise they say that only the host can. codes and the
-- plain status lines (alarm, cops, cameras, doors) work on a guest's own game.
--------------------------------------------------------------------------------------------------

local function Players() return AllOf("PlayerCharacter_C") end

local function NamesOf(list)
    return #list > 0 and table.concat(list, ", ") or "nobody"
end

Core.Command("reviveall", function(FullCommand, Parameters, Ar)
    if not HostOnly(Ar, "revive everyone", FullCommand) then return true end
    local revived = {}
    for _, c in ipairs(Players()) do
        if c["Downed?"] then
            ReviveCharacter(c)
            revived[#revived + 1] = CharacterName(c)
        end
    end
    Say(Ar, #revived > 0 and ("Revived: " .. NamesOf(revived)) or "Nobody is downed")
    return true
end)

-- Health on the character; armor on the armor the character wears (ArmorChildActor).
Core.Command("healall", function(FullCommand, Parameters, Ar)
    if not HostOnly(Ar, "heal everyone", FullCommand) then return true end
    local healed = {}
    for _, c in ipairs(Players()) do
        SetReplicated(c, "Health", c.MaxHealth)
        local ok, armor = pcall(function() return c.ArmorChildActor.ChildActor end)
        if ok and Valid(armor) then
            pcall(function() SetReplicated(armor, "ArmorHealth", armor.ArmorMaxHealth) end)
        end
        healed[#healed + 1] = CharacterName(c)
    end
    Say(Ar, "Full health and armor: " .. NamesOf(healed))
    return true
end)

-- The game's damage check: TakeDamage does nothing while the character's DamageImmunity is above 0
-- (it gives a few seconds of it after some events). Everyone's HUD shows the immunity vignette.
-- Whether it is on is read from the characters: everyone in a new heist starts at 0.
local function GodAllOn()
    for _, c in ipairs(Players()) do
        if (c.DamageImmunity or 0) > 0 then return true end
    end
    return false
end

Core.Command("godall", function(FullCommand, Parameters, Ar)
    if not HostOnly(Ar, "make everyone immune", FullCommand) then return true end
    local word = Parameters and Parameters[1] and Parameters[1]:lower()
    local on
    if word == "on" then on = true elseif word == "off" then on = false else on = not GodAllOn() end
    State.godAll = on
    local who = {}
    for _, c in ipairs(Players()) do
        SetReplicated(c, "DamageImmunity", on and 1 or 0)
        who[#who + 1] = CharacterName(c)
    end
    Say(Ar, (on and "Nobody takes damage now: " or "Damage is back on: ") .. NamesOf(who) ..
        (on and ". Type godall on again after someone joins or a new heist starts" or ""))
    return true
end)

-- The alarm box: in every heist it is a lever (BP_PowerSwitch_C) whose AffectedActors holds the alarm
-- (AlarmBP_C). Clicking it runs the lever's Interact event: if it has not been pulled, the server
-- half (SwitchLeverServer) tells each affected actor it was hacked, which makes the alarm
-- DeactivateAlarm (AlarmEnabled? = false, so guards can no longer set it off), swings the lever for
-- everyone and marks it pulled (Switched?). alarm off runs that same click event on the host.
-- alarm on undoes it: the alarm armed again and the lever usable again (it stays down).
-- alarm trigger is the alarm going off (TriggerAlarmInterface): the heist goes loud.
local LEVER_CLICK = "BndEvt__PowerSwitch_InteractComponent_K2Node_ComponentBoundEvent_2_Interact__DelegateSignature"

-- The levers wired to an alarm.
local function AlarmLevers(alarms)
    local isAlarm = {}
    for _, a in ipairs(alarms) do isAlarm[a:GetAddress()] = true end
    local levers = {}
    for _, lever in ipairs(AllOf("BP_PowerSwitch_C")) do
        local ok, affected = pcall(function() return lever.AffectedActors end)
        if ok and affected then
            for i = 1, affected:GetArrayNum() do
                local a = affected[i]
                if Valid(a) and isAlarm[a:GetAddress()] then levers[#levers + 1] = lever break end
            end
        end
    end
    return levers
end

local function AlarmState(alarm)
    local state = alarm["AlarmEnabled?"] and "Alarm is ON (armed)" or "Alarm is OFF (disabled, as if the alarm box was used)"
    if alarm["HasAlarmTriggered?"] then state = state .. ". It has gone off: the heist is loud" end
    return state
end

Core.Command("alarm", function(FullCommand, Parameters, Ar)
    local word = Parameters and Parameters[1] and Parameters[1]:lower() or ""
    if word ~= "" and word ~= "off" and word ~= "on" and word ~= "trigger" then
        Say(Ar, "Usage: alarm   |   alarm off (use the alarm box)   |   alarm on   |   alarm trigger (go loud)")
        return true
    end
    local alarms = AllOf("AlarmBP_C")
    if #alarms == 0 then Say(Ar, "There is no alarm here (only in a heist)") return true end
    local alarm = alarms[1]
    if word == "" then Say(Ar, AlarmState(alarm)) return true end
    local pc = HostOnly(Ar, "change the alarm", FullCommand)
    if not pc then return true end

    if word == "off" then
        if not alarm["AlarmEnabled?"] then Say(Ar, "The alarm is already OFF") return true end
        local levers = AlarmLevers(alarms)
        local pawn = Valid(pc.Pawn) and pc.Pawn or nil
        for _, lever in ipairs(levers) do
            local clicked = pawn and pcall(function() lever[LEVER_CLICK](lever, pawn, lever:K2_GetRootComponent()) end)
            if not clicked then lever:SwitchLeverServer() end
        end
        -- No lever (the tutorial), or one that was already pulled: the alarm's own hacked event.
        for _, a in ipairs(alarms) do
            if a["AlarmEnabled?"] then a:DeactivateAlarm() end
        end
        Say(Ar, AlarmState(alarm) .. (alarm["HasAlarmTriggered?"] and ", so the police keep coming" or ""))
    elseif word == "on" then
        for _, a in ipairs(alarms) do SetReplicated(a, "AlarmEnabled?", true) end
        for _, lever in ipairs(AlarmLevers(alarms)) do
            SetReplicated(lever, "Switched?", false)
            pcall(function() lever.SpottedHighlightcomponent["CanHighlight?"] = true end)
        end
        Say(Ar, AlarmState(alarm) .. ". The alarm box can be used again")
    else
        for _, a in ipairs(alarms) do a:TriggerAlarmInterface() end
        Say(Ar, "Alarm triggered: the heist is loud")
    end
    return true
end)

-- PoliceWaveSpawner: ForceNewWave and SpecialsWave are its own events; police are NPC_Police_base_C
-- and its subclasses (regular, helmet, swat, specials). clear removes them the way the escape does
-- with every NPC (DestroyActor); the spawner keeps sending waves while the heist is loud.
Core.Command("cops", function(FullCommand, Parameters, Ar)
    local word = Parameters and Parameters[1] and Parameters[1]:lower() or ""
    local spawner = AllOf("PoliceWaveSpawner_C")[1]
    local police = AllOf("NPC_Police_base_C")
    if word == "" then
        Say(Ar, string.format("Police here: %d%s", #police,
            spawner and (", wave " .. Fmt(spawner.WaveNumber or 0)) or ""))
        return true
    end
    if word ~= "wave" and word ~= "specials" and word ~= "clear" then
        Say(Ar, "Usage: cops   |   cops wave   |   cops specials   |   cops clear")
        return true
    end
    if not HostOnly(Ar, "control the police", FullCommand) then return true end
    if word == "clear" then
        for _, cop in ipairs(police) do cop:K2_DestroyActor() end
        Say(Ar, "Removed " .. #police .. " police")
        return true
    end
    if not Valid(spawner) then Say(Ar, "No police spawner here (only in a heist)") return true end
    if word == "wave" then spawner:ForceNewWave() else spawner:SpecialsWave() end
    Say(Ar, word == "wave" and "Sent a new police wave" or "Sent a special police wave")
    return true
end)

-- Security cameras are CameraBP_C pawns. cameras off removes them (DestroyActor, as the engine's
-- destroytarget does), so there is no broken camera for guards to notice. A player can be looking
-- through one from the security room (the camera is then possessed): their camera view is closed
-- first (RemoveCameraUI, while it is still theirs) and, a moment later, the camera's own
-- PossessPlayer puts them back in their character before that camera goes.
-- cameras destroy breaks them the way shooting does (DestroyCamera: Destroyed? = true, it stops
-- spotting, its head drops); guards may notice those.
Core.Command("cameras", function(FullCommand, Parameters, Ar)
    local word = Parameters and Parameters[1] and Parameters[1]:lower() or ""
    local cameras = AllOf("CameraBP_C")
    local working = {}
    for _, cam in ipairs(cameras) do
        if not cam["Destroyed?"] then working[#working + 1] = cam end
    end
    if word == "" then
        Say(Ar, string.format("Security cameras: %d working, %d destroyed", #working, #cameras - #working))
        return true
    end
    if word ~= "off" and word ~= "destroy" then
        Say(Ar, "Usage: cameras   |   cameras off (remove them, guards do not notice)   |   cameras destroy (break them)")
        return true
    end
    if not HostOnly(Ar, word == "off" and "remove the cameras" or "destroy the cameras", FullCommand) then return true end
    if word == "destroy" then
        for _, cam in ipairs(working) do cam:DestroyCamera() end
        Say(Ar, "Destroyed " .. #working .. " security cameras (as shooting them; guards may notice)")
        return true
    end
    local watched = 0
    for _, cam in ipairs(cameras) do
        if cam["Possessed?"] then
            watched = watched + 1
            pcall(function() cam:RemoveCameraUI() end)
            ExecuteWithDelay(300, function()
                ExecuteInGameThread(function()
                    if not Valid(cam) then return end
                    pcall(function() cam:PossessPlayer() end)
                    cam:K2_DestroyActor()
                end)
            end)
        else
            cam:K2_DestroyActor()
        end
    end
    Say(Ar, "Removed " .. #cameras .. " security cameras" ..
        (watched > 0 and string.format(" (%d being watched: that player is back in their character)", watched) or ""))
    return true
end)

-- BP_TypeableKeypad keeps its code in CorrectCode, which every player's game gets. Unlock is what
-- hacking the keypad does.
Core.Command("codes", function(FullCommand, Parameters, Ar)
    local word = Parameters and Parameters[1] and Parameters[1]:lower() or ""
    if word ~= "" and word ~= "open" then Say(Ar, "Usage: codes   |   codes open") return true end
    local keypads = AllOf("BP_TypeableKeypad_C")
    if #keypads == 0 then Say(Ar, "No keypads here") return true end
    if word == "open" then
        if not HostOnly(Ar, "open the keypads", FullCommand) then return true end
        for _, k in ipairs(keypads) do k:Unlock() end
        Say(Ar, "Unlocked " .. #keypads .. " keypads")
        return true
    end
    local pc = Robber()
    local here = pc and Valid(pc.Pawn) and pc.Pawn:K2_GetActorLocation()
    local list = {}
    for _, k in ipairs(keypads) do
        local ok, code = pcall(function() return k.CorrectCode:ToString() end)
        local metres
        if here then
            local at = k:K2_GetActorLocation()
            metres = math.sqrt((at.X - here.X) ^ 2 + (at.Y - here.Y) ^ 2 + (at.Z - here.Z) ^ 2) / 100
        end
        list[#list + 1] = { code = ok and code ~= "" and code or "(none yet)", metres = metres }
    end
    table.sort(list, function(a, b) return (a.metres or 0) < (b.metres or 0) end)
    Say(Ar, "Keypad codes, nearest first:")
    for _, k in ipairs(list) do
        Say(Ar, "  " .. k.code .. (k.metres and string.format("   (%d m away)", math.floor(k.metres + 0.5)) or ""))
    end
    return true
end)

-- Loot is Money_base_C and its subclasses. Each piece not held by a player, not stuck in a bag or
-- to anything else, and not already in the truck is teleported above the truck's money area
-- (MoneyOverlapper) in a stack; landing in it counts it the game's own way (CountMoney).
Core.Command("bringloot", function(FullCommand, Parameters, Ar)
    if not HostOnly(Ar, "move the loot", FullCommand) then return true end
    local truck = FindFirstOf("RobberTruck_C")
    if not Valid(truck) then Say(Ar, "Only during a heist: there is no getaway truck here") return true end
    local area = truck.MoneyOverlapper
    local spot = area:K2_GetComponentLocation()
    local held = {}
    for _, c in ipairs(Players()) do
        local h = c.HoldingActor
        if Valid(h) then held[h:GetAddress()] = true end
    end
    local perLayer = V.BringLootColumns * V.BringLootRows
    local moved, value = 0, 0
    for _, loot in ipairs(AllOf("Money_base_C")) do
        local parent = loot:GetAttachParentActor()
        if not held[loot:GetAddress()] and not Valid(parent) and not area:IsOverlappingActor(loot) then
            local i = moved % perLayer
            local layer = math.floor(moved / perLayer)
            local col, row = i % V.BringLootColumns, math.floor(i / V.BringLootColumns)
            local to = {
                X = spot.X + (col - (V.BringLootColumns - 1) / 2) * V.BringLootSpacing,
                Y = spot.Y + (row - (V.BringLootRows - 1) / 2) * V.BringLootSpacing,
                Z = spot.Z + 40 + layer * V.BringLootLayerHeight,
            }
            loot:K2_SetActorLocation(to, false, {}, true)
            moved = moved + 1
            value = value + (loot.Value or 0)
        end
    end
    Say(Ar, string.format("Moved %d pieces of loot worth %s into the truck", moved, Fmt(value)))
    return true
end)

-- LeaveButton.EndGame is what pressing the escape button does: if the truck's CanEndGame? is set
-- (everyone in it and the minimum take reached), it counts the money and every player gets the
-- win screen. escape sets CanEndGame? first, so nobody has to be in the truck.
Core.Command("escape", function(FullCommand, Parameters, Ar)
    if not HostOnly(Ar, "end the heist", FullCommand) then return true end
    local truck, button = FindFirstOf("RobberTruck_C"), FindFirstOf("LeaveButton_C")
    if not (Valid(truck) and Valid(button)) then Say(Ar, "Only during a heist: there is no getaway truck here") return true end
    SetReplicated(truck, "CanEndGame?", true)
    button:EndGame()
    Say(Ar, "Escaping with " .. Fmt(truck.TotalTake) .. " in the truck")
    return true
end)

-- infiniteammo (anyone, your own guns): after every shot the gun's magazine is full again. The
-- shot itself (GunBase.ShootClient) runs on the shooter's own game, so this works as a guest too.
State.infiniteAmmo = State.infiniteAmmo or false

local function MyPawn()
    local pc = Robber()
    return pc and Valid(pc.Pawn) and pc.Pawn or nil
end

-- Placed the first time infiniteammo is turned on, not at startup (see truckmoney's hooks).
local function HookShots()
    State.shotHooked = Core.Hook("/Game/BP/Guns/GunBase.GunBase_C:ShootClient", function(Self)
        if not State.infiniteAmmo then return end
        -- Runs on every shot: ask the gun's owner whether this game controls it, no object search.
        local gun = Self:get()
        if Valid(gun) and Valid(gun.OwnerPlayer) and gun.OwnerPlayer:IsLocallyControlled() then
            gun.BulletsLeft = gun.MagSize
        end
    end) or nil
    return State.shotHooked
end
-- After reloadconfig: point the hook at this code, or keep trying if it was not placed yet.
if State.shotHooked then HookShots() elseif State.infiniteAmmo then HookWhenLoaded(HookShots) end

Core.Command("infiniteammo", function(FullCommand, Parameters, Ar)
    local word = Parameters and Parameters[1] and Parameters[1]:lower()
    if word == "on" then State.infiniteAmmo = true
    elseif word == "off" then State.infiniteAmmo = false
    else State.infiniteAmmo = not State.infiniteAmmo end
    if State.infiniteAmmo and not State.shotHooked then HookWhenLoaded(HookShots) end
    local me = MyPawn()
    if State.infiniteAmmo and me and Valid(me.HoldingGun) then me.HoldingGun.BulletsLeft = me.HoldingGun.MagSize end
    if not State.infiniteAmmo then
        Say(Ar, "Infinite ammo off")
    elseif State.shotHooked then
        Say(Ar, "Infinite ammo on: your magazine refills after every shot")
    else
        Say(Ar, "Infinite ammo on: it starts working in a heist, once the guns are loaded")
    end
    return true
end)

--------------------------------------------------------------------------------------------------
-- doors  (host; a guest's go to the host through command sharing)
--
--    doors                  how many doors are locked and open, and the vault
--    doors unlock           unlock the door you are looking at; it stays shut
--    doors unlock all       unlock every door in the map
--    doors open [all]       open the door you are looking at (or every door), unlocking it first
--    doors close [all]      close it (or every open door)
--    doors vault            whether the vault is open
--    doors vault open       open the vault. It can NOT be closed again: the game has no way to
--    door ...               the same as doors
--
-- Doors are DoorBP_C and its subclasses: lock-picked doors (DoorBP_Locked_C, and
-- DoorBP_Locked_Alarm_C whose lock sets off the alarm when picked) and the keycard, hacked and
-- hand-scanner doors (plain DoorBP_C). A door is locked while Locked? is set, or while
-- PowerLocked? is set once the alarm has gone off (AlarmTriggered?).
-- Unlocking uses the door's own UnlockDoor, a multicast every player's game runs (Locked? off,
-- the "Door" name), after clearing PowerLocked? (UnlockDoor keeps it once the alarm went off).
-- Unlike picking an alarm lock, no alarm goes off. The game has no way to lock a door again.
-- Opening and closing use the door's own OpenDoorServer, which TOGGLES the door, so it is only
-- called on a door that is not already open (or shut) and not swinging (Opening?). The door
-- itself is passed as the player who opens it, so no guard is alerted.
-- The vault (VaultDoor_C: VaultDefault_C, Vault_DoorRectangle_C) opens with its own OpenVault, as
-- hacking or drilling it does, and the police waves pause for 30 seconds as in the game. Nothing
-- in the game closes it, and players who join afterwards see it shut but can walk through.
-- As a guest these go to the host, aimed from your own camera (command sharing level 2 or 3).
--------------------------------------------------------------------------------------------------
local DOOR_CLASS = "/Game/BP/Utility/DoorBP.DoorBP_C"
local VAULT_CLASS = "/Game/BP/Utility/Vaults/VaultDoor.VaultDoor_C"

local function DoorLocked(door)
    return (door["Locked?"] or (door["PowerLocked?"] and door["AlarmTriggered?"])) and true or false
end

-- The door an actor belongs to: the actor itself, or the door it is part of (a door's locks and
-- its inside unlock handle are child actors of the door).
local function DoorOf(actor, cls)
    for _ = 1, 4 do
        if not Valid(actor) then return nil end
        if actor:IsA(cls) then return actor end
        local parent
        pcall(function() parent = actor:GetParentActor() end)
        if not Valid(parent) then pcall(function() parent = actor:GetAttachParentActor() end) end
        actor = parent
    end
    return nil
end

-- The one of candidates (objects of cls) pc is looking at (pose: a guest's camera). When the line
-- hits something next to one (a door's frame, the floor by a guard), the nearest within radius
-- of that spot counts. where(object): its position (default: the actor's location).
local function LookedAtOneOf(pc, pose, cls, candidates, radius, where)
    local actor, hit = LookedAtActor(pc, pose)
    local found = DoorOf(actor, cls)
    if found or not hit then return found end
    local at, best, bestDistance = hit.Location, nil, radius * radius
    if not at then return nil end
    for _, d in ipairs(candidates) do
        local p = where and where(d) or d:K2_GetActorLocation()
        local distance = (p.X - at.X) ^ 2 + (p.Y - at.Y) ^ 2 + (p.Z - at.Z) ^ 2
        if distance < bestDistance then best, bestDistance = d, distance end
    end
    return best
end

-- Unlock one door the game's way. Returns true when it was locked, or power-locked (which locks
-- it once the alarm goes off).
local function UnlockOneDoor(door)
    local afterAlarm = door["PowerLocked?"] and door["AlarmTriggered?"]
    if not (door["Locked?"] or door["PowerLocked?"]) then return false end
    pcall(function() door:FlushNetDormancy() end)
    if door["PowerLocked?"] then SetReplicated(door, "PowerLocked?", false) end
    door:UnlockDoor()
    -- A guest's game may run UnlockDoor before PowerLocked? reaches it and name the door
    -- "Door (Powerlocked)"; the game's own name call comes after it and puts "Door" back.
    if afterAlarm then pcall(function() door:SetDoorName("Door") end) end
    return true
end

-- Open or close one door. Returns true when it started to move.
local function MoveOneDoor(door, open)
    if door["Opening?"] or (door["Open?"] and true or false) == open then return false end
    if open then UnlockOneDoor(door) end
    pcall(function() door:FlushNetDormancy() end)
    door:OpenDoorServer(door, V.DoorOpenTime, false, true)
    return true
end

local function DoorSummary(doors)
    local locked, open = 0, 0
    for _, d in ipairs(doors) do
        if DoorLocked(d) then locked = locked + 1 end
        if d["Open?"] then open = open + 1 end
    end
    return string.format("Doors: %d (%d locked, %d open)", #doors, locked, open)
end

local function VaultSummary(vaults)
    if #vaults == 0 then return "No vault here" end
    local open = 0
    for _, v in ipairs(vaults) do
        if v["Open?"] then open = open + 1 end
    end
    if #vaults == 1 then return open == 1 and "The vault is open" or "The vault is shut" end
    return string.format("Vaults: %d (%d open)", #vaults, open)
end

local DOORS_USAGE = "Usage: doors   |   doors unlock [all]   |   doors open [all]   |   doors close [all]   |   " ..
    "doors vault   |   doors vault open"

local function DoorsCommand(FullCommand, Parameters, Ar)
    local p = Parameters or {}
    local verb, scope = (p[1] or ""):lower(), (p[2] or ""):lower()
    local all = scope == "all"
    local known = verb == "" or ((verb == "unlock" or verb == "open" or verb == "close") and (scope == "" or all))
        or (verb == "vault" and (scope == "" or scope == "open" or scope == "close"))
    if not known then Say(Ar, DOORS_USAGE) return true end
    local doors, vaults = AllOf("DoorBP_C"), AllOf("VaultDoor_C")
    if verb == "" then
        Say(Ar, DoorSummary(doors) .. ". " .. VaultSummary(vaults))
        return true
    end

    if verb == "vault" then
        if scope == "" then Say(Ar, VaultSummary(vaults)) return true end
        if scope == "close" then
            Say(Ar, "The vault cannot be closed: the game has no way to close it once it is open")
            return true
        end
        if #vaults == 0 then Say(Ar, "No vault here") return true end
        if not HostOnly(Ar, "open the vault", FullCommand) then return true end
        local opened = 0
        for _, v in ipairs(vaults) do
            if not v["Open?"] then
                pcall(function() v:FlushNetDormancy() end)
                v:OpenVault()
                opened = opened + 1
            end
        end
        if opened == 0 then Say(Ar, "The vault is already open") return true end
        Say(Ar, string.format("Opened %s. WARNING: it cannot be closed again, the game has no way to close it. " ..
            "Police waves pause for 30 seconds", opened == 1 and "the vault" or (opened .. " vaults")))
        return true
    end

    if #doors == 0 then Say(Ar, "No doors here (only in a heist)") return true end
    local what = (verb == "unlock" and "unlock doors") or (verb == "open" and "open doors") or "close doors"
    if not HostOnly(Ar, what, FullCommand, { aim = not all }) then return true end
    local targets = doors
    if not all then
        local pc, pose = Acting()
        local cls = StaticFindObject(DOOR_CLASS)
        local door = pc and Valid(cls) and LookedAtOneOf(pc, pose, cls, doors, V.DoorAimRadius) or nil
        if not door then
            Say(Ar, "Not looking at a door (doors " .. verb .. " all does every door)")
            return true
        end
        targets = { door }
    end
    local changed = 0
    for _, d in ipairs(targets) do
        local ok, did
        if verb == "unlock" then ok, did = pcall(UnlockOneDoor, d) else ok, did = pcall(MoveOneDoor, d, verb == "open") end
        if ok and did then changed = changed + 1 end
        if not ok then Print("doors " .. verb .. ": " .. tostring(did)) end
    end
    if not all then
        local done = { unlock = "Unlocked the door (it stays shut)", open = "Opened the door", close = "Closed the door" }
        local already = { unlock = "That door is not locked", open = "That door is already open (or swinging)",
                          close = "That door is already shut (or swinging)" }
        Say(Ar, changed > 0 and done[verb] or already[verb])
        return true
    end
    local done = { unlock = "Unlocked %d doors (they stay shut)", open = "Opening %d doors", close = "Closing %d doors" }
    Say(Ar, string.format(done[verb], changed) .. ". " .. DoorSummary(doors))
    return true
end

Core.Command("doors", DoorsCommand)
Core.Command("door", DoorsCommand)

--------------------------------------------------------------------------------------------------
-- guards  (host; a guest's go to the host through command sharing)
--
--    guards                    how many guards are alive, alert and down, and the phones ringing
--    guards kill [all]         the guard you look at (all: every guard), as if shot
--    guards remove [all]       the guard you look at (all: every guard and body), gone from the heist
--    guards phones             the phones of guards that went down
--    guards phones answer      check every ringing phone in, as a scanner does: no alarm
--    guards phones remove      take the phones away (one a player holds is answered instead)
--
-- Guards are NPC_Guard_C. kill is the game's own damage (TakeDamage with all of the guard's
-- health, from you): Die runs on every player's game, the guard drops the gun, you get the game's
-- 1 XP, and other guards can find the body. A guard who was not alert drops a phone, as any guard
-- you take down does.
-- remove takes the guard out (DestroyActor): no body and no phone. A keycard on the guard's belt
-- drops to the floor first, and a player the guard was escorting out is let go.
-- A guard's phone (GuardPhone_C) counts SecondsToAlert down (15, more with the skill) and then
-- alerts every guard ("Guard did not check in"). answer is what carrying it to a scanner
-- (GuardScanPoint) does: the phone's own StopPhoneAlert (it stops, with the success sound) and an
-- empty countdown text, without using up a scanner.
-- The counts work on a guest's own game; the rest goes to the host (command sharing level 2 or 3),
-- aimed from your own camera.
--------------------------------------------------------------------------------------------------
local RingingPhones                   -- the Heist tab shows them too

do                                    -- (a block: config.lua is near Lua's limit of 200 locals)
    local GUARD_CLASS = "/Game/BP/NPC/NPC_Guard.NPC_Guard_C"

    -- An object parameter the game gets as None (UE4SS 3.0.1 cannot pass nil).
    local function NoObject() return StaticFindObject("/Script/UMG.OARCommands_NoSuchObject") end

    -- "1 guard", "2 guards"
    local function Many(n, one, many) return n .. " " .. (n == 1 and one or many) end

    -- Where a guard is: the body, also once it fell somewhere else than where the guard stood.
    local function GuardSpot(guard)
        local ok, at = pcall(function() return guard.Mesh:K2_GetComponentLocation() end)
        if ok and at then return at end
        return guard:K2_GetActorLocation()
    end

    local function GuardSummary(guards)
        local alive, alert = 0, 0
        for _, g in ipairs(guards) do
            if not g["Dead?"] then
                alive = alive + 1
                if g["Alert?"] then alert = alert + 1 end
            end
        end
        return string.format("Guards: %d alive%s, %d down", alive,
            alert > 0 and string.format(" (%d alert)", alert) or "", #guards - alive)
    end

    -- The phones still counting down, and the fewest seconds one has left.
    function RingingPhones(phones)
        local ringing, soonest = {}, nil
        for _, p in ipairs(phones) do
            if p["Active?"] then
                ringing[#ringing + 1] = p
                local left = (p.SecondsToAlert or 0) + 1        -- it alerts once the count goes below 0
                if not soonest or left < soonest then soonest = left end
            end
        end
        return ringing, soonest
    end

    local function PhoneSummary(phones)
        local ringing, soonest = RingingPhones(phones)
        if #ringing == 0 then
            return #phones > 0 and string.format("Phones: none ringing (%d answered or done)", #phones) or "Phones: none"
        end
        return string.format("Phones: %d ringing, the first alerts the guards in %d s", #ringing, math.max(soonest, 0))
    end

    -- Kill one guard the game's way. killer: the character who gets the credit (their phone skill
    -- sets how long the phone rings), or nil.
    local function KillGuard(guard, killer)
        if guard["Dead?"] then return false end
        pcall(function() guard:FlushNetDormancy() end)
        guard:TakeDamage(math.max(guard.Health or 0, 1), Valid(killer) and killer or NoObject())
        return true
    end

    local function RemoveGuard(guard)
        pcall(function()
            if Valid(guard.AttachedKeycard) then guard.PhysicsConstraint:BreakConstraint() end
        end)
        pcall(function()
            local player = guard.EscortingPlayer
            if guard["Escorting?"] and Valid(player) then SetReplicated(player, "Escorted?", false) end
        end)
        guard:K2_DestroyActor()
    end

    local function AnswerPhone(phone)
        if not phone["Active?"] then return false end
        pcall(function() phone:FlushNetDormancy() end)
        phone:StopPhoneAlert()
        pcall(function() phone:CountdownText(FText("")) end)
        return true
    end

    -- Take a phone away: "removed", or "held" when a player holds it (it is answered instead and
    -- stays in their hands).
    local function RemovePhone(phone)
        local held = false
        pcall(function() held = phone.PickupItemComponent["Picked up?"] == true end)
        if held then
            AnswerPhone(phone)
            return "held"
        end
        SetReplicated(phone, "Active?", false)                  -- its countdown stops with it
        phone:K2_DestroyActor()
        return "removed"
    end

    local USAGE = "Usage: guards   |   guards kill [all]   |   guards remove [all]   |   guards phones   |   " ..
        "guards phones answer   |   guards phones remove"

    local function PhonesCommand(FullCommand, scope, phones, Ar)
        if scope == "" then Say(Ar, PhoneSummary(phones)) return end
        local what = scope == "answer" and "answer the guards' phones" or "remove the guards' phones"
        if not HostOnly(Ar, what, FullCommand) then return end
        local answered, removed, held = 0, 0, 0
        for _, phone in ipairs(phones) do
            local ok, result
            if scope == "answer" then ok, result = pcall(AnswerPhone, phone) else ok, result = pcall(RemovePhone, phone) end
            if not ok then Print("guards phones " .. scope .. ": " .. tostring(result))
            elseif result == true then answered = answered + 1
            elseif result == "removed" then removed = removed + 1
            elseif result == "held" then held = held + 1 end
        end
        if scope == "answer" then
            Say(Ar, answered > 0 and ("Answered " .. Many(answered, "phone", "phones") .. ": those guards will not be missed")
                or "No phone is ringing")
        else
            Say(Ar, "Removed " .. Many(removed, "phone", "phones") ..
                (held > 0 and string.format(" (%d in a player's hands: answered instead)", held) or ""))
        end
    end

    Core.Command("guards", function(FullCommand, Parameters, Ar)
        local p = Parameters or {}
        local verb, scope = (p[1] or ""):lower(), (p[2] or ""):lower()
        local all = scope == "all"
        local known = verb == "" or ((verb == "kill" or verb == "remove") and (scope == "" or all))
            or (verb == "phones" and (scope == "" or scope == "answer" or scope == "remove"))
        if not known then Say(Ar, USAGE) return true end
        local guards, phones = AllOf("NPC_Guard_C"), AllOf("GuardPhone_C")
        if verb == "" then Say(Ar, GuardSummary(guards) .. ". " .. PhoneSummary(phones)) return true end
        if verb == "phones" then PhonesCommand(FullCommand, scope, phones, Ar) return true end

        if #guards == 0 then Say(Ar, "No guards here (only in a heist)") return true end
        if not HostOnly(Ar, verb .. " guards", FullCommand, { aim = not all }) then return true end
        local pc, pose = Acting()
        local targets = guards
        if not all then
            local cls = StaticFindObject(GUARD_CLASS)
            local guard = pc and Valid(cls) and LookedAtOneOf(pc, pose, cls, guards, V.GuardAimRadius, GuardSpot) or nil
            if not guard then
                Say(Ar, "Not looking at a guard (guards " .. verb .. " all does every guard)")
                return true
            end
            targets = { guard }
        end
        local killer = pc and Valid(pc.Pawn) and pc.Pawn or nil
        local ringingBefore = #RingingPhones(phones)
        local done, bodies = 0, 0
        for _, g in ipairs(targets) do
            local wasDown = g["Dead?"] and true or false
            local ok, did
            if verb == "kill" then ok, did = pcall(KillGuard, g, killer) else ok, did = pcall(function() RemoveGuard(g) return true end) end
            if ok and did then
                done = done + 1
                if wasDown then bodies = bodies + 1 end
            end
            if not ok then Print("guards " .. verb .. ": " .. tostring(did)) end
        end
        if verb == "remove" then
            if not all then Say(Ar, bodies > 0 and "Removed the body" or "Removed the guard") return true end
            Say(Ar, "Removed " .. Many(done - bodies, "guard", "guards") .. " and " .. Many(bodies, "body", "bodies"))
            return true
        end
        local rang = #RingingPhones(AllOf("GuardPhone_C")) - ringingBefore
        local phonesNote = rang > 0 and string.format(". %d phone%s ringing: guards phones answer stops %s",
            rang, rang == 1 and " is" or "s are", rang == 1 and "it" or "them") or ""
        if not all then
            Say(Ar, done > 0 and ("Killed the guard" .. phonesNote) or "That guard is already down")
            return true
        end
        Say(Ar, done > 0 and ("Killed " .. Many(done, "guard", "guards") .. phonesNote) or "Every guard is already down")
        return true
    end)
end

--------------------------------------------------------------------------------------------------
-- selectmap, forcemap  (host only)
--
--    selectmap             list the heists and show which one is selected
--    selectmap <heist>     in the lobby: pick the heist, the same call the map screen makes.
--                          Everyone still readies up and the countdown runs as usual.
--    forcemap              in the lobby: start the selected heist now for everyone, with no
--                          ready-up and no countdown
--    forcemap <map>        pick it and start it now. Also takes any other map in the game by
--                          file name (testmap, tutorial_loud, mainmenu...), and works from
--                          inside a heist to go straight to another map.
--
-- Names: the short name (datacenter), the heist's title (data center), or the map file
-- (map_aidatacenter); a unique start is enough.
--
-- How a heist starts in the game: the host's lobby menu waits until every player is ready,
-- counts down, and then runs its StartGame (close the lobby to new players, clean up the lobby
-- characters, "servertravel <map file>"). forcemap marks every lobby player ready on the host
-- and calls that same StartGame, so the game's own start runs, only without the wait.
-- Outside the lobby there is no menu to ask, so forcemap travels with the engine's servertravel,
-- the command the game itself uses to bring everyone back to the lobby after a heist.
--
-- Heists sold for coins are only picked or started when the game itself counts them as yours,
-- by the same test the map screen uses (in your Steam inventory, or in your unlocked maps).
-- Level requirements are not checked.
--------------------------------------------------------------------------------------------------
-- Heists first (by short name, title or map file), then the other map files.
-- Returns { heist = entry } or { file = name }, or nil and a message.
local function ResolveMap(text)
    local want = Squash(text)
    if want == "" then return nil, "no map name given" end
    local exact, starts, contains = {}, {}, {}
    local function try(names, result, label)
        local rank
        for _, n in ipairs(names) do
            if n == want then rank = 1
            elseif n:sub(1, #want) == want then rank = math.min(rank or 2, 2)
            elseif n:find(want, 1, true) then rank = math.min(rank or 3, 3) end
            if rank == 1 then break end
        end
        if rank then
            local list = (rank == 1 and exact) or (rank == 2 and starts) or contains
            list[#list + 1] = { result = result, label = label }
        end
    end
    for _, h in ipairs(Maps.Heists) do
        try({ Squash(h.key), Squash(h.name), Squash(h.file) }, { heist = h }, h.key)
    end
    for _, f in ipairs(Maps.Other) do
        try({ Squash(f) }, { file = f }, f)
    end
    local pool = (#exact > 0 and exact) or (#starts > 0 and starts) or contains
    if #pool == 1 then return pool[1].result end
    if #pool == 0 then return nil, "no map called '" .. text .. "' (selectmap lists the heists)" end
    local names = {}
    for i = 1, math.min(#pool, 8) do names[i] = pool[i].label end
    return nil, string.format("'%s' matches %d maps: %s%s", text, #pool, table.concat(names, ", "), #pool > 8 and ", ..." or "")
end

local function Lobby()
    local lm = FindFirstOf("LobbyManager_C")
    if Valid(lm) then return lm end
    return nil
end

-- The game's own test for a heist sold for coins (the map screen's "Unlocked?"): the heist is
-- in the list of maps you unlocked, or its item is in your Steam inventory.
local function OwnsHeist(pc, heist, cls)
    if heist.coin <= 0 then return true end
    local unlocked = pc.UnlockedMaps
    for i = 1, unlocked:GetArrayNum() do
        local c = unlocked[i]
        if Valid(c) and c:GetAddress() == cls:GetAddress() then return true end
    end
    local items = pc.InventoryResultItems
    for i = 1, items:GetArrayNum() do
        if items[i].Definition.Value == heist.item then return true end
    end
    return false
end

-- The heist the lobby has selected right now, as an entry of maps.lua (or nil).
local function SelectedHeist(lm)
    local ok, path = pcall(function()
        local cls = lm.SelectedMap
        if not Valid(cls) then return nil end
        return cls:GetFullName():match("%s(%S+)$")
    end)
    if not ok or not path then return nil end
    for _, h in ipairs(Maps.Heists) do
        if h.path == path then return h end
    end
    return nil
end

-- The lobby menu on your screen (old ones from earlier visits may still be in memory).
local function LobbyMenu()
    for _, ui in pairs(FindAllOf("MainMenuUI_C") or {}) do
        if ui:IsValid() and ui:IsInViewport() then return ui end
    end
    return nil
end

local function StartHeistNow()
    local ui = LobbyMenu()
    if not ui then return nil, "the lobby menu is not on screen" end
    for _, player in pairs(FindAllOf("MainMenuPlayer_C") or {}) do
        if player:IsValid() then player["Ready?"] = true end
    end
    ui:StartGame()
    return true
end

local function HostController(Ar)
    local pc = Robber()
    if not pc then Say(Ar, "No local player yet") return nil end
    if not pc:HasAuthority() then
        Say(Ar, "Only the host picks the map")
        return nil
    end
    return pc
end

local function ListHeists(Ar)
    local lm = Lobby()
    local current = lm and SelectedHeist(lm)
    local pc = Robber()
    Say(Ar, "Heists (selectmap <name> to pick one, forcemap <name> to start it now):")
    for _, h in ipairs(Maps.Heists) do
        local notes = {}
        if current == h then notes[#notes + 1] = "selected" end
        if h.coin > 0 then
            local owned = false
            pcall(function()
                local cls = LoadClass(h.path)
                owned = pc ~= nil and cls ~= nil and OwnsHeist(pc, h, cls)
            end)
            notes[#notes + 1] = owned and "sold for coins, owned" or "sold for coins, not owned"
        end
        if h.level > 0 then notes[#notes + 1] = "level " .. h.level end
        Say(Ar, string.format("  %-20s %s%s", h.key, h.name, #notes > 0 and ("  (" .. table.concat(notes, "; ") .. ")") or ""))
    end
    Say(Ar, "forcemap also takes the other map files, for example: testmap, tutorial_loud, mainmenu")
end

-- Heist entry -> its class, or nil after saying why not.
local function UsableHeist(pc, heist, Ar)
    local cls = LoadClass(heist.path)
    if not cls then Say(Ar, "Could not load " .. heist.name) return nil end
    if not OwnsHeist(pc, heist, cls) then
        Say(Ar, heist.name .. " is sold for coins and is not in your Steam inventory, so it is left alone. " ..
            "selectmap and forcemap only take heists you own.")
        return nil
    end
    return cls
end

local function NameAfterCommand(FullCommand)
    return (FullCommand:match("^%s*%S+%s+(.-)%s*$")) or ""
end

Core.Command("selectmap", function(FullCommand, Parameters, Ar)
    local text = NameAfterCommand(FullCommand)
    if text == "" then ListHeists(Ar) return true end
    local pc = HostController(Ar)
    if not pc then return true end
    local target, err = ResolveMap(text)
    if not target then Say(Ar, err) return true end
    if not target.heist then
        Say(Ar, target.file .. " is not a heist, so the lobby cannot select it; forcemap " .. target.file:lower() .. " goes there")
        return true
    end
    local lm = Lobby()
    if not lm then
        Say(Ar, "selectmap works in the lobby. From a heist, forcemap " .. target.heist.key .. " goes straight there")
        return true
    end
    local cls = UsableHeist(pc, target.heist, Ar)
    if not cls then return true end
    lm:SelectMap(cls)
    Say(Ar, "Selected " .. target.heist.name .. ". Ready up as usual, or forcemap to start now")
    return true
end)

Core.Command("forcemap", function(FullCommand, Parameters, Ar)
    local pc = HostController(Ar)
    if not pc then return true end
    local text = NameAfterCommand(FullCommand)
    local lm = Lobby()
    if text == "" then
        if not lm then Say(Ar, "Usage: forcemap <map>   e.g.  forcemap museum") return true end
        local current = SelectedHeist(lm)
        if current and not UsableHeist(pc, current, Ar) then return true end
        local ok, why = StartHeistNow()
        Say(Ar, ok and ("Starting " .. (current and current.name or "the selected heist") .. " now") or ("Not started: " .. why))
        return true
    end
    local target, err = ResolveMap(text)
    if not target then Say(Ar, err) return true end
    local heist = target.heist
    if heist then
        local cls = UsableHeist(pc, heist, Ar)
        if not cls then return true end
        if lm then
            lm:SelectMap(cls)
            local ok, why = StartHeistNow()
            Say(Ar, ok and ("Starting " .. heist.name .. " now") or ("Selected " .. heist.name .. ", but not started: " .. why))
            return true
        end
        -- Not in the lobby: tell the game which heist it is, then travel like the game does.
        pcall(function()
            local gi = FindFirstOf("RobberGI_C")
            if Valid(gi) then gi:UpdateMap(cls) end
        end)
    end
    local file = heist and heist.file or target.file
    Say(Ar, "Travelling to " .. (heist and heist.name or file) .. " now")
    Share.RunEngine("servertravel " .. file)
    return true
end)

--------------------------------------------------------------------------------------------------
-- commandsharing, host
--
--    commandsharing [0-3]   (host) 0 off, 1 player commands, 2 player + world commands,
--                           3 everything except the block list. Starts at V.ShareLevelAtStart.
--    host <command>         (guest) send any command line to the host (for level 3)
--
-- A host lets guests who also have this mod run commands through the host's game, where they
-- have authority.
--
-- Guest to host: PlayerController.ServerExecRPC(string), a reliable client-to-server call whose
-- Validate is "return true" and whose body is empty in this shipping build, so it has no effect
-- in the game unless the host's mod reads it. Host to guest: PlayerController.ClientMessage,
-- which also prints the reply in the guest's console.
--
--    request  "oar1 <id> <command line>[ @x,y,z,pitch,yaw]"   (camera pose for aimed commands)
--    reply    "[OAR host] <id> ok <summary>" | "... off" | "... denied <reason>"
--
-- Failsafe: when you are not a guest, when the host does not answer within V.ShareTimeoutMs, or
-- answers off or denied, the command runs on your own game exactly as it would without sharing.
-- Every step runs in pcall; an error also means "run it yourself".
--------------------------------------------------------------------------------------------------
local NO_REPLY = "0"               -- request id for fire-and-forget updates (noclip speed)
local SharePlayer, ShareWorld = Set(V.SharePlayerCommands), Set(V.ShareWorldCommands)
local ShareBlocked, ShareAimed = Set(V.ShareBlockedCommands), Set(V.ShareAimedCommands)

-- Kept across reloadconfig: the level, your request ids, and requests still waiting for an answer.
State.share = State.share or {
    level = V.ShareLevelAtStart,
    pending = {}, counter = 0,
    session = string.format("%04x", math.random(0, 0xffff)),
    silentUntil = 0,                -- a host stayed silent: skip it until this time
    active = false,                 -- the last answer was ok
}
local S = State.share
local localOnly = 0                 -- >0 while a fallback runs: never relay then
local bypass = false                -- true while handing an engine cheat to the engine

-- Is `name` (lowercase) allowed at sharing `level`? Returns true, or false plus the reason.
function Share.Allowed(level, name)
    if level <= 0 then return false, "off" end
    if ShareBlocked[name] then return false, "blocked" end
    if level >= 3 or SharePlayer[name] then return true end
    if level >= 2 and ShareWorld[name] then return true end
    return false, level == 1 and "needs commandsharing 2 or 3" or "not allowed"
end

function Share.Encode(id, line, pose)
    local msg = V.ShareProtocol .. " " .. id .. " " .. line
    if pose then
        msg = msg .. string.format(" @%.0f,%.0f,%.0f,%.1f,%.1f", pose.x, pose.y, pose.z, pose.pitch, pose.yaw)
    end
    return msg
end

function Share.Decode(text)
    local prefix = V.ShareProtocol .. " "
    if text:sub(1, #prefix) ~= prefix then return nil end
    local id, rest = text:sub(#prefix + 1):match("^(%w+) (.+)$")
    if not id then return nil end
    local line, x, y, z, p, w = rest:match("^(.-)%s+@(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
    if line then
        return id, line, { x = tonumber(x), y = tonumber(y), z = tonumber(z), pitch = tonumber(p), yaw = tonumber(w) }
    end
    return id, rest, nil
end

-- A line in UE4SS.log and in your console (through your own ClientMessage), for results that
-- arrive after the command that caused them has finished.
function Share.Notice(text)
    Print(text)
    pcall(function() if State.menu and State.menu.open then State.menu:Status(text) end end)
    pcall(function()
        local pc = LocalPlayerController()
        if pc then pc:ClientMessage(V.ShareNoticePrefix .. text, FName("None"), 0.0) end
    end)
end

local function IsGuest(pc)
    local ok, auth = pcall(function() return pc:HasAuthority() end)
    return ok and auth == false
end

local function RunLocally(fn)
    localOnly = localOnly + 1
    local ok, err = pcall(fn)
    localOnly = localOnly - 1
    if not ok then Share.Notice("failed: " .. tostring(err)) end
end

-- An engine command handed to the engine unchanged, past this mod's own intercepts.
function Share.RunEngine(line)
    local pc = LocalPlayerController()
    if not pc then return end
    CheatManagerFor(pc)
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    bypass = true
    local ok, err = pcall(function() ksl:ExecuteConsoleCommand(pc, line, pc) end)
    bypass = false
    if not ok then Share.Notice("failed: " .. tostring(err)) end
end

local function CameraPose()
    local pc = LocalPlayerController()
    local cam = pc and pc.PlayerCameraManager
    if not (cam and cam:IsValid()) then return nil end
    local loc, rot = cam:GetCameraLocation(), cam:GetCameraRotation()
    return { x = loc.X, y = loc.Y, z = loc.Z, pitch = rot.Pitch, yaw = rot.Yaw }
end

-- Guest: send `line` to the host. Returns true when it went out; the command then finishes by
-- itself (the host runs it, or `fallback` runs here). Returns false when it should run here now.
-- opts: aim (send the camera pose), onOk (run here when the host did it too).
function Share.Relay(line, Ar, fallback, opts)
    opts = opts or {}
    if localOnly > 0 then return false end
    local ok, sent = pcall(function()
        local pc = Robber()
        if not pc or not IsGuest(pc) then return false end
        if os.time() < S.silentUntil then return false end
        S.counter = S.counter + 1
        local id = S.session .. S.counter
        local msg = Share.Encode(id, line, opts.aim and CameraPose() or nil)
        if #msg > V.ShareMaxMessage then return false end
        pc:ServerExecRPC(msg)
        S.pending[id] = { line = line, fallback = fallback, onOk = opts.onOk, hostOnly = opts.hostOnly }
        ExecuteWithDelay(V.ShareTimeoutMs, function()
            ExecuteInGameThread(function()
                local p = S.pending[id]
                if not p then return end
                S.pending[id] = nil
                S.active, S.silentUntil = false, os.time() + V.ShareSilentSeconds
                if p.hostOnly then
                    Share.Notice("the host did not answer, so nothing changed (only the host can " .. p.hostOnly .. ")")
                else
                    Share.Notice("the host did not answer, so '" .. p.line .. "' runs on your game")
                end
                if p.fallback then RunLocally(p.fallback) end
            end)
        end)
        return true
    end)
    return ok and sent == true
end

-- Guest: a one-way update while sharing is known to work (noclip speed while Shift changes).
function Share.Notify(line)
    if not S.active or localOnly > 0 then return end
    pcall(function()
        local pc = Robber()
        if pc and IsGuest(pc) then pc:ServerExecRPC(Share.Encode(NO_REPLY, line)) end
    end)
end

-- Guest: the host's answer arrived as a ClientMessage.
function Share.HandleReply(text)
    local id, status = text:sub(#V.ShareReplyPrefix + 1):match("^(%w+) (%a+)")
    local p = id and S.pending[id]
    if not p then return end
    S.pending[id] = nil
    if status == "ok" then
        S.active = true
        if p.onOk then RunLocally(p.onOk) end
    else
        S.active = false
        if p.hostOnly then
            Share.Notice("the host said " .. status .. ": only the host can " .. p.hostOnly .. ", so nothing changed")
        else
            Share.Notice("the host said " .. status .. ", so '" .. p.line .. "' runs on your game")
        end
        if p.fallback then RunLocally(p.fallback) end
    end
end

local function Reply(pc, id, text)
    if id == NO_REPLY then return end
    pcall(function() pc:ClientMessage(V.ShareReplyPrefix .. id .. " " .. text, FName("None"), 0.0) end)
end

local function PlayerName(pc)
    local ok, name = pcall(function() return pc.PlayerState.PlayerName:ToString() end)
    return ok and name or "a guest"
end

-- Host: run one guest command as that guest (their controller, their character, their aim).
local function ExecuteForGuest(pc, name, line, pose)
    local words = Words(line)
    table.remove(words, 1)
    if name == "summon" or name == "spawn" then return DoSummon(pc, words, nil) end
    if name == "summonstop" then return StopSummons() end
    if name == "dupe" then return DoDupe(pc, words, nil, pose) end
    if name == "revive" then return Revive(pc) end
    if name == "noclip" then
        local on = words[1] == "on"
        return SetNoclip(pc.Pawn, on, tonumber(words[2]), false)
    end
    if name == "destroytarget" and pose then return DestroyLookedAt(pc, pose) end
    if name == "teleport" and pose then return TeleportToLookedAt(pc, pose) end
    -- The mod's own commands run as its own code. Handed to the engine on the guest's controller
    -- they would never reach the mod: the mod only answers commands typed in the console window.
    -- What the command says becomes the guest's answer; Acting() gives it the guest's controller
    -- and camera.
    local own = Core.OwnCommand(name)
    if own then
        local said = {}
        local answer = { Log = function(_, text) said[#said + 1] = text end }
        Guest = { pc = pc, pose = pose }
        local ok, problem = pcall(own, line, words, answer)
        Guest = nil
        if not ok then return name .. " failed: " .. tostring(problem) end
        return #said > 0 and table.concat(said, " | ") or line
    end
    CheatManagerFor(pc)
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    ksl:ExecuteConsoleCommand(pc, line, pc)
    return line
end

-- Host: a guest's request arrived (hook on ServerExecRPC).
function Share.HandleRequest(pc, text)
    local id, line, pose = Share.Decode(text)
    if not id then return end
    if pc:IsLocalController() or not pc:HasAuthority() then return end
    local name = (line:match("^(%S+)") or ""):lower()
    local allowed, why = Share.Allowed(S.level, name)
    if not allowed then
        Reply(pc, id, why == "off" and "off" or ("denied " .. name .. ": " .. why))
        return
    end
    if id ~= NO_REPLY then Share.Notice(PlayerName(pc) .. " ran: " .. line) end
    local ok, summary = pcall(ExecuteForGuest, pc, name, line, pose)
    if ok then
        Reply(pc, id, "ok " .. tostring(summary or line))
    else
        Reply(pc, id, "denied error: " .. tostring(summary))
    end
end

Core.Command("commandsharing", function(FullCommand, Parameters, Ar)
    local n = tonumber(Parameters[1] or "")
    if n then
        n = math.floor(n)
        if n < 0 or n > 3 then Say(Ar, "Usage: commandsharing 0-3") return true end
        S.level = n
    end
    Say(Ar, string.format("Command sharing is %d: %s%s", S.level, V.ShareLevelNames[S.level],
        S.level > 0 and " (guests with OARCommands can run these through your game; back to 0 next launch)" or ""))
    local pc = Robber()
    if pc and IsGuest(pc) then Say(Ar, "You are a guest here: only the host's setting counts") end
    return true
end)

Core.Command("host", function(FullCommand, Parameters, Ar)
    local line = FullCommand:match("^%s*%S+%s+(.-)%s*$")
    if not line or line == "" then Say(Ar, "Usage: host <command>   e.g.  host stat fps") return true end
    local name = (line:match("^(%S+)") or ""):lower()
    local function here()
        local own = Core.OwnCommand(name)
        if own then
            local words = Words(line)
            table.remove(words, 1)
            own(line, words, nil)
        else
            Share.RunEngine(line)
        end
    end
    if Share.Relay(line, Ar, here, { aim = ShareAimed[name] }) then return true end
    here()
    return true
end)

-- Guest side of the engine cheats: go to the host when possible, otherwise let the engine run
-- them as usual (returning false hands the command on unchanged).
for lower, capital in pairs(V.ShareEngineCheatShortcuts and V.ShareEngineCheats or {}) do
    local function handler(FullCommand, Parameters, Ar)
        if bypass then return false end
        local ok, sent = pcall(Share.Relay, FullCommand, Ar, function() Share.RunEngine(FullCommand) end,
            { aim = ShareAimed[lower] })
        return ok and sent == true
    end
    Core.Intercept(lower, handler)
    Core.Intercept(capital, handler)
end

Core.Hook("/Script/Engine.PlayerController:ServerExecRPC", function(Context, Msg)
    local ok, err = pcall(function() Share.HandleRequest(Context:get(), Msg:get():ToString()) end)
    if not ok then Print("command sharing request failed: " .. tostring(err)) end
end)

Core.Hook("/Script/Engine.PlayerController:ClientMessage", function(Context, Message)
    pcall(function()
        local text = Message:get():ToString()
        if text:sub(1, #V.ShareReplyPrefix) == V.ShareReplyPrefix then
            Share.HandleReply(text)
            if State.menu and State.menu.open then State.menu:Status(text) end
        end
    end)
end)

--------------------------------------------------------------------------------------------------
-- toggledebugcamera fix
--
-- ToggleDebugCamera switches you to a separate DebugCameraController. In hosted games the engine
-- gives it no cheat manager (and UE4SS's CheatManagerEnablerMod only adds one when a controller
-- gets a body), so ToggleDebugCamera could not run again to switch back. Give it one as it spawns.
--------------------------------------------------------------------------------------------------
Core.OnNewObject("/Script/Engine.DebugCameraController", function(dcc)
    ExecuteInGameThread(function()
        if dcc:IsValid() then CheatManagerFor(dcc) end
    end)
end)

--------------------------------------------------------------------------------------------------
-- opengui: the in-game menu
--
--    opengui     open the menu; type it again (or press your key for it) to close it.
--                A key for it:  bind f1 opengui
--
-- A window in the game with a tab for each kind of command on the left: Player, Spawn, Heist,
-- Doors, Progress, World, Lobby and Settings. A tab shows only its own commands, in groups, each
-- with the choices and amounts it takes. The Spawn tab lists everything summon knows in groups
-- that open and close. The search box at the top finds what you type anywhere in a name, in the
-- tab you are on. Two switches at the top: Advanced shows the rarely used groups and the console
-- line each button runs; Full names shows class and object names (what you would type) instead of
-- readable names. Results show at the bottom of the window.
--
-- Every button runs the same command as the console, so everything works as it does there: as a
-- guest, host commands go to the host through command sharing. While the menu is open the game
-- gets no keys (they go to the menu); Escape, the X at the top, or your opengui key closes it.
--
-- What the menu shows is set up here (MenuTabs). The window itself is built from the engine's own
-- UI pieces by Scripts\gui.lua.
--------------------------------------------------------------------------------------------------
-- The whole menu is one function, run right here: its names stay inside it (Lua allows 200 names
-- at the top level of a file, and this file is close to that).
;(function()
local Gui = Core.Data("gui")

-- Run a command line for the menu: the mod's own commands as code, anything else through the
-- console. Returns the lines it printed.
local function MenuRun(line)
    local said = {}
    local out = { Log = function(_, text) said[#said + 1] = text end }
    local words = Words(line)
    local name = words[1] and string.lower(table.remove(words, 1))
    if not name then return said end
    local own = Core.OwnCommand(name)
    if own then
        local ok, problem = pcall(own, line, words, out)
        if not ok then said[#said + 1] = name .. " failed: " .. tostring(problem) end
        return said
    end
    local pc = LocalPlayerController()
    if not pc then return { "No local player yet" } end
    CheatManagerFor(pc)
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    ksl:ExecuteConsoleCommand(pc, line, pc)
    return { "Ran: " .. line }
end

-- The game's own cheats act where the character is decided: a guest asks the host
-- ("host <command>", which runs it on the guest's game when the host does not answer).
local function Cheat(line, menu)
    local pc = menu and menu.pc
    if pc and IsGuest(pc) then return "host " .. line end
    return line
end

local function Try(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function OnOff(on) return on and "ON" or "OFF" end

--------------------------------------------------------------------------------------------------
-- The Spawn tab's list: everything summon knows, in groups by where the game keeps it.
-- Groups marked advanced only show with the Advanced switch on.
--------------------------------------------------------------------------------------------------
local SPAWN_GROUPS = {
    { name = "Valuables", match = { "^/Game/BP/Items/Valuables/" } },
    { name = "Tools and items", match = { "^/Game/BP/Items/" } },
    { name = "Guns", match = { "^/Game/BP/Guns/[^/]+$", "^/Game/BP/Guns/Mags/" } },
    { name = "Gun attachments", match = { "^/Game/BP/Guns/Attachments/" } },
    { name = "Armor and explosives", match = { "^/Game/BP/Armor/", "^/Game/BP/Explosives/" } },
    { name = "Police and people", match = { "^/Game/BP/NPC/" } },
    { name = "Heist gear", match = { "^/Game/BP/Puzzle/", "^/Game/BP/Hacking/", "^/Game/BP/Utility/", "^/Game/BP/Camera/" } },
    { name = "Props", match = { "^/Game/BP/Other/", "^/Game/BP/Setups/", "^/Game/BP/BuildingBPS/" } },
    { name = "Gun skins and back guns", match = { "^/Game/BP/Guns/" }, advanced = true },
    { name = "Player gear", match = { "^/Game/BP/Player/", "^/Game/Animation/" }, advanced = true },
    { name = "Building pieces", match = { "^/Game/Assets/" }, advanced = true },
    { name = "Menu scenery", match = { "^/Game/Maps/" }, advanced = true },
    { name = "Everything else", match = { "" }, advanced = true },
}

-- "Valuable_wine_AmaroneRossoSegreto_C" -> "Valuable wine Amarone Rosso Segreto"
local function Readable(className)
    local s = className:gsub("_C$", ""):gsub("_", " ")
    s = s:gsub("(%l)(%u)", "%1 %2"):gsub("%s+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SpawnGroupOf(path)
    for i, g in ipairs(SPAWN_GROUPS) do
        for _, pattern in ipairs(g.match) do
            if path:find(pattern) then return i end
        end
    end
    return #SPAWN_GROUPS
end

-- { [group index] = { { label, full, typed, find }, ... } }, sorted by label.
local function BuildSpawnList()
    local groups = {}
    for i = 1, #SPAWN_GROUPS do groups[i] = {} end
    local labelOf = {}                    -- class path -> the game's own name for it (objects.lua)
    for key, entry in pairs(Objects) do
        if IsPlain(entry) and entry.label then labelOf[entry.path] = entry.label end
    end
    local function add(path, label, full, typed)
        local g = groups[SpawnGroupOf(path)]
        g[#g + 1] = { label = label, full = full, typed = typed,
                      find = string.lower(label .. " " .. full .. " " .. typed .. " " .. path) }
    end
    for key, entry in pairs(Spawnables) do
        add(entry.path, labelOf[entry.path] or Readable(entry.name), entry.name, key)
    end
    for key, entry in pairs(Objects) do
        if not IsPlain(entry) then add(entry.path, entry.label or key, key, key) end
    end
    for _, g in ipairs(groups) do
        table.sort(g, function(a, b) return a.label:lower() < b.label:lower() end)
    end
    return groups
end
local SpawnList = BuildSpawnList()

--------------------------------------------------------------------------------------------------
-- The tabs. build(ui) adds what the tab shows, every time it is drawn:
--    ui:Header(text, key)      a group title; with a key it opens and closes (closed at first)
--    ui:Row{ label, hint, info, input = { key, default, width }, chips = { { text, action }, ... } }
--                              a line with buttons ("chips"). action: a console line, where {}
--                              is this line's amount and {name} another line's (by its input
--                              key), or a function(inputs) returning lines to show
--                              confirm = "text": the first click asks, the second runs it
--    ui:Item{ label, sub, action }   a line that runs action when clicked (the spawn list)
--    ui:Note(text)             a line of text
--    ui.options.advanced, ui.options.fullnames   the two switches at the top
--------------------------------------------------------------------------------------------------
local MenuTabs = {}
local ReloadAndReopen         -- filled in after the tabs
local ApplyLook, ResetLook    -- the same

--------------------------------------------------------------------------------------------------
-- The menu's look. The defaults are Kit.DefaultStyle in Scripts\gui.lua; V.Menu (top of this
-- file) changes them for this install; what you set in the menu (Settings > Menu look) is saved
-- in settings.lua (see "Your settings from the menu" near the top) and wins over both, so anyone
-- can make the menu their own and keep it. Settings > Reset everything goes back to the defaults.
-- (Where you drag the window is not saved: it stays in memory until the game closes.)
--------------------------------------------------------------------------------------------------
local LOOK_DEFAULT = {}       -- a value meaning "back to the default" for ApplyLook
local MenuSettings = Saved.look

-- What the menu is built with: V.Menu, then your saved settings (gui.lua fills in the rest).
local function MenuStyle()
    local style = {}
    for k, v in pairs(V.Menu or {}) do style[k] = v end
    for k, v in pairs(MenuSettings) do style[k] = v end
    return style
end

local function CurrentLook(key)
    local v = MenuSettings[key]
    if v == nil then v = (V.Menu or {})[key] end
    if v == nil then v = Gui.DefaultStyle[key] end
    return v
end

-- Colours: the engine takes linear colours; you see and type them as #rrggbb (screen colours).
local function ToScreen(c) if c <= 0.0031308 then return 12.92 * c end return 1.055 * c ^ (1 / 2.4) - 0.055 end
local function ToLinear(c) if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end

local function HexOf(color)
    local function byte(c) return math.floor(math.max(0, math.min(1, ToScreen(c))) * 255 + 0.5) end
    return string.format("#%02x%02x%02x", byte(color[1]), byte(color[2]), byte(color[3]))
end

-- "#5fa59c" (or 5fa59c) -> a linear colour with alpha's opacity, or nil.
local function ColorOf(text, alpha)
    local h = (text or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
    if not h then return nil end
    local n = tonumber(h, 16)
    local function c(shift) return tonumber(string.format("%.4f", ToLinear(((n >> shift) & 255) / 255))) end
    return { c(16), c(8), c(0), alpha or 1 }
end

local LOOK_COLORS = {
    { "accent", "Accent (title, lines, values)" }, { "window", "Window" }, { "bar", "Title bar, tabs, status line" },
    { "on", "Tab you are on, a switch that is on" }, { "header", "Group titles" }, { "row", "Lines" },
    { "rowAlt", "Every other line" }, { "item", "Spawn names" }, { "chip", "Buttons (filled style)" },
    { "chipHover", "A button under the mouse" }, { "input", "Search and amount boxes" }, { "text", "Text" },
    { "dim", "Quiet text" }, { "confirm", "A button asking \"Sure?\"" },
}
-- key, label, smallest, largest, step
local LOOK_TEXT = {
    { "textSize", "Text size", 9, 28, 1 }, { "smallSize", "Small text size", 8, 24, 1 },
    { "tabSize", "Tab text size", 10, 30, 1 }, { "titleSize", "Title size", 14, 50, 2 },
    { "codeSize", "Code editor text size", 9, 24, 1 },
}
local LOOK_LAYOUT = {
    { "width", "Window width (normal size)", 760, 2400, 20 }, { "height", "Window height (normal size)", 460, 1400, 20 },
    { "sidebar", "Tab list width", 120, 360, 10 }, { "labelWidth", "Width of a line's name", 140, 400, 10 },
    { "backdrop", "Darken the game behind (%)", 0, 90, 5 },
}
-- accent colours on the same dark tones
local LOOK_ACCENTS = { { "Slate teal", "#5fa59c" }, { "Steel blue", "#6f9bc7" }, { "Dusty violet", "#9a8fc4" },
                       { "Sage", "#8aab80" }, { "Graphite", "#aab3bd" }, { "Amber", "#ffb329" } }
local LOOK_FONTS = { { "Game font", "/Game/UI/Font/kenyan_coffee_rgUI_Font.kenyan_coffee_rgUI_Font" },
                     { "Roboto", "/Engine/EngineFonts/Roboto.Roboto" } }

-- A number setting's value as it shows (the backdrop is a percentage of darkness).
local function LookNumber(key)
    local v = CurrentLook(key)
    if key == "backdrop" then return math.floor((v[4] or 0) * 100 + 0.5) end
    return v
end

-- The settings typed in the boxes that differ from what is saved: { key = value }, problems.
local function PendingLook(inputs)
    local changes, problems = {}, {}
    for _, c in ipairs(LOOK_COLORS) do
        local key, typed = c[1], inputs["look " .. c[1]]
        local now = CurrentLook(key)
        if typed and typed:lower():gsub("%s", "") ~= HexOf(now) then
            local color = ColorOf(typed, now[4])
            if color then changes[key] = color else problems[#problems + 1] = c[2] .. ": '" .. typed .. "' is not a colour like #5fa59c" end
        end
    end
    for _, list in ipairs({ LOOK_TEXT, LOOK_LAYOUT }) do
        for _, n in ipairs(list) do
            local key, typed = n[1], inputs["look " .. n[1]]
            if typed and typed ~= tostring(LookNumber(key)) then
                local v = tonumber(typed)
                if v then
                    v = math.max(n[3], math.min(n[4], math.floor(v + 0.5)))
                    if key == "backdrop" then changes[key] = { 0, 0, 0, v / 100 } else changes[key] = v end
                else
                    problems[#problems + 1] = n[2] .. ": '" .. typed .. "' is not a number"
                end
            end
        end
    end
    local title = inputs["look title"]
    if title and title ~= CurrentLook("title") then changes.title = title end
    return changes, problems
end

-- Command values in the menu: key in the table at the top, label, smallest, largest, step.
local COMMAND_NUMBERS = {
    { "NoclipSpeed", "Noclip speed (0 = your walking speed)", 0, 20000, 100 },
    { "NoclipFastSpeed", "Noclip speed holding Shift (0 = twice the speed)", 0, 40000, 100 },
    { "SummonDelayMs", "Time between spawned copies (milliseconds)", 20, 2000, 10 },
    { "SummonMax", "Most copies one spawn makes", 1, 1000, 10 },
    { "AmmoMax", "Most spare ammo setammo gives", 1, 9999999, 1000 },
    { "DoorAimRadius", "doors: how close to a door you must aim", 50, 600, 25 },
    { "GuardAimRadius", "guards: how close to a guard you must aim", 50, 600, 25 },
    { "ShareLevelAtStart", "Command sharing when the game starts (0 to 3)", 0, 3, 1 },
}
local COMMAND_SWITCHES = {
    { "ReviveMatchesBar", "A teammate's revive finishes with the bar (Healing Touch fix)" },
    { "CopyLookToGuests", "Guests see the look of copies (dupe, objects)" },
}

-- The command values typed in the boxes that differ from what is used now.
local function PendingCommands(inputs)
    local changes, problems = {}, {}
    for _, n in ipairs(COMMAND_NUMBERS) do
        local key, typed = n[1], inputs["cmd " .. n[1]]
        if typed and typed ~= tostring(V[key]) then
            local v = tonumber(typed)
            if v then changes[key] = math.max(n[3], math.min(n[4], math.floor(v + 0.5)))
            else problems[#problems + 1] = n[2] .. ": '" .. typed .. "' is not a number" end
        end
    end
    return changes, problems
end

-- Use and save command values at once (no need to make the window again).
local function ApplyCommands(menu, changes)
    for k, v in pairs(changes) do
        if v == LOOK_DEFAULT then
            Saved.commands[k], V[k] = nil, VDefault[k]
        else
            Saved.commands[k], V[k] = v, v
        end
        if menu then menu:ResetInput("cmd " .. k) end              -- the box shows the new value
    end
    return SaveSettings()
end

-- A line with a number box: - and + change the box, Default goes back (at once).
local function LookNumberRow(ui, menu, n)
    local key, label, low, high, step = n[1], n[2], n[3], n[4], n[5]
    local box = "look " .. key
    local function nudge(by)
        return function(inputs)
            local v = tonumber(inputs[box]) or LookNumber(key)
            inputs[box] = tostring(math.max(low, math.min(high, v + by)))
        end
    end
    ui:Row{ label = label, input = { key = box, default = tostring(LookNumber(key)), width = 80 },
            info = string.format("%d to %d", low, high),
            chips = { { "-", nudge(-step) }, { "+", nudge(step) },
                      { "Default", function() return ApplyLook(menu, { [key] = LOOK_DEFAULT }, label .. " is back to the default") end } } }
end


MenuTabs[#MenuTabs + 1] = { name = "Player", build = function(ui, menu)
    local pc = menu.pc
    local pawn = pc and Valid(pc.Pawn) and pc.Pawn or nil
    local flying = pawn and Try(NoclipOn, pawn) or false
    ui:Header("Moving")
    ui:Row{ label = "Noclip", hint = OnOff(flying), info = "WASD, Space up, Ctrl down, Shift faster",
            chips = { { flying and "Land" or "Take off", "noclip" } } }
    ui:Row{ label = "Ghost, fly, walk", info = "the game's own: through walls / no gravity / back to normal",
            chips = { { "Ghost", Cheat("ghost", menu) }, { "Fly", Cheat("fly", menu) }, { "Walk", Cheat("walk", menu) } } }
    ui:Row{ label = "Teleport", info = "to where you are looking", chips = { { "Teleport", Cheat("teleport", menu) } } }
    ui:Header("Health")
    ui:Row{ label = "Revive", info = "back up with full health", chips = { { "Revive", "revive" } } }
    ui:Row{ label = "God mode", info = "the game's own; again to turn it off", chips = { { "On / off", Cheat("god", menu) } } }
    ui:Header("Guns")
    ui:Row{ label = "Spare ammo", input = { key = "ammo", default = "999", width = 90 },
            info = "every gun you carry, and a full magazine", chips = { { "Set", "setammo {}" } } }
    ui:Row{ label = "Infinite ammo", hint = OnOff(State.infiniteAmmo),
            chips = { { State.infiniteAmmo and "Turn off" or "Turn on", "infiniteammo" } } }
    ui:Header("What you look at")
    ui:Row{ label = "Copy it", info = "with its look and values", input = { key = "dupe", default = "1", width = 60 },
            chips = { { "Copy", "dupe {}" } } }
    ui:Row{ label = "Delete it", chips = { { "Delete", Cheat("destroytarget", menu) } } }
end }

-- What a spawn name is found by: every word typed must be somewhere in its name, class name,
-- the name you would type, its path or its group.
local function SpawnMatches(s, groupName, words)
    local hay = s.find .. " " .. groupName:lower()
    for _, w in ipairs(words) do
        if not hay:find(w, 1, true) then return false end
    end
    return true
end

local function SpawnItem(ui, s)
    local right = ui.options.fullnames and s.label or s.full       -- the other name, on the right
    if ui.options.advanced then right = right .. "    summon " .. s.typed end
    ui:Item{ label = ui.options.fullnames and s.full or s.label, sub = right,
             find = s.find, action = "summon " .. s.typed .. " {count}" }
end

MenuTabs[#MenuTabs + 1] = { name = "Spawn", still = true, build = function(ui)
    -- search everything (all groups, also the advanced ones) for the words typed here
    local words = {}
    for w in (ui.inputs.spawnsearch or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    local found, total = {}, 0
    if #words > 0 then
        for i, g in ipairs(SPAWN_GROUPS) do
            local list = {}
            for _, s in ipairs(SpawnList[i]) do
                if SpawnMatches(s, g.name, words) then list[#list + 1] = s end
            end
            found[i], total = list, total + #list
        end
    end
    ui:Row{ label = "Search all items", input = { key = "spawnsearch", default = "", width = 360, live = true },
            hint = #words > 0 and (total .. " found") or nil,
            info = #words == 0 and "any words, anywhere in a name, class or path" or nil,
            chips = { { "Clear", function(inputs) inputs.spawnsearch = "" end } } }
    ui:Row{ label = "How many", input = { key = "count", default = "1", width = 70 },
            chips = { { "1", function(inputs) inputs.count = "1" end }, { "5", function(inputs) inputs.count = "5" end },
                      { "10", function(inputs) inputs.count = "10" end }, { "25", function(inputs) inputs.count = "25" end } } }
    ui:Row{ label = "Spawning", chips = { { "Stop", "summonstop" } }, info = "click a name below to spawn it in front of you" }
    if #words > 0 then
        -- the matches of every group, open
        for i, g in ipairs(SPAWN_GROUPS) do
            if #found[i] > 0 then
                ui:Header(string.format("%s  (%d found)", g.name, #found[i]))
                for _, s in ipairs(found[i]) do SpawnItem(ui, s) end
            end
        end
        if total == 0 then ui:Note("Nothing has all of those words. Try fewer or shorter words.") end
        return
    end
    for i, g in ipairs(SPAWN_GROUPS) do
        if ui.options.advanced or not g.advanced then
            local list = SpawnList[i]
            ui:Header(string.format("%s  (%d)", g.name, #list), "spawn " .. g.name)
            for _, s in ipairs(list) do SpawnItem(ui, s) end
        end
    end
end }

MenuTabs[#MenuTabs + 1] = { name = "Heist", build = function(ui)
    local alarm = AllOf("AlarmBP_C")[1]
    local cams, working = AllOf("CameraBP_C"), 0
    for _, c in ipairs(cams) do if not c["Destroyed?"] then working = working + 1 end end
    local truck = FindFirstOf("RobberTruck_C")
    ui:Header("Alarm and cameras")
    ui:Row{ label = "Alarm", hint = alarm and (alarm["AlarmEnabled?"] and "ON" or "OFF") or "not here",
            chips = { { "Turn off", "alarm off" }, { "Turn on", "alarm on" },
                      { "Set it off", "alarm trigger", confirm = "Go loud?" } } }
    ui:Row{ label = "Security cameras", hint = #cams > 0 and string.format("%d working", working) or "not here",
            info = "remove: guards do not notice / break: as shooting them",
            chips = { { "Remove", "cameras off" }, { "Break", "cameras destroy" } } }
    ui:Row{ label = "Keypad codes", chips = { { "Show", "codes" }, { "Unlock all", "codes open" } } }
    ui:Header("Police")
    ui:Row{ label = "Police", hint = string.format("%d here", #AllOf("NPC_Police_base_C")),
            chips = { { "New wave", "cops wave" }, { "Special wave", "cops specials" }, { "Remove all", "cops clear" } } }
    ui:Header("Guards")
    local guards, alive = AllOf("NPC_Guard_C"), 0
    for _, g in ipairs(guards) do if not g["Dead?"] then alive = alive + 1 end end
    local ringing, soonest = RingingPhones(AllOf("GuardPhone_C"))
    ui:Row{ label = "The guard you look at", info = "kill: as if shot / remove: no body, no phone",
            chips = { { "Kill", "guards kill" }, { "Remove", "guards remove" } } }
    ui:Row{ label = "Every guard", hint = #guards > 0 and string.format("%d alive", alive) or "not here",
            info = "remove all also takes the bodies",
            chips = { { "Kill all", "guards kill all", confirm = "Their phones ring. Sure?" },
                      { "Remove all", "guards remove all" } } }
    ui:Row{ label = "Guard phones", hint = #ringing > 0 and string.format("%d ringing (%d s)", #ringing, math.max(soonest, 0))
                or "none ringing",
            info = "answer: as at a scanner, no alarm",
            chips = { { "Answer all", "guards phones answer" }, { "Remove all", "guards phones remove" } } }
    ui:Header("Team")
    ui:Row{ label = "Everyone", chips = { { "Revive all", "reviveall" }, { "Heal all", "healall" } } }
    local god = Try(GodAllOn) or false
    ui:Row{ label = "Nobody takes damage", hint = OnOff(god),
            chips = { { god and "Turn off" or "Turn on", god and "godall off" or "godall on" } } }
    ui:Row{ label = "XP for everyone", input = { key = "xpall", default = "50000", width = 100 },
            info = "paid on the win screen", chips = { { "Give", "setxp all {}" } } }
    ui:Header("Loot and escape")
    ui:Row{ label = "Truck money", hint = Valid(truck) and Fmt(truck.TotalTake) or "not here",
            input = { key = "truck", default = "1000000", width = 110 },
            chips = { { "Set", "truckmoney set {}" }, { "Add", "truckmoney add {}" }, { "Reset", "truckmoney reset" } } }
    ui:Row{ label = "Loose loot", chips = { { "Bring to the truck", "bringloot" } } }
    ui:Row{ label = "Escape now", info = "win with what is in the truck",
            chips = { { "Escape", "escape", confirm = "End the heist?" } } }
end }

MenuTabs[#MenuTabs + 1] = { name = "Doors", build = function(ui)
    local doors, vaults = AllOf("DoorBP_C"), AllOf("VaultDoor_C")
    ui:Header("The door you are looking at")
    ui:Row{ label = "This door", info = "unlock leaves it shut",
            chips = { { "Unlock", "doors unlock" }, { "Open", "doors open" }, { "Close", "doors close" } } }
    ui:Header("Every door")
    ui:Row{ label = "All doors", hint = #doors > 0 and DoorSummary(doors):gsub("^Doors: ", "") or "not here",
            chips = { { "Unlock all", "doors unlock all" }, { "Open all", "doors open all" }, { "Close all", "doors close all" } } }
    ui:Header("Vault")
    ui:Row{ label = "Vault", hint = VaultSummary(vaults),
            chips = { { "Open vault", "doors vault open", confirm = "Can't close it again. Sure?" } } }
    ui:Note("A vault cannot be closed again once it is open: the game has no way to close it.")
end }

MenuTabs[#MenuTabs + 1] = { name = "Progress", build = function(ui, menu)
    local pc = menu.pc
    local function num(field) return pc and Try(function() return Fmt(pc[field]) end) or "?" end
    ui:Header("Cash")
    ui:Row{ label = "Cash", hint = num("Cash"), input = { key = "cash", default = "5000000", width = 120 },
            chips = { { "Set", "setmoney {}" }, { "Add", "addmoney {}" } } }
    ui:Header("Level")
    ui:Row{ label = "Level", hint = num("Level"), input = { key = "level", default = "50", width = 80 },
            chips = { { "Set", "setlevel {}" } } }
    ui:Row{ label = "XP in this level", hint = num("EXP"), input = { key = "xp", default = "0", width = 80 },
            chips = { { "Set", "setxp {}" } } }
    ui:Header("Unlocks")
    ui:Row{ label = "Skills", info = "every skill at its top tier", chips = { { "Max all", "maxskills" } } }
    ui:Row{ label = "Gear", info = "every weapon, mod, tool and armor bought with cash", chips = { { "Unlock all", "unlockall" } } }
    ui:Note("These change your own save. Coins and anything bought with coins are never touched.")
end }

MenuTabs[#MenuTabs + 1] = { name = "World", build = function(ui, menu)
    ui:Header("Time and size")
    ui:Row{ label = "Speed of the game", chips = { { "Slow", Cheat("slomo 0.3", menu) }, { "Half", Cheat("slomo 0.5", menu) },
            { "Normal", Cheat("slomo 1", menu) }, { "Double", Cheat("slomo 2", menu) } } }
    ui:Row{ label = "Your size", chips = { { "Small", Cheat("changesize 0.5", menu) }, { "Normal", Cheat("changesize 1", menu) },
            { "Big", Cheat("changesize 2", menu) }, { "Giant", Cheat("changesize 3", menu) } } }
    ui:Row{ label = "Freeze AI and physics", info = "again to unfreeze", chips = { { "On / off", Cheat("playersonly", menu) } } }
    ui:Header("Screen")
    ui:Row{ label = "Free camera", info = "closes the menu; again to go back", chips = { { "On / off", function()
        menu:Close()                                  -- the free camera takes over the local player
        return MenuRun("toggledebugcamera")
    end } } }
    ui:Row{ label = "FPS counter", chips = { { "On / off", "stat fps" } } }
end }

MenuTabs[#MenuTabs + 1] = { name = "Lobby", build = function(ui)
    local lm = Lobby()
    local current = lm and SelectedHeist(lm)
    ui:Header("Heists")
    ui:Row{ label = "Selected heist", hint = current and current.name or (lm and "none" or "not in the lobby"),
            chips = { { "Start now", "forcemap", confirm = "Start for everyone?" } } }
    for _, h in ipairs(Maps.Heists) do
        local notes = {}
        if h.coin > 0 then notes[#notes + 1] = "coins" end
        if h.level > 0 then notes[#notes + 1] = "level " .. h.level end
        ui:Row{ label = ui.options.fullnames and h.key or h.name, hint = table.concat(notes, ", "),
                chips = { { "Select", "selectmap " .. h.key }, { "Start now", "forcemap " .. h.key, confirm = "Start for everyone?" } } }
    end
    if ui.options.advanced then
        ui:Header("Other map files", "maps other")
        for _, f in ipairs(Maps.Other) do
            ui:Item{ label = f, sub = "forcemap " .. f:lower(), action = "forcemap " .. f:lower() }
        end
    end
    ui:Note("Host only. Heists sold for coins are only started when you own them.")
end }

MenuTabs[#MenuTabs + 1] = { name = "Settings", still = true, build = function(ui, menu)
    ui:Header("Your settings")
    ui:Row{ label = "Your settings", info = "change anything below, then Save and apply; they stay after a restart",
            chips = { { "Save and apply", function(inputs)
                          local look, problems = PendingLook(inputs)
                          local cmds, more = PendingCommands(inputs)
                          for _, p in ipairs(more) do problems[#problems + 1] = p end
                          if #problems > 0 then return problems end
                          if next(look) == nil and next(cmds) == nil then return { "Nothing changed (type in the boxes first)" } end
                          if next(cmds) ~= nil and not ApplyCommands(menu, cmds) then return { "Could not write settings.lua" } end
                          if next(look) ~= nil then return ApplyLook(menu, look, "Saved your settings") end
                          return { "Saved your settings" }
                      end },
                      { "Reset everything", function() return ResetLook(menu) end, confirm = "Back to the defaults?" } } }
    ui:Header("Commands", "settings commands")
    for _, n in ipairs(COMMAND_NUMBERS) do
        local key, label, low, high, step = n[1], n[2], n[3], n[4], n[5]
        local box = "cmd " .. key
        local function nudge(by)
            return function(inputs)
                local v = tonumber(inputs[box]) or V[key]
                inputs[box] = tostring(math.max(low, math.min(high, v + by)))
            end
        end
        ui:Row{ label = label, input = { key = box, default = tostring(V[key]), width = 100 },
                hint = V[key] ~= VDefault[key] and "changed" or nil,
                chips = { { "-", nudge(-step) }, { "+", nudge(step) },
                          { "Default", function()
                              if not ApplyCommands(menu, { [key] = LOOK_DEFAULT }) then return { "Could not write settings.lua" } end
                              return { label .. " is back to " .. tostring(V[key]) }
                          end } } }
    end
    for _, sw in ipairs(COMMAND_SWITCHES) do
        local key, label = sw[1], sw[2]
        local function set(on)
            return function()
                if not ApplyCommands(menu, { [key] = on }) then return { "Could not write settings.lua" } end
                return { label .. ": " .. (on and "on" or "off") }
            end
        end
        ui:Row{ label = label, hint = V[key] and "ON" or "OFF", chips = { { "On", set(true) }, { "Off", set(false) } } }
    end
    ui:Note("Noclip speeds apply at once, also while you fly. The command sharing level is the one every game starts with.")

    ui:Header("Menu look")
    local accent = CurrentLook("accent")
    for i = 1, #LOOK_ACCENTS, 3 do
        local chips = {}
        for j = i, math.min(i + 2, #LOOK_ACCENTS) do
            local name, hex = LOOK_ACCENTS[j][1], LOOK_ACCENTS[j][2]
            chips[#chips + 1] = { name, function()
                return ApplyLook(menu, { accent = ColorOf(hex, 1), on = LOOK_DEFAULT }, "Accent: " .. name)
            end }
        end
        ui:Row{ label = i == 1 and "Accent colour" or "", swatch = i == 1 and accent or nil, chips = chips,
                hint = i == 1 and HexOf(accent) or nil }
    end

    ui:Header("Colours", "look colours")
    for _, c in ipairs(LOOK_COLORS) do
        local key, label = c[1], c[2]
        local now = CurrentLook(key)
        ui:Row{ label = label, swatch = now, input = { key = "look " .. key, default = HexOf(now), width = 100 },
                chips = { { "Default", function() return ApplyLook(menu, { [key] = LOOK_DEFAULT }, label .. " is back to the default") end } } }
    end
    ui:Note("Colours are typed like #5fa59c (red, green, blue). Colours that go with one you change (lighter under the mouse) follow it.")

    ui:Header("Text", "look text")
    ui:Row{ label = "Title", input = { key = "look title", default = CurrentLook("title"), width = 220 },
            chips = { { "Default", function() return ApplyLook(menu, { title = LOOK_DEFAULT }, "The title is back to the default") end } } }
    local font = CurrentLook("titleFont")
    local fontChips = {}
    for _, f in ipairs(LOOK_FONTS) do
        fontChips[#fontChips + 1] = { f[1], function() return ApplyLook(menu, { titleFont = f[2] }, "Title font: " .. f[1]) end }
    end
    ui:Row{ label = "Title font", chips = fontChips, hint = font:find("Roboto", 1, true) and "Roboto" or "Game font" }
    for _, n in ipairs(LOOK_TEXT) do LookNumberRow(ui, menu, n) end

    ui:Header("Size and layout", "look layout")
    for _, n in ipairs(LOOK_LAYOUT) do LookNumberRow(ui, menu, n) end

    ui:Header("Style", "look style")
    local function choice(label, key, options)
        local chips, now = {}, CurrentLook(key)
        local shown = ""
        for _, o in ipairs(options) do
            if o[2] == now then shown = o[1] end
            chips[#chips + 1] = { o[1], function() return ApplyLook(menu, { [key] = o[2] }, label .. ": " .. o[1]) end }
        end
        ui:Row{ label = label, chips = chips, hint = shown }
    end
    choice("The tab you are on", "tabStyle", { { "Filled", "fill" }, { "Bar on the left", "bar" } })
    choice("Buttons", "chipStyle", { { "Outlined", "outline" }, { "Filled", "filled" } })
    choice("Animations", "animate", { { "On", true }, { "Off", false } })

    local level = State.share and State.share.level or 0
    ui:Header("Command sharing (host)")
    ui:Row{ label = "Guests may run", hint = level .. ": " .. tostring(V.ShareLevelNames[level]),
            chips = { { "0 off", "commandsharing 0" }, { "1", "commandsharing 1" }, { "2", "commandsharing 2" },
                      { "3", "commandsharing 3" } } }
    ui:Note("1: player commands. 2: also world and heist commands. 3: everything except the block list.")
    ui:Header("This window")
    ui:Row{ label = "Place and size", info = "drag the title bar to move it, the corner to resize it; kept until the game closes",
            chips = { { "Back to normal", function() menu:ResetPlace() return { "The window is back in the middle at its normal size" } end } } }
    ui:Header("config.lua")
    ui:Row{ label = "After editing config.lua", info = "the menu opens again by itself",
            chips = { { "Reload it", function() return ReloadAndReopen("Settings") end } } }
    ui:Note("Turn on Advanced at the top for the Code tab: every command's code, editable here.")
end }

-- reloadconfig from the menu: the new config throws the open menu away, so it is opened again
-- right after, on the same tab, with the result at the bottom. Filled in below (OpenMenu).
local OpenMenu

ReloadAndReopen = function(tabName, extra)
    local said = MenuRun("reloadconfig")
    local open = Core.Exports.OpenMenu or OpenMenu          -- the newly loaded config's, when it loaded
    local opts = { tab = tabName, status = said }
    for k, v in pairs(extra or {}) do opts[k] = v end
    open(nil, opts)
    return nil
end

--------------------------------------------------------------------------------------------------
-- The Binds tab
--------------------------------------------------------------------------------------------------
local BIND_IDEAS = { "opengui", "noclip", "god", "ghost", "walk", "teleport", "destroytarget", "dupe", "revive",
                     "setammo 999", "infiniteammo", "summon goldbar 10", "doors unlock", "doors open", "alarm off",
                     "cameras off", "bringloot", "cops clear", "reviveall", "healall", "god | ghost" }

MenuTabs[#MenuTabs + 1] = { name = "Binds", still = true, build = function(ui)
    ui:Header("Add or change a bind")
    ui:Row{ label = "Key", input = { key = "bindkey", default = "", width = 110 },
            info = "f1 to f24, a letter, a digit, numpad5, space, enter, mouse4, mouse5, up, pageup..." }
    ui:Row{ label = "Command", input = { key = "bindcmd", default = "", width = 330 }, info = "several: god | ghost",
            chips = { { "Bind it", function(inputs)
                local key = (inputs.bindkey or ""):gsub("%s", "")
                local cmd = (inputs.bindcmd or ""):match("^%s*(.-)%s*$")
                if key == "" or cmd == "" then return { "Type a key and a command first" } end
                return MenuRun("bind " .. key .. " " .. cmd)
            end } } }
    ui:Header("Ideas: click one to put it in Command", "bind ideas")
    for _, idea in ipairs(BIND_IDEAS) do
        ui:Item{ label = idea, action = function(inputs) inputs.bindcmd = idea end }
    end
    ui:Header("Your binds")
    local keys = {}
    for k in pairs(Binds) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then ui:Note("No binds yet.") end
    for _, k in ipairs(keys) do
        local key, cmd = k, Binds[k]
        ui:Row{ label = key, info = cmd, chips = {
            { "Change", function(inputs) inputs.bindkey, inputs.bindcmd = key:lower(), cmd end },
            { "Remove", "unbind " .. key } } }
    end
    ui:Note("Binds are saved in binds.txt and come back every time you start the game. While this menu is open only your opengui key works.")
end }

--------------------------------------------------------------------------------------------------
-- The Code tab (only with Advanced on): this file, config.lua, in its sections (one per command
-- or group of commands, as marked by the comment blocks), each editable in the menu.
--    Check             looks for mistakes without saving
--    Save and reload   writes config.lua and loads it again. An edit that does not even load
--                      (a typo) is not saved; one that fails while it runs is taken back out
--                      again, and config.lua is as it was. Before the first save of a game
--                      session your file is copied to config.backup.lua.
--    Undo changes      back to what is in the file
--------------------------------------------------------------------------------------------------
local function ReadConfig()
    local f = io.open(Core.ConfigFile, "rb")
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return (text:gsub("\r\n", "\n"))
end

local function WriteFile(path, text)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

local function Separator(line)
    return line:match("^%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-") ~= nil or line:match("^%-%-====") ~= nil
end

-- The whole file as one part (the first one in the list).
local FULL_FILE = "Full file"

-- config.lua's sections: { key, title, first, last, commands } (line numbers; commands: the
-- console commands the section makes). The first is the full file. A section starts at a comment
-- block's opening line of dashes (the line before it is not a comment) and runs to the next one.
local function ConfigSections(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    if lines[#lines] == "" then lines[#lines] = nil end
    local starts = { 1 }
    for i, line in ipairs(lines) do
        if i > 1 and Separator(line) and not lines[i - 1]:match("^%-%-") then starts[#starts + 1] = i end
    end
    local sections, used = { { key = FULL_FILE, title = "Full file: all of config.lua", first = 1, last = #lines,
                               commands = {}, full = true } }, { [FULL_FILE] = true }
    for n, first in ipairs(starts) do
        local last = (starts[n + 1] or (#lines + 1)) - 1
        local title = "Top of the file"
        if n > 1 then
            for i = first + 1, math.min(first + 3, last) do
                local t = lines[i]:match("^%-%-%s+(.-)%s*$")
                if t and t ~= "" then title = t break end
            end
        end
        local key = title
        if used[key] then key = key .. " (" .. first .. ")" end
        used[key] = true
        local commands = {}
        for i = first, last do
            local name = lines[i]:match('Core%.Command%("([%w_]+)"') or lines[i]:match('^Edit%("([%w_]+)"')
            if name then commands[#commands + 1] = name end
        end
        sections[#sections + 1] = { key = key, title = title, first = first, last = last, commands = commands }
    end
    return sections, lines
end

-- The line of every place in text that has what (any case), in order (at most 2000).
local function FindLines(text, what)
    local out = {}
    if what == "" then return out end
    local hay, needle = text:lower(), what:lower()
    local at, line, counted = 1, 1, 1
    while #out < 2000 do
        local s, e = hay:find(needle, at, true)
        if not s then break end
        local _, breaks = hay:sub(counted, s - 1):gsub("\n", "")
        line, counted = line + breaks, s
        out[#out + 1] = line
        at = e + 1
    end
    return out
end

local function SectionText(lines, sec)
    return table.concat(lines, "\n", sec.first, sec.last) .. "\n"
end

local function FindSection(sections, key)
    for _, sec in ipairs(sections) do
        if sec.key == key then return sec end
    end
    return nil
end

-- config.lua with one section replaced by text, or nil and why.
local function WithSection(key, text)
    local file = ReadConfig()
    if not file then return nil, "config.lua could not be read" end
    local sections, lines = ConfigSections(file)
    local sec = FindSection(sections, key)
    if not sec then return nil, "that part is not in config.lua any more (press Back)" end
    text = text:gsub("\r\n", "\n")
    if text:sub(-1) ~= "\n" then text = text .. "\n" end
    local before = sec.first > 1 and (table.concat(lines, "\n", 1, sec.first - 1) .. "\n") or ""
    local after = sec.last < #lines and (table.concat(lines, "\n", sec.last + 1, #lines) .. "\n") or ""
    return before .. text .. after, nil, file, sec
end

-- A Lua error's line in the whole file -> the line in this section.
local function SectionError(err, sec)
    local n = tonumber(tostring(err):match(":(%d+):"))
    local msg = tostring(err):gsub("^.-:%d+: ", "")
    if n then return string.format("line %d of this part (line %d of config.lua): %s", n - sec.first + 1, n, msg) end
    return msg
end

local function CheckSection(key, text)
    local whole, why, _, sec = WithSection(key, text)
    if not whole then return { "Not checked: " .. why } end
    local _, err = load(whole, "=config.lua")
    if err then return { "Mistake: " .. SectionError(err, sec) } end
    return { "No mistakes found (Save and reload to try it in the game)" }
end

local function SaveSection(menu, key, text)
    local whole, why, old, sec = WithSection(key, text)
    if not whole then return { "Not saved: " .. why } end
    local _, err = load(whole, "=config.lua")
    if err then return { "Not saved, there is a mistake: " .. SectionError(err, sec) } end
    if not State.configBackedUp then
        if not WriteFile(Core.ModDir .. "/config.backup.lua", old) then return { "Not saved: could not write config.backup.lua" } end
        State.configBackedUp = true
    end
    if not WriteFile(Core.ConfigFile, whole) then return { "Not saved: config.lua could not be written" } end
    menu.codeBuffers[key] = nil                       -- saved: the box shows the file again
    local said = MenuRun("reloadconfig")
    local failed = false
    for _, line in ipairs(said) do
        if line:find("was NOT loaded", 1, true) then failed = true end
    end
    if failed then
        local reason = said[#said] or "?"
        WriteFile(Core.ConfigFile, old)                -- take the edit back out
        MenuRun("reloadconfig")
        said = { "Not saved: config.lua failed when it ran, so it is back as it was. " .. SectionError(reason, sec) }
        State.codeKeep = { key = key, text = text }   -- keep the edit in the box to fix it
    else
        table.insert(said, 1, "Saved " .. sec.title)
    end
    local open = Core.Exports.OpenMenu or OpenMenu
    open(nil, { tab = "Code", code = key, status = said })
    return nil
end

MenuTabs[#MenuTabs + 1] = { name = "Code", advanced = true, still = true, build = function(ui, menu)
    local file = ReadConfig()
    if not file then ui:Note("config.lua could not be read.") return end
    local sections, lines = ConfigSections(file)
    local open = menu.codeOpen and FindSection(sections, menu.codeOpen)
    if not open then
        menu.codeOpen = nil
        ui:Header("config.lua: click a part to edit it (A to Z, the full file first)")
        local list = {}
        for _, sec in ipairs(sections) do
            local label = sec.title
            -- the commands a part makes, when its title does not already say them
            local unnamed = {}
            for _, name in ipairs(sec.commands) do
                if not label:lower():find(name, 1, true) then unnamed[#unnamed + 1] = name end
            end
            if #unnamed > 0 then label = label .. "  (" .. table.concat(unnamed, ", ") .. ")" end
            list[#list + 1] = { sec = sec, label = label }
        end
        table.sort(list, function(a, b)
            if a.sec.full ~= b.sec.full then return a.sec.full == true end
            return a.label:lower() < b.label:lower()
        end)
        for _, entry in ipairs(list) do
            local sec = entry.sec
            ui:Item{ label = entry.label, sub = string.format("line %d, %d lines", sec.first, sec.last - sec.first + 1),
                     find = table.concat(sec.commands, " "),
                     action = function()
                         menu.codeOpen = sec.key
                         menu:ResetInput("code find")             -- a new part starts with an empty Find
                         menu:ScrollTop()
                     end }
        end
        ui:Note("Nothing is left out: Full file is all of config.lua, and each part is the lines between two of " ..
            "its title comments. A command can also use values at the top of the file (1. VALUES) and helpers in " ..
            "\"Things several commands use\".")
        ui:Note("Your edits are saved to config.lua (the file in Mods\\OARCommands) and loaded at once.")
        return
    end
    local key = open.key
    local original = SectionText(lines, open)
    local edited = menu.codeBuffers[key]
    ui:Header("Editing: " .. open.title .. string.format("   (config.lua line %d)", open.first))
    ui:Row{ label = "This part", hint = (edited and edited ~= original) and "not saved" or nil, chips = {
        { "Save and reload", function() return SaveSection(menu, key, menu:EditorText(key) or original) end },
        { "Check", function() return CheckSection(key, menu:EditorText(key) or original) end },
        { "Undo changes", function() menu:ForgetEdits(key, original) return { "Back to what is in config.lua" } end },
        { "Back", function() menu:KeepInputs() menu.codeOpen = nil menu:ScrollTop() end } } }

    -- Find: every place in the box (with your edits) that has the text; the current one is marked
    -- and scrolled to. Typing starts again at the first; Next and Previous go round.
    local query = ui.inputs["code find"] or ""
    local found = FindLines(menu:EditorText(key) or original, query)
    local f = menu.codeFind
    if not f or f.key ~= key or f.query ~= query then
        f = { key = key, query = query, index = 1, seq = (f and f.seq or 0) + 1 }
        menu.codeFind = f
    end
    if f.index > #found then f.index = 1 end
    local function step(by)
        return function()
            if #found == 0 then return { query == "" and "Type what to find first" or "Not in this part" } end
            f.index = (f.index - 1 + by) % #found + 1
            f.seq = f.seq + 1
        end
    end
    local findHint
    if #found > 0 then
        findHint = string.format("%d of %d%s, line %d", f.index, #found, #found >= 2000 and "+" or "", found[f.index])
    elseif query ~= "" then
        findHint = "not found"
    end
    ui:Row{ label = "Find", input = { key = "code find", default = "", width = 300, live = true }, hint = findHint,
            chips = { { "Previous", step(-1) }, { "Next", step(1) } } }
    ui:Editor{ key = key, text = original, mark = found[f.index], markSeq = f.seq }
    ui:Note("Before the first save in a game session your file is copied to config.backup.lua. An edit that does not load is not saved.")
    ui:Note("Values saved in Settings (settings.lua) win over the same values in this file.")
end }

-- Settings after Binds, Code (Advanced only) last
for i, tab in ipairs(MenuTabs) do
    if tab.name == "Settings" then
        local settings = table.remove(MenuTabs, i)
        table.insert(MenuTabs, #MenuTabs, settings)    -- before the last one (Code)
        break
    end
end

local MENU_OPTIONS = {
    { key = "advanced", label = "Advanced" },
    { key = "fullnames", label = "Full names" },
}

-- A menu built by the config from before a reloadconfig is closed and thrown away; the next
-- opengui builds it from this one.
-- Drop a menu that is not to be used any more: in the same map it is closed and taken off the
-- screen; from another map it is only forgotten (the engine freed it).
-- (A menu made by an older gui.lua, before a reloadconfig, may not know SameWorld: it is only
-- forgotten, and the next opengui takes its window off the screen with the other strays.)
local function DropMenu(m, pc)
    pcall(function()
        if pc and m.SameWorld and m:SameWorld(pc) then m:Destroy() elseif m.Abandon then m:Abandon(pc) end
    end)
end

if State.menu then
    DropMenu(State.menu, LocalPlayerController())
    State.menu = nil
end

-- Only one menu window: any other one still on the screen (lost track of after a reloadconfig, the
-- free camera, or anything else) is taken off it. The search only finds live windows, and only
-- runs when the menu opens.
local function RemoveStrayWindows(keep)
    local keepAddress = keep and keep.root and keep.root:GetAddress() or nil
    local removed = 0
    for _, w in pairs(FindAllOf(Gui.WindowClass) or {}) do
        if w:IsValid() and w:GetAddress() ~= keepAddress then
            pcall(function()
                if w:IsInViewport() then
                    w:RemoveFromParent()
                    removed = removed + 1
                end
            end)
        end
    end
    if removed > 0 then Print("removed " .. removed .. " old menu window(s) from the screen") end
end

-- Keys the menu needs while it is open: the left mouse button (its clicks) and Escape. They are
-- watched from the start (registering keys later, while UE4SS reads them, is not safe); with the
-- menu closed they do nothing of the menu's (see Watch).
Watch("LEFT_MOUSE_BUTTON")
Watch("ESCAPE")

-- The game's per-frame event of your controller drives the menu (clicks, search box, numbers),
-- and the game clearing the screen (loading, death, win screen) closes it first. Placed the first
-- time the menu opens, not at startup (see truckmoney's hooks).
local function HookMenu()
    local tick = Core.Hook(Gui.TickEvent, function(Context)
        local m = State.menu
        if m then m:Tick(Context:get()) end
    end)
    State.menuRemovalHooked = Core.Hook(Gui.RemoveAllEvent, function()
        local m = State.menu
        if m then m:Removed() end
    end) or nil
    State.menuHooked = tick or nil
    return tick
end
if State.menuHooked then HookMenu() end      -- after reloadconfig: point the hook at this code

-- Open the menu (opts: tab = a tab's name, code = a Code tab part, status = lines to show), or
-- close it when it is open and nothing else is asked for.
OpenMenu = function(Ar, opts)
    opts = opts or {}
    local say = function(text) if Ar then Say(Ar, text) else Print(text) end end
    local pc = LocalPlayerController()
    local m = State.menu
    -- Open and asked to toggle: close it, also when the local player now drives another controller
    -- in the same map (the free camera); a menu of the other controller is then dropped.
    if m and m.open and not opts.tab and pc and m.SameWorld and m:SameWorld(pc) then
        m:Close()
        if not m:BelongsTo(pc) then DropMenu(m, pc); State.menu = nil end
        return
    end
    if m and not (pc and m:BelongsTo(pc)) then
        -- Built for another controller (taken off the screen), in another map, or the game cleared
        -- the screen (forgotten without being touched: the engine frees those).
        DropMenu(m, pc)
        m, State.menu = nil, nil
    end
    if m and m.open and not opts.tab then m:Close() return end
    if not pc then say("No local player yet") return end
    if not HookMenu() then say("The menu cannot open yet: your controller's per-frame event is not loaded") return end
    if not m then
        -- where you moved the window and its size: kept in memory (State), so a new map or a
        -- reloadconfig keeps it, and a game restart puts it back to normal
        State.menuPlace = State.menuPlace or { x = 0, y = 0 }
        local ok, made = pcall(Gui.New, { pc = pc, tabs = MenuTabs, options = MENU_OPTIONS, place = State.menuPlace,
                                          run = MenuRun, style = MenuStyle(), keep = opts.keep,
                                          tickPc = Robber() })
        if not ok then say("The menu could not be built: " .. tostring(made)) return end
        m, State.menu = made, made
    end
    m.removalWatched = State.menuRemovalHooked
    RemoveStrayWindows(m)
    if opts.code then m.codeOpen = opts.code end
    if State.codeKeep and State.codeKeep.key == opts.code then
        m.codeBuffers[opts.code] = State.codeKeep.text  -- a failed save: the edit stays in the box
    end
    State.codeKeep = nil
    if not m.open then
        local ok, opened = pcall(m.Open, m)
        if not (ok and opened) then say("The menu could not open: " .. tostring(ok and "no window" or opened)) return end
    end
    if opts.tab then m:SelectTabByName(opts.tab) end
    if opts.status then m:Status(opts.status) end
    m:Render()
end
Core.Exports.OpenMenu = OpenMenu

-- Save look changes and make the window again with them (a look is set when the window is made),
-- on the Settings tab, with the same groups open and switches on.
ApplyLook = function(menu, changes, message, everything)
    for k, v in pairs(changes) do
        if v == LOOK_DEFAULT then MenuSettings[k] = nil else MenuSettings[k] = v end
    end
    if not SaveSettings() then return { "Could not write settings.lua" } end
    if State.menu then pcall(function() State.menu:Destroy() end) end
    State.menu = nil
    -- What was typed carries over (taken after closing, which keeps it), except the boxes of what
    -- was just saved, which show the new values.
    local keep = nil
    if menu then
        keep = { options = menu.options, expanded = menu.expanded, inputs = {} }
        for k, v in pairs(menu.inputs) do
            local setting = k:sub(1, 5) == "look " or k:sub(1, 4) == "cmd "
            if not (everything and setting) then keep.inputs[k] = v end
        end
        for k in pairs(changes) do keep.inputs["look " .. k], keep.inputs["cmd " .. k] = nil, nil end
    end
    OpenMenu(nil, { tab = "Settings", status = { message }, keep = keep })
    return nil
end

ResetLook = function(menu)
    for k in pairs(MenuSettings) do MenuSettings[k] = nil end
    for k in pairs(Saved.commands) do
        Saved.commands[k] = nil
        V[k] = VDefault[k]
    end
    return ApplyLook(menu, {}, "Everything is back to the defaults", true)
end

Core.Command("opengui", function(FullCommand, Parameters, Ar)
    OpenMenu(Ar)
    return true
end)

end)()

--------------------------------------------------------------------------------------------------
-- Last: read binds.txt, and show a few things to other scripts (OARCommands.Exports)
--------------------------------------------------------------------------------------------------
for _, k in ipairs(START_KEYS) do
    if Key[k] ~= nil then Watch(k, true) end
end
LoadBinds()

Core.Exports.Values = V
Core.Exports.Share = Share
Core.Exports.Lobby = { Resolve = ResolveMap }
