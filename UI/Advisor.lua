-- Advisor: three push-channel features that fire at real decision moments.
--   1. Mana-cooldown / potion timing — alert the first moment the mana deficit
--      exceeds what the source restores, so none of it is wasted. The sources
--      and their values come from Engine/ManaCooldowns.lua.
--   2. Gear-change rank toast — when +healing shifts a spell's efficient rank.
--   3. Drink reminder — out of combat, low mana, not drinking.
local _, ST = ...

-- Every mana source (Innervate today, per-class cooldowns later, plus carried
-- potions) and what it is worth right now comes from Engine/ManaCooldowns.lua,
-- so the advisor and the OOM clock can never quote different numbers for the
-- same decision.
local fired = {}

ST:OnTick(function()
    -- T58 (P14, review A28): the kernel's combat flag (Core.lua), not a poll.
    if not ST.db or not ST.inCombat or not ST.player.usesMana then return end
    if not ST.ManaCooldowns then return end
    local deficit = UnitPowerMax("player", 0) - UnitPower("player", 0)

    local sources = ST.ManaCooldowns:All() -- richest first
    for i, src in ipairs(sources) do
        -- Fire the first moment the deficit swallows the whole thing: any
        -- earlier and part of the restore is wasted.
        if src.ready and src.delta > 500 and not fired[src.key] and deficit >= src.delta then
            fired[src.key] = true
            -- The clock advertises the RICHEST ready source; this alert fires
            -- for the one that fits the deficit NOW. On the first dungeon log
            -- those disagreed on screen (clock: Innervate, alert: potion), so
            -- say why the cheaper one is being called first.
            local held
            for j = 1, i - 1 do
                local richer = sources[j]
                if richer.ready and not fired[richer.key] then held = richer break end
            end
            local msg = string.format("%s now - you're down %d mana (worth ~%d), none of it will be wasted.",
                src.name, deficit, src.delta)
            if held then
                msg = msg .. string.format(" %s is ready too but worth ~%d: hold it until you're down that far.",
                    held.name, held.delta)
            end
            ST:Alert(msg)
        end
    end
end)

ST:On("PLAYER_REGEN_ENABLED", function()
    wipe(fired)
end)

--------------------------------------------------------------------------------
-- Gear-change rank toast
--------------------------------------------------------------------------------
local toastPending = false

-- T99 (docs/SPEC-next.md 4.4): the rank toast is the class profile's
-- `advisor` capability (ST.ClassProfile:Can), the druid's on this line.
local function CheckRankShift()
    toastPending = false
    if not ST.ClassProfile:Can("advisor") or not ST.cdb then return end
    if ST.sim and next(ST.sim) then return end -- dashboard simulation active: not real gear
    -- Suggestions depend on the form too (Tree of Life cost + aura), so a
    -- stored snapshot from the other form is replaced, never compared.
    local current = ST.RankMath:SuggestedRanks()
    local form = ST:InTreeForm() and "tree" or "caster"
    local stored = ST.cdb.suggestedRanks
    if stored and stored.form == form and stored.ranks then
        for family, rank in pairs(current) do
            if stored.ranks[family] and stored.ranks[family] ~= rank then
                local label = ST.SpellData.families[family].label
                ST:Alert(string.format("gear change - %s R%d is now your efficient rank (was R%d). Rebind?",
                    label, rank, stored.ranks[family]))
            end
        end
    end
    ST.cdb.suggestedRanks = { form = form, ranks = current }
end

ST:On("PLAYER_EQUIPMENT_CHANGED", function()
    if toastPending or not ST.db then return end
    toastPending = true
    C_Timer.After(2, CheckRankShift) -- debounce a full outfit swap into one check
end)

ST:RegisterCallback("MD_READY", function()
    C_Timer.After(5, function()
        if ST.ClassProfile:Can("advisor") and ST.cdb
            and not (ST.cdb.suggestedRanks and ST.cdb.suggestedRanks.ranks) then
            ST.cdb.suggestedRanks = { form = ST:InTreeForm() and "tree" or "caster",
                                      ranks = ST.RankMath:SuggestedRanks() }
        end
    end)
end)

--------------------------------------------------------------------------------
-- Drink reminder: OOC, mana < 70%, stationary ~5s, not drinking, at most once
-- per rest period (re-arms when mana passes 90% or combat starts).
--------------------------------------------------------------------------------
local DRINK_NAMES = { ["Drink"] = true, ["Refreshment"] = true, ["Food & Drink"] = true }
local stillSince = nil
local drinkArmed = true

local function IsDrinking()
    if not UnitBuff then return false end
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if DRINK_NAMES[name] then return true end
    end
    return false
end

ST:OnTick(function(dt)
    if not ST.db or not ST.db.drinkReminder or not ST.player.usesMana then return end
    if ST.inCombat then -- T58 (P14, A28): the kernel's flag
        stillSince = nil
        drinkArmed = true
        return
    end
    local manaMax = UnitPowerMax("player", 0)
    local pct = manaMax > 0 and UnitPower("player", 0) / manaMax or 1
    if pct > 0.90 then drinkArmed = true end
    if not drinkArmed or pct >= 0.70 or IsDrinking() then
        stillSince = nil
        return
    end
    local speed = GetUnitSpeed and GetUnitSpeed("player") or 0
    if speed and speed > 0 then
        stillSince = nil
        return
    end
    stillSince = stillSince or GetTime()
    if GetTime() - stillSince >= 5 then
        drinkArmed = false
        stillSince = nil
        -- "Drink." answers nothing; "2 more pulls, or 4 after a drink" is
        -- the decision actually being made between pulls.
        local line = ST.PullBudget and ST.PullBudget:Line()
        ST:Alert(line and ("Drink? " .. line) or "Drink.")
    end
end)
