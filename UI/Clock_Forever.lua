-- T11 (docs/tasks/T11-clock.md, M2): the Forever counterpart of the TBC mana
-- clock -- a small movable widget over Engine/ManaModel.lua's modelled pool,
-- because current mana is secret always on this client (Facts). Reaches the
-- client only through MD.API; the widget toolkit (CreateFrame, GameTooltip,
-- UI/Style.lua) is not a client call (CLAUDE.md). Forever only.
local _, MD = ...
local UI = MD.UI

MD.Clock = MD.Clock or {}
local Clock = MD.Clock

local model
local widget, text, bar
local inCombat = false

-- T11b (docs/tasks/T11b-clock-modes.md): out-of-combat hysteresis state --
-- TBC's UI/Widget.lua MD:UpdateVisibility (lines 144-173) shows below 90% of
-- max and, once shown, keeps the clock up until above 95%, so it does not
-- flicker in the band a plain threshold would. This is the one flag that
-- remembers which side of the band the clock is currently on.
local shown = false

--------------------------------------------------------------------------------
-- Cost lookup: MD.Book's own entry.cost.amount (a family's known rank, or a
-- standalone ReadSpell for anything else the book does not list -- both
-- already reach the client only through MD.API). A percentage-of-base-mana
-- cost, or nothing readable at all, is never priced -- the caller counts it
-- as unpriced instead of guessing an amount.
--------------------------------------------------------------------------------
local function CostFor(id)
    if not MD.Book then return nil end
    local book = MD.Book:Get()
    local entry = book and book.spells[id]
    if not entry then
        local ok
        ok, entry = pcall(MD.Book.ReadSpell, MD.Book, id)
        if not ok then entry = nil end
    end
    if not entry then return nil end
    if entry.costState == "free" then return 0 end
    if entry.cost and type(entry.cost.amount) == "number" then return entry.cost.amount end
    return nil
end

--------------------------------------------------------------------------------
-- Visibility: one owner. Hidden when db.clock.shown is false; else shown in
-- combat, and out of combat with TBC's own hysteresis (UI/Widget.lua
-- MD:UpdateVisibility lines 144-173): appears once the modelled pool drops
-- under 90% of max, and once shown stays up until it is back over 95% --
-- never the plain "below 95%" threshold, which redrew at 94.x% (T11b Facts,
-- the author's `~refill 0:05` sighting).
--------------------------------------------------------------------------------
local function UpdateVisibility()
    if not widget then return end
    if not (MD.db and MD.db.clock and MD.db.clock.shown) then
        widget:Hide()
        shown = false
        return
    end
    if inCombat then
        widget:Show()
        shown = true
        return
    end
    if model.max and model.max > 0 then
        local pct = model.mana / model.max
        if shown then
            if pct > 0.95 then shown = false end
        else
            if pct < 0.90 then shown = true end
        end
    else
        shown = false
    end
    if shown then widget:Show() else widget:Hide() end
end

--------------------------------------------------------------------------------
-- Hover
--------------------------------------------------------------------------------
local function ShowHover(self)
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

    if inCombat then
        local state = model:Project(GetTime())
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

local function CreateWidget()
    widget = CreateFrame("Frame", "SpellTunerClock", UIParent, "BackdropTemplate")
    widget:SetSize(180, 30)
    widget:SetFrameStrata("MEDIUM")
    UI.StylizeFrame(widget)
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

    ApplyPoint()
    Clock.frame = widget
end

--------------------------------------------------------------------------------
-- Paint: rendering only, tick-driven -- the model is event/tick driven above.
--------------------------------------------------------------------------------
local function Paint(now)
    local state = model:Project(now)
    text:SetText(MD.ManaModel.Text(state))
    MD.API.DrawUnitPower(bar, "player", 0)
    UpdateVisibility()
end

-- Repaints without waiting for the next tick -- used by settings/commands
-- that just changed db.clock, and by the test harness.
function Clock:Refresh()
    if not model then return end
    Paint(GetTime())
end

function Clock:Pool()
    if not model then return {} end
    return { max = model.max, mana = model.mana, regenCasting = model.casting }
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
MD:RegisterCallback("MD_READY", function()
    model = MD.ManaModel.New()
    Clock.model = model

    local max = MD.API.UnitPowerMax("player", 0)
    if type(max) == "number" then model:SetMax(max) end

    local base, casting = MD.API.ManaRegen()
    if type(base) == "number" and type(casting) == "number" then
        model:SetRegen(base, casting)
    end

    model:Anchor(GetTime(), model.max, "assumed full at login")

    -- Review R36/R37: a login or /reload in the middle of a fight gets no
    -- PLAYER_REGEN_DISABLED (it already fired), so the combat state is read
    -- here once, through the adapter -- anything but a plain true (false,
    -- absent, secret) leaves the clock out of combat, as before.
    inCombat = (MD.API.UnitAffectingCombat("player") == true)
    if inCombat then model:StartFight(GetTime()) end

    if not widget then CreateWidget() end
    UpdateVisibility()
end)

MD:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID, spellID)
    if not model then return end
    -- Facts/T9 Review: IsSecret before the comparison, every time -- type()
    -- of a secret does not raise and may answer the underlying type.
    if MD.API.IsSecret(unit) or unit ~= "player" then return end

    local now = GetTime()
    if not MD.API.IsSecret(spellID) and type(spellID) == "number" then
        local cost = CostFor(spellID)
        if cost ~= nil then
            if cost > 0 then model:Spend(cost, now) end -- a free cast spends nothing and restarts no five-second rule
            return
        end
    end
    model:Unpriced(now)
end)

MD:On("PLAYER_REGEN_DISABLED", function()
    inCombat = true
    if model then model:StartFight(GetTime()) end
end)

MD:On("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    if model then model:EndFight(GetTime()) end
end)

MD:OnTick(function()
    if not model then return end
    local now = GetTime()

    local max = MD.API.UnitPowerMax("player", 0)
    if type(max) == "number" then model:SetMax(max) end

    if not inCombat then
        local base, casting = MD.API.ManaRegen()
        if type(base) == "number" and type(casting) == "number" then
            model:SetRegen(base, casting)
        end
    end

    model:Advance(now)

    -- Out of combat, once regen alone (at the base rate, the faster of the
    -- two -- Facts) would have had time to refill the whole pool from empty,
    -- the real pool is assumed full even if the model's own integral (which
    -- spent part of that time at the slower casting rate, Engine/ManaModel.lua
    -- Advance) has not quite caught up -- the drift the plan accepts
    -- (FOREVER-PLAN.md sec2.5): drinks, potions, other heals are invisible to
    -- this model, so "assume full after long enough" is the only correction
    -- it gets.
    if not inCombat and model.max and model.max > 0 and model.base and model.base > 0
       and (now - model.lastSpend) >= (model.max / model.base) and model.mana < model.max then
        model:Anchor(now, model.max, "regen had time to fill it")
    end

    if widget then Paint(now) end
end)
