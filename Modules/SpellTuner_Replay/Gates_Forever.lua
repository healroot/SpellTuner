-- T14 (docs/tasks/T14-gates-v3.md): the eight gates re-founded on what
-- Forever can know. Health is scored against the reconstruction (T13d
-- `sc.recordedHp`); foreign healing and the model's calibration are checked
-- against the damage meter's totals for the fight (T13's `rec.meter`); mana
-- is a consistency check between the engine's mana model and the client's own
-- modelled pool, never the real (secret) pool; the enemy-cast and threat
-- inputs are dropped (Facts, plan Sec2.3). Pure: no client call, no mutation
-- of `rec`. `Engine/SimModel.lua` is untouched -- its own `SM:Validate` still
-- runs byte for byte on a v2 (TBC) recording; this file only adds the v3 road
-- and wraps the dispatch.
local _, MD = ...
local SM = MD.SimModel

-- The v3 stream's own HEAL kind (Modules/SpellTuner_Recorder/
-- Recorder_Forever.lua's local K, Scenario_Forever.lua's local V3) --
-- duplicated here for the same reason those files give: nothing guarantees
-- one module can read another's locals. It never reaches SM.K (which only
-- knows FHEAL); it is this file's job to read the raw stream a second time,
-- for the amounts ScenarioV3 does not carry back out.
local V3_HEAL = 15

-- `Threshold` and `MeanMax` are local to Engine/SimModel.lua (not exposed on
-- SM) and that file is untouched by this task, so the same small arithmetic
-- is duplicated here. `SM.GATES` itself IS the shared table (`SM.GATES =
-- GATES` there), so every threshold's setting/default/why still lives in one
-- place and this file only adds two entries to it.
local function Threshold(name)
    local g = SM.GATES[name]
    local v = MD.db and MD.db[g.setting]
    if v == nil then v = g.default end
    return v, g.why
end

local function MeanMax(sim, rec, n, scale)
    if not sim or not rec or n == 0 or scale <= 0 then return nil, nil end
    local sum, worst, at = 0, 0, 0
    local used = 0
    for i = 1, n do
        local a, b = sim[i], rec[i]
        if a ~= nil and b ~= nil and b >= 0 then
            local d = math.abs(a - b) / scale
            sum = sum + d
            used = used + 1
            if d > worst then worst, at = d, i end
        end
    end
    if used == 0 then return nil, nil end
    return sum / used, worst, at
end

-- Two new thresholds, only if some other file has not already added them
-- (Files table).
if not SM.GATES.meterOwn then
    SM.GATES.meterOwn = { setting = "simGateMeter", default = 0.10,
        why = "lead's first threshold (2026-09-28); the meter counts effective healing; re-measured in M5" }
end
if not SM.GATES.attributed then
    SM.GATES.attributed = { setting = "simGateAttrib", default = 0.10,
        why = "planner ruling 2 (2026-09-28); lead's first threshold; re-measured on the author's first Forever pulls" }
end

-- Whether a UNIT_COMBAT HEAL amount is gross or effective is still open
-- (docs/TESTING.md Sec38.2 step 4, Q3). "unknown" until the author answers it;
-- gate 8 checks only the short side until this becomes "effective".
SM.HEAL_AMOUNT = "unknown"

--------------------------------------------------------------------------------
-- SM:ValidateV3(rec, kit) -- the eight gates on a v3 stream.
--------------------------------------------------------------------------------
function SM:ValidateV3(rec, kit)
    if not rec then return nil end
    kit = kit or MD.RankMath:SpellKit()
    local sc = SM.ScenarioFromRecording(rec, kit)
    local r = SM:Run(sc, nil, { critMode = "ev" })

    local out = { gates = {}, excluded = {}, ok = true, rec = rec,
                  energize = 0, energizeAssumed = false }
    local function Gate(name, ok, text, value, limit, why)
        out.gates[#out.gates + 1] = { name = name, ok = ok, text = text,
                                      value = value, limit = limit, why = why }
        if not ok then out.ok = false end
    end

    ----------------------------------------------------------------------------
    -- 1 + 2: mana curve. The recorded mana IS the clock's own model
    -- (T13, `manaModelled = true`), so this compares the engine's mana model
    -- with the live mana model -- a consistency check, not a check against the
    -- real pool, which is secret (Facts, Planner ruling 3). Thresholds as v2.
    ----------------------------------------------------------------------------
    local mn = rec.mana or {}
    local pool = rec.pool or 0
    local mMean, mMax = MeanMax(r.manaCurve, mn.v, #(mn.t or {}), pool)
    local limMean, whyMean = Threshold("manaMean")
    local limMax, whyMax = Threshold("manaMax")
    if mMean then
        Gate("mana mean", mMean <= limMean,
            string.format("mean off by %.1f%% of pool (limit %.0f%%) (modelled pool)", mMean * 100, limMean * 100),
            mMean, limMean, whyMean)
        Gate("mana max", mMax <= limMax,
            string.format("worst sample off by %.1f%% of pool (limit %.0f%%) (modelled pool)", mMax * 100, limMax * 100),
            mMax, limMax, whyMax)
    else
        Gate("mana curve", false, "no mana samples recorded (modelled pool)", nil, nil, whyMean)
    end

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
        if rec.ev.kind[i] == SM.K.DMG and (rec.ev.tgt[i] or 0) > 0 then
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
                out.excluded[i] = string.format("mean %.0f%% / worst %.0f%% of max health",
                    mean * 100, max * 100)
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
    Gate("health curves", scored > 0, hcText, nil, limHpMean, whyHp)

    ----------------------------------------------------------------------------
    -- 4: no tracked death (as v2).
    ----------------------------------------------------------------------------
    if rec.practice then
        Gate("no tracked death", true,
            #(rec.deaths or {}) == 0 and "nobody died"
                or string.format("%d death(s) - practice: the whole damage timeline is recorded", #rec.deaths),
            nil, nil, "practice fights record damage the dead would have taken")
    else
        Gate("no tracked death", #(rec.deaths or {}) == 0,
            #(rec.deaths or {}) == 0 and "nobody died"
                or string.format("%d death(s): damage after one is truncated in the log",
                    #rec.deaths),
            nil, nil, "post-death damage truncation")
    end

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
                nil, limForeign, whyForeign)
        else
            local total = (meter.own or 0) + (meter.others or 0)
            local fs = total > 0 and (meter.others or 0) / total or 0
            Gate("foreign healing", fs <= limForeign,
                string.format("%.0f%% of healing on your group was somebody else's (limit %.0f%%)",
                    fs * 100, limForeign * 100),
                fs, limForeign, whyForeign)
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
                nil, limMeter, whyMeter)
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
            Gate("model calibrated", d <= limMeter, text, d, limMeter, whyMeter)
        end
    end

    ----------------------------------------------------------------------------
    -- 7: spend coverage (as v2), classified with the Forever `MD:ClassifyCast`
    -- (T13d).
    ----------------------------------------------------------------------------
    local spendBySpell, spend = {}, 0
    do
        local evr = rec.ev or {}
        for i = 1, (rec.n or 0) do
            if evr.kind[i] == SM.K.OWNCAST and (evr.amt[i] or 0) > 0 then
                spendBySpell[evr.x[i]] = (spendBySpell[evr.x[i]] or 0) + evr.amt[i]
                spend = spend + evr.amt[i]
            end
        end
    end
    local form = (rec.initial and rec.initial.form) or "caster"
    local modelled, replayed, unclassified = 0, 0, 0
    for i = 1, #sc.script do
        local c = sc.script[i]
        local e = kit[form][c[2]] or kit.caster[c[2]]
        local cost = c[3] or (e and e.cost) or 0
        if e then
            modelled = modelled + cost
        else
            local kind
            if MD.ClassifyCast then local _, k = MD:ClassifyCast(c[2]); kind = k end
            if kind and kind ~= "unknown" then replayed = replayed + cost
            else unclassified = unclassified + cost end
        end
    end
    local coverage = spend > 0 and (modelled + replayed) / spend or 0
    Gate("spend coverage", coverage >= 0.90,
        string.format("%.0f%% of the mana is accounted for (%.0f%% healing, %.0f%% replayed as cast)%s",
            coverage * 100, spend > 0 and modelled / spend * 100 or 0,
            spend > 0 and replayed / spend * 100 or 0,
            unclassified > 0 and string.format("; %d mana on spells nothing can name", unclassified) or ""),
        coverage, 0.90, "book classification (Forever)")

    ----------------------------------------------------------------------------
    -- 8: heals attributed (Planner ruling 2) -- the paired own total against
    -- the meter's own total. The short side (paired below the meter -- own
    -- heals the attribution called foreign) is always checked; the long side
    -- only once `SM.HEAL_AMOUNT == "effective"`.
    ----------------------------------------------------------------------------
    local limAttrib, whyAttrib = Threshold("attributed")
    do
        local ownSet, counts = SM.AttributeHeals(rec, kit)
        local pairedTotal = 0
        local evr = rec.ev or {}
        for i = 1, (rec.n or 0) do
            if evr.kind[i] == V3_HEAL and ownSet[i] then
                pairedTotal = pairedTotal + (evr.amt[i] or 0)
            end
        end
        local meter = rec.meter
        if not meter or meter.read == "none" then
            Gate("heals attributed", false,
                string.format("no damage meter reading after the fight (%s)",
                    (meter and meter.why) or "no meter data"),
                nil, limAttrib, whyAttrib)
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
            Gate("heals attributed", okGate, text, d, limAttrib, whyAttrib)
        end
    end

    out.result = r
    out.manaMean, out.manaMax = mMean, mMax
    return out
end

--------------------------------------------------------------------------------
-- Wrap SM:Validate: a v3 stream goes to ValidateV3, everything else (every
-- v2/TBC recording) takes the road it always has.
--------------------------------------------------------------------------------
local V2Validate = SM.Validate
function SM.Validate(self, rec, kit)
    if rec and rec.v == 3 then return SM.ValidateV3(self, rec, kit) end
    return V2Validate(self, rec, kit)
end
