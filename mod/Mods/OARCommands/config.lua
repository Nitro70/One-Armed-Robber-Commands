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
      unlockall) and maps.lua (selectmap, forcemap).

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
    ChangeLog = "OAR\\Saved\\SaveGames\\OARCommands-changes.log",   -- inside your local application data folder

    ------------------------------------------------------------------------------------------
    -- noclip
    ------------------------------------------------------------------------------------------
    NoclipKeysUp = { "SpaceBar" },                         -- Unreal key names
    NoclipKeysDown = { "LeftControl", "RightControl" },
    NoclipKeysFast = { "LeftShift", "RightShift" },
    NoclipFastMultiplier = 2,        -- speed while a fast key is held
    NoclipSpeed = 0,                 -- flying speed; 0 = your walking speed
    -- The event of your character that runs every frame; noclip adds up and down from it.
    NoclipFrameEvent = "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:InpAxisEvt_MoveForward_K2Node_InputAxisEvent_0",

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
    ShareWorldCommands = { "destroyall", "slomo", "playersonly", "changesize" },
    -- Never passed to the host, at any level
    ShareBlockedCommands = {
        -- would close, move or cut off the host's game
        "exit", "quit", "open", "travel", "servertravel", "disconnect", "reconnect", "switchlevel", "restartlevel",
        "streammap", "demoplay", "demorec", "selectmap", "forcemap",
        -- would touch the host's files or crash it
        "exec", "deletecloudfiles", "doublefreefindercrash", "mallocframeprofiler", "purchase", "debug",
        -- this mod's commands that always stay on your own game
        "setmoney", "addmoney", "setlevel", "setxp", "maxskills", "unlockall", "bind", "unbind", "unbindall",
        "commandsharing", "host", "reloadconfig",
    },
    -- Engine cheats a guest's mod passes to the host: what you type -> the engine's own spelling.
    -- Command names match exactly, so both spellings are watched.
    ShareEngineCheats = { god = "God", ghost = "Ghost", fly = "Fly", walk = "Walk", teleport = "Teleport",
                          destroytarget = "DestroyTarget", destroyall = "DestroyAll", slomo = "Slomo",
                          playersonly = "PlayersOnly", changesize = "ChangeSize" },
    -- Commands that send the guest's camera position and angle along
    ShareAimedCommands = { "destroytarget", "dupe", "teleport" },
}

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

local function Watch(keyName)
    local shared = Core.KeyBind(keyName, function()
        if Binds[keyName] then
            ExecuteInGameThread(function() RunBound(keyName, 0) end)
        end
    end)
    if shared then Print(keyName .. " is also used by another UE4SS mod") end
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

-- One property's name and its value in a form that can be put on another object. Nothing for the
-- kinds that are left alone (see the top of this section).
local function CopyableValue(owner, prop)
    local name = prop:GetFName():ToString()
    if PropertyIs(prop, "ClassProperty") or PropertyIs(prop, "ObjectProperty") then
        local value = owner[name]
        if not Valid(value) or IsKind(value, "Actor") or IsKind(value, "ActorComponent") then return nil end
        return name, value
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
            if Valid(mesh) then c.mesh, c.skeletal = mesh, skeletal or nil end
            c.materials = {}
            for slot = 0, comp:GetNumMaterials() - 1 do
                local material = comp:GetMaterial(slot)
                if Valid(material) then c.materials[slot] = material end
            end
            c.scale = PlainStruct(comp.RelativeScale3D)
        end
        if c.props or c.mesh or c.materials then data.comps[name] = c end
    end
    return data
end

-- The data of a name from objects.lua, with its meshes and materials loaded. nil for a plain class.
local function DataOf(entry)
    if not (entry.props or entry.assets or entry.comps) then return nil end
    local data = { props = {}, comps = {} }
    for name, value in pairs(entry.props or {}) do data.props[#data.props + 1] = { name, value } end
    for name, path in pairs(entry.assets or {}) do
        local asset = LoadClass(path)
        if asset then data.props[#data.props + 1] = { name, asset } end
    end
    for name, c in pairs(entry.comps or {}) do
        local out = { skeletal = c.skeletal }
        if c.mesh then out.mesh = LoadClass(c.mesh) end
        if c.materials then
            out.materials = {}
            for slot, path in pairs(c.materials) do out.materials[slot] = LoadClass(path) end
        end
        if c.scale then out.scale = { X = c.scale[1], Y = c.scale[2], Z = c.scale[3] } end
        data.comps[name] = out
    end
    return data
end

local function SetProps(object, props)
    for _, p in ipairs(props or {}) do
        pcall(function() object[p[1]] = p[2] end)
    end
end

-- Give a component another mesh. Returns true when the mesh changed.
local function SetMesh(comp, c)
    if c.skeletal then
        comp:SetSkeletalMesh(c.mesh, true)
        return true
    end
    local current = comp.StaticMesh
    if Valid(current) and current:GetAddress() == c.mesh:GetAddress() then return false end
    if comp:SetStaticMesh(c.mesh) then return true end
    -- The engine refuses a component that is set to never move: make it movable for the change.
    local mobility = comp.Mobility
    comp:SetMobility(2)                         -- EComponentMobility::Movable
    comp:SetStaticMesh(c.mesh)
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
                if c.mesh and SetMesh(comp, c) and V.CopyLookToGuests and actor:HasAuthority() then
                    comp:SetIsReplicated(true)
                end
                for slot, material in pairs(c.materials or {}) do
                    if material then comp:SetMaterial(slot, material) end
                end
                if c.scale then comp:SetRelativeScale3D(c.scale) end
            end)
            if not ok then Print("could not copy the data of " .. name .. ": " .. tostring(problem)) end
        end
    end
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

-- entry: { name, path, label, and for an object its data (props, assets, comps) }.
-- dupe passes cls and data itself. target: the controller to summon for (a guest's, on the
-- host); default your own.
local function SpawnBatch(entry, count, Ar, target)
    local pc = target or LocalPlayerController()
    if not pc then Say(Ar, "No local player yet") return "no local player" end
    if not CheatManagerFor(pc) then Say(Ar, "No cheat manager, cannot summon") return "no cheat manager" end
    if entry.path then LoadAsset(entry.path) end
    local cls, data = entry.cls, entry.data
    if not data then
        local ok, loaded = pcall(DataOf, entry)
        if ok then data = loaded else Print("could not load the data of " .. tostring(entry.label) .. ": " .. tostring(loaded)) end
        if data then cls = LoadClass(entry.path) end
    end
    if data and not Valid(cls) then data = nil end
    local generation, done = State.summonGeneration, 0
    local delay = V.SummonDelayMs
    local function step()
        if generation ~= State.summonGeneration then return end
        local p = target or LocalPlayerController()
        if not (p and p:IsValid()) then return end
        local cm = CheatManagerFor(p)
        if not cm then return end
        local spawned = false
        if data then
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
    return SpawnBatch({ name = path, label = className, cls = cls, data = data }, count, Ar, pc)
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
--------------------------------------------------------------------------------------------------
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

Edit("setxp", "setxp <amount>   e.g.  setxp 100", function(pc, p, Ar)
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
State.noclip = State.noclip or {}               -- character address -> { pawn, on, base, oldFly, fast, localInput }

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

-- Every frame while you control your character: Space/Ctrl up and down, Shift speed.
local function OnNoclipFrame(pawn)
    local st = State.noclip[pawn:GetAddress()]
    if not (st and st.on and st.localInput) then return end
    local pc = Robber()
    if not pc then return end
    local v = (KeyDown(pc, V.NoclipKeysUp) and 1.0 or 0.0) - (KeyDown(pc, V.NoclipKeysDown) and 1.0 or 0.0)
    if v ~= 0 then pawn:AddMovementInput(UP, v, true) end
    local fast = KeyDown(pc, V.NoclipKeysFast)
    if fast ~= st.fast then
        st.fast = fast
        local speed = st.base * (fast and V.NoclipFastMultiplier or 1)
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
        if not st then
            st = { pawn = pawn, oldFly = cm.MaxFlySpeed, base = V.NoclipSpeed > 0 and V.NoclipSpeed or cm.MaxWalkSpeed,
                   fast = false }
            State.noclip[key] = st
        end
        st.on, st.localInput = true, localInput
        pawn:SetActorEnableCollision(false)
        cm.bCheatFlying = true                  -- stop dead when the keys are let go
        cm:SetMovementMode(MOVE_FLYING, 0)
        cm.MaxFlySpeed = speed or st.base * (st.fast and V.NoclipFastMultiplier or 1)
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
    local function here(ArNow)
        Out(ArNow, SetNoclip(pawn, on, on and speed or nil, true) ..
            (on and ": WASD to move, Space up, Ctrl down, Shift faster" or ""))
    end
    local line = on and ("noclip on " .. Decimal(speed)) or "noclip off"
    -- As a guest the host does it to your character too; your game does the same so both agree.
    local later = function() here(nil) end
    if Share.Relay(line, Ar, later, { onOk = later }) then return true end
    here(Ar)
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
local function Revive(pc)
    local pawn = pc and pc.Pawn
    if not (pawn and pawn:IsValid()) then return "no character to revive" end
    local down = pawn["Downed?"]
    pawn.Health = pawn.MaxHealth
    pawn["Downed?"] = false
    pawn:ReviveClient()
    return down and "revived" or "not downed, health refilled"
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
        S.pending[id] = { line = line, fallback = fallback, onOk = opts.onOk }
        ExecuteWithDelay(V.ShareTimeoutMs, function()
            ExecuteInGameThread(function()
                local p = S.pending[id]
                if not p then return end
                S.pending[id] = nil
                S.active, S.silentUntil = false, os.time() + V.ShareSilentSeconds
                Share.Notice("the host did not answer, so '" .. p.line .. "' runs on your game")
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
        Share.Notice("the host said " .. status .. ", so '" .. p.line .. "' runs on your game")
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
for lower, capital in pairs(V.ShareEngineCheats) do
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
        if text:sub(1, #V.ShareReplyPrefix) == V.ShareReplyPrefix then Share.HandleReply(text) end
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
-- Last: read binds.txt, and show a few things to other scripts (OARCommands.Exports)
--------------------------------------------------------------------------------------------------
LoadBinds()

Core.Exports.Values = V
Core.Exports.Share = Share
Core.Exports.Lobby = { Resolve = ResolveMap }
