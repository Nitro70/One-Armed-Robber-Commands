"""Run OARCommands' main.lua against stub UE4SS globals and check its behaviour."""
import os
import shutil
import tempfile

from lupa import LuaRuntime

SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mod", "Mods", "OARCommands", "Scripts")


def make_runtime(tmp):
    scripts = os.path.join(tmp, "OARCommands", "Scripts")
    os.makedirs(scripts, exist_ok=True)
    for f in ("main.lua", "spawnables.lua", "progress.lua", "unlockables.lua", "share.lua", "player.lua"):
        shutil.copy(os.path.join(SCRIPTS, f), os.path.join(scripts, f))
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
                ({SPACE=1, RETURN=1, ESCAPE=1, NUM_FIVE=1, FIVE=1, XBUTTON_ONE=1, OEM_THREE=1})[k])
            if ok then return "KEY_" .. k end
            return nil
        end})
        function RegisterConsoleCommandHandler(name, fn) Handlers[name] = fn end
        function RegisterKeyBind(key, fn) KeyCallbacks[key] = fn end
        Hooks = {}
        function RegisterHook(name, fn) Hooks[name] = fn; return 1, 2 end
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
        function FindAllOf(name) return { PC } end
        -- debug camera: its own controller, which the engine gives no cheat manager in hosted games
        DCC = { CheatManager = Invalid, CheatClass = CM }
        function DCC:IsValid() return true end
        function DCC:IsLocalController() return true end
        function DCC:IsInputKeyDown(k) return true end
        function DCC:WasInputKeyJustPressed(k) return false end
        LP = nil              -- the LocalPlayer; nil means "not found", like during loading
        function FindFirstOf(name) if name == "LocalPlayer" then return LP end end
        NewObjectHooks = {}
        function NotifyOnNewObject(cls, fn) NewObjectHooks[cls] = fn end
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
            if LookTarget then hit.Actor = { Get = function() return LookTarget end } end
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
        function StaticFindObject(path)
            if path:find("KismetMathLibrary", 1, true) then return KML end
            if path:sub(1, 6) == "/Game/" then
                if Loaded[path] then return FakeClass(path) end
                return Invalid
            end
            return KSL
        end
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
            function pawn:SetActorEnableCollision(on) self.Collision = on end
            function pawn:AddMovementInput(dir, v, force) self.Inputs[#self.Inputs + 1] = { z = dir.Z, v = v } end
            function pawn:ReviveClient() self.Revived = self.Revived + 1 end
            function pawn:K2_GetActorRotation() return { Pitch = 0, Yaw = 0, Roll = 0 } end
            function pawn:K2_TeleportTo(loc, rot) self.TeleportedTo = loc return true end
            return pawn
        end
        Pawn = MakePawn(500)
        PC.Pawn = Pawn
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
        function GuestRequest(text)
            Hooks["/Script/Engine.PlayerController:ServerExecRPC"](Param(GuestPC), Param(FStr(text)))
        end
        function HostReply(text) PC:ClientMessage(text) end
        function LastSentId() return Sent[#Sent]:match("^oar1 (%w+) ") end
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
    u = lua.eval('require("unlockables")')
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
    ok &= check("Space adds up input, Ctrl adds down input",
                lua.eval("Pawn.Inputs[1].z == 1 and Pawn.Inputs[1].v == 1 and Pawn.Inputs[2].v == -1"))
    lua.execute(f'KeysDown = {{ LeftShift = true }}; Hooks["{frame}"](Param(Pawn))')
    ok &= check("Shift doubles the fly speed", g.Pawn.CharacterMovement.MaxFlySpeed == 1200)
    lua.execute(f'KeysDown = {{}}; Hooks["{frame}"](Param(Pawn))')
    ok &= check("letting go of Shift goes back to normal speed", g.Pawn.CharacterMovement.MaxFlySpeed == 600)
    lua.execute('KeysDown = { LeftShift = true }; Console("noclip"); KeysDown = {}; KeyDown = true')
    ok &= check("noclip off: collision back, falling, fly speed restored",
                g.Pawn.Collision is True and g.Pawn.CharacterMovement.Mode == 3
                and g.Pawn.CharacterMovement.bCheatFlying is False and g.Pawn.CharacterMovement.MaxFlySpeed == 600)

    # --- command sharing: pure rules
    ok &= check("sharing levels: 0 off, 1 player, 2 world, 3 all but blocked", lua.eval(r"""(function()
        local S = require("share")
        return not S.Allowed(0, "summon") and S.Allowed(1, "summon") and S.Allowed(1, "destroytarget")
            and not S.Allowed(1, "slomo") and S.Allowed(2, "slomo") and not S.Allowed(2, "stat")
            and S.Allowed(3, "stat") and not S.Allowed(3, "exit") and not S.Allowed(3, "deletecloudfiles")
            and not S.Allowed(3, "setmoney") and not S.Allowed(3, "open")
    end)()"""))
    ok &= check("request format round-trips with a camera pose", lua.eval(r"""(function()
        local S = require("share")
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
    lua.execute('Messages = {}; Hooks["/Script/Engine.PlayerController:ServerExecRPC"](Param(PC), Param(FStr("oar1 ad1 summon goldbar")))')
    ok &= check("the host ignores requests from its own controller", len(g.Messages) == 0)
    lua.execute('Console("commandsharing 0")')

    # --- guest side
    lua.execute('Authority = false; QueueDelays = true; Summons = {}; Sent = {}; Console("summon goldbar 2")')
    ok &= check("guest: summon goes to the host, nothing spawns here",
                len(g.Sent) == 1 and g.Sent[1].endswith(" summon goldbar 2") and g.Sent[1].startswith("oar1 ") and len(g.Summons) == 0)
    lua.execute('HostReply("[OAR host] " .. LastSentId() .. " ok Summoning Goldbar_C x2"); RunDelays()')
    ok &= check("guest: after the host's ok nothing runs here, not even after the timeout", len(g.Summons) == 0)
    lua.execute('Console("summon goldbar 2"); HostReply("[OAR host] " .. LastSentId() .. " off"); RunDelays()')
    ok &= check("guest: host says off, so it runs here like normal", values(g.Summons) == ["Goldbar_C", "Goldbar_C"])
    lua.execute('Calls = {}; HandlerResults = {}; Sent = {}; handled = Console("god")')
    ok &= check("guest: god goes to the host", g.handled is True and g.Sent[1].endswith(" god"))
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
    lua.execute('Authority = true; QueueDelays = false')
    ok &= check("host or solo: god is left to the engine", lua.eval('Console("god")') is False)

    # --- restart
    lua2, _ = make_runtime(tmp)
    g2 = lua2.globals()
    lua2.execute('KeyCallbacks["KEY_F1"]()')
    ok &= check("binds survive a restart", values(g2.Calls) == ["god", "fly"])
    ok &= check("unbound X stays unbound after restart", g2.KeyCallbacks["KEY_X"] is None)
    print("ALL PASS" if ok else "SOME FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
