"""Run OARCommands (Scripts/main.lua, which loads config.lua) against stub UE4SS globals and check
its behaviour, including editing config.lua and loading it again with reloadconfig."""
import os
import shutil
import tempfile

from lupa import LuaRuntime

MOD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mod", "Mods", "OARCommands")
SCRIPTS = os.path.join(MOD, "Scripts")


def write_config(tmp, text, name="config.lua"):
    with open(os.path.join(tmp, "OARCommands", name), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def make_runtime(tmp, config_text=None):
    scripts = os.path.join(tmp, "OARCommands", "Scripts")
    os.makedirs(scripts, exist_ok=True)
    for f in ("main.lua", "spawnables.lua", "objects.lua", "unlockables.lua", "maps.lua", "gui.lua", "esp.lua"):
        shutil.copy(os.path.join(SCRIPTS, f), os.path.join(scripts, f))
    if config_text is None:
        config_text = open(os.path.join(MOD, "config.lua"), encoding="utf-8").read()
    write_config(tmp, config_text)
    write_config(tmp, open(os.path.join(MOD, "config.lua"), encoding="utf-8").read(), "config.default.lua")
    os.environ["LOCALAPPDATA"] = tmp                  # the change log goes under tmp\OAR\Saved\SaveGames
    os.makedirs(os.path.join(tmp, "OAR", "Saved", "SaveGames"), exist_ok=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        Calls = {}            -- ExecuteConsoleCommand calls
        Summons = {}          -- CheatManager:Summon calls
        Loads = {}            -- LoadAsset calls
        Delays = {}           -- queued ExecuteWithDelay callbacks {ms, fn}
        Handlers = {}
        KeyCallbacks = {}
        KeyDown = true
        QueueDelays = false
        Key = setmetatable({}, {__index = function(t, k)
            local ok = (type(k) == "string") and (k:match("^[A-Z]$") or k:match("^F%d+$") or
                ({SPACE=1, RETURN=1, ESCAPE=1, NUM_FIVE=1, FIVE=1, XBUTTON_ONE=1, OEM_THREE=1, LEFT_MOUSE_BUTTON=1})[k])
            if ok then return "KEY_" .. k end
            return nil
        end})
        Registrations = {}    -- how often each command, key and hook was registered with UE4SS
        local function Count(kind, name) Registrations[kind .. " " .. name] = (Registrations[kind .. " " .. name] or 0) + 1 end
        function RegisterConsoleCommandHandler(name, fn) Count("command", name); Handlers[name] = fn end
        function RegisterProcessConsoleExecPreHook(fn) Count("consolehook", "pre") end
        function RegisterKeyBind(key, fn) Count("key", key); KeyCallbacks[key] = fn end
        Hooks = {}
        -- Blueprint functions that are not loaded yet (the character's, until a heist loads it)
        MissingHooks = { ["/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:StartRevive"] = true, ["/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:RevivePlayer"] = true }
        PostHooks = {}        -- a hook's second callback (after the function), when it has one
        function RegisterHook(name, fn, post)
            if MissingHooks[name] then error("Tried to register a hook with Lua function 'RegisterHook' but no UFunction with the specified name was found.") end
            Count("hook", name); Hooks[name] = fn; PostHooks[name] = post; return 1, 2
        end
        function Param(v) return { get = function() return v end } end          -- a hook parameter
        function FStr(s) return { ToString = function() return s end } end
        function IsKeyBindRegistered(key) return false end
        function ExecuteInGameThread(fn) fn() end
        function ExecuteWithDelay(ms, fn)
            if QueueDelays then Delays[#Delays + 1] = {ms, fn} else fn() end
        end
        function RunDelays()
            while #Delays > 0 do local d = table.remove(Delays, 1); d[2]() end
        end
        function FName(s) return s end
        function LoadAsset(p) Loads[#Loads + 1] = p end
        CM = {}
        function CM:IsValid() return true end
        function CM:Summon(name) Summons[#Summons + 1] = name end
        Invalid = {}
        function Invalid:IsValid() return false end
        Constructed = 0
        OtherSummons = {}     -- Summon calls on cheat managers of other controllers: {owner, name}
        function StaticConstructObject(cls, outer)
            if cls and cls.UMGName then return FakeWidget(cls.UMGName) end
            Constructed = Constructed + 1
            if outer == PC or outer == DCC then return CM end
            local cm = { IsValid = function() return true end }
            function cm:Summon(name) OtherSummons[#OtherSummons + 1] = { owner = outer, name = name } end
            return cm
        end
        PC = { CheatManager = CM, CheatClass = CM }
        function PC:IsValid() return true end
        function PC:IsLocalController() return true end
        KeysDown = {}          -- per-key override of KeyDown
        function PC:IsInputKeyDown(k)
            assert(k.KeyName)
            if KeysDown[k.KeyName] ~= nil then return KeysDown[k.KeyName] end
            return KeyDown
        end
        Authority = true       -- false: this game is a guest in someone else's lobby
        function PC:HasAuthority() return Authority end
        function PC:GetAddress() return 42 end
        Sent, Messages = {}, {}  -- ServerExecRPC calls; ClientMessage texts
        function PC:ServerExecRPC(msg) Sent[#Sent + 1] = msg end
        function PC:ClientMessage(text) Messages[#Messages + 1] = text; if Hooks["/Script/Engine.PlayerController:ClientMessage"] then Hooks["/Script/Engine.PlayerController:ClientMessage"](Param(PC), Param(FStr(text))) end end
        function PC:WasInputKeyJustPressed(k) return false end
        function PC:EnableCheats() end
        function PC:GetWorld() return World end
        function PC:GetControlRotation() return { Pitch = 0, Yaw = 90, Roll = 0 } end
        function PC:GetFocalLocation() return { X = 100, Y = 0, Z = 50 } end
        -- the lobby: its manager, the host's menu and one lobby character per player
        Lobby, GI, Menu, MenuPlayers = nil, nil, nil, {}
        function NewLobby(players)
            Lobby = { SelectedMap = Invalid, Selects = {} }
            function Lobby:IsValid() return true end
            function Lobby:SelectMap(cls) self.SelectedMap = cls; self.Selects[#self.Selects + 1] = cls.Path end
            Menu = { Started = {}, Shown = true }
            function Menu:IsValid() return true end
            function Menu:IsInViewport() return self.Shown end
            function Menu:StartGame()
                local ready = true
                for _, p in ipairs(MenuPlayers) do ready = ready and p["Ready?"] end
                self.Started[#self.Started + 1] = { map = Lobby.SelectedMap.Path, ready = ready }
            end
            MenuPlayers = {}
            for i = 1, players do MenuPlayers[i] = { ["Ready?"] = false, IsValid = function() return true end } end
            PC.UnlockedMaps, PC.InventoryResultItems = MakeArray(), MakeArray()
        end
        GIUpdates = {}
        GI = { IsValid = function() return true end }
        function GI:UpdateMap(cls) GIUpdates[#GIUpdates + 1] = cls.Path end
        Objects = {}          -- FindObjects results by class name
        FindObjectsCalls = {}
        ObjectSearches = 0
        function FindObjects(n, className, shortName, required, banned, exact)
            ObjectSearches = ObjectSearches + 1
            FindObjectsCalls[#FindObjectsCalls + 1] = { class = className, banned = banned, exact = exact }
            if className == "PlayerCharacter_C" then return Characters or {} end
            return Objects[className] or {}
        end
        function FindAllOf(name)
            ObjectSearches = ObjectSearches + 1
            if name == "MainMenuUI_C" then return Menu and { Menu } or nil end
            if name == "MainMenuPlayer_C" then return #MenuPlayers > 0 and MenuPlayers or nil end
            if name == "PlayerCharacter_C" then return Characters end
            if name == "PlayerController" then return { PC, GuestPC } end     -- the live controllers
            if name == "HammerCursor_C" then                                 -- live windows only (the engine's list)
                local live = {}
                for _, w in ipairs(UMG and UMG.windows or {}) do if not w.Freed then live[#live + 1] = w end end
                return live
            end
            return { PC }
        end
        -- debug camera: its own controller, which the engine gives no cheat manager in hosted games
        DCC = { CheatManager = Invalid, CheatClass = CM }
        function DCC:IsValid() return true end
        function DCC:IsLocalController() return true end
        function DCC:IsInputKeyDown(k) return true end
        function DCC:GetWorld() return PC:GetWorld() end      -- the free camera is in the same world
        function DCC:WasInputKeyJustPressed(k) return false end
        LP = nil              -- the LocalPlayer; nil means "not found", like during loading
        function FindFirstOf(name)
            ObjectSearches = ObjectSearches + 1
            if name == "LocalPlayer" then return LP end
            if name == "LobbyManager_C" then return Lobby end
            if name == "LeaveButton_C" then return Button end
            if name == "RobberTruck_C" then return Truck end
            if name == "RobberGI_C" then return GI end
        end
        NewObjectHooks = {}
        function NotifyOnNewObject(cls, fn) Count("class", cls); NewObjectHooks[cls] = fn end
        CallPCs = {}          -- which controller each ExecuteConsoleCommand ran on
        local KSL = {}
        function KSL:IsValid() return true end
        HandlerResults = {}   -- what a UE4SS console handler answered when the engine ran a command
        function KSL:ExecuteConsoleCommand(world, cmd, pc)
            Calls[#Calls + 1] = cmd; CallPCs[#CallPCs + 1] = pc
            -- For your own player the engine's console path passes UE4SS's handlers first
            local name = cmd:match("^(%S+)")
            if (pc == PC or pc == DCC) and Handlers[name] and not OwnHandler(name) then
                local params = {}
                for w in cmd:gmatch("%S+") do params[#params + 1] = w end
                table.remove(params, 1)
                HandlerResults[#HandlerResults + 1] = Handlers[name](cmd, params, nil)
            end
        end
        -- line trace for dupe
        LookTarget = nil      -- actor the fake trace hits
        TraceArgs = nil
        function KSL:LineTraceSingle(ctx, s, e, chan, complex, ignore, draw, hit, ignoreSelf, c1, c2, t)
            TraceArgs = { chan = chan, complex = complex, ignored = ignore[1] }
            if LookTarget then
                hit.Actor = { Get = function() return LookTarget end }
                hit.Location = LookLocation or { X = 0, Y = 0, Z = 0 }
            end
            return LookTarget ~= nil
        end
        local KML = {}
        function KML:GetForwardVector(r) return { X = 1, Y = 0, Z = 0 } end
        function KML:Multiply_VectorFloat(v, f) return { X = v.X * f, Y = v.Y * f, Z = v.Z * f } end
        function KML:Add_VectorVector(a, b) return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z } end
        -- value commands: game classes the mod looks up by path, and which of them are loaded
        Classes, Loaded = {}, {}
        local nextAddress = 1000
        function FakeClass(path)
            if not Classes[path] then
                nextAddress = nextAddress + 8
                local addr = nextAddress
                Classes[path] = { Path = path, IsValid = function() return true end,
                                  GetAddress = function() return addr end,
                                  GetFullName = function() return "BlueprintGeneratedClass " .. path end }
            end
            return Classes[path]
        end
        function LoadAsset(p) Loads[#Loads + 1] = p; Loaded[p] = true end
        Dirty = {}            -- MarkPropertyDirty calls: "address:property"
        Helpers = { IsValid = function() return true end }
        function Helpers:MarkPropertyDirty(object, name) Dirty[#Dirty + 1] = object:GetAddress() .. ":" .. name end
        LoadMapHooks = {}
        function RegisterLoadMapPostHook(fn) Count("loadmap", "post"); LoadMapHooks[#LoadMapHooks + 1] = fn end
        function StaticFindObject(path)
            if path == "/Script/Engine.Default__NetPushModelHelpers" then return Helpers end
            if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return WBL end
            if path == "/Script/UMG.OARCommands_NoSuchObject" then return Invalid end
            if path == "/Script/UMG.Default__WidgetLayoutLibrary" then return WLL end
            local umg = path:match("^/Script/UMG%.(%a+)$")
            if umg then
                UMGClasses[umg] = UMGClasses[umg] or { UMGName = umg, IsValid = function() return true end }
                return UMGClasses[umg]
            end
            if path:find("KismetMathLibrary", 1, true) then return KML end
            if ByPath and ByPath[path] then return ByPath[path] end
            if path:sub(1, 6) == "/Game/" then
                if Loaded[path] then return FakeClass(path) end
                return Invalid
            end
            local engine = path:match("^/Script/Engine%.(%a+)$")
            if engine and EngineKinds[engine] then return EngineKinds[engine] end
            return KSL
        end
        -- engine classes the mod asks for by path; an object says which of them it is with Kinds
        EngineKinds = {}
        for _, name in ipairs({ "Actor", "ActorComponent", "StaticMeshComponent", "SkeletalMeshComponent" }) do
            EngineKinds[name] = { EngineName = name, IsValid = function() return true end }
        end
        PropertyTypes = setmetatable({}, { __index = function(t, k) return k end })
        -- UE4SS 3.0.1 TArray, including its off-by-one (LuaTArray.cpp prepare_to_handle): indexing
        -- only grows the array when the 0-based index is ABOVE Num (or the array is empty), by
        -- index - Num elements (1 when empty), and then touches that index anyway. So only
        -- "empty array, index 1" grows safely; anything else past the end is an out-of-bounds access.
        OutOfBounds = 0
        function MakeArray(items, newElement)
            local data = items or {}
            local function touch(k)
                local i, num = k - 1, #data
                if i > num or num == 0 then
                    local count = (i == 0 or num == 0) and 1 or (i - num)
                    for _ = 1, count do data[#data + 1] = newElement and newElement() or {} end
                end
                if i >= #data then OutOfBounds = OutOfBounds + 1 return false end
                return true
            end
            return setmetatable({ Data = data }, {
                __index = function(t, k)
                    if k == "GetArrayNum" then return function() return #data end end
                    if k == "Empty" then return function() for i = #data, 1, -1 do data[i] = nil end end end
                    if type(k) == "number" then
                        if not touch(k) then return {} end        -- past the end: memory that isn't the array's
                        return data[k]
                    end
                end,
                __newindex = function(t, k, v)
                    if touch(k) then data[k] = v end
                end,
            })
        end
        -- A UE4SS 3.0.1 struct: fields read back live. Assigning a Lua table to a field fails when
        -- the table holds a class: push_classproperty checks is_userdata() at stack slot 1 (the
        -- table) instead of the member's value, and throws "Value must be UClass or nil".
        function StructProxy(fields)
            local store = fields or {}
            return setmetatable({}, {
                __index = store,
                __newindex = function(t, k, v)
                    if type(v) == "table" and not v.GetAddress then
                        for _, x in pairs(v) do
                            if type(x) == "table" and x.GetAddress then
                                error("[push_classproperty] Value must be UClass or nil")
                            end
                        end
                    end
                    store[k] = v
                end,
            })
        end
        function NewResearch()
            local P = require("unlockables").ProgressFields
            return StructProxy({ [P.skill] = StructProxy(), [P.progress] = 0 })
        end
        local function Named(s) return { ToString = function() return s end } end
        function ClassNamed(s) return { GetFName = function() return Named(s) end } end

        -- Objects with data: assets, components, Blueprint classes with properties, and the world
        -- that spawns actors (UE4SS: World:SpawnActor(class, location table, rotation table)).
        local nextAsset = 5000
        ByPath = {}           -- objects StaticFindObject finds by their path (assets, Blueprint classes)
        function FakeAsset(name)
            nextAsset = nextAsset + 8
            local addr = nextAsset
            local path = "/Game/Fake/" .. name .. "." .. name
            local a = { Name = name, IsValid = function() return true end, GetAddress = function() return addr end,
                        IsA = function() return false end, GetFullName = function() return "StaticMesh " .. path end }
            ByPath[path] = a
            return a
        end
        NativeClass = { IsValid = function() return true end,
                        GetClass = function() return { GetFName = function() return Named("Class") end } end,
                        GetFName = function() return Named("StaticMeshComponent") end }
        function NewMeshComponent(name, mesh, materials, mobility)
            local c = { StaticMesh = mesh or Invalid, Materials = materials or {}, Mobility = mobility or 2,
                        RelativeScale3D = { X = 1, Y = 1, Z = 1 }, Replicated = false, MobilityChanges = 0,
                        Kinds = { StaticMeshComponent = true, ActorComponent = true } }
            function c:IsValid() return true end
            function c:GetFName() return Named(name) end
            function c:GetClass() return NativeClass end
            function c:IsA(cls) return self.Kinds[cls.EngineName] == true end
            function c:GetNumMaterials() return #self.Materials end              -- slot 0 is Materials[1]
            function c:GetMaterial(slot) return self.Materials[slot + 1] or Invalid end
            function c:SetMaterial(slot, m) self.Materials[slot + 1] = m end
            function c:SetStaticMesh(mesh)
                if self.Mobility == 0 then return false end                      -- the engine refuses a static component
                self.StaticMesh = mesh
                return true
            end
            function c:SetMobility(m) self.Mobility = m; self.MobilityChanges = self.MobilityChanges + 1 end
            function c:SetRelativeScale3D(v) self.RelativeScale3D = { X = v.X, Y = v.Y, Z = v.Z } end
            function c:SetIsReplicated(on) self.Replicated = on end
            return c
        end
        -- props: { { name, type }, ... }; components: function returning the Blueprint's own components
        function NewBlueprintClass(name, path, parent, props, components)
            nextAsset = nextAsset + 8
            local addr = nextAsset
            local cls = { Path = path, Components = components }
            function cls:IsValid() return true end
            function cls:GetAddress() return addr end
            function cls:GetFName() return Named(name) end
            function cls:GetFullName() return "BlueprintGeneratedClass " .. path end
            function cls:GetClass() return { GetFName = function() return Named("BlueprintGeneratedClass") end } end
            ByPath[path] = cls
            function cls:GetSuperStruct() return parent or NativeClass end
            function cls:ForEachProperty(fn)
                for _, prop in ipairs(props or {}) do
                    fn({ GetFName = function() return Named(prop[1]) end,
                         IsA = function(_, kind) return kind == prop[2] end })
                end
            end
            return cls
        end
        function NewItemActor(cls, fields)
            local a = { Root = NewMeshComponent("StaticMeshComponent0", FakeAsset("DefaultMesh"), { FakeAsset("DefaultMaterial") },
                                                StaticRoots and 0 or 2),
                        BlueprintCreatedComponents = MakeArray(cls.Components and cls.Components() or {}),
                        Kinds = { Actor = true }, Authority = true }
            for k, v in pairs(fields or {}) do a[k] = v end
            function a:IsValid() return true end
            function a:GetClass() return cls end
            function a:K2_GetRootComponent() return self.Root end
            function a:HasAuthority() return self.Authority end
            function a:IsA(c) return self.Kinds[c.EngineName] == true end
            return a
        end
        Spawned, SpawnFails, StaticRoots = {}, false, false
        World = { GetAddress = function() return 3000 end }
        function World:SpawnActor(cls, location, rotation)
            assert(type(location) == "table" and type(rotation) == "table", "UE4SS wants tables for location and rotation")
            if SpawnFails then return Invalid end
            local actor = NewItemActor(cls)
            Spawned[#Spawned + 1] = { cls = cls, location = location, rotation = rotation, actor = actor }
            return actor
        end
        function NewLook(text)
            local c = { Name = FStr(text), Kinds = { ActorComponent = true } }
            function c:IsValid() return true end
            function c:GetFName() return Named("LookatInfoComponent") end
            function c:GetClass() return LookClass end
            function c:IsA(cls) return self.Kinds[cls.EngineName] == true end
            return c
        end
        LookClass = NewBlueprintClass("LookatInfoComponent_C", "/Game/BP/Component/LookatInfoComponent.LookatInfoComponent_C",
                                      nil, { { "Name", "StrProperty" } })
        -- A painting as it hangs in the museum: an Artwork (Statue_museum_C) with its own mesh, two
        -- materials, size, value and look-at text, plus things that must not be copied.
        function NewPainting()
            local base = NewBlueprintClass("Money_base_C", "/Game/BP/Items/Valuables/Money_base.Money_base_C", nil,
                { { "Value", "IntProperty" }, { "EXP", "FloatProperty" }, { "UberGraphFrame", "StructProperty" } })
            local cls = NewBlueprintClass("Statue_museum_C", "/Game/BP/Items/Valuables/Statue_museum.Statue_museum_C", base,
                { { "Title", "StrProperty" }, { "Tint", "StructProperty" }, { "LookatInfoComponent", "ObjectProperty" },
                  { "Sound", "ObjectProperty" }, { "Kind", "ClassProperty" }, { "Holder", "ObjectProperty" },
                  { "Parts", "ArrayProperty" }, { "Stolen?", "BoolProperty" }, { "Sort", "NameProperty" } },
                function() return { NewLook("Artwork") } end)
            local look = NewLook("Mona Lisa")
            local holder = { Kinds = { Actor = true }, IsValid = function() return true end }
            function holder:IsA(c) return self.Kinds[c.EngineName] == true end
            local actor = NewItemActor(cls, { Value = 45000, EXP = 10.5, UberGraphFrame = {}, Title = FStr("Painting"),
                Tint = { R = 1, G = 0.5, B = 0, A = 1 }, LookatInfoComponent = look, Sound = FakeAsset("Clink"),
                Kind = FakeAsset("SomeClass"), Holder = holder, Parts = MakeArray({ 1, 2 }), ["Stolen?"] = true,
                Sort = "Painting" })
            actor.Root = NewMeshComponent("StaticMeshComponent0", FakeAsset("PaintingMesh"), { FakeAsset("Canvas"), FakeAsset("Frame") })
            actor.Root.RelativeScale3D = { X = 0.35, Y = 0.35, Z = 0.35 }
            actor.BlueprintCreatedComponents = MakeArray({ look })
            return actor
        end
        GameCalls = {}        -- SaveCash, LoadLevel... in call order
        for _, fn in ipairs({ "SaveCash", "LoadCash", "SaveLevel", "LoadLevel", "SaveInventoryItems" }) do
            PC[fn] = function(self) GameCalls[#GameCalls + 1] = fn end
        end
        -- The game's own Blueprint functions, which append with Kismet's Array_Add (always safe)
        function PC:AddInventoryItem(item, out)
            assert(type(out) == "table", "UE4SS needs a table for out parameters")
            local d = self.ItemInventory.Data
            d[#d + 1] = item
            out.Index = #d - 1
            GameCalls[#GameCalls + 1] = "AddInventoryItem"
            GameCalls[#GameCalls + 1] = "SaveInventoryItems"
        end
        function PC:ProgressSkills(xp)
            local U = require("unlockables")
            local F, P = U.SkillFields, U.ProgressFields
            local research, owned = self.ResearchingSkills.Data, self.UnlockedSkills.Data
            for i = #research, 1, -1 do
                local r = research[i]
                r[P.progress] = (r[P.progress] or 0) + xp / #research
                if r[P.progress] >= 150 then                           -- RequiredProgress is 150..450
                    local done = false
                    for _, e in ipairs(owned) do
                        if e[F.skill] == r[P.skill][F.skill] then e[F.tier] = r[P.skill][F.tier]; done = true end
                    end
                    if not done then owned[#owned + 1] = { [F.skill] = r[P.skill][F.skill], [F.tier] = r[P.skill][F.tier] } end
                    table.remove(research, i)
                end
            end
            GameCalls[#GameCalls + 1] = "ProgressSkills"
        end
        function PC:GetClass() return ClassNamed("RobberController_C") end
        function DCC:GetClass() return ClassNamed("DebugCameraController") end
        DCC.OriginalControllerRef = PC
        function ResetProgress()
            PC.Cash, PC.Level, PC.EXP = 100, 3, 12.5
            PC.UnlockedSkills, PC.ResearchingSkills, PC.ItemInventory = MakeArray(), MakeArray(nil, NewResearch), MakeArray()
            GameCalls, Log = {}, {}
        end
        ResetProgress()
        local function Named(s) return { ToString = function() return s end } end
        local function FakeActor(className, meta, fullName)
            local cls = {}
            function cls:GetFName() return Named(className) end
            function cls:GetClass() return { GetFName = function() return Named(meta) end } end
            function cls:GetFullName() return fullName end
            local a = {}
            function a:IsValid() return true end
            function a:GetClass() return cls end
            return a
        end
        GoldActor = FakeActor("Goldbar_C", "BlueprintGeneratedClass",
            "BlueprintGeneratedClass /Game/BP/Items/Valuables/Goldbar.Goldbar_C")
        WallActor = FakeActor("StaticMeshActor", "Class", "Class /Script/Engine.StaticMeshActor")
        -- a character: movement component, health, revive, collision
        function MakePawn(addr)
            local cm = { MaxWalkSpeed = 600, MaxFlySpeed = 600, bCheatFlying = false, Mode = 1 }
            function cm:SetMovementMode(m, c) self.Mode = m; self.MovementMode = m end
            local pawn = { CharacterMovement = cm, Health = 100, MaxHealth = 100, ["Downed?"] = false,
                           Collision = true, Inputs = {}, Revived = 0 }
            function pawn:IsValid() return true end
            function pawn:GetAddress() return addr end
            function pawn:HasAuthority() return Authority end
            function pawn:SetActorEnableCollision(on) self.Collision = on end
            function pawn:AddMovementInput(dir, v, force) self.Inputs[#self.Inputs + 1] = { z = dir.Z, v = v } end
            function pawn:ReviveClient() self.Revived = self.Revived + 1 end
            function pawn:IsLocallyControlled() return self.Local ~= false end
            function pawn:K2_GetActorRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
            function pawn:K2_TeleportTo(loc, rot) self.TeleportedTo = loc return true end
            return pawn
        end
        Pawn = MakePawn(500)
        PC.Pawn = Pawn
        Pawn.Controller = PC
        -- a guest's controller as the host sees it
        GuestPawn = MakePawn(700)
        GuestMessages = {}
        GuestPC = { Pawn = GuestPawn, CheatManager = Invalid, CheatClass = CM,
                    PlayerState = { PlayerName = FStr("Friend") } }
        function GuestPC:IsValid() return true end
        function GuestPC:HasAuthority() return true end
        function GuestPC:IsLocalController() return false end
        function GuestPC:GetAddress() return 77 end
        function GuestPC:ClientMessage(text) GuestMessages[#GuestMessages + 1] = text end
        function GuestPC:GetWorld() return World end
        function GuestPC:GetControlRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
        function GuestPC:GetFocalLocation() return { X = 900, Y = 900, Z = 0 } end
        function GuestRequest(text)
            Hooks["/Script/Engine.PlayerController:ServerExecRPC"](Param(GuestPC), Param(FStr(text)))
        end
        function HostReply(text) PC:ClientMessage(text) end
        function LastSentId() return Sent[#Sent]:match("^oar1 (%w+) ") end

        -- UMG: the engine's UI widgets, enough for opengui's window
        function FText(s) assert(type(s) == "string", "FText wants a string"); return { s = s } end
        NAME_None = "None"
        Hovered = nil         -- the widget under the mouse
        -- a struct member read as a live view; members of members appear when first used
        function AutoStruct()
            return setmetatable({}, { __index = function(t, k) local v = AutoStruct(); rawset(t, k, v); return v end })
        end
        UMG = { inputMode = "game", created = 0 }
        UMGClasses = {}
        local nextWidget = 90000
        local function FakeSlot()
            local slot = {}
            function slot:SetSize(v) assert(type(v.Value) == "number" and (v.SizeRule == 0 or v.SizeRule == 1)) end
            function slot:SetPadding(m) assert(m.Left and m.Top and m.Right and m.Bottom); self.Padding = m end
            -- a CanvasPanel's slot: anchors, then place and size (flat structs only)
            function slot:SetMinimum(v) assert(type(v.X) == "number" and type(v.Y) == "number"); self.Min = v end
            function slot:SetMaximum(v) assert(type(v.X) == "number" and type(v.Y) == "number"); self.Max = v end
            function slot:SetOffsets(m) assert(m.Left and m.Top and m.Right and m.Bottom); self.Offsets = m end
            function slot:SetAlignment(v) assert(type(v.X) == "number" and type(v.Y) == "number"); self.Align = v end
            function slot:SetAutoSize(on) assert(type(on) == "boolean"); self.Auto = on end
            function slot:SetVerticalAlignment(a) assert(type(a) == "number") end
            function slot:SetHorizontalAlignment(a) assert(type(a) == "number") end
            return slot
        end
        function FakeWidget(className)
            nextWidget = nextWidget + 8
            local addr = nextWidget
            -- the engine's defaults: a Button is VISIBLE (0), most pieces let the mouse through (4)
            local w = { ClassName = className, Children = {}, Visibility = className == "Button" and 0 or 4, TextValue = "",
                        Font = { Size = 24 }, ColorAndOpacity = { SpecifiedColor = {} }, WidgetStyle = AutoStruct() }
            -- only a VISIBLE widget is ever under the mouse (the engine leaves the rest out)
            function w:IsHovered()
                if Hovered ~= self or self.Visibility ~= 0 then return false end
                local p = self.Parent
                while p do
                    if p.Visibility == 1 then return false end      -- inside something hidden
                    p = p.Parent
                end
                return true
            end
            function w:HasKeyboardFocus() return Focused == self end
            function w:SetBackgroundColor(c) assert(c.R and c.G and c.B and c.A); self.Background = c end
            function w:IsValid() return not self.Dead end
            function w:GetAddress() return addr end
            function w:IsA(cls) return cls.UMGName == self.ClassName end
            function w:SetText(t) assert(type(t) == "table" and t.s, "SetText wants an FText"); self.TextValue = t.s end
            function w:GetText() local v = self.TextValue; return { ToString = function() return v end } end
            function w:SetHintText(t) self.Hint = t.s end
            function w:SetVisibility(v) self.Visibility = v end
            function w:SetBrushColor(c) assert(c.R and c.G and c.B and c.A); self.Brush = c end
            function w:SetPadding(m) assert(m.Left and m.Bottom) end
            local function adopt(self, c)
                self.Children[#self.Children + 1] = c; c.Parent = self
                c.Slot = FakeSlot()
                return c.Slot
            end
            w.SetContent, w.AddChild, w.AddChildToHorizontalBox = adopt, adopt, adopt
            w.AddChildToVerticalBox, w.AddChildToOverlay, w.AddChildToCanvas = adopt, adopt, adopt
            function w:SetRenderTransformAngle(a) assert(type(a) == "number"); self.Angle = a end
            function w:SetRenderTransformPivot(v) assert(type(v.X) == "number" and type(v.Y) == "number"); self.Pivot = v end
            function w:SetContentColorAndOpacity(c) assert(c.R and c.G and c.B and c.A); self.Content = c end
            function w:SetWidthOverride(x) self.Width = x end
            function w:SetHeightOverride(x) self.Height = x end
            function w:ScrollToStart() self.ScrollOffset = 0 end
            function w:SetScrollOffset(y) assert(type(y) == "number"); self.ScrollOffset = y end
            -- the size the engine measured: a code box is 20 per line, anything else 30 tall
            function w:GetDesiredSize()
                if self.ClassName == "MultiLineEditableText" then
                    local _, breaks = self.TextValue:gsub("\n", "")
                    return { X = 600, Y = (breaks + 1) * 20 }
                end
                return { X = 100, Y = 30 }
            end
            function w:SetRenderOpacity(o) assert(type(o) == "number"); self.Opacity = o end
            function w:SetRenderTranslation(v) assert(type(v.X) == "number" and type(v.Y) == "number"); self.Moved = v end
            function w:SetAnimateWheelScrolling(on) self.SmoothScroll = on end
            function w:IsPressed() return self.Pressed == true end
            function w:SetCursor(c) assert(type(c) == "number"); self.Cursor = c end
            return w
        end
        WBL = { IsValid = function() return true end }
        -- the mouse and the screen (1920 x 1080 at DPI scale 1)
        Mouse = { X = 960, Y = 540 }
        WLL = { IsValid = function() return true end }
        function WLL:GetMousePositionOnViewport(world) return { X = Mouse.X, Y = Mouse.Y } end
        function WLL:GetViewportSize(world) return { X = 1920, Y = 1080 } end
        function WLL:GetViewportScale(world) return 1.0 end
        function WBL:Create(world, cls, pc)
            local overlay = cls.Path == "/Game/UI/Cursors/HammerCursor_Pressed.HammerCursor_Pressed_C"   -- the ESP's
            assert((overlay or cls.Path == "/Game/UI/Cursors/HammerCursor.HammerCursor_C") and pc ~= nil)
            local uw = FakeWidget("UserWidget")
            if overlay then
                UMG.overlays = UMG.overlays or {}
                UMG.overlays[#UMG.overlays + 1] = uw
            else
                UMG.created = UMG.created + 1
                UMG.windows = UMG.windows or {}
                UMG.windows[#UMG.windows + 1] = uw
            end
            uw.WidgetTree = { RootWidget = FakeWidget("CanvasPanel"), IsValid = function() return true end }
            uw.InViewport = false
            function uw:AddToViewport(z) self.InViewport = true end
            function uw:IsInViewport() return self.InViewport end
            function uw:RemoveFromParent() self.InViewport = false end
            return uw
        end
        function WBL:SetInputMode_UIOnlyEx(pc, w, lock) assert(w and lock == 0); UMG.inputMode = "ui"; UMG.focus = w end
        function WBL:SetInputMode_GameOnly(pc) UMG.inputMode = "game" end
        function WBL:SetInputMode_GameAndUIEx(pc, w, lock, hide)
            assert(w ~= nil and lock == 0 and hide == false, "no nil object parameter (UE4SS 3.0.1 would shift the rest)")
            UMG.inputMode = "gameandui"; UMG.focusedNothing = not w:IsValid()
        end
        PC.bShowMouseCursor = false
        -- the local player: it always knows the controller it drives now (the free camera has its own)
        PC.Player = { IsValid = function() return true end }
        PC.Player.PlayerController = PC
        PC.PlayerCameraManager = { IsValid = function() return true end,
            GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end,
            GetCameraRotation = function() return { Pitch = 10, Yaw = 20, Roll = 0 } end }
        Log = {}
        Ar = { Log = function(self, msg) Log[#Log + 1] = msg end }
        OwnHandlerNames = {}
        function OwnHandler(name) return OwnHandlerNames[name] end
        function Console(line)
            local params = {}
            for w in line:gmatch("%S+") do params[#params + 1] = w end
            local name = table.remove(params, 1)
            if not Handlers[name] then return false end     -- no handler: UE4SS leaves it to the engine
            return Handlers[name](line, params, Ar)
        end
    ''')
    lua.execute(rf'package.path = [[{scripts}\?.lua;]] .. package.path')
    lua.execute(f'dofile([[{os.path.join(scripts, "main.lua")}]])')
    return lua, os.path.join(tmp, "OARCommands", "binds.txt")


def check(label, cond):
    print(("PASS " if cond else "FAIL ") + label)
    return cond


def values(t):
    return list(t.values())


def main():
    ok = True
    tmp = tempfile.mkdtemp()
    lua, binds = make_runtime(tmp)
    g = lua.globals()

    # --- bind
    # UE4SS 3.0.1 has room for about 45 console-command handlers and new-object watchers per mod;
    # past that it corrupts the game's memory (2026-10-03: 52 handlers crashed the game, 40 did not).
    console = sorted(k for k in g.Registrations.keys() if k.startswith("command "))
    watchers = [k for k in g.Registrations.keys() if k.startswith("class ")]
    ok &= check(f"UE4SS registrations that use up its room stay well under its limit ({len(console)} commands + {len(watchers)} watchers <= 40)",
                len(console) + len(watchers) <= 40 and g.Registrations["consolehook pre"] is None)
    lua.execute('Console("bind x destroytarget")')
    ok &= check("bind reports success", "Bound X to: destroytarget" in values(g.Log))
    ok &= check("X is watched", g.KeyCallbacks["KEY_X"] is not None)
    lua.execute('KeyCallbacks["KEY_X"]()')
    ok &= check("pressing X runs destroytarget", values(g.Calls) == ["destroytarget"])
    lua.execute('KeyDown = false; KeyCallbacks["KEY_X"]()')
    ok &= check("no run while the console has the key", len(g.Calls) == 1)
    lua.execute('KeyDown = true; Console([[bind f1 "god | fly"]])')
    lua.execute('KeyCallbacks["KEY_F1"]()')
    ok &= check("quoted multi-command bind runs each part", values(g.Calls)[-2:] == ["god", "fly"])
    lua.execute('Console("bind 5 summon Duffelbag_C")')
    ok &= check("digit alias maps to FIVE", g.KeyCallbacks["KEY_FIVE"] is not None)
    lua.execute('Console("bind wtfkey god")')
    ok &= check("unknown key is refused", any("Unknown key" in m for m in values(g.Log)))
    saved = open(binds).read()
    ok &= check("binds saved to file", "X=destroytarget" in saved and "F1=god | fly" in saved)
    lua.execute('Console("unbind x"); KeyCallbacks["KEY_X"]()')
    ok &= check("unbind stops X", values(g.Calls)[-1] == "fly")
    lua.execute('Log = {}; Console("bind")')
    ok &= check("bind lists binds", any(m.startswith("F1 = ") for m in values(g.Log)))

    # --- summon
    lua.execute('QueueDelays = true; Console("summon goldbar 3")')
    ok &= check("first gold bar spawns at once", values(g.Summons) == ["Goldbar_C"])
    ok &= check("gold bar class loaded first", values(g.Loads) == ["/Game/BP/Items/Valuables/Goldbar.Goldbar_C"])
    ok &= check("next spawn waits 150 ms", len(g.Delays) == 1 and g.Delays[1][1] == 150)
    lua.execute('RunDelays()')
    ok &= check("summon goldbar 3 spawns exactly 3", values(g.Summons) == ["Goldbar_C"] * 3)
    lua.execute('Summons = {}; Console("summon Duffelbag_C")')
    ok &= check("summon without a count spawns one", values(g.Summons) == ["Duffelbag_C"] and len(g.Delays) == 0)
    lua.execute('Summons = {}; Console("spawn gold 2"); RunDelays()')
    ok &= check("spawn alias + unique prefix 'gold'", values(g.Summons) == ["Goldbar_C", "Goldbar_C"])
    lua.execute('Summons = {}; Log = {}; Console("summon valuable_wine 2")')
    ok &= check("ambiguous name lists matches, spawns nothing",
                len(g.Summons) == 0 and any("matches" in m for m in values(g.Log)))
    lua.execute('Summons = {}; Console("summon goldbar 100"); Console("summonstop"); RunDelays()')
    ok &= check("summonstop cancels a running batch", values(g.Summons) == ["Goldbar_C"])
    lua.execute('Summons = {}; Console("summon goldbar 99999"); RunDelays()')
    ok &= check("count is capped at 500", len(g.Summons) == 500)
    lua.execute('Summons = {}; Console("summon PointLight 2"); RunDelays()')
    ok &= check("engine classes pass straight through", values(g.Summons) == ["PointLight", "PointLight"])

    lua.execute('Summons = {}; PC.CheatManager = Invalid; Console("summon goldbar")')
    ok &= check("missing cheat manager gets created, then summons",
                g.Constructed == 1 and values(g.Summons) == ["Goldbar_C"] and lua.eval("PC.CheatManager == CM"))
    lua.execute('PC.CheatManager = Invalid; Calls = {}; KeyCallbacks["KEY_F1"]()')
    ok &= check("a bind also creates the cheat manager first", g.Constructed == 2 and values(g.Calls) == ["god", "fly"])

    # --- dupe
    gold = "/Game/BP/Items/Valuables/Goldbar.Goldbar_C"
    lua.execute('Summons = {}; Log = {}; LookTarget = GoldActor; Console("dupe 3"); RunDelays()')
    ok &= check("dupe 3 copies the looked-at class by full path", values(g.Summons) == [gold] * 3)
    ok &= check("dupe traces visibility, complex, ignoring your pawn",
                g.TraceArgs.chan == 0 and g.TraceArgs.complex and lua.eval("TraceArgs.ignored == Pawn"))
    ok &= check("dupe message names the class", any("Summoning Goldbar_C x3" in m for m in values(g.Log)))
    lua.execute('Summons = {}; Log = {}; LookTarget = nil; Console("dupe")')
    ok &= check("dupe at nothing says so", len(g.Summons) == 0 and "Not looking at anything" in values(g.Log))
    lua.execute('Summons = {}; Log = {}; LookTarget = WallActor; Console("dupe")')
    ok &= check("dupe refuses plain map pieces", len(g.Summons) == 0 and any("part of the map" in m for m in values(g.Log)))
    lua.execute('Summons = {}; Calls = {}; LookTarget = GoldActor; Console("bind c dupe"); KeyCallbacks["KEY_C"]()')
    ok &= check("bind c dupe calls dupe directly", values(g.Summons) == [gold] and len(g.Calls) == 0)
    lua.execute('Summons = {}; Calls = {}; Console([[bind f2 "god | dupe 2"]]); KeyCallbacks["KEY_F2"](); RunDelays()')
    ok &= check("mixed bind: console part + own command", values(g.Calls) == ["god"] and values(g.Summons) == [gold] * 2)
    lua.execute('Console("unbind c"); Console("unbind f2")')

    # --- debug camera (hosted game: the engine gives its controller no cheat manager)
    hook = g.NewObjectHooks["/Script/Engine.DebugCameraController"]
    ok &= check("mod watches for debug camera controllers", hook is not None)
    if hook is not None:
        lua.execute('Constructed = 0; NewObjectHooks["/Script/Engine.DebugCameraController"](DCC)')
        ok &= check("a new debug camera gets a cheat manager, so ToggleDebugCamera can exit",
                    g.Constructed == 1 and lua.eval("DCC.CheatManager == CM"))
    # In the debug camera the local player drives DCC; the normal controller is frozen and gets no keys.
    lua.execute('LP = { PlayerController = DCC, IsValid = function() return true end }')
    lua.execute('KeyDown = false; Calls = {}; CallPCs = {}; Console("bind g toggledebugcamera"); KeyCallbacks["KEY_G"]()')
    ok &= check("in the debug camera a bind runs on the debug camera's controller",
                values(g.Calls) == ["toggledebugcamera"] and lua.eval("CallPCs[1] == DCC"))
    lua.execute('KeyDown = true; LP.PlayerController = PC; Calls = {}; CallPCs = {}; KeyCallbacks["KEY_G"]()')
    ok &= check("after leaving it, binds run on the normal controller again",
                values(g.Calls) == ["toggledebugcamera"] and lua.eval("CallPCs[1] == PC"))
    lua.execute('LP = nil; Console("unbind g")')

    # --- value commands
    changes = os.path.join(tmp, "OAR", "Saved", "SaveGames", "OARCommands-changes.log")
    def change_log():
        return open(changes, encoding="utf-8").read() if os.path.exists(changes) else ""
    u = lua.eval('(require("unlockables"))')
    skills, gear = list(u.Skills.values()), list(u.Gear.values())
    ok &= check("unlockables: 17 skills, all with 3 tiers", len(skills) == 17 and all(s.tiers == 3 for s in skills))
    ok &= check("unlockables: cash gear only, no emotes, masks, outfits or maps",
                len(gear) > 200 and not any(k in x.path for x in gear for k in ("Emote", "Mask", "Outfit", "_Map_")))

    lua.execute('ResetProgress(); Console("setmoney 5000")')
    ok &= check("setmoney sets cash", g.PC.Cash == 5000)
    ok &= check("setmoney saves with the game's SaveCash, then reloads", values(g.GameCalls) == ["SaveCash", "LoadCash"])
    ok &= check("the old value goes in the change log first", "setmoney: cash 100 -> 5000" in change_log())
    lua.execute('ResetProgress(); Console("setmoney lots")')
    ok &= check("setmoney with no number changes nothing", g.PC.Cash == 100 and len(g.GameCalls) == 0
                and any("Usage" in m for m in values(g.Log)))
    lua.execute('ResetProgress(); Console("setmoney 99999999999")')
    ok &= check("cash is capped at 2,000,000,000", g.PC.Cash == 2000000000 and any("capped" in m for m in values(g.Log)))
    lua.execute('ResetProgress(); Console("addmoney 250")')
    ok &= check("addmoney adds", g.PC.Cash == 350 and values(g.GameCalls) == ["SaveCash", "LoadCash"])
    lua.execute('ResetProgress(); Console("addmoney -999999")')
    ok &= check("addmoney never goes below 0", g.PC.Cash == 0)

    lua.execute('ResetProgress(); Console("setlevel 50")')
    ok &= check("setlevel sets the level and starts it at 0 XP", g.PC.Level == 50 and g.PC.EXP == 0)
    ok &= check("setlevel saves with SaveLevel, then reloads", values(g.GameCalls) == ["SaveLevel", "LoadLevel"])
    ok &= check("setlevel logs the old level and XP", "setlevel: level 3 -> 50, xp 12.5 -> 0" in change_log())
    lua.execute('ResetProgress(); Console("setlevel 0")')
    ok &= check("setlevel refuses levels below 1", g.PC.Level == 3 and len(g.GameCalls) == 0)
    lua.execute('ResetProgress(); Console("setxp 99.5")')
    ok &= check("setxp sets XP and saves", g.PC.EXP == 99.5 and values(g.GameCalls) == ["SaveLevel", "LoadLevel"])
    # level 3 needs (3 / 0.005) ^ 0.8 = 166.9 XP; more would make the game's AddEXP recurse level by level
    lua.execute('ResetProgress(); Console("setxp 500")')
    ok &= check("setxp refuses XP at or above the level-up amount",
                g.PC.EXP == 12.5 and len(g.GameCalls) == 0 and any("levels up at 167 XP" in m for m in values(g.Log)))

    # setxp all: every player in the heist gains XP through the escape van's own AddPlayerEXP
    lua.execute('''
        Button = nil
        XPCalls, Flushes = {}, 0
        function MakeButton()
            local b = {}
            function b:IsValid() return true end
            function b:FlushNetDormancy() Flushes = Flushes + 1 end
            -- a reliable multicast: on the host it also runs at once, and the game's AddEXP adds to
            -- the character's GainedEXP (credited on the win screen)
            function b:AddPlayerEXP(c, amount)
                XPCalls[#XPCalls + 1] = { who = c:GetAddress(), amount = amount }
                c.GainedEXP = (c.GainedEXP or 0) + amount
            end
            return b
        end
        Pawn.GainedEXP, GuestPawn.GainedEXP = 0, 0
        Pawn.PlayerState = { PlayerName = FStr("Host") }
        GuestPawn.PlayerState = { PlayerName = FStr("Friend") }
        Characters = { Pawn, GuestPawn }
        function XPGiven()
            local t = {}
            for _, c in ipairs(XPCalls) do t[#t + 1] = c.who .. "=" .. c.amount end
            return table.concat(t, " ")
        end
    ''')
    lua.execute('ResetProgress(); Console("setxp all 500")')
    ok &= check("setxp all outside a heist (no escape van) gives nothing and says why",
                g.XPGiven() == "" and any("heist" in m for m in values(g.Log)) and len(g.GameCalls) == 0)
    lua.execute('Button = MakeButton(); Authority = false; ResetProgress(); Console("setxp all 500"); Authority = true')
    ok &= check("setxp all as a guest gives nothing: only the host can",
                g.XPGiven() == "" and any("host" in m for m in values(g.Log)))
    lua.execute('ResetProgress(); Console("setxp all 50000")')
    ok &= check("setxp all: every player in the heist, you included, gains that much through the van's AddPlayerEXP",
                g.XPGiven() == "500=50000 700=50000" and g.Flushes >= 1 and g.PC.EXP == 12.5
                and any("2 players" in m for m in values(g.Log)) and len(g.GameCalls) == 0)
    ok &= check("setxp all is written to the change log with the names", "setxp all: Host +50000, Friend +50000" in change_log())
    lua.execute('XPCalls = {}; ResetProgress(); Console("setxp all 80000")')
    ok &= check("setxp all stops at 100,000 extra XP per player per heist",
                g.XPGiven() == "500=50000 700=50000" and g.Pawn.GainedEXP == 100000)
    lua.execute('XPCalls = {}; ResetProgress(); Console("setxp all 10")')
    ok &= check("setxp all at the cap gives nothing more and says so",
                g.XPGiven() == "" and any("100000" in m.replace(",", "") for m in values(g.Log)))
    lua.execute('XPCalls = {}; ResetProgress(); Console("setxp all"); Console("setxp all lots"); Console("setxp all 0")')
    ok &= check("setxp all without a positive amount shows the usage", g.XPGiven() == ""
                and sum("Usage: setxp" in m for m in values(g.Log)) == 3)
    lua.execute('Button = nil; Characters = nil; Pawn.PlayerState = nil')

    # maxskills: one skill already owned at a broken tier, one in research, the other 16 not owned
    lua.execute('''
        ResetProgress()
        OutOfBounds = 0
        local U = require("unlockables")
        local F = U.SkillFields
        local first = U.Skills[1].path
        Loaded = { [first] = true }
        PC.UnlockedSkills = MakeArray({ { [F.skill] = FakeClass(first), [F.tier] = 72 } })
        PC.ResearchingSkills = MakeArray({ NewResearch() }, NewResearch)
        Loads = {}
        Console("maxskills")
    ''')
    ok &= check("maxskills: every skill owned once, at its top tier, including ones you never bought",
                lua.eval('''(function()
        local U, F = require("unlockables"), require("unlockables").SkillFields
        local arr = PC.UnlockedSkills.Data
        if #arr ~= #U.Skills then return false end
        local seen = {}
        for _, e in ipairs(arr) do
            if e[F.tier] ~= 3 or seen[e[F.skill].Path] then return false end
            seen[e[F.skill].Path] = true
        end
        for _, s in ipairs(U.Skills) do if not seen[s.path] then return false end end
        return true
    end)()'''))
    ok &= check("maxskills never touches memory past the end of an array", g.OutOfBounds == 0)
    ok &= check("maxskills adds skills through the game's ProgressSkills, then saves",
                values(g.GameCalls) == ["ProgressSkills"] * 16 + ["SaveLevel", "LoadLevel"])
    ok &= check("maxskills clears the research queue", lua.eval("#PC.ResearchingSkills.Data") == 0)
    ok &= check("maxskills loads the skills it did not have", len(g.Loads) == 16)
    ok &= check("maxskills logs what it changed", "tier 72 -> 3" in change_log() and "added 16 skills" in change_log())

    # unlockall: one gear item and a coin emote already owned
    lua.execute('''
        ResetProgress()
        OutOfBounds = 0
        local U = require("unlockables")
        local emote = "/Game/Maps/Menu/BP/Shop/Appearance/Emotes/ShopItem_Emote_Wave.ShopItem_Emote_Wave_C"
        Loaded = { [U.Gear[1].path] = true, [emote] = true }
        PC.ItemInventory = MakeArray({ FakeClass(U.Gear[1].path), FakeClass(emote) })
        Loads = {}
        Console("unlockall")
    ''')
    ok &= check("unlockall: every cash item once, owned items kept", lua.eval('''(function()
        local U = require("unlockables")
        local arr = PC.ItemInventory.Data
        if #arr ~= #U.Gear + 1 then return false end
        local count = {}
        for _, c in ipairs(arr) do count[c.Path] = (count[c.Path] or 0) + 1 end
        for _, s in ipairs(U.Gear) do if count[s.path] ~= 1 then return false end end
        return count["/Game/Maps/Menu/BP/Shop/Appearance/Emotes/ShopItem_Emote_Wave.ShopItem_Emote_Wave_C"] == 1
    end)()'''))
    ok &= check("unlockall never touches memory past the end of an array", g.OutOfBounds == 0)
    ok &= check("unlockall adds each item with the game's AddInventoryItem (which saves)",
                values(g.GameCalls) == ["AddInventoryItem", "SaveInventoryItems"] * (len(gear) - 1))
    ok &= check("unlockall logs what it added", f"unlockall: added {len(gear) - 1} items" in change_log())

    lua.execute('ResetProgress(); LP = { PlayerController = DCC, IsValid = function() return true end }; Console("setmoney 777")')
    ok &= check("in the debug camera the edit goes to your real controller", g.PC.Cash == 777)
    lua.execute('LP = nil; ResetProgress(); Console("bind f6 addmoney 1000"); KeyCallbacks["KEY_F6"]()')
    ok &= check("value commands work from a bind", g.PC.Cash == 1100)
    lua.execute('Console("unbind f6")')

    # --- revive and noclip (solo / host)
    lua.execute('Pawn["Downed?"] = true; Pawn.Health = 0; Log = {}; Console("revive")')
    ok &= check("revive: full health, not downed, the game's ReviveClient ran",
                g.Pawn.Health == 100 and g.Pawn["Downed?"] is False and g.Pawn.Revived == 1
                and "revived" in values(g.Log))
    lua.execute('Log = {}; Console("noclip")')
    ok &= check("noclip on: no collision, flying, stops when keys are let go, walk speed",
                g.Pawn.Collision is False and g.Pawn.CharacterMovement.Mode == 5
                and g.Pawn.CharacterMovement.bCheatFlying is True and g.Pawn.CharacterMovement.MaxFlySpeed == 600)
    frame = "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:InpAxisEvt_MoveForward_K2Node_InputAxisEvent_0"
    ok &= check("noclip hooks the character's per-frame MoveForward event", g.Hooks[frame] is not None)
    lua.execute('KeyDown = false')        # only the keys listed in KeysDown are held
    lua.execute(f'KeysDown = {{ SpaceBar = true }}; Hooks["{frame}"](Param(Pawn))')
    lua.execute(f'KeysDown = {{ LeftControl = true }}; Hooks["{frame}"](Param(Pawn))')
    lua.execute(f'ObjectSearches = 0; KeysDown = {{ SpaceBar = true }}; Hooks["{frame}"](Param(Pawn)); SearchesInFrame = ObjectSearches; Pawn.Inputs[#Pawn.Inputs] = nil')
    ok &= check("noclip's per-frame code reads the keys from the character's own controller and never searches all objects",
                g.SearchesInFrame == 0)
    ok &= check("Space adds up input, Ctrl adds down input",
                lua.eval("Pawn.Inputs[1].z == 1 and Pawn.Inputs[1].v == 1 and Pawn.Inputs[2].v == -1"))
    lua.execute(f'KeysDown = {{ LeftShift = true }}; Hooks["{frame}"](Param(Pawn))')
    ok &= check("Shift doubles the fly speed", g.Pawn.CharacterMovement.MaxFlySpeed == 1200)
    lua.execute(f'KeysDown = {{}}; Hooks["{frame}"](Param(Pawn))')
    ok &= check("letting go of Shift goes back to normal speed", g.Pawn.CharacterMovement.MaxFlySpeed == 600)
    lua.execute(f"""
        Pawn.CharacterMovement.Mode = 1; Pawn.CharacterMovement.MovementMode = 1     -- the game ended the flight
        Hooks["{frame}"](Param(Pawn))
        KeysDown = {{}}; KeyDown = true
    """)
    ok &= check("when the game ends the flight, noclip forgets it (Shift changes nothing any more)",
                lua.eval("OARCommands.State.noclip[500] == nil"))
    lua.execute('Pawn.CharacterMovement.MaxWalkSpeed = 450; Console("noclip")')
    ok &= check("noclip again flies at today's walking speed", g.Pawn.CharacterMovement.MaxFlySpeed == 450)
    lua.execute('Console("noclip"); Pawn.CharacterMovement.MaxWalkSpeed = 600; Console("noclip")')
    lua.execute('KeysDown = { LeftShift = true }; Console("noclip"); KeysDown = {}; KeyDown = true')
    ok &= check("noclip off: collision back, falling, fly speed restored",
                g.Pawn.Collision is True and g.Pawn.CharacterMovement.Mode == 3
                and g.Pawn.CharacterMovement.bCheatFlying is False and g.Pawn.CharacterMovement.MaxFlySpeed == 600)

    # --- revive timing (host): a revive finishes when the reviver's bar does
    started, timer = "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:StartRevive", "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:RevivePlayer"
    restart = "/Script/Engine.PlayerController:ClientRestart"
    ok &= check("revive timing: no hook while the character's Blueprint is not loaded",
                g.Hooks[started] is None and g.Hooks[restart] is not None)
    lua.execute(f'MissingHooks = {{}}; Hooks["{restart}"](Param(PC)); Hooks["{restart}"](Param(PC))')
    ok &= check("revive timing: hooked once a controller gets its character (ClientRestart)",
                g.Hooks[started] is not None and g.Hooks[timer] is not None
                and g.Registrations["hook " + started] == 1)
    ok &= check("the truck and gun hooks are not placed at startup or on ClientRestart, only when first used",
                g.Hooks["/Game/BP/Player/RobberTruck.RobberTruck_C:CheckAllMoney"] is None and g.Hooks["/Game/BP/Player/RobberTruck.RobberTruck_C:CountMoney"] is None
                and g.Hooks["/Game/BP/Player/RobberTruck.RobberTruck_C:RemoveMoney"] is None and g.Hooks["/Game/BP/Guns/GunBase.GunBase_C:ShootClient"] is None)
    lua.execute(f'''
        Downed = MakePawn(800); Downed["Downed?"] = true; Downed.ReviveTime = 5.0
        Pawn.ReviveTime = 3.0; Downed["Assisting Player"] = Pawn
        Other = MakePawn(900); Other["Downed?"] = true; Other.ReviveTime = 5.0; Other["Assisting Player"] = GuestPawn
        GuestPawn.ReviveTime = 5.0
        Characters = {{ Pawn, Downed, Other, GuestPawn }}
        -- the game on the host: RevivePlayer on the downed character sets "Assisting Player", runs the
        -- reviver's StartRevive (the bar), starts its timer with its own ReviveTime, and ends
        function GameRevive(downed, reviver)
            downed["Assisting Player"] = reviver
            Hooks["{started}"](Param(reviver))
            TimerTime = downed.ReviveTime
            Hooks["{timer}"](Param(downed), Param(reviver))
        end
    ''')
    lua.execute('Authority = true; GameRevive(Downed, Pawn)')
    ok &= check("host: a reviver with Healing Touch (3 s) gets a 3 s revive, the downed player's own time comes back",
                g.TimerTime == 3.0 and g.Downed.ReviveTime == 5.0)
    ok &= check("host: a downed player someone else is helping keeps their time", g.Other.ReviveTime == 5.0)
    lua.execute('Pawn.ReviveTime = 5.0; Downed.ReviveTime = 3.0; GameRevive(Downed, Pawn)')
    ok &= check("host: a revive is never made slower than the game makes it",
                g.TimerTime == 3.0 and g.Downed.ReviveTime == 3.0)
    lua.execute('Pawn.ReviveTime = 3.0; Downed.ReviveTime = 5.0; Authority = false; GameRevive(Downed, Pawn); Authority = true')
    ok &= check("guest: the host decides, nothing is changed", g.TimerTime == 5.0 and g.Downed.ReviveTime == 5.0)

    # --- truckmoney: the getaway truck's take (host, during a heist)
    recount, counted, removed = "/Game/BP/Player/RobberTruck.RobberTruck_C:CheckAllMoney", "/Game/BP/Player/RobberTruck.RobberTruck_C:CountMoney", "/Game/BP/Player/RobberTruck.RobberTruck_C:RemoveMoney"
    lua.execute('''
        Truck = nil
        function MakeTruck(address)
            local t = { TotalTake = 0, MinimumTake = 20000, Flushes = 0 }
            function t:IsValid() return true end
            function t:GetAddress() return address end
            function t:HasAuthority() return Authority end
            function t:FlushNetDormancy() self.Flushes = self.Flushes + 1 end
            function t:GetWorld() return { GetAddress = function() return WorldId end } end
            function t:GetGameTimeSinceCreation() return TruckAge end
            return t
        end
        WorldId = 1           -- a new map is a new world
        TruckAge = 100        -- seconds since the truck was created
        -- the game: loot going in or out changes TotalTake, then its server event ends (hook)
        local function Ran(name) local h = Hooks["/Game/BP/Player/RobberTruck.RobberTruck_C:" .. name]; if h then h(Param(Truck)) end end
        function LootIn(value) Truck.TotalTake = Truck.TotalTake + value; Ran("CountMoney") end
        function LootOut(value) Truck.TotalTake = Truck.TotalTake - value; Ran("RemoveMoney") end
        -- the escape button: the truck counts its take again from the loot inside
        function Recount(loot) Truck.TotalTake = loot; Ran("CheckAllMoney") end
    ''')
    lua.execute('Log = {}; Console("truckmoney set 5000")')
    ok &= check("truckmoney outside a heist (no truck) says why", any("heist" in m for m in values(g.Log)))
    lua.execute('Truck = MakeTruck(4000); Authority = false; Log = {}; Console("truckmoney set 5000"); Console("truckmoney")')
    ok &= check("truckmoney as a guest only shows the money, only the host changes it",
                g.Truck.TotalTake == 0 and any("host" in m for m in values(g.Log))
                and any("Truck money: 0" in m for m in values(g.Log)))
    ok &= check("truckmoney outside a heist or as a guest places no hooks", g.Hooks["/Game/BP/Player/RobberTruck.RobberTruck_C:CheckAllMoney"] is None)
    lua.execute('Authority = true; Dirty = {}; Log = {}; LootIn(3000); Console("truckmoney set 500000")')
    ok &= check("the truck hooks are placed the first time truckmoney changes the take, once each",
                g.Hooks["/Game/BP/Player/RobberTruck.RobberTruck_C:CheckAllMoney"] is not None and g.Registrations["hook /Game/BP/Player/RobberTruck.RobberTruck_C:CountMoney"] == 1)
    ok &= check("truckmoney set: the truck holds exactly that, changed the game's way (flush, set, mark for sending)",
                g.Truck.TotalTake == 500000 and g.Truck.Flushes >= 1 and "4000:TotalTake" in values(g.Dirty))
    lua.execute('LootIn(2000)')
    ok &= check("loot put in afterwards adds to it", g.Truck.TotalTake == 502000)
    lua.execute('Log = {}; Console("truckmoney")')
    ok &= check("truckmoney shows the money, the loot and the change",
                any("502000" in m and "5000" in m and "497000" in m for m in values(g.Log)))
    lua.execute('Recount(5000)')
    ok &= check("the escape button's recount from the loot keeps the change", g.Truck.TotalTake == 502000)
    lua.execute('Console("truckmoney add 1000")')
    ok &= check("truckmoney add adds", g.Truck.TotalTake == 503000)
    lua.execute('Console("truckmoney add -999999999")')
    ok &= check("truckmoney add with a big negative amount stops at 0", g.Truck.TotalTake == 0)
    lua.execute('Console("truckmoney set 10000"); Console("truckmoney reset")')
    ok &= check("truckmoney reset: back to 0", g.Truck.TotalTake == 0)
    lua.execute('LootOut(5000)')
    ok &= check("loot taken out after a reset does not go below 0", g.Truck.TotalTake == 0)
    lua.execute('Recount(0)')
    ok &= check("and the recount after that stays at 0", g.Truck.TotalTake == 0)
    lua.execute('Log = {}; Console("truckmoney set 999999999")')
    ok &= check("truckmoney stops at 100,000,000 so no one's cash overflows",
                g.Truck.TotalTake == 100000000 and any("100000000" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("truckmoney set lots"); Console("truckmoney fly 5"); Console("truckmoney add")')
    ok &= check("truckmoney with a wrong word or no amount shows the usage",
                sum("Usage: truckmoney" in m for m in values(g.Log)) == 3 and g.Truck.TotalTake == 100000000)
    lua.execute('Console("truckmoney set 7000"); WorldId = 2; Truck = MakeTruck(4000); Recount(3000); WorldId = 1')
    ok &= check("a new map forgets the change, even for a truck at the same address", g.Truck.TotalTake == 3000)
    lua.execute('Truck = MakeTruck(4300); Console("truckmoney set 9000"); Recount(0)')
    ok &= check("the escape recount puts the change back once", g.Truck.TotalTake == 9000)
    lua.execute('Recount(0)')
    ok &= check("a second recount (the escape pressed twice) keeps the change too", g.Truck.TotalTake == 9000)
    lua.execute('TruckAge = 500; Console("truckmoney set 7000"); TruckAge = 20; Truck = MakeTruck(4300); Recount(3000); TruckAge = 100')
    ok &= check("a heist that ended without escaping does not hand its change to the next one, even at the same addresses",
                g.Truck.TotalTake == 3000)
    lua.execute('Truck = MakeTruck(4100); Truck.TotalTake = -50; Hooks["/Game/BP/Player/RobberTruck.RobberTruck_C:RemoveMoney"](Param(Truck))')
    ok &= check("a truck truckmoney never touched is left exactly as the game has it", g.Truck.TotalTake == -50)
    lua.execute('Truck = nil')

    # --- setammo: your own guns (ammo is counted on your own game)
    lua.execute('''
        Gun = { BulletsLeft = 3, MagSize = 30, IsValid = function() return true end }
        Pawn.ReserveAmmo = MakeArray({ 12, 40 })
        Pawn.HoldingGun = Gun
    ''')
    lua.execute('Log = {}; Console("setammo 999")')
    ok &= check("setammo: every gun's spare ammo, and a full magazine in your hand",
                lua.eval("Pawn.ReserveAmmo.Data[1] == 999 and Pawn.ReserveAmmo.Data[2] == 999 and #Pawn.ReserveAmmo.Data == 2")
                and g.Gun.BulletsLeft == 30 and lua.eval("OutOfBounds") == 0)
    lua.execute('Console("setammo 5000000")')
    ok &= check("setammo stops at 999,999", lua.eval("Pawn.ReserveAmmo.Data[1] == 999999"))
    lua.execute('Gun.BulletsLeft = 45; Console("setammo 10")')
    ok &= check("setammo never takes bullets out of a magazine", g.Gun.BulletsLeft == 45)
    lua.execute('Pawn.HoldingGun = Invalid; Log = {}; Console("setammo 20")')
    ok &= check("setammo with no gun in your hand still sets the spare ammo",
                lua.eval("Pawn.ReserveAmmo.Data[2] == 20") and len(g.Log) == 1)
    lua.execute('Log = {}; Console("setammo"); Console("setammo -5"); Console("setammo lots")')
    ok &= check("setammo without a valid amount shows the usage",
                sum("Usage: setammo" in m for m in values(g.Log)) == 3 and lua.eval("Pawn.ReserveAmmo.Data[2] == 20"))
    lua.execute('Pawn.ReserveAmmo = nil; Pawn.HoldingGun = nil; Log = {}; Console("setammo 5")')
    ok &= check("setammo without a character that has guns says so", any("gun" in m for m in values(g.Log)))


    # --- heist commands for the host: reviveall, healall, godall, alarm, cops, cameras, codes,
    #     bringloot, escape; and infiniteammo
    lua.execute("""
        function Thing(address, fields)
            local t = fields or {}
            function t:IsValid() return true end
            function t:GetAddress() return address end
            function t:FlushNetDormancy() end
            return t
        end
        Host = MakePawn(510); Host.PlayerState = { PlayerName = FStr("Host") }
        Friend = MakePawn(710); Friend.PlayerState = { PlayerName = FStr("Friend") }; Friend.Local = false
        Characters = { Host, Friend }
        Authority = true
    """)
    lua.execute('Log = {}; FindObjectsCalls = {}; Console("reviveall")')
    ok &= check("player lookups include subclasses (PlayerCharacter_Rain) and leave class defaults out",
                lua.eval("FindObjectsCalls[1].class == 'PlayerCharacter_C' and FindObjectsCalls[1].exact == false "
                         "and FindObjectsCalls[1].banned == 48"))
    ok &= check("reviveall with nobody downed says so", any("Nobody is downed" in m for m in values(g.Log)))
    lua.execute('Friend["Downed?"] = true; Friend.Health = 0; Dirty = {}; Log = {}; Console("reviveall")')
    ok &= check("reviveall: the downed player is revived the game's way, and the change is marked for sending",
                g.Friend["Downed?"] is False and g.Friend.Health == 100 and g.Friend.Revived == 1
                and "710:Downed?" in values(g.Dirty) and "710:Health" in values(g.Dirty)
                and any("Revived: Friend" in m for m in values(g.Log)) and g.Host.Revived == 0)
    lua.execute('Authority = false; Friend["Downed?"] = true; Log = {}; Console("reviveall"); Authority = true')
    ok &= check("reviveall as a guest asks the host (nothing changes on the guest's own game)",
                g.Friend["Downed?"] is True and any("Asked the host to revive everyone" in m for m in values(g.Log))
                and g.Sent[len(g.Sent)].endswith(" reviveall"))
    lua.execute('Friend["Downed?"] = false')

    lua.execute("""
        HostArmor = Thing(520, { ArmorHealth = 3, ArmorMaxHealth = 50 })
        Host.ArmorChildActor = { ChildActor = HostArmor }
        Host.Health, Friend.Health = 10, 20
        Dirty = {}; Log = {}
    """)
    lua.execute('Console("healall")')
    ok &= check("healall: full health for everyone and full armor where worn",
                g.Host.Health == 100 and g.Friend.Health == 100 and g.HostArmor.ArmorHealth == 50
                and "520:ArmorHealth" in values(g.Dirty))

    lua.execute('Log = {}; Console("godall")')
    ok &= check("godall: everyone gets the game's damage immunity",
                g.Host.DamageImmunity == 1 and g.Friend.DamageImmunity == 1 and "710:DamageImmunity" in values(g.Dirty))
    lua.execute('Console("godall")')
    ok &= check("godall again turns it off", g.Host.DamageImmunity == 0 and g.Friend.DamageImmunity == 0)
    lua.execute('Console("godall off")')
    ok &= check("godall off stays off", g.Friend.DamageImmunity == 0)
    lua.execute('OARCommands.State.godAll = true; Host.DamageImmunity, Friend.DamageImmunity = 0, 0; Log = {}; Console("godall")')
    ok &= check("godall in a new heist (everyone back at 0) turns it on, whatever it was before",
                g.Friend.DamageImmunity == 1 and any("Nobody takes damage" in m for m in values(g.Log)))
    lua.execute('Console("godall off")')

    lua.execute("""
        Alarm = Thing(600, { ["AlarmEnabled?"] = true, ["HasAlarmTriggered?"] = false, Calls = {} })
        function Alarm:DeactivateAlarm() self.Calls[#self.Calls + 1] = "deactivate"; self["AlarmEnabled?"] = false end
        function Alarm:TriggerAlarmInterface() self.Calls[#self.Calls + 1] = "trigger"; self["HasAlarmTriggered?"] = true end
        -- the alarm box: a lever (BP_PowerSwitch) whose AffectedActors holds the alarm
        function Lever(address, affected)
            local l = Thing(address, { ["Switched?"] = false, AffectedActors = MakeArray(affected),
                                       SpottedHighlightcomponent = { ["CanHighlight?"] = false }, Clicks = {} })
            function l:K2_GetRootComponent() return { IsValid = function() return true end } end
            -- clicking it: if not switched yet, the server half tells every affected actor it was hacked
            l["BndEvt__PowerSwitch_InteractComponent_K2Node_ComponentBoundEvent_2_Interact__DelegateSignature"] = function(self, player, hit)
                self.Clicks[#self.Clicks + 1] = player:GetAddress()
                if not self["Switched?"] then
                    for _, a in ipairs(self.AffectedActors.Data) do if a.DeactivateAlarm then a:DeactivateAlarm() end end
                    self["Switched?"] = true
                end
            end
            return l
        end
        AlarmLever = Lever(605, { Alarm })
        LaserLever = Lever(606, { Thing(607) })
        Log = {}
    """)
    lua.execute('Console("alarm off")')
    ok &= check("alarm outside a heist says so", any("no alarm" in m for m in values(g.Log)))
    lua.execute('Objects.AlarmBP_C = { Alarm }; Objects.BP_PowerSwitch_C = { LaserLever, AlarmLever }; Log = {}; Console("alarm")')
    ok &= check("alarm shows ON while it is armed", any("Alarm is ON" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("alarm off")')
    ok &= check("alarm off pulls the alarm box's lever exactly as a click does, and only that lever",
                lua.eval("#AlarmLever.Clicks == 1 and AlarmLever.Clicks[1] == PC.Pawn:GetAddress() and #LaserLever.Clicks == 0")
                and g.AlarmLever["Switched?"] is True and g.Alarm["AlarmEnabled?"] is False
                and any("Alarm is OFF" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("alarm")')
    ok &= check("alarm then shows OFF", any("Alarm is OFF" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("alarm off")')
    ok &= check("alarm off twice says it is already off", any("already OFF" in m for m in values(g.Log)) and lua.eval("#AlarmLever.Clicks == 1"))
    lua.execute('Dirty = {}; Log = {}; Console("alarm on")')
    ok &= check("alarm on switches it back on, and the lever can be used again",
                g.Alarm["AlarmEnabled?"] is True and g.AlarmLever["Switched?"] is False
                and "600:AlarmEnabled?" in values(g.Dirty) and "605:Switched?" in values(g.Dirty)
                and any("Alarm is ON" in m for m in values(g.Log)))
    lua.execute('Objects.BP_PowerSwitch_C = {}; Log = {}; Console("alarm off")')
    ok &= check("alarm off without a lever (the tutorial) uses the alarm's own hacked event",
                lua.eval("Alarm.Calls[#Alarm.Calls] == 'deactivate'") and g.Alarm["AlarmEnabled?"] is False)
    lua.execute('Log = {}; Console("alarm trigger")')
    ok &= check("alarm trigger makes it go off (the heist goes loud)",
                lua.eval("Alarm.Calls[#Alarm.Calls] == 'trigger'") and any("loud" in m for m in values(g.Log)))
    lua.execute('Console("alarm on"); Log = {}; Console("alarm off")')
    ok &= check("alarm off after it went off warns that the police keep coming", any("keep coming" in m for m in values(g.Log)))
    lua.execute('n = #Alarm.Calls; Authority = false; Log = {}; Console("alarm trigger"); Console("alarm on"); Authority = true')
    ok &= check("alarm changes as a guest need the host", any("host" in m for m in values(g.Log)) and lua.eval("#Alarm.Calls == n"))
    lua.execute('Log = {}; Console("alarm loud please")')
    ok &= check("alarm with a wrong word shows the usage", any("Usage: alarm" in m for m in values(g.Log)))
    lua.execute("""
        Spawner = Thing(610, { WaveNumber = 2, Calls = {} })
        function Spawner:ForceNewWave() self.Calls[#self.Calls + 1] = "wave" end
        function Spawner:SpecialsWave() self.Calls[#self.Calls + 1] = "specials" end
        Destroyed = {}
        function Cop(address) local c = Thing(address); function c:K2_DestroyActor() Destroyed[#Destroyed + 1] = address end; return c end
        Objects.PoliceWaveSpawner_C = { Spawner }
        Objects.NPC_Police_base_C = { Cop(620), Cop(621), Cop(622) }
        Log = {}
    """)
    lua.execute('Console("cops")')
    ok &= check("cops shows the police count and the wave", any("Police here: 3" in m and "wave 2" in m for m in values(g.Log)))
    lua.execute('Console("cops wave"); Console("cops specials"); Console("cops clear")')
    ok &= check("cops wave / specials use the spawner's own events, clear removes every police officer",
                lua.eval("Spawner.Calls[1] == 'wave' and Spawner.Calls[2] == 'specials' and #Destroyed == 3"))
    lua.execute('Log = {}; Console("cops fly")')
    ok &= check("cops with a wrong word shows the usage", any("Usage: cops" in m for m in values(g.Log)))

    lua.execute("""
        Broken, Removed, CamCalls = {}, {}, {}
        function Cam(address, destroyed, possessed)
            local c = Thing(address, { ["Destroyed?"] = destroyed, ["Possessed?"] = possessed or false })
            function c:DestroyCamera() Broken[#Broken + 1] = address end
            function c:K2_DestroyActor() Removed[#Removed + 1] = address end
            function c:RemoveCameraUI() CamCalls[#CamCalls + 1] = address .. ":ui" end
            function c:PossessPlayer() CamCalls[#CamCalls + 1] = address .. ":back" end
            return c
        end
        Objects.CameraBP_C = { Cam(630, false), Cam(631, true), Cam(632, false) }
        Log = {}
    """)
    lua.execute('Console("cameras")')
    ok &= check("cameras shows working and destroyed", any("2 working, 1 destroyed" in m for m in values(g.Log)))
    lua.execute('Console("cameras destroy")')
    ok &= check("cameras destroy breaks the working ones the game's way (as shooting them)",
                lua.eval("#Broken == 2 and Broken[1] == 630 and Broken[2] == 632 and #Removed == 0"))
    lua.execute('Log = {}; Console("cameras off")')
    ok &= check("cameras off removes every camera, broken ones too, without breaking any (as destroytarget)",
                lua.eval("#Removed == 3 and #Broken == 2") and any("Removed 3" in m for m in values(g.Log)))
    lua.execute("""
        Removed, CamCalls = {}, {}
        Objects.CameraBP_C = { Cam(633, false, true), Cam(634, false) }
        QueueDelays = true; Log = {}
    """)
    lua.execute('Console("cameras off")')
    ok &= check("a camera someone is watching: their camera view is closed first, the camera removed after",
                lua.eval("CamCalls[1] == '633:ui' and #Removed == 1 and Removed[1] == 634"))
    lua.execute('RunDelays(); QueueDelays = false')
    ok &= check("then they are back in their character and that camera is removed too",
                lua.eval("CamCalls[2] == '633:back' and #Removed == 2 and Removed[2] == 633"))
    lua.execute('Authority = false; Removed = {}; Console("cameras off"); Authority = true')
    ok &= check("cameras off as a guest needs the host", lua.eval("#Removed == 0"))

    lua.execute("""
        Host.K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end
        Pawn = Host; PC.Pawn = Host; Host.Controller = PC
        Unlocked = {}
        function Keypad(address, code, x)
            local k = Thing(address, { CorrectCode = FStr(code) })
            function k:K2_GetActorLocation() return { X = x, Y = 0, Z = 0 } end
            function k:Unlock() Unlocked[#Unlocked + 1] = address end
            return k
        end
        Objects.BP_TypeableKeypad_C = { Keypad(640, "9999", 5000), Keypad(641, "1234", 1200) }
        Log = {}
    """)
    lua.execute('Authority = false; Console("codes"); Authority = true')
    ok &= check("codes shows every keypad's code, nearest first, also for a guest",
                values(g.Log)[1:] == ["  1234   (12 m away)", "  9999   (50 m away)"])
    lua.execute('Console("codes open")')
    ok &= check("codes open unlocks them the way hacking does", lua.eval("#Unlocked == 2"))

    lua.execute("""
        Truck = MakeTruck(4200)
        Overlapping = {}
        -- the money area as in the real truck: a box 318 wide, 842 long and 364 tall, its bottom on
        -- the cargo floor and its top at the roof
        BoxExtent = { X = 159, Y = 421, Z = 182 }
        BoxForward, BoxRight = { X = 1, Y = 0, Z = 0 }, { X = 0, Y = 1, Z = 0 }
        Truck.MoneyOverlapper = {
            K2_GetComponentLocation = function() return { X = 1000, Y = 2000, Z = 100 } end,
            GetScaledBoxExtent = function() return BoxExtent end,
            GetForwardVector = function() return BoxForward end,
            GetRightVector = function() return BoxRight end,
            IsOverlappingActor = function(self, a) return Overlapping[a:GetAddress()] == true end,
        }
        Moves = {}
        -- a piece of loot as the game has it: its physics may be off (placed in the map, or come to
        -- rest), and its pickup component sets it up on the first pick up and let go
        Taken = {}
        function Loot(address, value, parent, physicsOn)
            local l = Thing(address, { Value = value })
            function l:GetAttachParentActor() return parent or Invalid end
            local root = { Physics = physicsOn or false }
            function root:IsSimulatingPhysics(bone) assert(bone == "None"); return self.Physics end
            function root:SetMobility(m) assert(m == 2); self.Movable = true end
            function root:SetSimulatePhysics(on) assert(self.Movable, "movable first"); self.Physics = on end
            function l:K2_GetRootComponent() return root end
            l.Root = root
            l.PickupItemComponent = Thing(address + 0.5)
            function l.PickupItemComponent:OnPickedUp() Taken[#Taken + 1] = address .. ":picked up" end
            function l.PickupItemComponent:OnDropped() Taken[#Taken + 1] = address .. ":let go" end
            function l:K2_SetActorLocation(to, sweep, hit, teleport)
                assert(sweep == false and type(hit) == "table" and teleport == true)
                Moves[#Moves + 1] = { who = address, at = to, falls = root.Physics, taken = #Taken }
                Overlapping[address] = true                -- put inside the money area: counted
                return true
            end
            return l
        end
        -- a move is inside the money area (in the box's own directions, clear of its sides) and no
        -- higher than 200 over its floor
        function InBox(at)
            local dx, dy = at.X - 1000, at.Y - 2000
            local a = dx * BoxForward.X + dy * BoxForward.Y
            local b = dx * BoxRight.X + dy * BoxRight.Y
            return math.abs(a) <= BoxExtent.X - 60 + 0.01 and math.abs(b) <= BoxExtent.Y - 60 + 0.01
                and at.Z > 100 - 182 and at.Z <= 100 - 182 + 200
        end
        function AllInBox() for _, m in ipairs(Moves) do if not InBox(m.at) then return false end end return true end
        function Heights()
            local seen, out = {}, {}
            for _, m in ipairs(Moves) do if not seen[m.at.Z] then seen[m.at.Z] = true; out[#out + 1] = m.at.Z end end
            table.sort(out)
            return table.concat(out, ",")
        end
        function ManyLoot(n, first)
            local list = {}
            for i = 1, n do list[i] = Loot(first + i, 100) end
            return list
        end
        Bag = Thing(659)
        Objects.Money_base_C = { Loot(650, 1000), Loot(651, 2000), Loot(652, 4000), Loot(653, 8000, Bag), Loot(654, 16000) }
        Friend.HoldingActor = Objects.Money_base_C[2]
        Overlapping[652] = true
        Log = {}
    """)
    lua.execute('Console("bringloot")')
    ok &= check("bringloot moves loose loot into the truck, not what is held, stuck to a bag or already inside",
                lua.eval("#Moves == 2 and Moves[1].who == 650 and Moves[2].who == 654")
                and any("Moving 2 pieces of loot worth 17000 into the truck" in m for m in values(g.Log)))
    ok &= check("bringloot drops a few pieces side by side in the middle of the money area, just above its floor",
                lua.eval("Moves[1].at.Z == -22 and Moves[2].at.Z == -22 and AllInBox() and Moves[1].at.X == 1000 "
                         "and Moves[1].at.Y == 2000 and Moves[2].at.X == 1000 and Moves[2].at.Y == 1955"))
    ok &= check("each piece is picked up and let go the game's way before it moves: its physics on, then its own "
                "OnPickedUp and OnDropped, so a piece that only moves once picked up falls instead of floating",
                lua.eval("Moves[1].falls and Moves[2].falls and Taken[1] == '650:picked up' and Taken[2] == '650:let go' "
                         "and Moves[1].taken == 2 and Taken[3] == '654:picked up' and Moves[2].taken == 4"))
    lua.execute("""
        Moves, Overlapping, Taken = {}, {}, {}
        Thrown = Loot(660, 500, nil, true)                 -- already falling: its physics is left as it is
        Thrown.Root.SetMobility = function() error("not again") end
        Objects.Money_base_C = { Thrown }
        Console("bringloot")
    """)
    ok &= check("a piece that already has its physics on keeps it and is still picked up and let go",
                lua.eval("#Moves == 1 and Moves[1].falls and #Taken == 2"))
    lua.execute("""
        Moves, Overlapping = {}, { [650] = true, [654] = true }
        Objects.Money_base_C = { Loot(650, 1000), Loot(651, 2000), Loot(652, 4000), Loot(653, 8000, Bag), Loot(654, 16000) }
        Friend.HoldingActor = Objects.Money_base_C[2]
        Overlapping[652] = true
    """)
    lua.execute('Log = {}; Console("bringloot")')
    ok &= check("bringloot with nothing loose says so", any("No loose loot to move" in m for m in values(g.Log)))
    lua.execute("""
        Moves, Overlapping = {}, {}
        Objects.Money_base_C = ManyLoot(250, 3000)
        QueueDelays = true; Log = {}
        Console("bringloot")
    """)
    ok &= check("a big pile: the whole floor of the money area is used, one layer first (85 pieces)",
                lua.eval("#Moves == 85 and Heights() == '-22' and AllInBox()")
                and any("Moving 250 pieces" in m and "in 3 layers" in m for m in values(g.Log)))
    lua.execute('RunDelays()')
    ok &= check("then each further layer drops a little higher once the one below has landed, all inside the truck",
                lua.eval("#Moves == 250 and Heights() == '-22,13,48' and AllInBox()"))
    lua.execute("""
        Moves, Overlapping = {}, {}
        Objects.Money_base_C = ManyLoot(600, 4000)
        Log = {}
        Console("bringloot"); RunDelays()
    """)
    ok &= check("never higher than the safe height under the roof: what does not fit stays and is reported",
                lua.eval("#Moves == 425 and Heights() == '-22,13,48,83,118' and AllInBox()")
                and any("175 more do not fit at once" in m for m in values(g.Log)))
    lua.execute("""
        Moves, Overlapping = {}, {}
        BoxForward, BoxRight = { X = 0, Y = 1, Z = 0 }, { X = -1, Y = 0, Z = 0 }   -- a truck turned 90 degrees
        Objects.Money_base_C = ManyLoot(85, 5000)
        Console("bringloot"); RunDelays()
        MaxX, MaxY = 0, 0
        for _, m in ipairs(Moves) do
            MaxX = math.max(MaxX, math.abs(m.at.X - 1000)); MaxY = math.max(MaxY, math.abs(m.at.Y - 2000))
        end
    """)
    ok &= check("a turned truck: the pieces follow the truck's own length and width",
                lua.eval("#Moves == 85 and AllInBox() and MaxX == 360 and MaxY == 90"))
    lua.execute("""
        BoxForward, BoxRight = { X = 1, Y = 0, Z = 0 }, { X = 0, Y = 1, Z = 0 }
        Moves, Overlapping = {}, {}
        Objects.Money_base_C = ManyLoot(250, 6000)
        Console("bringloot")
        WorldId = 2                                        -- the heist ended: another map
        RunDelays()
        WorldId = 1; QueueDelays = false
    """)
    ok &= check("a map change stops the layers still to come", lua.eval("#Moves == 85"))
    lua.execute("""
        Moves, Overlapping = {}, {}
        Objects.Money_base_C = { Loot(650, 1000), Loot(651, 2000), Loot(652, 4000), Loot(653, 8000, Bag), Loot(654, 16000) }
        Overlapping[652] = true
    """)

    lua.execute("""
        Button = MakeButton()
        Ended = 0
        function Button:EndGame() Ended = Ended + 1; EndedWith = Truck["CanEndGame?"] end
        Truck.TotalTake = 30000
        Log = {}
    """)
    lua.execute('Console("escape")')
    ok &= check("escape: the truck may leave and the escape button's own EndGame runs",
                g.Ended == 1 and g.EndedWith is True and "4200:CanEndGame?" in values(g.Dirty)
                and any("30000" in m for m in values(g.Log)))
    lua.execute('Authority = false; Console("escape"); Authority = true')
    ok &= check("escape as a guest needs the host", g.Ended == 1)

    shot = "/Game/BP/Guns/GunBase.GunBase_C:ShootClient"
    lua.execute(f"""
        MyGun = Thing(670, {{ BulletsLeft = 4, MagSize = 30, OwnerPlayer = Host }})
        OtherGun = Thing(671, {{ BulletsLeft = 4, MagSize = 30, OwnerPlayer = Friend }})
        Host.HoldingGun = MyGun
        Log = {{}}
    """)
    ok &= check("no gun hook before infiniteammo is turned on", g.Hooks["/Game/BP/Guns/GunBase.GunBase_C:ShootClient"] is None)
    lua.execute('MissingHooks["/Game/BP/Guns/GunBase.GunBase_C:ShootClient"] = true; Log = {}; Console("infiniteammo on")')
    ok &= check("infiniteammo where the guns are not loaded yet: says it starts in a heist, no hook yet",
                g.Hooks["/Game/BP/Guns/GunBase.GunBase_C:ShootClient"] is None and any("heist" in m for m in values(g.Log)))
    lua.execute('MissingHooks["/Game/BP/Guns/GunBase.GunBase_C:ShootClient"] = nil; Hooks["/Script/Engine.PlayerController:ClientRestart"](Param(PC)); Console("infiniteammo off"); MyGun.BulletsLeft = 4')
    ok &= check("the gun hook is placed once a heist loads, once", g.Hooks["/Game/BP/Guns/GunBase.GunBase_C:ShootClient"] is not None and g.Registrations["hook /Game/BP/Guns/GunBase.GunBase_C:ShootClient"] == 1)
    lua.execute('Console("infiniteammo")')
    ok &= check("infiniteammo on fills the magazine in your hand, and places the gun hook once",
                g.MyGun.BulletsLeft == 30 and g.Registrations["hook /Game/BP/Guns/GunBase.GunBase_C:ShootClient"] == 1)
    lua.execute(f'MyGun.BulletsLeft = 29; Hooks["{shot}"](Param(MyGun)); OtherGun.BulletsLeft = 29; Hooks["{shot}"](Param(OtherGun))')
    lua.execute('ObjectSearches = 0; MyGun.BulletsLeft = 29; Hooks["/Game/BP/Guns/GunBase.GunBase_C:ShootClient"](Param(MyGun)); SearchesInShot = ObjectSearches')
    ok &= check("infiniteammo's per-shot check never searches all objects", g.SearchesInShot == 0)
    ok &= check("infiniteammo refills your gun after every shot, not anyone else's",
                g.MyGun.BulletsLeft == 30 and g.OtherGun.BulletsLeft == 29)
    lua.execute(f'Console("infiniteammo"); MyGun.BulletsLeft = 29; Hooks["{shot}"](Param(MyGun))')
    ok &= check("infiniteammo again turns it off", g.MyGun.BulletsLeft == 29)
    lua.execute('Pawn = MakePawn(500); PC.Pawn = Pawn; Pawn.Controller = PC')

    # --- doors: unlock / open / close (one or all), the vault
    lua.execute("""
        DOOR, VAULT = "/Game/BP/Utility/DoorBP.DoorBP_C", "/Game/BP/Utility/Vaults/VaultDoor.VaultDoor_C"
        Loaded[DOOR], Loaded[VAULT] = true, true
        DoorCalls = {}
        -- a door as the game has it: UnlockDoor keeps PowerLocked? once the alarm went off,
        -- OpenDoorServer toggles Open? unless the door is swinging
        function Door(address, fields, x)
            local d = Thing(address, fields)
            d["Open?"] = d["Open?"] or false
            d["Opening?"] = d["Opening?"] or false
            d["Locked?"] = d["Locked?"] or false
            d["PowerLocked?"] = d["PowerLocked?"] or false
            d["AlarmTriggered?"] = d["AlarmTriggered?"] or false
            function d:IsA(cls) return cls.Path == DOOR end
            function d:K2_GetActorLocation() return { X = x or 0, Y = 0, Z = 0 } end
            function d:UnlockDoor()
                DoorCalls[#DoorCalls + 1] = address .. ":unlock"
                if not self["AlarmTriggered?"] then self["PowerLocked?"] = false end
                self["Locked?"] = false
            end
            function d:SetDoorName(n) DoorCalls[#DoorCalls + 1] = address .. ":name " .. n end
            function d:OpenDoorServer(player, speed, sneak, ease)
                DoorCalls[#DoorCalls + 1] = address .. ":toggle"
                self.OpenedBy = player
                if self["Opening?"] then return end
                self["Open?"] = not self["Open?"]
            end
            return d
        end
        function Vault(address, open)
            local v = Thing(address, { ["Open?"] = open, Opened = 0 })
            function v:IsA(cls) return cls.Path == VAULT end
            function v:OpenVault() self.Opened = self.Opened + 1; self["Open?"] = true end
            return v
        end
        Plain = Door(800, {}, 0)
        Picked = Door(801, { ["Locked?"] = true }, 1000)
        Keycard = Door(802, { ["Locked?"] = true, ["PowerLocked?"] = true, ["AlarmTriggered?"] = true }, 2000)
        Swinging = Door(803, { ["Opening?"] = true }, 3000)
        Ajar = Door(804, { ["Open?"] = true }, 4000)
        Objects.DoorBP_C = { Plain, Picked, Keycard, Swinging, Ajar }
        TheVault = Vault(810, false)
        Objects.VaultDoor_C = { TheVault }
        -- the padlock on the picked door: a child actor of the door
        Padlock = Thing(805)
        function Padlock:IsA(cls) return false end
        function Padlock:GetParentActor() return Picked end
        Wall = Thing(806)
        function Wall:IsA(cls) return false end
        function Wall:GetParentActor() return Invalid end
        function Wall:GetAttachParentActor() return Invalid end
        Log = {}
    """)
    lua.execute('Console("doors")')
    ok &= check("doors shows how many doors are locked and open, and the vault",
                any("Doors: 5 (2 locked, 1 open)" in m and "vault is shut" in m for m in values(g.Log)))
    lua.execute('LookTarget = Padlock; Dirty = {}; Log = {}; Console("doors unlock")')
    ok &= check("doors unlock: the door you look at (here its padlock) is unlocked the game's way and stays shut",
                g.Picked["Locked?"] is False and g.Picked["Open?"] is False and "801:unlock" in values(g.DoorCalls)
                and g.Keycard["Locked?"] is True and any("Unlocked the door" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("doors unlock")')
    ok &= check("doors unlock on a door that is not locked says so", any("not locked" in m for m in values(g.Log)))
    lua.execute('LookTarget = Wall; LookLocation = { X = 2080, Y = 0, Z = 0 }; Log = {}; DoorCalls = {}; Console("door unlock")')
    ok &= check("door (the same command) looking at the wall right beside a door unlocks that door, power lock too",
                g.Keycard["Locked?"] is False and g.Keycard["PowerLocked?"] is False and "802:PowerLocked?" in values(g.Dirty)
                and values(g.DoorCalls) == ["802:unlock", "802:name Door"])
    lua.execute('LookLocation = { X = 9000, Y = 0, Z = 0 }; Log = {}; Console("doors unlock")')
    ok &= check("doors unlock looking far from any door says so", any("Not looking at a door" in m for m in values(g.Log)))
    lua.execute("""
        LookLocation = nil; LookTarget = nil
        Picked["Locked?"] = true
        Keycard["Locked?"], Keycard["PowerLocked?"] = true, true
        Plain["PowerLocked?"] = true          -- locks once the alarm goes off
        DoorCalls = {}; Log = {}
    """)
    lua.execute('Console("doors unlock all")')
    ok &= check("doors unlock all: every locked or power-locked door is unlocked, none opened",
                g.Picked["Locked?"] is False and g.Keycard["Locked?"] is False and g.Keycard["PowerLocked?"] is False
                and g.Plain["PowerLocked?"] is False and not any(c.endswith(":toggle") for c in values(g.DoorCalls))
                and any("Unlocked 3 doors" in m for m in values(g.Log)))
    lua.execute('Picked["Locked?"] = true; LookTarget = Picked; DoorCalls = {}; Log = {}; Console("doors open")')
    ok &= check("doors open: unlocks and opens the door you look at, as the door itself (no guard alerted)",
                g.Picked["Open?"] is True and g.Picked["Locked?"] is False and lua.eval("Picked.OpenedBy == Picked"))
    lua.execute('DoorCalls = {}; Log = {}; Console("doors open")')
    ok &= check("doors open on an open door leaves it open (the game's open is a toggle)",
                g.Picked["Open?"] is True and len(g.DoorCalls) == 0 and any("already open" in m for m in values(g.Log)))
    lua.execute('Console("doors close")')
    ok &= check("doors close shuts it", g.Picked["Open?"] is False)
    lua.execute('LookTarget = nil; DoorCalls = {}; Log = {}; Console("doors open all")')
    ok &= check("doors open all opens every shut door, leaves open and swinging ones alone",
                g.Plain["Open?"] is True and g.Picked["Open?"] is True and g.Keycard["Open?"] is True
                and g.Ajar["Open?"] is True and g.Swinging["Open?"] is False
                and "804:toggle" not in values(g.DoorCalls) and "803:toggle" not in values(g.DoorCalls))
    lua.execute('Log = {}; Console("doors close all")')
    ok &= check("doors close all shuts every open door", g.Plain["Open?"] is False and g.Ajar["Open?"] is False)
    # --- doors lock: the one you look at, or every door
    lua.execute("""
        -- a picked padlock door, left open: both padlocks Unlocked?, their tool spots and the
        -- inside handle gone (picking destroys them), its health used up by the grinder
        function Padlock2(address)
            local l = Thing(address, { ["Unlocked?"] = true })
            l.ToolOwnerComponent = { Health = 0 }
            l.SpottedHighlightcomponent = { ["CanHighlight?"] = false }
            l.ToolSpotChild = { ChildActor = Invalid }
            function l.ToolSpotChild:SetChildActorClass(cls) DoorCalls[#DoorCalls + 1] = address .. ":spot " .. cls.Path end
            return l
        end
        Barred = Door(807, { ["Open?"] = true, Health = 50 }, 5000)
        Barred.Lock = { ChildActor = Padlock2(808) }
        Barred.Lock1 = { ChildActor = Padlock2(809) }
        Barred.UnlockSide = { ChildActor = Invalid }
        function Barred.UnlockSide:SetChildActorClass(cls) DoorCalls[#DoorCalls + 1] = "807:handle " .. cls.Path end
        function Barred:GetFullName() return "DoorBP_Locked_C /Game/Maps/Bank.Bank:PersistentLevel.DoorBP_Locked2" end
        Objects.DoorBP_C = { Plain, Picked, Keycard, Swinging, Ajar, Barred }
        for _, d in ipairs(Objects.DoorBP_C) do
            local a = d:GetAddress()
            if not d.GetFullName then d.GetFullName = function() return "DoorBP_C /Game/Maps/Bank.Bank:PersistentLevel.Door" .. a end end
        end
        LookTarget = Barred; DoorCalls = {}; Dirty = {}; Log = {}
    """)
    lua.execute('Console("doors lock")')
    ok &= check("doors lock: the door you look at is locked again and closed, its padlocks pickable again and their tool spots and inside handle made again",
                g.Barred["Locked?"] is True and g.Barred["Open?"] is False and "807:Locked?" in values(g.Dirty)
                and "807:name Door (locked)" in values(g.DoorCalls) and "807:toggle" in values(g.DoorCalls)
                and lua.eval("Barred.Lock.ChildActor['Unlocked?'] == false and Barred.Lock1.ChildActor['Unlocked?'] == false "
                             "and Barred.Lock.ChildActor.ToolOwnerComponent.Health == 10 "
                             "and Barred.Lock1.ChildActor.SpottedHighlightcomponent['CanHighlight?'] == true")
                and "808:Unlocked?" in values(g.Dirty) and "809:Unlocked?" in values(g.Dirty)
                and "808:spot /Game/BP/Utility/ToolSpot.ToolSpot_C" in values(g.DoorCalls)
                and "809:spot /Game/BP/Utility/ToolSpot.ToolSpot_C" in values(g.DoorCalls)
                and "807:handle /Game/BP/Utility/UnlockCollision.UnlockCollision_C" in values(g.DoorCalls)
                and any("Locked the door and closed it" in m for m in values(g.Log)))
    lua.execute('Log = {}; DoorCalls = {}; Console("doors lock")')
    ok &= check("doors lock on a locked door says so and does not toggle it",
                any("already locked" in m for m in values(g.Log)) and "807:toggle" not in values(g.DoorCalls))
    lua.execute('Log = {}; Console("doors unlock"); Console("doors open")')
    ok &= check("a relocked door unlocks and opens again with doors unlock / doors open",
                g.Barred["Locked?"] is False and g.Barred["Open?"] is True)
    lua.execute("""
        Swinging["Opening?"], Swinging["Open?"] = true, false     -- swinging open right now
        Ajar["Open?"] = true
        LookTarget = nil; DoorCalls = {}; Dirty = {}; Log = {}; QueueDelays = true; Delays = {}
        Console("doors lock all")
    """)
    ok &= check("doors lock all: every door locked and named locked; open ones closed, a swinging one left to stop first",
                all(g[n]["Locked?"] is True for n in ("Plain", "Picked", "Keycard", "Swinging", "Ajar", "Barred"))
                and g.Ajar["Open?"] is False and g.Barred["Open?"] is False and "803:toggle" not in values(g.DoorCalls)
                and len([c for c in values(g.DoorCalls) if c.endswith(":name Door (locked)")]) == 6
                and any("Locked 6 doors (3 being closed)" in m and "Guards can still open" in m for m in values(g.Log)))
    lua.execute('Swinging["Opening?"], Swinging["Open?"] = false, true; RunDelays(); QueueDelays = false')
    ok &= check("doors lock all: the door that was swinging open is closed once it stops",
                g.Swinging["Open?"] is False and "803:toggle" in values(g.DoorCalls))
    lua.execute('Log = {}; Console("doors lock everything")')
    ok &= check("doors lock with a wrong word shows the usage", any("Usage: doors" in m and "doors lock [all]" in m for m in values(g.Log)))
    lua.execute("""
        Swinging["Opening?"] = true; Swinging["Open?"] = false
        for _, d in ipairs({ Plain, Picked, Keycard, Ajar, Barred }) do d["Locked?"] = false; d["Open?"] = false end
        Swinging["Locked?"] = false
        Objects.DoorBP_C = { Plain, Picked, Keycard, Swinging, Ajar }
        DoorCalls = {}; Log = {}
    """)
    lua.execute('Log = {}; Console("doors vault close")')
    ok &= check("doors vault close says the game cannot close a vault", any("cannot be closed" in m for m in values(g.Log))
                and g.TheVault.Opened == 0)
    lua.execute('Log = {}; Console("doors vault open")')
    ok &= check("doors vault open opens it the game's way and warns that it cannot be closed again",
                g.TheVault.Opened == 1 and any("WARNING" in m and "cannot be closed" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("doors vault open"); Console("doors vault")')
    ok &= check("doors vault open again does nothing; doors vault shows it is open",
                g.TheVault.Opened == 1 and any("already open" in m for m in values(g.Log)) and any("vault is open" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("doors smash")')
    ok &= check("doors with a wrong word shows the usage", any("Usage: doors" in m for m in values(g.Log)))
    lua.execute('OARCommands.State.share.silentUntil = 0; Authority = false; Sent = {}; QueueDelays = true; Log = {}; Console("doors unlock all")')
    ok &= check("guest: doors unlock all goes to the host", g.Sent[1].endswith(" doors unlock all") and any("Asked the host" in m for m in values(g.Log)))
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok Unlocked 2 doors"); Sent = {}; Console("doors unlock")')
    ok &= check("guest: doors unlock sends your camera so the host unlocks the door YOU look at",
                g.Sent[1].endswith(" doors unlock @0,0,0,10.0,20.0"))
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok"); RunDelays(); QueueDelays = false; Authority = true')
    lua.execute("""
        Console("commandsharing 1"); GuestMessages = {}
        Picked["Locked?"] = true; LookTarget = Picked
        GuestRequest("oar1 af1 doors unlock @100,200,300,-5.0,45.0")
    """)
    ok &= check("host, sharing 1: a guest's doors is denied (it changes the map for everyone)",
                g.Picked["Locked?"] is True and values(g.GuestMessages)[-1].startswith("[OAR host] af1 denied doors"))
    lua.execute('Console("commandsharing 2"); GuestMessages = {}; TraceArgs = nil; GuestRequest("oar1 af2 doors unlock @100,200,300,-5.0,45.0")')
    ok &= check("host, sharing 2: a guest's doors unlock unlocks the door the guest looks at, and the guest gets the answer",
                g.Picked["Locked?"] is False and lua.eval("TraceArgs.ignored == GuestPawn")
                and values(g.GuestMessages)[-1] == "[OAR host] af2 ok Unlocked the door (it stays shut)")
    lua.execute('GuestMessages = {}; GuestRequest("oar1 af3 alarm")')
    ok &= check("host, sharing 2: a guest's heist command runs as the mod's own code and answers with what it says",
                values(g.GuestMessages)[-1].startswith("[OAR host] af3 ok Alarm is"))
    # --- guards: kill / remove (one or all), their phones
    lua.execute("""
        GUARD = "/Game/BP/NPC/NPC_Guard.NPC_Guard_C"
        Loaded[GUARD] = true
        GuardCalls = {}
        function Phone(address, fields)
            local p = Thing(address, fields)
            if p["Active?"] == nil then p["Active?"] = true end
            p.SecondsToAlert = p.SecondsToAlert or 15
            p.PickupItemComponent = { ["Picked up?"] = p.Held or false }
            function p:StopPhoneAlert() self["Active?"] = false; GuardCalls[#GuardCalls + 1] = address .. ":answered" end
            function p:CountdownText(t) assert(type(t) == "table", "CountdownText wants an FText"); self.Countdown = t.s end
            function p:K2_DestroyActor() GuardCalls[#GuardCalls + 1] = address .. ":destroyed" end
            return p
        end
        -- a guard as the game has it: TakeDamage at 0 health kills; one who was not alert drops a phone
        function Guard(address, fields, x)
            local gd = Thing(address, fields)
            gd["Dead?"] = gd["Dead?"] or false
            gd["Alert?"] = gd["Alert?"] or false
            gd.Health = gd.Health or 100
            function gd:IsA(cls) return cls.Path == GUARD end
            function gd:K2_GetActorLocation() return { X = x or 0, Y = 0, Z = 0 } end
            gd.Mesh = { K2_GetComponentLocation = function() return { X = (x or 0) + (gd.Fell or 0), Y = 0, Z = 0 } end }
            function gd:TakeDamage(damage, player)
                GuardCalls[#GuardCalls + 1] = address .. ":damage " .. damage
                self.Killer = player
                self.Health = self.Health - damage
                if self.Health <= 0 and not self["Dead?"] then
                    self["Dead?"] = true
                    if not self["Alert?"] then
                        Objects.GuardPhone_C = Objects.GuardPhone_C or {}
                        table.insert(Objects.GuardPhone_C, Phone(address + 50))
                    end
                end
            end
            gd.PhysicsConstraint = { BreakConstraint = function() GuardCalls[#GuardCalls + 1] = address .. ":keycard drops" end }
            function gd:K2_DestroyActor() GuardCalls[#GuardCalls + 1] = address .. ":destroyed" end
            return gd
        end
        Patrol = Guard(850, { AttachedKeycard = Thing(890) }, 0)
        Watchful = Guard(851, { ["Alert?"] = true }, 1000)
        Escort = Guard(852, { ["Escorting?"] = true, EscortingPlayer = Friend }, 2000)
        Body = Guard(853, { ["Dead?"] = true, Fell = 300 }, 3000)
        Objects.NPC_Guard_C = { Patrol, Watchful, Escort, Body }
        Objects.GuardPhone_C = { Phone(860, { SecondsToAlert = 9 }), Phone(861, { ["Active?"] = false }) }
        Friend["Escorted?"] = true
        Log = {}
    """)
    lua.execute('Console("guards")')
    ok &= check("guards shows how many are alive, alert and down, and the phones ringing",
                any("Guards: 3 alive (1 alert), 1 down" in m and "Phones: 1 ringing, the first alerts the guards in 10 s" in m
                    for m in values(g.Log)))
    lua.execute('LookTarget = Patrol; Log = {}; GuardCalls = {}; Console("guards kill")')
    ok &= check("guards kill: the guard you look at dies the game's way (all its health, from you) and drops a ringing phone",
                lua.eval("Patrol['Dead?'] and Patrol.Killer == PC.Pawn and GuardCalls[1] == '850:damage 100' "
                         "and Objects.GuardPhone_C[3]['Active?'] == true")
                and any("Killed the guard. 1 phone is ringing" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("guards kill")')
    ok &= check("guards kill on a guard that is down already does nothing", any("already down" in m for m in values(g.Log)))
    lua.execute('LookTarget = Wall; LookLocation = { X = 3290, Y = 0, Z = 0 }; Log = {}; GuardCalls = {}; Console("guards remove")')
    ok &= check("guards remove: looking at the floor by a body (where it fell, not where the guard stood) removes it",
                lua.eval("GuardCalls[1] == '853:destroyed'") and any("Removed the body" in m for m in values(g.Log)))
    lua.execute('LookLocation = { X = 9000, Y = 0, Z = 0 }; Log = {}; Console("guards kill")')
    ok &= check("guards kill looking at no guard says so", any("Not looking at a guard" in m for m in values(g.Log)))
    lua.execute('LookTarget = nil; Objects.NPC_Guard_C = { Patrol, Watchful, Escort }; Dirty = {}; Log = {}; GuardCalls = {}; Console("guards remove all")')
    ok &= check("guards remove all: every guard and body; a keycard on a belt drops first, an escorted player is let go",
                lua.eval("GuardCalls[1] == '850:keycard drops' and GuardCalls[2] == '850:destroyed' and GuardCalls[3] == '851:destroyed' "
                         "and GuardCalls[4] == '852:destroyed' and Friend['Escorted?'] == false")
                and "710:Escorted?" in values(g.Dirty) and any("Removed 2 guards and 1 body" in m for m in values(g.Log)))
    lua.execute("""
        Objects.NPC_Guard_C = { Guard(870, {}, 0), Guard(871, { ["Alert?"] = true }, 100) }
        Objects.GuardPhone_C = {}
        Log = {}; Console("guards kill all")
    """)
    ok &= check("guards kill all: every guard; only the one who was not alert drops a phone",
                lua.eval("Objects.NPC_Guard_C[1]['Dead?'] and Objects.NPC_Guard_C[2]['Dead?'] and #Objects.GuardPhone_C == 1")
                and any("Killed 2 guards. 1 phone is ringing" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("guards kill all")')
    ok &= check("guards kill all when all are down", any("Every guard is already down" in m for m in values(g.Log)))
    lua.execute("""
        Objects.GuardPhone_C = { Phone(880, { SecondsToAlert = 4 }), Phone(881, { Held = true }), Phone(882, { ["Active?"] = false }) }
        Log = {}; GuardCalls = {}; Console("guards phones")
    """)
    ok &= check("guards phones shows the ringing phones", any("Phones: 2 ringing, the first alerts the guards in 5 s" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("guards phones answer")')
    ok &= check("guards phones answer: each ringing phone's own StopPhoneAlert and an empty countdown, as a scanner does",
                lua.eval("GuardCalls[1] == '880:answered' and GuardCalls[2] == '881:answered' and #GuardCalls == 2 "
                         "and Objects.GuardPhone_C[1].Countdown == ''")
                and any("Answered 2 phones" in m for m in values(g.Log)))
    lua.execute("""
        Objects.GuardPhone_C = { Phone(883), Phone(884, { Held = true }) }
        Log = {}; GuardCalls = {}; Dirty = {}; Console("guards phones remove")
    """)
    ok &= check("guards phones remove: takes the phones away (stopped first); one in a player's hands is answered instead",
                lua.eval("GuardCalls[1] == '883:destroyed' and GuardCalls[2] == '884:answered' and #GuardCalls == 2")
                and "883:Active?" in values(g.Dirty)
                and any("Removed 1 phone (1 in a player's hands: answered instead)" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("guards dance")')
    ok &= check("guards with a wrong word shows the usage", any("Usage: guards" in m for m in values(g.Log)))
    lua.execute('OARCommands.State.share.silentUntil = 0; Authority = false; Sent = {}; QueueDelays = true; Log = {}; Console("guards kill")')
    ok &= check("guest: guards kill goes to the host with your camera (the guard YOU look at)",
                g.Sent[1].endswith(" guards kill @0,0,0,10.0,20.0") and any("Asked the host" in m for m in values(g.Log)))
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok Killed the guard"); RunDelays(); QueueDelays = false; Authority = true')
    lua.execute('Objects.NPC_Guard_C = nil; Objects.GuardPhone_C = nil')
    lua.execute('Console("commandsharing 0"); LookTarget = nil; Objects.DoorBP_C = nil; Objects.VaultDoor_C = nil')
    lua.execute('Objects = {}; Truck = nil; Button = nil; Characters = nil; Pawn = MakePawn(500); PC.Pawn = Pawn; Pawn.Controller = PC')

    # --- command sharing: pure rules
    ok &= check("sharing levels: 0 off, 1 player, 2 world, 3 all but blocked", lua.eval(r"""(function()
        local S = OARCommands.Exports.Share
        return not S.Allowed(0, "summon") and S.Allowed(1, "summon") and S.Allowed(1, "destroytarget")
            and not S.Allowed(1, "slomo") and S.Allowed(2, "slomo") and not S.Allowed(2, "stat")
            and S.Allowed(3, "stat") and not S.Allowed(3, "exit") and not S.Allowed(3, "deletecloudfiles")
            and not S.Allowed(3, "setmoney") and not S.Allowed(3, "open")
            and not S.Allowed(3, "setammo") and not S.Allowed(3, "infiniteammo")
    end)()"""))
    ok &= check("request format round-trips with a camera pose", lua.eval(r"""(function()
        local S = OARCommands.Exports.Share
        local id, line, pose = S.Decode(S.Encode("ab1", "destroytarget", { x = 1.4, y = -2, z = 3, pitch = -10.25, yaw = 90 }))
        return id == "ab1" and line == "destroytarget" and pose.x == 1 and pose.y == -2 and pose.pitch == -10.2 and pose.yaw == 90
    end)()"""))

    # --- host side: a guest's requests
    lua.execute('Authority = true; Log = {}; Console("commandsharing")')
    ok &= check("commandsharing starts at 0 (off)", any("Command sharing is 0: off" in m for m in values(g.Log)))
    lua.execute('GuestMessages = {}; GuestRequest("oar1 ab1 summon goldbar 3")')
    ok &= check("sharing 0: the guest is told it is off", values(g.GuestMessages) == ["[OAR host] ab1 off"])
    lua.execute('Console("commandsharing 1"); QueueDelays = true; OtherSummons = {}; GuestMessages = {}; Messages = {}')
    lua.execute('GuestRequest("oar1 ab2 summon goldbar 3"); RunDelays(); QueueDelays = false')
    ok &= check("sharing 1: a guest's summon runs on the guest's own cheat manager (in front of them)",
                lua.eval('#OtherSummons == 3 and OtherSummons[1].owner == GuestPC and OtherSummons[3].name == "Goldbar_C"'))
    ok &= check("the guest gets ok with a summary", values(g.GuestMessages)[-1].startswith("[OAR host] ab2 ok Summoning Goldbar_C x3"))
    ok &= check("the host sees who ran what", any("Friend ran: summon goldbar 3" in m for m in values(g.Messages)))
    lua.execute('GuestMessages = {}; GuestRequest("oar1 ab3 slomo 0.5")')
    ok &= check("sharing 1: world commands are denied", values(g.GuestMessages)[-1].startswith("[OAR host] ab3 denied slomo"))
    lua.execute('Console("commandsharing 2"); GuestMessages = {}; Calls = {}; CallPCs = {}; GuestRequest("oar1 ab4 slomo 0.5")')
    ok &= check("sharing 2: slomo runs through the engine as the guest",
                values(g.Calls) == ["slomo 0.5"] and lua.eval("CallPCs[1] == GuestPC") and values(g.GuestMessages)[-1].startswith("[OAR host] ab4 ok"))
    lua.execute('Console("commandsharing 3"); GuestMessages = {}; Calls = {}; GuestRequest("oar1 ab5 exit"); GuestRequest("oar1 ab6 stat fps")')
    ok &= check("sharing 3: blocked commands are refused, the rest runs",
                values(g.GuestMessages)[0].startswith("[OAR host] ab5 denied exit") and values(g.Calls) == ["stat fps"])
    lua.execute('GuestMessages = {}; Calls = {}; GuestRequest("oar1 ab7 setmoney 5")')
    ok &= check("value commands never run on the host", values(g.GuestMessages)[0].startswith("[OAR host] ab7 denied") and len(g.Calls) == 0)
    ok &= check("a guest can never open the host's menu", lua.eval('not OARCommands.Exports.Share.Allowed(3, "opengui")'))

    lua.execute("""
        Console("commandsharing 1"); GuestMessages = {}
        Target = { IsValid = function() return true end, GetFName = function() return { ToString = function() return "Vase_C" end } end }
        function Target:K2_DestroyActor() self.Destroyed = true end
        LookTarget = Target
        GuestRequest("oar1 ab8 destroytarget @100,200,300,-5.0,45.0")
    """)
    ok &= check("a guest's destroytarget traces from the guest's own camera and destroys it",
                lua.eval("Target.Destroyed == true") and values(g.GuestMessages)[-1] == "[OAR host] ab8 ok destroyed Vase_C")
    lua.execute("""
        Friend = { IsValid = function() return true end, PlayerState = { IsValid = function() return true end } }
        function Friend:K2_DestroyActor() self.Destroyed = true end
        LookTarget = Friend; GuestMessages = {}
        GuestRequest("oar1 ab9 destroytarget @0,0,0,0.0,0.0")
        LookTarget = nil
    """)
    ok &= check("destroytarget from a guest leaves players alone",
                lua.eval("Friend.Destroyed == nil") and "player" in values(g.GuestMessages)[-1])
    lua.execute('GuestPawn["Downed?"] = true; GuestPawn.Health = 0; GuestMessages = {}; GuestRequest("oar1 ac1 revive")')
    ok &= check("a guest's revive revives the guest's character on the host",
                g.GuestPawn.Health == 100 and g.GuestPawn["Downed?"] is False and g.GuestPawn.Revived == 1
                and values(g.GuestMessages)[-1] == "[OAR host] ac1 ok revived")
    lua.execute('GuestMessages = {}; GuestRequest("oar1 ac2 noclip on 800")')
    ok &= check("a guest's noclip is applied to the guest's character on the host",
                g.GuestPawn.Collision is False and g.GuestPawn.CharacterMovement.Mode == 5
                and g.GuestPawn.CharacterMovement.MaxFlySpeed == 800)
    lua.execute('GuestMessages = {}; GuestRequest("oar1 0 noclip on 1600")')
    ok &= check("speed updates (id 0) apply without a reply",
                g.GuestPawn.CharacterMovement.MaxFlySpeed == 1600 and len(g.GuestMessages) == 0)
    lua.execute('GuestRequest("oar1 ac3 noclip off")')
    ok &= check("and noclip off lands the guest again", g.GuestPawn.Collision is True and g.GuestPawn.CharacterMovement.Mode == 3)
    lua.execute('Console("commandsharing 3"); Calls = {}; GuestMessages = {}; GuestRequest("oar1 ae1 cops")')
    ok &= check("sharing 3: a guest's mod command runs on the host as the mod's own code, not handed to the engine",
                "cops" not in values(g.Calls) and len(g.GuestMessages) == 1 and " ok " in values(g.GuestMessages)[0])
    lua.execute('Messages = {}; Hooks["/Script/Engine.PlayerController:ServerExecRPC"](Param(PC), Param(FStr("oar1 ad1 summon goldbar")))')
    ok &= check("the host ignores requests from its own controller", len(g.Messages) == 0)
    lua.execute('Console("commandsharing 0")')

    # --- guest side
    lua.execute('OARCommands.State.share.silentUntil = 0')
    lua.execute('Authority = false; QueueDelays = true; Summons = {}; Sent = {}; Console("summon goldbar 2")')
    ok &= check("guest: summon goes to the host, nothing spawns here",
                len(g.Sent) == 1 and g.Sent[1].endswith(" summon goldbar 2") and g.Sent[1].startswith("oar1 ") and len(g.Summons) == 0)
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok Summoning Goldbar_C x2"); RunDelays()')
    ok &= check("guest: after the host's ok nothing runs here, not even after the timeout", len(g.Summons) == 0)
    lua.execute('Console("summon goldbar 2"); HostReply("[OAR host] " .. LastSentId() .. " off"); RunDelays()')
    ok &= check("guest: host says off, so it runs here like normal", values(g.Summons) == ["Goldbar_C", "Goldbar_C"])
    cfg = open(os.path.join(MOD, "config.lua"), encoding="utf-8").read()
    lua.execute('Calls = {}; Sent = {}; handled0 = Console("god")')
    ok &= check("by default a guest's god is not intercepted, it goes straight to the engine (host god sends it)",
                g.handled0 is False and len(g.Sent) == 0)
    write_config(tmp, cfg.replace("ShareEngineCheatShortcuts = false,", "ShareEngineCheatShortcuts = true,", 1))
    lua.execute('Console("reloadconfig")')
    lua.execute('Calls = {}; HandlerResults = {}; Sent = {}; handled = Console("god")')
    ok &= check("guest, shortcuts on: god goes to the host", g.handled is True and g.Sent[1].endswith(" god"))
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " denied god: needs commandsharing 2 or 3")')
    ok &= check("guest: denied, so the engine runs god here, past this mod's own handler",
                values(g.Calls) == ["god"] and values(g.HandlerResults) == [False])
    lua.execute('Sent = {}; Console("destroytarget")')
    ok &= check("guest: destroytarget sends the guest's camera position and angle",
                g.Sent[1].endswith(" destroytarget @0,0,0,10.0,20.0"))
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok destroyed Vase_C")')
    lua.execute('Pawn.Collision = true; Sent = {}; Console("noclip")')
    ok &= check("guest: noclip asks the host first", g.Sent[1].endswith(" noclip on 600") and g.Pawn.Collision is True)
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok noclip on")')
    ok &= check("guest: after the host's ok the guest's own game flies too", g.Pawn.Collision is False)
    lua.execute(f'Sent = {{}}; KeyDown = false; KeysDown = {{ LeftShift = true }}; Hooks["{frame}"](Param(Pawn)); KeysDown = {{}}; KeyDown = true')
    ok &= check("guest: Shift tells the host the new speed (no reply wanted)", g.Sent[1] == "oar1 0 noclip on 1200")
    lua.execute('Console("noclip"); HostReply("[OAR host] " .. LastSentId() .. " ok noclip off")')
    lua.execute('Summons = {}; Sent = {}; Console("summon goldbar"); RunDelays()')
    ok &= check("guest: the host never answers, so after the wait it runs here", values(g.Summons) == ["Goldbar_C"])
    lua.execute('Summons = {}; Sent = {}; Console("summon goldbar"); RunDelays()')
    ok &= check("guest: a silent host is skipped for a while, commands run here at once",
                len(g.Sent) == 0 and values(g.Summons) == ["Goldbar_C"])
    write_config(tmp, cfg)
    lua.execute('Authority = true; QueueDelays = false; Console("reloadconfig")')
    ok &= check("host or solo: god is left to the engine", lua.eval('Console("god")') is False)


    # --- long summon batches and a guest's deferred noclip never touch objects from before
    lua.execute("""
        Authority = true; QueueDelays = true; Summons = {}
        Console("summon goldbar 3")
        Elsewhere = { GetAddress = function() return 3900 end }
        PC.GetWorld = function() return Elsewhere end      -- the map changed while it was running
        RunDelays()
        PC.GetWorld = function() return World end
    """)
    ok &= check("a summon batch ends when the map changes", len(g.Summons) == 1)
    lua.execute("""
        Console("commandsharing 1"); OtherSummons = {}; GuestMessages = {}
        GuestRequest("oar1 ba1 summon goldbar 3")
        -- the guest leaves: their controller is gone from the game and will be freed
        Gone = GuestPC
        GuestPC = { IsValid = function() return false end, GetAddress = function() return 7777 end }
        for k, v in pairs(Gone) do if type(v) == "function" then Gone[k] = function() error("touched a guest who left") end end end
        RunDelays()
        GuestPC = Gone; Console("commandsharing 0"); QueueDelays = false
    """)
    ok &= check("a guest's summon batch ends when that guest leaves, without touching them again",
                lua.eval("#OtherSummons == 1") and not any("touched" in m for m in values(g.Messages)))
    lua.execute("""
        -- put the guest's controller back as it was
        for k, v in pairs(GuestPC) do if type(v) == "function" then GuestPC[k] = nil end end
        function GuestPC:IsValid() return true end
        function GuestPC:HasAuthority() return true end
        function GuestPC:IsLocalController() return false end
        function GuestPC:GetAddress() return 77 end
        function GuestPC:ClientMessage(text) GuestMessages[#GuestMessages + 1] = text end
        function GuestPC:GetWorld() return World end
        function GuestPC:GetControlRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
        function GuestPC:GetFocalLocation() return { X = 900, Y = 900, Z = 0 } end
    """)
    lua.execute("""
        OARCommands.State.share.silentUntil = 0
        Authority = false; QueueDelays = true; Sent = {}; Log = {}; Messages = {}
        Pawn.Collision = true
        Console("noclip")
        Old = Pawn
        Pawn = MakePawn(501); PC.Pawn = Pawn; Pawn.Controller = PC  -- a new character before the host answered
        for k, v in pairs(Old) do if type(v) == "function" and k ~= "GetAddress" then Old[k] = function() error("touched the old character") end end end
        HostReply("[OAR host] " .. LastSentId() .. " ok noclip on")
        RunDelays(); Authority = true; QueueDelays = false
    """)
    ok &= check("a guest's noclip answered after the character changed asks to type it again, the old one untouched",
                any("type noclip again" in m for m in values(g.Messages)) and g.Pawn.Collision is True)

    # --- selectmap and forcemap
    maps = lua.eval('(require("maps"))')
    heists = list(maps.Heists.values())
    paid = [h for h in heists if h.coin > 0]
    other = [f.lower() for f in maps.Other.values()]
    ok &= check("maps: 13 heists, the 6 sold for coins carry a Steam item ID and are not in the plain list",
                len(heists) == 13 and len(paid) == 6 and all(h.item > 0 for h in paid)
                and not any(h.file.lower() in other for h in paid))
    ok &= check("map names: short name, title with spaces, map file, unique start; dev maps by file name",
                lua.eval(r"""(function()
        local L = OARCommands.Exports.Lobby
        local function key(text) local r = L.Resolve(text) return r and ((r.heist and r.heist.key) or r.file) end
        return key("datacenter") == "datacenter" and key("data center") == "datacenter"
            and key("Map_AIDataCenter") == "datacenter" and key("muse") == "museum" and key("testmap") == "TestMap"
            and key("small bank") == "small_bank" and L.Resolve("tutorial") == nil and L.Resolve("nosuchmap") == nil
    end)()""") is True)
    museum = "/Game/Maps/Menu/BP/Shop/Maps/ShopItem_Map_Museum.ShopItem_Map_Museum_C"
    datacenter = "/Game/Maps/Menu/BP/Shop/Maps/ShopItem_Map_Datacenter.ShopItem_Map_Datacenter_C"
    lua.execute('Authority = true; NewLobby(3); Log = {}; Calls = {}; Console("selectmap")')
    ok &= check("selectmap alone lists the heists and marks the ones sold for coins as not owned",
                any("museum" in m and "Pegasus" in m for m in values(g.Log))
                and any("datacenter" in m and "not owned" in m for m in values(g.Log)) and len(g.Lobby.Selects) == 0)
    lua.execute('Log = {}; Console("selectmap museum")')
    ok &= check("selectmap picks the heist with the lobby's own SelectMap and starts nothing",
                values(g.Lobby.Selects) == [museum] and len(g.Menu.Started) == 0
                and lua.eval('MenuPlayers[1]["Ready?"] == false') and len(g.Calls) == 0)
    lua.execute('Log = {}; Console("selectmap datacenter")')
    ok &= check("a heist sold for coins that you do not own is refused",
                len(g.Lobby.Selects) == 1 and any("sold for coins" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("forcemap data center")')
    ok &= check("forcemap refuses it too: nothing selected, started or travelled to",
                len(g.Lobby.Selects) == 1 and len(g.Menu.Started) == 0 and len(g.Calls) == 0)
    lua.execute('Console("forcemap map_aidatacenter"); Console("forcemap casino")')
    ok &= check("and the map file names of paid heists do not get around that",
                len(g.Lobby.Selects) == 1 and len(g.Menu.Started) == 0 and len(g.Calls) == 0)
    lua.execute('PC.InventoryResultItems = MakeArray({ { Definition = { Value = 77 } }, { Definition = { Value = 205 } } })')
    lua.execute('OutOfBounds = 0; Console("selectmap datacenter")')
    ok &= check("owned in your Steam inventory (the game's own test): it can be picked",
                values(g.Lobby.Selects)[-1] == datacenter and g.OutOfBounds == 0)
    lua.execute(f'NewLobby(3); Loaded["{datacenter}"] = true; PC.UnlockedMaps = MakeArray({{ FakeClass("{datacenter}") }})')
    lua.execute('Console("selectmap datacenter")')
    ok &= check("owned through your unlocked maps: it can be picked", values(g.Lobby.Selects) == [datacenter])

    lua.execute('NewLobby(3); Log = {}; Calls = {}; Console("forcemap museum")')
    ok &= check("forcemap: selects, marks every lobby player ready, then runs the menu's own StartGame once",
                values(g.Lobby.Selects) == [museum] and len(g.Menu.Started) == 1
                and lua.eval(f'Menu.Started[1].map == "{museum}" and Menu.Started[1].ready == true'))
    ok &= check("forcemap in the lobby leaves the travel to the game", len(g.Calls) == 0)
    lua.execute('NewLobby(2); Console("selectmap wineshop"); Console("forcemap")')
    ok &= check("forcemap alone starts the selected heist", len(g.Menu.Started) == 1
                and lua.eval('Menu.Started[1].ready == true'))
    lua.execute(f'NewLobby(2); Loaded["{datacenter}"] = true; Lobby.SelectedMap = FakeClass("{datacenter}"); Console("forcemap")')
    ok &= check("forcemap alone does not start a selected paid heist you do not own", len(g.Menu.Started) == 0)
    lua.execute('NewLobby(2); Menu.Shown = false; Log = {}; Console("forcemap museum")')
    ok &= check("no lobby menu on screen: says so instead of starting",
                len(g.Menu.Started) == 0 and any("not started" in m for m in values(g.Log)))
    lua.execute('NewLobby(1); Calls = {}; Console("forcemap testmap")')
    ok &= check("forcemap with a non-heist map file travels there with servertravel",
                values(g.Calls) == ["servertravel TestMap"] and len(g.Menu.Started) == 0)
    lua.execute('Lobby = nil; Menu = nil; MenuPlayers = {}; Calls = {}; GIUpdates = {}; Log = {}; Console("selectmap museum")')
    ok &= check("selectmap outside the lobby points to forcemap", len(g.Calls) == 0
                and any("works in the lobby" in m for m in values(g.Log)))
    lua.execute('Console("forcemap museum")')
    ok &= check("forcemap from inside a heist: tells the game which heist, then servertravel",
                values(g.GIUpdates) == [museum] and values(g.Calls) == ["servertravel Museum_night"])
    lua.execute('Calls = {}; GIUpdates = {}; PC.InventoryResultItems = MakeArray(); PC.UnlockedMaps = MakeArray(); Console("forcemap harbour")')
    ok &= check("from inside a heist a paid heist you do not own is still refused",
                len(g.Calls) == 0 and len(g.GIUpdates) == 0)
    lua.execute('NewLobby(2); Authority = false; Sent = {}; Log = {}; Calls = {}; Console("forcemap museum"); Console("selectmap museum")')
    ok &= check("guest: only the host picks the map, and nothing is sent to the host",
                len(g.Sent) == 0 and len(g.Lobby.Selects) == 0 and len(g.Calls) == 0
                and any("Only the host" in m for m in values(g.Log)))
    lua.execute('Authority = true; Console("commandsharing 3"); GuestMessages = {}; GuestRequest("oar1 am1 forcemap museum")')
    ok &= check("command sharing never lets a guest change the host's map",
                values(g.GuestMessages)[-1].startswith("[OAR host] am1 denied forcemap") and len(g.Lobby.Selects) == 0)
    lua.execute('Console("commandsharing 0"); NewLobby(1); Console("bind f7 forcemap museum"); KeyCallbacks["KEY_F7"]()')
    ok &= check("forcemap works from a bind", len(g.Menu.Started) == 1)
    lua.execute('Console("unbind f7"); Lobby = nil; Menu = nil; MenuPlayers = {}')

    # --- config.lua and reloadconfig
    default = open(os.path.join(MOD, "config.lua"), encoding="utf-8").read()

    def edited(*pairs):
        text = default
        for a, b in pairs:
            assert a in text, a
            text = text.replace(a, b, 1)
        return text

    lua.execute('Authority = true; QueueDelays = false; PC.CheatManager = CM')
    ok &= check("the values sit at the top of config.lua and every command's code is in it",
                default.index("local V = {") < default.index('Core.Command("bind"')
                and all(f'("{c}"' in default for c in ("bind", "unbind", "unbindall", "summon", "spawn", "summonstop", "dupe",
                                                      "setmoney", "addmoney", "setlevel", "setxp", "maxskills", "unlockall",
                                                      "noclip", "revive", "selectmap", "forcemap", "commandsharing", "host")))
    write_config(tmp, edited(("SummonMax = 500,", "SummonMax = 3,")))
    lua.execute('Summons = {}; Console("summon goldbar 99999")')
    ok &= check("an edit does nothing until reloadconfig", len(g.Summons) == 500)
    lua.execute('Log = {}; Summons = {}; Console("reloadconfig"); Console("summon goldbar 99999")')
    ok &= check("reloadconfig: a changed value applies at once",
                len(g.Summons) == 3 and any("Loaded config.lua" in m for m in values(g.Log)))
    write_config(tmp, edited(('return "Stopped all summon batches"', 'return "No more summons"')))
    lua.execute('Log = {}; Console("reloadconfig"); Console("summonstop")')
    ok &= check("reloadconfig: changed command code applies at once", "No more summons" in values(g.Log))
    write_config(tmp, default + """
Core.Command("hello", function(FullCommand, Parameters, Ar)
    Core.Say(Ar, "hello " .. (Parameters[1] or "you"))
    return true
end)
""")
    lua.execute('Log = {}; Console("reloadconfig"); Console("hello there")')
    ok &= check("reloadconfig: a command added to the file works", "hello there" in values(g.Log))
    write_config(tmp, default)
    lua.execute('Console("reloadconfig"); r = Console("hello there")')
    ok &= check("reloadconfig: a command removed from the file goes back to the engine", g.r is False
                and lua.eval('OARCommands.Handles("hello")') is False)

    write_config(tmp, edited(("SummonMax = 500,", "SummonMax = 500,,")))
    lua.execute('Log = {}; Summons = {}; Console("reloadconfig"); Console("summon goldbar 2")')
    ok &= check("a syntax error is reported with its line, and the commands from before keep working",
                any("NOT loaded" in m for m in values(g.Log)) and any("config.lua:" in m for m in values(g.Log))
                and len(g.Summons) == 2)
    write_config(tmp, default + "\nlocal broken = nil\nbroken.field = 1\n")
    lua.execute('Log = {}; Summons = {}; Console("reloadconfig"); Console("summon goldbar 2"); Console("bind")')
    ok &= check("an error while the file loads is reported too, and nothing is half loaded",
                any("NOT loaded" in m for m in values(g.Log)) and len(g.Summons) == 2)
    write_config(tmp, edited(('local keyName = KeyFromText(Parameters[1])\n    if not keyName then Say(Ar, "Usage: unbind <key>")',
                              'local keyName = NoSuchFunction(Parameters[1])\n    if not keyName then Say(Ar, "Usage: unbind <key>")')))
    lua.execute('Log = {}; Console("reloadconfig"); r = Console("unbind x")')
    ok &= check("a command that breaks while it runs says so and does not reach the engine",
                g.r is True and any(m.startswith("unbind failed:") and "config.lua:" in m for m in values(g.Log)))

    write_config(tmp, default)
    lua.execute('Console("reloadconfig"); Console("commandsharing 2"); Console("bind f8 god"); Calls = {}')
    lua.execute('Console("noclip"); Console("reloadconfig"); Log = {}; Console("commandsharing"); KeyCallbacks["KEY_F8"]()')
    ok &= check("kept across reloadconfig: sharing level, binds, noclip",
                any("Command sharing is 2" in m for m in values(g.Log)) and values(g.Calls) == ["god"]
                and g.Pawn.CharacterMovement.Mode == 5)
    lua.execute(f'KeyDown = false; KeysDown = {{ SpaceBar = true }}; Pawn.Inputs = {{}}; Hooks["{frame}"](Param(Pawn)); KeysDown = {{}}; KeyDown = true')
    ok &= check("noclip's Space still works after reloadconfig", lua.eval("#Pawn.Inputs == 1 and Pawn.Inputs[1].v == 1"))
    lua.execute('Console("noclip"); Console("commandsharing 0"); Console("unbind f8")')
    lua.execute('Characters = { Pawn, Downed }; Pawn.ReviveTime = 3.0; Downed.ReviveTime = 5.0; GameRevive(Downed, Pawn)')
    lua.execute('Truck = MakeTruck(4400); Console("truckmoney set 6000"); Console("reloadconfig"); Recount(0); TakeAfterReload = Truck.TotalTake; Truck = nil')
    ok &= check("truckmoney's hooks still work after reloadconfig (the recount keeps the change)", g.TakeAfterReload == 6000)
    ok &= check("revive timing still works after reloadconfig", g.TimerTime == 3.0 and g.Downed.ReviveTime == 5.0)
    ok &= check("noclip turned on before a reload can be turned off after it", g.Pawn.CharacterMovement.Mode == 3)
    ok &= check("nothing is ever registered with UE4SS twice, however often the config loads",
                all(n == 1 for n in g.Registrations.values()) and g.Registrations["command summon"] == 1
                and g.Registrations["hook /Script/Engine.PlayerController:ServerExecRPC"] == 1
                and g.Registrations["loadmap post"] is None)

    write_config(tmp, edited(("SummonMax = 500,", "SummonMax = 7,")), "config.default.lua")
    lua.execute('Log = {}; Summons = {}; Console("reloadconfig default"); Console("summon goldbar 99999")')
    ok &= check("reloadconfig default loads config.default.lua", len(g.Summons) == 7
                and any("Loaded config.default.lua" in m for m in values(g.Log)))
    lua.execute('Log = {}; Console("reloadconfig nonsense")')
    ok &= check("reloadconfig with anything else shows the usage", any("Usage: reloadconfig" in m for m in values(g.Log)))
    lua.execute('Summons = {}; Console("reloadconfig"); Console("summon goldbar 99999"); Console("bind f9 reloadconfig"); KeyCallbacks["KEY_F9"](); Console("unbind f9")')
    ok &= check("back on config.lua, and reloadconfig works from a bind", len(g.Summons) == 500)

    broken_tmp = tempfile.mkdtemp()
    lua3, _ = make_runtime(broken_tmp, default.replace("local V = {", "local V = {{", 1))
    g3 = lua3.globals()
    ok &= check("a broken config.lua at game start: only reloadconfig exists",
                lua3.eval('OARCommands.Handles("summon")') is False and lua3.eval('OARCommands.Handles("reloadconfig")') is True)
    write_config(broken_tmp, default)
    lua3.execute('Console("reloadconfig"); Console("summon goldbar 2")')
    ok &= check("and after fixing the file, reloadconfig brings every command back", len(g3.Summons) == 2)

    # --- objects: one class with different data (summon by object name, dupe with data)
    lua.execute('Authority = true; QueueDelays = false; PC.CheatManager = CM; LookTarget = nil')
    objects = lua.eval('(require("objects"))')
    with_data = {k: v for k, v in objects.items() if v.props is not None or v.comps is not None or v.assets is not None}
    spawn_keys = set(lua.eval('(require("spawnables"))').keys())
    spawn_paths = {v.path for v in lua.eval('(require("spawnables"))').values()}
    ok &= check("objects table: over 60 objects, each of a class summon knows, no name used twice",
                len(with_data) > 60 and all(v.path in spawn_paths for v in objects.values())
                and not set(objects.keys()) & spawn_keys)
    ok &= check("objects table: artwork variants, the Mona Lisa, keycards by name, in-game names",
                {"mona_lisa", "artwork_nefertiti", "vault_keycard", "artwork", "gold_bar"} <= set(objects.keys())
                and len([k for k in with_data if k.startswith("artwork_")]) >= 15)

    painting_mesh = "/Game/Assets/PolygonCasino/Models/Props/SM_Prop_Wall_Safe_01_Painting_01.SM_Prop_Wall_Safe_01_Painting_01"
    lua.execute('Spawned = {}; Summons = {}; Log = {}; OutOfBounds = 0; QueueDelays = true; Console("summon mona lisa 2"); RunDelays(); QueueDelays = false')
    ok &= check("summon mona lisa 2: two Artworks spawned as actors, not through the engine's summon",
                len(g.Spawned) == 2 and len(g.Summons) == 0
                and lua.eval('Spawned[1].cls.Path == "/Game/BP/Items/Valuables/Statue_museum.Statue_museum_C"'))
    ok &= check("each one gets the painting's mesh, material and value",
                lua.eval(f'Spawned[2].actor.Root.StaticMesh.Path == "{painting_mesh}"')
                and lua.eval('Spawned[2].actor.Root.Materials[1].Path:find("M_PolygonCasino_Texture_03_A", 1, true) ~= nil')
                and lua.eval('Spawned[2].actor.Value == 45000'))
    ok &= check("it appears where the engine's summon would put it: 72 in front, 15 up",
                lua.eval('Spawned[1].location.X == 172 and Spawned[1].location.Y == 0 and Spawned[1].location.Z == 65 '
                         'and Spawned[1].rotation.Yaw == 90'))
    ok &= check("the host sends the changed mesh to guests", lua.eval('Spawned[1].actor.Root.Replicated == true'))
    ok &= check("the summary names the object", any("Summoning Artwork: Mona Lisa" in m and "x2" in m for m in values(g.Log)))
    ok &= check("no memory outside a list is touched", g.OutOfBounds == 0)
    lua.execute('Spawned = {}; Summons = {}; Console("summon artwork")')
    ok &= check("summon artwork (the in-game name) is the plain class", values(g.Summons) == ["Statue_museum_C"] and len(g.Spawned) == 0)
    lua.execute('Spawned = {}; Summons = {}; Console("summon gold bar 2")')
    ok &= check("names ignore spaces and underscores: gold bar is goldbar",
                values(g.Summons) == ["Goldbar_C"] * 2 and len(g.Spawned) == 0)
    lua.execute('Spawned = {}; Summons = {}; Console("summon Statue_Museum")')
    ok &= check("class names still work, with or without underscores", values(g.Summons) == ["Statue_museum_C"])
    lua.execute('Spawned = {}; Summons = {}; Log = {}; Console("summon artw")')
    ok &= check("an unclear start lists the matching names",
                len(g.Summons) == 0 and len(g.Spawned) == 0 and any("matches" in m and "artwork" in m for m in values(g.Log)))
    lua.execute('Spawned = {}; Summons = {}; Console("summon mona")')
    ok &= check("a unique start of an object name is enough", len(g.Spawned) == 1 and len(g.Summons) == 0)
    lua.execute('Spawned = {}; Console("summon vault keycard")')
    ok &= check("text variables are set too: a keycard by its name",
                len(g.Spawned) == 1 and lua.eval('Spawned[1].actor["Keycard name"] == "Vault Keycard"'))
    lua.execute('Spawned = {}; Console("summon artwork_artthing")')
    ok &= check("size is copied", lua.eval('math.abs(Spawned[1].actor.Root.RelativeScale3D.X - 0.352) < 0.001'))
    lua.execute('Spawned = {}; Summons = {}; SpawnFails = true; Console("summon mona lisa"); SpawnFails = false')
    ok &= check("if spawning as an actor fails, the plain class is summoned instead", values(g.Summons) == ["Statue_museum_C"])
    lua.execute('Spawned = {}; StaticRoots = true; Console("summon mona lisa"); StaticRoots = false')
    ok &= check("a component that never moves is made movable just for the mesh change",
                lua.eval(f'Spawned[1].actor.Root.StaticMesh.Path == "{painting_mesh}" and Spawned[1].actor.Root.Mobility == 0 '
                         'and Spawned[1].actor.Root.MobilityChanges == 2'))

    lua.execute('Spawned = {}; Summons = {}; Log = {}; OutOfBounds = 0; Source = NewPainting(); LookTarget = Source; QueueDelays = true; Console("dupe 2"); RunDelays(); QueueDelays = false')
    ok &= check("dupe 2 of a painting: two actors of its class, no plain summon",
                len(g.Spawned) == 2 and len(g.Summons) == 0 and lua.eval("Spawned[1].cls == Source:GetClass()"))
    ok &= check("dupe copies the mesh, every material and the size",
                lua.eval("""(function()
        local r = Spawned[2].actor.Root
        return r.StaticMesh.Name == "PaintingMesh" and r.Materials[1].Name == "Canvas" and r.Materials[2].Name == "Frame"
            and r.RelativeScale3D.X == 0.35 and r.Replicated == true
    end)()"""))
    ok &= check("dupe copies the Blueprint variables of the class and of its parent classes",
                lua.eval("""(function()
        local a = Spawned[2].actor
        return a.Value == 45000 and a.EXP == 10.5 and a.Title == "Painting" and a["Stolen?"] == true and a.Sort == "Painting"
            and a.Tint.R == 1 and a.Tint.G == 0.5 and a.Sound.Name == "Clink" and a.Kind.Name == "SomeClass"
    end)()"""))
    ok &= check("dupe copies the variables of Blueprint components (the look-at text)",
                lua.eval('Spawned[2].actor.BlueprintCreatedComponents.Data[1].Name == "Mona Lisa"'))
    ok &= check("dupe leaves out references to other actors and components, lists and engine data",
                lua.eval('Spawned[2].actor.Holder == nil and Spawned[2].actor.LookatInfoComponent == nil '
                         'and Spawned[2].actor.Parts == nil and Spawned[2].actor.UberGraphFrame == nil'))
    ok &= check("dupe touches no memory outside a list", g.OutOfBounds == 0)
    ok &= check("dupe still names the class", any("Summoning Statue_museum_C x2" in m for m in values(g.Log)))
    lua.execute('Spawned = {}; Source.Value = 1; Source.Root.StaticMesh = FakeAsset("Changed"); QueueDelays = true; Console("dupe 2")')
    lua.execute('Source.Value = 7; RunDelays(); QueueDelays = false')
    ok &= check("the data is read once, when dupe runs", lua.eval('Spawned[2].actor.Value == 1 and Spawned[2].actor.Root.StaticMesh.Name == "Changed"'))
    lua.execute('Spawned = {}; Summons = {}; LookTarget = GoldActor; Console("dupe")')
    ok &= check("an object whose data cannot be read is still copied as its plain class",
                values(g.Summons) == [gold] and len(g.Spawned) == 0)
    write_config(tmp, edited(("CopyLookToGuests = true,", "CopyLookToGuests = false,")))
    lua.execute('Console("reloadconfig"); Spawned = {}; LookTarget = NewPainting(); Console("dupe")')
    ok &= check("CopyLookToGuests = false keeps the mesh change on the host only",
                lua.eval('Spawned[1].actor.Root.StaticMesh.Name == "PaintingMesh" and Spawned[1].actor.Root.Replicated == false'))
    write_config(tmp, default)
    lua.execute('Console("reloadconfig"); Console("commandsharing 1"); Spawned = {}; GuestMessages = {}; LookTarget = NewPainting()')
    lua.execute('GuestRequest("oar1 ao1 dupe @1,2,3,0.0,0.0")')
    ok &= check("a guest's dupe: the host copies the data and spawns it in front of the guest",
                len(g.Spawned) == 1 and lua.eval('Spawned[1].actor.Value == 45000 and Spawned[1].location.X == 972')
                and values(g.GuestMessages)[-1].startswith("[OAR host] ao1 ok Summoning Statue_museum_C"))
    lua.execute('Spawned = {}; GuestRequest("oar1 ao2 summon mona lisa")')
    ok &= check("a guest's summon of an object name works through the host too",
                len(g.Spawned) == 1 and lua.eval('Spawned[1].actor.Value == 45000'))
    lua.execute('Console("commandsharing 0"); LookTarget = nil; Spawned = {}')


    # --- opengui: the in-game menu (with stand-ins for the engine's UI widgets)
    tick = "/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"
    ok &= check("the menu's keys (left mouse button, Escape) are watched from the start, once each, nothing hooked yet",
                g.Registrations["key KEY_LEFT_MOUSE_BUTTON"] == 1 and g.Registrations["key KEY_ESCAPE"] == 1
                and g.Hooks[tick] is None)
    lua.execute("""
        Authority = true; QueueDelays = false
        Objects = {}; Truck = nil; Button = nil
        function Menu() return OARCommands.State.menu end
        -- the visible lines and buttons of the menu, by their text
        function Lines()
            local out = {}
            for _, r in ipairs(Menu().rows) do
                if r.line and r.root.Visibility ~= 1 then out[#out + 1] = r end
            end
            return out
        end
        function LineTexts()
            local out = {}
            for _, r in ipairs(Lines()) do out[#out + 1] = r.line.label or r.line.text end
            return out
        end
        function FindChip(text)
            for _, r in ipairs(Lines()) do
                for _, c in ipairs(r.chips) do
                    if r.plain.Visibility ~= 1 and c.outer.Visibility ~= 1 and c.text.TextValue == text then return c end
                end
            end
            for _, c in pairs(Menu().optionChips) do if c.text.TextValue == text then return c end end
            for _, c in ipairs(Menu().tabChips) do if c.text.TextValue == text then return c end end
            if Menu().closeChip.text.TextValue == text then return Menu().closeChip end
        end
        function FindLine(text)
            for _, r in ipairs(Lines()) do
                if (r.line.label or r.line.text or "") == text then return r end
            end
            for _, r in ipairs(Lines()) do
                if (r.line.label or r.line.text or ""):find(text, 1, true) then return r end
            end
        end
        -- a click as the game sees it: the mouse is over a widget, UE4SS's key watcher sees the
        -- left button go down, and the menu acts on its next frame
        function Click(widget)
            Hovered = widget
            KeyCallbacks["KEY_LEFT_MOUSE_BUTTON"]()
            Tick()
            Hovered = nil
        end
        function ClickChip(text) local c = assert(FindChip(text), "no button " .. text); Click(c.button) end
        function ClickLine(text) local r = assert(FindLine(text), "no line " .. text); Click(r.wide) end
        function Tab(name) ClickChip(name) end
        function Tick() Menu().nextTick = 0; Hooks["/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"](Param(PC)) end
        -- let running animations reach their end (the next frame after their time is up)
        function FinishAnims(m)
            m = m or Menu()
            for _, a in pairs(m.anims or {}) do a.start = -1000 end
            Hooks["/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"](Param(PC))
        end
    """)
    lua.execute('Log = {}; Console("opengui")')
    ok &= check("opengui builds the window from the game's do-nothing widget and opens it: the menu gets the mouse and keys",
                lua.eval("Menu() ~= nil and Menu().open and Menu().root.InViewport and UMG.inputMode == 'ui' "
                         "and UMG.focus == Menu().root and PC.bShowMouseCursor == true and Menu().root.bIsFocusable == true")
                and len(g.Log) == 0)
    ok &= check("the per-frame hook is placed once the menu opens", g.Hooks[tick] is not None)
    ok &= check("the window has eleven tabs (ESP after Doors); Code only shows with Advanced on",
                lua.eval("#Menu().tabChips == 11 and Menu().tabs[11].name == 'Code' and Menu().tabs[10].name == 'Settings' "
                         "and Menu().tabs[9].name == 'Binds' and Menu().tabs[5].name == 'ESP' and Menu().tabs[4].name == 'Doors' "
                         "and Menu().tabChips[11].button.Visibility == 1"))
    ok &= check("buttons are engine buttons in flat colours, lighter under the mouse, and do not take the keyboard",
                lua.eval("(function() local b = FindChip('X').button; return b.ClassName == 'Button' and b.IsFocusable == false "
                         "and b.WidgetStyle.Normal.ResourceName == 'None' and b.WidgetStyle.Hovered.TintColor.SpecifiedColor.R "
                         "> b.WidgetStyle.Normal.TintColor.SpecifiedColor.R end)()"))
    ok &= check("text is written in place before it is shown (UE4SS cannot pass a struct inside a struct)",
                lua.eval("(function() local t = FindChip('X').text; return t.Font.Size == 14 and t.ColorAndOpacity.SpecifiedColor.R > 0.9 "
                         "and t.ColorAndOpacity.ColorUseRule == 0 end)()"))
    lua.execute("""
        Broken = {}
        for i = 1, #Menu().tabs do
            Menu():SelectTab(i)
            for _, t in ipairs(LineTexts()) do
                if t:find("could not be shown", 1, true) then Broken[#Broken + 1] = t end
            end
        end
        Menu():SelectTab(1)
    """)
    ok &= check("every tab draws without an error", len(g.Broken) == 0 or print(values(g.Broken)))
    ok &= check("the Player tab shows its groups and lines", lua.eval("FindLine('Noclip') ~= nil and FindLine('Spare ammo') ~= nil and FindLine('Moving') ~= nil"))
    ok &= check("the tab you are on is filled in (the look picked on the design page)",
                lua.eval("Menu().tabChips[1].button.Background.G > 1 and Menu().tabChips[2].button.Background.G == 1 "
                         "and Menu().tabChips[1].mark.Visibility == 1"))
    ok &= check("the window is titled One-Armed-Menu, buttons are outlined in the accent colour, scrolling is smooth",
                lua.eval("(function() local m = Menu(); local x = m.closeChip; return x.outer ~= x.button and x.outer.ClassName == 'Border' "
                         "and x.outer.Brush.G == m.style.accent[2] and m.scroll.SmoothScroll == true end)()"))
    lua.execute('FinishAnims()')
    ok &= check("opening fades the window in and slides it into place", lua.eval("Menu().root.Opacity == 1 and Menu().windowBox.Moved.Y == 0"))
    lua.execute('Pawn.ReserveAmmo = MakeArray({ 1, 2 }); Pawn.HoldingGun = nil; ClickChip("Set")')
    ok &= check("a button with an amount runs its command with what is in the box (setammo 999)",
                lua.eval("Pawn.ReserveAmmo.Data[1] == 999") and "Spare ammo is now 999" in g.Menu().status.TextValue)
    lua.execute('FindLine("Spare ammo").input:SetText(FText("50")); ClickChip("Set")')
    ok &= check("what you type in the box is used", lua.eval("Pawn.ReserveAmmo.Data[1] == 50"))
    lua.execute('Hovered = nil; KeyCallbacks["KEY_LEFT_MOUSE_BUTTON"](); Tick(); Pawn.ReserveAmmo.Data[1] = 7; Hovered = FindChip("Set").button; Tick(); Hovered = nil')
    ok &= check("a click on no button does nothing, and is not kept for later", lua.eval("Pawn.ReserveAmmo.Data[1] == 7"))
    lua.execute('Pawn.Collision = true; ClickChip("Take off")')
    ok &= check("Noclip's button flies, and the line then says ON with a Land button",
                g.Pawn.Collision is False and lua.eval("FindChip('Land') ~= nil and FindLine('Noclip').hint.TextValue == 'ON'"))
    lua.execute('ClickChip("Land")')
    lua.execute("""
        Characters = { Pawn }
        Plain2 = Door(820, { ["Locked?"] = true }, 0)
        Objects.DoorBP_C = { Plain2 }
        Tab("Doors")
    """)
    ok &= check("the Doors tab shows how many doors are locked", lua.eval("FindLine('All doors').hint.TextValue == '1 (1 locked, 0 open)'"))
    lua.execute('ClickChip("Unlock all")')
    ok &= check("Doors > Unlock all unlocks them, says so at the bottom, and the line updates",
                g.Plain2["Locked?"] is False and "Unlocked 1 doors" in g.Menu().status.TextValue
                and lua.eval("FindLine('All doors').hint.TextValue == '1 (0 locked, 0 open)'"))
    lua.execute('TheVault = Vault(821, false); Objects.VaultDoor_C = { TheVault }; Tab("Player"); Tab("Doors"); ClickChip("Open vault")')
    ok &= check("the vault's button asks first: the first click only shows the question, in another colour",
                g.TheVault.Opened == 0 and lua.eval("FindChip(\"Can't close it again. Sure?\") ~= nil")
                and lua.eval("FindChip(\"Can't close it again. Sure?\").button.Background.R > 1"))
    lua.execute('ClickChip("Can\'t close it again. Sure?")')
    ok &= check("the second click opens the vault", g.TheVault.Opened == 1 and "cannot be closed" in g.Menu().status.TextValue)

    lua.execute('Tab("Spawn")')
    ok &= check("Spawn: the groups start closed, no names listed yet",
                lua.eval("FindLine('Valuables') ~= nil and FindLine('Gold bar') == nil"))
    lua.execute('ClickLine("Valuables")')
    ok &= check("clicking a group opens it", lua.eval("FindLine('Gold bar') ~= nil"))
    lua.execute('Summons = {}; ClickLine("Gold bar")')
    ok &= check("clicking a name spawns it (as many as How many says)", values(g.Summons) == ["Goldbar_C"])
    lua.execute('ClickChip("5"); Summons = {}; ClickLine("Gold bar")')
    ok &= check("the 5 button sets How many, and the next spawn makes 5",
                len(g.Summons) == 5 and lua.eval("FindLine('How many').input.TextValue == '5'"))
    lua.execute('ClickLine("Valuables")')
    ok &= check("clicking the group again closes it", lua.eval("FindLine('Gold bar') == nil"))
    lua.execute('Menu().search:SetText(FText("old b")); Tick()')
    ok &= check("search finds the text anywhere in a name, in closed groups too, with the group's title",
                lua.eval("FindLine('Gold bar') ~= nil and FindLine('Valuables') ~= nil and FindLine('How many') == nil"))
    lua.execute('Menu().search:SetText(FText("GOLDBAR_c")); Tick()')
    ok &= check("search also finds class names, in any case", lua.eval("FindLine('Gold bar') ~= nil"))
    lua.execute('ClickChip("Full names: off")')
    ok &= check("Full names shows the class name instead", lua.eval("FindLine('Goldbar_C') ~= nil and FindLine('Gold bar') == nil"))
    lua.execute('ClickChip("Full names: on"); Menu().search:SetText(FText("")); Tick()')
    ok &= check("the advanced groups only show with Advanced on", lua.eval("FindLine('Menu scenery') == nil"))
    lua.execute('ClickChip("Advanced: off")')
    ok &= check("Advanced on shows them", lua.eval("FindLine('Menu scenery') ~= nil"))
    lua.execute('rowsBefore = #Menu().rows; ClickLine("Menu scenery"); firstFrame = #Menu().rows - rowsBefore')
    ok &= check("a long list makes only a few new lines per frame", g.firstFrame == g.Menu().style.rowsPerFrame)
    lua.execute('for _ = 1, 20 do Tick() end')
    ok &= check("then the rest, up to the most a tab shows, which says to search for more",
                lua.eval("#Lines() == Menu().style.maxRows") and lua.eval("FindLine('type in the search box') ~= nil"))
    ok &= check("lines only ever used for spawn names get no buttons or amount box (made only when a line needs them)",
                lua.eval("#Menu().rows[#Menu().rows].chips == 0 and Menu().rows[#Menu().rows].input == nil"))
    lua.execute('ClickLine("Menu scenery"); ClickChip("Advanced: on")')

    lua.execute('Tab("Heist")')
    ok &= check("Heist outside a heist says so on its lines", lua.eval("FindLine('Alarm').hint.TextValue == 'not here'"))
    lua.execute('Ended = 0; ClickChip("Escape")')
    ok &= check("Escape asks first", lua.eval("FindChip('End the heist?') ~= nil"))
    lua.execute('Menu().confirm.untilTime = 0; Tick()')
    ok &= check("an unanswered question goes away after a few seconds", lua.eval("FindChip('End the heist?') == nil and FindChip('Escape') ~= nil"))
    lua.execute('Click(FindLine("Alarm and cameras").wide); Click(Menu().root)')
    ok &= check("clicking a group title without a group, or the window itself, does nothing", lua.eval("Menu().open"))

    lua.execute('Tab("Settings"); ClickChip("2")')
    ok &= check("Settings: command sharing level buttons", lua.eval("OARCommands.State.share.level == 2")
                and lua.eval("FindLine('Guests may run').hint.TextValue:find('^2: ') ~= nil"))
    lua.execute('ClickChip("0 off")')
    # --- the Binds tab
    lua.execute('Tab("Binds"); FindLine("Key").input:SetText(FText("f6")); FindLine("Command").input:SetText(FText("noclip")); ClickChip("Bind it")')
    ok &= check("Binds: a key and a command, then Bind it, makes the bind (no new key watch: F6 is watched from the start)",
                lua.eval('FindLine("F6") ~= nil and FindLine("F6").line.info == "noclip"') and g.Registrations["key KEY_F6"] == 1
                and "Bound F6 to: noclip" in g.Menu().status.TextValue)
    lua.execute('ClickLine("Ideas"); ClickLine("god | ghost")')
    ok &= check("Binds: clicking an idea puts it in Command", lua.eval('FindLine("Command").input.TextValue == "god | ghost"'))
    lua.execute('FindLine("Key").input:SetText(FText("")); Click(FindLine("F6").chips[1].button)')
    ok &= check("Binds: Change puts a bind's key and command in the boxes",
                lua.eval('FindLine("Key").input.TextValue == "f6" and FindLine("Command").input.TextValue == "noclip"'))
    lua.execute('Click(FindLine("F6").chips[2].button)')
    ok &= check("Binds: Remove unbinds it", lua.eval('FindLine("F6") == nil'))
    lua.execute('ClickLine("Ideas")')

    # --- the Code tab (Advanced only)
    cfg_path = os.path.join(tmp, "OARCommands", "config.lua")
    backup_path = os.path.join(tmp, "OARCommands", "config.backup.lua")
    cfg_before = open(cfg_path, encoding="utf-8").read()
    lua.execute('ClickChip("Advanced: off"); Tab("Code")')
    ok &= check("Code: with Advanced on there is a Code tab listing config.lua's parts",
                lua.eval('FindLine("doors  (host") ~= nil and FindLine("Top of the file") ~= nil and FindLine("1. VALUES") ~= nil'))
    lua.execute('ClickLine("doors  (host")')
    lua.execute("""
        function Editor()
            for _, r in ipairs(Lines()) do if r.line.kind == "editor" then return r end end
        end
    """)
    ok &= check("Code: clicking a part opens it in an editor, starting at its comment block",
                lua.eval('Editor() ~= nil and Editor().code.TextValue:find("^%-%-%-%-") ~= nil '
                         'and Editor().code.TextValue:find("Core.Command%(\\"doors\\"") ~= nil'))
    lua.execute('original = Editor().code.TextValue; Editor().code:SetText(FText(original .. "\\nlocal x = = 1\\n")); ClickChip("Check")')
    ok &= check("Code: Check finds a mistake and says on which line of this part", "Mistake: line" in g.Menu().status.TextValue)
    lua.execute('ClickChip("Save and reload")')
    ok &= check("Code: a part with a mistake is not saved", open(cfg_path, encoding="utf-8").read() == cfg_before
                and "Not saved, there is a mistake" in g.Menu().status.TextValue and not os.path.exists(backup_path))
    lua.execute('Editor().code:SetText(FText((original:gsub("Usage: doors   |", "Usage: doors!  |")))); old = Menu(); ClickChip("Save and reload")')
    ok &= check("Code: Save writes config.lua, copies the old file to config.backup.lua first, and loads it",
                "Usage: doors!  |" in open(cfg_path, encoding="utf-8").read() and open(backup_path, encoding="utf-8").read() == cfg_before)
    ok &= check("Code: the menu opens again by itself on the same part, with the result at the bottom",
                lua.eval('Menu() ~= old and Menu().open and Menu().tabs[Menu().tab].name == "Code" and Editor() ~= nil')
                and "Saved doors" in g.Menu().status.TextValue)
    lua.execute('Log = {}; Console("doors smash")')
    ok &= check("Code: the saved change is what the game runs now", any("Usage: doors!" in m for m in values(g.Log)))
    saved = open(cfg_path, encoding="utf-8").read()
    lua.execute('Editor().code:SetText(FText(Editor().code.TextValue .. "\\nerror(\\"boom\\")\\n")); ClickChip("Save and reload")')
    ok &= check("Code: an edit that fails when it runs is taken back out: config.lua is as it was, the edit stays in the box",
                open(cfg_path, encoding="utf-8").read() == saved and "failed when it ran" in g.Menu().status.TextValue
                and lua.eval('Editor().code.TextValue:find("boom") ~= nil'))
    lua.execute('ClickChip("Undo changes")')
    ok &= check("Code: Undo changes goes back to the file", lua.eval('Editor().code.TextValue:find("boom") == nil'))
    lua.execute('ClickChip("Back")')
    ok &= check("Code: Back returns to the list", lua.eval('Editor() == nil and FindLine("doors  (host") ~= nil'))
    ok &= check("Code: the list has the full file first, then every part A to Z",
                lua.eval("""(function()
                    local labels = {}
                    for _, r in ipairs(Lines()) do if r.line.kind == "item" then labels[#labels + 1] = r.line.label end end
                    if #labels < 20 or not labels[1]:find("^Full file") then return false end
                    for i = 3, #labels do if labels[i - 1]:lower() > labels[i]:lower() then return false end end
                    return true
                end)()"""))
    ok &= check("Code: a part's commands are named when its title does not say them",
                lua.eval('FindLine("Heist commands for the host").line.label:find("alarm, cops, cameras", 1, true) ~= nil '
                         'and FindLine("guards  (host").line.label:sub(-8) == "sharing)"'))
    lua.execute('Menu().search:SetText(FText("bringloot")); Tick()')
    ok &= check("Code: the search box finds the part a command is in", lua.eval('FindLine("Heist commands for the host") ~= nil'))
    lua.execute('Menu().search:SetText(FText("")); Tick(); ClickLine("Full file")')
    ok &= check("Code: Full file opens all of config.lua",
                lua.eval('Editor() ~= nil and Editor().code.TextValue') == open(cfg_path, encoding="utf-8").read())
    full_text = open(cfg_path, encoding="utf-8").read()
    guards_line = full_text[:full_text.index('Core.Command("guards"')].count("\n") + 1
    lua.execute('FindLine("Find").input:SetText(FText("core.command(\\"guards\\"")); Tick(); Tick(); Tick()')
    ok &= check("Find: typing finds the text (any case) in the open file and says where",
                lua.eval('FindLine("Find").line.hint') == f"1 of 1, line {guards_line}")
    ok &= check("Find: that line is marked in the box and scrolled to",
                lua.eval(f"Editor().markSlot.Padding.Top == {(guards_line - 1) * 20} and Editor().markSize.Height == 20 "
                         f"and Editor().markSize.Visibility == 3 and Menu().scroll.ScrollOffset == {3 * 30 + 10 + (guards_line - 1) * 20 - 60}"))
    lua.execute('FindLine("Find").input:SetText(FText("local function")); Tick()')
    count = full_text.count("local function")
    ok &= check("Find: every place is counted", lua.eval('FindLine("Find").line.hint').startswith(f"1 of {count}, line "))
    lua.execute('ClickChip("Next")')
    ok &= check("Find: Next goes to the next place", lua.eval('FindLine("Find").line.hint').startswith(f"2 of {count}, "))
    lua.execute('ClickChip("Previous"); ClickChip("Previous")')
    ok &= check("Find: Previous goes round to the last", lua.eval('FindLine("Find").line.hint').startswith(f"{count} of {count}, "))
    lua.execute('Editor().code:SetText(FText(Editor().code.TextValue .. "-- zz_my_new_line\\n")); FindLine("Find").input:SetText(FText("zz_my_new_line")); Tick()')
    ok &= check("Find: it finds your edits too (what is in the box now)",
                lua.eval('FindLine("Find").line.hint') == f"1 of 1, line {full_text.count(chr(10)) + 1}")
    lua.execute('FindLine("Find").input:SetText(FText("nothing like this zz")); Tick(); Tick(); Tick()')
    ok &= check("Find: text that is not there says so, and the mark goes",
                lua.eval('FindLine("Find").line.hint') == "not found" and lua.eval("Editor().markSize.Visibility == 1"))
    lua.execute('ClickChip("Undo changes"); ClickChip("Back"); ClickLine("doors  (host")')
    ok &= check("Code: a part opened from the list starts at the top with an empty Find",
                lua.eval('FindLine("Find").input.TextValue == "" and Menu().scroll.ScrollOffset == 0'))
    lua.execute('ClickChip("Back")')
    lua.execute('Tab("Settings"); ClickLine("Commands")')
    ok &= check("long names in a line wrap inside their space instead of running under the boxes",
                lua.eval('FindLine("Noclip speed holding Shift").label.AutoWrapText == true'))
    lua.execute('ClickLine("Commands")')
    lua.execute("""
        Objects.NPC_Guard_C = { Guard(900, {}, 0), Guard(901, { ["Dead?"] = true }, 0) }
        Objects.GuardPhone_C = { Phone(902, { SecondsToAlert = 6 }) }
        GuardCalls = {}
        Tab("Heist")
    """)
    ok &= check("Heist tab: guards alive and phones ringing",
                lua.eval('FindLine("Every guard").line.hint == "1 alive" and FindLine("Guard phones").line.hint == "1 ringing (7 s)"'))
    lua.execute('Click(FindLine("Guard phones").chips[1].button)')
    ok &= check("Heist tab: Answer all answers the phones", lua.eval("GuardCalls[1] == '902:answered'"))
    lua.execute('Objects.NPC_Guard_C = nil; Objects.GuardPhone_C = nil; Tab("Code")')
    lua.execute('ClickChip("Advanced: on")')
    ok &= check("turning Advanced off on the Code tab goes back to the first tab",
                lua.eval('Menu().tabs[Menu().tab].name == "Player" and Menu().tabChips[11].button.Visibility == 1'))
    lua.execute('Tab("Settings"); old = Menu(); ClickChip("Reload it")')
    ok &= check("Settings: Reload it reloads config.lua and opens the menu again on Settings",
                lua.eval('Menu() ~= old and Menu().open and Menu().tabs[Menu().tab].name == "Settings"')
                and "Loaded config.lua" in g.Menu().status.TextValue)
    write_config(tmp, cfg_before)
    os.remove(backup_path)
    lua.execute('Console("opengui"); Console("reloadconfig")')
    lua.execute('Console("opengui")')
    # --- the Spawn tab's own search, and words anywhere
    lua.execute('Tab("Spawn"); FindLine("Search all items").input:SetText(FText("bar gold")); Tick()')
    ok &= check("Spawn search: every word typed, in any order, anywhere in a name; closed groups are searched too",
                lua.eval('FindLine("Gold bar") ~= nil and FindLine("Search all items").hint.TextValue:find("found") ~= nil'))
    lua.execute('FindLine("Search all items").input:SetText(FText("valuables goldbar_c")); Tick()')
    ok &= check("Spawn search: also the class name and the group (the text on the right)", lua.eval('FindLine("Gold bar") ~= nil'))
    ok &= check("spawn names show their class name on the right", lua.eval('FindLine("Gold bar").line.sub == "Goldbar_C"'))
    lua.execute('FindLine("Search all items").input:SetText(FText("menu scenery")); Tick()')
    ok &= check("Spawn search covers every group, also the advanced ones", lua.eval('FindLine("Menu scenery") ~= nil'))
    lua.execute('FindLine("Search all items").input:SetText(FText("zzzz nothing")); Tick()')
    ok &= check("Spawn search with no match says so", lua.eval('FindLine("Nothing has all of those words") ~= nil'))
    lua.execute('ClickChip("Clear")')
    ok &= check("Clear empties the search and the groups are back", lua.eval('FindLine("Search all items").input.TextValue == "" and FindLine("Valuables") ~= nil and FindLine("Gold bar") == nil'))
    lua.execute('Tab("Heist"); Menu().search:SetText(FText("police wave")); Tick()')
    ok &= check("the search at the top also takes several words", lua.eval('FindLine("Police") ~= nil and FindLine("Alarm") == nil'))
    lua.execute('Menu().search:SetText(FText("")); Tick()')

    # --- moving and resizing the window (kept in memory only)
    files_before = sorted(os.listdir(os.path.join(tmp, "OARCommands")))
    lua.execute("""
        function Drag(button, fromX, fromY, toX, toY)
            Mouse.X, Mouse.Y = fromX, fromY
            Click(button)                 -- pressing it starts the drag
            button.Pressed = true
            Mouse.X, Mouse.Y = toX, toY
            Tick()                        -- the window follows while it stays pressed
            button.Pressed = false
            Tick()                        -- let go: the drag ends
        end
        m = Menu()
        FinishAnims(m)                    -- the opening slide is over
    """)
    ok &= check("the title bar moves the window (a grab cursor), the corner grip resizes it",
                lua.eval('m.dragBar.Cursor == 10 and m.grip.Cursor == 5'))
    lua.execute('Drag(m.dragBar, 700, 200, 820, 260)')
    ok &= check("dragging the title bar moves the window with the mouse",
                lua.eval('m.place.x == 120 and m.place.y == 60 and m.windowBox.Moved.X == 120 and m.windowBox.Moved.Y == 60'))
    lua.execute('Drag(m.grip, 1400, 900, 1500, 950)')
    ok &= check("dragging the corner makes it bigger, and the top left corner stays put",
                lua.eval('m.place.w == 1200 and m.place.h == 730 and m.windowBox.Width == 1200 and m.windowBox.Height == 730 '
                         'and m.place.x == 170 and m.place.y == 85'))
    lua.execute('Drag(m.grip, 1000, 900, 100, 100)')
    ok &= check("it cannot be made smaller than its smallest size", lua.eval('m.place.w == m.style.minWidth and m.place.h == m.style.minHeight'))
    lua.execute('Drag(m.dragBar, 500, 100, 5000, 5000)')
    ok &= check("it cannot be dragged off the screen (the title bar stays on it)",
                lua.eval('m.place.x <= 1920 / 2 + m.place.w / 2 - 120 and m.place.y <= 1080 / 2 + m.place.h / 2 - 50'))
    lua.execute('placed = { x = m.place.x, y = m.place.y, w = m.place.w }; Console("opengui"); Console("opengui")')
    ok &= check("closing and opening keeps where it was", lua.eval('Menu().place.x == placed.x and Menu().place.w == placed.w'))
    lua.execute('Console("reloadconfig"); Console("opengui")')
    ok &= check("a new window (reloadconfig, another map) opens where you left it, at that size",
                lua.eval('Menu().place.x == placed.x and Menu().windowBox.Width == placed.w'))
    ok &= check("it is only kept in memory (no file was written for it)",
                sorted(os.listdir(os.path.join(tmp, "OARCommands"))) == files_before)
    lua.execute('Tab("Settings"); ClickChip("Back to normal")')
    ok &= check("Settings > Back to normal puts it in the middle at its normal size",
                lua.eval('Menu().place.x == 0 and Menu().place.y == 0 and Menu().place.w == nil and Menu().windowBox.Width == 1100'))
    lua.execute('Tab("Player")')

    # --- Settings: your commands and the menu's look, saved in settings.lua
    settings_path = os.path.join(tmp, "OARCommands", "settings.lua")
    lua.execute('Tab("Settings"); ClickLine("Commands")')
    lua.execute('FindLine("Noclip speed (0").input:SetText(FText("800")); FindLine("Noclip speed holding Shift").input:SetText(FText("2000")); ClickChip("Save and apply")')
    ok &= check("Settings > Commands: noclip speed and Shift speed are saved to settings.lua and used at once",
                lua.eval("OARCommands.Exports.Values.NoclipSpeed == 800 and OARCommands.Exports.Values.NoclipFastSpeed == 2000")
                and os.path.exists(settings_path) and "NoclipSpeed = 800" in open(settings_path, encoding="utf-8").read()
                and "Saved your settings" in g.Menu().status.TextValue)
    lua.execute('Pawn.Collision = true; Pawn.CharacterMovement.MaxWalkSpeed = 600; Console("opengui"); Console("noclip")')
    ok &= check("noclip flies at the saved speed", lua.eval("Pawn.CharacterMovement.MaxFlySpeed == 800"))
    lua.execute(f'KeyDown = false; KeysDown = {{ LeftShift = true }}; Hooks["{frame}"](Param(Pawn))')
    ok &= check("and at the saved Shift speed while Shift is held", lua.eval("Pawn.CharacterMovement.MaxFlySpeed == 2000"))
    lua.execute('OARCommands.Exports.Values.NoclipFastSpeed = 3000')
    lua.execute(f'Hooks["{frame}"](Param(Pawn))')
    ok &= check("a changed speed applies while flying", lua.eval("Pawn.CharacterMovement.MaxFlySpeed == 3000"))
    lua.execute(f'KeysDown = {{}}; KeyDown = true; Hooks["{frame}"](Param(Pawn)); Console("noclip"); OARCommands.Exports.Values.NoclipFastSpeed = 2000')
    lua.execute('Console("opengui"); Tab("Settings"); Click(FindLine("Noclip speed (0").chips[3].button)')
    ok &= check("Default puts a command value back and takes it out of settings.lua",
                lua.eval("OARCommands.Exports.Values.NoclipSpeed == 0") and "NoclipSpeed" not in open(settings_path, encoding="utf-8").read())
    lua.execute('Click(FindLine("A teammate\'s revive finishes").chips[2].button)')
    ok &= check("a switch (revive with the bar) turns off and is saved",
                lua.eval("OARCommands.Exports.Values.ReviveMatchesBar == false") and "ReviveMatchesBar = false" in open(settings_path, encoding="utf-8").read())
    lua.execute('Click(FindLine("A teammate\'s revive finishes").chips[1].button)')

    lua.execute('old = Menu(); ClickChip("Steel blue")')
    ok &= check("an accent preset makes the window again in that colour, saved; the matching tab colour follows it",
                lua.eval("Menu() ~= old and Menu().open and Menu().tabs[Menu().tab].name == 'Settings' "
                         "and math.abs(Menu().style.accent[3] - 0.5711) < 0.001 and Menu().style.on[3] < Menu().style.accent[3]")
                and "accent = {" in open(settings_path, encoding="utf-8").read() and lua.eval("old.destroyed"))
    lua.execute('ClickLine("Colours"); FindLine("Text").input:SetText(FText("#ff0000")); ClickChip("Save and apply")')
    ok &= check("a colour typed as #rrggbb is saved and used (and the Colours group stays open)",
                lua.eval("Menu().style.text[1] == 1 and Menu().style.text[2] == 0 and Menu().expanded['look colours'] == true"))
    lua.execute('FindLine("Text").input:SetText(FText("red please")); ClickChip("Save and apply")')
    ok &= check("a colour that is not #rrggbb is refused, nothing saved", "is not a colour" in g.Menu().status.TextValue
                and lua.eval("Menu().style.text[1] == 1"))
    lua.execute("""
        for _, r in ipairs(Lines()) do if r.line.kind == "header" and r.line.text == "Text" then Click(r.wide) end end
        FindLine("Text").input:SetText(FText("#eceff3"))
    """)
    lua.execute('Click(FindLine("Text size").chips[2].button); ClickChip("Save and apply")')
    ok &= check("Text size + then Save makes the text bigger",
                lua.eval("Menu().style.textSize == 15 and Menu().closeChip.text.Font.Size == 15"))
    lua.execute('for _, r in ipairs(Lines()) do if r.line.kind == "header" and r.line.text == "Style" then Click(r.wide) end end')
    lua.execute('Click(FindLine("Buttons").chips[2].button)')
    ok &= check("a style switch (filled buttons) applies at once", lua.eval("Menu().style.chipStyle == 'filled' and Menu().closeChip.outer == Menu().closeChip.button"))
    lua.execute('FindLine("Most copies one spawn makes").input:SetText(FText("600")); ClickChip("Save and apply")')
    lua.execute('ClickChip("Reset everything"); ClickChip("Back to the defaults?")')
    ok &= check("Reset everything: the default look and command values again",
                lua.eval("Menu().style.textSize == 14 and Menu().style.chipStyle == 'outline' and math.abs(Menu().style.accent[2] - 0.3763) < 0.001 "
                         "and OARCommands.Exports.Values.SummonMax == 500 and FindLine('Most copies one spawn makes').input.TextValue == '500'"))

    # --- from the second review: the title, oversized windows, dark colours
    lua.execute("""
        function TitleText(m)
            for _, w in ipairs(UMG.windows) do end
            -- the title is the first text in the title bar: find the TextBlock with the title's size
            local found
            local function walk(x)
                if type(x) ~= "table" or found then return end
                if x.ClassName == "TextBlock" and x.Font and x.Font.Size == m.style.titleSize then found = x return end
                for _, c in ipairs(x.Children or {}) do walk(c) end
            end
            walk(m.tree.RootWidget)
            return found and found.TextValue
        end
    """)
    ok &= check("the window shows the title it comes with: One-Armed-Menu", lua.eval("TitleText(Menu()) == 'One-Armed-Menu'"))
    lua.execute("""
        for _, r in ipairs(Lines()) do if r.line.kind == "header" and r.line.text == "Text" and not Menu().expanded["look text"] then Click(r.wide) end end
        FindLine("Title").input:SetText(FText("Heist Tools")); ClickChip("Save and apply")
    """)
    ok &= check("a Title saved in Settings is what the window shows", lua.eval("TitleText(Menu()) == 'Heist Tools'"))
    lua.execute('Click(FindLine("Title").chips[1].button)')
    lua.execute("""
        for _, r in ipairs(Lines()) do if r.line.kind == "header" and r.line.text == "Size and layout" and not Menu().expanded["look layout"] then Click(r.wide) end end
        FindLine("Window height (normal size)").input:SetText(FText("1400")); ClickChip("Save and apply")
        m = Menu(); FinishAnims(m)
        Drag(m.dragBar, 900, 20, 910, 25)
    """)
    ok &= check("a window taller than the screen (drawn as tall as the screen) still moves with its title bar on the screen",
                lua.eval("m.place.y <= 0 + 50 and m.place.y >= 0"))
    lua.execute('Click(FindLine("Window height (normal size)").chips[3].button)')
    lua.execute("""
        for _, r in ipairs(Lines()) do if r.line.kind == "header" and r.line.text == "Colours" and not Menu().expanded["look colours"] then Click(r.wide) end end
        FindLine("Buttons (filled style)").input:SetText(FText("#000000")); ClickChip("Save and apply")
    """)
    ok &= check("a black button colour still gets a lighter colour under the mouse",
                lua.eval("Menu().style.chip[1] >= 0.01 and Menu().style.chipHover[1] > Menu().style.chip[1]"))
    lua.execute('Click(FindLine("Buttons (filled style)").chips[1].button)')
    lua.execute('FindLine("Most copies one spawn makes").input:SetText(FText("600")); ClickChip("Save and apply"); Console("opengui")')
    saved_after = open(settings_path, encoding="utf-8").read()

    # --- only one menu window, whatever happened before
    lua.execute("""
        Console("opengui"); first = Menu()
        -- the free camera: the local player drives another controller in the same map
        DCC.Player = PC.Player; DCC.bShowMouseCursor = false
        function DCC:GetAddress() return 99 end
        LP = { IsValid = function() return true end, PlayerController = DCC }
        PC.Player.PlayerController = DCC
        Console("opengui")
    """)
    ok &= check("the opengui key after switching to the free camera closes the open menu (and takes it off the screen)",
                lua.eval("Menu() == nil and first.destroyed and not first.root.InViewport and UMG.inputMode == 'game'"))
    lua.execute('Console("opengui"); second = Menu()')
    ok &= check("pressed again it opens a new one for the free camera, and it gets its per-frame updates from your character's controller",
                lua.eval("second ~= nil and second.open and second.pc == DCC and second.tickAddress == 42"))
    lua.execute('second.clicks = 1; Hovered = second.closeChip.button; Hooks["/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"](Param(PC)); Hovered = nil')
    ok &= check("so its buttons work (the X closes it)", lua.eval("not second.open"))
    lua.execute('Console("opengui")')
    lua.execute("""
        Console("opengui")
        LP = nil; PC.Player.PlayerController = PC
        -- a window an earlier config lost track of, still on the screen
        stray = WBL:Create(PC, FakeClass("/Game/UI/Cursors/HammerCursor.HammerCursor_C"), PC); stray:AddToViewport(50)
        OARCommands.State.menu = nil
        Console("opengui")
        onScreen = 0
        for _, w in ipairs(UMG.windows) do if w.InViewport then onScreen = onScreen + 1 end end
    """)
    ok &= check("any other menu window still on the screen is taken off it: only one window", lua.eval("onScreen == 1 and not stray.InViewport"))

    # --- the ESP: guards, police, civilians and players marked through walls
    lua.execute("""
        -- engine pieces the ESP uses
        GS = { IsValid = function() return true end }
        Sight = {}                                        -- which actors you can see directly (line of sight)
        function GS:GetPlayerController(ctx, i) assert(i == 0); return PC end
        WorldTime = 100                                   -- the world's clock (a new map starts it again)
        function GS:GetRealTimeSeconds(w) return WorldTime end
        -- engine functions and classes the ESP keeps (permanent /Script objects)
        GetLocFn = setmetatable({ IsValid = function() return true end }, { __call = function(_, a) return a:K2_GetActorLocation() end })
        for _, k in ipairs({ "SkeletalMeshComponent", "StaticMeshComponent", "ChildActorComponent" }) do
            EngineKinds[k] = { EngineName = k, IsValid = function() return true end }
        end
        Owners = {}                                       -- who each overlay was made for
        local create = WBL.Create
        function WBL:Create(world, cls, pc)
            local w = create(self, world, cls, pc)
            if cls.Path:find("Pressed", 1, true) then Owners[#Owners + 1] = pc end
            return w
        end
        function PC:LineOfSightTo(actor, vp, alt) assert(vp.X == 0 and alt == false); return Sight[actor:GetAddress()] == true end
        KMatL = { IsValid = function() return true end }
        function KMatL:CreateDynamicMaterialInstance(ctx, parent, name, flags)
            assert(name == "OARCommands_EspOutline" and flags == 0)
            Copy = { Params = {}, Parent = parent }
            function Copy:IsValid() return true end
            function Copy:GetFullName() return "MaterialInstanceDynamic /Game/Maps/Bank.Bank:PersistentLevel.Highlight.OARCommands_EspOutline" end
            function Copy:SetVectorParameterValue(n, c) assert(c.R and c.A); self.Params[n] = c end
            function Copy:SetScalarParameterValue(n, v) assert(type(v) == "number"); self.Params[n] = v end
            return Copy
        end
        local find = StaticFindObject
        function StaticFindObject(path)
            if path == "/Script/Engine.Default__GameplayStatics" then return GS end
            if path == "/Script/Engine.Default__KismetMaterialLibrary" then return KMatL end
            if path == "/Script/Engine.Actor:K2_GetActorLocation" then return GetLocFn end
            return find(path)
        end
        -- the heist map's outline effect: a PostProcessVolume holding the game's outline material
        Original = { IsValid = function() return true end,
                     GetFullName = function() return "MaterialInstanceConstant /Game/Mats/HighlightMat_Inst.HighlightMat_Inst" end }
        Entry = { Weight = 1.0, Object = Original }
        Volume = { IsValid = function() return true end, GetAddress = function() return 880 end,
                   Settings = { WeightedBlendables = { Array = MakeArray({ Entry }) } } }
        local findAll = FindAllOf
        function FindAllOf(name)
            if name == "PostProcessVolume" then return { Volume } end
            return findAll(name)
        end
        -- the camera: at 0,0,0 looking along X, 90 degrees wide; 1920 x 1080
        PC.PlayerCameraManager.GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end
        PC.PlayerCameraManager.GetCameraRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end
        PC.PlayerCameraManager.GetFOVAngle = function() return 90 end
        PC.PlayerCameraManager.ViewTarget = { Target = Pawn }
        SavedControlRotation = PC.GetControlRotation
        function PC:GetControlRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
        -- NPCs as the game has them
        function Npc(address, className, x, fields)
            local n = fields or {}
            n.Health = n.Health or 100
            n.Pos = { X = x, Y = 0, Z = 0 }
            function n:IsValid() return true end
            function n:GetAddress() return address end
            function n:GetClass() return { GetFName = function() return { ToString = function() return className end } end } end
            function n:K2_GetActorLocation() return self.Pos end
            n.CapsuleComponent = { GetScaledCapsuleHalfHeight = function() return 88 end }
            n.Mesh = MeshPart("SkeletalMeshComponent")
            n.BlueprintCreatedComponents = MakeArray(n.Parts or {})
            function n:GetWorld() return World end
            return n
        end
        -- a mesh part (or another component) of an actor
        function MeshPart(kind)
            local m = { bRenderCustomDepth = false, Kind = kind }
            function m:IsValid() return true end
            function m:IsA(cls) return cls.EngineName == self.Kind end
            function m:SetRenderCustomDepth(on) self.bRenderCustomDepth = on end
            function m:SetCustomDepthStencilValue(v) self.Stencil = v end
            return m
        end
        NPC_TICK, NPC_DIE = "/Game/BP/NPC/NPCBase.NPCBase_C:ReceiveTick", "/Game/BP/NPC/NPCBase.NPCBase_C:Die"
        function NpcTick(n) Hooks[NPC_TICK](Param(n)) end
        function Frame() Hooks["/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"](Param(PC)) end
        function E() return OARCommands.State.esp end
        function Open() if not (Menu() and Menu().open) then Console("opengui") end end
        function Shut() if Menu() and Menu().open then Console("opengui") end end
        function Expand(key, title) if not Menu().expanded[key] then ClickLine(title) end end
        -- a line of one group (several groups have lines of the same name)
        function RowIn(group, label)
            for _, r in ipairs(Lines()) do if r.line.group == group and r.line.label == label then return r end end
        end
        function ChipIn(group, label, text)
            for _, c in ipairs(RowIn(group, label).chips) do if c.text.TextValue == text then return c end end
        end
        -- a group's ESP type: Box, Silhouette or Both
        function SetType(key, title, kind)
            Open(); if Menu().tabs[Menu().tab].name ~= "ESP" then Tab("ESP") end
            Expand(key, title); Click(ChipIn(key, "ESP type", kind).button); Shut()
        end
        WasOpen, WasTab = Menu() and Menu().open, Menu() and Menu().tabs[Menu().tab].name
        -- another player, in the game's list of players
        Buddy = MakePawn(720)
        Buddy.Pos = { X = 2000, Y = 0, Z = 0 }
        function Buddy:K2_GetActorLocation() return self.Pos end
        Buddy.CapsuleComponent = { GetScaledCapsuleHalfHeight = function() return 88 end }
        Buddy.Mesh = MeshPart("SkeletalMeshComponent")
        Buddy.BlueprintCreatedComponents = MakeArray({})
        BuddyState = { PawnPrivate = Buddy, IsValid = function() return true end, GetAddress = function() return 721 end,
                       PlayerNamePrivate = FStr("Buddy") }
        MyState = { PawnPrivate = Pawn, IsValid = function() return true end, GetAddress = function() return 501 end,
                    PlayerNamePrivate = FStr("Me") }
        World.GameState = { PlayerArray = MakeArray({ MyState, BuddyState }), PowerMultiplier = 1.0 }
        World.IsValid = function() return true end
        Log = {}
    """)
    lua.execute('Console("esp")')
    ok &= check("esp turns the ESP on and saves it in settings.lua",
                any("ESP on" in m for m in values(g.Log)) and "esp = {" in open(settings_path, encoding="utf-8").read()
                and "on = true" in open(settings_path, encoding="utf-8").read().split("esp = {")[1])
    lua.execute("""
        Frame()                                           -- the first frame: the NPCs' event is hooked
        E().removedAt = -10                               -- (a second has passed: the overlay can be made)
        Guard = Npc(9001, "NPC_Guard_C", 1000)
        Swat = Npc(9002, "NPC_Police_Swat_C", 1500, { Health = 100 })
        Alert = Npc(9003, "NPC_Guard_C", 1200, { ["Alert?"] = true })
        Behind = Npc(9004, "NPC_Guard_C", -1000)
        Far = Npc(9005, "NPC_Guard_C", 50000)
        for _, n in ipairs({ Guard, Swat, Alert, Behind, Far }) do NpcTick(n) end
        Frame()
        Cards = E().overlay.cards
        function CardOf(text)                             -- in the overlay of now (it is made again now and then)
            for _, c in ipairs(E().overlay and E().overlay.cards or {}) do if c.shown and c.nameValue == text then return c end end
        end
    """)
    ok &= check("the NPCs' own per-frame event is hooked, and the overlay is a separate see-through widget over the game",
                lua.eval("Hooks[NPC_TICK] ~= nil and Hooks[NPC_DIE] ~= nil and #UMG.overlays == 1 and UMG.overlays[1].InViewport "
                         "and UMG.overlays[1].Visibility == 3 and UMG.overlays[1].WidgetTree.RootWidget.ClassName == 'CanvasPanel'"))
    ok &= check("a guard 10 m ahead gets a box where the engine would draw it, with its name and distance",
                lua.eval("""(function()
                    local c = CardOf("Guard")
                    local o = c.slot.Offsets
                    local function near(a, b) return math.abs(a - b) < 0.01 end
                    return near(o.Left, 924.5184) and near(o.Top, 455.52) and near(o.Right, 70.9632) and near(o.Bottom, 168.96)
                        and c.infoValue == "10 m" and c.vis.edge1 and not c.vis.corner1 and c.vis.hpFill and not c.vis.fill
                end)()"""))
    ok &= check("each kind of NPC is named, and a guard that is alert gets the warning colour",
                lua.eval("CardOf('SWAT') ~= nil and CardOf('Guard (alert)') ~= nil "
                         "and CardOf('Guard').edges[1].Brush.G > 0.4 and CardOf('Guard (alert)').edges[1].Brush.G < 0.1"))
    ok &= check("the health bar shows what is left (a SWAT with 100 of the 125 the game gives it at this power)",
                lua.eval("math.abs(CardOf('SWAT').hpSlot.Min.Y - (1 - 16 / 20)) < 0.001"))
    ok &= check("other players come from the game's list of players, by name; not you, nothing behind you, nothing out of range",
                lua.eval("CardOf('Buddy') ~= nil and CardOf('Me') == nil and E().shown == 4"))
    lua.execute('Log = {}; Open(); Tab("ESP")')
    ok &= check("the ESP tab: on, with a group per kind of target",
                lua.eval("FindChip('Turn off') ~= nil and FindLine('Guards') ~= nil and FindLine('Police specials') ~= nil "
                         "and FindLine('Civilians  (off)') ~= nil and FindLine('Silhouettes through walls') ~= nil"))
    lua.execute("""
        Expand("esp guard", "Guards")
        FindLine("Colour").input:SetText(FText("#00ff00")); Click(FindLine("Colour").chips[1].button)
        ClickChip("Corners")
        Click(FindLine("Fill the box").chips[1].button)
        ClickChip("Bottom")
        Shut()
        NpcTick(Guard); NpcTick(Swat); NpcTick(Alert); Frame()
    """)
    ok &= check("a group's colour, box style, fill and line change at once and are saved",
                lua.eval("""(function()
                    local c = CardOf("Guard")
                    return c.edges[1].Brush.G == 1 and c.edges[1].Brush.R == 0 and c.vis.corner1 and not c.vis.edge1 and c.vis.fill
                        and c.fill.Brush.A == 0.2 and c.lineShown and c.lineSlot.Offsets.Left == 960 and c.lineSlot.Offsets.Top == 1079
                        and math.abs(c.line.Angle - math.deg(math.atan(624.48 - 1080, 960 - 960))) < 0.01
                end)()""") and 'guardColor = "#00ff00"' in open(settings_path, encoding="utf-8").read())
    lua.execute("""
        Open(); Expand("esp guard", "Guards")
        ClickChip("No box")
        Click(FindLine("Show them").chips[2].button)
        Shut()
        NpcTick(Guard); NpcTick(Swat); Frame()
    """)
    ok &= check("a group turned off is not shown", lua.eval("CardOf('Guard') == nil and CardOf('SWAT') ~= nil"))
    lua.execute("""
        Open(); Expand("esp guard", "Guards"); Click(FindLine("Show them").chips[1].button); ClickChip("Box")
        Expand("esp look", "Look"); ClickChip("Hide")
        Shut()
        Sight[9001] = true
        NpcTick(Guard); NpcTick(Swat); Frame()
    """)
    ok &= check("targets you can see directly can be hidden (only the ones behind walls are marked)",
                lua.eval("CardOf('Guard') == nil and CardOf('SWAT') ~= nil"))
    lua.execute("""
        Sight = {}
        Open(); Expand("esp look", "Look"); ClickChip("Show"); Shut()
        SetType("esp guard", "Guards", "Both")
        SetType("esp police", "Police", "Silhouette")
        SetType("esp player", "Other players", "Silhouette")
        NpcTick(Guard); NpcTick(Swat); Frame()
    """)
    ok &= check("silhouettes: a copy of the game's outline material in the ESP's two colours takes the effect's place",
                lua.eval("Entry.Object == Copy and Copy.Parent == Original and Copy.Params.Color1.R == 1 and Copy.Params.Color1.G < 0.1 "
                         "and Copy.Params.Color.G > 0.5 and Copy.Params.LineWidth == 2 and Copy.Params.EdgeAngleFalloff == 100"))
    ok &= check("silhouettes per group: guards and police in the first colour, other players in the second",
                lua.eval("Guard.Mesh.bRenderCustomDepth and Guard.Mesh.Stencil == 1 and Swat.Mesh.Stencil == 1 "
                         "and Buddy.Mesh.bRenderCustomDepth and Buddy.Mesh.Stencil == 0"))
    ok &= check("ESP type: Both keeps the box, Silhouette has none",
                lua.eval("CardOf('Guard').vis.edge1 and not CardOf('SWAT').vis.edge1 and not CardOf('SWAT').vis.corner1"))
    lua.execute("""
        Open(); Expand("esp guard", "Guards"); Click(ChipIn("esp guard", "Silhouette colour", "Second").button); Shut()
        NpcTick(Guard); NpcTick(Swat); Frame()
    """)
    ok &= check("a group's silhouette can take the second colour (at once)", lua.eval("Guard.Mesh.Stencil == 0 and Swat.Mesh.Stencil == 1"))
    lua.execute("""
        Open(); Expand("esp guard", "Guards"); Click(ChipIn("esp guard", "Silhouette colour", "First").button); Shut()
        Open(); Expand("esp glow", "Silhouettes through walls"); Click(ChipIn("esp glow", "Style", "Filled").button); Shut()
        NpcTick(Guard); Frame()
    """)
    ok &= check("Filled: a thick band inside the body (the effect's inner side, made thicker)",
                lua.eval("Copy.Params.EdgeAngleFalloff == -100 and Copy.Params.LineWidth == 20"))
    lua.execute("""
        Open(); Expand("esp glow", "Silhouettes through walls"); Click(ChipIn("esp glow", "Style", "Outline").button); Shut()
        Objects.NPCBase_C = { Guard, Swat, Alert, Behind, Far }
        Characters = { Buddy }
        SetType("esp guard", "Guards", "Box")
        SetType("esp police", "Police", "Box")
        SetType("esp player", "Other players", "Box")
        Frame()
    """)
    ok &= check("no silhouettes left: the game's own material is back and every mark the ESP made is taken off",
                lua.eval("Entry.Object == Original and not Guard.Mesh.bRenderCustomDepth and not Swat.Mesh.bRenderCustomDepth "
                         "and not Buddy.Mesh.bRenderCustomDepth"))
    lua.execute("""
        -- a civilian: its body is its clothes (actors it carries) and its hair (a mesh part)
        Shirt = MeshPart("SkeletalMeshComponent")
        ShirtActor = { IsValid = function() return true end, BlueprintCreatedComponents = MakeArray({ Shirt }) }
        Holder = MeshPart("ChildActorComponent"); Holder.ChildActor = ShirtActor
        Hair = MeshPart("StaticMeshComponent")
        Civ = Npc(9010, "Civilian_NPC_C", 1300, { Parts = { Holder, Hair } })
        Open(); Expand("esp civilian", "Civilians  (off)"); Click(RowIn("esp civilian", "Show them").chips[1].button); Shut()
        SetType("esp civilian", "Civilians", "Silhouette")
        SetType("esp player", "Other players", "Silhouette")
        NpcTick(Civ); Frame()
    """)
    ok &= check("silhouettes: every mesh of a target is marked, also the ones of the actors it carries (a civilian's clothes and hair)",
                lua.eval("Civ.Mesh.bRenderCustomDepth and Shirt.bRenderCustomDepth and Hair.bRenderCustomDepth and Shirt.Stencil == 0 "
                         "and Holder.bRenderCustomDepth == false"))
    lua.execute("""
        Buddy["Downed?"] = true
        Frame(); Frame(); Frame(); Frame(); Frame(); Frame()       -- its state is read again
        Objects.NPCBase_C = { Civ }; Characters = { Buddy }
        SetType("esp civilian", "Civilians", "Box")
        SetType("esp player", "Other players", "Box")
        Frame()
    """)
    ok &= check("silhouettes off: the clothes are unmarked too, and a downed teammate keeps the game's own outline",
                lua.eval("not Shirt.bRenderCustomDepth and not Hair.bRenderCustomDepth and Buddy.Mesh.bRenderCustomDepth and Buddy.Mesh.Stencil == 0"))
    lua.execute("""
        Buddy["Downed?"] = false
        Open(); Expand("esp civilian", "Civilians"); Click(RowIn("esp civilian", "Show them").chips[2].button); Shut()
        Twin = Npc(9011, "NPC_Police_Shield_C", 1001)
        NpcTick(Guard); NpcTick(Twin); Frame()
        ShieldCard = CardOf("Shield")
        Twin.Pos = { X = 999, Y = 0, Z = 0 }               -- now nearer than the guard
        NpcTick(Guard); NpcTick(Twin); Frame()
    """)
    ok &= check("a target keeps its card when targets swap places by distance (nothing to change but places)",
                lua.eval("CardOf('Shield') == ShieldCard"))
    lua.execute("""
        Before = E().overlay.root
        Open(); Expand("esp look", "Look"); Click(FindLine("Line thickness").chips[2].button); Shut()
        NpcTick(Guard); Frame()
    """)
    ok &= check("a new line thickness: the old overlay is taken off the screen and a new one is made",
                lua.eval("not Before.InViewport and E().overlay ~= nil and E().overlay.root ~= Before and E().overlay.thickness == 3"))
    lua.execute("""
        Open(); Expand("esp look", "Look"); Click(FindLine("Line thickness").chips[4].button); Shut()
        -- the free camera: the local player drives the camera's controller, yours has no player
        DCC.PlayerCameraManager = PC.PlayerCameraManager
        function DCC:GetAddress() return 99 end
        DCC.Player = PC.Player
        LP = { IsValid = function() return true end, PlayerController = DCC }
        E().lp = nil
        Hooks["/Script/UMG.WidgetLayoutLibrary:RemoveAllWidgets"](); E().removedAt = -10
        NpcTick(Guard); Frame()
    """)
    ok &= check("in the free camera the overlay is made for the camera's controller (yours has no player to show it)",
                lua.eval("Owners[#Owners] == DCC and E().overlay ~= nil"))
    lua.execute("""
        LP = nil; E().lp = nil; DCC.Player = nil
        WorldTime = 5                                     -- a map loaded fresh, at the old one's address
        Frame()
    """)
    ok &= check("a map loaded fresh at the old map's address is still noticed (its clock started again)",
                lua.eval("E().overlay == nil and E().samples[9001] == nil"))
    lua.execute('E().removedAt = -10; NpcTick(Guard); NpcTick(Swat); Hooks[NPC_DIE](Param(Swat)); Frame()')
    ok &= check("an NPC that dies drops off at once", lua.eval("CardOf('SWAT') == nil"))
    lua.execute("""
        Before = E().frame
        Hooks["/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"](Param(GuestPC))
    """)
    ok &= check("on the host, a guest's controller ticking does not run the ESP (only your own does)",
                lua.eval("E().frame == Before"))
    lua.execute('OverlaysBefore = #UMG.overlays; Hooks["/Script/UMG.WidgetLayoutLibrary:RemoveAllWidgets"](); Frame()')
    ok &= check("the game clearing the screen: the overlay is forgotten (the engine frees it), not made again at once",
                lua.eval("E().overlay == nil and #UMG.overlays == OverlaysBefore"))
    lua.execute('E().removedAt = -10; NpcTick(Guard); Frame()')
    ok &= check("a second later it is made again", lua.eval("#UMG.overlays == OverlaysBefore + 1 and E().overlay ~= nil"))
    lua.execute("""
        Old = UMG.overlays[#UMG.overlays]
        EspWorld = { GetAddress = function() return 3300 end, GameState = World.GameState, IsValid = function() return true end }
        PC.GetWorld = function() return EspWorld end
        Frame()
    """)
    ok &= check("a new map: everything from the old one is forgotten without being touched",
                lua.eval("E().samples[9001] == nil and E().overlay == nil and Old.InViewport"))
    lua.execute("""
        PC.GetWorld = function() return World end
        Frame()                                           -- back in the first map (a new world for the ESP)
        E().removedAt = -10; Frame()
        CAM_TICK = "/Game/BP/Camera/CameraBP.CameraBP_C:ReceiveTick"
        if not Hooks[CAM_TICK] then E().camerasHooked = E().hookCameras() end
        -- a security camera: a wall mount with an arm and a head (no Mesh); it may be spotting someone
        function Camera(address, number, x, spotting)
            local c = { CamNumber = number, ["Destroyed?"] = false, EMPed = false, ["Ignored?"] = false, ["Possessed?"] = false }
            function c:IsValid() return true end
            function c:GetAddress() return address end
            c.CameraHead = MeshPart("StaticMeshComponent")
            c.CameraHead.K2_GetComponentLocation = function() return { X = x, Y = 0, Z = 0 } end
            c.CameraArm = MeshPart("StaticMeshComponent")
            c.BlueprintCreatedComponents = MakeArray({ c.CameraArm, c.CameraHead })
            c.SpotPlayerComponent = { SpottedPlayer = spotting and Buddy or Invalid }
            return c
        end
        Cam = Camera(9200, 2, 1100)
        Spotter = Camera(9201, 3, 1400, true)
        Hooks[CAM_TICK](Param(Cam)); Hooks[CAM_TICK](Param(Spotter)); Frame()
    """)
    ok &= check("camera ESP: security cameras get a square box at their head, named by their number",
                lua.eval("""(function()
                    local c = CardOf("Camera 3")
                    local o = c and c.slot.Offsets
                    return o ~= nil and math.abs(o.Right - o.Bottom) < 0.001 and c.infoValue == "11 m" and not c.vis.hpFill
                end)()"""))
    ok &= check("camera ESP: a camera spotting someone says so in the warning colour",
                lua.eval("CardOf('Camera 4 (spotting)') ~= nil and CardOf('Camera 4 (spotting)').edges[1].Brush.G < 0.1 "
                         "and CardOf('Camera 3').edges[1].Brush.B > 0.5"))
    lua.execute("""
        SetType("esp camera", "Cameras", "Silhouette")
        Hooks[CAM_TICK](Param(Cam)); Frame()
    """)
    ok &= check("camera silhouettes: the arm and the head are marked (cameras have no body mesh)",
                lua.eval("Cam.CameraHead.bRenderCustomDepth and Cam.CameraArm.bRenderCustomDepth and Cam.CameraHead.Stencil == 1"))
    lua.execute('Objects.CameraBP_C = { Cam, Spotter }; SetType("esp camera", "Cameras", "Box"); Hooks[CAM_TICK](Param(Cam)); Frame()')
    ok &= check("camera silhouettes off: unmarked again", lua.eval("not Cam.CameraHead.bRenderCustomDepth and not Cam.CameraArm.bRenderCustomDepth"))
    lua.execute("""
        PC.GetWorld = function() return World end
        Frame()
        Log = {}; Console("esp off"); Frame()
    """)
    ok &= check("esp off: nothing is shown", lua.eval("E().on == false") and any("ESP off" in m for m in values(g.Log)))
    lua.execute('PC.GetControlRotation = SavedControlRotation; World.GameState = nil; Objects.NPCBase_C = nil; Characters = nil')
    lua.execute('if WasOpen then Open(); if WasTab then Tab(WasTab) end else Shut() end')      # the menu as it was

    # --- notarget: guards, cameras and civilians ignore you
    lua.execute("""
        -- your character's collision as the game has it (both block the cameras' line and bullets)
        function Body()
            local b = { Responses = { [19] = 2, [14] = 2 } }
            function b:GetCollisionResponseToChannel(ch) return self.Responses[ch] or 1 end
            function b:SetCollisionResponseToChannel(ch, r) assert(type(ch) == "number" and type(r) == "number"); self.Responses[ch] = r end
            return b
        end
        Pawn.CapsuleComponent, Pawn.Mesh = Body(), Body()
        Pawn.PawnNoiseEmitter = { LastLocalNoiseVolume = 1, LastRemoteNoiseVolume = 1 }
        Pawn.Pos = { X = 0, Y = 0, Z = 0 }
        function Pawn:K2_GetActorLocation() return self.Pos end
        function Pawn:GetWorld() return World end
        MyState = { PawnPrivate = Pawn, IsValid = function() return true end, GetAddress = function() return 501 end,
                    PlayerNamePrivate = FStr("Me") }
        PC.PlayerState = MyState
        World.GameState = { PlayerArray = MakeArray({ MyState }) }
        World.IsValid = function() return true end
        Authority = true; Log = {}
        Console("notarget")
        Frame()
    """)
    ok &= check("notarget: on for you only; cameras' line and NPC bullets pass through your character, and you make no noise",
                any("No target: guards, cameras and civilians ignore you" in m for m in values(g.Log))
                and lua.eval("Pawn.CapsuleComponent.Responses[19] == 0 and Pawn.Mesh.Responses[19] == 0 and Pawn.Mesh.Responses[14] == 0 "
                             "and Pawn.PawnNoiseEmitter.LastLocalNoiseVolume == 0 and Pawn['IsSpotted?'] == true"))
    lua.execute("""
        DIST = "/Script/Engine.Actor:GetDistanceTo"
        Watcher = Npc(9300, "NPC_Guard_C", 800)
        function Watcher:HasAuthority() return true end
        Passer = Npc(9301, "Civilian_NPC_C", 800)
        function Passer:HasAuthority() return true end
    """)
    ok &= check("notarget: a guard asking how far you are is told you are far away (it neither sees nor shoots you)",
                lua.eval("PostHooks[DIST](Param(Watcher), Param(800.0)) == 100000.0"))
    ok &= check("notarget: other distances, and what others ask, are left as they are",
                lua.eval("PostHooks[DIST](Param(Watcher), Param(650.0)) == nil and PostHooks[DIST](Param(Passer), Param(800.0)) == nil"))
    lua.execute("""
        SPOT = "/Game/BP/Component/SpotPlayerComponent.SpotPlayerComponent_C:SpotPlayer"
        Calledoff = {}
        Spotter = { SpottedPlayer = Pawn }
        function Spotter:GetOwner() return Passer end
        function Spotter:ExecuteUbergraph_SpotPlayerComponent(entry) Calledoff[#Calledoff + 1] = entry end
        Hooks[SPOT](Param(Spotter))
    """)
    ok &= check("notarget: a civilian starting to spot you is called off at once, the game's own way",
                lua.eval("Calledoff[1] == 93"))
    lua.execute("""
        -- civilians see with the engine's PawnSensing: 2000 units, a 55 degree cone, eyes 64 up
        function Seeing(address, x, yaw)
            local c = Npc(address, "Civilian_NPC_C", x, { BaseEyeHeight = 64 })
            c.Yaw = yaw
            function c:HasAuthority() return true end
            function c:K2_GetActorRotation() return { Pitch = 0, Yaw = self.Yaw, Roll = 0 } end
            c.PawnSensing = { bSeePawns = true, SightRadius = 2000, PeripheralVisionAngle = 55, IsValid = function() return true end }
            return c
        end
        Facing = Seeing(9303, 1000, 180)        -- 1000 units away, looking straight at you
        Away = Seeing(9304, 1000, 0)            -- as near, looking the other way
        Far = Seeing(9305, 5000, 180)           -- looking at you from beyond its sight
        Frame()
        for _, c in ipairs({ Facing, Away, Far }) do Hooks[NPC_TICK](Param(c)) end
    """)
    ok &= check("notarget: a civilian looking at you sees only up to just short of you (so it never starts to spot you)",
                abs(lua.eval("Facing.PawnSensing.SightRadius") - ((1000 ** 2 + 64 ** 2) ** 0.5 - 150)) < 0.01
                and lua.eval("Away.PawnSensing.SightRadius == 2000 and Far.PawnSensing.SightRadius == 2000"))
    lua.execute("""
        local had, open = Menu() ~= nil, Menu() ~= nil and Menu().open
        OARCommands.State.npcHooked = true
        Console("reloadconfig")                 -- throws the menu away; it is opened again below as it was
        Facing.Yaw = 0; Hooks[NPC_TICK](Param(Facing))
        if had then Console("opengui"); if not open then Console("opengui") end end
    """)
    ok &= check("notarget: once you are not in front of it, the civilian's own sight range is back (also after reloadconfig)",
                lua.eval("Facing.PawnSensing.SightRadius == 2000"))
    lua.execute("Facing.Yaw = 180; Hooks[NPC_TICK](Param(Facing)); Objects.NPCBase_C = { Facing, Away, Far }")
    lua.execute("""
        Cop = Npc(9302, "NPC_Police_regular_C", 900, { TargetPlayer = Pawn, ["Sensing?"] = true })
        function Cop:HasAuthority() return true end
        Hooks[NPC_TICK](Param(Cop))
    """)
    ok &= check("notarget: an officer that picked you as its target drops it",
                lua.eval("Cop.TargetPlayer == Invalid and Cop['Sensing?'] == false"))
    lua.execute('Log = {}; Console("notarget"); Frame()')
    ok &= check("notarget again: off, and your character is as it was (and every civilian's sight range)",
                any("No target is off" in m for m in values(g.Log))
                and lua.eval("Facing.PawnSensing.SightRadius == 2000")
                and lua.eval("Pawn.CapsuleComponent.Responses[19] == 2 and Pawn.Mesh.Responses[19] == 2 and Pawn.Mesh.Responses[14] == 2 "
                             "and Pawn['IsSpotted?'] == false and PostHooks[DIST](Param(Watcher), Param(800.0)) == nil"))
    lua.execute('OARCommands.State.share.silentUntil = 0; Authority = false; Sent = {}; QueueDelays = true; Log = {}; Console("notarget")')
    ok &= check("guest: notarget goes to the host (the host's guards are the ones that must not see you)",
                g.Sent[1].endswith(" notarget") and any("Asked the host" in m for m in values(g.Log)))
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok No target"); RunDelays(); QueueDelays = false; Authority = true')
    lua.execute('World.GameState = nil; PC.PlayerState = nil; Objects.NPCBase_C = nil')
    lua.execute('OARCommands.Exports.Share.Notice("hello from the host")')
    ok &= check("notices (the host's answers) show at the bottom of the menu", "hello from the host" in g.Menu().status.TextValue)

    removeAll = "/Script/UMG.WidgetLayoutLibrary:RemoveAllWidgets"
    lua.execute(f'Hooks["{removeAll}"](Param(WBL))')
    ok &= check("when the game clears the screen (loading, death, win screen) the menu closes first and gives the game its keys back",
                lua.eval("not Menu().open and Menu().destroyed and UMG.inputMode == 'game' and PC.bShowMouseCursor == false"))
    lua.execute("""
        old = Menu()
        -- the engine frees that window: touching it now would read freed memory
        old.root.Freed = true; for k, v in pairs(old.root) do if type(v) == "function" then old.root[k] = function() error("touched a freed widget") end end end
        Console("opengui")
    """)
    ok &= check("opengui then builds a new window without touching the freed one",
                lua.eval("Menu() ~= old and Menu().open and Menu().root.InViewport and UMG.inputMode == 'ui'"))
    lua.execute(f'Hooks["{removeAll}"](Param(WBL)); Console("opengui")')
    lua.execute("""
        old = Menu()
        old.root.Freed = true; for k, v in pairs(old.root) do if type(v) == "function" then old.root[k] = function() error("touched a freed widget") end end end
        OtherWorld = { GetAddress = function() return 3100 end }
        PC.GetWorld = function() return OtherWorld end
        Console("opengui")
    """)
    ok &= check("after a map change (another world) opengui builds a new window without touching the old one",
                lua.eval("Menu() ~= old and Menu().open"))
    lua.execute("""
        -- leaving a heist: the engine frees the game's widget class the menu is made from, and the
        -- next map loads a new one. Asking the freed one anything would read freed memory.
        Console("opengui"); old = Menu()
        local freed = FakeClass("/Game/UI/Cursors/HammerCursor.HammerCursor_C")
        for k, v in pairs(freed) do if type(v) == "function" then freed[k] = function() error("touched a freed class") end end end
        Classes["/Game/UI/Cursors/HammerCursor.HammerCursor_C"] = nil
        Lobby2 = { GetAddress = function() return 3200 end }
        PC.GetWorld = function() return Lobby2 end
        Log = {}
        Console("opengui")
    """)
    ok &= check("in the lobby after a heist opengui builds the window from the class the lobby has, never the freed one",
                lua.eval("Menu() ~= old and Menu().open") and not any("failed" in m for m in values(g.Log)))
    lua.execute("""
        -- a guest whose host changes the map while the menu is open: no RemoveAllWidgets, the window
        -- is freed with the old map, and Escape, a notice or a click must not touch it
        old = Menu()
        old.root.Freed = true; for k, v in pairs(old.root) do if type(v) == "function" then old.root[k] = function() error("touched a freed widget") end end end
        for _, r in ipairs(old.rows) do r.input = nil end
        Lobby3 = { GetAddress = function() return 3300 end }
        PC.GetWorld = function() return Lobby3 end
        KeyCallbacks["KEY_ESCAPE"]()
        OARCommands.Exports.Share.Notice("after the map change")
    """)
    ok &= check("after the host changed the map, Escape and notices leave the freed window alone, and the cursor goes back",
                lua.eval("not old.open and old.destroyed and PC.bShowMouseCursor == false"))
    lua.execute('Console("opengui")')
    ok &= check("and opengui builds a new window there", lua.eval("Menu() ~= old and Menu().open"))
    lua.execute("""
        m = Menu(); m.clicks = 1; Hovered = m.closeChip.button
        Hooks["/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"](Param(GuestPC))
        Hovered = nil
    """)
    ok &= check("another player's controller ticking (on the host) does not run the menu", lua.eval("Menu().open and Menu().clicks == 1"))
    lua.execute('Menu().clicks = 0; PC.GetWorld = function() return World end; Console("opengui"); Console("opengui")')
    lua.execute('ClickChip("X")')
    ok &= check("the X closes it: the game gets its keys and mouse back at once, the window lets clicks through while it fades",
                lua.eval("not Menu().open and Menu().root.Visibility == 3 and UMG.inputMode == 'game' and PC.bShowMouseCursor == false"))
    lua.execute('FinishAnims()')
    ok &= check("then it is hidden", lua.eval("Menu().root.Visibility == 1 and Menu().root.Opacity == 0"))
    lua.execute('Calls = {}; Hovered = Menu().closeChip.button; KeyCallbacks["KEY_LEFT_MOUSE_BUTTON"](); Hovered = nil')
    ok &= check("with the menu closed the left mouse button is not counted for it", lua.eval("Menu().clicks == 0"))
    lua.execute('built = UMG.created; Console("opengui")')
    ok &= check("opening again reuses the window (nothing new is built)", lua.eval("Menu().open and UMG.created == built"))
    lua.execute('Console("opengui")')
    ok &= check("opengui again closes it", lua.eval("not Menu().open"))
    lua.execute('PC.bShowMouseCursor = true; Console("opengui"); Console("opengui")')
    ok &= check("opened where the game shows a mouse (menus), closing leaves the mouse and the game's UI input as they were",
                lua.eval("UMG.inputMode == 'gameandui' and PC.bShowMouseCursor == true and UMG.focusedNothing"))
    lua.execute('PC.bShowMouseCursor = false; UMG.inputMode = "game"')

    lua.execute('Console("bind f2 opengui"); Console("bind f3 god"); KeyDown = true; Calls = {}; KeyCallbacks["KEY_F2"]()')
    ok &= check("a key bound to opengui opens the menu", lua.eval("Menu().open"))
    lua.execute('KeyDown = false; KeyCallbacks["KEY_F3"](); KeyCallbacks["KEY_F2"]()')
    ok &= check("while the menu is open (the game gets no keys) other binds do nothing and the opengui key closes it",
                lua.eval("not Menu().open") and "god" not in values(g.Calls))
    lua.execute('KeyDown = true; Console("unbind f2"); Console("unbind f3")')
    lua.execute('Console("opengui"); KeyDown = false; KeyCallbacks["KEY_ESCAPE"](); KeyDown = true')
    ok &= check("Escape closes the menu", lua.eval("not Menu().open and UMG.inputMode == 'game'"))
    lua.execute('Calls = {}; KeyCallbacks["KEY_ESCAPE"]()')
    ok &= check("with the menu closed Escape does nothing of the mod's (the game's own pause still works)",
                lua.eval("not Menu().open") and len(g.Calls) == 0)

    lua.execute('Console("bind m opengui"); Console("opengui"); Focused = Menu().search; KeyCallbacks["KEY_M"]()')
    ok &= check("a letter bound to opengui does not close the menu while you type in its search box", lua.eval("Menu().open"))
    lua.execute('Focused = nil; KeyCallbacks["KEY_M"](); Console("unbind m")')
    ok &= check("and does when you are not typing", lua.eval("not Menu().open"))

    lua.execute('Console("opengui"); Tab("World"); Calls = {}; Click(FindLine("Free camera").chips[1].button)')
    ok &= check("Free camera closes the menu first (the free camera takes over the local player), then switches",
                lua.eval("not Menu().open and UMG.inputMode == 'game'") and values(g.Calls) == ["toggledebugcamera"])
    lua.execute("""
        Console("opengui")
        PC.Player.PlayerController = DCC        -- the free camera was turned on from the console
        DCC.bShowMouseCursor = true
        Console("opengui")
    """)
    ok &= check("closing gives the keys back through the controller the local player drives now, and the cursor back on both",
                lua.eval("DCC.bShowMouseCursor == false and PC.bShowMouseCursor == false and UMG.inputMode == 'game'"))
    lua.execute('PC.Player.PlayerController = PC; Tab("Player")')

    lua.execute('Console("opengui"); old = Menu(); Console("reloadconfig")')
    ok &= check("reloadconfig throws the old menu away (closed, off the screen); the next opengui builds it from the new config",
                lua.eval("Menu() == nil and old.destroyed and not old.root.InViewport and UMG.inputMode == 'game'"))
    lua.execute('Console("opengui")')
    ok &= check("and opengui after reloadconfig works, with the hook pointing at the new code", lua.eval("Menu() ~= old and Menu().open"))
    lua.execute('ClickChip("X")')
    ok &= check("clicks work in the rebuilt menu", lua.eval("not Menu().open"))
    ok &= check("the per-frame hook and the menu's keys were registered once each",
                g.Registrations["hook " + tick] == 1 and g.Registrations["key KEY_LEFT_MOUSE_BUTTON"] == 1
                and g.Registrations["key KEY_ESCAPE"] == 1)
    lua.execute('Objects = {}; Characters = nil')

    # --- restart
    lua2, _ = make_runtime(tmp)
    g2 = lua2.globals()
    lua2.execute('KeyCallbacks["KEY_F1"]()')
    ok &= check("binds survive a restart", values(g2.Calls) == ["god", "fly"])
    ok &= check("settings saved in the menu are used again after a restart (settings.lua)",
                lua2.eval('OARCommands.Exports.Values.SummonMax == 600') and "SummonMax = 600" in saved_after)
    ok &= check("a game restart puts the window back to normal (its place was only in memory)",
                lua2.eval('OARCommands.State.menuPlace == nil'))
    lua2.execute('Calls = {}; KeyCallbacks["KEY_X"]()')
    ok &= check("unbound X stays unbound after restart (watched from the start, but runs nothing)", len(g2.Calls) == 0)
    print("ALL PASS" if ok else "SOME FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
