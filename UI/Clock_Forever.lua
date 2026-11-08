-- T11 (docs/tasks/T11-clock.md, M2): the Forever counterpart of the TBC mana
-- clock -- a small movable widget over the modelled pool, because current
-- mana is secret always on this client (Facts). Reaches the client only
-- through ST.API; the widget toolkit (CreateFrame, GameTooltip, UI/Style.lua)
-- is not a client call (CLAUDE.md). Forever only.
--
-- T68 (P24, review A29): this file PAINTS. The model instance, the cast and
-- regen events, the pricing and the assume-full rule are
-- Engine/ManaPool_Forever.lua's (ST.Pool), which loads just before it; the
-- clock reads ST.Pool.model and ST.Pool:Project. ST.Clock:Pool() and
-- ST.Clock.model stay as aliases of the pool's for their existing readers.
--
-- T93: no clock for a character without a mana pool (F3, the shared rule's
-- manaUsersOnly); db.clock.clickThrough (F4); the pulse, once per fight under
-- 30 s and on ST:Alert (F5). The mover seam (ApplyPoint, ResetPosition,
-- Preview) is ST.Clock, provided as ST.ClockWidget.
--
-- T145c (docs/SPEC-clock-v3.md 2.5; docs/tasks/T145c-clock-bar.md): the
-- renderer is UI/ClockBar.lua (it replaces UI/ClockView.lua). The tick is
--     ST.Pool:Project -> ST.ManaModel.Face -> ST.ClockWords.Build(face, look,
--     steady, now, words, ST.Pool:QuietFull(now)) -> renderer:Paint(words),
--     renderer:PaintPower(withMax) (the range only when the max moved, or
--     every RANGE_EVERY s; review N1)
-- UNIT_POWER_FREQUENT -> renderer:PaintPower() (the value only), UNIT_MAXPOWER
-- -> PaintPower(true), CLOCK_LOOK / STYLE_CHANGED -> renderer:Apply(look) with
-- the look from UI/ClockStore.lua (migrated once at MD_READY). This file keeps
-- the frame, the drag, the hover and the one visibility owner; the moving line
-- is the renderer's own driver, which nothing here starts or stops.
local _, ST = ...
local UI = ST.UI

-- T93: the two switches this file reads, declared here (docs/SPEC-next.md 11:
-- a default is registered by the file that reads it). db.clock's shown /
-- locked / point stay Core_Forever.lua's. T145c: showRest is the Rest text's
-- own switch now (db.clockLook.texts.rest.on); the key stays for its readers.
ST:RegisterDefaults({ clock = { showRest = true, clickThrough = false } })

ST.Clock = ST.Clock or {}
local Clock = ST.Clock

-- ST.Clock.model: the pool's model, looked up at every read (a /reload's
-- MD_READY makes a new one), never a copy of it.
setmetatable(Clock, { __index = function(_, k)
    if k == "model" then return ST.Pool and ST.Pool.model end
end })

local widget, renderer

-- T93 (F5): the once-per-fight flash under 30 s has fired in this fight.
local flashedThisFight = false
-- T58 (P14, review A28): "in combat" is the kernel's ST.inCombat (Core.lua),
-- set by the two regen events before any other handler of them runs and
-- seeded at MD_READY through the adapter; this file keeps no copy of it.

-- T11b (docs/tasks/T11b-clock-modes.md): out-of-combat hysteresis state --
-- the one flag that remembers which side of the 90/95 band the clock is
-- currently on (the rule is ST.Visibility.Want, UI/Visibility.lua, T68).
local shown = false

-- T144 (item 5): the shown time's latch (ST.ClockWords.Steady's) -- at most
-- one 5 s step a second; emptied on PLAYER_REGEN_*, whenever the clock hides
-- and when a preview ends.
local steady = {}
local function ResetSteady()
    for k in pairs(steady) do steady[k] = nil end
end
-- the latch, for its tests (read-only by convention)
function Clock:SteadyLatch() return steady end

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
-- the TBC widget asks too (ST.Visibility.Want, T68): shown in combat, and out
-- of combat once the modelled pool drops under 90% of max, staying up until
-- it is back over 95% -- never the plain "below 95%" threshold, which redrew
-- at 94.x% (T11b Facts, the author's `~refill 0:05` sighting). No max yet
-- reads as nothing to compare: hidden.
--------------------------------------------------------------------------------
local function UpdateVisibility()
    if not widget then return end
    local c = ST.db and ST.db.clock
    -- T93 (F4): click-through takes no mouse -- no hover, no click, no drag --
    -- except while the clock is being placed (the preview), as TBC's widget
    -- takes the mouse while unlocked
    widget:EnableMouse(Previewing() or not (c and c.clickThrough))
    if not (c and c.shown) then
        widget:Hide()
        shown = false
        ResetSteady()
        return
    end
    local model = ST.Pool.model
    local pct
    if model and model.max and model.max > 0 then pct = model.mana / model.max end
    -- T93 (F3): no mana pool (a warrior, a rogue), no clock -- the shared
    -- rule's manaUsersOnly, the TBC widget's gate
    local usesMana = ST.player and ST.player.usesMana
    shown = ST.Visibility.Want(pct, shown, ST.inCombat, Previewing(), nil, usesMana ~= false)
    if shown then widget:Show() else widget:Hide(); ResetSteady() end
end

--------------------------------------------------------------------------------
-- Hover. T76 (P32 of docs/PLAN-refactor-ux.md, review U9): label / value
-- pairs in a healer's words, through UI/Tip.lua (ST.Tip:Show: GameTooltip, in
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
    return ST.Util.Clock(sec)
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
    if not ST.Pool.model then return lines end
    state = state or ST.Pool:Project(now or GetTime())
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
    if ST.inCombat and type(state.rest) == "number" then
        lines[#lines + 1] = Pair("Full again in", "~" .. Time(state.rest) .. " if you stop", "mana")
    end
    return lines
end

-- T79 (P36): the minimap button's clock lines on this line (UI/MinimapButton.lua):
-- the title, the summary, and the hints when it is given any.
ST:Provide("MinimapLines", function(hints)
    local lines = { { l = "SpellTuner", c = "accent" } }
    for _, ln in ipairs(Clock:SummaryLines(GetTime())) do lines[#lines + 1] = ln end
    if hints then
        lines[#lines + 1] = {}
        for _, h in ipairs(hints) do lines[#lines + 1] = { l = h, c = "muted" } end
    end
    return lines
end)

-- T145c: what the bar is, in the hover's words, from the look drawn (the
-- moving line on or off).
local FSR_IS = "the five seconds after your last priced cast"
local function BarWords()
    local l = renderer and renderer.look
    local words = " The bar is your real mana, drawn by the game"
    if l and l.line then return words .. "; the amber line crossing it is " .. FSR_IS .. "." end
    return words .. "."
end

-- Clock:HoverLines(now): the hover's lines (UI/Tip.lua's line model), or nil
-- before the pool has a model.
function Clock:HoverLines(now)
    local model = ST.Pool.model
    if not model then return nil end
    local lines = { { l = "SpellTuner mana clock", c = "accent" } }
    local state = ST.Pool:Project(now or GetTime())
    lines[#lines + 1] = Pair("Mana", string.format("~%d of %d", math.floor((model.mana or 0) + 0.5),
        math.floor((model.max or 0) + 0.5)), "mana")
    -- T79: the summary the minimap button shows too
    for _, ln in ipairs(Clock:SummaryLines(now, state)) do lines[#lines + 1] = ln end
    if ST.inCombat then
        local casts = model.fight and model.fight.casts or 0
        lines[#lines + 1] = Pair("Spending", Rate(state.spend) .. " over " .. tostring(casts)
            .. (casts == 1 and " cast" or " casts"))
        lines[#lines + 1] = Pair("Regen", Rate(state.regen))
    end
    if model.unpriced and model.unpriced > 0 then
        lines[#lines + 1] = Pair("Unpriced casts", tostring(model.unpriced))
    end
    lines[#lines + 1] = {}
    -- T116 / T144 S1: a Mana % / Mana text drawn from the model says so
    local mw = renderer and renderer:Modelled()
    if type(mw) == "string" and mw ~= "" then
        lines[#lines + 1] = { l = mw .. " is the model's; the game's own number cannot be shown yet.",
            c = "muted", wrap = true }
    end
    lines[#lines + 1] = { l = "~ = modelled from your casts." .. BarWords(), c = "muted", wrap = true }
    lines[#lines + 1] = Pair("Left-click", "open the window (out of combat)")
    return lines
end

local function ShowHover(self)
    local lines = Clock:HoverLines(GetTime())
    if not lines then return end
    ST.Tip:Show(self, lines, { anchor = "ANCHOR_TOP" })
end

--------------------------------------------------------------------------------
-- The widget
--------------------------------------------------------------------------------
local DEFAULT_POINT = { "TOP", nil, "TOP", 0, -120 }
local function ApplyPoint()
    if not widget then return end
    local p = ST.db.clock and ST.db.clock.point
    widget:ClearAllPoints()
    if p and p[1] then
        widget:SetPoint(p[1], UIParent, p[3] or p[1], p[4] or 0, p[5] or 0)
    else
        widget:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

-- T145c (docs/SPEC-clock-v3.md 2.5): this line's sources for the renderer
-- (UI/ClockBar.lua): the real pool, its range and its mana texts, handed to
-- the bar and the font strings by the adapter and never read
-- (ST.API.DrawUnitPower / DrawUnitPowerMax / DrawPowerText), and the
-- five-second rule's end from the model's last priced spend (plain: the
-- model's own clock).
local draw = {
    pool = function(b) ST.API.DrawUnitPower(b, "player", 0, true) end, -- T143: eased
    poolMax = function(b) ST.API.DrawUnitPowerMax(b, "player", 0) end,
    fsrEnd = function()
        local m = ST.Pool and ST.Pool.model
        if m and type(m.lastSpend) == "number" then return m.lastSpend + 5 end
        return nil
    end,
    -- T116 / T144: Mana, Mana / max and Mana % drawn by the game while
    -- ST.API.POWER_TEXT_READS is on; off, the renderer draws the model's words
    powerText = function(fs, kind)
        if ST.API.POWER_TEXT_READS ~= true then return false end
        return ST.API.DrawPowerText(fs, "player", 0, kind) == true
    end,
}
Clock.draw = draw

-- The look drawn (UI/ClockStore.lua: a validated v3 copy), made again on
-- CLOCK_LOOK and STYLE_CHANGED; the words, one table reused every tick.
local look
local words = {}

local function CreateWidget()
    widget = CreateFrame("Frame", "SpellTunerClock", UIParent, "BackdropTemplate")
    widget:SetSize(200, 8)
    widget:SetFrameStrata("MEDIUM")
    widget:SetMovable(true)
    widget:SetClampedToScreen(true)
    widget:EnableMouse(true)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", function(self)
        -- T70: draggable while unlocked, and during a preview (TBC's rule)
        if ST.db.clock and ST.db.clock.locked and not Previewing() then return end
        dragged = true
        self:StartMoving()
    end)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ST.db.clock.point = { point, nil, relPoint, x, y }
    end)
    widget:SetScript("OnEnter", ShowHover)
    widget:SetScript("OnLeave", function() ST.Tip:Hide() end)
    -- T70 (U18): a left-click opens the window -- out of combat only, since
    -- the window hides in combat (decision 4) and the clock is up in every
    -- fight, where a stray click would put the window over the party.
    widget:SetScript("OnMouseDown", function() dragged = false end)
    widget:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or dragged then return end
        if ST.inCombat then return end
        if ST.ToggleDashboard then ST:ToggleDashboard() end
    end)

    -- T145c: the renderer, laid out once per look
    renderer = ST.ClockBar.New(widget, draw)
    Clock.renderer = renderer
    look = ST.ClockStore.Look()
    renderer:Apply(look)

    ApplyPoint()
    Clock.frame = widget
end

--------------------------------------------------------------------------------
-- Paint: rendering only, tick-driven -- the model is event/tick driven in
-- Engine/ManaPool_Forever.lua, whose tick runs just before this file's.
--------------------------------------------------------------------------------
-- T145c (spec 2.5): the face, its words (the FULL rule, Steady, the quiet
-- pool) and the power -- text and colour only; no visibility pass.
local wasPreviewing = false
-- T145 review N1: the tick hands the bar its range only when the plain max
-- moved, else every RANGE_EVERY seconds as a safety net -- each
-- SetMinMaxValues may restart the client's easing (review W1)
Clock.RANGE_EVERY = 10
local rangeMax, rangeAt = nil, nil
local function PaintFace(now)
    renderer:Snap() -- T41: Apply again after a UI scale change, else a compare
    local state
    if Previewing() then
        -- T70: the preview says what it is for (TBC's words), in the accent
        wasPreviewing = true
        renderer:Message("SpellTuner - drag me", UI.RGB("accent"))
    else
        -- T144 N3: the steady time starts over when a preview ends
        if wasPreviewing then
            wasPreviewing = false
            ResetSteady()
        end
        renderer:Message(nil)
        state = ST.Pool:Project(now)
        local face = ST.ManaModel.Face(state, now)
        ST.ClockWords.Build(face, look, steady, now, words, ST.Pool:QuietFull(now))
        renderer:Paint(words)
    end
    local mx = ST.Pool.model and ST.Pool.model.max
    local withMax = mx ~= rangeMax or rangeAt == nil or now - rangeAt >= Clock.RANGE_EVERY
    if withMax then rangeMax, rangeAt = mx, now end
    renderer:PaintPower(withMax)
    return state
end

local function Paint(now)
    local state = PaintFace(now)
    UpdateVisibility()
    -- T93 (F5): one attention event per fight, the first time the clock reads
    -- under 30 s (TBC's widget's rule, on the model's projection)
    if state and not flashedThisFight and shown and ST.inCombat and state.mode == "oom"
        and type(state.tto) == "number" and state.tto < 30 then
        flashedThisFight = true
        renderer:Pulse()
    end
end

-- Repaints without waiting for the next tick -- used by settings/commands
-- that just changed db.clock, and by the test harness.
function Clock:Refresh()
    if not ST.Pool.model or not widget then return end
    Paint(GetTime())
end

-- T70 (P26, U18): what Settings -> General's MANA CLOCK pane calls.
-- The clock up for `seconds` (default PREVIEW_SECONDS) at any mana level, and
-- draggable meanwhile; off (db.clock.shown false) stays off.
function Clock:Preview(seconds)
    previewUntil = GetTime() + (tonumber(seconds) or Clock.PREVIEW_SECONDS)
    if widget and ST.Pool.model then Paint(GetTime()) end
end

function Clock:Previewing()
    return Previewing()
end

-- Lock on: the preview ends and the clock stays where it is. Lock off: the
-- 60 s preview, so it can be dragged at full mana.
function Clock:SetLocked(locked)
    ST.db.clock = ST.db.clock or {}
    ST.db.clock.locked = locked and true or false
    if locked then
        previewUntil = 0
        if widget and ST.Pool.model then Paint(GetTime()) end
    else
        Clock:Preview()
    end
end

-- T93 (docs/SPEC-next.md 6.3, the mover seam): the frame at its stored place
-- (db.clock.point), or the default one -- what a mover calls after writing it.
function Clock:ApplyPoint()
    ApplyPoint()
end

-- T93 (F5): ST:Alert's pulse (Core.lua calls ST:PulseWidget when it exists),
-- on this clock while it is shown -- the TBC widget's own rule.
function ST:PulseWidget()
    if widget and renderer and shown then renderer:Pulse() end
end

-- Back at the default place (the top of the screen): the saved point cleared.
function Clock:ResetPosition()
    ST.db.clock = ST.db.clock or {}
    ST.db.clock.point = nil
    if widget then ApplyPoint() end
end

-- Kept for its readers (the Spellbook pane, the spell tooltip): the pool's.
function Clock:Pool()
    return ST.Pool:Pool()
end

--------------------------------------------------------------------------------
-- Wiring: the widget, once the pool has its model (ST.Pool's MD_READY runs
-- first), and a repaint on every tick after the pool's own.
--------------------------------------------------------------------------------
ST:RegisterCallback("MD_READY", function()
    -- T145c: the stored look made v3 once a session (UI/ClockStore.lua; the
    -- dump names what changed) before the first Apply reads it
    ST.ClockStore.MigrateStored()
    if not widget then CreateWidget() end
    UpdateVisibility()
end)

ST:OnTick(function()
    if not ST.Pool.model then return end
    if widget then Paint(GetTime()) end
end)

-- T143 / T145c: the real pool between ticks -- the value only (its range is
-- the tick's and UNIT_MAXPOWER's, so the client's easing is never restarted,
-- review W1) and the game's own mana texts; no words, no layout.
ST:OnUnit("UNIT_POWER_FREQUENT", "player", function()
    if renderer and widget and widget:IsShown() then renderer:PaintPower() end
end)
ST:OnUnit("UNIT_MAXPOWER", "player", function()
    if renderer and widget and widget:IsShown() then renderer:PaintPower(true) end
end)

-- T93 (F5): a new fight may flash again. T144: the steady time starts over.
ST:On("PLAYER_REGEN_DISABLED", function()
    flashedThisFight = false
    ResetSteady()
end)
ST:On("PLAYER_REGEN_ENABLED", function()
    ResetSteady()
end)

-- T145c: a new look (CLOCK_LOOK: the user's change; STYLE_CHANGED: the kit's
-- font may have moved) -- laid out again inside the frame, which is never
-- shown or hidden here. A Width change keeps the clock's centre where it was
-- (the frame's scale is always 1 now).
local function NewLook(repaint)
    look = ST.ClockStore.Look()
    if not renderer then return end
    local w0, h0 = widget:GetWidth(), widget:GetHeight()
    renderer:Apply(look)
    local w1, h1 = look.width, look.height
    if w1 ~= w0 and type(w0) == "number" and type(h0) == "number" then
        ST.db.clock = ST.db.clock or {}
        local p = ST.db.clock.point
        if type(p) ~= "table" or not p[1] then p = DEFAULT_POINT end
        local x1, y1 = ST.ClockBar.KeepCentre(p[1], p[4] or 0, p[5] or 0, 1, 1, w0, h0, w1, h1)
        ST.db.clock.point = { p[1], nil, p[3] or p[1], x1, y1 }
        ApplyPoint()
    end
    if repaint and ST.Pool.model then PaintFace(GetTime()) end
end
ST:RegisterCallback("CLOCK_LOOK", function() NewLook(true) end)
ST:RegisterCallback("STYLE_CHANGED", function() NewLook(false) end)

-- T93: the mover seam under the name both lines provide (UI/Widget.lua's
-- ST.Widget on TBC): ApplyPoint, ResetPosition, Preview, frame.
ST:Provide("ClockWidget", Clock)

-- T93: the two switches by hand -- TBC's rest and tooltip verbs, as
-- subcommands of /st clock (docs/SPEC-next.md 2.5: matched before the verb,
-- so /st clock and /st clock lock are unchanged). T145c: rest is the Rest
-- text's own switch (UI/ClockStore.lua).
ST:AddSubcommand("clock", "rest", function()
    local on = ST.ClockStore.Get("texts.rest.on") == true
    ST.ClockStore.SetText("rest", "on", not on)
    ST:Print("mana clock: rest text " .. ((not on) and "on" or "off"))
end, "rest", "toggle the 'rest' text (time to full if you stop casting)")
ST:AddSubcommand("clock", "clickthrough", function()
    ST.db.clock = ST.db.clock or {}
    ST.db.clock.clickThrough = not ST.db.clock.clickThrough
    ST:Print("mana clock: " .. (ST.db.clock.clickThrough
        and "click-through - it takes no mouse input (no hover, no click) except while you place it"
        or "takes the mouse again - hover for the breakdown, left-click opens the window"))
    if Clock.frame then Clock:Refresh() end
end, "clickthrough", "the clock takes no mouse input")
