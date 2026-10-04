--[[
    OAR Commands: gui.lua, the window that opengui shows.

    This file builds the window out of the engine's own UI pieces (UMG widgets) while the game
    runs; config.lua decides what is in it (its "opengui" section). It is read again on every
    reloadconfig, like the other files in this folder.

    How it is put together (UE4SS 3.0.1 Lua; every step below was checked in UE4SS's source and
    in the game's own class data):
      - The window needs one UserWidget to go on the screen. A UserWidget cannot be created by
        itself (the engine marks it abstract), so it is a copy of one of the game's own widget
        Blueprints that does nothing: HammerCursor, a cursor picture the game never uses. Its
        picture is swapped for the menu's own pieces before it is shown.
      - Everything clickable is an engine Button (UButton). The engine draws it lighter under the
        mouse and darker while pressed by itself.
      - A click: UE4SS's key watcher sees the left mouse button go down (config.lua counts it in
        menu.clicks), and on the next frame the menu asks its buttons which one has the mouse over
        it (IsHovered) and runs that one. The engine's UserWidget mouse events cannot be used:
        in this game they are Blueprint-only events, which UE4SS never sees for a widget that
        does not fill them in.
      - Every frame (from the game's own per-frame event of your controller, RobberController
        ReceiveTick): clicks, the search box, fresh numbers once a second, and noticing that the
        game took the menu off the screen. It does nothing while the menu is closed.
      - Colours, sizes and fonts are written into the pieces before they are first shown, member
        by member (UE4SS 3.0.1 cannot pass a struct inside a struct to the engine); later changes
        only use calls that take plain numbers or plain structs.
      - The window stays in memory when closed (hidden), so opening it again is instant. The game
        clears the screen on loading, death and the win screen (WidgetLayoutLibrary
        RemoveAllWidgets, which config.lua hooks): the menu closes first, before the game sets up
        its own screen, and is never touched again (the engine frees it), so the next opengui
        builds a new one. The same happens on a map change (another world or controller).
      - Moving and resizing: pressing the title bar (or the grip in the bottom right corner)
        starts it; then every frame, while that button stays pressed, the window follows the
        mouse (WidgetLayoutLibrary GetMousePositionOnViewport). Where it is and how big it is
        live in `place`, which config.lua keeps in memory only: a game restart puts it back.
      - The list is a fixed set of lines that are filled in again for each tab (no widgets are
        made or thrown away while you click around). New lines are made only when a tab needs
        more than ever before, a few per frame, up to style.maxRows; a line's buttons and amount
        box are only made once a line first needs them.
--]]

local Kit = {}

--------------------------------------------------------------------------------------------------
-- Looks. config.lua can change any of these (V.Menu).
--------------------------------------------------------------------------------------------------
Kit.DefaultStyle = {
    -- The look picked on the design page (2026-10-04): slate teal, filled tab highlight,
    -- outlined buttons, the game darkened a quarter behind the window.
    title = "One-Armed-Menu",
    width = 1100, height = 680,          -- the window, in screen units at 1080p
    sidebar = 180,                       -- width of the tab list on the left
    labelWidth = 230,                    -- width of a line's name
    maxRows = 160,                       -- most lines one tab shows (more: "search to narrow")
    rowsPerFrame = 30,                   -- new lines made per frame when a tab needs more
    zOrder = 50,                         -- above the game's own UI
    font = "/Engine/EngineFonts/Roboto.Roboto",
    titleFont = "/Game/UI/Font/kenyan_coffee_rgUI_Font.kenyan_coffee_rgUI_Font",
    codeFont = "/Engine/EngineFonts/DroidSansMono.DroidSansMono",
    titleSize = 30, tabSize = 16, textSize = 14, smallSize = 12, codeSize = 13,
    tabStyle = "fill",                   -- the tab you are on: "fill" (filled) or "bar" (a bar on its left)
    chipStyle = "outline",               -- buttons: "outline" (a thin accent frame) or "filled"
    animate = true,                      -- short fades and slides when opening, closing, changing tab
    -- colours are the engine's linear colours: { red, green, blue, opacity }
    backdrop = { 0.0, 0.0, 0.0, 0.25 },  -- over the game behind the window
    window = { 0.0545, 0.0595, 0.0742, 0.97 },
    bar = { 0.0356, 0.0395, 0.0497, 1.0 },  -- title bar, tab list and status line
    barHover = { 0.0999, 0.1095, 0.1413, 1.0 },
    accent = { 0.1144, 0.3763, 0.3325, 1.0 },  -- slate teal
    header = { 0.0908, 0.0999, 0.1248, 1.0 },
    headerHover = { 0.14, 0.15, 0.19, 1.0 },
    row = { 0.0648, 0.0704, 0.0887, 1.0 },
    rowAlt = { 0.0742, 0.0802, 0.0999, 1.0 },
    item = { 0.0704, 0.0742, 0.0931, 1.0 },
    itemHover = { 0.159, 0.1714, 0.2086, 1.0 },
    chip = { 0.15, 0.159, 0.2016, 1.0 },
    chipHover = { 0.2705, 0.2918, 0.3515, 1.0 },
    pressed = { 0.05, 0.05, 0.06, 1.0 },
    on = { 0.0452, 0.15, 0.1329, 1.0 },    -- a switch that is on, the tab you are on
    confirm = { 0.6172, 0.159, 0.1195, 1.0 },  -- a button waiting for its second click
    input = { 0.0203, 0.0222, 0.0296, 1.0 },
    text = { 0.9301, 0.9387, 0.956, 1.0 },
    dim = { 0.552, 0.5776, 0.6376, 1.0 },
    dragHover = { 0.05, 0.055, 0.07, 1.0 },  -- the title bar under the mouse (it moves the window)
    minWidth = 760, minHeight = 460,     -- the smallest the window can be made
    confirmSeconds = 4,                  -- how long a "Sure?" button waits for its second click
}

local HOST_CLASS = "/Game/UI/Cursors/HammerCursor.HammerCursor_C"
local VISIBLE, COLLAPSED, SELF_HIT_TEST_INVISIBLE = 0, 1, 4         -- ESlateVisibility
local AUTO, FILL = 0, 1                                              -- ESlateSizeRule
local H_FILL, H_LEFT, H_CENTER, H_RIGHT = 0, 1, 2, 3                 -- EHorizontalAlignment
local V_FILL, V_TOP, V_CENTER, V_BOTTOM = 0, 1, 2, 3                 -- EVerticalAlignment
local CURSOR_RESIZE_SE, CURSOR_GRAB = 5, 10                         -- EMouseCursor

local function Valid(o) return o ~= nil and type(o) ~= "number" and o:IsValid() end

local function Color(c) return { R = c[1], G = c[2], B = c[3], A = c[4] } end

local function Margin(l, t, r, b) return { Left = l, Top = t or l, Right = r or l, Bottom = b or t or l } end

-- An object parameter left empty. A Lua nil there makes UE4SS 3.0.1 read the nil again for every
-- parameter after it; an invalid object is passed as "none" and counted properly.
local function NoObject() return StaticFindObject("/Script/UMG.OARCommands_NoSuchObject") end

--------------------------------------------------------------------------------------------------
-- Making widgets
--------------------------------------------------------------------------------------------------
-- The engine's own classes (/Script/...) live as long as the game and are looked up once.
-- Anything else (the game's widget Blueprint, fonts) is looked up again every time: after a map
-- change the engine may have freed it, and even asking a freed object whether it is valid reads
-- freed memory. A kept HammerCursor class crashed the game when the menu opened in the lobby
-- after a heist (2026-10-04).
local NativeClasses = {}
local function UClass(path)
    local native = path:sub(1, 8) == "/Script/"
    if native and NativeClasses[path] then return NativeClasses[path] end
    local c = StaticFindObject(path)
    if not Valid(c) and (path:sub(1, 6) == "/Game/" or path:sub(1, 8) == "/Engine/") then
        LoadAsset(path)
        c = StaticFindObject(path)
    end
    if not Valid(c) then error("the game has no " .. path) end
    if native then NativeClasses[path] = c end
    return c
end

local function Make(className, outer)
    local w = StaticConstructObject(UClass("/Script/UMG." .. className), outer, 0, 0, 0, nil, false, false, nil)
    if not Valid(w) then error("could not make a " .. className) end
    return w
end

-- Write a colour into a live view of an FLinearColor.
local function Paint(view, c)
    view.R, view.G, view.B, view.A = c[1], c[2], c[3], c[4]
end

local Menu = {}
Menu.__index = Menu

-- The outer for new pieces: the window's widget tree.
function Menu:Outer() return self.tree end

-- A font by path, or nil (the text then keeps the engine's default font).
function Menu:Font(path)
    self.fonts = self.fonts or {}
    if self.fonts[path] == nil then
        local ok, font = pcall(UClass, path)
        self.fonts[path] = ok and font or false
    end
    return self.fonts[path] or nil
end

function Menu:Text(size, color, fontPath, bold)
    local t = Make("TextBlock", self:Outer())
    local font = self:Font(fontPath or self.style.font)
    if font then
        local roboto = (fontPath or self.style.font):find("Roboto", 1, true) ~= nil
        t.Font.FontObject = font
        t.Font.TypefaceFontName = FName(bold and "Bold" or (roboto and "Regular" or "Default"))
    end
    t.Font.Size = size
    Paint(t.ColorAndOpacity.SpecifiedColor, color)
    t.ColorAndOpacity.ColorUseRule = 0                  -- the colour above, not the parent's
    return t
end

function Menu:Box(color, padding)
    local b = Make("Border", self:Outer())
    b:SetBrushColor(Color(color))
    if padding then b:SetPadding(padding) end
    return b
end

-- A box to type in (plain text on the menu's own dark box), in the menu's text size.
function Menu:Input()
    local e = Make("EditableText", self:Outer())
    -- This engine version keeps the font both in the box itself and in its style: set both.
    for _, view in ipairs({ function() return e.Font end, function() return e.WidgetStyle.Font end }) do
        pcall(function()
            local f = view()
            local font = self:Font(self.style.font)
            if font then
                f.FontObject = font
                f.TypefaceFontName = FName("Regular")
            end
            f.Size = self.style.textSize
        end)
    end
    return e
end

function Menu:Sized(child, width, height)
    local s = Make("SizeBox", self:Outer())
    if width then s:SetWidthOverride(width) end
    if height then s:SetHeightOverride(height) end
    s:AddChild(child)
    return s
end

-- Put child in a horizontal or vertical box. size: "fill" or nil (as big as it needs).
local function Add(box, child, size, padding, valign, halign)
    local slot
    if box:IsA(UClass("/Script/UMG.HorizontalBox")) then
        slot = box:AddChildToHorizontalBox(child)
    else
        slot = box:AddChildToVerticalBox(child)
    end
    slot:SetSize({ Value = 1.0, SizeRule = size == "fill" and FILL or AUTO })
    if padding then slot:SetPadding(padding) end
    slot:SetVerticalAlignment(valign or V_CENTER)
    if halign then slot:SetHorizontalAlignment(halign) end
    return slot
end

-- An engine button in flat colours (normal, mouse over, pressed), with `content` inside. It
-- cannot take the keyboard, so typing stays in the search and amount boxes.
function Menu:Button(content, normal, hover, padding)
    local b = Make("Button", self:Outer())
    local ws = b.WidgetStyle
    for name, color in pairs({ Normal = normal, Hovered = hover, Pressed = self.style.pressed }) do
        local brush = ws[name]
        brush.ResourceName = NAME_None                    -- no picture: a plain box in TintColor
        brush.DrawAs = 1                                  -- ESlateBrushDrawType::Box
        Paint(brush.TintColor.SpecifiedColor, color)
        brush.TintColor.ColorUseRule = 0
    end
    local p = padding or Margin(10, 4)
    for _, name in ipairs({ "NormalPadding", "PressedPadding" }) do
        local m = ws[name]
        m.Left, m.Top, m.Right, m.Bottom = p.Left, p.Top, p.Right, p.Bottom
    end
    b.IsFocusable = false
    b:SetContent(content)
    return b
end

-- Something to click: fn() when it is clicked. base: its normal colour (for Tint).
function Menu:Clickable(button, base, fn, fixed)
    local c = { button = button, base = base, fn = fn, tint = nil }
    if fixed then self.fixed[#self.fixed + 1] = c end
    return c
end

-- Show a button in another colour than its normal one (a switch that is on, a question).
-- The engine multiplies the button's colours by its background colour.
function Menu:Tint(c, color)
    local key = color and table.concat(color, ",") or "none"
    if c.tint == key then return end
    c.tint = key
    local m = { R = 1, G = 1, B = 1, A = 1 }
    if color then
        local function ratio(i) return color[i] / math.max(c.base[i], 0.01) end
        m = { R = ratio(1), G = ratio(2), B = ratio(3), A = 1 }
    end
    c.button:SetBackgroundColor(m)
end

local function SetText(cache, w, s)
    local key = w:GetAddress()
    if cache[key] == s then return end
    cache[key] = s
    w:SetText(FText(s))
end

-- Show or hide a piece. Buttons are shown as VISIBLE: the engine leaves anything else out when it
-- works out what is under the mouse, and a button that is never under the mouse cannot be hovered.
local function Show(cache, w, on, shownAs)
    local key = w:GetAddress()
    local v = on and (shownAs or SELF_HIT_TEST_INVISIBLE) or COLLAPSED
    if cache[key] == v then return end
    cache[key] = v
    w:SetVisibility(v)
end

-- A small button with a word on it. Returns { button, text, click, outer }: outer is what goes
-- into a box and is shown or hidden (the thin accent frame of an outlined button, or the button).
function Menu:Chip(label, size, padding, fn, fixed)
    local st = self.style
    local text = self:Text(size or st.textSize, st.text)
    text:SetText(FText(label))
    local chip = { text = text }
    local outline = st.chipStyle == "outline"
    local normal = outline and st.row or st.chip
    chip.button = self:Button(text, normal, st.chipHover, padding or Margin(10, 4))
    chip.outer, chip.outerShown = chip.button, VISIBLE
    if outline then
        local frame = self:Box(st.accent, Margin(1))
        frame:SetContent(chip.button)
        chip.outer, chip.outerShown = frame, nil
    end
    chip.click = self:Clickable(chip.button, normal, fn, fixed)
    return chip
end

--------------------------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------------------------
function Menu:Build()
    local st = self.style
    self.wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    self.wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    self.hostClass = UClass(HOST_CLASS)

    self.pcAddress = self.pc:GetAddress()
    self.worldAddress = self.pc:GetWorld():GetAddress()
    -- the per-frame event comes from your character's controller (RobberController); in the free
    -- camera the menu belongs to the camera's controller, but the robber's still ticks
    self.tickAddress = self.tickPc and self.tickPc:GetAddress() or self.pcAddress
    self.tickPc = nil                              -- only its address is kept
    self.lp = self.pc.Player                      -- the local player keeps its controller up to date
    local root = self.wbl:Create(self.pc, self.hostClass, self.pc)
    if not Valid(root) then error("the game would not make a widget") end
    self.root, self.tree = root, root.WidgetTree
    local overlay = Make("Overlay", self.tree)
    self.tree.RootWidget = overlay
    root.bIsFocusable = true

    -- dark backdrop over the whole game; it also keeps clicks off the game
    local backdrop = self:Box(st.backdrop)
    backdrop:SetVisibility(VISIBLE)
    local s = overlay:AddChildToOverlay(backdrop)
    s:SetHorizontalAlignment(H_FILL)
    s:SetVerticalAlignment(V_FILL)

    local window = self:Box(st.window, Margin(0))
    self.windowBox = self:Sized(window, self.place.w or st.width, self.place.h or st.height)
    s = overlay:AddChildToOverlay(self.windowBox)
    s:SetHorizontalAlignment(H_CENTER)
    s:SetVerticalAlignment(V_CENTER)
    local layers = Make("Overlay", self.tree)
    window:SetContent(layers)
    local column = Make("VerticalBox", self.tree)
    s = layers:AddChildToOverlay(column)
    s:SetHorizontalAlignment(H_FILL)
    s:SetVerticalAlignment(V_FILL)
    -- the grip in the bottom right corner resizes the window
    local gripMark = self:Box(st.accent)
    local grip = self:Button(self:Sized(gripMark, 10, 10), st.window, st.chipHover, Margin(3))
    pcall(function() grip:SetCursor(CURSOR_RESIZE_SE) end)
    s = layers:AddChildToOverlay(grip)
    s:SetHorizontalAlignment(H_RIGHT)
    s:SetVerticalAlignment(V_BOTTOM)
    self.grip = grip
    self:Clickable(grip, st.window, function() self:BeginDrag("size", grip) end, true)

    -- title bar: name, search, the switches, close
    -- The bar is two layers: underneath, a plain button over the whole bar that moves the window
    -- when pressed; on top, the title, the search box and the buttons (the title lets the mouse
    -- through to the button underneath, the search box and the buttons take their own clicks).
    local barLayers = Make("Overlay", self.tree)
    Add(column, barLayers, nil, nil, V_FILL)
    local dragFill = Make("SizeBox", self.tree)
    local drag = self:Button(dragFill, st.bar, st.dragHover, Margin(0))
    pcall(function() drag:SetCursor(CURSOR_GRAB) end)
    s = barLayers:AddChildToOverlay(drag)
    s:SetHorizontalAlignment(H_FILL)
    s:SetVerticalAlignment(V_FILL)
    self.dragBar = drag
    local barPad = Make("Border", self.tree)
    barPad:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
    barPad:SetPadding(Margin(16, 10, 12, 10))
    barPad:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    s = barLayers:AddChildToOverlay(barPad)
    s:SetHorizontalAlignment(H_FILL)
    s:SetVerticalAlignment(V_FILL)
    local bar = Make("HorizontalBox", self.tree)
    bar:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    barPad:SetContent(bar)
    local title = self:Text(st.titleSize, st.accent, st.titleFont, st.titleFont:find("Roboto", 1, true) ~= nil)
    title:SetText(FText(self.title or st.title))
    title:SetVisibility(3)                          -- HitTestInvisible: dragging works on the title too
    Add(bar, title, nil, Margin(0, 0, 24, 0))
    local searchLabel = self:Text(st.textSize, st.dim)
    searchLabel:SetText(FText("Search"))
    searchLabel:SetVisibility(3)
    Add(bar, searchLabel, nil, Margin(0, 0, 8, 0))
    local searchBox = self:Box(st.input, Margin(10, 6))
    self.search = self:Input()
    self.search:SetHintText(FText("words in this tab..."))
    searchBox:SetContent(self.search)
    Add(bar, self:Sized(searchBox, 280, nil), "fill", Margin(0, 0, 16, 0), V_CENTER, H_LEFT)
    self.optionChips = {}
    for _, o in ipairs(self.optionList) do
        local chip = self:Chip(o.label, st.smallSize, Margin(10, 5), function() self:ToggleOption(o.key) end, true)
        self.optionChips[o.key] = chip
        Add(bar, chip.outer, nil, Margin(0, 0, 8, 0))
    end
    self.closeChip = self:Chip("X", st.textSize, Margin(12, 5), function() self:Close() end, true)
    Add(bar, self.closeChip.outer, nil, Margin(8, 0, 0, 0))
    self:Clickable(drag, st.bar, function() self:BeginDrag("move", drag) end, true)
    Add(column, self:Sized(self:Box(st.accent), nil, 2), nil, nil, V_FILL)

    -- body: tabs on the left, the tab's lines on the right
    local body = Make("HorizontalBox", self.tree)
    Add(column, body, "fill", nil, V_FILL)
    local sideBox = self:Box(st.bar, Margin(0, 8))
    Add(body, self:Sized(sideBox, st.sidebar, nil), nil, nil, V_FILL)
    local side = Make("VerticalBox", self.tree)
    sideBox:SetContent(side)
    self.tabChips = {}
    for i, tab in ipairs(self.tabs) do
        local h = Make("HorizontalBox", self.tree)
        local mark = self:Box(st.accent)
        Add(h, self:Sized(mark, 4, 22), nil, Margin(0, 0, 12, 0))
        local text = self:Text(st.tabSize, st.text)
        text:SetText(FText(tab.name))
        Add(h, text, "fill")
        local button = self:Button(h, st.bar, st.barHover, Margin(10, 8))
        local chip = { button = button, text = text, mark = mark }
        chip.click = self:Clickable(button, st.bar, function() self:SelectTab(i) end, true)
        Add(side, button, nil, Margin(0, 1), V_FILL, H_FILL)
        self.tabChips[i] = chip
    end
    self.scroll = Make("ScrollBox", self.tree)
    pcall(function() self.scroll:SetAnimateWheelScrolling(st.animate) end)   -- the engine's smooth scrolling
    Add(body, self.scroll, "fill", Margin(10, 8, 6, 8), V_FILL)

    -- status line: what the last button said
    local statusBox = self:Box(st.bar, Margin(16, 8))
    Add(column, self:Sized(statusBox, nil, 74), nil, nil, V_FILL)
    self.status = self:Text(st.smallSize, st.dim)
    self.status.AutoWrapText = true
    self.status:SetText(FText(""))
    statusBox:SetContent(self.status)

    self.rows = {}
    self:Font(st.codeFont)                         -- loaded now, for the Code tab
end

-- One line of the list (made when first needed, then reused). A line is either a plain line
-- (name, amount box, buttons, note, value) or one wide button (a spawn name, a group title).
function Menu:NewRow()
    local st = self.style
    local r = {}
    r.root = Make("VerticalBox", self.tree)

    r.plain = self:Box(st.row, Margin(12, 5))
    Add(r.root, r.plain, nil, nil, V_FILL)
    local h = Make("HorizontalBox", self.tree)
    r.plain:SetContent(h)
    r.label = self:Text(st.textSize, st.text)
    r.label.AutoWrapText = true                        -- a long name takes two lines, never the boxes' room
    r.labelSize = self:Sized(r.label, st.labelWidth, nil)
    Add(h, r.labelSize, nil, Margin(0, 0, 10, 0))
    r.note = self:Text(st.textSize, st.dim)
    r.note.AutoWrapText = true
    Add(h, r.note, "fill")
    r.swatch = self:Box(st.text)                       -- a colour sample (Settings), hidden otherwise
    r.swatchSize = self:Sized(r.swatch, 22, 22)
    Add(h, r.swatchSize, nil, Margin(0, 0, 8, 0))
    r.inputSize = Make("SizeBox", self.tree)               -- its box is made when first needed
    r.inputSize:SetWidthOverride(100)
    Add(h, r.inputSize, nil, Margin(0, 0, 8, 0))
    r.chipBox = Make("HorizontalBox", self.tree)           -- its buttons too
    Add(h, r.chipBox)
    r.chips = {}
    r.info = self:Text(st.smallSize, st.dim)
    r.info.AutoWrapText = true
    Add(h, r.info, "fill", Margin(6, 0, 6, 0))
    r.hint = self:Text(st.textSize, st.accent, nil, true)
    Add(h, r.hint, nil, Margin(6, 0, 0, 0), V_CENTER, H_RIGHT)

    local wh = Make("HorizontalBox", self.tree)
    r.wideText = self:Text(st.textSize, st.text)
    r.wideText.AutoWrapText = true
    Add(wh, r.wideText, "fill")
    r.wideHead = self:Text(st.textSize + 1, st.accent, nil, true)
    Add(wh, r.wideHead, "fill")
    r.wideSub = self:Text(st.smallSize, st.dim)
    Add(wh, r.wideSub, nil, Margin(10, 0, 0, 0), V_CENTER, H_RIGHT)
    r.wide = self:Button(wh, st.item, st.itemHover, Margin(14, 5))
    Add(r.root, r.wide, nil, Margin(0, 1, 0, 0), V_FILL)
    r.wideClick = self:Clickable(r.wide, st.item, function() self:RowClicked(r) end)

    self.scroll:AddChild(r.root)
    self.rows[#self.rows + 1] = r
    return r
end

-- The amount box of a line, made the first time the line needs one.
function Menu:RowInput(r)
    if not r.input then
        local box = self:Box(self.style.input, Margin(8, 3))
        local input = self:Input()
        box:SetContent(input)
        r.inputSize:AddChild(box)
        r.input = input
    end
    return r.input
end

-- The code box of a line (the Code tab's editor), made the first time a line needs one.
function Menu:RowCode(r)
    if not r.code then
        local st = self.style
        local box = self:Box(st.input, Margin(10, 8))
        local layers = Make("Overlay", self.tree)
        box:SetContent(layers)
        -- the line Find found: a band behind the text (placed once the text is measured)
        local a = st.accent
        local markSize = self:Sized(self:Box({ a[1], a[2], a[3], 0.35 }), nil, 20)
        markSize:SetVisibility(COLLAPSED)
        local slot = layers:AddChildToOverlay(markSize)
        slot:SetHorizontalAlignment(H_FILL)
        slot:SetVerticalAlignment(V_TOP)
        r.markSize, r.markSlot = markSize, slot
        local code = Make("MultiLineEditableText", self.tree)
        pcall(function()
            local font = self:Font(st.codeFont) or self:Font(st.font)
            if font then
                code.Font.FontObject = font
                code.Font.TypefaceFontName = FName("Default")
                code.WidgetStyle.Font.FontObject = font
                code.WidgetStyle.Font.TypefaceFontName = FName("Default")
            end
            code.Font.Size = st.codeSize
            code.WidgetStyle.Font.Size = st.codeSize
            Paint(code.WidgetStyle.ColorAndOpacity.SpecifiedColor, st.text)
            code.WidgetStyle.ColorAndOpacity.ColorUseRule = 0
        end)
        slot = layers:AddChildToOverlay(code)
        slot:SetHorizontalAlignment(H_FILL)
        slot:SetVerticalAlignment(V_FILL)
        Add(r.root, box, nil, Margin(0, 2, 0, 2), V_FILL)
        r.code, r.codeBox = code, box
    end
    return r.code
end

local function CodeText(r)
    if not r.code then return nil end
    local ok, text = pcall(function() return r.code:GetText():ToString() end)
    if not ok or not text then return nil end
    return (text:gsub("\r\n", "\n"))
end

-- Button i of a line, made the first time the line needs that many.
function Menu:RowChip(r, i)
    while #r.chips < i do
        local index = #r.chips + 1
        local chip = self:Chip("", self.style.textSize, Margin(10, 4), function() self:ChipClicked(r, index) end)
        Add(r.chipBox, chip.outer, nil, Margin(0, 0, 6, 0))
        r.chips[index] = chip
    end
    return r.chips[i]
end

--------------------------------------------------------------------------------------------------
-- Filling the list
--------------------------------------------------------------------------------------------------
local Builder = {}
Builder.__index = Builder

function Builder:Header(text, key)
    self.lines[#self.lines + 1] = { kind = "header", text = text, key = key }
    self.group = key
end

function Builder:Row(t)
    t.kind, t.group = "row", self.group
    self.lines[#self.lines + 1] = t
end

function Builder:Item(t)
    t.kind, t.group = "item", self.group
    self.lines[#self.lines + 1] = t
end

function Builder:Note(text)
    self.lines[#self.lines + 1] = { kind = "note", text = text, group = self.group }
end

-- A box to edit text in (many lines): key names it, text is what it starts with. mark: a line to
-- mark and scroll to (Find); a new markSeq scrolls to it again.
function Builder:Editor(t)
    t.kind = "editor"
    self.lines[#self.lines + 1] = t
end

-- Every word of what was typed is somewhere in the line: its name, note, value, the text on its
-- right, its buttons, or its hidden search text (a spawn name's class and path).
local function Matches(line, want)
    local parts = { line.text, line.label, line.info, line.hint, line.sub, line.find }
    for _, c in ipairs(line.chips or {}) do parts[#parts + 1] = c[1] end
    local hay = {}
    for _, p in pairs(parts) do
        if type(p) == "string" then hay[#hay + 1] = p:lower() end
    end
    hay = table.concat(hay, " ")
    for word in want:gmatch("%S+") do
        if not hay:find(word, 1, true) then return false end
    end
    return true
end
Kit.Matches = Matches

-- Which lines show: groups with a key open and close; while searching, only lines that match
-- (and the titles of their groups).
function Menu:Visible(lines)
    local out = {}
    local want = self.searchText:lower()
    if want == "" then
        for _, l in ipairs(lines) do
            if l.kind == "header" or not l.group or self.expanded[l.group] then out[#out + 1] = l end
        end
        return out
    end
    local pendingHeader
    for _, l in ipairs(lines) do
        if l.kind == "header" then
            pendingHeader = l
        elseif l.kind == "editor" or Matches(l, want) then
            if pendingHeader then out[#out + 1] = pendingHeader; pendingHeader = nil end
            out[#out + 1] = l
        end
    end
    return out
end

local function BoxText(r)
    if not r.input then return nil end
    local ok, text = pcall(function() return r.input:GetText():ToString() end)
    if ok then return text end
    return nil
end

-- A box shows its line's own value again on the next draw (after that value was saved).
function Menu:ResetInput(key)
    self.inputs[key] = nil
    self.resetInputs[key] = true
end

-- Remember what was typed in the amount boxes and the code box on screen.
function Menu:KeepInputs()
    for _, r in ipairs(self.rows) do
        local line = r.line
        if line and line.input and line.input.key and not self.resetInputs[line.input.key] then
            local text = BoxText(r)
            if text then self.inputs[line.input.key] = text end
        end
        if line and line.kind == "editor" and r.codeKey == line.key then
            local text = CodeText(r)
            if text then self.codeBuffers[line.key] = text end
        end
    end
end

-- What is in the code box for key now (the edited text), or nil if it was never edited.
function Menu:EditorText(key)
    self:KeepInputs()
    return self.codeBuffers[key]
end

-- Throw away the edits of key: the box shows text again.
function Menu:ForgetEdits(key, text)
    self.codeBuffers[key] = nil
    for _, r in ipairs(self.rows) do
        if r.codeKey == key and r.code then pcall(function() r.code:SetText(FText(text)) end) end
    end
end

-- Put changed amounts (a button that sets one) into their boxes on screen.
function Menu:PushInputs()
    for _, r in ipairs(self.rows) do
        local line = r.line
        if line and line.input and line.input.key and self.inputs[line.input.key] ~= nil then
            local value = self.inputs[line.input.key]
            if r.input and BoxText(r) ~= value then pcall(function() r.input:SetText(FText(value)) end) end
        end
    end
end

function Menu:Render()
    if not self:Alive() then return end
    local st, cache = self.style, self.cache
    self:KeepInputs()
    local tab = self.tabs[self.tab]
    local b = setmetatable({ lines = {}, options = self.options, inputs = self.inputs }, Builder)
    local ok, err = pcall(tab.build, b, self)
    if not ok then b.lines = { { kind = "note", text = tab.name .. " could not be shown: " .. tostring(err) } } end
    local lines = self:Visible(b.lines)
    local shown = math.min(#lines, st.maxRows)
    if #lines > st.maxRows then
        lines[shown] = { kind = "note", text = string.format("... and %d more: type in the search box to narrow it down",
            #lines - st.maxRows + 1) }
    end
    local made = 0
    while #self.rows < shown and made < st.rowsPerFrame do
        self:NewRow()
        made = made + 1
    end
    self.needMore = #self.rows < shown           -- the rest next frame
    if self.needMore then shown = #self.rows end
    for i, r in ipairs(self.rows) do
        local l = i <= shown and lines[i] or nil
        r.line = l
        Show(cache, r.root, l ~= nil)
        if l then self:FillRow(r, l, i) end
    end
    for i, chip in ipairs(self.tabChips) do
        local shown = not self.tabs[i].advanced or self.options.advanced
        Show(cache, chip.button, shown, VISIBLE)
        chip.click.off = not shown
        Show(cache, chip.mark, i == self.tab and st.tabStyle ~= "fill")
        self:Tint(chip.click, i == self.tab and st.on or nil)
    end
    for _, o in ipairs(self.optionList) do
        local chip = self.optionChips[o.key]
        SetText(cache, chip.text, o.label .. (self.options[o.key] and ": on" or ": off"))
        self:Tint(chip.click, self.options[o.key] and st.on or nil)
    end
end

function Menu:FillRow(r, l, index)
    local st, cache = self.style, self.cache
    if l.kind == "editor" then
        Show(cache, r.plain, false)
        Show(cache, r.wide, false)
        local code = self:RowCode(r)
        Show(cache, r.codeBox, true)
        if r.codeKey ~= l.key then
            code:SetText(FText(self.codeBuffers[l.key] or l.text or ""))
            r.codeKey = l.key
            r.markKey = nil
        end
        local markKey = l.mark and (l.mark .. " " .. (l.markSeq or 0)) or nil
        if r.markKey ~= markKey then
            r.markKey = markKey
            if l.mark then
                self.pendingMark = { row = r, line = l.mark, frames = 2 }   -- once the engine has measured it
            else
                self.pendingMark = nil
                Show(cache, r.markSize, false)
            end
        end
        r.wideLine = false
        return
    end
    if r.codeBox then
        Show(cache, r.codeBox, false)
        r.codeKey = nil
    end
    local wide = l.kind == "item" or l.kind == "header"
    r.wideLine = wide
    Show(cache, r.plain, not wide)
    Show(cache, r.wide, wide, VISIBLE)
    if wide then
        local header = l.kind == "header"
        Show(cache, r.wideHead, header)
        Show(cache, r.wideText, not header)
        if header then
            local mark = ""
            if l.key and self.searchText == "" then mark = self.expanded[l.key] and "v  " or ">  " end
            SetText(cache, r.wideHead, mark .. l.text)
        else
            SetText(cache, r.wideText, l.label or "")
        end
        local sub = header and nil or l.sub
        Show(cache, r.wideSub, sub ~= nil)
        if sub then SetText(cache, r.wideSub, sub) end
        r.wideClick.off = header and not l.key
        self:Tint(r.wideClick, header and st.header or nil)
        return
    end

    local isRow = l.kind == "row"
    if cache["bg " .. index] ~= (index % 2) then
        cache["bg " .. index] = index % 2
        r.plain:SetBrushColor(Color((index % 2 == 0) and st.rowAlt or st.row))
    end
    Show(cache, r.labelSize, isRow)
    if isRow then SetText(cache, r.label, l.label or "") end
    Show(cache, r.note, not isRow)
    if not isRow then SetText(cache, r.note, l.text or "") end

    Show(cache, r.swatchSize, isRow and l.swatch ~= nil)
    if isRow and l.swatch then
        local key = table.concat(l.swatch, ",")
        if cache["swatch " .. index] ~= key then
            cache["swatch " .. index] = key
            r.swatch:SetBrushColor(Color(l.swatch))
        end
    end
    local input = isRow and l.input or nil
    Show(cache, r.inputSize, input ~= nil)
    if input then
        local width = input.width or 100
        if cache["width " .. index] ~= width then
            cache["width " .. index] = width
            r.inputSize:SetWidthOverride(width)
        end
        local value = self.inputs[input.key]
        if value == nil then value = input.default or ""; self.inputs[input.key] = value end
        self.resetInputs[input.key] = nil
        -- Only when it differs (a button changed it, or another line now uses this box), so the
        -- cursor stays put while you type.
        local box = self:RowInput(r)
        if BoxText(r) ~= value then box:SetText(FText(value)) end
    end
    if isRow and l.chips and #l.chips > 0 then self:RowChip(r, math.min(#l.chips, 4)) end
    for i, chip in ipairs(r.chips) do
        local c = isRow and l.chips and l.chips[i] or nil
        Show(cache, chip.outer, c ~= nil, chip.outerShown)
        if c then
            local asking = self.confirm and self.confirm.row == r and self.confirm.index == i
            SetText(cache, chip.text, asking and (type(c.confirm) == "string" and c.confirm or "Sure?") or c[1])
            self:Tint(chip.click, asking and st.confirm or nil)
        end
    end
    local info = isRow and l.info or nil
    if self.options.advanced and isRow and l.chips and l.chips[1] and type(l.chips[1][2]) == "string" then
        info = (info and (info .. "   ") or "") .. "[" .. l.chips[1][2] .. "]"
    end
    Show(cache, r.info, info ~= nil)
    if info then SetText(cache, r.info, info) end
    local hint = isRow and l.hint ~= nil and l.hint ~= "" and tostring(l.hint) or nil
    Show(cache, r.hint, hint ~= nil)
    if hint then SetText(cache, r.hint, hint) end
end

--------------------------------------------------------------------------------------------------
-- Clicks
--------------------------------------------------------------------------------------------------
function Menu:Status(lines)
    if type(lines) == "string" then lines = { lines } end
    if not lines or #lines == 0 then return end
    for _, l in ipairs(lines) do
        self.statusLines[#self.statusLines + 1] = l
    end
    while #self.statusLines > 4 do table.remove(self.statusLines, 1) end
    if self:Alive() then pcall(function() self.status:SetText(FText(table.concat(self.statusLines, "\n"))) end) end
end

-- Run an action: a console line ({} = this line's amount, {name} = another line's) or a function.
function Menu:Act(action, line)
    self:KeepInputs()
    local result
    if type(action) == "function" then
        result = action(self.inputs, line)
        self:PushInputs()
    else
        local own = line and line.input and self.inputs[line.input.key] or ""
        local text = action:gsub("{(%w*)}", function(name)
            if name == "" then return own end
            return self.inputs[name] or ""
        end)
        text = text:gsub("%s+$", "")
        result = self.run(text)
    end
    if self.destroyed then return end
    if result then self:Status(result) end
    self:Render()
end

function Menu:ChipClicked(r, index)
    local l = r.line
    local c = l and l.chips and l.chips[index]
    if not c then return end
    if c.confirm then
        local waiting = self.confirm and self.confirm.row == r and self.confirm.index == index
            and os.clock() < self.confirm.untilTime
        if not waiting then
            self.confirm = { row = r, index = index, untilTime = os.clock() + self.style.confirmSeconds }
            self:Render()
            return
        end
    end
    self.confirm = nil
    self:Act(c[2], l)
end

function Menu:RowClicked(r)
    local l = r.line
    if not l then return end
    if l.kind == "header" and l.key then
        self.expanded[l.key] = not self.expanded[l.key] or nil
        self:Render()
    elseif l.kind == "item" and l.action then
        self:Act(l.action, l)
    end
end

function Menu:SelectTab(i)
    if i == self.tab then return end
    self:KeepInputs()
    self.tab, self.confirm = i, nil
    self.searchText = ""
    pcall(function() self.search:SetText(FText("")) end)
    self:Render()
    pcall(function() self.scroll:ScrollToStart() end)
    -- the new tab's lines fade and slide in
    self:Animate("tab", 0.14, function(e)
        self.scroll:SetRenderOpacity(0.25 + 0.75 * e)
        self.scroll:SetRenderTranslation({ X = (1 - e) * 10, Y = 0.0 })
    end)
end

function Menu:ToggleOption(key)
    self.options[key] = not self.options[key]
    if key == "advanced" and not self.options.advanced and self.tabs[self.tab].advanced then
        self:KeepInputs()
        self.tab = 1                                  -- that tab only shows with Advanced on
    end
    self:Render()
end

-- Go to the tab with that name (when the menu is opened again after reloadconfig).
function Menu:SelectTabByName(name)
    for i, tab in ipairs(self.tabs) do
        if tab.name == name then
            if tab.advanced then self.options.advanced = true end
            self:SelectTab(i)
            return true
        end
    end
    return false
end

local function Hovered(c)
    if c.off then return false end
    local ok, over = pcall(function() return c.button:IsHovered() end)
    return ok and over == true
end

-- The button under the mouse, of those on screen now.
function Menu:HoveredClickable()
    for _, c in ipairs(self.fixed) do
        if Hovered(c) then return c end
    end
    for _, r in ipairs(self.rows) do
        local l = r.line
        if l then
            if r.wideLine then
                if Hovered(r.wideClick) then return r.wideClick end
            else
                for i, chip in ipairs(r.chips) do
                    if l.chips and l.chips[i] and Hovered(chip.click) then return chip.click end
                end
            end
        end
    end
    return nil
end

--------------------------------------------------------------------------------------------------
-- Moving and resizing
--------------------------------------------------------------------------------------------------
function Menu:MousePos()
    local ok, p = pcall(function() return self.wll:GetMousePositionOnViewport(self.pc) end)
    if ok and p and type(p.X) == "number" then return p end
    return nil
end

-- The viewport in the same units as the window (screen pixels / the engine's DPI scale).
function Menu:ViewportSize()
    local ok, size, scale = pcall(function()
        return self.wll:GetViewportSize(self.pc), self.wll:GetViewportScale(self.pc)
    end)
    if not (ok and size and scale and scale > 0) then return nil end
    return size.X / scale, size.Y / scale
end

-- Size and place the window from self.place (x, y: offset from the middle of the screen).
function Menu:ApplyPlace(slide)
    local st, p, cache = self.style, self.place, self.cache
    local w, h = p.w or st.width, p.h or st.height
    if cache.w ~= w then cache.w = w; self.windowBox:SetWidthOverride(w) end
    if cache.h ~= h then cache.h = h; self.windowBox:SetHeightOverride(h) end
    self.windowBox:SetRenderTranslation({ X = p.x or 0, Y = (p.y or 0) + (slide or 0) })
end

function Menu:BeginDrag(kind, button)
    local mouse = self:MousePos()
    if not mouse then return end
    local p, st = self.place, self.style
    self.drag = { kind = kind, button = button, mouse = mouse, x = p.x or 0, y = p.y or 0,
                  w = p.w or st.width, h = p.h or st.height }
    self.drag.vw, self.drag.vh = self:ViewportSize()
    if self.drag.vw then                           -- the size as drawn
        self.drag.w, self.drag.h = math.min(self.drag.w, self.drag.vw), math.min(self.drag.h, self.drag.vh)
    end
end

-- Every frame while the title bar or the grip stays pressed.
function Menu:StepDrag()
    local d = self.drag
    local ok, held = pcall(function() return d.button:IsPressed() end)
    if not (ok and held) then self.drag = nil return end
    local mouse = self:MousePos()
    if not mouse then return end
    local dx, dy = mouse.X - d.mouse.X, mouse.Y - d.mouse.Y
    local p, st = self.place, self.style
    local w, h = d.w, d.h
    if d.kind == "size" then
        w = math.max(st.minWidth, d.w + dx)
        h = math.max(st.minHeight, d.h + dy)
        if d.vw then w, h = math.min(w, d.vw), math.min(h, d.vh) end
        p.w, p.h = math.floor(w), math.floor(h)
        -- the top left corner stays where it is (the window grows to the right and down)
        p.x, p.y = d.x + (p.w - d.w) / 2, d.y + (p.h - d.h) / 2
    else
        p.x, p.y = d.x + dx, d.y + dy
    end
    self:ClampPlace(d.vw, d.vh)
    self:ApplyPlace()
end

-- Keep the title bar on the screen. The window is drawn at most as big as the screen, so that is
-- the size used here.
function Menu:ClampPlace(vw, vh)
    if not vw then return end
    local st, p = self.style, self.place
    local w, h = math.min(p.w or st.width, vw), math.min(p.h or st.height, vh)
    p.x = math.max(120 - vw / 2 - w / 2, math.min(p.x or 0, vw / 2 + w / 2 - 120))
    p.y = math.max(h / 2 - vh / 2, math.min(p.y or 0, vh / 2 + h / 2 - 50))
end

-- Back to the middle of the screen at the normal size.
function Menu:ResetPlace()
    self.place.x, self.place.y, self.place.w, self.place.h = 0, 0, nil, nil
    self:ApplyPlace()
end

--------------------------------------------------------------------------------------------------
-- Animations: a few engine calls per frame while one runs (opacity and position only), nothing
-- otherwise. fn(e) gets e going from 0 to 1 (eased) over `seconds`; done() runs at the end.
--------------------------------------------------------------------------------------------------
function Menu:Animate(name, seconds, fn, done)
    self.anims = self.anims or {}
    if not self.style.animate then
        pcall(fn, 1)
        if done then pcall(done) end
        self.anims[name] = nil
        return
    end
    self.anims[name] = { start = os.clock(), seconds = seconds, fn = fn, done = done }
    pcall(fn, 0)
end

function Menu:StepAnims()
    if not (self.anims and next(self.anims)) then return end
    if not self:Here() then self.anims = {} return end
    local now = os.clock()
    for name, a in pairs(self.anims) do
        local t = math.min(1, (now - a.start) / a.seconds)
        pcall(a.fn, 1 - (1 - t) ^ 3)                -- ease out
        if t >= 1 then
            self.anims[name] = nil
            if a.done then pcall(a.done) end
        end
    end
end

--------------------------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------------------------
-- Whether the window is still in the world the local player is in now. The local player itself
-- lives as long as the game, so asking it is always safe; the window is only touched when this is
-- true (after a map change the engine frees it, and even asking a freed widget whether it is valid
-- reads freed memory). A guest whose host changes the map gets no RemoveAllWidgets call, so every
-- way in (Escape, a bind, a notice, the next frame) checks this first.
function Menu:Here()
    if self.destroyed then return false end
    local ok, world = pcall(function() return self.lp.PlayerController:GetWorld():GetAddress() end)
    return ok and world == self.worldAddress
end

function Menu:Alive()
    return self:Here() and Valid(self.root)
end

-- Whether this menu was built for that controller in its current world. Checked before the menu
-- touches any of its widgets: after a map change the engine has freed them, and even asking a
-- freed widget whether it is valid reads freed memory.
function Menu:BelongsTo(pc)
    if self.destroyed then return false end
    local ok, world = pcall(function() return pc:GetWorld():GetAddress() end)
    return pc:GetAddress() == self.pcAddress and ok and world == self.worldAddress
end

-- Whether that (live) controller is in the world this window was made in: then the window is
-- still there and can be closed and taken off the screen properly, even for another controller
-- (the free camera has its own).
function Menu:SameWorld(pc)
    if self.destroyed or not pc then return false end
    local ok, world = pcall(function() return pc:GetWorld():GetAddress() end)
    return ok and world == self.worldAddress
end

-- The window is gone with the old map, so it is never touched again. If it was open on this same
-- controller (a map change that keeps the controller), the mouse cursor goes back to how it was,
-- or the character could not walk (the game stops movement while the cursor shows).
function Menu:Abandon(controller, wasOpen)
    if (wasOpen or self.open) and controller and controller:GetAddress() == self.pcAddress then
        pcall(function() controller.bShowMouseCursor = self.cursorBefore or false end)
    end
    self.open, self.destroyed = false, true
end

-- The game is about to clear the screen (RemoveAllWidgets): close now, while the window still
-- exists and before the game sets up its own screen, then never touch it again.
function Menu:Removed()
    if self.destroyed then return end
    if self.open then self:Close() end
    self.destroyed = true
end

function Menu:Open()
    if not self:Alive() then return false end
    if not self.root:IsInViewport() then self.root:AddToViewport(self.style.zOrder) end
    if self.anims then self.anims.close = nil end
    self:ClampPlace(self:ViewportSize())            -- a saved place or size may be off the screen now
    self.root:SetVisibility(SELF_HIT_TEST_INVISIBLE)
    -- fade in, the window rising a little into place
    self:Animate("open", 0.16, function(e)
        self.root:SetRenderOpacity(e)
        self:ApplyPlace((1 - e) * 18)
    end)
    self.lp = self.pc.Player                      -- the local player keeps its controller up to date
    self.cursorBefore = self.pc.bShowMouseCursor
    self.pc.bShowMouseCursor = true
    self.wbl:SetInputMode_UIOnlyEx(self.pc, self.root, 0)        -- 0: do not lock the mouse
    self.open, self.clicks = true, 0
    self.nextTick, self.nextRefresh = 0, os.clock() + 1
    self:Render()
    return true
end

-- Give the game its keys and mouse back the way it had them, through whichever controller the
-- local player has now (the free camera has its own).
function Menu:GiveBackInput()
    -- the cursor back on the controller the menu turned it on for (the character's one)
    pcall(function()
        if Valid(self.pc) then self.pc.bShowMouseCursor = self.cursorBefore or false end
    end)
    pcall(function()
        local pc = self.lp and Valid(self.lp) and self.lp.PlayerController or self.pc
        if not Valid(pc) then return end
        if self.cursorBefore then
            self.wbl:SetInputMode_GameAndUIEx(pc, NoObject(), 0, false)
        else
            pc.bShowMouseCursor = false
            self.wbl:SetInputMode_GameOnly(pc)
        end
    end)
end

-- Whether you are typing in the menu right now (the search box or an amount box).
function Menu:Typing()
    if not (self.open and self:Alive()) then return false end
    local function focused(w)
        local ok, yes = pcall(function() return w:HasKeyboardFocus() end)
        return ok and yes == true
    end
    if focused(self.search) then return true end
    for _, r in ipairs(self.rows) do
        if r.line and r.line.input and r.input and focused(r.input) then return true end
    end
    return self:EditingCode()
end

-- The line Find found: the band behind it in the code box, and the list scrolled so it shows a
-- few lines down from the top. The engine measures text a frame after it changes, so this runs a
-- couple of frames after the line was given. Every line of the code box is as tall as the others
-- (one font, no wrapping): the box's height over its number of lines.
function Menu:StepMark()
    local p = self.pendingMark
    p.frames = p.frames - 1
    if p.frames > 0 then return end
    self.pendingMark = nil
    local r = p.row
    if not (r.code and r.line and r.line.kind == "editor" and r.line.mark == p.line) then return end
    local ok, err = pcall(function()
        local _, breaks = (CodeText(r) or ""):gsub("\n", "")
        local size = r.code:GetDesiredSize()
        local height = size and size.Y or 0
        local lineHeight = height > 0 and height / (breaks + 1) or self.style.codeSize * 1.55
        local top = (p.line - 1) * lineHeight
        r.markSize:SetHeightOverride(lineHeight)
        r.markSlot:SetPadding(Margin(0, top, 0, 0))
        Show(self.cache, r.markSize, true, 3)                  -- HitTestInvisible: clicks reach the text
        local above = 0                                        -- the lines of the list over the code box
        for _, other in ipairs(self.rows) do
            if other == r then break end
            if other.line then above = above + other.root:GetDesiredSize().Y end
        end
        self.scroll:SetScrollOffset(math.max(0, above + 10 + top - 3 * lineHeight))
    end)
    if not ok then self:Status("Find could not scroll there: " .. tostring(err)) end
end

-- Back to the top of the list (a new view in the same tab).
function Menu:ScrollTop()
    pcall(function() self.scroll:ScrollToStart() end)
end

-- Whether you are typing in the code box (Escape then does not close the menu).
function Menu:EditingCode()
    if not (self.open and self:Alive()) then return false end
    for _, r in ipairs(self.rows) do
        if r.line and r.line.kind == "editor" and r.code then
            local ok, yes = pcall(function() return r.code:HasKeyboardFocus() end)
            if ok and yes == true then return true end
        end
    end
    return false
end

function Menu:Close()
    if not self.open then return end
    self.open, self.confirm, self.clicks = false, nil, 0
    if not self:Here() then
        -- another map: the window is gone; only the cursor of a kept controller is put back
        local ok, pc = pcall(function() return self.lp.PlayerController end)
        self:Abandon(ok and pc or nil, true)
        return
    end
    self:KeepInputs()
    if self.anims then self.anims.open = nil end
    -- the game gets its keys back at once; the window fades out (clicks already pass through it)
    pcall(function() self.root:SetVisibility(3) end)            -- ESlateVisibility::HitTestInvisible
    self:Animate("close", 0.12, function(e) self.root:SetRenderOpacity(1 - e) end,
        function() if not self.open then self.root:SetVisibility(COLLAPSED) end end)
    self:GiveBackInput()
end

-- Thrown away for good (reloadconfig): only for a menu that still belongs to this world.
function Menu:Destroy()
    if self.destroyed then return end
    self:Close()
    self.destroyed = true
    pcall(function() self.root:RemoveFromParent() end)
end

-- Every frame (from a controller's tick): cheap unless the menu is open. controller: the one
-- that ticks (on the host every player's controller ticks; only the menu's own counts).
function Menu:Tick(controller)
    if self.destroyed then return end
    if not (controller and controller:GetAddress() == self.tickAddress) then return end
    if self.anims and next(self.anims) then self:StepAnims() end
    if not self.open then return end
    if self.drag then
        if self:Here() then self:StepDrag() else self.drag = nil end
    end
    if (self.clicks or 0) > 0 then
        self.clicks = 0
        if not self:SameWorld(controller) then self:Abandon(controller) return end
        local c = self:HoveredClickable()
        if c then
            local ok, err = pcall(c.fn)
            if not ok then self:Status("menu: " .. tostring(err)) end
        end
        return
    end
    if self.needMore then self:Render() return end     -- more lines for a long list
    if self.pendingMark then self:StepMark() end
    local now = os.clock()
    if now < self.nextTick then return end
    self.nextTick = now + 0.08
    if not self:SameWorld(controller) then
        self:Abandon(controller)                        -- another map: the engine freed the window
        return
    end
    if not self.root:IsInViewport() then
        -- Taken off the screen some other way than RemoveAllWidgets: never touch it again. The
        -- game sets up its own input then; only without the RemoveAllWidgets hook give it back.
        self.open, self.destroyed = false, true
        if not self.removalWatched then self:GiveBackInput() end
        return
    end
    local ok, text = pcall(function() return self.search:GetText():ToString() end)
    if ok and text and text ~= self.searchText then
        self.searchText = text
        self:Render()
        return
    end
    -- amount boxes marked live (a tab's own search) redraw as you type
    for _, r in ipairs(self.rows) do
        local l = r.line
        if l and l.input and l.input.live then
            local typed = BoxText(r)
            if typed and typed ~= self.inputs[l.input.key] then
                self:Render()
                return
            end
        end
    end
    if self.confirm and now >= self.confirm.untilTime then
        self.confirm = nil
        self:Render()
        return
    end
    if now >= self.nextRefresh then
        self.nextRefresh = now + 1
        if not self.tabs[self.tab].still then self:Render() end   -- fresh numbers once a second
    end
end

--------------------------------------------------------------------------------------------------
-- Kit.New{ pc, title, tabs, options, run, style } -> a menu (built at once; errors if it cannot)
--    tabs     { { name, build = function(ui, menu) end, advanced = true or nil, still = true or nil }, ... }
--             (an advanced tab only shows with the Advanced switch on; a still tab has no
--             numbers that change by themselves, so it is not drawn again every second)
--    options  { { key, label }, ... }   switches in the title bar (ui.options[key])
--    run      function(commandLine) -> lines to show
--    place    { x, y, w, h }: where the window is and its size (changed when you move or resize it)
--    keep     an earlier window's { options, expanded, inputs }, to carry over
-- menu.clicks: count a left mouse button press here (config.lua's key watcher does).
--------------------------------------------------------------------------------------------------
-- The colours that go with a base colour (lighter under the mouse...), as the multiple of the base
-- they are made from when the base was changed and they were not.
Kit.Derived = {
    { "bar", "barHover", 2.8 }, { "bar", "dragHover", 1.45 }, { "header", "headerHover", 1.5 },
    { "item", "itemHover", 2.3 }, { "chip", "chipHover", 1.8 }, { "accent", "on", 0.4 },
}

function Kit.New(o)
    local style = {}
    for k, v in pairs(Kit.DefaultStyle) do style[k] = v end
    for k, v in pairs(o.style or {}) do style[k] = v end
    for _, d in ipairs(Kit.Derived) do
        local base, derived, k = d[1], d[2], d[3]
        local given = o.style or {}
        if given[base] and not given[derived] then
            local b = style[base]
            local function c(i)
                if k < 1 then return b[i] * k end
                return math.min(1, math.max(b[i] * k, b[i] + 0.04))   -- lighter, also from black
            end
            style[derived] = { c(1), c(2), c(3), b[4] or 1 }
        end
    end
    -- Buttons get other colours by multiplying (Tint), which needs some colour to multiply: the
    -- base colours of buttons are never fully black in any channel.
    for _, key in ipairs({ "bar", "row", "rowAlt", "item", "chip", "header" }) do
        local b = style[key]
        style[key] = { math.max(b[1], 0.01), math.max(b[2], 0.01), math.max(b[3], 0.01), b[4] or 1 }
    end
    local m = setmetatable({
        pc = o.pc, title = o.title, tabs = o.tabs, optionList = o.options or {}, run = o.run,
        style = style, fixed = {}, cache = {}, options = {}, inputs = {}, resetInputs = {}, expanded = {}, codeBuffers = {},
        statusLines = {}, searchText = "", tab = 1, open = false, clicks = 0,
        place = o.place or { x = 0, y = 0 }, tickPc = o.tickPc,
    }, Menu)
    for _, opt in ipairs(m.optionList) do m.options[opt.key] = opt.default or false end
    -- the window made again (a new look): what was open and switched on stays so
    if o.keep then
        for k, v in pairs(o.keep.options or {}) do m.options[k] = v end
        for k, v in pairs(o.keep.expanded or {}) do m.expanded[k] = v end
        for k, v in pairs(o.keep.inputs or {}) do m.inputs[k] = v end
    end
    m:Build()
    return m
end

-- Every menu window is a copy of the game's unused HammerCursor widget, so all of them, also
-- ones an earlier window or an earlier config.lua lost track of, are found by that class.
Kit.WindowClass = "HammerCursor_C"

-- The game's own per-frame event of your controller, in every map (config.lua hooks it). The
-- test map's and the stealth tutorial's controllers have their own, which run this one first.
Kit.TickEvent = "/Game/BP/Player/RobberController.RobberController_C:ReceiveTick"
-- The game clearing the screen (a native engine function, so UE4SS can hook it).
Kit.RemoveAllEvent = "/Script/UMG.WidgetLayoutLibrary:RemoveAllWidgets"

return Kit
