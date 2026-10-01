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
local _, MD = ...
local UI = MD.UI

local widget, text, bar, barBack
local shown = false
local forceUntil = 0        -- first-run / unlock preview
local flashedThisFight = false

-- The bar's slot and colours (M6: Forever's 160 x 4; the five-second rule's
-- amber and green as before).
local BAR_W, BAR_H = 160, 4
local FSR_COLOR   = { 1, 0.67, 0.2 }   -- in the five-second rule: amber, filling
local REGEN_COLOR = { 0.2, 1, 0.4 }    -- spirit regen running

-- The physical pixel the panel was last snapped to (UI.px(1, widget)); nil
-- until the first snap. UI/Clock_Forever.lua's rule: the window manager never
-- touches a clock, so the clock re-snaps itself when the scale moves.
local snappedPx

local function Snap()
    local e = UI.px(1, widget)
    local P = UI.PALETTE or {}
    UI.StylizeFrame(widget, P.bg, P.border)
    barBack:SetSize(BAR_W + 2 * e, BAR_H + 2 * e)
    snappedPx = e
end

local function CreateWidget()
    widget = CreateFrame("Frame", "SpellTunerWidget", UIParent, "BackdropTemplate")
    widget:SetSize(180, 30)
    widget:SetFrameStrata("MEDIUM")
    widget:SetMovable(true)
    widget:SetClampedToScreen(true)
    widget:EnableMouse(false)
    widget:RegisterForDrag("LeftButton")

    text = widget:CreateFontString(nil, "OVERLAY", UI.FONT)
    text:SetPoint("TOP", widget, "TOP", 0, -4)
    text:SetTextColor(UI.RGB("text"))
    widget.text = text

    bar = CreateFrame("StatusBar", nil, widget)
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("BOTTOM", widget, "BOTTOM", 0, 5)
    bar:SetStatusBarTexture(UI.whiteTexture)
    bar:SetMinMaxValues(0, 5)
    widget.bar = bar

    -- a texture of the widget: the bar is a child frame and draws above it,
    -- the backdrop beneath it
    barBack = widget:CreateTexture(nil, "ARTWORK")
    barBack:SetColorTexture(0, 0, 0, 1)
    barBack:SetPoint("CENTER", bar, "CENTER", 0, 0)
    widget.barBack = barBack

    Snap()

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
        local hints = { Tip.ClockPair("Left-click", "open the window") }
        if not detail then hints[2] = Tip.ClockPair("Shift", "spend, regen and cooldowns") end
        Tip:Show(self, Tip:Clock(hints, detail), { anchor = "ANCHOR_TOP" })
    end)
    widget:SetScript("OnLeave", function() MD.Tip:Hide() end)
    widget:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and MD.db.locked and MD.ToggleDashboard then
            MD:ToggleDashboard()
        end
    end)

    -- pulse animation (used by MD:Alert and the one-per-fight 30s flash)
    local pulse = widget:CreateAnimationGroup()
    for i, dir in ipairs({ 1, -1, 1, -1 }) do
        local a = pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(dir > 0 and 1 or 0.2)
        a:SetToAlpha(dir > 0 and 0.2 or 1)
        a:SetDuration(0.25)
        a:SetOrder(i)
    end
    widget.pulse = pulse

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
        if UI.px(1, widget) ~= snappedPx then Snap() end -- re-snap after a scale change

        if not MD.db.locked or GetTime() < forceUntil then
            -- T82 (M6): the preview in the accent, over a full accent bar
            text:SetText("SpellTuner - drag me")
            text:SetTextColor(UI.RGB("accent"))
            bar:SetValue(5)
            bar:SetStatusBarColor(UI.RGB("accent"))
            return
        end

        if textAcc >= 0.25 then
            textAcc = 0
            local str = MD:GetDisplayString()
            text:SetText(str ~= "" and str or "|cff999999OOM ...|r")
            text:SetTextColor(UI.RGB("text"))

            -- one attention event per fight: first time TTO crosses below 30s
            if not flashedThisFight then
                local s = MD:GetManaState()
                if s and s.mode == "oom" and s.tto and s.tto < 30 and s.stable then
                    flashedThisFight = true
                    widget.pulse:Play()
                end
            end
        end

        local remaining = MD.Regen:FSRRemaining()
        bar:SetValue(5 - remaining)
        if remaining > 0 then
            bar:SetStatusBarColor(unpack(FSR_COLOR))
        else
            bar:SetStatusBarColor(unpack(REGEN_COLOR))
        end
    end)
end

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
    if widget and shown then widget.pulse:Play() end
end

function MD:ForceWidgetPreview(seconds)
    forceUntil = GetTime() + (seconds or 60)
    MD:UpdateVisibility()
end

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
    if not unlocked and not MD.player.usesMana then
        wantShown = false
    else
        -- the mana is read only when the answer depends on it (locked, out
        -- of combat), as before
        local pct
        if not unlocked and not MD.inCombat then -- T58 (P14, A28): the kernel's flag (Core.lua)
            local mana = UnitPower("player", 0)
            local manaMax = UnitPowerMax("player", 0)
            pct = manaMax > 0 and mana / manaMax or 1
        end
        wantShown = MD.Visibility.Want(pct, shown, MD.inCombat, unlocked)
    end

    if wantShown ~= shown then
        shown = wantShown
        if shown then widget:Show() else widget:Hide() end
    end
end

MD:RegisterCallback("MD_READY", function()
    CreateWidget()
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
