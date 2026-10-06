--[[
    OAR Commands: esp.lua, the ESP: guards, police, civilians and other players marked on the
    screen, also through walls. config.lua decides what it shows (its ESP section, the ESP tab of
    the menu and the esp command); this file draws it. It is read again on every reloadconfig.

    How it works (UE4SS 3.0.1; every step checked in UE4SS's source, the game's class data and
    its scripts, 2026-10-05):
      - Nothing here keeps a game object from one frame to the next. Objects the game deletes are
        freed later, and touching a freed one (even asking whether it is valid) crashes the game.
        What is kept are numbers (positions, health, flags) by the object's address.
      - Guards, police and civilians: each one runs the base NPC's per-frame event (NPCBase
        ReceiveTick; civilians call it from their own), which config.lua hooks. The NPC hands
        itself in, alive, and its place and state are written down. A dead or tied-up NPC stops
        ticking, so it drops off by itself.
      - Players: the game's own list of players (GameState PlayerArray), read every frame.
      - Security cameras: each one runs its own per-frame event too (CameraBP ReceiveTick), hooked
        the same way. A broken camera stops ticking and drops off.
      - Where on the screen: worked out here from the camera (place, angle, field of view), the
        same maths as the engine's. The engine's own functions for it are not used: in UE4SS
        3.0.1 every call that writes a result into a table leaks a little memory.
      - Drawing: one see-through widget over the whole screen (a copy of the game's unused
        HammerCursor_Pressed widget, holding a CanvasPanel) with one "card" per target: box edges
        or corners, a fill, two labels, a health bar and a head dot, laid out inside the card
        once; every frame only the card's place and size change (one call). A line from the edge
        of the screen is a thin box turned towards the target.
      - Silhouettes through walls are the game's own outline effect (a post-process material
        placed in every heist map, drawn through walls), which outlines every mesh marked for it
        (custom depth). The ESP marks the targets' meshes and puts a copy of that material, in its
        own colours, in the effect's place. The effect has two colours: the first for meshes
        marked 1 or more, the second for meshes marked 0; each group picks one.
--]]

local Esp = {}
Esp.__index = Esp

local HOST_CLASS = "/Game/UI/Cursors/HammerCursor_Pressed.HammerCursor_Pressed_C"
local FONT = "/Engine/EngineFonts/Roboto.Roboto"
local COLLAPSED, HIT_TEST_INVISIBLE = 1, 3          -- ESlateVisibility
local HEAD_AT = 0.09                                -- the head dot, as a part of the box from its top
local CORNER = 0.25                                 -- a corner's arms, as a part of the box's side
local CLEAR = { 0, 0, 0, 0 }

-- What each kind of NPC is: its group, its name on the screen and its full health.
Esp.Kinds = {
    NPC_Guard_C = { group = "guard", label = "Guard", hp = 100 },
    NPC_Police_base_C = { group = "police", label = "Police", hp = 100 },
    NPC_Police_regular_C = { group = "police", label = "Police", hp = 100 },
    NPC_Police_Helmet_C = { group = "police", label = "Police (helmet)", hp = 100 },
    NPC_Police_Swat_C = { group = "police", label = "SWAT", hp = 125, swat = true },   -- see SwatHealth
    NPC_Police_Shield_C = { group = "police", label = "Shield", hp = 250 },
    NPC_Police_BlindingShield_C = { group = "police", label = "Blinding shield", hp = 250 },
    NPC_Police_Juggernaut_C = { group = "police", label = "Juggernaut", hp = 2500 },
    NPC_Interceptor_C = { group = "special", label = "Interceptor", hp = 200 },
    NPC_PowerboxDefuser_C = { group = "special", label = "Powerbox defuser", hp = 200 },
    Civilian_NPC_C = { group = "civilian", label = "Civilian", hp = 10 },
    NPC_Civilian_CustomClothes_C = { group = "civilian", label = "Civilian", hp = 10 },
    NPC_Cinema_C = { group = "civilian", label = "Civilian", hp = 10 },
}

--------------------------------------------------------------------------------------------------
-- Esp.New{ kit, hookNpcs, hookCameras, allOf, say }
--    kit        gui.lua (its widget pieces)
--    hookNpcs   function() -> true once config.lua's NPC hooks are in place (they can only be
--               placed once the NPC Blueprint is loaded, so this is asked again now and then)
--    hookCameras  the same for the security cameras' hook (maps without cameras never load them)
--    allOf      config.lua's AllOf (every live object of a class and its subclasses)
--    say        function(text): a message for the console
-- Then SetConf(conf) with what to show (config.lua's EspConf).
--------------------------------------------------------------------------------------------------
function Esp.New(o)
    local self = setmetatable({
        kit = o.kit, hookNpcs = o.hookNpcs, hookCameras = o.hookCameras or function() return true end,
        allOf = o.allOf, say = o.say or print,
        on = false, frame = 0, samples = {}, names = {}, glowed = {}, shown = 0,
        W = 1920, H = 1080, focal = 1000, cam = nil,
    }, Esp)
    self.wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    self.wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    self.gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    self.kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    -- an engine function called directly (name lookups skipped: it runs for every NPC every frame)
    self.getLoc = StaticFindObject("/Script/Engine.Actor:K2_GetActorLocation")
    -- the kinds of parts that are outlined
    self.meshKinds = { StaticFindObject("/Script/Engine.SkeletalMeshComponent"), StaticFindObject("/Script/Engine.StaticMeshComponent") }
    self.childKind = StaticFindObject("/Script/Engine.ChildActorComponent")
    return self
end

-- New settings. Nothing on the screen is touched here (this can run before the ESP has noticed a
-- new map): a new line thickness or text size makes the next frame build the overlay again.
function Esp:SetConf(conf)
    self.conf = conf
    self.on = conf.on
    if self.overlay then
        for _, c in ipairs(self.overlay.cards) do c.colorKey, c.look = nil, nil end
    end
end

local function Valid(o) return o ~= nil and type(o) ~= "number" and o:IsValid() end

--------------------------------------------------------------------------------------------------
-- Where things are on the screen
--------------------------------------------------------------------------------------------------
-- The camera's axes from its rotation (degrees), as the engine's rotation matrix has them.
local function Axes(rot)
    local p, y, r = math.rad(rot.Pitch), math.rad(rot.Yaw), math.rad(rot.Roll or 0)
    local SP, CP, SY, CY, SR, CR = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return { CP * CY, CP * SY, SP },
           { SR * SP * CY - CR * SY, SR * SP * SY + CR * CY, -SR * CP },
           { -(CR * SP * CY + SR * SY), CY * SR - CR * SP * SY, CR * CP }
end

-- A point in the world -> the screen (in the overlay's units), or nil when it is behind you.
function Esp:Project(x, y, z)
    local c = self.cam
    local dx, dy, dz = x - c.x, y - c.y, z - c.z
    local F, R, U = c.F, c.R, c.U
    local depth = dx * F[1] + dy * F[2] + dz * F[3]
    if depth < 1 then return nil end
    local right = dx * R[1] + dy * R[2] + dz * R[3]
    local up = dx * U[1] + dy * U[2] + dz * U[3]
    return self.W / 2 + right * self.focal / depth, self.H / 2 - up * self.focal / depth
end

-- The camera of the local player this frame. view: the controller the local player drives (the
-- free camera has its own); own: your character's controller (its aim is this frame's, the
-- camera's is from the frame before).
function Esp:ReadCamera(view, own)
    local pcm = view.PlayerCameraManager
    local loc, rot, fov = pcm:GetCameraLocation(), pcm:GetCameraRotation(), pcm:GetFOVAngle()
    if view:GetAddress() == own:GetAddress() then
        pcall(function()
            local pawn = own.Pawn
            if Valid(pawn) and pcm.ViewTarget.Target:GetAddress() == pawn:GetAddress() then
                local r = own:GetControlRotation()
                rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = rot.Roll }
            end
        end)
    end
    if self.frame % 30 == 1 or not self.viewportRead then
        pcall(function()
            local size, scale = self.wll:GetViewportSize(own), self.wll:GetViewportScale(own)
            if size.X > 0 and scale > 0 then self.W, self.H = size.X / scale, size.Y / scale end
            self.viewportRead = true
        end)
    end
    self.focal = (self.W / 2) / math.tan(math.rad(math.max(fov, 1)) / 2)
    local F, R, U = Axes(rot)
    self.cam = { x = loc.X, y = loc.Y, z = loc.Z, F = F, R = R, U = U }
end

--------------------------------------------------------------------------------------------------
-- Writing down the targets (numbers only)
--------------------------------------------------------------------------------------------------
-- Where an actor is (the engine function itself when it was found, else by name).
function Esp:Where(actor)
    local f = self.getLoc
    if f and type(f) ~= "number" and f:IsValid() then return f(actor) end
    return actor:K2_GetActorLocation()
end

-- A SWAT officer's full health, as its own BeginPlay sets it: 125 times the game's power
-- multiplier (whole part), between 100 and 175.
local function SwatHealth(npc)
    local ok, pm = pcall(function() return npc:GetWorld().GameState.PowerMultiplier end)
    if not (ok and type(pm) == "number") then return nil end
    return math.max(100, math.min(175, 125 * math.floor(pm)))
end

-- A new sample for an NPC (its class read once; only numbers and text are kept).
function Esp:NewNpcSample(npc, a)
    local ok, name = pcall(function() return npc:GetClass():GetFName():ToString() end)
    name = ok and name or "NPC"
    local kind = Esp.Kinds[name] or { group = "police", label = (name:gsub("_C$", "")), hp = 100 }
    local s = { address = a, group = kind.group, label = kind.label, baseLabel = kind.label, maxHp = kind.hp,
                stagger = (a // 64) % 6, hh = 88 }
    pcall(function() s.hh = npc.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    if kind.swat then s.maxHp = SwatHealth(npc) or kind.hp end
    self.samples[a] = s
    return s
end

-- An NPC's own per-frame event (config.lua's hook): the NPC is alive right now. A sample that
-- missed frames may belong to an NPC that is gone, its address now another one's: made anew.
function Esp:NpcTick(npc)
    if not (self.on and self.conf) then return end
    local a = npc:GetAddress()
    local s = self.samples[a]
    if not s or s.group == "player" or self.frame - (s.frame or 0) > 3 then s = self:NewNpcSample(npc, a) end
    s.frame = self.frame
    local g = self.conf.groups[s.group]
    if not (g and g.on) then
        if s.glow then self:Glow(npc, s, false) end
        return
    end
    self:Glow(npc, s, g.sil, g.silSlot)
    local p = self:Where(npc)
    s.x, s.y, s.z = p.X, p.Y, p.Z
    if s.hp == nil or (self.frame + s.stagger) % 6 == 0 then
        s.hp = npc.Health or 0
        if s.hp > s.maxHp then s.maxHp = s.hp end
        pcall(function()
            if s.group == "guard" then
                local alert, searching = npc["Alert?"], npc["Investigating?"]
                s.warn = alert or searching
                s.state = alert and "alert" or (searching and "searching" or nil)
            elseif s.group == "civilian" then
                local tied = npc["TiedUp?"]
                s.label = tied and "Hostage" or s.baseLabel
                s.warn = tied or npc["Scared?"] or npc["Fleeing?"]
            end
        end)
        if self.conf.visible ~= "show" then
            pcall(function()
                local pc = self.gs:GetPlayerController(npc, 0)
                s.seen = Valid(pc) and pc:LineOfSightTo(npc, { X = 0, Y = 0, Z = 0 }, false) or false
            end)
        end
    end
end

-- A security camera's own per-frame event (config.lua's hook): the camera is alive right now.
-- It is marked at its head (the actor itself is the wall mount) with a square box; it warns while
-- it is spotting someone.
function Esp:CameraTick(cam)
    if not (self.on and self.conf) then return end
    local a = cam:GetAddress()
    local s = self.samples[a]
    if not s or s.group ~= "camera" or self.frame - (s.frame or 0) > 3 then
        s = { address = a, group = "camera", label = "Camera", baseLabel = "Camera", stagger = (a // 64) % 6,
              hh = 18, ratio = 1, part = "CameraHead", noHealth = true }
        pcall(function() s.label = "Camera " .. tostring(cam.CamNumber + 1) end)
        s.baseLabel = s.label
        self.samples[a] = s
    end
    s.frame = self.frame
    local g = self.conf.groups.camera
    if not (g and g.on) then
        if s.glow then self:Glow(cam, s, false) end
        return
    end
    self:Glow(cam, s, g.sil, g.silSlot)
    if not s.x or (self.frame + s.stagger) % 6 == 0 then
        pcall(function()
            local p = cam.CameraHead:K2_GetComponentLocation()   -- the head turns, but stays where it is
            s.x, s.y, s.z = p.X, p.Y, p.Z
        end)
        pcall(function()
            local state = (cam["Destroyed?"] and "broken") or (cam.EMPed and "EMP") or (cam["Ignored?"] and "blinded")
                or (cam["Possessed?"] and "watched") or nil
            local spotting = false
            pcall(function() spotting = Valid(cam.SpotPlayerComponent.SpottedPlayer) end)
            s.warn = spotting
            s.state = spotting and "spotting" or state
        end)
        if self.conf.visible ~= "show" then
            pcall(function()
                local pc = self.gs:GetPlayerController(cam, 0)
                s.seen = Valid(pc) and pc:LineOfSightTo(cam, { X = 0, Y = 0, Z = 0 }, false) or false
            end)
        end
    end
end

-- An NPC died (config.lua's hook on NPCBase Die): its outline goes, its card with it.
function Esp:NpcDied(npc)
    local a = npc:GetAddress()
    local s = self.samples[a]
    if s and s.glow then self:Glow(npc, s, false) end
    self.samples[a] = nil
end

-- The other players, from the game's list of players.
function Esp:ReadPlayers(world, own)
    local g = self.conf.groups.player
    local ownPawn = 0
    pcall(function() ownPawn = own.Pawn:GetAddress() end)
    local arr = world.GameState.PlayerArray
    local n = arr:GetArrayNum()
    for i = 1, n do
        local ps = arr[i]
        if Valid(ps) then
            local pawn = ps.PawnPrivate
            if Valid(pawn) and pawn:GetAddress() ~= ownPawn then self:SamplePlayer(ps, pawn, g) end
        end
    end
end

function Esp:SamplePlayer(ps, pawn, g)
    local a = pawn:GetAddress()
    local s = self.samples[a]
    if not s or s.group ~= "player" or self.frame - (s.frame or 0) > 3 then
        s = { address = a, group = "player", label = "Player", baseLabel = "Player", maxHp = 100,
              stagger = (a // 64) % 6, hh = 88 }
        self.samples[a] = s
    end
    s.frame = self.frame
    if not (g and g.on) then
        if s.glow then self:Glow(pawn, s, false) end
        return
    end
    self:Glow(pawn, s, g.sil, g.silSlot)
    local p = self:Where(pawn)
    s.x, s.y, s.z = p.X, p.Y, p.Z
    if s.hp == nil or (self.frame + s.stagger) % 6 == 0 then
        pcall(function()
            s.hp, s.maxHp = pawn.Health or 0, math.max(pawn.MaxHealth or 100, 1)
            s.hh = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
            local down = pawn["Downed?"]
            s.warn, s.state, s.down = down, down and "down" or nil, down
        end)
        local key = ps:GetAddress()
        if not self.names[key] or (self.frame + s.stagger) % 60 == 0 then
            -- read in place (GetPlayerName's text would be read from UE4SS's freed call buffer)
            pcall(function() self.names[key] = ps.PlayerNamePrivate:ToString() end)
        end
        s.label = self.names[key] or "Player"
        if self.conf.visible ~= "show" then
            pcall(function()
                local pc = self.gs:GetPlayerController(pawn, 0)
                s.seen = Valid(pc) and pc:LineOfSightTo(pawn, { X = 0, Y = 0, Z = 0 }, false) or false
            end)
        end
    end
end

--------------------------------------------------------------------------------------------------
-- Silhouettes through walls (the game's own outline effect)
--------------------------------------------------------------------------------------------------
-- Mark (or unmark) every mesh of an actor for the outline: its body, its other mesh parts, and
-- the meshes of the actors it carries (a civilian's clothes and hair, a guard's gun, a police
-- helmet or shield), as the game's own outline does. actor is alive right now; nothing is kept.
function Esp:MarkMeshes(actor, on, stencil)
    local function mark(c)
        c:SetRenderCustomDepth(on)
        if on then c:SetCustomDepthStencilValue(stencil) end
    end
    local function isMesh(c)
        for _, kind in ipairs(self.meshKinds) do
            if kind and type(kind) ~= "number" and c:IsA(kind) then return true end
        end
        return false
    end
    local function walk(owner, depth)
        local list = owner.BlueprintCreatedComponents
        for i = 1, list:GetArrayNum() do                   -- never past its end (that would grow it)
            local c = list[i]
            if Valid(c) then
                if isMesh(c) then
                    pcall(mark, c)
                elseif depth == 0 and self.childKind and c:IsA(self.childKind) then
                    local child = c.ChildActor
                    if Valid(child) then pcall(walk, child, 1) end
                end
            end
        end
    end
    pcall(mark, actor.Mesh)
    pcall(walk, actor, 0)
end

-- Mark (or unmark) a target for its silhouette (slot: the effect's first or second colour). actor
-- is alive right now. The game turns the mark off itself now and then (a guard that stops
-- spotting you, a teammate getting up), so it is put back every half second. Unmarked, a downed
-- teammate keeps the game's own outline.
function Esp:Glow(actor, s, want, slot)
    if want then
        local stencil = slot == 2 and 0 or 1                 -- marked 1 or more: the first colour
        if s.glow and s.stencil == stencil and (self.frame + s.stagger) % 30 ~= 0 then return end
        local cleared = true
        pcall(function() cleared = not actor[s.part or "Mesh"].bRenderCustomDepth end)
        if not s.glow or cleared or s.stencil ~= stencil then self:MarkMeshes(actor, true, stencil) end
        s.glow, s.stencil = true, stencil
        self.glowed[s.address] = true
    elseif s.glow then
        self:Unmark(actor, s.group == "player" and s.down)
        s.glow = false
        self.glowed[s.address] = nil
    end
end

function Esp:Unmark(actor, downedTeammate)
    if downedTeammate then self:MarkMeshes(actor, true, 0) else self:MarkMeshes(actor, false) end
end

-- The effect in this map: a PostProcessVolume holding the game's outline material, in a slot of
-- its settings. Returns the slot, the game's material and the ESP's copy when it is in the slot.
local function OutlineSlot(volume)
    local arr = volume.Settings.WeightedBlendables.Array
    if arr:GetArrayNum() < 1 then return nil end
    local entry = arr[1]
    local object = entry.Object
    if not Valid(object) then return nil end
    local name = object:GetFullName()
    if name:find("HighlightMat", 1, true) then return entry, object, nil end
    -- the ESP's copy (also one from before a reloadconfig): its parent is the game's material
    local ok, parent = pcall(function() return object.Parent end)
    if name:find("OARCommands_EspOutline", 1, true) and ok and Valid(parent) then return entry, parent, object end
    return nil
end

-- Found again each time (rarely: once per map, and when the outline's settings change), so no
-- object of the map is kept from one frame to the next.
local function FindOutline()
    for _, volume in pairs(FindAllOf("PostProcessVolume") or {}) do
        local ok, entry, original, copy = pcall(OutlineSlot, volume)
        if ok and entry then return volume, entry, original, copy end
    end
    return nil
end

function Esp:SetUpOutline()
    if self.outlineWorld == self.world then return end
    self.outlineWorld = self.world
    self.outline, self.outlineSet = nil, nil
    local volume, entry, original, copy = FindOutline()
    if not volume then
        self.say("ESP silhouettes: this map has no outline effect (heist maps have it)")
        return
    end
    local made, err = pcall(function()
        copy = copy or self.kml:CreateDynamicMaterialInstance(volume, original, FName("OARCommands_EspOutline"), 0)
        entry.Object = copy
    end)
    if made and Valid(copy) then
        self.outline = true
        self:OutlineColours(copy)
    else
        self.say("ESP silhouettes: could not use the game's outline effect: " .. tostring(err))
    end
end

-- The copy's colours, thickness, brightness and style (copy: as just found, or found again).
-- glowEnemy is the first colour (marked 1 or more), glowTeam the second (marked 0).
function Esp:OutlineColours(copy)
    local c = self.conf
    local key = table.concat(c.glowEnemy, ",") .. table.concat(c.glowTeam, ",") .. c.glowWidth .. c.glowBright .. c.glowStyle
    if self.outlineSet == key then return end
    if not copy then
        local _, _, _, found = FindOutline()
        copy = found
    end
    if not copy then return end
    self.outlineSet = key
    pcall(function()
        local function color(t) return { R = t[1], G = t[2], B = t[3], A = 0 } end
        copy:SetVectorParameterValue(FName("Color1"), color(c.glowEnemy))       -- marked 1 or more
        copy:SetVectorParameterValue(FName("Color"), color(c.glowTeam))         -- marked 0
        copy:SetScalarParameterValue(FName("LineWidth"), c.glowWidth)
        copy:SetScalarParameterValue(FName("OutlineGlowInt"), c.glowBright)
        -- the sign picks the side of the edge: an outline around the body, or a band inside it
        copy:SetScalarParameterValue(FName("EdgeAngleFalloff"), c.glowStyle == "band" and -100 or 100)
    end)
end

-- The outline off: the game's own material back in its place, and every mark the ESP made taken
-- off (found again by class; NPCs that died or were tied up no longer tick to be unmarked).
function Esp:OutlineOff()
    if self.outline and self.outlineWorld == self.world then
        pcall(function()
            local _, entry, original, copy = FindOutline()
            if entry and copy then entry.Object = original end
        end)
    end
    self.outline, self.outlineWorld, self.outlineSet = nil, nil, nil
    if next(self.glowed) == nil then return end
    for _, className in ipairs({ "NPCBase_C", "PlayerCharacter_C" }) do
        for _, actor in ipairs(self.allOf(className) or {}) do
            local a = actor:GetAddress()
            if self.glowed[a] then
                local down = false
                if className == "PlayerCharacter_C" then pcall(function() down = actor["Downed?"] == true end) end
                self:Unmark(actor, down)
                local s = self.samples[a]
                if s then s.glow = false end
            end
        end
    end
    self.glowed = {}
end

--------------------------------------------------------------------------------------------------
-- The overlay
--------------------------------------------------------------------------------------------------
local function Slot(slot, minX, minY, maxX, maxY, l, t, r, b, ax, ay, auto)
    slot:SetMinimum({ X = minX, Y = minY })
    slot:SetMaximum({ X = maxX, Y = maxY })
    slot:SetOffsets({ Left = l, Top = t, Right = r, Bottom = b })
    if ax then slot:SetAlignment({ X = ax, Y = ay }) end
    if auto then slot:SetAutoSize(true) end
    return slot
end

function Esp:BuildOverlay(pc)
    local kit = self.kit
    local root = self.wbl:Create(pc, kit.UClass(HOST_CLASS), pc)
    if not Valid(root) then error("the game would not make a widget") end
    local tree = root.WidgetTree
    local canvas = kit.Make("CanvasPanel", tree)
    tree.RootWidget = canvas
    root:SetVisibility(HIT_TEST_INVISIBLE)              -- the mouse goes straight through
    root:AddToViewport(1)                               -- over the game's HUD, under its menus
    self.overlay = { root = root, tree = tree, canvas = canvas, cards = {}, world = self.world,
                     thickness = self.conf.thickness, textSize = self.conf.textSize, shown = true }
    local ok, font = pcall(kit.UClass, FONT)
    self.overlay.font = ok and font or nil
end

function Esp:Box(color)
    local b = self.kit.Make("Border", self.overlay.tree)
    b:SetBrushColor(self.kit.Color(color))
    return b
end

-- A label: a text inside a see-through box, whose content colour tints it (the text itself is
-- white, so any colour can be set later with one flat call).
function Esp:Label(card)
    local kit, o = self.kit, self.overlay
    local wrap = self:Box(CLEAR)
    local t = kit.Make("TextBlock", o.tree)
    if o.font then
        t.Font.FontObject = o.font
        t.Font.TypefaceFontName = FName("Bold")
    end
    t.Font.Size = o.textSize
    pcall(function() t.Font.OutlineSettings.OutlineSize = 1 end)      -- a thin dark edge to read it on anything
    kit.Paint(t.ColorAndOpacity.SpecifiedColor, { 1, 1, 1, 1 })
    t.ColorAndOpacity.ColorUseRule = 0
    t:SetText(FText(""))
    wrap:SetContent(t)
    return wrap, t
end

-- One card: everything that marks one target, laid out once inside its own canvas.
function Esp:NewCard()
    local o = self.overlay
    local t = o.thickness
    local c = { parts = {}, vis = {} }
    c.panel = self.kit.Make("CanvasPanel", o.tree)
    c.slot = o.canvas:AddChildToCanvas(c.panel)
    local function part(name, widget)
        local s = c.panel:AddChildToCanvas(widget)
        c.parts[name] = widget
        return s
    end
    c.fill = self:Box(CLEAR)
    Slot(part("fill", c.fill), 0, 0, 1, 1, 0, 0, 0, 0)
    c.edges = {}
    local edges = {
        { 0, 0, 1, 0, 0, 0, 0, t }, { 0, 1, 1, 1, 0, -t, 0, t },       -- top, bottom
        { 0, 0, 0, 1, 0, 0, t, 0 }, { 1, 0, 1, 1, -t, 0, t, 0 },       -- left, right
    }
    for i, e in ipairs(edges) do
        c.edges[i] = self:Box(CLEAR)
        Slot(part("edge" .. i, c.edges[i]), table.unpack(e))
    end
    c.corners = {}
    local k = CORNER
    local corners = {
        { 0, 0, k, 0, 0, 0, 0, t }, { 0, 0, 0, k, 0, 0, t, 0 },                      -- top left
        { 1 - k, 0, 1, 0, 0, 0, 0, t }, { 1, 0, 1, k, -t, 0, t, 0 },                 -- top right
        { 0, 1, k, 1, 0, -t, 0, t }, { 0, 1 - k, 0, 1, 0, 0, t, 0 },                 -- bottom left
        { 1 - k, 1, 1, 1, 0, -t, 0, t }, { 1, 1 - k, 1, 1, -t, 0, t, 0 },            -- bottom right
    }
    for i, e in ipairs(corners) do
        c.corners[i] = self:Box(CLEAR)
        Slot(part("corner" .. i, c.corners[i]), table.unpack(e))
    end
    local bar = math.max(2, t + 1)
    c.hpBack = self:Box({ 0, 0, 0, 0.6 })
    Slot(part("hpBack", c.hpBack), 0, 0, 0, 1, -(bar + 3), 0, bar, 0)
    c.hpFill = self:Box({ 0.2, 0.9, 0.3, 1 })
    c.hpSlot = Slot(part("hpFill", c.hpFill), 0, 0, 0, 1, -(bar + 3), 0, bar, 0)
    local dot = math.max(3, t * 2 + 1)
    c.head = self:Box(CLEAR)
    Slot(part("head", c.head), 0.5, HEAD_AT, 0.5, HEAD_AT, 0, 0, dot, dot, 0.5, 0.5)
    c.name, c.nameText = self:Label(c)
    Slot(part("name", c.name), 0.5, 0, 0.5, 0, 0, -2, 0, 0, 0.5, 1, true)
    c.info, c.infoText = self:Label(c)
    Slot(part("info", c.info), 0.5, 1, 0.5, 1, 0, 2, 0, 0, 0.5, 0, true)
    -- the line from the edge of the screen lives in the overlay itself (it reaches outside the card)
    c.line = self:Box(CLEAR)
    c.lineSlot = o.canvas:AddChildToCanvas(c.line)
    Slot(c.lineSlot, 0, 0, 0, 0, 0, 0, 0, 0)
    c.line:SetRenderTransformPivot({ X = 0, Y = 0.5 })
    for name, w in pairs(c.parts) do w:SetVisibility(COLLAPSED); c.vis[name] = false end
    c.panel:SetVisibility(COLLAPSED)
    c.line:SetVisibility(COLLAPSED)
    c.shown, c.lineShown = false, false
    o.cards[#o.cards + 1] = c
    return c
end

local function Show(c, name, on)
    if c.vis[name] == on then return end
    c.vis[name] = on
    c.parts[name]:SetVisibility(on and HIT_TEST_INVISIBLE or COLLAPSED)
end

local function ShowCard(c, on)
    if c.shown == on then return end
    c.shown = on
    c.panel:SetVisibility(on and HIT_TEST_INVISIBLE or COLLAPSED)
end

local function ShowLine(c, on)
    if c.lineShown == on then return end
    c.lineShown = on
    c.line:SetVisibility(on and HIT_TEST_INVISIBLE or COLLAPSED)
end

-- Which parts a group shows (only when that changes).
function Esp:CardLook(c, g)
    if c.look == g then return end
    c.look = g
    for i = 1, 4 do Show(c, "edge" .. i, g.box == "box") end
    for i = 1, 8 do Show(c, "corner" .. i, g.box == "corners") end
    Show(c, "fill", g.fill)
    Show(c, "name", g.name)
    Show(c, "info", g.distance)
    Show(c, "hpBack", g.health)
    Show(c, "hpFill", g.health)
    Show(c, "head", g.head)
end

function Esp:CardColour(c, color)
    local key = color[1] .. "," .. color[2] .. "," .. color[3]
    if c.colorKey == key then return end
    c.colorKey = key
    local kit = self.kit
    local solid = kit.Color(color)
    for _, e in ipairs(c.edges) do e:SetBrushColor(solid) end
    for _, e in ipairs(c.corners) do e:SetBrushColor(solid) end
    c.head:SetBrushColor(solid)
    c.line:SetBrushColor(solid)
    c.fill:SetBrushColor(kit.Color({ color[1], color[2], color[3], self.conf.fillOpacity }))
    c.name:SetContentColorAndOpacity(solid)
    c.info:SetContentColorAndOpacity(solid)
end

local function SetText(c, which, text)
    local key = which .. "Value"
    if c[key] == text then return end
    c[key] = text
    c[which .. "Text"]:SetText(FText(text))
end

-- Put card c on target s (its box on the screen is x, y, w, h).
function Esp:DrawCard(c, s, g, x, y, w, h)
    ShowCard(c, true)
    self:CardLook(c, g)
    local p = c.place
    if not p or math.abs(p[1] - x) >= 0.5 or math.abs(p[2] - y) >= 0.5 or math.abs(p[3] - w) >= 0.5 or math.abs(p[4] - h) >= 0.5 then
        c.place = { x, y, w, h }
        c.slot:SetOffsets({ Left = x, Top = y, Right = w, Bottom = h })
    end
    self:CardColour(c, (s.warn and g.warn) and g.warnColor or g.color)
    local dim = self.conf.visible == "dim" and s.seen
    if c.dim ~= dim then
        c.dim = dim
        c.panel:SetRenderOpacity(dim and 0.35 or 1)
        c.line:SetRenderOpacity(dim and 0.35 or 1)
    end
    if g.name then SetText(c, "name", s.state and (s.label .. " (" .. s.state .. ")") or s.label) end
    if g.distance then SetText(c, "info", string.format("%d m", math.floor(s.dist / 100 + 0.5))) end
    if g.health and not s.noHealth then
        local frac = math.max(0, math.min(1, (s.hp or 0) / math.max(s.maxHp or 100, 1)))
        local step = math.floor(frac * 20 + 0.5)
        if c.hpStep ~= step then
            c.hpStep = step
            c.hpSlot:SetMinimum({ X = 0, Y = 1 - step / 20 })
            local f = step / 20
            c.hpFill:SetBrushColor(self.kit.Color({ math.min(1, 2 * (1 - f)), math.min(1, 2 * f) * 0.85, 0.15, 1 }))
        end
    end
    -- the line from the edge of the screen to the target's feet, middle or head
    if g.line ~= "off" then
        local x0 = self.W / 2
        local y0 = (g.line == "top" and 0) or (g.line == "middle" and self.H / 2) or self.H
        local tx = x + w / 2
        local ty = (g.line == "top" and y) or (g.line == "middle" and y + h / 2) or (y + h)
        local dx, dy = tx - x0, ty - y0
        local len = math.sqrt(dx * dx + dy * dy)
        local t = self.overlay.thickness
        local lp = c.linePlace
        if not lp or math.abs(lp[1] - tx) >= 0.5 or math.abs(lp[2] - ty) >= 0.5 or lp[3] ~= g.line then
            c.linePlace = { tx, ty, g.line }
            c.lineSlot:SetOffsets({ Left = x0, Top = y0 - t / 2, Right = len, Bottom = t })
            c.line:SetRenderTransformAngle(math.deg(math.atan(dy, dx)))
        end
        ShowLine(c, true)
    else
        ShowLine(c, false)
    end
end

function Esp:HideCard(c)
    ShowCard(c, false)
    ShowLine(c, false)
end

-- Forget the overlay without touching it (the game took it off the screen, or another map freed it).
function Esp:DropOverlay(remove)
    local o = self.overlay
    if o and remove and o.world == self.world then pcall(function() o.root:RemoveFromParent() end) end
    self.overlay = nil
end

-- The game cleared the screen (config.lua's hook on RemoveAllWidgets): the overlay is gone. It is
-- made again once the screen has stayed as it is for a second (while loading the game clears it
-- several times).
function Esp:Removed()
    self.overlay = nil
    self.removedAt = os.clock()
end

--------------------------------------------------------------------------------------------------
-- Every frame (from your controller's per-frame event)
--------------------------------------------------------------------------------------------------
function Esp:NewWorld(world)
    self.world = world
    self.samples, self.names, self.glowed = {}, {}, {}
    self.overlay = nil                                  -- freed with the old map: never touched
    self.outline, self.outlineWorld, self.outlineSet = nil, nil, nil
    self.removedAt = os.clock()
    self.viewportRead = nil
end

function Esp:Tick(controller)
    if not self.conf then return end
    if not self.on and not self.overlay and not self.outline and next(self.glowed) == nil and next(self.samples) == nil then return end
    -- only the local player's controller (the host also ticks every guest's)
    local a = controller:GetAddress()
    local newController = false
    if a ~= self.ownAddress then
        if not controller:IsLocalController() then return end
        newController = self.ownAddress ~= nil
        self.ownAddress = a
    end
    local okWorld, worldObject = pcall(function() return controller:GetWorld() end)
    if not (okWorld and Valid(worldObject)) then return end
    local world = worldObject:GetAddress()
    -- A new map: a new world address, or (a map loaded fresh can get the old one's address) a new
    -- controller of yours or a world clock that went back.
    local clock = 0
    pcall(function() clock = self.gs:GetRealTimeSeconds(worldObject) end)
    if world ~= self.world or newController or clock < (self.worldClock or 0) then self:NewWorld(world) end
    self.worldClock = clock
    self.frame = self.frame + 1
    -- a new line thickness or text size: the overlay is made again (the old one off the screen)
    local o = self.overlay
    if o and (o.thickness ~= self.conf.thickness or o.textSize ~= self.conf.textSize) then self:DropOverlay(true) end

    if not self.on then
        if self.overlay and self.overlay.shown then
            self.overlay.shown = false
            pcall(function() self.overlay.root:SetVisibility(COLLAPSED) end)
        end
        if self.outline or next(self.glowed) ~= nil then self:OutlineOff() end
        self.samples = {}                               -- nothing is written down while it is off
        return
    end
    if not self.npcsHooked and self.frame % 60 == 1 then self.npcsHooked = self.hookNpcs() end
    if not self.camerasHooked and self.frame % 60 == 31 then self.camerasHooked = self.hookCameras() end

    -- the silhouettes
    if self.conf.glow then
        self:SetUpOutline()
        if self.outline then self:OutlineColours() end    -- finds the copy again only when they change
    elseif self.outline or next(self.glowed) ~= nil then
        self:OutlineOff()
    end

    -- the camera
    local lp = self.lp
    if not Valid(lp) then
        lp = FindFirstOf("LocalPlayer")
        self.lp = lp
    end
    local view = Valid(lp) and lp.PlayerController or controller
    if not Valid(view) then view = controller end
    local okCam = pcall(function() self:ReadCamera(view, controller) end)
    if not okCam then return end

    pcall(function() self:ReadPlayers(worldObject, controller) end)

    -- the overlay (made again a second after the game last cleared the screen), for the controller
    -- the local player drives now (in the free camera yours has no player to show widgets to)
    if not self.overlay then
        if os.clock() - (self.removedAt or -10) < 1 then return end
        local owner = controller
        pcall(function() if Valid(view) and Valid(view.Player) then owner = view end end)
        local ok, err = pcall(function() self:BuildOverlay(owner) end)
        if not ok then
            if not self.buildFailed then self.say("ESP: could not make its overlay: " .. tostring(err)) end
            self.buildFailed = true
            self.removedAt = os.clock() + 5                 -- try again later
            return
        end
        self.buildFailed = nil
    elseif not self.overlay.shown then
        self.overlay.shown = true
        self.overlay.root:SetVisibility(HIT_TEST_INVISIBLE)
    end
    self:Draw()
end

-- The targets in range and on the screen, nearest first, each with its box: only those count
-- towards the most shown at once (one behind you takes no place).
function Esp:Draw()
    local conf, cam = self.conf, self.cam
    local list = {}
    for a, s in pairs(self.samples) do
        local age = self.frame - (s.frame or 0)
        if age > 120 then
            self.samples[a] = nil                       -- gone (destroyed, or another map)
        elseif age <= 3 and s.x then
            local g = conf.groups[s.group]
            if g and g.on and not (conf.visible == "hide" and s.seen) then
                local dx, dy, dz = s.x - cam.x, s.y - cam.y, s.z - cam.z
                s.dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if s.dist <= g.range * 100 then
                    local tx, ty = self:Project(s.x, s.y, s.z + s.hh)
                    local bx, by = self:Project(s.x, s.y, s.z - s.hh)
                    if tx and bx then
                        local h = math.max(by - ty, 4)
                        local w = h * (s.ratio or 0.42)
                        local x = (tx + bx) / 2 - w / 2
                        if x + w > 0 and x < self.W and ty + h > 0 and ty < self.H then
                            s.box = { x, ty, w, h }
                            list[#list + 1] = s
                        end
                    end
                end
            end
        end
    end
    table.sort(list, function(p, q) return p.dist < q.dist end)
    local count = math.min(#list, conf.maxTargets)
    local wanted = {}
    for i = 1, count do wanted[list[i].address] = list[i] end
    -- Each target keeps its card while it stays shown (nearer and farther ones swapping places
    -- change nothing on the screen but places); the others' cards are free.
    local o = self.overlay
    local placed, free = {}, {}
    for _, c in ipairs(o.cards) do
        if c.owner and wanted[c.owner] and not placed[c.owner] then placed[c.owner] = c else free[#free + 1] = c end
    end
    local need = 0
    for i = 1, count do if not placed[list[i].address] then need = need + 1 end end
    local made = 0
    while #free < need and made < 4 do                    -- a few new cards per frame
        free[#free + 1] = self:NewCard()
        made = made + 1
    end
    for i = 1, count do
        local s = list[i]
        if not placed[s.address] and #free > 0 then
            local pick = 1
            for k, c in ipairs(free) do                   -- one that showed the same group: less to change
                if c.lookGroup == s.group then pick = k break end
            end
            local c = table.remove(free, pick)
            c.owner = s.address
            placed[s.address] = c
        end
    end
    local drawn = 0
    for a, c in pairs(placed) do
        local s = wanted[a]
        local b = s.box
        c.lookGroup = s.group
        self:DrawCard(c, s, conf.groups[s.group], b[1], b[2], b[3], b[4])
        drawn = drawn + 1
    end
    for _, c in ipairs(free) do
        c.owner = nil
        self:HideCard(c)
    end
    self.shown = drawn
end

-- Thrown away for good (reloadconfig): the overlay off the screen and the outline back to the
-- game's, when still in the same map (pc: a live controller of the current map, or nil).
function Esp:Destroy(pc)
    local same = false
    pcall(function() same = pc ~= nil and pc:GetWorld():GetAddress() == self.world end)
    if not same then return end
    self:DropOverlay(true)
    self.on = false
    self:OutlineOff()
end

return Esp
