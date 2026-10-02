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
--
-- T93 (docs/SPEC-next.md 7.1, decisions 14, 16 and 18): the clock's words are
-- drawn by UI/ClockView.lua from MD.ManaModel.Face -- three segments at fixed
-- places, each in its tone (F1: TBC's red under 20 s, amber under 60 s; never
-- an arrow); no clock for a character without a mana pool (F3, the shared
-- rule's manaUsersOnly); db.clock.clickThrough (F4); the pulse, once per fight
-- under 30 s and on MD:Alert (F5); db.clock.showRest (F6). The mover seam
-- (ApplyPoint, ResetPosition, Preview) is MD.Clock, provided as MD.ClockWidget.
--
-- T98 (docs/SPEC-next.md 7.2-7.3, decisions 13 and 15): the view owns the
-- layout (db.clockLook: line / compact / bar), the panel (UI.Skin(widget,
-- "clock") -- the style's clock role, the user's overrides) and the bar
-- (built by the view; its source the real pool by default, handed to it by
-- MD.API.DrawUnitPower and never read, or the modelled pool, the time to OOM,
-- the five-second rule from the model's last priced spend, none; the spark).
-- This file hands it the line's facts and the two sources it reads itself,
-- rebuilds the look on CLOCK_LOOK / STYLE_CHANGED (PaintFace: words and bar,
-- no visibility pass), and keeps the frame, the drag, the hover and the one
-- visibility owner. MD.Clock.facts / .view / .bar / .barBack for its readers.
local _, MD = ...
local UI = MD.UI

-- T93: the two switches this file reads, declared here (docs/SPEC-next.md 11:
-- a default is registered by the file that reads it). db.clock's shown /
-- locked / point stay Core_Forever.lua's.
MD:RegisterDefaults({ clock = { showRest = true, clickThrough = false } })

MD.Clock = MD.Clock or {}
local Clock = MD.Clock

-- MD.Clock.model: the pool's model, looked up at every read (a /reload's
-- MD_READY makes a new one), never a copy of it.
setmetatable(Clock, { __index = function(_, k)
    if k == "model" then return MD.Pool and MD.Pool.model end
end })

local widget, view, bar, barBack

-- T93 (F5): the once-per-fight flash under 30 s has fired in this fight.
local flashedThisFight = false
-- T58 (P14, review A28): "in combat" is the kernel's MD.inCombat (Core.lua),
-- set by the two regen events before any other handler of them runs and
-- seeded at MD_READY through the adapter; this file keeps no copy of it.

-- T41 (docs/SPEC-forever-ui.md 4.4): the physical pixel the clock was last
-- snapped to is the view's (view.snappedPx, T98).

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
    local c = MD.db and MD.db.clock
    -- T93 (F4): click-through takes no mouse -- no hover, no click, no drag --
    -- except while the clock is being placed (the preview), as TBC's widget
    -- takes the mouse while unlocked
    widget:EnableMouse(Previewing() or not (c and c.clickThrough))
    if not (c and c.shown) then
        widget:Hide()
        shown = false
        return
    end
    local model = MD.Pool.model
    local pct
    if model and model.max and model.max > 0 then pct = model.mana / model.max end
    -- T93 (F3): no mana pool (a warrior, a rogue), no clock -- the shared
    -- rule's manaUsersOnly, the TBC widget's gate
    local usesMana = MD.player and MD.player.usesMana
    shown = MD.Visibility.Want(pct, shown, MD.inCombat, Previewing(), nil, usesMana ~= false)
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

local function Pair(l, r, rc) return { l = l, r = r, c = "label", rc = rc or "text" } end

-- Clock:SummaryLines(now, state): T79 (P36) -- the clock's own answer in a
-- healer's words, the lines the hover and the minimap button's tooltip share
-- (so the two cannot drift): when mana runs out or is full again, and in a
-- fight when it is full again if you stop. {} before the pool has a model.
-- `state` is the projection at `now` when the caller already has it.
function Clock:SummaryLines(now, state)
    local lines = {}
    if not MD.Pool.model then return lines end
    state = state or MD.Pool:Project(now or GetTime())
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
    if MD.inCombat and type(state.rest) == "number" then
        lines[#lines + 1] = Pair("Full again in", "~" .. Time(state.rest) .. " if you stop", "mana")
    end
    return lines
end

-- T79 (P36): the minimap button's clock lines on this line (UI/MinimapButton.lua):
-- the title, the summary, and the hints when it is given any.
MD:Provide("MinimapLines", function(hints)
    local lines = { { l = "SpellTuner", c = "accent" } }
    for _, ln in ipairs(Clock:SummaryLines(GetTime())) do lines[#lines + 1] = ln end
    if hints then
        lines[#lines + 1] = {}
        for _, h in ipairs(hints) do lines[#lines + 1] = { l = h, c = "muted" } end
    end
    return lines
end)

-- T98 / T115: what the bars are, in the hover's words, from the look the view
-- draws (what it shows, the mana bar's source, where the five-second rule
-- is); none: nothing said.
local FSR_IS = "the five seconds after your last priced cast"
local FSR_WHERE = {
    stacked = "the strip under it",
    veil = "the amber veil over it",
    chip = "the square beside the label",
}
local function BarWords()
    local l = Clock.view and Clock.view.look
    local b = (l and l.bars) or MD.ClockView.BARS_DEFAULT
    local show = b.show or "both"
    if show == "none" then return "" end
    if show == "fsr" then return " The bar is " .. FSR_IS .. "." end
    local manaPart = b.mana == "model" and "your modelled mana (~)" or "your real mana, drawn by the game"
    if show == "mana" then return " The bar is " .. manaPart .. "." end
    local where = FSR_WHERE[b.join] or FSR_WHERE.stacked
    if (b.join == nil or b.join == "stacked") and b.order == "fsrOver" then where = "the strip over it" end
    return " The bar is " .. manaPart .. "; " .. where .. " is " .. FSR_IS .. "."
end

-- Clock:HoverLines(now): the hover's lines (UI/Tip.lua's line model), or nil
-- before the pool has a model.
function Clock:HoverLines(now)
    local model = MD.Pool.model
    if not model then return nil end
    local lines = { { l = "SpellTuner mana clock", c = "accent" } }
    local state = MD.Pool:Project(now or GetTime())
    lines[#lines + 1] = Pair("Mana", string.format("~%d of %d", math.floor((model.mana or 0) + 0.5),
        math.floor((model.max or 0) + 0.5)), "mana")
    -- T79: the summary the minimap button shows too
    for _, ln in ipairs(Clock:SummaryLines(now, state)) do lines[#lines + 1] = ln end
    if MD.inCombat then
        local casts = model.fight and model.fight.casts or 0
        lines[#lines + 1] = Pair("Spending", Rate(state.spend) .. " over " .. tostring(casts)
            .. (casts == 1 and " cast" or " casts"))
        lines[#lines + 1] = Pair("Regen", Rate(state.regen))
    end
    if model.unpriced and model.unpriced > 0 then
        lines[#lines + 1] = Pair("Unpriced casts", tostring(model.unpriced))
    end
    lines[#lines + 1] = {}
    lines[#lines + 1] = { l = "~ = modelled from your casts." .. BarWords(), c = "muted", wrap = true }
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
local DEFAULT_POINT = { "TOP", nil, "TOP", 0, -120 }
local function ApplyPoint()
    if not widget then return end
    local p = MD.db.clock and MD.db.clock.point
    widget:ClearAllPoints()
    if p and p[1] then
        widget:SetPoint(p[1], UIParent, p[3] or p[1], p[4] or 0, p[5] or 0)
    else
        widget:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

-- T41 (docs/SPEC-forever-ui.md 4.4): the theme's `bg` fill and a 1-px border,
-- and the bar's backing sized one physical pixel around it. The window
-- manager never touches the clock (6.1), so the clock keeps itself snapped:
-- Paint asks the view to whenever UI.px(1) has moved (a UI scale or display
-- change), no reload needed. T98: the panel is the view's -- UI.Skin(widget,
-- "clock") with the style's clock role and the user's overrides.

-- T98 (docs/SPEC-next.md 7.2-7.3): what this line tells the renderer about
-- itself -- the bar's own meaning (the real pool, decision 15 (a)), a pool it
-- can only hand to a status bar unread (no ring may draw it), a modelled pool
-- (the face's pct), its widest label ("~FULL", the pool is modelled) and the
-- rest switch (F6).
-- T115: no regen tick (the pool cannot be read, so its rises cannot be
-- timed) and flat bars only.
local facts = { line = "forever", poolPlain = false, model = true, tick = false, textures = false,
    labelSample = "~FULL", show = {} }
MD.ClockView.lineFacts = facts
local function Facts()
    local c = MD.db and MD.db.clock
    facts.show.rest = not (c and c.showRest == false)
    facts.show.cd = false -- T115: this line has no cooldown secondary (Line's minimum)
    return facts
end

-- The bar's sources this line draws itself: the real pool, handed to the bar
-- by the adapter and never read (MD.API.DrawUnitPower), and the five-second
-- rule from the model's last priced spend (plain: the model's own clock).
local draw = {
    pool = function(b) MD.API.DrawUnitPower(b, "player", 0) end,
    fsr = function(now)
        local m = MD.Pool and MD.Pool.model
        if not (m and type(m.lastSpend) == "number" and type(now) == "number") then return nil end
        return m.lastSpend + 5 - now
    end,
    -- T115: the chip's swipe starts at the spend
    spend = function()
        local m = MD.Pool and MD.Pool.model
        if m and type(m.lastSpend) == "number" then return m.lastSpend end
        return nil
    end,
}

-- T93 / T98: the resolved look (UI/ClockView.lua: the layout's defaults, the
-- style's clock role, the user's overrides), made again on CLOCK_LOOK and
-- STYLE_CHANGED; the rest switch refreshed in place at each paint.
local look
local function Look()
    local f = Facts()
    if not look then look = MD.ClockView.Look(f) end
    look.show.rest, look.show.cd = f.show.rest, f.show.cd
    return look
end

local function CreateWidget()
    widget = CreateFrame("Frame", "SpellTunerClock", UIParent, "BackdropTemplate")
    widget:SetSize(180, 32)
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

    -- T93: the words, in three fixed segments (UI/ClockView.lua); the
    -- label slot is as wide as this line's widest label, "~FULL". T98: and
    -- the layout, the panel and the bar with its black backing (T41: one
    -- physical pixel wider on every side, so the bar reads on bright
    -- ground), the view's -- 160 x 4 under the line layout, the real pool by
    -- default, drawn by the game in the mana blue
    view = MD.ClockView.Build(widget, Look(), draw)
    Clock.view = view
    bar, barBack = view.bar, view.barBack
    Clock.bar = bar
    Clock.barBack = barBack
    Clock.strip = view.strip
    Clock.stripBack = view.stripBack
    Clock.facts = facts
    widget:SetScale(view:Scale())

    ApplyPoint()
    Clock.frame = widget
end

--------------------------------------------------------------------------------
-- Paint: rendering only, tick-driven -- the model is event/tick driven in
-- Engine/ManaPool_Forever.lua, whose tick runs just before this file's.
--------------------------------------------------------------------------------
-- T98: the words and the bar only -- what a new look repaints at once, with
-- no visibility pass (a layout switch never shows or hides the clock).
local function PaintFace(now)
    if UI.px(1, widget) ~= view.snappedPx then view:Snap() end -- T41: re-snap after a scale change
    local state
    if Previewing() then
        -- T70: the preview says what it is for (TBC's words), in the accent
        view:Message("SpellTuner - drag me", UI.RGB("accent"))
    else
        -- T93: the face, in segments and tones (F1), the rest switch (F6)
        state = MD.Pool:Project(now)
        view:Paint(MD.ManaModel.Face(state, now), Look())
    end
    -- T115: the mana bar -- the real pool by default, handed to the bar by
    -- MD.API.DrawUnitPower and never read -- and the five-second rule, placed
    -- by time alone (the view's step moves it between ticks)
    view:PaintBar(now)
    return state
end

local function Paint(now)
    local state = PaintFace(now)
    UpdateVisibility()
    -- T93 (F5): one attention event per fight, the first time the clock reads
    -- under 30 s (TBC's widget's rule, on the model's projection)
    if state and not flashedThisFight and shown and MD.inCombat and state.mode == "oom"
        and type(state.tto) == "number" and state.tto < 30 then
        flashedThisFight = true
        view:Pulse()
    end
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

-- T93 (docs/SPEC-next.md 6.3, the mover seam): the frame at its stored place
-- (db.clock.point), or the default one -- what a mover calls after writing it.
function Clock:ApplyPoint()
    ApplyPoint()
end

-- T93 (F5): MD:Alert's pulse (Core.lua calls MD:PulseWidget when it exists),
-- on this clock while it is shown -- the TBC widget's own rule.
function MD:PulseWidget()
    if widget and view and shown then view:Pulse() end
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

-- T93 (F5): a new fight may flash again.
MD:On("PLAYER_REGEN_DISABLED", function()
    flashedThisFight = false
end)

-- T98: a new look (a layout, an override: CLOCK_LOOK; a style: STYLE_CHANGED)
-- -- the view rebuilt inside the frame, which is never shown or hidden here.
-- After a CLOCK_LOOK (the user's change) the words and the bar are drawn at
-- once; after a style the next tick draws them (a style changes paint only).
local function NewLook(repaint)
    look = nil
    local l = Look()
    if not view then return end
    local w0, h0 = widget:GetWidth(), widget:GetHeight()
    local s0 = widget:GetScale()
    view:SetLook(l)
    local s1 = view:Scale()
    if s1 ~= s0 then
        -- T115: the scale per layout, the clock's centre kept where it was
        MD.db.clock = MD.db.clock or {}
        local p = MD.db.clock.point
        if type(p) ~= "table" or not p[1] then p = DEFAULT_POINT end
        local x1, y1 = MD.ClockView.KeepCentre(p[1], p[4] or 0, p[5] or 0, s0, s1, w0, h0,
            widget:GetWidth(), widget:GetHeight())
        MD.db.clock.point = { p[1], nil, p[3] or p[1], x1, y1 }
        widget:SetScale(s1)
        ApplyPoint()
    end
    if repaint and MD.Pool.model then PaintFace(GetTime()) end
end
MD:RegisterCallback("CLOCK_LOOK", function() NewLook(true) end)
MD:RegisterCallback("STYLE_CHANGED", function() NewLook(false) end)

-- T93: the mover seam under the name both lines provide (UI/Widget.lua's
-- MD.Widget on TBC): ApplyPoint, ResetPosition, Preview, frame.
MD:Provide("ClockWidget", Clock)

-- T93: the two new switches by hand until Settings -> Clock (T102) shows
-- them -- TBC's /md rest and /md tooltip, as subcommands of /st clock
-- (docs/SPEC-next.md 2.5: matched before the verb, so /st clock and
-- /st clock lock are unchanged).
MD:AddSubcommand("clock", "rest", function()
    MD.db.clock = MD.db.clock or {}
    MD.db.clock.showRest = MD.db.clock.showRest == false
    MD:Print("mana clock: rest segment " .. (MD.db.clock.showRest and "on" or "off"))
    if Clock.frame then Clock:Refresh() end
end, "rest", "toggle the 'rest' segment (time to full if you stop casting)")
MD:AddSubcommand("clock", "clickthrough", function()
    MD.db.clock = MD.db.clock or {}
    MD.db.clock.clickThrough = not MD.db.clock.clickThrough
    MD:Print("mana clock: " .. (MD.db.clock.clickThrough
        and "click-through - it takes no mouse input (no hover, no click) except while you place it"
        or "takes the mouse again - hover for the breakdown, left-click opens the window"))
    if Clock.frame then Clock:Refresh() end
end, "clickthrough", "the clock takes no mouse input")
