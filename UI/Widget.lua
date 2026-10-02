-- The TBC mana clock: "OOM 1:20 v  rest 2:10" over a five-second-rule bar
-- that fills over 5 s after each mana spend (amber while it fills, green once
-- spirit regen runs). T82 (C4 of docs/PLAN-refactor-ux.md, review U4, mockup
-- M6): one clock look on both lines -- the kit's panel (UI.StylizeFrame in the
-- theme's `bg` with a 1-px edge), the kit's font (UI.FONT), the text centred
-- at the top, and the bar in Forever's 160 x 4 slot with a black backing one
-- pixel wider all round (UI/Clock_Forever.lua's layout, 180 x 30). The bar
-- still means the five-second rule here; on Forever it is the real pool. The
-- unlock preview says "SpellTuner - drag me" in the accent over a full accent
-- bar. All show/hide decisions live in MD:UpdateVisibility() -- nothing else
-- may call Show/Hide on this frame. Hovering shows the clock tooltip
-- (UI/Tip_TBC.lua's Tip:Clock); that requires mouse input on the frame, so
-- db.widgetTooltip turns both off together -- and with them the frame's habit
-- of swallowing clicks in its own rectangle, which is what a clock parked in
-- the middle of the screen wants. The setting is THIS frame's alone: the
-- minimap button and the ElvUI datatexts keep their tooltips.
--
-- T93 (docs/SPEC-next.md 7.1, decisions 14 and 17): the words are drawn by
-- UI/ClockView.lua from MD:GetClockFace() -- the label, the value and the
-- secondary segment at FIXED places (no longer centred), the same bytes as
-- MD:GetDisplayString; the preview is the view's message line, the pulse the
-- view's. A left-click opens the window out of combat only, as on Forever.
-- The mover seam (ApplyPoint, ResetPosition, Preview) is MD.Widget, provided
-- as MD.ClockWidget -- the Forever clock provides the same name.
--
-- T98 (docs/SPEC-next.md 7.2-7.3, decisions 13 and 15): the view owns the
-- layout (db.clockLook: line / compact / bar), the panel (UI.Skin(widget,
-- "clock") -- the style's clock role, the user's overrides) and the bar
-- (built by the view; its source the five-second rule by default, or the
-- real pool, the time to OOM, none; the spark). This file hands it the
-- line's facts and the two sources it reads itself (the pool, the 5SR),
-- rebuilds the look on CLOCK_LOOK / STYLE_CHANGED, and keeps the frame, the
-- drag, the hover and the one visibility owner.
--
-- T115 (clock v2, docs/tasks/T115-clock-bars-frame.md): the mana bar AND the
-- five-second rule on every layout (the view's bars.<layout>: stacked / veil /
-- chip, the order, the strip's thickness, after the rule, the texture); this
-- line reads the pool plain, learns the 2-s regen tick (MD.Regen:RegenTick)
-- and offers the client's two bar textures. The frame's scale per layout
-- (frame.<layout>.scale) is applied here with SetScale, the clock's centre
-- kept (CV.KeepCentre) by rewriting db.pos.
local _, MD = ...
local UI = MD.UI

local widget, view, bar, barBack, strip, stripBack
local shown = false
local forceUntil = 0        -- first-run / unlock preview
local flashedThisFight = false

-- T98 (docs/SPEC-next.md 7.2-7.3): what this line tells the renderer about
-- itself -- the bar's own meaning (the five-second rule, decision 15 (a)), a
-- pool it can read (so a ring may draw it, T104), no modelled pool, its widest
-- label, and its own switches (db.showRest / db.showCooldown: the face
-- already obeys them, the view is told so the two agree). The bar's slot (M6:
-- Forever's 160 x 4) and the five-second rule's amber and green are the
-- view's (UI/ClockView.lua) under the line layout.
-- T116: cd = true -- this line has a cooldown secondary, so the Text tab
-- offers it in a Right slot.
local facts = { line = "tbc", poolPlain = true, model = false, tick = true, textures = true,
    labelSample = "FULL", show = {}, cd = true }
MD.ClockView.lineFacts = facts
local function Facts()
    facts.show.rest = MD.db.showRest ~= false
    facts.show.cd = MD.db.showCooldown ~= false
    return facts
end

-- The bars' sources this line draws itself: the real pool (read plain here,
-- drawn as a fraction), the seconds left in the five-second rule, the spend
-- that started it (the chip's swipe) and the last regen tick (the strip's
-- tick mark).
local draw = {
    pool = function(b)
        local max = UnitPowerMax("player", 0)
        local cur = UnitPower("player", 0)
        b:SetMinMaxValues(0, 1)
        if type(max) == "number" and max > 0 and type(cur) == "number" then
            b:SetValue(math.max(0, math.min(1, cur / max)))
        else
            b:SetValue(0)
        end
    end,
    fsr = function() return MD.Regen and MD.Regen:FSRRemaining() or nil end,
    spend = function()
        local e = MD.Regen and MD.Regen.fsrEnd
        if type(e) == "number" and e > 0 then return e - 5 end
        return nil
    end,
    tick = function(now)
        if MD.Regen and MD.Regen.RegenTick then return MD.Regen:RegenTick(now) end
        return nil
    end,
}

-- T93 / T98: the resolved look (UI/ClockView.lua: the layout's defaults, the
-- style's clock role, the user's overrides), made again on CLOCK_LOOK and
-- STYLE_CHANGED; the switches refreshed in place at each paint (4 a second).
local look
local function Look()
    local f = Facts()
    if not look then look = MD.ClockView.Look(f) end
    look.show.rest, look.show.cd = f.show.rest, f.show.cd
    return look
end

local function CreateWidget()
    widget = CreateFrame("Frame", "SpellTunerWidget", UIParent, "BackdropTemplate")
    widget:SetSize(180, 32)
    widget:SetFrameStrata("MEDIUM")
    widget:SetMovable(true)
    widget:SetClampedToScreen(true)
    widget:EnableMouse(false)
    widget:RegisterForDrag("LeftButton")

    -- T93: the words, in three fixed segments (UI/ClockView.lua); T98: and
    -- the layout, the panel (UI.Skin(widget, "clock")) and the bar with its
    -- black backing, the view's -- 160 x 4 under the line layout, the
    -- five-second rule by default
    view = MD.ClockView.Build(widget, Look(), draw)
    widget.view = view
    bar, barBack, strip, stripBack = view.bar, view.barBack, view.strip, view.stripBack
    widget.bar = bar
    widget.barBack = barBack
    widget.strip = strip
    widget.stripBack = stripBack
    widget:SetScale(view:Scale())

    widget:SetScript("OnDragStart", function(self)
        -- draggable when unlocked OR during the first-run/unlock preview
        if not MD.db.locked or GetTime() < forceUntil then self:StartMoving() end
    end)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        MD.db.pos = { point, relPoint, x, y }
    end)

    -- Hover tooltip (Tip:Clock, the minimap button's words) and a left-click
    -- shortcut to the window. This needs mouse input on the widget, which
    -- also means it swallows clicks in its own 180x30 rectangle -- hence the
    -- setting. T82: the hints are label / value pairs, Shift the detail key.
    widget:SetScript("OnEnter", function(self)
        if MD.db.widgetTooltip == false then return end
        local Tip = MD.Tip
        local detail = Tip.ClockDetail()
        local hints = { Tip.ClockPair("Left-click", "open the window (out of combat)") }
        if not detail then hints[2] = Tip.ClockPair("Shift", "spend, regen and cooldowns") end
        Tip:Show(self, Tip:Clock(hints, detail), { anchor = "ANCHOR_TOP" })
    end)
    widget:SetScript("OnLeave", function() MD.Tip:Hide() end)
    -- T93 (decision 17): out of combat only -- the window hides in combat (C1)
    -- and the clock is up in every fight, where a stray click would put the
    -- window over the party (the Forever clock's rule, T70)
    widget:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and MD.db.locked and not MD.inCombat and MD.ToggleDashboard then
            MD:ToggleDashboard()
        end
    end)

    -- pulse animation (used by MD:Alert and the one-per-fight 30s flash):
    -- the view's since T93
    widget.pulse = view.pulse

    widget:Hide()
    MD:ApplyWidgetPosition()

    -- Rendering only; the model is event/tick driven elsewhere. The text is
    -- rebuilt 4x/s (the latch in TTO.lua means it can only change every 1s
    -- anyway); the bar keeps a 10 Hz refresh so it fills smoothly.
    local acc, textAcc = 0, 1
    widget:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        textAcc = textAcc + acc
        acc = 0
        if UI.px(1, widget) ~= view.snappedPx then view:Snap() end -- re-snap after a scale change

        if not MD.db.locked or GetTime() < forceUntil then
            -- T82 (M6): the preview in the accent, over a full accent bar
            view:Message("SpellTuner - drag me", UI.RGB("accent"))
            view:FillBar(UI.RGB("accent"))
            return
        end

        if textAcc >= 0.25 then
            textAcc = 0
            -- T93: the face, drawn in segments; no face yet draws "OOM ..."
            view:Paint(MD:GetClockFace(), Look())

            -- one attention event per fight: first time TTO crosses below 30s
            if not flashedThisFight then
                local s = MD:GetManaState()
                if s and s.mode == "oom" and s.tto and s.tto < 30 and s.stable then
                    flashedThisFight = true
                    view:Pulse()
                end
            end
        end

        -- T115: the mana bar and the five-second rule (amber while it runs,
        -- green once spirit regen runs; the view's step moves the rule every
        -- frame between these paints)
        view:PaintBar(GetTime())
    end)
end

-- T98: a new look (a layout, an override: CLOCK_LOOK; a style: STYLE_CHANGED)
-- -- the view rebuilt inside the frame, never shown or hidden here. After a
-- CLOCK_LOOK (the user's change) the words and the bar are drawn at once;
-- after a style the next paint draws them (a style changes paint only).
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
        local pos = MD.db.pos
        if type(pos) ~= "table" then pos = { "CENTER", "CENTER", 0, -140 } end
        if #pos ~= 4 then pos = { pos[1], pos[1], pos[2], pos[3] } end
        local x1, y1 = MD.ClockView.KeepCentre(pos[1], pos[3], pos[4], s0, s1, w0, h0,
            widget:GetWidth(), widget:GetHeight())
        MD.db.pos = { pos[1], pos[2], x1, y1 }
        widget:SetScale(s1)
        MD:ApplyWidgetPosition()
    end
    if not repaint then return end
    if not MD.db.locked or GetTime() < forceUntil then
        view:Message("SpellTuner - drag me", UI.RGB("accent"))
        view:FillBar(UI.RGB("accent"))
    else
        view:Paint(MD:GetClockFace(), l)
        view:PaintBar(GetTime())
    end
end
MD:RegisterCallback("CLOCK_LOOK", function() NewLook(true) end)
MD:RegisterCallback("STYLE_CHANGED", function() NewLook(false) end)

function MD:ApplyWidgetPosition()
    if not widget then return end
    widget:ClearAllPoints()
    local pos = MD.db.pos
    if #pos == 4 then
        widget:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else -- legacy 3-element form
        widget:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    end
end

function MD:PulseWidget()
    if widget and shown then view:Pulse() end
end

function MD:ForceWidgetPreview(seconds)
    forceUntil = GetTime() + (seconds or 60)
    MD:UpdateVisibility()
end

--------------------------------------------------------------------------------
-- T93 (docs/SPEC-next.md 6.3, the mover seam): what a mover (EllesmereUI's
-- /unlock, T97) or Settings -> Clock (T102) calls on either line's clock,
-- under one name, MD.ClockWidget -- here this widget, on Forever MD.Clock.
--   ApplyPoint()        put the frame at the stored place (db.pos)
--   ResetPosition()     the default place (MD.DEFAULTS.pos), stored and applied
--   Preview(seconds)    the clock up and draggable for `seconds` (60), 0 ends it
--   frame               the frame (nil until MD_READY)
-- None of them shows or hides the frame: MD:UpdateVisibility does.
--------------------------------------------------------------------------------
MD.Widget = MD.Widget or {}
local Widget = MD.Widget

function Widget:ApplyPoint()
    MD:ApplyWidgetPosition()
end

function Widget:ResetPosition()
    local d = MD.DEFAULTS and MD.DEFAULTS.pos
    if type(d) ~= "table" then return end
    MD.db.pos = { d[1], d[2], d[3], d[4] }
    MD:ApplyWidgetPosition()
end

function Widget:Preview(seconds)
    MD:ForceWidgetPreview(tonumber(seconds) or 60)
end

MD:Provide("ClockWidget", Widget)

--------------------------------------------------------------------------------
-- Visibility: the single owner. In combat: always show. Out of combat:
-- hysteresis (show below 90% mana, hide above 95%) so it never flickers --
-- the rule itself is UI/Visibility.lua's MD.Visibility.Want (T68, P24), the
-- one the Forever clock asks too; this function keeps the Show/Hide.
--------------------------------------------------------------------------------
function MD:UpdateVisibility()
    if not widget then return end

    local unlocked = not MD.db.locked or GetTime() < forceUntil
    local wantShown
    if unlocked then
        widget:EnableMouse(true)
    else
        widget:EnableMouse(MD.db.widgetTooltip ~= false)
    end
    -- T93: "no mana pool, no clock" is the shared rule's manaUsersOnly now
    -- (UI/Visibility.lua), the same answer as the gate that stood here. The
    -- mana is read only when the answer depends on it (locked, out of combat,
    -- a mana user), as before.
    local usesMana = MD.player.usesMana
    local pct
    if not unlocked and not MD.inCombat and usesMana then -- T58 (P14, A28): the kernel's flag (Core.lua)
        local mana = UnitPower("player", 0)
        local manaMax = UnitPowerMax("player", 0)
        pct = manaMax > 0 and mana / manaMax or 1
    end
    wantShown = MD.Visibility.Want(pct, shown, MD.inCombat, unlocked, nil, usesMana and true or false)

    if wantShown ~= shown then
        shown = wantShown
        if shown then widget:Show() else widget:Hide() end
    end
end

MD:RegisterCallback("MD_READY", function()
    CreateWidget()
    Widget.frame = widget
    Widget.view = view   -- T98: the renderer (a preview or a suite reads its layout)
    Widget.facts = facts -- T98: this line's bar facts (CV.BarsOK, CV.Look)
    MD:UpdateVisibility()
end)

MD:OnTick(function()
    MD:UpdateVisibility()
end)

MD:On("PLAYER_REGEN_DISABLED", function()
    flashedThisFight = false
    MD:UpdateVisibility()
end)

MD:On("PLAYER_REGEN_ENABLED", function()
    MD:UpdateVisibility()
end)
