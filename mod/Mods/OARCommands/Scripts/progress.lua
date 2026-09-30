--[[
    Value commands for OARCommands:
        setmoney <amount>      set your cash                 addmoney <amount>   add (or remove) cash
        setlevel <level>       set your level, XP back to 0   setxp <amount>      set XP within the level
        maxskills              every skill owned, researched to its top tier
        unlockall              every weapon, weapon mod, tool and armor that costs cash

    Each command changes your own RobberController and then saves through the game's own
    functions (SaveCash, SaveLevel, SaveInventoryItems). Those write the save's check field (your
    SteamID, the only thing the game verifies on load) and upload to Steam Cloud themselves, so a
    later launch does not pull an older copy back down. Coins and anything that costs coins are
    never touched: unlockables.lua only lists things bought with in-game cash.
--]]
local Unlockables = require("unlockables")

local M = {}

local MAX_VALUE = 2000000000     -- cash and level are 32-bit in the game; leave room so payouts can't overflow
local SAVE_SLOTS = { "Cash", "Level", "InventoryItems" }   -- the saves these commands rewrite

function M.Register(api)
    local Command, Say = api.Command, api.Say
    local backedUp = false

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

    -- Save slots are named <SteamID64><slot>.sav; the game builds the ID the same way.
    local function SteamID()
        local ok, id = pcall(function()
            local user = StaticFindObject("/Script/SteamCore.Default__User")
            local util = StaticFindObject("/Script/SteamCore.Default__SteamUtilities")
            local s = util:BreakSteamID(user:GetSteamID_Pure())
            if type(s) ~= "string" then s = s:ToString() end
            return s
        end)
        if ok and type(id) == "string" and id:match("^%d+$") then return id end
        return nil
    end

    -- Once per game session, before the first edit: copy the saves we are about to rewrite.
    local function CopySaves(Ar)
        local root, id = os.getenv("LOCALAPPDATA"), SteamID()
        if not root or not id then
            Say(Ar, "Could not back up your save first (Steam ID not found); the game keeps its own backup")
            return
        end
        local dir = root .. "\\OAR\\Saved\\SaveGames\\"
        local stamp = os.date("%Y%m%d-%H%M%S")
        local copied = 0
        for _, slot in ipairs(SAVE_SLOTS) do
            local name = dir .. id .. slot .. ".sav"
            local src = io.open(name, "rb")
            if src then
                local data = src:read("*a")
                src:close()
                local dst = io.open(name .. ".oarbackup-" .. stamp, "wb")
                if dst then
                    dst:write(data)
                    dst:close()
                    copied = copied + 1
                end
            end
        end
        backedUp = true
        Say(Ar, string.format("Backed up %d save files first (SaveGames, *.oarbackup-%s)", copied, stamp))
    end

    local function BackupSaves(Ar)
        if backedUp then return end
        local ok, err = pcall(CopySaves, Ar)     -- a failed backup never blocks the edit
        if not ok then Say(Ar, "Could not back up your save first: " .. tostring(err)) end
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

    -- Wrap a command: find your controller, back up once, then run the edit.
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

    local function SetCash(pc, value, Ar)
        local capped = value > MAX_VALUE
        value = math.floor(math.max(0, math.min(value, MAX_VALUE)))
        BackupSaves(Ar)
        pc.Cash = value
        pc:SaveCash()
        pc:LoadCash()       -- the same reload the shop does before a purchase; refreshes the cash shown
        Say(Ar, string.format("Cash is now %d%s", value,
            capped and " (capped at 2,000,000,000 so heist payouts can't overflow)" or ""))
    end

    Edit("setmoney", "setmoney <amount>   e.g.  setmoney 5000000", function(pc, p, Ar)
        local n = Number(p[1])
        if not n then return false end
        SetCash(pc, n, Ar)
    end)

    Edit("addmoney", "addmoney <amount>   e.g.  addmoney 100000  (negative removes)", function(pc, p, Ar)
        local n = Number(p[1])
        if not n then return false end
        SetCash(pc, pc.Cash + n, Ar)
    end)

    Edit("setlevel", "setlevel <level>   e.g.  setlevel 50", function(pc, p, Ar)
        local n = Number(p[1])
        if not n or n < 1 then return false, "level 1 or higher" end
        n = math.floor(math.min(n, MAX_VALUE))
        BackupSaves(Ar)
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
        BackupSaves(Ar)
        pc.EXP = n
        pc:SaveLevel()
        pc:LoadLevel()
        Say(Ar, "XP is now " .. n)
    end)

    Edit("maxskills", "maxskills", function(pc, p, Ar)
        local F = Unlockables.SkillFields
        local wanted, missing = {}, {}          -- class address -> skill; skills that would not load
        for _, s in ipairs(Unlockables.Skills) do
            local cls = LoadClass(s.path)
            if cls then wanted[cls:GetAddress()] = { skill = s, cls = cls } else missing[#missing + 1] = s.name end
        end
        BackupSaves(Ar)
        local owned = pc.UnlockedSkills
        -- Raise the skills you already have (tiers above the top one do nothing in the game)...
        local have = {}
        for i = 1, owned:GetArrayNum() do
            local entry = owned[i]
            local cls = entry[F.skill]
            local w = cls and cls:IsValid() and wanted[cls:GetAddress()]
            if w then
                entry[F.tier] = w.skill.tiers
                have[cls:GetAddress()] = true
            end
        end
        -- ...then append the rest. Growing the array can move it, so each new entry is filled
        -- right away and no earlier entry is touched again.
        local added = 0
        for address, w in pairs(wanted) do
            if not have[address] then
                local entry = owned[owned:GetArrayNum() + 1]     -- UE4SS grows the array by one
                entry[F.skill] = w.cls
                entry[F.tier] = w.skill.tiers
                added = added + 1
            end
        end
        pc.ResearchingSkills:Empty()
        pc:SaveLevel()
        pc:LoadLevel()
        Say(Ar, string.format("All %d skills at their top tier (%d new). They apply from your next spawn.",
            #Unlockables.Skills - #missing, added))
        if #missing > 0 then Say(Ar, "Could not load: " .. table.concat(missing, ", ")) end
    end)

    Edit("unlockall", "unlockall", function(pc, p, Ar)
        local inv = pc.ItemInventory
        local have = {}
        for i = 1, inv:GetArrayNum() do
            local cls = inv[i]
            if cls and cls:IsValid() then have[cls:GetAddress()] = true end
        end
        BackupSaves(Ar)
        local added, owned, missing = 0, 0, {}
        for _, item in ipairs(Unlockables.Gear) do
            local cls = LoadClass(item.path)
            if not cls then
                missing[#missing + 1] = item.name
            elseif have[cls:GetAddress()] then
                owned = owned + 1
            else
                inv[inv:GetArrayNum() + 1] = cls
                have[cls:GetAddress()] = true
                added = added + 1
            end
        end
        if added > 0 then pc:SaveInventoryItems() end
        Say(Ar, string.format("Added %d cash items (%d you already had): weapons, weapon mods, tools, armor", added, owned))
        if #missing > 0 then Say(Ar, "Could not load: " .. table.concat(missing, ", ")) end
    end)
end

return M
