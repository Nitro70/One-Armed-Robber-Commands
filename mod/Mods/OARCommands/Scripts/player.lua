--[[
    revive    back up with full health, the same steps the game runs when a teammate's revive
              finishes: Health = MaxHealth, Downed? = false, ReviveClient() on your machine
              (camera colour and look limits back).
    noclip    fly through walls: WASD as usual, Space up, Ctrl down, Shift twice as fast.
              Type it again to land.

    Both act on the machine in charge of the character: yours when you host or play solo, the
    host's when you are a guest (through command sharing, see share.lua). As a guest without
    sharing they still run on your game, which the host then overrides.

    The game only moves you along your level forward and right, so flying needs its own up/down.
    That is added every frame from a hook on your character's MoveForward input event.
--]]
local M = {}

local MOVE_FALLING, MOVE_FLYING = 3, 5          -- EMovementMode
local UP = { X = 0.0, Y = 0.0, Z = 1.0 }
local KEYS_UP = { "SpaceBar" }
local KEYS_DOWN = { "LeftControl", "RightControl" }
local KEYS_FAST = { "LeftShift", "RightShift" }
local FRAME_EVENT = "/Game/BP/Player/PlayerCharacter.PlayerCharacter_C:InpAxisEvt_MoveForward_K2Node_InputAxisEvent_0"

local function Fmt(n)
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.1f", n)
end

function M.Init(api)
    local Say = api.Say
    local states = {}                -- character address -> { pawn, on, base, oldFly, fast, localInput }
    local hooked = false

    function api.Revive(pc)
        local pawn = pc and pc.Pawn
        if not (pawn and pawn:IsValid()) then return "no character to revive" end
        local down = pawn["Downed?"]
        pawn.Health = pawn.MaxHealth
        pawn["Downed?"] = false
        pawn:ReviveClient()
        return down and "revived" or "not downed, health refilled"
    end

    local function KeyDown(pc, names)
        for _, n in ipairs(names) do
            if pc:IsInputKeyDown({ KeyName = FName(n) }) then return true end
        end
        return false
    end

    -- Every frame while you control your character: Space/Ctrl up and down, Shift speed.
    local function OnFrame(pawn)
        local st = states[pawn:GetAddress()]
        if not (st and st.on and st.localInput) then return end
        local pc = api.Robber()
        if not pc then return end
        local v = (KeyDown(pc, KEYS_UP) and 1.0 or 0.0) - (KeyDown(pc, KEYS_DOWN) and 1.0 or 0.0)
        if v ~= 0 then pawn:AddMovementInput(UP, v, true) end
        local fast = KeyDown(pc, KEYS_FAST)
        if fast ~= st.fast then
            st.fast = fast
            local speed = st.base * (fast and 2 or 1)
            pawn.CharacterMovement.MaxFlySpeed = speed
            api.Share.Notify("noclip on " .. Fmt(speed))     -- a guest's host follows the speed
        end
    end

    -- The character's Blueprint must be loaded to hook it (it is in a heist, maybe not in the
    -- menu), so this is tried again every time noclip turns on until it works.
    local function HookFrames()
        if hooked then return true end
        local ok, err = pcall(function()
            RegisterHook(FRAME_EVENT, function(Self)
                pcall(OnFrame, Self:get())
            end)
        end)
        hooked = ok
        if not ok then
            print("[OARCommands] noclip: no per-frame hook yet (" .. tostring(err) .. ")\n")
        end
        return ok
    end

    -- On or off for one character. localInput: this machine reads the keys (your own character).
    -- Used for your own character and, on the host, for a guest's.
    function api.SetNoclip(pawn, on, speed, localInput)
        if not (pawn and pawn:IsValid()) then return "no character" end
        local key = pawn:GetAddress()
        local cm = pawn.CharacterMovement
        local st = states[key]
        if on then
            if not st then
                st = { pawn = pawn, oldFly = cm.MaxFlySpeed, base = cm.MaxWalkSpeed, fast = false }
                states[key] = st
            end
            st.on, st.localInput = true, localInput
            pawn:SetActorEnableCollision(false)
            cm.bCheatFlying = true
            cm:SetMovementMode(MOVE_FLYING, 0)
            cm.MaxFlySpeed = speed or st.base * (st.fast and 2 or 1)
            if localInput and not HookFrames() then
                return "noclip on (Space/Ctrl up and down need a heist map; WASD works)"
            end
            return "noclip on"
        end
        pawn:SetActorEnableCollision(true)
        cm.bCheatFlying = false
        cm:SetMovementMode(MOVE_FALLING, 0)
        if st then cm.MaxFlySpeed = st.oldFly end
        states[key] = nil
        return "noclip off"
    end

    -- On only while the character really is still flying: if the game ended it (respawn, a reset),
    -- noclip counts as off and typing it turns it back on.
    local function NoclipOn(pawn)
        local st = states[pawn:GetAddress()]
        return st ~= nil and st.on and pawn.CharacterMovement.MovementMode == MOVE_FLYING
    end

    -- `Ar` (the console's output) only lives while the command runs; results that come later,
    -- after the host answered, are printed with api.Notice instead.
    local function Out(Ar, text)
        if Ar then Say(Ar, text) else api.Notice(text) end
    end

    api.Command("revive", function(FullCommand, Parameters, Ar)
        local function here(ArNow)
            local pc = api.Robber()
            Out(ArNow, pc and api.Revive(pc) or "No local player yet")
        end
        if api.Share.Relay("revive", Ar, function() here(nil) end) then return true end
        here(Ar)
        return true
    end)

    api.Command("noclip", function(FullCommand, Parameters, Ar)
        local pc = api.Robber()
        local pawn = pc and pc.Pawn
        if not (pawn and pawn:IsValid()) then Say(Ar, "No character to noclip") return true end
        local on = not NoclipOn(pawn)
        local speed = pawn.CharacterMovement.MaxWalkSpeed
        local function here(ArNow)
            Out(ArNow, api.SetNoclip(pawn, on, on and speed or nil, true) ..
                (on and ": WASD to move, Space up, Ctrl down, Shift faster" or ""))
        end
        local line = on and ("noclip on " .. Fmt(speed)) or "noclip off"
        -- As a guest the host does it to your character too; your game does the same so both agree.
        local later = function() here(nil) end
        if api.Share.Relay(line, Ar, later, { onOk = later }) then return true end
        here(Ar)
        return true
    end)
end

return M
