--[[
    Value commands for OARCommands:
        setmoney <amount>      set your cash                 addmoney <amount>   add (or remove) cash
        setlevel <level>       set your level, XP back to 0   setxp <amount>      set XP within the level
        maxskills              every skill owned, researched to its top tier
        unlockall              every weapon, weapon mod, tool and armor that costs cash

    Each command changes your own RobberController and then saves through the game's own
    functions (SaveCash, SaveLevel, AddInventoryItem). Those write the save's check field (your
    SteamID, the only thing the game verifies on load) and upload to Steam Cloud themselves, so a
    later launch does not pull an older copy back down. Coins and anything that costs coins are
    never touched: unlockables.lua only lists things bought with in-game cash.

    Adding to an array goes through the game's own Blueprint code (ProgressSkills,
    AddInventoryItem), never through UE4SS: in UE4SS 3.0.1, indexing one past the end of a TArray
    does not grow it but still reads or writes that slot, outside the array's memory. The only
    growth it gets right is an empty array indexed at 1.
--]]
local Unlockables = require("unlockables")

local M = {}

local MAX_VALUE = 2000000000          -- cash and level are 32-bit in the game; leave room so payouts can't overflow
local DONE_PROGRESS = 1000000000.0    -- research progress far past any skill's RequiredProgress (150 to 450)

local function Fmt(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%g", n)
end

function M.Register(api)
    local Command, Say = api.Command, api.Say

    -- Your own controller. In the debug camera the local player drives the camera's controller
    -- and your real one is parked in its OriginalControllerRef.
    local function Robber()
        local pc = api.LocalPlayerController()
        if pc and pc:GetClass():GetFName():ToString() == "DebugCameraController" then
            pc = pc.OriginalControllerRef
        end
        if pc and pc:IsValid() then return pc end
        return nil
    end

    -- Every change goes into SaveGames\OARCommands-changes.log with the old value, so it can be
    -- undone with the same commands. (The save files are named after your SteamID, which UE4SS
    -- 3.0.1 cannot read, so copying the saves themselves is not possible from here.)
    local function LogChange(text)
        pcall(function()
            local root = os.getenv("LOCALAPPDATA")
            if not root then return end
            local f = io.open(root .. "\\OAR\\Saved\\SaveGames\\OARCommands-changes.log", "a")
            if f then
                f:write(os.date("%Y-%m-%d %H:%M:%S  "), text, "\n")
                f:close()
            end
        end)
    end

    local function Number(text)
        local n = tonumber(text or "")
        if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
        return n
    end

    local function LoadClass(path)
        local cls = StaticFindObject(path)
        if cls and cls:IsValid() then return cls end
        LoadAsset(path)
        cls = StaticFindObject(path)
        if cls and cls:IsValid() then return cls end
        return nil
    end

    -- Wrap a command: find your controller, then run the edit; errors come back as a message.
    local function Edit(name, usage, fn)
        Command(name, function(FullCommand, Parameters, Ar)
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

    local function SetCash(cmd, pc, value, Ar)
        local capped = value > MAX_VALUE
        value = math.floor(math.max(0, math.min(value, MAX_VALUE)))
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

    Edit("setlevel", "setlevel <level>   e.g.  setlevel 50", function(pc, p, Ar)
        local n = Number(p[1])
        if not n or n < 1 then return false, "level 1 or higher" end
        n = math.floor(math.min(n, MAX_VALUE))
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
                r[P.progress] = DONE_PROGRESS
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
end

return M
