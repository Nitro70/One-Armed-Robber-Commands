"""Run OARCommands' main.lua against stub UE4SS globals and check its behaviour."""
import os
import shutil
import tempfile

from lupa import LuaRuntime

SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mod", "Mods", "OARCommands", "Scripts")


def make_runtime(tmp):
    scripts = os.path.join(tmp, "OARCommands", "Scripts")
    os.makedirs(scripts, exist_ok=True)
    for f in ("main.lua", "spawnables.lua"):
        shutil.copy(os.path.join(SCRIPTS, f), os.path.join(scripts, f))
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
        function StaticFindObject(path)
            if path:find("KismetMathLibrary", 1, true) then return KML end
            return KSL
        end
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
