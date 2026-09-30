--[[
    Command sharing: a host lets guests who also have OARCommands run commands through the host's
    game, where they have authority.

        commandsharing [0-3]   (host) 0 off, 1 player commands, 2 player + world commands,
                               3 everything except the block list. Every launch starts at 0.
        host <command>         (guest) send any command line to the host (for level 3)

    Guest to host: PlayerController.ServerExecRPC(string), a reliable client-to-server call whose
    Validate is "return true" and whose body is empty in this shipping build, so it has no effect
    in the game unless the host's mod reads it. Host to guest: PlayerController.ClientMessage,
    which also prints the reply in the guest's console.

        request  "oar1 <id> <command line>[ @x,y,z,pitch,yaw]"   (camera pose for aimed commands)
        reply    "[OAR host] <id> ok <summary>" | "... off" | "... denied <reason>"

    Failsafe: when you are not a guest, when the host does not answer within 1.5 s, or answers off
    or denied, the command runs on your own game exactly as it would without this file. Every step
    runs in pcall; an error also means "run it yourself".
--]]
local M = {}

local PROTOCOL = "oar1"
local REPLY = "[OAR host] "
local TIMEOUT_MS = 1500
local SILENT_SECONDS = 60          -- after a host stays silent, skip it for this long
local MAX_MESSAGE = 120
local NO_REPLY = "0"               -- request id for fire-and-forget updates (noclip speed)

local function Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

M.LEVELS = { [0] = "off", "player commands", "player and world commands", "everything except the block list" }
M.PLAYER = Set({ "summon", "spawn", "summonstop", "dupe", "revive", "noclip", "god", "ghost", "fly", "walk",
                 "teleport", "destroytarget" })
M.WORLD = Set({ "destroyall", "slomo", "playersonly", "changesize" })
M.BLOCKED = Set({
    -- would close, move or cut off the host's game
    "exit", "quit", "open", "travel", "servertravel", "disconnect", "reconnect", "switchlevel", "restartlevel",
    "streammap", "demoplay", "demorec",
    -- would touch the host's files or crash it
    "exec", "deletecloudfiles", "doublefreefindercrash", "mallocframeprofiler", "purchase", "debug",
    -- this mod's commands that always stay on your own game and save
    "setmoney", "addmoney", "setlevel", "setxp", "maxskills", "unlockall", "bind", "unbind", "unbindall",
    "commandsharing", "host",
})
-- Engine cheats a guest's mod passes to the host (lowercase -> the usual capitalised spelling;
-- UE4SS matches command names exactly, so both are registered).
M.ENGINE_CHEATS = { god = "God", ghost = "Ghost", fly = "Fly", walk = "Walk", teleport = "Teleport",
                    destroytarget = "DestroyTarget", destroyall = "DestroyAll", slomo = "Slomo",
                    playersonly = "PlayersOnly", changesize = "ChangeSize" }
M.AIMED = Set({ "destroytarget", "dupe", "teleport" })

-- Is `name` (lowercase) allowed at sharing `level`? Returns true or false plus the reason.
function M.Allowed(level, name)
    if level <= 0 then return false, "off" end
    if M.BLOCKED[name] then return false, "blocked" end
    if level >= 3 or M.PLAYER[name] then return true end
    if level >= 2 and M.WORLD[name] then return true end
    return false, level == 1 and "needs commandsharing 2 or 3" or "not allowed"
end

function M.Encode(id, line, pose)
    local msg = PROTOCOL .. " " .. id .. " " .. line
    if pose then
        msg = msg .. string.format(" @%.0f,%.0f,%.0f,%.1f,%.1f", pose.x, pose.y, pose.z, pose.pitch, pose.yaw)
    end
    return msg
end

function M.Decode(text)
    local id, rest = text:match("^" .. PROTOCOL .. " (%w+) (.+)$")
    if not id then return nil end
    local line, x, y, z, p, w = rest:match("^(.-)%s+@(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
    if line then
        return id, line, { x = tonumber(x), y = tonumber(y), z = tonumber(z), pitch = tonumber(p), yaw = tonumber(w) }
    end
    return id, rest, nil
end

function M.Init(api)
    local Say = api.Say
    local level = 0                         -- host setting; not saved, every launch starts at 0
    local pending, counter = {}, 0
    local session = string.format("%04x", math.random(0, 0xffff))
    local silentUntil, active = 0, false    -- host stayed silent / last answer was ok
    local localOnly = 0                     -- >0 while a fallback runs: never relay then
    local bypass = false                    -- true while handing an engine cheat to the engine

    local function Notice(text)
        print("[OARCommands] " .. text .. "\n")
        pcall(function()
            local pc = api.LocalPlayerController()
            if pc then pc:ClientMessage("[OAR] " .. text, FName("None"), 0.0) end
        end)
    end

    api.Notice = Notice

    local function IsGuest(pc)
        local ok, auth = pcall(function() return pc:HasAuthority() end)
        return ok and auth == false
    end

    local function RunLocally(fn)
        localOnly = localOnly + 1
        local ok, err = pcall(fn)
        localOnly = localOnly - 1
        if not ok then Notice("failed: " .. tostring(err)) end
    end

    -- An engine command handed to the engine unchanged, past this mod's own handlers.
    local function RunEngine(line)
        local pc = api.LocalPlayerController()
        if not pc then return end
        api.CheatManagerFor(pc)
        local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        bypass = true
        local ok, err = pcall(function() ksl:ExecuteConsoleCommand(pc, line, pc) end)
        bypass = false
        if not ok then Notice("failed: " .. tostring(err)) end
    end
    api.RunEngine = RunEngine

    local function CameraPose()
        local pc = api.LocalPlayerController()
        local cam = pc and pc.PlayerCameraManager
        if not (cam and cam:IsValid()) then return nil end
        local loc, rot = cam:GetCameraLocation(), cam:GetCameraRotation()
        return { x = loc.X, y = loc.Y, z = loc.Z, pitch = rot.Pitch, yaw = rot.Yaw }
    end

    -- Guest: send `line` to the host. Returns true when it went out; the command then finishes by
    -- itself (the host runs it, or `fallback` runs here). Returns false when it should run here now.
    -- opts: aim (send the camera pose), onOk (run here when the host did it too).
    function M.Relay(line, Ar, fallback, opts)
        opts = opts or {}
        if localOnly > 0 then return false end
        local ok, sent = pcall(function()
            local pc = api.Robber()
            if not pc or not IsGuest(pc) then return false end
            if os.time() < silentUntil then return false end
            counter = counter + 1
            local id = session .. counter
            local msg = M.Encode(id, line, opts.aim and CameraPose() or nil)
            if #msg > MAX_MESSAGE then return false end
            pc:ServerExecRPC(msg)
            pending[id] = { line = line, fallback = fallback, onOk = opts.onOk }
            ExecuteWithDelay(TIMEOUT_MS, function()
                ExecuteInGameThread(function()
                    local p = pending[id]
                    if not p then return end
                    pending[id] = nil
                    active, silentUntil = false, os.time() + SILENT_SECONDS
                    Notice("the host did not answer, so '" .. p.line .. "' runs on your game")
                    if p.fallback then RunLocally(p.fallback) end
                end)
            end)
            return true
        end)
        return ok and sent == true
    end

    -- Guest: a one-way update while sharing is known to work (noclip speed while Shift changes).
    function M.Notify(line)
        if not active or localOnly > 0 then return end
        pcall(function()
            local pc = api.Robber()
            if pc and IsGuest(pc) then pc:ServerExecRPC(M.Encode(NO_REPLY, line)) end
        end)
    end

    -- Guest: the host's answer arrived as a ClientMessage.
    function M.HandleReply(text)
        local id, status = text:match("^%[OAR host%] (%w+) (%a+)")
        local p = id and pending[id]
        if not p then return end
        pending[id] = nil
        if status == "ok" then
            active = true
            if p.onOk then RunLocally(p.onOk) end
        else
            active = false
            Notice("the host said " .. status .. ", so '" .. p.line .. "' runs on your game")
            if p.fallback then RunLocally(p.fallback) end
        end
    end

    local function Reply(pc, id, text)
        if id == NO_REPLY then return end
        pcall(function() pc:ClientMessage(REPLY .. id .. " " .. text, FName("None"), 0.0) end)
    end

    local function PlayerName(pc)
        local ok, name = pcall(function() return pc.PlayerState.PlayerName:ToString() end)
        return ok and name or "a guest"
    end

    -- Host: run one guest command as that guest (their controller, their character, their aim).
    local function Execute(pc, name, line, pose)
        local words = {}
        for w in line:gmatch("%S+") do words[#words + 1] = w end
        table.remove(words, 1)
        if name == "summon" or name == "spawn" then return api.DoSummon(pc, words, nil) end
        if name == "summonstop" then return api.StopSummons() end
        if name == "dupe" then return api.DoDupe(pc, words, nil, pose) end
        if name == "revive" then return api.Revive(pc) end
        if name == "noclip" then
            local on = words[1] == "on"
            return api.SetNoclip(pc.Pawn, on, tonumber(words[2]), false)
        end
        if name == "destroytarget" and pose then return api.DestroyLookedAt(pc, pose) end
        if name == "teleport" and pose then return api.TeleportToLookedAt(pc, pose) end
        api.CheatManagerFor(pc)
        local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        ksl:ExecuteConsoleCommand(pc, line, pc)
        return line
    end

    -- Host: a guest's request arrived (hook on ServerExecRPC).
    function M.HandleRequest(pc, text)
        local id, line, pose = M.Decode(text)
        if not id then return end
        if pc:IsLocalController() or not pc:HasAuthority() then return end
        local name = (line:match("^(%S+)") or ""):lower()
        local allowed, why = M.Allowed(level, name)
        if not allowed then
            Reply(pc, id, why == "off" and "off" or ("denied " .. name .. ": " .. why))
            return
        end
        if id ~= NO_REPLY then Notice(PlayerName(pc) .. " ran: " .. line) end
        local ok, summary = pcall(Execute, pc, name, line, pose)
        if ok then
            Reply(pc, id, "ok " .. tostring(summary or line))
        else
            Reply(pc, id, "denied error: " .. tostring(summary))
        end
    end

    api.Command("commandsharing", function(FullCommand, Parameters, Ar)
        local n = tonumber(Parameters[1] or "")
        if n then
            n = math.floor(n)
            if n < 0 or n > 3 then Say(Ar, "Usage: commandsharing 0-3") return true end
            level = n
        end
        Say(Ar, string.format("Command sharing is %d: %s%s", level, M.LEVELS[level],
            level > 0 and " (guests with OARCommands can run these through your game; back to 0 next launch)" or ""))
        local pc = api.Robber()
        if pc and IsGuest(pc) then Say(Ar, "You are a guest here: only the host's setting counts") end
        return true
    end)

    api.Command("host", function(FullCommand, Parameters, Ar)
        local line = FullCommand:match("^%s*%S+%s+(.-)%s*$")
        if not line or line == "" then Say(Ar, "Usage: host <command>   e.g.  host stat fps") return true end
        local function here()
            local name = line:match("^(%S+)"):lower()
            local own = api.OwnCommands[name]
            if own then
                local words = {}
                for w in line:gmatch("%S+") do words[#words + 1] = w end
                table.remove(words, 1)
                own(line, words, nil)
            else
                RunEngine(line)
            end
        end
        if M.Relay(line, Ar, here, { aim = M.AIMED[(line:match("^(%S+)") or ""):lower()] }) then return true end
        here()
        return true
    end)

    -- Guest side of the engine cheats: go to the host when possible, otherwise let the engine run
    -- them as usual (returning false hands the command on unchanged).
    for lower, capital in pairs(M.ENGINE_CHEATS) do
        local function handler(FullCommand, Parameters, Ar)
            if bypass then return false end
            local ok, sent = pcall(M.Relay, FullCommand, Ar, function() RunEngine(FullCommand) end,
                { aim = M.AIMED[lower] })
            return ok and sent == true
        end
        RegisterConsoleCommandHandler(lower, handler)
        RegisterConsoleCommandHandler(capital, handler)
    end

    RegisterHook("/Script/Engine.PlayerController:ServerExecRPC", function(Context, Msg)
        local ok, err = pcall(function() M.HandleRequest(Context:get(), Msg:get():ToString()) end)
        if not ok then print("[OARCommands] command sharing request failed: " .. tostring(err) .. "\n") end
    end)
    RegisterHook("/Script/Engine.PlayerController:ClientMessage", function(Context, S)
        pcall(function()
            local text = S:get():ToString()
            if text:sub(1, #REPLY) == REPLY then M.HandleReply(text) end
        end)
    end)

    api.Share = M
end

return M
