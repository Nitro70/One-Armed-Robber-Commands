"""Run OARCommands' main.lua against stub UE4SS globals and check its behaviour."""
import os
import shutil
import tempfile

from lupa import LuaRuntime

SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mod", "Mods", "OARCommands", "Scripts")


def make_runtime(tmp):
    scripts = os.path.join(tmp, "OARCommands", "Scripts")
    os.makedirs(scripts, exist_ok=True)
    for f in ("main.lua", "spawnables.lua", "progress.lua", "unlockables.lua"):
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
        function StaticConstructObject(cls, outer) Constructed = Constructed + 1; return CM end
        PC = { CheatManager = CM, CheatClass = CM }
        function PC:IsValid() return true end
        function PC:IsLocalController() return true end
        function PC:IsInputKeyDown(k) assert(k.KeyName) return KeyDown end
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
        function KSL:ExecuteConsoleCommand(world, cmd, pc) Calls[#Calls + 1] = cmd; CallPCs[#CallPCs + 1] = pc end
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
        Pawn = {}
        function Pawn:IsValid() return true end
        PC.Pawn = Pawn
        PC.PlayerCameraManager = { IsValid = function() return true end,
            GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end,
            GetCameraRotation = function() return {} end }
        Log = {}
        Ar = { Log = function(self, msg) Log[#Log + 1] = msg end }
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
