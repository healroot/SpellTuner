-- The TBC mana clock. All show/hide decisions live in ST:UpdateVisibility() --
-- nothing else may call Show/Hide on this frame. Hovering shows the clock
-- tooltip (UI/Tip_TBC.lua's Tip:Clock); that requires mouse input on the
-- frame, so db.widgetTooltip turns both off together -- and with them the
-- frame's habit of swallowing clicks in its own rectangle, which is what a
-- clock parked in the middle of the screen wants. The setting is THIS frame's
-- alone: the minimap button and the ElvUI datatexts keep their tooltips.
--
-- T93 (docs/SPEC-next.md 7.1, decisions 14 and 17): the preview is the
-- renderer's message line, the pulse the renderer's. A left-click opens the
-- window out of combat only, as on Forever. The mover seam (ApplyPoint,
-- ResetPosition, Preview) is ST.Widget, provided as ST.ClockWidget -- the
-- Forever clock provides the same name.
--
-- T145c (docs/SPEC-clock-v3.md 2.5; docs/tasks/T145c-clock-bar.md): the same
-- bar as Forever's, drawn by UI/ClockBar.lua (it replaces UI/ClockView.lua):
-- the face is ST:GetClockFace() (TBC keeps its own sigma precision and latch,
-- Engine/TTO.lua, so no steady latch here and no quiet-pool signal: the pool
-- is read plain and the face's pct says FULL), its words ST.ClockWords.Build,
-- the pool and its mana texts through the TBC adapter (ST.API.DrawUnitPower /
-- DrawUnitPowerMax / DrawPowerText, plain reads), the moving line from
-- ST.Regen.fsrEnd. The look is UI/ClockStore.lua's, migrated once at MD_READY.
local _, ST = ...
local UI = ST.UI

local widget, renderer
local shown = false
local forceUntil = 0        -- first-run / unlock preview
local flashedThisFight = false

-- This line's sources for the renderer: the pool and its texts (plain reads
-- through the adapter) and the five-second rule's end (ST.Regen's own clock).
local draw = {
    pool = function(b) ST.API.DrawUnitPower(b, "player", 0) end,
    poolMax = function(b) ST.API.DrawUnitPowerMax(b, "player", 0) end,
    fsrEnd = function()
        local e = ST.Regen and ST.Regen.fsrEnd
        if type(e) == "number" and e > 0 then return e end
        return nil
    end,
    powerText = function(fs, kind)
        if type(ST.API.DrawPowerText) ~= "function" then return false end
        return ST.API.DrawPowerText(fs, "player", 0, kind) == true
    end,
}

-- The look drawn (a validated v3 copy), and the words, one table reused.
local look
local words = {}

local PaintWidget -- below CreateWidget, which its OnUpdate calls

local function Unlocked()
    return not ST.db.locked or GetTime() < forceUntil
end

local function CreateWidget()
    widget = CreateFrame("Frame", "SpellTunerWidget", UIParent, "BackdropTemplate")
    widget:SetSize(200, 8)
    widget:SetFrameStrata("MEDIUM")
    widget:SetMovable(true)
    widget:SetClampedToScreen(true)
    widget:EnableMouse(false)
    widget:RegisterForDrag("LeftButton")

    -- T145c: the renderer, laid out once per look
    renderer = ST.ClockBar.New(widget, draw)
    widget.renderer = renderer
    look = ST.ClockStore.Look()
    renderer:Apply(look)

    widget:SetScript("OnDragStart", function(self)
        -- draggable when unlocked OR during the first-run/unlock preview
        if Unlocked() then self:StartMoving() end
    end)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ST.db.pos = { point, relPoint, x, y }
    end)

    -- Hover tooltip (Tip:Clock, the minimap button's words) and a left-click
    -- shortcut to the window. This needs mouse input on the widget, which
    -- also means it swallows clicks in its own rectangle -- hence the
    -- setting. T82: the hints are label / value pairs, Shift the detail key.
    widget:SetScript("OnEnter", function(self)
        if ST.db.widgetTooltip == false then return end
        local Tip = ST.Tip
        local detail = Tip.ClockDetail()
        local hints = { Tip.ClockPair("Left-click", "open the window (out of combat)") }
        if not detail then hints[2] = Tip.ClockPair("Shift", "spend, regen and cooldowns") end
        Tip:Show(self, Tip:Clock(hints, detail), { anchor = "ANCHOR_TOP" })
    end)
    widget:SetScript("OnLeave", function() ST.Tip:Hide() end)
    -- T93 (decision 17): out of combat only -- the window hides in combat (C1)
    -- and the clock is up in every fight, where a stray click would put the
    -- window over the party (the Forever clock's rule, T70)
    widget:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and ST.db.locked and not ST.inCombat and ST.ToggleDashboard then
            ST:ToggleDashboard()
        end
    end)

    -- pulse animation (used by ST:Alert and the one-per-fight 30s flash):
    -- the renderer's
    widget.pulse = renderer.pulse

    widget:Hide()
    ST:ApplyWidgetPosition()

    -- Rendering only; the model is event/tick driven elsewhere. The words
    -- and the pool 4x/s (the latch in TTO.lua means the time can only change
    -- every 1s anyway); the moving line is the renderer's own driver.
    local acc = 1
    widget:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.25 then return end
        acc = 0
        PaintWidget(GetTime())
    end)
end

-- PaintWidget(now): one paint -- the preview's line, or the face's words;
-- then the pool and its texts. Text and colour only (T145c, P5).
PaintWidget = function(now)
    if not renderer then return end
    renderer:Snap() -- re-snap after a scale change, else a compare
    if Unlocked() then
        -- T82 (M6): the preview in the accent
        renderer:Message("SpellTuner - drag me", UI.RGB("accent"))
        renderer:PaintPower(true)
        return
    end
    renderer:Message(nil)
    ST.ClockWords.Build(ST:GetClockFace(), look, nil, now, words, false)
    renderer:Paint(words)
    renderer:PaintPower(true)

    -- one attention event per fight: first time TTO crosses below 30s
    if not flashedThisFight then
        local s = ST:GetManaState()
        if s and s.mode == "oom" and s.tto and s.tto < 30 and s.stable then
            flashedThisFight = true
            renderer:Pulse()
        end
    end
end

-- T145c: a new look (CLOCK_LOOK: the user's change; STYLE_CHANGED: the kit's
-- font may have moved) -- laid out again inside the frame, never shown or
-- hidden here. A Width change keeps the clock's centre where it was.
local function NewLook(repaint)
    look = ST.ClockStore.Look()
    if not renderer then return end
    local w0, h0 = widget:GetWidth(), widget:GetHeight()
    renderer:Apply(look)
    local w1, h1 = look.width, look.height
    if w1 ~= w0 and type(w0) == "number" and type(h0) == "number" then
        local pos = ST.db.pos
        if type(pos) ~= "table" then pos = { "CENTER", "CENTER", 0, -140 } end
        if #pos ~= 4 then pos = { pos[1], pos[1], pos[2], pos[3] } end
        local x1, y1 = ST.ClockBar.KeepCentre(pos[1], pos[3], pos[4], 1, 1, w0, h0, w1, h1)
        ST.db.pos = { pos[1], pos[2], x1, y1 }
        ST:ApplyWidgetPosition()
    end
    if repaint then PaintWidget(GetTime()) end
end
ST:RegisterCallback("CLOCK_LOOK", function() NewLook(true) end)
ST:RegisterCallback("STYLE_CHANGED", function() NewLook(false) end)

function ST:ApplyWidgetPosition()
    if not widget then return end
    widget:ClearAllPoints()
    local pos = ST.db.pos
    if #pos == 4 then
        widget:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else -- legacy 3-element form
        widget:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    end
end

function ST:PulseWidget()
    if widget and shown then renderer:Pulse() end
end

function ST:ForceWidgetPreview(seconds)
    forceUntil = GetTime() + (seconds or 60)
    ST:UpdateVisibility()
end

--------------------------------------------------------------------------------
-- T93 (docs/SPEC-next.md 6.3, the mover seam): what a mover (EllesmereUI's
-- /unlock, T97) or Settings -> Clock (T102) calls on either line's clock,
-- under one name, ST.ClockWidget -- here this widget, on Forever ST.Clock.
--   ApplyPoint()        put the frame at the stored place (db.pos)
--   ResetPosition()     the default place (ST.DEFAULTS.pos), stored and applied
--   Preview(seconds)    the clock up and draggable for `seconds` (60), 0 ends it
--   frame               the frame (nil until MD_READY)
--   renderer            the renderer (UI/ClockBar.lua), T145c
-- None of them shows or hides the frame: ST:UpdateVisibility does.
--------------------------------------------------------------------------------
ST.Widget = ST.Widget or {}
local Widget = ST.Widget

function Widget:ApplyPoint()
    ST:ApplyWidgetPosition()
end

function Widget:ResetPosition()
    local d = ST.DEFAULTS and ST.DEFAULTS.pos
    if type(d) ~= "table" then return end
    ST.db.pos = { d[1], d[2], d[3], d[4] }
    ST:ApplyWidgetPosition()
end

function Widget:Preview(seconds)
    ST:ForceWidgetPreview(tonumber(seconds) or 60)
end

-- One paint now (the frame's OnUpdate calls it 4x/s; a suite may too).
function Widget:Paint(now)
    PaintWidget(now or GetTime())
end

ST:Provide("ClockWidget", Widget)

--------------------------------------------------------------------------------
-- Visibility: the single owner. In combat: always show. Out of combat:
-- hysteresis (show below 90% mana, hide above 95%) so it never flickers --
-- the rule itself is UI/Visibility.lua's ST.Visibility.Want (T68, P24), the
-- one the Forever clock asks too; this function keeps the Show/Hide.
--------------------------------------------------------------------------------
function ST:UpdateVisibility()
    if not widget then return end

    local unlocked = Unlocked()
    local wantShown
    if unlocked then
        widget:EnableMouse(true)
    else
        widget:EnableMouse(ST.db.widgetTooltip ~= false)
    end
    -- T93: "no mana pool, no clock" is the shared rule's manaUsersOnly now
    -- (UI/Visibility.lua), the same answer as the gate that stood here. The
    -- mana is read only when the answer depends on it (locked, out of combat,
    -- a mana user), as before.
    local usesMana = ST.player.usesMana
    local pct
    if not unlocked and not ST.inCombat and usesMana then -- T58 (P14, A28): the kernel's flag (Core.lua)
        local mana = UnitPower("player", 0)
        local manaMax = UnitPowerMax("player", 0)
        pct = manaMax > 0 and mana / manaMax or 1
    end
    wantShown = ST.Visibility.Want(pct, shown, ST.inCombat, unlocked, nil, usesMana and true or false)

    if wantShown ~= shown then
        shown = wantShown
        if shown then widget:Show() else widget:Hide() end
    end
end

ST:RegisterCallback("MD_READY", function()
    -- T145c: the stored look made v3 once a session (UI/ClockStore.lua)
    ST.ClockStore.MigrateStored()
    CreateWidget()
    Widget.frame = widget
    Widget.renderer = renderer
    ST:UpdateVisibility()
end)

ST:OnTick(function()
    ST:UpdateVisibility()
end)

ST:On("PLAYER_REGEN_DISABLED", function()
    flashedThisFight = false
    ST:UpdateVisibility()
end)

ST:On("PLAYER_REGEN_ENABLED", function()
    ST:UpdateVisibility()
end)
