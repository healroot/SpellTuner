-- Widget kit in the style of Cell's options UI (flat 0.115-grey panels with a
-- 1px black border, class-colour accent, 13px widget font, tab buttons that
-- sit on the top edge of the frame). Written from scratch for SpellTuner: no
-- libraries, no pixel-perfect layer, plain sizes. Exposed on MD.UI and used
-- by the options frame, the debug console and the dashboard.
local _, MD = ...

local UI = {}
MD.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
UI.whiteTexture = WHITE

--------------------------------------------------------------------------------
-- Colours: accent = class colour (Cell convention)
--------------------------------------------------------------------------------
local accent = { 0.7, 0.7, 0.7 }
local accentHex = "|cffb2b2b2"
do
    -- Client call, through the adapter (T2): UnitClass returns localized,
    -- token (or nil, "<reason>" on failure) -- the token is the SECOND
    -- value, and it is only meaningful when the first came back at all
    -- (same rule as Core.lua's DetectProfile, T1b Review re-issue 2).
    local loc, class = MD.API.UnitClass("player")
    if not loc then class = nil end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then
        accent = { c.r, c.g, c.b }
        accentHex = c.colorStr and ("|c" .. c.colorStr)
            or string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
end
UI.accent = accent
UI.accentHex = accentHex
UI.grey = { 0.7, 0.7, 0.7 }
function UI.GetAccentColorRGB() return accent[1], accent[2], accent[3] end

--------------------------------------------------------------------------------
-- Fonts (global font objects, like Cell's CELL_FONT_*)
--------------------------------------------------------------------------------
-- T29: every font object the kit builds, by name, so UI/Theme_Forever.lua's
-- UI.ApplyFonts can resize them in place. Nothing on TBC reads it.
UI.fontObjects = {}
local function MakeFont(name, size, r, g, b)
    local f = _G[name] or CreateFont(name)
    UI.fontObjects[name] = f
    f:SetFont(GameFontNormal:GetFont(), size, "")
    f:SetTextColor(r, g, b, 1)
    f:SetShadowColor(0, 0, 0)
    f:SetShadowOffset(1, -1)
    f:SetJustifyH("CENTER")
    return f
end
UI.FONT_TITLE = "MANADEMON_FONT_TITLE";                 MakeFont(UI.FONT_TITLE, 14, 1, 1, 1)
UI.FONT_TITLE_DISABLE = "MANADEMON_FONT_TITLE_DISABLE"; MakeFont(UI.FONT_TITLE_DISABLE, 14, 0.4, 0.4, 0.4)
UI.FONT = "MANADEMON_FONT";                             MakeFont(UI.FONT, 13, 1, 1, 1)
UI.FONT_DISABLE = "MANADEMON_FONT_DISABLE";             MakeFont(UI.FONT_DISABLE, 13, 0.4, 0.4, 0.4)
UI.FONT_SMALL = "MANADEMON_FONT_SMALL";                 MakeFont(UI.FONT_SMALL, 11, 1, 1, 1)
UI.FONT_SPECIAL = "MANADEMON_FONT_SPECIAL";             MakeFont(UI.FONT_SPECIAL, 12, 1, 1, 1)
UI.FONT_CLASS_TITLE = "MANADEMON_FONT_CLASS_TITLE";     MakeFont(UI.FONT_CLASS_TITLE, 14, accent[1], accent[2], accent[3])
UI.FONT_CLASS = "MANADEMON_FONT_CLASS";                 MakeFont(UI.FONT_CLASS, 13, accent[1], accent[2], accent[3])

--------------------------------------------------------------------------------
-- Tooltip: a private GameTooltip with the flat backdrop. The 2.5.x tooltip
-- template draws a NineSlice and may lack the backdrop mixin, so both are
-- handled defensively; on any failure the stock look is kept.
--------------------------------------------------------------------------------
local tooltip = CreateFrame("GameTooltip", "SpellTunerTooltip", UIParent, "GameTooltipTemplate")
UI.tooltip = tooltip

local function StyleTooltip()
    if tooltip.NineSlice then tooltip.NineSlice:SetAlpha(0) end
    if not tooltip.SetBackdrop and BackdropTemplateMixin then
        Mixin(tooltip, BackdropTemplateMixin)
        tooltip:HookScript("OnSizeChanged", tooltip.OnBackdropSizeChanged)
    end
    if tooltip.SetBackdrop then
        tooltip:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        tooltip:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        tooltip:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end
end
pcall(StyleTooltip)
tooltip:SetOwner(UIParent, "ANCHOR_NONE")
tooltip:HookScript("OnShow", function() pcall(StyleTooltip) end)
tooltip:HookScript("OnHide", function() tooltip:ClearLines() end)

local function ShowTooltips(widget, anchor, x, y, lines)
    if type(lines) ~= "table" or #lines == 0 then
        tooltip:Hide()
        return
    end
    tooltip:SetOwner(widget, anchor or "ANCHOR_TOP", x or 0, y or 0)
    tooltip:AddLine(lines[1])
    for i = 2, #lines do
        if lines[i] then tooltip:AddLine("|cffffffff" .. lines[i]) end
    end
    tooltip:Show()
end

-- UI.SetTooltips(widget, anchor, x, y, title, line2, line3, ...)
function UI.SetTooltips(widget, anchor, x, y, ...)
    if select("#", ...) == 0 or select(1, ...) == nil then return end
    if not widget._tooltipsInited then
        widget._tooltipsInited = true
        widget:HookScript("OnEnter", function() ShowTooltips(widget, anchor, x, y, widget.tooltips) end)
        widget:HookScript("OnLeave", function() tooltip:Hide() end)
    end
    widget.tooltips = { ... }
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- T29 (docs/SPEC-forever-ui.md 4.3): pixel-perfect edges, additive. UI.PIXEL is
-- nil unless UI/Theme_Forever.lua (Forever TOCs only) sets it, so on TBC
-- StylizeFrame draws exactly the backdrop it always drew.
--
-- UI.px(n, frame): n physical pixels in the frame's own units --
-- n * (768 / physicalHeight) / frame:GetEffectiveScale(). The physical height
-- comes through the adapter (MD.API.PhysicalScreenSize, Forever's binding); with
-- no usable answer (TBC, absent, secret, zero) n is returned unchanged.
--------------------------------------------------------------------------------
function UI.px(n, frame)
    local h
    if MD.API.PhysicalScreenSize then
        -- explicit locals: the adapter answers (w, h) or (nil, "<reason>")
        local w, hh = MD.API.PhysicalScreenSize()
        if type(w) == "number" and type(hh) == "number" and hh > 0 then h = hh end
    end
    if not h then return n end
    frame = frame or UIParent
    local s
    if frame and frame.GetEffectiveScale then
        local ok, v = pcall(frame.GetEffectiveScale, frame)
        if ok and type(v) == "number" and v > 0 then s = v end
    end
    return n * (768 / h) / (s or 1)
end

-- Frames styled under UI.PIXEL, weak-keyed so the registry never keeps a frame
-- alive; the value is the colours it was styled with (the fallback when the
-- backdrop cannot say what it shows now).
UI.pixelFrames = setmetatable({}, { __mode = "k" })

local function PixelBackdrop(frame)
    local e = UI.px(1, frame)
    return { bgFile = WHITE, edgeFile = WHITE, edgeSize = e,
             insets = { left = e, right = e, top = e, bottom = e } }
end

function UI.StylizeFrame(frame, color, borderColor)
    color = color or { 0.1, 0.1, 0.1, 0.9 }
    borderColor = borderColor or { 0, 0, 0, 1 }
    if UI.PIXEL then
        frame:SetBackdrop(PixelBackdrop(frame))
        UI.pixelFrames[frame] = { color = color, border = borderColor }
    else
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    end
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(borderColor))
end

-- UI.px is evaluated when a frame is styled, so a UI scale or display change
-- leaves stale edges: re-apply the edge and insets to every registered frame,
-- keeping the colours it shows now (a hover may have changed them since). The
-- window manager calls it on UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED and after
-- db.ui.scale changes. Returns how many frames it restyled.
function UI.RestylePixels()
    local n = 0
    for frame, rec in pairs(UI.pixelFrames) do
        local done = pcall(function()
            -- explicit locals: each getter's four returns kept whole
            local r, g, b, a
            if frame.GetBackdropColor then r, g, b, a = frame:GetBackdropColor() end
            local br, bg, bb, ba
            if frame.GetBackdropBorderColor then br, bg, bb, ba = frame:GetBackdropBorderColor() end
            frame:SetBackdrop(PixelBackdrop(frame))
            if type(r) == "number" then
                frame:SetBackdropColor(r, g, b, a)
            else
                frame:SetBackdropColor(unpack(rec.color))
            end
            if type(br) == "number" then
                frame:SetBackdropBorderColor(br, bg, bb, ba)
            else
                frame:SetBackdropBorderColor(unpack(rec.border))
            end
        end)
        if done then n = n + 1 end
    end
    return n
end

function UI.CreateFrame(name, parent, width, height, isTransparent)
    local f = CreateFrame("Frame", name, parent, "BackdropTemplate")
    f:Hide()
    if not isTransparent then UI.StylizeFrame(f) end
    f:EnableMouse(true)
    if width and height then f:SetSize(width, height) end
    return f
end

-- Frame with a 20px header bar above it (title in class colour, red x).
-- T32: opts (additive; TBC never passes it) -- opts.resizable adds a 16x16 grip
-- at the bottom-right corner (SetResizable, StartSizing); its mouse-up calls
-- f:OnResized() when set, as a drag's end calls f:OnMoved(). The bounds are the
-- caller's (the window manager sets each group's minimum).
function UI.CreateMovableFrame(title, name, width, height, strata, level, notUserPlaced, opts)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetUserPlaced(not notUserPlaced)
    f:SetFrameStrata(strata or "HIGH")
    f:SetFrameLevel(level or 1)
    f:SetClampedToScreen(true)
    f:SetClampRectInsets(0, 0, 20, 0)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:Hide()
    UI.StylizeFrame(f)

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.header = header
    header:EnableMouse(true)
    header:SetClampedToScreen(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        f:StartMoving()
        if notUserPlaced then f:SetUserPlaced(false) end
    end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if f.OnMoved then f:OnMoved() end
    end)
    header:SetPoint("LEFT")
    header:SetPoint("RIGHT")
    header:SetPoint("BOTTOM", f, "TOP", 0, -1)
    header:SetHeight(20)
    UI.StylizeFrame(header, { 0.115, 0.115, 0.115, 1 })

    header.text = header:CreateFontString(nil, "OVERLAY", UI.FONT_CLASS_TITLE)
    header.text:SetText(title)
    header.text:SetPoint("CENTER", header)

    header.closeBtn = UI.CreateButton(header, "x", "red", { 20, 20 }, false, false, UI.FONT_SPECIAL, UI.FONT_SPECIAL)
    header.closeBtn:SetPoint("TOPRIGHT")
    header.closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- T34 (docs/SPEC-forever-ui.md 6.3): opts.back (a label, or true for
    -- "< Back") adds a back button at the header's left, 84x20, hidden until
    -- the window manager shows it; a click calls f:OnBack() when set.
    if opts and opts.back then
        local label = type(opts.back) == "string" and opts.back or "< Back"
        header.backBtn = UI.CreateButton(header, label, "accent-hover", { 84, 20 })
        header.backBtn:SetPoint("TOPLEFT")
        header.backBtn:SetScript("OnClick", function() if f.OnBack then f:OnBack() end end)
        header.backBtn:Hide()
    end

    if opts and opts.resizable then -- T32
        f:SetResizable(true)
        local grip = CreateFrame("Button", nil, f)
        f.resizeGrip = grip
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        grip:SetFrameLevel(f:GetFrameLevel() + 20)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            f:StartSizing("BOTTOMRIGHT")
            if notUserPlaced then f:SetUserPlaced(false) end
        end)
        grip:SetScript("OnMouseUp", function()
            f:StopMovingOrSizing()
            if notUserPlaced then f:SetUserPlaced(false) end
            if f.OnResized then f:OnResized() end
        end)
    end

    return f
end

function UI.CreateSeparator(text, parent, width, color)
    color = color or { accent[1], accent[2], accent[3], 0.777 }
    width = width or parent:GetWidth() - 10

    local fs = parent:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetText(text)

    local line = parent:CreateTexture()
    line:SetSize(width, 1)
    line:SetColorTexture(unpack(color))
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
    local shadow = parent:CreateTexture()
    shadow:SetSize(width, 1)
    shadow:SetColorTexture(0, 0, 0, 1)
    shadow:SetPoint("TOPLEFT", line, "TOPLEFT", 1, -1)
    return fs
end

-- Titled pane: accent title, underline at y = -17, content below.
function UI.CreateTitledPane(parent, text, width, height)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetSize(width, height)

    local line = pane:CreateTexture()
    pane.line = line
    line:SetHeight(1)
    line:SetColorTexture(accent[1], accent[2], accent[3], 0.777)
    line:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -17)
    line:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -17)

    local shadow = pane:CreateTexture()
    shadow:SetHeight(1)
    shadow:SetColorTexture(0, 0, 0, 1)
    shadow:SetPoint("TOPLEFT", line, "TOPLEFT", 1, -1)
    shadow:SetPoint("TOPRIGHT", line, "TOPRIGHT", 1, -1)

    local title = pane:CreateFontString(nil, "OVERLAY", UI.FONT_TITLE)
    pane.title = title
    title:SetJustifyH("LEFT")
    title:SetTextColor(accent[1], accent[2], accent[3])
    title:SetText(text)
    title:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 0, 2)

    function pane:SetTitle(t) title:SetText(t) end
    return pane
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------
local BUTTON_COLORS = {
    ["red"]          = { { 0.6, 0.1, 0.1, 0.6 },          { 0.6, 0.1, 0.1, 1 } },
    ["red-hover"]    = { { 0.115, 0.115, 0.115, 1 },      { 0.6, 0.1, 0.1, 1 } },
    ["green"]        = { { 0.1, 0.6, 0.1, 0.6 },          { 0.1, 0.6, 0.1, 1 } },
    ["green-hover"]  = { { 0.115, 0.115, 0.115, 1 },      { 0.1, 0.6, 0.1, 1 } },
    ["blue-hover"]   = { { 0.115, 0.115, 0.115, 1 },      { 0, 0.5, 0.8, 1 } },
    ["yellow-hover"] = { { 0.115, 0.115, 0.115, 1 },      { 0.7, 0.7, 0, 1 } },
    ["accent"]       = { { accent[1], accent[2], accent[3], 0.3 }, { accent[1], accent[2], accent[3], 0.6 } },
    ["accent-hover"] = { { 0.115, 0.115, 0.115, 1 },      { accent[1], accent[2], accent[3], 0.6 } },
    ["transparent"]  = { { 0, 0, 0, 0 },                  { accent[1], accent[2], accent[3], 0.6 } },
    ["none"]         = { { 0, 0, 0, 0 },                  nil },
}

-- UI.CreateButton(parent, text, colorName, {w, h}, noBorder, noBackground, fontNormal, fontDisable, tooltip...)
function UI.CreateButton(parent, text, buttonColor, size, noBorder, noBackground, fontNormal, fontDisable, ...)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    if parent then b:SetFrameLevel(parent:GetFrameLevel() + 1) end
    b:SetText(text or "")
    b:SetSize(size[1], size[2])

    local pair = BUTTON_COLORS[buttonColor] or { { 0.115, 0.115, 0.115, 1 }, { 0.23, 0.23, 0.23, 1 } }
    b.color, b.hoverColor = pair[1], pair[2]

    local s = b:GetFontString()
    b.fs = s
    if s then
        s:SetWordWrap(false)
        s:SetPoint("LEFT")
        s:SetPoint("RIGHT")
        function b:SetTextColor(...) s:SetTextColor(...) end
    end

    if noBorder then
        b:SetBackdrop({ bgFile = WHITE })
    else
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    end

    if buttonColor == "transparent" then
        if s then
            s:SetJustifyH("LEFT")
            s:SetPoint("LEFT", 5, 0)
            s:SetPoint("RIGHT", -5, 0)
        end
        b:SetBackdropBorderColor(1, 1, 1, 0)
        b:SetPushedTextOffset(0, 0)
    else
        if not noBackground then
            local bg = b:CreateTexture()
            bg:SetDrawLayer("BACKGROUND", -8)
            b.bg = bg
            bg:SetAllPoints(b)
            bg:SetColorTexture(0.115, 0.115, 0.115, 1)
        end
        b:SetBackdropBorderColor(0, 0, 0, 1)
        b:SetPushedTextOffset(0, -1)
    end

    b:SetBackdropColor(unpack(b.color))
    b:SetDisabledFontObject(fontDisable or UI.FONT_DISABLE)
    b:SetNormalFontObject(fontNormal or UI.FONT)
    b:SetHighlightFontObject(fontNormal or UI.FONT)

    if b.hoverColor then
        b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
        b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
    end
    b:SetScript("PostClick", function()
        if SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
    end)

    UI.SetTooltips(b, "ANCHOR_TOPLEFT", 0, 3, ...)
    return b
end

-- Radio-style group: the active button keeps its hover colour. Each button
-- needs an .id; onClick(id, button) fires on click. Returns Highlight(id).
function UI.CreateButtonGroup(buttons, onClick, onActive, onInactive)
    local function Highlight(id)
        for _, b in pairs(buttons) do
            if id == b.id then
                b:SetBackdropColor(unpack(b.hoverColor))
                b:SetScript("OnEnter", nil)
                b:SetScript("OnLeave", nil)
                if onActive then onActive(b.id, b) end
            else
                b:SetBackdropColor(unpack(b.color))
                b:SetScript("OnEnter", function() b:SetBackdropColor(unpack(b.hoverColor)) end)
                b:SetScript("OnLeave", function() b:SetBackdropColor(unpack(b.color)) end)
                if onInactive then onInactive(b.id, b) end
            end
        end
    end
    for _, b in pairs(buttons) do
        b:SetScript("OnClick", function()
            Highlight(b.id)
            onClick(b.id, b)
        end)
    end
    return Highlight
end

--------------------------------------------------------------------------------
-- Navigation (docs/SPEC-v0.11.md §3): one window, groups down the left, that
-- group's views along the top, and -- where a pane needs it -- the same rule
-- again inside a bordered box.
--
-- Written once so the panes stay dumb: a pane is a frame parented to
-- nav:Content(), created LAZILY the first time its view is selected and cached
-- after. A druid who never opens Simulate never builds it.
--
-- The palette is UI.PALETTE and nothing here carries its own literals: the
-- author asked for the settings window's colours everywhere, and "everywhere"
-- only holds if there is one place to change.
--------------------------------------------------------------------------------
UI.PALETTE = {
    frame  = { 0.1, 0.1, 0.1, 0.9 },      -- the window itself (UI.StylizeFrame's default)
    header = { 0.115, 0.115, 0.115, 1 },  -- the title bar and the nav columns
    pane   = { 0.13, 0.13, 0.13, 1 },     -- a box drawn inside the content area
    border = { 0, 0, 0, 1 },
}

local NAV_W = 108        -- the left column
local NAV_TOP = 24       -- the horizontal view row
local NAV_PAD = 8
local RAIL_W = 172       -- T31: a rail group's list column (docs/SPEC-forever-ui.md 3.2)

-- groups: { { id, text, views = { { id, text, hidden }, ... } }, ... }
--   T31 (docs/SPEC-forever-ui.md 3.1), additive: a group with layout = "rail"
--   draws no view row. Its views are the rows of a list down the content's
--   left edge (UI.CreateRail, options from group.rail; a view may also carry
--   icon / tag / new / stale / fixed / tooltip), and its panes are built into
--   the area right of that list (onCreate is handed that area as `content`).
--   The content frame is re-anchored per group: NAV_PAD below the frame's top
--   for a rail group, NAV_TOP + NAV_PAD for any other (today's, and TBC's
--   only, since TBC declares no rail group).
-- onCreate(groupID, viewID, content, nav) -> pane. Called ONCE per view, the
--   first time it is selected; the pane is cached and shown thereafter.
-- onShow(groupID, viewID, pane, nav). Called on every selection, including the
--   first. This is where a pane is refreshed -- rebuilding it instead would
--   throw away its state and its frames every time the author clicked a tab.
-- T32: opts (optional, additive) is handed to UI.CreateMovableFrame -- the
--   Forever window passes { resizable = true, notUserPlaced = true }.
function UI.CreateNavFrame(title, name, width, height, groups, onCreate, onShow, opts)
    local P = UI.PALETTE
    local f = UI.CreateMovableFrame(title, name, width, height, nil, nil, opts and opts.notUserPlaced, opts)
    UI.StylizeFrame(f, P.frame, P.border)

    local nav = { frame = f, groups = groups, buttons = {}, viewButtons = {},
                  group = nil, view = nil }

    -- the left column
    local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    left:SetWidth(NAV_W)
    UI.StylizeFrame(left, P.header, P.border)
    nav.left = left

    -- the content area, and the row of view buttons above it
    local content = CreateFrame("Frame", nil, f)
    nav.content = content
    function nav:Content() return content end

    -- T31: anchored per group -- a rail group has no view row above it
    local function AnchorContent(isRail)
        local top = isRail and -NAV_PAD or -(NAV_TOP + NAV_PAD)
        if nav.contentTop == top then return end
        nav.contentTop = top
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", left, "TOPRIGHT", NAV_PAD, top)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -NAV_PAD, NAV_PAD)
    end
    AnchorContent(false)

    -- T31: a rail group's list and the area right of it, built the first time
    -- the group is asked for, one holder per rail group
    nav.rails = {}
    local function RailOf(group)
        if not group or group.layout ~= "rail" then return nil end
        local h = nav.rails[group.id]
        if h then return h end
        local holder = CreateFrame("Frame", nil, content)
        holder:SetAllPoints(content)
        local o = {}
        for k, v in pairs(group.rail or {}) do o[k] = v end
        local own = o.onSelect
        o.onSelect = function(id)
            nav:Select(group.id, id)
            if own then own(id) end
        end
        local rail = UI.CreateRail(holder, o.width or RAIL_W, o)
        rail.frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        rail.frame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        local view = CreateFrame("Frame", nil, holder)
        view:SetPoint("TOPLEFT", rail.frame, "TOPRIGHT", NAV_PAD, 0)
        view:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
        rail:SetRows(group.views)
        h = { holder = holder, rail = rail, view = view }
        nav.rails[group.id] = h
        if nav.group ~= group.id then holder:Hide() end
        return h
    end
    local function GroupOf(groupID)
        for _, g in ipairs(groups) do if g.id == groupID then return g end end
    end
    -- nav:Rail(groupID) -> the rail (UI.CreateRail's), nav:RailView(groupID) ->
    -- the frame right of it that the group's panes live in; nil for a group
    -- without layout = "rail"
    function nav:Rail(groupID)
        local h = RailOf(GroupOf(groupID))
        return h and h.rail or nil
    end
    function nav:RailView(groupID)
        local h = RailOf(GroupOf(groupID))
        return h and h.view or nil
    end
    local function ShowRails(groupID)
        for id, h in pairs(nav.rails) do
            if id == groupID then h.holder:Show() else h.holder:Hide() end
        end
    end

    -- Hide everything that is not the selected pane, THEN show it. One frame can
    -- be registered under several views (the rank table is the pane for every
    -- spell family), and a single pass would hide it again on whichever key
    -- pairs() happened to visit last.
    local function ShowOnly(groupID, viewID)
        local keep = nav.panes and nav.panes[groupID] and nav.panes[groupID][viewID]
        for _, panes in pairs(nav.panes or {}) do
            for _, pane in pairs(panes) do
                if pane ~= keep and pane.Hide then pane:Hide() end
            end
        end
        if keep and keep.Show then keep:Show() end
    end

    -- the horizontal row for the selected group. T31: the buttons come from a
    -- pool and a hidden one is reused by index -- a rebuild used to create a
    -- fresh set every time and hide the old (Reports -> Runs leaked a row per
    -- SetViews). A reused button is put back as CreateButton left it.
    nav.viewButtonPool = {}
    local function ReleaseViews()
        for _, b in ipairs(nav.viewButtonPool) do b:Hide() end
        wipe(nav.viewButtons)
    end
    local function BuildViews(group)
        ReleaseViews()
        local prev
        for _, v in ipairs(group.views or {}) do
            if not v.hidden then
                local i = #nav.viewButtons + 1
                local bw = math.max(64, #v.text * 8 + 16)
                local b = nav.viewButtonPool[i]
                if b then
                    b:SetText(v.text)
                    b:SetSize(bw, 20)
                    b:ClearAllPoints()
                    b:SetBackdropColor(unpack(b.color))
                    b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
                    b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.color)) end)
                    b:Show()
                else
                    b = UI.CreateButton(f, v.text, "accent-hover", { bw, 20 },
                        false, false, UI.FONT_TITLE, UI.FONT_TITLE_DISABLE)
                    nav.viewButtonPool[i] = b
                end
                b.id = v.id
                if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
                else b:SetPoint("TOPLEFT", left, "TOPRIGHT", NAV_PAD, -2) end
                nav.viewButtons[#nav.viewButtons + 1] = b
                prev = b
            end
        end
        nav.highlightView = UI.CreateButtonGroup(nav.viewButtons, function(id) nav:Select(group.id, id) end)
    end

    function nav:Select(groupID, viewID)
        local group
        for _, g in ipairs(groups) do if g.id == groupID then group = g end end
        if not group then group = groups[1] end
        if not group then return end
        if nav.group ~= group.id then
            nav.group = group.id
            local isRail = group.layout == "rail"
            AnchorContent(isRail)
            if isRail then
                -- T31: no view row; the rail marks the selection
                ReleaseViews()
                local r = RailOf(group).rail
                nav.highlightView = function(id) r:Select(id) end
            else
                BuildViews(group)
            end
            ShowRails(group.id)
            nav.view = nil
        end
        local views = group.views or {}
        local view
        for _, v in ipairs(views) do
            if v.id == viewID and not v.hidden then view = v end
        end
        if not view then
            for _, v in ipairs(views) do if not v.hidden and not view then view = v end end
        end
        nav.view = view and view.id or nil
        if nav.highlightGroup then nav.highlightGroup(group.id) end
        if nav.highlightView and nav.view then nav.highlightView(nav.view) end
        if MD.db then MD.db.uiPath = { group.id, nav.view } end
        nav.panes = nav.panes or {}
        nav.panes[group.id] = nav.panes[group.id] or {}
        local pane = nav.view and nav.panes[group.id][nav.view] or nil
        if not pane and nav.view and onCreate then
            local h = nav.rails[group.id]   -- T31: a rail group's panes go right of its rail
            pane = onCreate(group.id, nav.view, h and h.view or content, nav)
            if pane then nav.panes[group.id][nav.view] = pane end
        end
        ShowOnly(group.id, nav.view)
        if onShow then onShow(group.id, nav.view, pane, nav) end
    end

    -- a group's views can change while the window is open (Reports/Runs)
    function nav:SetViews(groupID, views)
        for _, g in ipairs(groups) do
            if g.id == groupID then
                g.views = views
                if g.layout == "rail" then
                    -- T31: a rail group has no view row to build; its rail
                    -- (if it exists yet) takes the new rows
                    local h = nav.rails[groupID]
                    if h then h.rail:SetRows(views) end
                    if nav.group == groupID then nav:Select(groupID, nav.view) end
                    return
                end
                if nav.group == groupID then BuildViews(g); nav:Select(groupID, nav.view) end
                return
            end
        end
    end

    function nav:Selected() return nav.group, nav.view end

    local prev
    for _, g in ipairs(groups) do
        local b = UI.CreateButton(left, g.text, "accent-hover", { NAV_W - 2, 22 }, false, false,
            UI.FONT_TITLE, UI.FONT_TITLE_DISABLE)
        b.id = g.id
        if prev then b:SetPoint("TOP", prev, "BOTTOM", 0, 1)
        else b:SetPoint("TOP", left, "TOP", 0, -2) end
        nav.buttons[#nav.buttons + 1] = b
        prev = b
    end
    nav.highlightGroup = UI.CreateButtonGroup(nav.buttons, function(id) nav:Select(id, nil) end)

    return nav
end

-- The same rule one level down, in a bordered box: for a pane that has
-- sub-categories of its own. Nothing needs it yet; it exists so that the next
-- thing that does is not a fourth window.
function UI.CreateNavBox(parent, width, height, groups, onSelect)   -- one hook: a box owns no panes
    local P = UI.PALETTE
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    UI.StylizeFrame(box, P.pane, P.border)
    local nav = { frame = box, groups = groups, buttons = {}, viewButtons = {} }

    local left = CreateFrame("Frame", nil, box, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 1, -1)
    left:SetPoint("BOTTOMLEFT", 1, 1)
    left:SetWidth(NAV_W - 20)
    UI.StylizeFrame(left, P.header, P.border)

    local content = CreateFrame("Frame", nil, box)
    content:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, -(NAV_TOP + 2))
    content:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 6)
    function nav:Content() return content end

    local function BuildViews(group)
        for _, b in ipairs(nav.viewButtons) do b:Hide() end
        wipe(nav.viewButtons)
        local prev
        for _, v in ipairs(group.views or {}) do
            local b = UI.CreateButton(box, v.text, "accent-hover", { math.max(56, #v.text * 7 + 14), 18 },
                false, false, UI.FONT_SMALL, UI.FONT_SMALL)
            b.id = v.id
            if prev then b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
            else b:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, -2) end
            nav.viewButtons[#nav.viewButtons + 1] = b
            prev = b
        end
        nav.highlightView = UI.CreateButtonGroup(nav.viewButtons, function(id) nav:Select(group.id, id) end)
    end

    function nav:Select(groupID, viewID)
        local group
        for _, g in ipairs(groups) do if g.id == groupID then group = g end end
        group = group or groups[1]
        if not group then return end
        if nav.group ~= group.id then nav.group = group.id; BuildViews(group); nav.view = nil end
        local view
        for _, v in ipairs(group.views or {}) do if v.id == viewID then view = v end end
        view = view or (group.views or {})[1]
        nav.view = view and view.id or nil
        if nav.highlightGroup then nav.highlightGroup(group.id) end
        if nav.highlightView and nav.view then nav.highlightView(nav.view) end
        if onSelect then onSelect(group.id, nav.view, content, nav) end
    end

    local prev
    for _, g in ipairs(groups) do
        local b = UI.CreateButton(left, g.text, "accent-hover", { NAV_W - 22, 18 }, false, false,
            UI.FONT_SMALL, UI.FONT_SMALL)
        b.id = g.id
        if prev then b:SetPoint("TOP", prev, "BOTTOM", 0, 1)
        else b:SetPoint("TOP", left, "TOP", 0, -2) end
        nav.buttons[#nav.buttons + 1] = b
        prev = b
    end
    nav.highlightGroup = UI.CreateButtonGroup(nav.buttons, function(id) nav:Select(id, nil) end)

    return nav
end

--------------------------------------------------------------------------------
-- T31 (docs/SPEC-forever-ui.md 3.2, 6.2, 6.4): the rail, sheets and masks.
-- Additive: nothing on TBC builds them (only a layout = "rail" nav group and
-- the Forever panes do). Colours are the theme's (UI.PALETTE / UI.TEXT, from
-- UI/Theme_Forever.lua) with the flat literals as the fallback.
--------------------------------------------------------------------------------
local function TextRGB(token, r, g, b)
    local t = UI.TEXT and UI.TEXT[token]
    if t then return t[1], t[2], t[3] end
    return r, g, b
end
local function Fill(key, fallback)
    local c = UI.PALETTE and UI.PALETTE[key]
    return c or fallback
end

-- A popup list (a dropdown's, the rail's menu) opened or closed: the window
-- manager's hook (6.5), called only when it is set -- TBC never sets it.
local function Popup(list, shown)
    if UI.OnPopup then UI.OnPopup(list, shown) end
end
local function WatchPopup(list)
    list:SetScript("OnShow", function(self) Popup(self, true) end)
    list:SetScript("OnHide", function(self) Popup(self, false) end)
end

--------------------------------------------------------------------------------
-- The rail: a list you build yourself, one row per view (3.2).
--
-- UI.CreateRail(parent, w, opts) -> rail     (rail.frame is the list's frame;
--                                             the caller anchors it)
--   opts.title          the label on top ("MY SPELLS"), 11 px muted, 18 tall
--   opts.rowHeight      a row's height, 20 (a Forever pane passes UI.Pitch(20));
--                       rows overlap by 1 px, so their tops are rowHeight - 1 apart
--   opts.footerHeight   the slot pinned at the bottom (rail:Footer()), 0 if absent
--   opts.empty          the line shown when no movable row is listed
--   opts.onSelect(id)   a row clicked
--   opts.onMove(id, to) ONCE per reorder (a drag, ^ / v, the menu); `to` is the
--                       row's new place among the movable rows
--   opts.onRemove(id)   the hover x or the menu's Remove
--   opts.onDrop(at)     something dropped on the rail, to go in before movable
--                       row `at` (#rows + 1: at the end). The kit never reads
--                       or clears the cursor: the caller does what it likes.
--   opts.canDrop()      true when a click on the rail should drop (the cursor
--                       holds something) rather than select
-- rail:SetRows(rows)   rows = { { id, text, icon, tag, new, stale, fixed,
--                      tooltip, hidden }, ... }: fixed rows (Overview) are not
--                      movable, and a 1-px rule follows the last of them;
--                      `stale` greys the name and drops the tag
-- rail:Select(id)      marks the row (fill + a 2-px accent bar)
-- rail:Rows()          the rows shown, in order (each .id, .index, .data)
-- rail:Footer()        the bottom slot's frame
-- rail:SetRowHeight(h) a new row height (the font offset changed), rows re-laid
-- rail:OpenMenu(row)   the right-click menu: Move up / Move down / Remove from list
--------------------------------------------------------------------------------
function UI.CreateRail(parent, w, opts)
    opts = opts or {}
    local rowH = opts.rowHeight or 20
    local pitch = rowH - 1
    local TITLE_H = 18
    local RULE_GAP = 8          -- 3 above the 1-px rule, 4 below
    local rail = { opts = opts, rows = {}, pool = {}, selected = nil }

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetWidth(w)
    frame:EnableMouse(true)
    UI.StylizeFrame(frame, Fill("pane", { 0.11, 0.11, 0.11, 1 }), Fill("border", { 0, 0, 0, 1 }))
    rail.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    title:SetJustifyH("LEFT")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -5)
    title:SetTextColor(TextRGB("muted", 0.48, 0.48, 0.48))
    title:SetText(opts.title or "")
    rail.title = title

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    local lc = Fill("line", { 0.165, 0.165, 0.165, 1 })
    rule:SetColorTexture(lc[1], lc[2], lc[3], lc[4] or 1)
    rule:Hide()

    local emptyText = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetPoint("LEFT", frame, "LEFT", 8, 0)
    emptyText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    emptyText:SetTextColor(TextRGB("muted", 0.48, 0.48, 0.48))
    emptyText:Hide()

    -- the insertion line a drag shows (2 px, accent)
    local line = frame:CreateTexture(nil, "OVERLAY")
    line:SetHeight(2)
    line:SetColorTexture(accent[1], accent[2], accent[3], 1)
    line:Hide()

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    footer:SetHeight(opts.footerHeight or 0)
    function rail:Footer() return footer end

    local function Movables()
        local n = 0
        for _, r in ipairs(rail.rows) do if r.movable then n = n + 1 end end
        return n
    end

    ----------------------------------------------------------------------------
    -- painting one row: fill, bar, name, tag, dot, controls
    ----------------------------------------------------------------------------
    local function Paint(row)
        local fill
        if row.selected then fill = Fill("selected", { accent[1], accent[2], accent[3], 0.28 })
        elseif row.hovered then fill = Fill("hover", { accent[1], accent[2], accent[3], 0.12 }) end
        if fill then row.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
        else row.bg:SetColorTexture(0, 0, 0, 0) end
        if row.selected then row.bar:Show() else row.bar:Hide() end
        local d = row.data or {}
        local controls = row.hovered and row.movable and (opts.onMove or opts.onRemove) and true or false
        local right
        if controls then
            row.up:Show(); row.down:Show(); row.rm:Show()
            row.tag:Hide(); row.dot:Hide()
            right = 56
        else
            row.up:Hide(); row.down:Hide(); row.rm:Hide()
            local tag = d.tag and d.tag ~= "" and not d.stale
            local dot = d.new and not d.stale
            if tag then row.tag:Show() else row.tag:Hide() end
            if dot then row.dot:Show() else row.dot:Hide() end
            right = (tag and 32 or 6) + (dot and 11 or 0)
        end
        -- the name is truncated before whatever sits at the right
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", row, "LEFT", row.nameX or 24, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -right, 0)
    end

    local function Leave(row)
        if row.IsMouseOver and row:IsMouseOver() then return end   -- onto its own control
        row.hovered = nil
        Paint(row)
    end

    local function DropAt(row)
        if row and row.movable then return row.index end
        if row and not row.movable then return 1 end
        return Movables() + 1
    end

    local function NewRow()
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(rowH)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:RegisterForDrag("LeftButton")

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints(row)
        row.bg:SetColorTexture(0, 0, 0, 0)

        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetWidth(2)
        row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", -1, 0)
        row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -1, 0)
        row.bar:SetColorTexture(accent[1], accent[2], accent[3], 1)
        row.bar:Hide()

        row.iconEdge = row:CreateTexture(nil, "ARTWORK")
        row.iconEdge:SetSize(18, 18)
        row.iconEdge:SetPoint("LEFT", row, "LEFT", 3, 0)
        row.iconEdge:SetColorTexture(0, 0, 0, 1)
        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.tag = row:CreateFontString(nil, "OVERLAY", UI.FONT_NUM_SMALL or UI.FONT_SMALL)
        row.tag:SetJustifyH("RIGHT")
        row.tag:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.tag:SetTextColor(TextRGB("muted", 0.48, 0.48, 0.48))

        row.dot = row:CreateTexture(nil, "OVERLAY")
        row.dot:SetSize(6, 6)
        row.dot:SetColorTexture(accent[1], accent[2], accent[3], 1)

        row.name = row:CreateFontString(nil, "OVERLAY", UI.FONT)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        -- the hover controls: ^ move up, v move down, x remove (red, as Cell's delete)
        local function Ctl(text, color)
            local b = UI.CreateButton(row, text, color, { 14, 14 }, false, false, UI.FONT_SMALL, UI.FONT_SMALL)
            b:HookScript("OnLeave", function() Leave(row) end)
            b:Hide()
            return b
        end
        row.rm = Ctl("x", "red-hover")
        row.rm:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.down = Ctl("v", "accent-hover")
        row.down:SetPoint("RIGHT", row.rm, "LEFT", -2, 0)
        row.up = Ctl("^", "accent-hover")
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        row.up:SetScript("OnClick", function()
            if row.index and row.index > 1 and opts.onMove then opts.onMove(row.id, row.index - 1) end
        end)
        row.down:SetScript("OnClick", function()
            if row.index and row.index < Movables() and opts.onMove then opts.onMove(row.id, row.index + 1) end
        end)
        row.rm:SetScript("OnClick", function()
            if opts.onRemove then opts.onRemove(row.id) end
        end)

        row:SetScript("OnEnter", function(self)
            self.hovered = true
            Paint(self)
        end)
        row:SetScript("OnLeave", function(self) Leave(self) end)
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if self.movable then rail:OpenMenu(self) end
                return
            end
            if opts.canDrop and opts.onDrop and opts.canDrop() then
                opts.onDrop(DropAt(self))
                return
            end
            if opts.onSelect then opts.onSelect(self.id) end
        end)
        row:SetScript("OnReceiveDrag", function(self)
            if opts.onDrop then opts.onDrop(DropAt(self)) end
        end)
        row:SetScript("OnDragStart", function(self) rail:BeginDrag(self) end)
        row:SetScript("OnDragStop", function() rail:EndDrag() end)

        -- the row's tooltip (a stale row's "not in your spellbook"); the
        -- kit's hover hook is installed once, the lines set per SetRows
        UI.SetTooltips(row, "ANCHOR_RIGHT", 2, 0, "")
        row.tooltips = nil
        return row
    end

    ----------------------------------------------------------------------------
    -- rows
    ----------------------------------------------------------------------------
    function rail:SetRows(rows)
        rail.lastRows = rows
        for _, r in ipairs(rail.pool) do r:Hide() end
        wipe(rail.rows)
        rule:Hide()
        rail.firstTop = nil
        local y = TITLE_H
        local sawFixed, sawMovable, movable = false, false, 0
        for _, d in ipairs(rows or {}) do
            if not d.hidden then
                if not d.fixed and sawFixed and not sawMovable then
                    rule:ClearAllPoints()
                    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(y + 3))
                    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(y + 3))
                    rule:Show()
                    y = y + RULE_GAP
                end
                local i = #rail.rows + 1
                local row = rail.pool[i]
                if not row then row = NewRow(); rail.pool[i] = row end
                row.id, row.data = d.id, d
                row.movable = not d.fixed
                if row.movable then
                    movable = movable + 1
                    row.index = movable
                    sawMovable = true
                    if movable == 1 then rail.firstTop = y end
                else
                    row.index = nil
                    sawFixed = true
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -y)
                row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -y)
                row.top = y

                local hasIcon = d.icon ~= nil and not d.fixed
                if hasIcon then
                    row.icon:SetTexture(d.icon); row.icon:Show(); row.iconEdge:Show()
                else
                    row.icon:Hide(); row.iconEdge:Hide()
                end
                row.nameX = d.fixed and 8 or 24
                row.name:SetText(d.text or "")
                if d.stale then row.name:SetTextColor(TextRGB("disabled", 0.3, 0.3, 0.3))
                else row.name:SetTextColor(TextRGB("text", 1, 1, 1)) end
                row.tag:SetText(d.tag or "")
                row.dot:ClearAllPoints()
                if d.tag and d.tag ~= "" then row.dot:SetPoint("RIGHT", row.tag, "LEFT", -5, 0)
                else row.dot:SetPoint("RIGHT", row, "RIGHT", -6, 0) end
                if d.stale or d.tooltip then
                    row.tooltips = { d.text or "", d.tooltip or "not in your spellbook" }
                else
                    row.tooltips = nil
                end
                row.selected = (rail.selected ~= nil and rail.selected == d.id)
                row.hovered = nil
                row:SetAlpha(1)
                Paint(row)
                row:Show()
                rail.rows[i] = row
                y = y + pitch
            end
        end
        if not rail.firstTop then rail.firstTop = y end
        if movable == 0 and opts.empty then
            if sawFixed then y = y + RULE_GAP end
            emptyText:ClearAllPoints()
            emptyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -(y + 4))
            emptyText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -(y + 4))
            emptyText:SetText(opts.empty)
            emptyText:Show()
        else
            emptyText:Hide()
        end
    end

    function rail:Rows() return rail.rows end

    function rail:SetRowHeight(h)
        if type(h) ~= "number" or h <= 1 or h == rowH then return end
        rowH, pitch = h, h - 1
        for _, r in ipairs(rail.pool) do r:SetHeight(rowH) end
        rail:SetRows(rail.lastRows)
    end

    function rail:Select(id)
        rail.selected = id
        for _, r in ipairs(rail.rows) do
            r.selected = (r.id == id)
            Paint(r)
        end
    end

    ----------------------------------------------------------------------------
    -- drag to reorder: the row lifts to alpha 0.5, a 2-px line marks the drop
    -- point, and the move is reported ONCE (OnDragStop can fire twice)
    ----------------------------------------------------------------------------
    local function SlotAtCursor()
        local _, cy = GetCursorPosition()
        local top = frame:GetTop()
        local s = frame:GetEffectiveScale()
        if type(cy) ~= "number" or type(top) ~= "number" or type(s) ~= "number" or s <= 0 then return nil end
        local rel = top - cy / s
        local n = Movables()
        local slot = math.floor((rel - (rail.firstTop or TITLE_H) + pitch / 2) / pitch) + 1
        if slot < 1 then slot = 1 end
        if slot > n + 1 then slot = n + 1 end
        return slot
    end

    function rail:BeginDrag(row)
        if rail.drag or not row.movable or not opts.onMove then return end
        rail.drag = { row = row, from = row.index }
        row:SetAlpha(0.5)
        frame:SetScript("OnUpdate", function() rail:TrackDrag() end)
        rail:TrackDrag()
    end

    function rail:TrackDrag()
        local slot = rail.drag and SlotAtCursor()
        if not slot then line:Hide(); return end
        local y = (rail.firstTop or TITLE_H) + (slot - 1) * pitch
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(y - 1))
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -(y - 1))
        line:Show()
    end

    -- a drag that ends nowhere (the rail hidden under it) moves nothing
    local function StopDrag()
        local d = rail.drag
        if not d then return nil end
        rail.drag = nil
        frame:SetScript("OnUpdate", nil)
        line:Hide()
        d.row:SetAlpha(1)
        return d
    end

    function rail:EndDrag()
        local d = StopDrag()
        if not d then return end
        local slot = SlotAtCursor()
        if not slot then return end
        local to = slot
        if slot > d.from then to = slot - 1 end
        if to ~= d.from and opts.onMove then opts.onMove(d.row.id, to) end
    end

    -- a drop on the rail's own ground (below the rows) goes in at the end
    frame:SetScript("OnReceiveDrag", function()
        if opts.onDrop then opts.onDrop(Movables() + 1) end
    end)
    frame:SetScript("OnMouseUp", function()
        if opts.canDrop and opts.onDrop and opts.canDrop() then opts.onDrop(Movables() + 1) end
    end)

    ----------------------------------------------------------------------------
    -- the right-click menu (a kit popup list, in the lists' strata)
    ----------------------------------------------------------------------------
    local MENU_W, MENU_H = 130, 18
    local menu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    menu:SetFrameStrata(UI.LIST_STRATA or "DIALOG")
    menu:SetWidth(MENU_W)
    UI.StylizeFrame(menu, Fill("header", { 0.115, 0.115, 0.115, 1 }))
    menu:Hide()
    WatchPopup(menu)
    rail.menu = menu
    local items = {
        { "Move up", function(r) if r.index > 1 and opts.onMove then opts.onMove(r.id, r.index - 1) end end },
        { "Move down", function(r) if r.index < Movables() and opts.onMove then opts.onMove(r.id, r.index + 1) end end },
        { "Remove from list", function(r) if opts.onRemove then opts.onRemove(r.id) end end },
    }
    menu.buttons = {}
    for i, it in ipairs(items) do
        local b = UI.CreateButton(menu, it[1], "accent-hover", { MENU_W - 2, MENU_H }, true, false,
            UI.FONT_SMALL, UI.FONT_SMALL)
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -1 - (i - 1) * (MENU_H - 1))
        b:SetScript("OnClick", function()
            local r = menu.row
            menu:Hide()
            if r and r.movable then it[2](r) end
        end)
        menu.buttons[i] = b
    end
    menu:SetHeight(#items * (MENU_H - 1) + 3)

    function rail:OpenMenu(row)
        menu.row = row
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 8, 1)
        menu:Show()
    end
    frame:SetScript("OnHide", function() menu:Hide(); StopDrag() end)

    return rail
end

--------------------------------------------------------------------------------
-- Masks and sheets (6.4): an editor is a sheet inside the pane, never another
-- window. Behind it a mask covers the region the caller names and swallows
-- mouse and wheel input there (Cell's CreateMask); whatever is outside that
-- region stays live (the Spells rail while the picker is open).
--
-- UI.CreateMask(region, level) -> mask, hidden; at `level` (default the
--   region's +30), over the whole region
-- UI.CreateSheet(pane, maskRegion, w, h, title) -> sheet, hidden; a child of
--   the pane at its level +50, the mask over maskRegion (default the pane) at
--   the pane's +30, a 20-px title row, the `pane` fill and a 1-px accent edge;
--   centred on maskRegion until the caller anchors it. sheet:Body() is the
--   area under the title. Only one sheet is open at a time: showing one hides
--   the other.
--------------------------------------------------------------------------------
function UI.CreateMask(region, level)
    local m = CreateFrame("Frame", nil, region)
    m:SetAllPoints(region)
    m:SetFrameLevel(level or (region:GetFrameLevel() + 30))
    m:EnableMouse(true)
    if m.EnableMouseWheel then m:EnableMouseWheel(true) end
    m:SetScript("OnMouseWheel", function() end)
    local c = Fill("mask", { 0.15, 0.15, 0.15, 0.7 })
    local tex = m:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(m)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.7)
    m:Hide()
    return m
end

function UI.CreateSheet(pane, maskRegion, w, h, title)
    maskRegion = maskRegion or pane
    local base = pane:GetFrameLevel()
    local mask = UI.CreateMask(maskRegion, base + 30)

    local s = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    s:SetSize(w, h)
    s:SetPoint("CENTER", maskRegion, "CENTER", 0, 0)
    s:SetFrameLevel(base + 50)
    s:EnableMouse(true)
    UI.StylizeFrame(s, Fill("pane", { 0.11, 0.11, 0.11, 1 }), { accent[1], accent[2], accent[3], 1 })
    s.mask = mask

    local bar = s:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", s, "TOPRIGHT", -1, -1)
    bar:SetHeight(20)
    local nc = Fill("nav", Fill("header", { 0.115, 0.115, 0.115, 1 }))
    bar:SetColorTexture(nc[1], nc[2], nc[3], nc[4] or 1)
    local edge = s:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    edge:SetHeight(1)
    edge:SetColorTexture(0, 0, 0, 1)

    s.title = s:CreateFontString(nil, "OVERLAY", UI.FONT_CLASS)
    s.title:SetJustifyH("LEFT")
    s.title:SetPoint("LEFT", bar, "LEFT", 7, 0)
    s.title:SetText(title or "")
    function s:SetTitle(t) s.title:SetText(t or "") end

    local body = CreateFrame("Frame", nil, s)
    body:SetPoint("TOPLEFT", s, "TOPLEFT", 1, -22)
    body:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
    function s:Body() return body end

    s:Hide()
    s:SetScript("OnShow", function(self)
        if UI.openSheet and UI.openSheet ~= self then UI.openSheet:Hide() end
        UI.openSheet = self
        mask:Show()
    end)
    s:SetScript("OnHide", function(self)
        mask:Hide()
        if UI.openSheet == self then UI.openSheet = nil end
    end)
    return s
end

--------------------------------------------------------------------------------
-- Dropdown: a button that says what is selected and drops a list under it.
--
-- The kit had button groups and nothing else, which is fine for two or three
-- short labels and wrong for four long ones -- four strategy names beside the
-- replay's column title ran off the window (v0.11.11). A dropdown costs one
-- control's width whatever the labels say.
--
-- UI.CreateDropdown(parent, width, height, onSelect) -> dd
--   dd:SetItems({ { id, text, tooltip }, ... })
--   dd:SetValue(id)   -- no callback
--   dd:Value()
--   dd:Close()
--------------------------------------------------------------------------------
function UI.CreateDropdown(parent, width, height, onSelect)
    height = height or 18
    local dd = UI.CreateButton(parent, "", "accent-hover", { width, height }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL)
    dd.items, dd.rows, dd.value = {}, {}, nil

    local arrow = dd:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    arrow:SetPoint("RIGHT", dd, "RIGHT", -4, 0)
    arrow:SetText("v")
    arrow:SetTextColor(0.7, 0.7, 0.7)

    local list = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -1)
    list:SetWidth(width)
    -- T31 (6.2): the lists' strata is the kit's setting; nil is today's DIALOG
    -- (TBC's), the Forever theme lifts it above the replay's
    list:SetFrameStrata(UI.LIST_STRATA or "DIALOG")
    UI.StylizeFrame(list, UI.PALETTE and UI.PALETTE.header or { 0.115, 0.115, 0.115, 1 })
    list:Hide()
    WatchPopup(list)   -- T31: UI.OnPopup told, once it exists (after the first Hide)
    dd.list = list

    local function Label(id)
        for _, it in ipairs(dd.items) do if it.id == id then return it.text end end
        return ""
    end

    function dd:Close() list:Hide() end

    function dd:SetValue(id)
        dd.value = id
        dd:SetText(Label(id))
    end

    function dd:Value() return dd.value end

    function dd:SetItems(items)
        dd.items = items or {}
        for _, r in ipairs(dd.rows) do r:Hide() end
        local prev
        for i, it in ipairs(dd.items) do
            local r = dd.rows[i]
            if not r then
                r = UI.CreateButton(list, "", "accent-hover", { width - 2, height }, true, false,
                    UI.FONT_SMALL, UI.FONT_SMALL)
                dd.rows[i] = r
            end
            r:SetText(it.text)
            r:ClearAllPoints()
            if prev then r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
            else r:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1) end
            if it.tooltip then UI.SetTooltips(r, "ANCHOR_RIGHT", 0, 0, it.text, it.tooltip) end
            r:SetScript("OnClick", function()
                dd:SetValue(it.id)
                list:Hide()
                if onSelect then onSelect(it.id) end
            end)
            r:Show()
            prev = r
        end
        list:SetHeight(math.max(height, #dd.items * (height - 1) + 3))
        if dd.value == nil and dd.items[1] then dd:SetValue(dd.items[1].id) end
    end

    dd:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else list:Show() end
    end)
    dd:SetScript("OnHide", function() list:Hide() end)

    return dd
end

--------------------------------------------------------------------------------
-- Tree dropdown (v0.15.2): the same button and list, one level deeper. An item
-- with `children` opens them in a second list beside it on hover, and clicking
-- the parent itself picks the parent.
--
-- It exists because a flat list of every rank of every spell is 40 rows long:
-- it ran off the bottom of the bindings window, and picking Rejuvenation Rank 5
-- meant reading past nine Lifeblooms. Five families, hover one, see its ranks.
--------------------------------------------------------------------------------
function UI.CreateTreeDropdown(parent, width, height, onSelect)
    height = height or 18
    local dd = UI.CreateButton(parent, "", "accent-hover", { width, height }, false, false,
        UI.FONT_SMALL, UI.FONT_SMALL)
    dd.items, dd.rows, dd.subRows, dd.value = {}, {}, {}, nil

    local arrow = dd:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    arrow:SetPoint("RIGHT", dd, "RIGHT", -4, 0)
    arrow:SetText("v")
    arrow:SetTextColor(0.7, 0.7, 0.7)

    local function Panel(strata)
        local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetFrameStrata(strata)
        UI.StylizeFrame(f, UI.PALETTE and UI.PALETTE.header or { 0.115, 0.115, 0.115, 1 })
        f:Hide()
        return f
    end
    -- T31 (6.2): the first list in the kit's list strata (nil: today's DIALOG),
    -- the second in FULLSCREEN_DIALOG as before and always above the first by
    -- level too -- once the theme puts both in one strata, only the level
    -- keeps the second on top
    local list = Panel(UI.LIST_STRATA or "DIALOG")
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -1)
    list:SetWidth(width)
    local sub = Panel("FULLSCREEN_DIALOG")
    sub:SetWidth(width)
    sub:SetFrameLevel(list:GetFrameLevel() + 10)
    dd.list, dd.sub = list, sub
    WatchPopup(list)
    list:HookScript("OnHide", function() sub:Hide() end)   -- the second list goes with the first

    local function Label(id)
        for _, it in ipairs(dd.items) do
            if it.id == id then return it.text end
            for _, c in ipairs(it.children or {}) do
                if c.id == id then return c.text end
            end
        end
        return ""
    end

    function dd:Close() sub:Hide(); list:Hide() end
    function dd:SetValue(id) dd.value = id; dd:SetText(Label(id)) end
    function dd:Value() return dd.value end

    local function Pick(id)
        dd:SetValue(id)
        dd:Close()
        if onSelect then onSelect(id) end
    end

    -- the children of one parent row, beside it
    local function ShowChildren(row, children)
        for _, r in ipairs(dd.subRows) do r:Hide() end
        if not children or #children == 0 then sub:Hide(); return end
        local prev
        for i, c in ipairs(children) do
            local r = dd.subRows[i]
            if not r then
                r = UI.CreateButton(sub, "", "accent-hover", { width - 2, height }, true, false,
                    UI.FONT_SMALL, UI.FONT_SMALL)
                dd.subRows[i] = r
            end
            r:SetText(c.text)
            r:ClearAllPoints()
            if prev then r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
            else r:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, -1) end
            r:SetScript("OnClick", function() Pick(c.id) end)
            r:Show()
            prev = r
        end
        sub:SetHeight(math.max(height, #children * (height - 1) + 3))
        sub:SetFrameLevel(list:GetFrameLevel() + 10)   -- T31
        sub:ClearAllPoints()
        sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 1)
        sub:Show()
    end

    function dd:SetItems(items)
        dd.items = items or {}
        for _, r in ipairs(dd.rows) do r:Hide() end
        sub:Hide()
        local prev
        for i, it in ipairs(dd.items) do
            local r = dd.rows[i]
            if not r then
                r = UI.CreateButton(list, "", "accent-hover", { width - 2, height }, true, false,
                    UI.FONT_SMALL, UI.FONT_SMALL)
                dd.rows[i] = r
            end
            r:SetText(it.text .. ((it.children and #it.children > 0) and "   |cff777777>|r" or ""))
            r.item = it
            r:ClearAllPoints()
            if prev then r:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1)
            else r:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1) end
            if it.tooltip then UI.SetTooltips(r, "ANCHOR_RIGHT", 0, 0, it.text, it.tooltip) end
            r:SetScript("OnClick", function() Pick(it.id) end)
            -- the button's own hover (and its tooltip, if it has one) is kept and
            -- called first: a hook would be a second handler on some clients and
            -- a replacement on others, and this has to be neither
            r.baseEnter = r.baseEnter or r:GetScript("OnEnter")
            local kids = it.children
            r:SetScript("OnEnter", function(self, ...)
                if r.baseEnter then r.baseEnter(self, ...) end
                ShowChildren(self, kids)
            end)
            r:Show()
            prev = r
        end
        list:SetHeight(math.max(height, #dd.items * (height - 1) + 3))
        if dd.value == nil and dd.items[1] then dd:SetValue(dd.items[1].id) end
    end

    dd:SetScript("OnClick", function()
        if list:IsShown() then dd:Close() else list:Show() end
    end)
    dd:SetScript("OnHide", function() dd:Close() end)
    return dd
end

--------------------------------------------------------------------------------
-- Check button
--------------------------------------------------------------------------------
-- UI.CreateCheckButton(parent, label, onClick(checked, cb), tooltip...)
function UI.CreateCheckButton(parent, label, onClick, ...)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb.onClick = onClick
    cb:SetScript("OnClick", function(self)
        if SOUNDKIT then
            PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        if cb.onClick then cb.onClick(self:GetChecked() and true or false, self) end
    end)

    cb.label = cb:CreateFontString(nil, "OVERLAY", UI.FONT)
    cb.label:SetText(label or "")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 5, 0)

    cb:SetSize(14, 14)
    if label and strtrim(label) ~= "" then
        cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 5, 0, 0)
    end

    cb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    cb:SetBackdropColor(0.115, 0.115, 0.115, 0.9)
    cb:SetBackdropBorderColor(0, 0, 0, 1)

    local checkedTexture = cb:CreateTexture(nil, "ARTWORK")
    checkedTexture:SetColorTexture(accent[1], accent[2], accent[3], 0.7)
    checkedTexture:SetPoint("TOPLEFT", 1, -1)
    checkedTexture:SetPoint("BOTTOMRIGHT", -1, 1)

    local highlightTexture = cb:CreateTexture(nil, "ARTWORK")
    highlightTexture:SetColorTexture(accent[1], accent[2], accent[3], 0.1)
    highlightTexture:SetPoint("TOPLEFT", 1, -1)
    highlightTexture:SetPoint("BOTTOMRIGHT", -1, 1)

    cb:SetCheckedTexture(checkedTexture)
    cb:SetHighlightTexture(highlightTexture, "ADD")

    cb:SetScript("OnEnable", function()
        cb.label:SetTextColor(1, 1, 1)
        checkedTexture:SetColorTexture(accent[1], accent[2], accent[3], 0.7)
        cb:SetBackdropBorderColor(0, 0, 0, 1)
    end)
    cb:SetScript("OnDisable", function()
        cb.label:SetTextColor(0.4, 0.4, 0.4)
        checkedTexture:SetColorTexture(0.4, 0.4, 0.4)
        cb:SetBackdropBorderColor(0, 0, 0, 0.4)
    end)

    function cb:SetText(text)
        cb.label:SetText(text)
        if strtrim(text) ~= "" then
            cb:SetHitRectInsets(0, -cb.label:GetStringWidth() - 5, 0, 0)
        else
            cb:SetHitRectInsets(0, 0, 0, 0)
        end
    end

    UI.SetTooltips(cb, "ANCHOR_TOPLEFT", 0, 3, ...)
    return cb
end

--------------------------------------------------------------------------------
-- Edit boxes
--------------------------------------------------------------------------------
function UI.CreateEditBox(parent, width, height, isTransparent, isMultiLine, isNumeric, font)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    if not isTransparent then UI.StylizeFrame(eb, { 0.115, 0.115, 0.115, 0.9 }) end
    eb:SetFontObject(font or UI.FONT)
    eb:SetMultiLine(isMultiLine)
    eb:SetMaxLetters(0)
    eb:SetJustifyH("LEFT")
    eb:SetJustifyV("MIDDLE")
    eb:SetWidth(width or 0)
    eb:SetHeight(height or 0)
    eb:SetTextInsets(5, 5, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(isNumeric)
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() eb:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function() eb:HighlightText(0, 0) end)
    eb:SetScript("OnDisable", function() eb:SetTextColor(0.4, 0.4, 0.4, 1) end)
    eb:SetScript("OnEnable", function() eb:SetTextColor(1, 1, 1, 1) end)
    return eb
end

--------------------------------------------------------------------------------
-- Scroll frame with a 5px accent scrollbar (mouse wheel + draggable thumb)
--------------------------------------------------------------------------------
function UI.CreateScrollFrame(parent, top, bottom, color, border)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "BackdropTemplate")
    parent.scrollFrame = scrollFrame
    top = top or 0
    bottom = bottom or 0
    scrollFrame:SetPoint("TOPLEFT", 0, top)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, bottom)
    if color then UI.StylizeFrame(scrollFrame, color, border) end

    function scrollFrame:Resize(newTop, newBottom)
        top, bottom = newTop, newBottom
        scrollFrame:SetPoint("TOPLEFT", 0, top)
        scrollFrame:SetPoint("BOTTOMRIGHT", 0, bottom)
    end

    local content = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    content:SetSize(scrollFrame:GetWidth(), 2)
    scrollFrame:SetScrollChild(content)
    scrollFrame.content = content

    local scrollbar = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
    scrollbar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", scrollFrame, 7, 0)
    scrollbar:Hide()
    UI.StylizeFrame(scrollbar, { 0.1, 0.1, 0.1, 0.8 })
    scrollFrame.scrollbar = scrollbar

    local scrollThumb = CreateFrame("Frame", nil, scrollbar, "BackdropTemplate")
    scrollThumb:SetWidth(5)
    scrollThumb:SetHeight(scrollbar:GetHeight())
    scrollThumb:SetPoint("TOP")
    UI.StylizeFrame(scrollThumb, { accent[1], accent[2], accent[3], 0.8 })
    scrollThumb:EnableMouse(true)
    scrollThumb:SetMovable(true)
    scrollThumb:SetHitRectInsets(-5, -5, 0, 0)
    scrollFrame.scrollThumb = scrollThumb

    function scrollFrame:ResetHeight() content:SetHeight(2) end

    function scrollFrame:ResetScroll()
        scrollFrame:SetVerticalScroll(0)
        scrollThumb:SetPoint("TOP")
    end

    function scrollFrame:GetVerticalScrollRange()
        local range = content:GetHeight() - scrollFrame:GetHeight()
        return range > 0 and range or 0
    end

    function scrollFrame:VerticalScroll(step)
        local scroll = scrollFrame:GetVerticalScroll() + step
        if scroll <= 0 then
            scrollFrame:SetVerticalScroll(0)
        elseif scroll >= scrollFrame:GetVerticalScrollRange() then
            scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
        else
            scrollFrame:SetVerticalScroll(scroll)
        end
    end

    function scrollFrame:ScrollToBottom()
        scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
    end

    function scrollFrame:SetContentHeight(height, num, spacing)
        if num and spacing then
            content:SetHeight(num * height + (num - 1) * spacing)
        else
            content:SetHeight(height)
        end
    end

    scrollFrame:SetScript("OnSizeChanged", function()
        content:SetWidth(scrollFrame:GetWidth())
    end)

    content:SetScript("OnSizeChanged", function()
        local p = scrollFrame:GetHeight() / math.max(content:GetHeight(), 1)
        p = tonumber(string.format("%.3f", p))
        if p < 1 then
            scrollThumb:SetHeight(scrollbar:GetHeight() * p)
            scrollFrame:SetPoint("BOTTOMRIGHT", parent, -7, bottom)
            scrollbar:Show()
        else
            scrollFrame:SetPoint("BOTTOMRIGHT", parent, 0, bottom)
            scrollbar:Hide()
            if scrollFrame:GetVerticalScroll() > 0 then scrollFrame:SetVerticalScroll(0) end
        end
    end)

    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local offsetY = select(5, scrollThumb:GetPoint(1)) or 0
        local mouseY = select(2, GetCursorPosition())
        local uiScale = UIParent:GetEffectiveScale()
        self:SetScript("OnUpdate", function()
            local newOffsetY = offsetY + (select(2, GetCursorPosition()) - mouseY) / uiScale
            if newOffsetY >= 0 then
                scrollThumb:SetPoint("TOP")
                newOffsetY = 0
            elseif (-newOffsetY) + scrollThumb:GetHeight() >= scrollbar:GetHeight() then
                scrollThumb:SetPoint("TOP", 0, -(scrollbar:GetHeight() - scrollThumb:GetHeight()))
                newOffsetY = -(scrollbar:GetHeight() - scrollThumb:GetHeight())
            else
                scrollThumb:SetPoint("TOP", 0, newOffsetY)
            end
            local track = scrollbar:GetHeight() - scrollThumb:GetHeight()
            if track > 0 then
                scrollFrame:SetVerticalScroll((-newOffsetY / track) * scrollFrame:GetVerticalScrollRange())
            end
        end)
    end)
    scrollThumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    scrollFrame:SetScript("OnVerticalScroll", function()
        local range = scrollFrame:GetVerticalScrollRange()
        if range ~= 0 then
            local scrollP = scrollFrame:GetVerticalScroll() / range
            scrollThumb:SetPoint("TOP", 0, -((scrollbar:GetHeight() - scrollThumb:GetHeight()) * scrollP))
        end
    end)

    local step = 25
    function scrollFrame:SetScrollStep(s) step = s end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if delta == 1 then
            scrollFrame:VerticalScroll(-step)
        elseif delta == -1 then
            scrollFrame:VerticalScroll(step)
        end
    end)

    return scrollFrame
end

-- Multi-line edit box inside a scroll frame (used by the copy popup).
function UI.CreateScrollEditBox(parent, onTextChanged, scrollStep)
    scrollStep = scrollStep or 1
    local frame = CreateFrame("Frame", nil, parent)
    UI.CreateScrollFrame(frame)
    UI.StylizeFrame(frame.scrollFrame, { 0.15, 0.15, 0.15, 0.9 })

    frame.eb = UI.CreateEditBox(frame.scrollFrame.content, 10, 20, true, true)
    frame.eb:SetPoint("TOPLEFT")
    frame.eb:SetPoint("RIGHT")
    frame.eb:SetTextInsets(2, 2, 2, 2)
    frame.eb:SetScript("OnEditFocusGained", nil)
    frame.eb:SetScript("OnEditFocusLost", nil)
    frame.eb:SetScript("OnEnterPressed", function(self) self:Insert("\n") end)

    frame.eb:SetScript("OnCursorChanged", function(self, _, y, cursorWidth, lineHeight)
        frame.scrollFrame:SetScrollStep((lineHeight + frame.eb:GetSpacing()) * scrollStep)
        local vs = frame.scrollFrame:GetVerticalScroll()
        local h = frame.scrollFrame:GetHeight()
        local cursorHeight = lineHeight - y
        if vs + y > 0 then
            frame.scrollFrame:SetVerticalScroll(-y)
        elseif cursorHeight > h + vs then
            frame.scrollFrame:SetVerticalScroll(-y - h + lineHeight + (cursorWidth or 0))
        end
        if frame.scrollFrame:GetVerticalScroll() > frame.scrollFrame:GetVerticalScrollRange() then
            frame.scrollFrame:ScrollToBottom()
        end
    end)

    frame.eb:SetScript("OnTextChanged", function(self, userChanged)
        frame.scrollFrame:SetContentHeight(self:GetHeight())
        if onTextChanged then onTextChanged(self, userChanged) end
    end)

    frame.scrollFrame:SetScript("OnMouseDown", function() frame.eb:SetFocus(true) end)

    function frame:SetText(text)
        frame.eb:SetText(text)
        frame.scrollFrame:ResetScroll()
        frame.eb:SetCursorPosition(0)
    end
    function frame:GetText() return frame.eb:GetText() end
    function frame:SetEnabled(enabled) frame.eb:SetEnabled(enabled) end
    return frame
end

--------------------------------------------------------------------------------
-- Slider: label above, value edit box below the middle, low/high captions
--------------------------------------------------------------------------------
-- UI.CreateSlider(name, parent, low, high, width, step, onValueChanged, afterValueChanged, isPercentage, tooltip...)
function UI.CreateSlider(name, parent, low, high, width, step, onValueChangedFn, afterValueChangedFn, isPercentage, ...)
    local tooltips = { ... }
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 10)
    local unit = isPercentage and "%" or ""
    UI.StylizeFrame(slider, { 0.115, 0.115, 0.115, 1 })

    local label = slider:CreateFontString(nil, "OVERLAY", UI.FONT)
    label:SetText(name)
    label:SetPoint("BOTTOM", slider, "TOP", 0, 2)
    function slider:SetLabel(n) label:SetText(n) end

    local currentEditBox = UI.CreateEditBox(slider, 48, 14)
    slider.currentEditBox = currentEditBox
    currentEditBox:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", math.ceil(width / 2 - 24), -1)
    currentEditBox:SetJustifyH("CENTER")
    currentEditBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    currentEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local value = tonumber(self:GetText())
        if value == self.oldValue then return end
        if value then
            if value < slider.low then value = slider.low end
            if value > slider.high then value = slider.high end
            self:SetText(value)
            slider:SetValue(value)
            if slider.onValueChangedFn then slider.onValueChangedFn(value) end
            if slider.afterValueChangedFn then slider.afterValueChangedFn(value) end
        else
            self:SetText(self.oldValue)
        end
    end)
    currentEditBox:SetScript("OnShow", function(self)
        if self.oldValue then self:SetText(self.oldValue) end
    end)

    local lowText = slider:CreateFontString(nil, "OVERLAY", UI.FONT)
    slider.lowText = lowText
    lowText:SetTextColor(unpack(UI.grey))
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1)
    lowText:SetPoint("BOTTOM", currentEditBox)

    local highText = slider:CreateFontString(nil, "OVERLAY", UI.FONT)
    slider.highText = highText
    highText:SetTextColor(unpack(UI.grey))
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1)
    highText:SetPoint("BOTTOM", currentEditBox)

    local tex = slider:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(accent[1], accent[2], accent[3], 0.7)
    tex:SetSize(8, 8)
    slider:SetThumbTexture(tex)

    local valueBeforeClick
    slider.onEnter = function()
        tex:SetColorTexture(accent[1], accent[2], accent[3], 1)
        valueBeforeClick = slider:GetValue()
        if #tooltips > 0 then ShowTooltips(slider, "ANCHOR_TOPLEFT", 0, 3, tooltips) end
    end
    slider:SetScript("OnEnter", slider.onEnter)
    slider.onLeave = function()
        tex:SetColorTexture(accent[1], accent[2], accent[3], 0.7)
        tooltip:Hide()
    end
    slider:SetScript("OnLeave", slider.onLeave)

    slider.onValueChangedFn = onValueChangedFn
    slider.afterValueChangedFn = afterValueChangedFn

    local oldValue
    slider:SetScript("OnValueChanged", function(_, value, userChanged)
        if oldValue == value then return end
        oldValue = value
        if math.floor(value) < value then value = tonumber(string.format("%.2f", value)) end
        currentEditBox:SetText(value)
        currentEditBox.oldValue = value
        if userChanged and slider.onValueChangedFn then slider.onValueChangedFn(value) end
    end)

    slider:SetScript("OnMouseUp", function()
        if not slider:IsEnabled() then return end
        if valueBeforeClick ~= oldValue and slider.afterValueChangedFn then
            valueBeforeClick = oldValue
            local value = slider:GetValue()
            if math.floor(value) < value then value = tonumber(string.format("%.2f", value)) end
            slider.afterValueChangedFn(value)
        end
    end)

    slider:SetValue(low)

    slider:SetScript("OnDisable", function()
        label:SetTextColor(0.4, 0.4, 0.4)
        currentEditBox:SetEnabled(false)
        slider:SetScript("OnEnter", nil)
        slider:SetScript("OnLeave", nil)
        tex:SetColorTexture(0.4, 0.4, 0.4, 0.7)
        lowText:SetTextColor(0.4, 0.4, 0.4)
        highText:SetTextColor(0.4, 0.4, 0.4)
    end)
    slider:SetScript("OnEnable", function()
        label:SetTextColor(1, 1, 1)
        currentEditBox:SetEnabled(true)
        slider:SetScript("OnEnter", slider.onEnter)
        slider:SetScript("OnLeave", slider.onLeave)
        tex:SetColorTexture(accent[1], accent[2], accent[3], 0.7)
        lowText:SetTextColor(unpack(UI.grey))
        highText:SetTextColor(unpack(UI.grey))
    end)

    function slider:UpdateMinMaxValues(minV, maxV)
        slider:SetMinMaxValues(minV, maxV)
        slider.low, slider.high = minV, maxV
        lowText:SetText(minV .. unit)
        highText:SetText(maxV .. unit)
    end
    slider:UpdateMinMaxValues(low, high)

    return slider
end
