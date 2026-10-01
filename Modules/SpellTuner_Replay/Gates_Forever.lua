-- T14 (docs/tasks/T14-gates-v3.md): the eight gates re-founded on what
-- Forever can know. Health is scored against the reconstruction (T13d
-- `sc.recordedHp`); foreign healing and the model's calibration are checked
-- against the damage meter's totals for the fight (T13's `rec.meter`); mana
-- is a consistency check between the engine's mana model and the client's own
-- modelled pool, never the real (secret) pool; the enemy-cast and threat
-- inputs are dropped (Facts, plan Sec2.3). Pure: no client call, no mutation
-- of `rec`. `Engine/SimModel.lua`'s own v2 road still runs byte for byte on a
-- v2 (TBC) recording; this file registers the v3 road in SM.validators (T66,
-- P22, review A18: it used to wrap SM.Validate) and reads the gates both
-- roads share (mana, death, spend) and the arithmetic (SM.Threshold,
-- SM.MeanMax) from there.
local _, MD = ...
local SM = MD.SimModel

-- The v3 stream's own kinds, published once by the Recorder module's
-- Stream_Forever.lua (T66), which this module depends on.
local STREAM = MD.StreamV3
local V3 = STREAM.K
local Threshold, MeanMax = SM.Threshold, SM.MeanMax

-- T71 (P27, review A31): each gate's `short` (SM.NewValidation's seventh
-- argument), the words a Review cell shows; the three meter gates share this
-- one when there is no meter reading.
local NO_METER = "no meter reading"

-- Two new thresholds, only if some other file has not already added them
-- (Files table). T64 (P20, review A3): their defaults are registered here,
-- once, and the gate's `default` reads them back (Engine/SimModel.lua's
-- SM.Gate); MD:Setting answers the player's value, else this default.
MD:RegisterDefaults({
    simGateMeter = 0.10,   -- gate 6: the replay's own healing against the meter's own total
    simGateAttrib = 0.10,  -- gate 8: the paired own heals against the meter's own total
})
if not SM.GATES.meterOwn then
    SM.GATES.meterOwn = SM.Gate("simGateMeter",
        "lead's first threshold (2026-09-28); the meter counts effective healing; re-measured in M5")
end
if not SM.GATES.attributed then
    SM.GATES.attributed = SM.Gate("simGateAttrib",
        "planner ruling 2 (2026-09-28); lead's first threshold; re-measured on the author's first Forever pulls")
end

-- Whether a UNIT_COMBAT HEAL amount is gross or effective is still open
-- (docs/TESTING.md Sec38.2 step 4, Q3). "unknown" until the author answers it;
-- gate 8 checks only the short side until this becomes "effective".
SM.HEAL_AMOUNT = "unknown"

--------------------------------------------------------------------------------
-- SM.ValidateV3(rec, kit) -- the eight gates on a v3 stream (SM.validators[3]).
--------------------------------------------------------------------------------
function SM.ValidateV3(rec, kit)
    if not rec then return nil end
    kit = kit or MD.RankMath:SpellKit()
    local sc = SM.ScenarioFromRecording(rec, kit)
    local r = SM:Run(sc, nil, { critMode = "ev" })

    -- energize 0, never assumed: a v3 scenario carries both (ScenarioV3).
    local out, Gate = SM.NewValidation(rec, sc)

    ----------------------------------------------------------------------------
    -- 1 + 2: mana curve. The recorded mana IS the clock's own model
    -- (T13, `manaModelled = true`), so this compares the engine's mana model
    -- with the live mana model -- a consistency check, not a check against the
    -- real pool, which is secret (Facts, Planner ruling 3). Thresholds as v2.
    ----------------------------------------------------------------------------
    local mMean, mMax = SM.GateMana(Gate, r, rec, " (modelled pool)")

    ----------------------------------------------------------------------------
    -- 3: health per target, scored against the reconstruction
    -- (`sc.recordedHp`), stronger with more samples than a TBC recording's
    -- native health log. Text says when any scored target's max was
    -- estimated (Planner ruling 1: a secret max stood in for).
    ----------------------------------------------------------------------------
    local limHpMean, whyHp = Threshold("hpMean")
    local limHpMax = Threshold("hpMax")
    local scored, excluded = 0, 0
    local worstMean, worstTgt, anyScoredEstimated = 0, nil, false
    local hpT = (sc.recordedHp and sc.recordedHp.t) or {}
    local hpAll = (sc.recordedHp and sc.recordedHp.hp) or {}
    local damageTaken = {}
    for i = 1, (rec.n or 0) do
        if rec.ev.kind[i] == V3.DMG and (rec.ev.tgt[i] or 0) > 0 then
            damageTaken[rec.ev.tgt[i]] = (damageTaken[rec.ev.tgt[i]] or 0) + 1
        end
    end
    for i, tg in ipairs(sc.targets) do
        if tg.tracked and not damageTaken[i] then
            out.excluded[i] = "took no damage"
            excluded = excluded + 1
        elseif tg.tracked and hpAll[i] then
            local mean, max = MeanMax(r.hpCurve[i], hpAll[i], #hpT, tg.maxHP)
            if mean == nil then
                out.excluded[i] = "no health readings"
                excluded = excluded + 1
            elseif mean > limHpMean or max > limHpMax then
                -- review-replay R27: a percentage of a stand-in max says so
                -- (Planner ruling 1), here as on the gate's own text.
                out.excluded[i] = string.format("mean %.0f%% / worst %.0f%% of max health%s",
                    mean * 100, max * 100, tg.maxEstimated and ", max estimated" or "")
                excluded = excluded + 1
            else
                scored = scored + 1
                if tg.maxEstimated then anyScoredEstimated = true end
                if mean > worstMean then worstMean, worstTgt = mean, i end
            end
        end
    end
    local hcText
    if scored > 0 then
        hcText = string.format("%d damaged target(s) reproduced%s, %d excluded",
            scored,
            worstTgt and string.format(" (worst mean %.0f%% on %s)", worstMean * 100,
                sc.targets[worstTgt].name or "?") or "",
            excluded)
    else
        hcText = string.format("no target reproduced within %.0f%% mean / %.0f%% worst",
            limHpMean * 100, limHpMax * 100)
    end
    if anyScoredEstimated then hcText = hcText .. ", max estimated" end
    Gate("health curves", scored > 0, hcText, nil, limHpMean, whyHp,
        scored > 0 and string.format("health, %d reproduced", scored) or "health")

    ----------------------------------------------------------------------------
    -- 4: no tracked death (as v2, the same gate).
    ----------------------------------------------------------------------------
    SM.GateDeath(Gate, rec)

    ----------------------------------------------------------------------------
    -- 5: foreign healing -- the damage meter's own share, not TBC's combat
    -- log. No meter reading fails the gate outright.
    ----------------------------------------------------------------------------
    local limForeign, whyForeign = Threshold("foreign")
    do
        local meter = rec.meter
        if not meter or meter.read == "none" then
            Gate("foreign healing", false,
                string.format("no damage meter reading after the fight (%s)",
                    (meter and meter.why) or "no meter data"),
                nil, limForeign, whyForeign, NO_METER)
        else
            local total = (meter.own or 0) + (meter.others or 0)
            local fs = total > 0 and (meter.others or 0) / total or 0
            Gate("foreign healing", fs <= limForeign,
                string.format("%.0f%% of healing on your group was somebody else's (limit %.0f%%)",
                    fs * 100, limForeign * 100),
                fs, limForeign, whyForeign, string.format("foreign healing %.0f%%", fs * 100))
        end
    end

    ----------------------------------------------------------------------------
    -- 6: model calibrated -- the replay's own effective healing (`r.healed`
    -- minus whatever landed under family "foreign") against the meter's own
    -- total for the fight.
    ----------------------------------------------------------------------------
    local limMeter, whyMeter = Threshold("meterOwn")
    do
        local meter = rec.meter
        if not meter or meter.read == "none" then
            Gate("model calibrated", false,
                string.format("no damage meter reading after the fight (%s)",
                    (meter and meter.why) or "no meter data"),
                nil, limMeter, whyMeter, NO_METER)
        else
            local sim = (r.healed or 0) - ((r.healByFamily and r.healByFamily.foreign) or 0)
            local mOwn = meter.own or 0
            local d
            if mOwn > 0 then d = math.abs(sim - mOwn) / mOwn else d = sim > 0 and 1 or 0 end
            local text = string.format(
                "replay heals %.0f effective, the meter counted %.0f (%.0f%% off, limit %.0f%%)",
                sim, mOwn, d * 100, limMeter * 100)
            if mOwn > 0 and meter.bySpell then
                local worstID, worstAmt = nil, 0
                for spellID, amt in pairs(meter.bySpell) do
                    if (amt / mOwn) >= 0.10 and amt > worstAmt then worstID, worstAmt = spellID, amt end
                end
                if worstID then
                    local name = (MD.API and MD.API.SpellName and MD.API.SpellName(worstID)) or tostring(worstID)
                    text = text .. string.format("; %s is %.0f%% of it", tostring(name), worstAmt / mOwn * 100)
                end
            end
            Gate("model calibrated", d <= limMeter, text, d, limMeter, whyMeter,
                string.format("model %.0f%% off the meter", d * 100))
        end
    end

    ----------------------------------------------------------------------------
    -- 7: spend coverage (as v2, the same gate), classified with the Forever
    -- `MD:ClassifyCast` (T13d).
    ----------------------------------------------------------------------------
    local _, spend = SM.OwnSpend(rec, V3.OWNCAST)
    SM.GateSpend(Gate, rec, sc, kit, spend, "book classification (Forever)")

    ----------------------------------------------------------------------------
    -- 8: heals attributed (Planner ruling 2) -- the paired own total against
    -- the meter's own total. The short side (paired below the meter -- own
    -- heals the attribution called foreign) is always checked; the long side
    -- only once `SM.HEAL_AMOUNT == "effective"`. The attribution is the
    -- scenario's own (T66: `sc.ownHeals`, `sc.attribution`), never made twice.
    ----------------------------------------------------------------------------
    local limAttrib, whyAttrib = Threshold("attributed")
    do
        local ownSet, counts = sc.ownHeals or {}, sc.attribution or {}
        local pairedTotal = 0
        local evr = rec.ev or {}
        for i = 1, (rec.n or 0) do
            if evr.kind[i] == V3.HEAL and ownSet[i] then
                pairedTotal = pairedTotal + (evr.amt[i] or 0)
            end
        end
        local meter = rec.meter
        if not meter or meter.read == "none" then
            Gate("heals attributed", false,
                string.format("no damage meter reading after the fight (%s)",
                    (meter and meter.why) or "no meter data"),
                nil, limAttrib, whyAttrib, NO_METER)
        else
            local mOwn = meter.own or 0
            local d
            if mOwn > 0 then d = math.abs(pairedTotal - mOwn) / mOwn else d = pairedTotal > 0 and 1 or 0 end
            local shortfall = pairedTotal < mOwn * (1 - limAttrib)
            local longFail = (SM.HEAL_AMOUNT == "effective") and pairedTotal > mOwn * (1 + limAttrib)
            local okGate = not (shortfall or longFail)
            local text = string.format(
                "own %d heals paired with your casts, foreign %d; paired total %.0f vs meter %.0f (%.0f%% off, limit %.0f%%)",
                counts.own or 0, counts.foreign or 0, pairedTotal, mOwn, d * 100, limAttrib * 100)
            if SM.HEAL_AMOUNT ~= "effective" then
                text = text .. "; only a shortfall is checked until a heal amount is known to be effective"
            end
            Gate("heals attributed", okGate, text, d, limAttrib, whyAttrib,
                string.format("heals %.0f%% off the meter", d * 100))
        end
    end

    out.result = r
    out.manaMean, out.manaMax = mMean, mMax
    return out
end

--------------------------------------------------------------------------------
-- The v3 road, registered (T66, P22, review A18) where this file used to wrap
-- SM:Validate: Engine/SimModel.lua picks the validator by the stream's version;
-- every v2/TBC recording takes the road it always has.
--------------------------------------------------------------------------------
SM.validators[STREAM.V] = function(rec, kit, ...) return SM.ValidateV3(rec, kit, ...) end
