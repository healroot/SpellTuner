-- T11 (docs/tasks/T11-clock.md, M2): the Forever counterpart of the TBC mana
-- clock -- a small movable widget over the modelled pool, because current
-- mana is secret always on this client (Facts). Reaches the client only
-- through MD.API; the widget toolkit (CreateFrame, GameTooltip, UI/Style.lua)
-- is not a client call (CLAUDE.md). Forever only.
--
-- T68 (P24, review A29): this file PAINTS. The model instance, the cast and
-- regen events, the pricing and the assume-full rule are
-- Engine/ManaPool_Forever.lua's (MD.Pool), which loads just before it; the
-- clock reads MD.Pool.model and MD.Pool:Project. MD.Clock:Pool() and
-- MD.Clock.model stay as aliases of the pool's for their existing readers.
local _, MD = ...
local UI = MD.UI

MD.Clock = MD.Clock or {}
local Clock = MD.Clock

-- MD.Clock.model: the pool's model, looked up at every read (a /reload's
-- MD_READY makes a new one), never a copy of it.
setmetatable(Clock, { __index = function(_, k)
    if k == "model" then return MD.Pool and MD.Pool.model end
end })

local widget, text, bar, barBack
-- T58 (P14, review A28): "in combat" is the kernel's MD.inCombat (Core.lua),
-- set by the two regen events before any other handler of them runs and
-- seeded at MD_READY through the adapter; this file keeps no copy of it.

-- T41 (docs/SPEC-forever-ui.md 4.4): the physical pixel the clock was last
-- snapped to, in its own units (UI.px(1, widget)); nil until the first snap.
local snappedPx

-- T11b (docs/tasks/T11b-clock-modes.md): out-of-combat hysteresis state --
-- the one flag that remembers which side of the 90/95 band the clock is
-- currently on (the rule is MD.Visibility.Want, UI/Visibility.lua, T68).
local shown = false

-- T70 (P26 of docs/PLAN-refactor-ux.md, review U18): the preview -- the clock
-- up at any mana level for PREVIEW_SECONDS after Lock is unticked or Show now
-- is pressed, as TBC's widget does (UI/Widget.lua forceUntil), so it can be
-- placed at full mana. A GetTime() deadline; 0 is "no preview".
Clock.PREVIEW_SECONDS = 60
local previewUntil = 0

-- T70: a left-click opens the window; a drag is not a click. OnMouseDown
-- clears this, OnDragStart sets it, OnMouseUp reads it -- whatever order the
-- client fires OnDragStop and OnMouseUp in.
local dragged = false

local function Previewing()
    return GetTime() < previewUntil
end

--------------------------------------------------------------------------------
-- Visibility: one owner. Hidden when db.clock.shown is false; else the rule
-- the TBC widget asks too (MD.Visibility.Want, T68): shown in combat, and out
-- of combat once the modelled pool drops under 90% of max, staying up until
-- it is back over 95% -- never the plain "below 95%" threshold, which redrew
-- at 94.x% (T11b Facts, the author's `~refill 0:05` sighting). No max yet
-- reads as nothing to compare: hidden.
--------------------------------------------------------------------------------
local function UpdateVisibility()
    if not widget then return end
    if not (MD.db and MD.db.clock and MD.db.clock.shown) then
        widget:Hide()
        shown = false
        return
    end
    local model = MD.Pool.model
    local pct
    if model and model.max and model.max > 0 then pct = model.mana / model.max end
    shown = MD.Visibility.Want(pct, shown, MD.inCombat, Previewing())
    if shown then widget:Show() else widget:Hide() end
end

--------------------------------------------------------------------------------
-- Hover. T76 (P32 of docs/PLAN-refactor-ux.md, review U9): label / value
-- pairs in a healer's words, through UI/Tip.lua (MD.Tip:Show: GameTooltip, in
-- the kit's skin under the theme) -- what the pool holds, when it runs dry,
-- when it is full again if you stop, what you spend and get back. Every
-- modelled number carries the clock's "~" in the mana colour, and one muted
-- line says what "~" means; no word about the client's secrets or the
-- model's anchor (those are /st dump's).
--------------------------------------------------------------------------------
-- The clock's own rounding (Engine/ManaModel.lua's Text): to 5 s, over ten
-- minutes ">10m", nothing to show "--".
local function Time(sec)
    if type(sec) ~= "number" then return "--" end
    if sec > 600 then return ">10m" end
    sec = math.floor(sec / 5 + 0.5) * 5
    if sec > 600 then return ">10m" end
    return MD.Util.Clock(sec)
end

local function Rate(v)
    if type(v) ~= "number" then return "-" end
    return string.format("~%d a sec", math.floor(v + 0.5))
end

-- Clock:HoverLines(now): the hover's lines (UI/Tip.lua's line model), or nil
-- before the pool has a model.
function Clock:HoverLines(now)
    local model = MD.Pool.model
    if not model then return nil end
    local function Pair(l, r, rc) return { l = l, r = r, c = "label", rc = rc or "text" } end
    local lines = { { l = "SpellTuner mana clock", c = "accent" } }
    local state = MD.Pool:Project(now or GetTime())
    lines[#lines + 1] = Pair("Mana", string.format("~%d of %d", math.floor((model.mana or 0) + 0.5),
        math.floor((model.max or 0) + 0.5)), "mana")
    local m = state.mode
    if m == "oom" then
        lines[#lines + 1] = Pair("Out of mana in", "~" .. Time(state.tto), "mana")
    elseif m == "full" then
        lines[#lines + 1] = Pair("Full again in", "~" .. Time(state.ttf), "mana")
    elseif m == "warmup" then
        lines[#lines + 1] = Pair("Out of mana in", "a few more casts first", "muted")
    elseif m == "hold" then
        lines[#lines + 1] = Pair("Out of mana in", (state.regen == nil) and "--" or "not at this pace", "muted")
    elseif m == "ooc" then
        lines[#lines + 1] = Pair("Full again in", "~" .. Time(state.ttf), "mana")
    elseif m == "fullnow" then
        lines[#lines + 1] = Pair("Full", "now", "text")
    end
    if MD.inCombat then
        if type(state.rest) == "number" then
            lines[#lines + 1] = Pair("Full again in", "~" .. Time(state.rest) .. " if you stop", "mana")
        end
        local casts = model.fight and model.fight.casts or 0
        lines[#lines + 1] = Pair("Spending", Rate(state.spend) .. " over " .. tostring(casts)
            .. (casts == 1 and " cast" or " casts"))
        lines[#lines + 1] = Pair("Regen", Rate(state.regen))
    end
    if model.unpriced and model.unpriced > 0 then
        lines[#lines + 1] = Pair("Unpriced casts", tostring(model.unpriced))
    end
    lines[#lines + 1] = {}
    lines[#lines + 1] = { l = "~ = modelled from your casts. The bar under the clock is your real mana, "
        .. "drawn by the game.", c = "muted", wrap = true }
    lines[#lines + 1] = Pair("Left-click", "open the window (out of combat)")
    return lines
end

local function ShowHover(self)
    local lines = Clock:HoverLines(GetTime())
    if not lines then return end
    MD.Tip:Show(self, lines, { anchor = "ANCHOR_TOP" })
end

--------------------------------------------------------------------------------
-- The widget
--------------------------------------------------------------------------------
local function ApplyPoint()
    local p = MD.db.clock and MD.db.clock.point
    widget:ClearAllPoints()
    if p and p[1] then
        widget:SetPoint(p[1], UIParent, p[3] or p[1], p[4] or 0, p[5] or 0)
    else
        widget:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

-- T41 (docs/SPEC-forever-ui.md 4.4): the theme's `bg` fill and a 1-px border
-- (UI.StylizeFrame under UI.PIXEL draws the physical-pixel edge), and the
-- bar's backing sized one physical pixel around it. The window manager never
-- touches the clock (6.1), so the clock keeps itself snapped: Paint calls this
-- whenever UI.px(1) has moved (a UI scale or display change), no reload
-- needed. Without the theme the kit's own default fill is used.
local function Snap()
    local e = UI.px(1, widget)
    local P = UI.PALETTE or {}
    UI.StylizeFrame(widget, P.bg, P.border)
    barBack:SetSize(160 + 2 * e, 4 + 2 * e)
    snappedPx = e
end

local function CreateWidget()
    widget = CreateFrame("Frame", "SpellTunerClock", UIParent, "BackdropTemplate")
    widget:SetSize(180, 30)
    widget:SetFrameStrata("MEDIUM")
    widget:SetMovable(true)
    widget:SetClampedToScreen(true)
    widget:EnableMouse(true)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", function(self)
        -- T70: draggable while unlocked, and during a preview (TBC's rule)
        if MD.db.clock and MD.db.clock.locked and not Previewing() then return end
        dragged = true
        self:StartMoving()
    end)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        MD.db.clock.point = { point, nil, relPoint, x, y }
    end)
    widget:SetScript("OnEnter", ShowHover)
    widget:SetScript("OnLeave", function() MD.Tip:Hide() end)
    -- T70 (U18): a left-click opens the window -- out of combat only, since
    -- the window hides in combat (decision 4) and the clock is up in every
    -- fight, where a stray click would put the window over the party.
    widget:SetScript("OnMouseDown", function() dragged = false end)
    widget:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or dragged then return end
        if MD.inCombat then return end
        if MD.ToggleDashboard then MD:ToggleDashboard() end
    end)

    text = widget:CreateFontString(nil, "OVERLAY", UI.FONT)
    text:SetPoint("TOP", widget, "TOP", 0, -4)
    Clock.text = text

    bar = CreateFrame("StatusBar", nil, widget)
    bar:SetSize(160, 4)
    bar:SetPoint("BOTTOM", widget, "BOTTOM", 0, 5)
    bar:SetStatusBarTexture(UI.whiteTexture)
    bar:SetStatusBarColor(0.3, 0.6, 1)
    Clock.bar = bar

    -- T41: a black backing one physical pixel wider than the bar on every
    -- side, so the bar reads on bright ground. A texture of the widget: the
    -- bar is a child frame and draws above it, the backdrop beneath it.
    barBack = widget:CreateTexture(nil, "ARTWORK")
    barBack:SetColorTexture(0, 0, 0, 1)
    barBack:SetPoint("CENTER", bar, "CENTER", 0, 0)
    Clock.barBack = barBack

    Snap()
    ApplyPoint()
    Clock.frame = widget
end

--------------------------------------------------------------------------------
-- Paint: rendering only, tick-driven -- the model is event/tick driven in
-- Engine/ManaPool_Forever.lua, whose tick runs just before this file's.
--------------------------------------------------------------------------------
local function Paint(now)
    if UI.px(1, widget) ~= snappedPx then Snap() end -- T41: re-snap after a scale change
    if Previewing() then
        -- T70: the preview says what it is for (TBC's words), in the accent
        text:SetText("SpellTuner - drag me")
        text:SetTextColor(UI.RGB("accent"))
    else
        local state = MD.Pool:Project(now)
        text:SetText(MD.ManaModel.Text(state))
        text:SetTextColor(UI.RGB("text"))
    end
    MD.API.DrawUnitPower(bar, "player", 0)
    UpdateVisibility()
end

-- Repaints without waiting for the next tick -- used by settings/commands
-- that just changed db.clock, and by the test harness.
function Clock:Refresh()
    if not MD.Pool.model then return end
    Paint(GetTime())
end

-- T70 (P26, U18): what Settings -> General's MANA CLOCK pane calls.
-- The clock up for `seconds` (default PREVIEW_SECONDS) at any mana level, and
-- draggable meanwhile; off (db.clock.shown false) stays off.
function Clock:Preview(seconds)
    previewUntil = GetTime() + (tonumber(seconds) or Clock.PREVIEW_SECONDS)
    if widget and MD.Pool.model then Paint(GetTime()) end
end

function Clock:Previewing()
    return Previewing()
end

-- Lock on: the preview ends and the clock stays where it is. Lock off: the
-- 60 s preview, so it can be dragged at full mana.
function Clock:SetLocked(locked)
    MD.db.clock = MD.db.clock or {}
    MD.db.clock.locked = locked and true or false
    if locked then
        previewUntil = 0
        if widget and MD.Pool.model then Paint(GetTime()) end
    else
        Clock:Preview()
    end
end

-- Back at the default place (the top of the screen): the saved point cleared.
function Clock:ResetPosition()
    MD.db.clock = MD.db.clock or {}
    MD.db.clock.point = nil
    if widget then ApplyPoint() end
end

-- Kept for its readers (the Spellbook pane, the spell tooltip): the pool's.
function Clock:Pool()
    return MD.Pool:Pool()
end

--------------------------------------------------------------------------------
-- Wiring: the widget, once the pool has its model (MD.Pool's MD_READY runs
-- first), and a repaint on every tick after the pool's own.
--------------------------------------------------------------------------------
MD:RegisterCallback("MD_READY", function()
    if not widget then CreateWidget() end
    UpdateVisibility()
end)

MD:OnTick(function()
    if not MD.Pool.model then return end
    if widget then Paint(GetTime()) end
end)
