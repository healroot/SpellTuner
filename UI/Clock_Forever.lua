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
    shown = MD.Visibility.Want(pct, shown, MD.inCombat, false)
    if shown then widget:Show() else widget:Hide() end
end

--------------------------------------------------------------------------------
-- Hover
--------------------------------------------------------------------------------
local function ShowHover(self)
    local model = MD.Pool.model
    if not model then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("SpellTuner mana clock (modelled)")
    GameTooltip:AddLine(string.format("Mana %d / %d (modelled - the real pool is secret on this client)",
        math.floor((model.mana or 0) + 0.5), math.floor((model.max or 0) + 0.5)))

    local why = model.anchor.why or "not yet anchored"
    local ago = "--"
    if model.anchor.at then
        local d = GetTime() - model.anchor.at
        if d < 0 then d = 0 end
        ago = string.format("%d:%02d", math.floor(d / 60), math.floor(d % 60))
    end
    GameTooltip:AddLine("Anchored " .. ago .. " ago: " .. why)

    if MD.inCombat then
        local state = MD.Pool:Project(GetTime())
        local spend = type(state.spend) == "number" and string.format("%.1f", state.spend) or "-"
        local regen = type(state.regen) == "number" and string.format("%.1f", state.regen) or "-"
        local casts = model.fight and model.fight.casts or 0
        GameTooltip:AddLine("Spend " .. spend .. "/s over " .. tostring(casts) .. " casts, regen " .. regen .. "/s")
    else
        GameTooltip:AddLine("Regen rate read out of combat")
    end

    if model.unpriced and model.unpriced > 0 then
        GameTooltip:AddLine("Unpriced casts: " .. tostring(model.unpriced))
    end

    GameTooltip:AddLine("The bar under the clock is the real pool, drawn by the game")
    GameTooltip:Show()
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
        if MD.db.clock and MD.db.clock.locked then return end
        self:StartMoving()
    end)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        MD.db.clock.point = { point, nil, relPoint, x, y }
    end)
    widget:SetScript("OnEnter", ShowHover)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    local state = MD.Pool:Project(now)
    text:SetText(MD.ManaModel.Text(state))
    MD.API.DrawUnitPower(bar, "player", 0)
    UpdateVisibility()
end

-- Repaints without waiting for the next tick -- used by settings/commands
-- that just changed db.clock, and by the test harness.
function Clock:Refresh()
    if not MD.Pool.model then return end
    Paint(GetTime())
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
