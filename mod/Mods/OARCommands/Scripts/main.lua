--[[
    OARCommands for One-armed robber (UE4SS 3.0.1 Lua mod)

    The engine's own SetBind is compiled out of this shipping build, so this mod adds working
    console commands:
        bind                      list your binds
        bind <key>                show what one key does
        bind <key> <command>      bind a key, e.g.  bind x destroytarget
                                  several commands: bind f1 "god | fly"
        unbind <key>              remove one bind
        unbindall                 remove every bind
        summon <thing> [count]    spawn count copies 0.15 s apart, e.g.  summon goldbar 10
                                  (also: spawn). Loads the thing first, so it works on any map.
                                  Names: goldbar, Goldbar_C, a unique start like gold, or a full path.
        summonstop                cancel summon batches that are still running
        dupe [count]              summon copies of whatever is under your crosshair, e.g.  dupe 5
        setmoney, addmoney, setlevel, setxp, maxskills, unlockall
                                  change your progress and save it (see progress.lua)

    Binds are saved in binds.txt next to this mod's Scripts folder and come back after a restart.
    A bind only fires when the key actually reached the game (not while you type in the console
    or a chat box). This mod's own commands run directly; anything else goes through the console.

    It also makes ToggleDebugCamera work both ways in hosted games (the debug camera gets a cheat
    manager), and binds keep working while the debug camera is on.
--]]

local MOD = "[OARCommands] "
local CHECK_RETRIES = 6          -- game ticks to wait for the key press to reach the game
local CHECK_DELAY_MS = 16

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
local DIGITS = { "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }
local DIGIT_UE = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
for i = 1, 10 do
    UE_KEY[DIGITS[i]] = DIGIT_UE[i]
    UE_KEY["NUM_" .. DIGITS[i]] = "NumPad" .. DIGIT_UE[i]
end
for c = string.byte("A"), string.byte("Z") do UE_KEY[string.char(c)] = string.char(c) end
for n = 1, 24 do UE_KEY["F" .. n] = "F" .. n end

-- What people type -> UE4SS key name.
local ALIASES = {
    SPACEBAR = "SPACE", ENTER = "RETURN", ESC = "ESCAPE", DELETE = "DEL", INSERT = "INS",
    PAGEUP = "PAGE_UP", PGUP = "PAGE_UP", PAGEDOWN = "PAGE_DOWN", PGDN = "PAGE_DOWN",
    LEFT = "LEFT_ARROW", RIGHT = "RIGHT_ARROW", UP = "UP_ARROW", DOWN = "DOWN_ARROW",
    CAPSLOCK = "CAPS_LOCK", TILDE = "OEM_THREE", MOUSE1 = "LEFT_MOUSE_BUTTON", MOUSE2 = "RIGHT_MOUSE_BUTTON",
    MOUSE3 = "MIDDLE_MOUSE_BUTTON", MIDDLEMOUSE = "MIDDLE_MOUSE_BUTTON", MOUSE4 = "XBUTTON_ONE",
    MOUSE5 = "XBUTTON_TWO", THUMBMOUSE = "XBUTTON_ONE",
}
for i = 1, 10 do
    ALIASES[tostring(i - 1)] = DIGITS[i]
    ALIASES["NUMPAD" .. (i - 1)] = "NUM_" .. DIGITS[i]
    ALIASES["NUM" .. (i - 1)] = "NUM_" .. DIGITS[i]
end

local Binds = {}          -- UE4SS key name -> console command
local Registered = {}     -- keys we already asked UE4SS to watch (they cannot be unregistered)

local function ScriptDir()
    local src = debug.getinfo(1, "S").source
    return (src:gsub("^@", ""):match("^(.*)[/\\][^/\\]*$")) or "."
end
local BINDS_FILE = ScriptDir() .. "/../binds.txt"

local function Say(Ar, msg)
    print(MOD .. msg .. "\n")
    if Ar then pcall(function() Ar:Log(msg) end) end
end

local function KeyFromText(text)
    local k = string.upper(text or "")
    k = ALIASES[k] or k
    if Key[k] ~= nil then return k end
    return nil
end

local function Save()
    local f = io.open(BINDS_FILE, "w")
    if not f then print(MOD .. "could not write " .. BINDS_FILE .. "\n") return end
    for k, cmd in pairs(Binds) do f:write(k, "=", cmd, "\n") end
    f:close()
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

local CheatManagerFor          -- defined with the summon code below
local OwnCommands = {}         -- this mod's console commands, so binds can call them directly

local function Command(name, fn)
    OwnCommands[name] = fn
    RegisterConsoleCommandHandler(name, fn)
end

-- Run a bound command line. "a | b" runs both; our own commands are called directly, anything
-- else goes through the normal console path (KismetSystemLibrary::ExecuteConsoleCommand).
local function RunCommandLine(pc, line)
    for part in line:gmatch("[^|]+") do
        local text = part:match("^%s*(.-)%s*$")
        local words = {}
        for w in text:gmatch("%S+") do words[#words + 1] = w end
        local name = words[1] and string.lower(table.remove(words, 1))
        if name and OwnCommands[name] then
            OwnCommands[name](text, words, nil)
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
    local ueKey = UE_KEY[keyName]
    if ueKey then
        local fkey = { KeyName = FName(ueKey) }
        if not (pc:IsInputKeyDown(fkey) or pc:WasInputKeyJustPressed(fkey)) then
            -- Not (yet) seen by the game: either input is still on its way, or the console/a menu has it.
            if attempt < CHECK_RETRIES then
                ExecuteWithDelay(CHECK_DELAY_MS, function()
                    ExecuteInGameThread(function() RunBound(keyName, attempt + 1) end)
                end)
            end
            return
        end
    end
    RunCommandLine(pc, cmd)
end

local function Watch(keyName)
    if Registered[keyName] then return end
    Registered[keyName] = true
    if IsKeyBindRegistered(Key[keyName]) then
        print(MOD .. keyName .. " is also used by another UE4SS mod\n")
    end
    RegisterKeyBind(Key[keyName], function()
        if Binds[keyName] then
            ExecuteInGameThread(function() RunBound(keyName, 0) end)
        end
    end)
end

local function Load()
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

Command("bind", function(FullCommand, Parameters, Ar)
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
    Save()
    Say(Ar, "Bound " .. keyName .. " to: " .. cmd)
    return true
end)

Command("unbind", function(FullCommand, Parameters, Ar)
    local keyName = KeyFromText(Parameters[1])
    if not keyName then Say(Ar, "Usage: unbind <key>") return true end
    Binds[keyName] = nil
    Save()
    Say(Ar, "Unbound " .. keyName)
    return true
end)

Command("unbindall", function(FullCommand, Parameters, Ar)
    Binds = {}
    Save()
    Say(Ar, "Removed every bind")
    return true
end)

--------------------------------------------------------------------------------------------------
-- summon <thing> [count]: spawns count copies, SPAWN_DELAY_MS apart, loading the class first so it
-- works on any map. Also answers to "spawn". summonstop cancels batches still running.
--------------------------------------------------------------------------------------------------
local SPAWN_DELAY_MS = 150
local SPAWN_MAX = 500
local Spawnables = require("spawnables")
local StopGeneration = 0

local function ResolveSpawnable(text)
    if text:sub(1, 1) == "/" then                                  -- full path given
        return { name = text:match("%.([^%.]+)$") or text, path = text }
    end
    local key = string.lower(text):gsub("_c$", "")
    if Spawnables[key] then return Spawnables[key] end
    local starts, contains = {}, {}
    for k, v in pairs(Spawnables) do
        if k:sub(1, #key) == key then starts[#starts + 1] = v
        elseif k:find(key, 1, true) then contains[#contains + 1] = v end
    end
    local pool = (#starts > 0) and starts or contains
    if #pool == 1 then return pool[1] end
    if #pool > 1 then
        table.sort(pool, function(a, b) return a.name < b.name end)
        local names = {}
        for i = 1, math.min(#pool, 8) do names[i] = pool[i].name end
        return nil, string.format("'%s' matches %d things: %s%s", text, #pool, table.concat(names, ", "),
            #pool > 8 and ", ..." or "")
    end
    return { name = text }                     -- not a Blueprint we know: let the engine try (PointLight etc.)
end

-- Cheat commands (summon, destroytarget, god...) need a CheatManager on the controller. Shipping
-- builds only make one in solo play, so build it ourselves when it is missing (same as UE4SS's
-- CheatManagerEnablerMod does, but on demand, so it also covers hosted games).
function CheatManagerFor(pc)
    local cm = pc.CheatManager
    if cm:IsValid() then return cm end
    local cls = pc.CheatClass
    if not cls:IsValid() then cls = StaticFindObject("/Script/Engine.CheatManager") end
    if cls:IsValid() then
        cm = StaticConstructObject(cls, pc, 0, 0, 0, nil, false, false, nil)
        if cm:IsValid() then
            pc.CheatManager = cm
            print(MOD .. "created a cheat manager\n")
            return cm
        end
    end
    return nil
end

-- ToggleDebugCamera switches you to a separate DebugCameraController. In hosted games the engine
-- gives it no cheat manager (and UE4SS's CheatManagerEnablerMod only adds one when a controller
-- gets a body), so ToggleDebugCamera could not run again to switch back. Give it one as it spawns.
NotifyOnNewObject("/Script/Engine.DebugCameraController", function(dcc)
    ExecuteInGameThread(function()
        if dcc:IsValid() then CheatManagerFor(dcc) end
    end)
end)

local function SpawnBatch(entry, count, Ar)
    local pc = LocalPlayerController()
    if not pc then Say(Ar, "No local player yet") return end
    if not CheatManagerFor(pc) then Say(Ar, "No cheat manager, cannot summon") return end
    if entry.path then LoadAsset(entry.path) end
    local generation, done = StopGeneration, 0
    local function step()
        if generation ~= StopGeneration then return end
        local p = LocalPlayerController()
        local cm = p and CheatManagerFor(p)
        if not cm then return end
        cm:Summon(entry.name)
        done = done + 1
        if done < count then
            ExecuteWithDelay(SPAWN_DELAY_MS, function() ExecuteInGameThread(step) end)
        end
    end
    step()
    Say(Ar, string.format("Summoning %s x%d%s", entry.label or entry.name, count,
        count > 1 and string.format(" (%.2fs apart, summonstop to cancel)", SPAWN_DELAY_MS / 1000) or ""))
end

local function SummonHandler(FullCommand, Parameters, Ar)
    if #Parameters == 0 then
        Say(Ar, "Usage: summon <thing> [count]   e.g.  summon goldbar 10")
        return true
    end
    local entry, err = ResolveSpawnable(Parameters[1])
    if not entry then Say(Ar, err) return true end
    local count = math.floor(tonumber(Parameters[2] or "1") or 1)
    count = math.max(1, math.min(count, SPAWN_MAX))
    SpawnBatch(entry, count, Ar)
    return true
end

Command("summon", SummonHandler)
Command("spawn", SummonHandler)
Command("summonstop", function(FullCommand, Parameters, Ar)
    StopGeneration = StopGeneration + 1
    Say(Ar, "Stopped all summon batches")
    return true
end)

--------------------------------------------------------------------------------------------------
-- dupe [count]: line trace from the camera (same call as UE4SS's LineTraceMod) and summon copies
-- of the actor's class by its full path, so two classes with the same short name can't mix up.
--------------------------------------------------------------------------------------------------
local TRACE_DISTANCE = 50000.0
local TRACE_VISIBILITY = 0            -- ETraceTypeQuery::TraceTypeQuery1
local DRAW_DEBUG_NONE = 0

local function LookedAtActor(pc)
    local cam = pc.PlayerCameraManager
    if not cam:IsValid() then return nil end
    local kml = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local start = cam:GetCameraLocation()
    local reach = kml:Multiply_VectorFloat(kml:GetForwardVector(cam:GetCameraRotation()), TRACE_DISTANCE)
    local finish = kml:Add_VectorVector(start, reach)
    local pawn = pc.Pawn
    local ignore = {}
    if pawn:IsValid() then ignore[1] = pawn end
    local hit = {}
    local color = { R = 0, G = 0, B = 0, A = 0 }
    local wasHit = ksl:LineTraceSingle(pawn:IsValid() and pawn or pc, start, finish, TRACE_VISIBILITY, true,
        ignore, DRAW_DEBUG_NONE, hit, true, color, color, 0.0)
    if not wasHit then return nil end
    local ok, actor = pcall(function() return hit.Actor:Get() end)
    if ok and actor and actor:IsValid() then return actor end
    return nil
end

Command("dupe", function(FullCommand, Parameters, Ar)
    local pc = LocalPlayerController()
    if not pc then Say(Ar, "No local player yet") return true end
    local actor = LookedAtActor(pc)
    if not actor then Say(Ar, "Not looking at anything") return true end
    local cls = actor:GetClass()
    local className = cls:GetFName():ToString()
    if cls:GetClass():GetFName():ToString() ~= "BlueprintGeneratedClass" then
        Say(Ar, string.format("That is %s, a plain part of the map; dupe only copies game objects", className))
        return true
    end
    local path = cls:GetFullName():match("%s(%S+)$") or className   -- "BlueprintGeneratedClass /Game/..X_C"
    local count = math.floor(tonumber(Parameters[1] or "1") or 1)
    count = math.max(1, math.min(count, SPAWN_MAX))
    SpawnBatch({ name = path, label = className }, count, Ar)
    return true
end)

-- setmoney, addmoney, setlevel, setxp, maxskills, unlockall
require("progress").Register({ Command = Command, Say = Say, LocalPlayerController = LocalPlayerController })

Load()
print(MOD .. "loaded, binds file: " .. BINDS_FILE .. "\n")
