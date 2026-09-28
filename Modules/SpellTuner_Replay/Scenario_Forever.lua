-- T13d (docs/tasks/T13d-scenario-v3.md): a v3 stream (T13,
-- Modules/SpellTuner_Recorder/Recorder_Forever.lua) becomes a scenario of
-- exactly the shape Engine/SimModel.lua already runs. Pure: no client call,
-- no MD.API, no GetTime() here -- MD:ClassifyCast reads MD.Book, which is the
-- adapter's own job, not this file's. Never mutates `rec`.
local _, MD = ...
local SM = MD.SimModel

-- The v3 stream's own event-kind numbers (Recorder_Forever.lua's local K,
-- duplicated for the same reason that file gives: the two modules are not
-- guaranteed to load in a way that lets one read the other's locals). HEAL
-- (15) never reaches SM.K -- SM.Run only knows FHEAL (2), which the engine
-- generates its own heals to match; a HEAL of unknown source is this file's
-- job to turn into either nothing (own) or an FHEAL (foreign).
local V3 = { DMG = 1, HEAL = 15, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9 }

--------------------------------------------------------------------------------
-- Planner ruling 1, 2026-09-28 (FOREVER-PLAN.md, rulings for M3): a party
-- member's max health is secret, so it is stood in for by the largest deficit
-- the target lived through plus the biggest single hit it took -- it
-- survived the first, and one more like it is the plan's own danger idea.
-- `deficits` and `hits` are plain lists of numbers; only their maximums
-- matter. A lower bound, never a guess at the true number.
--------------------------------------------------------------------------------
function SM.EstimateMaxHP(deficits, hits)
    local d, h = 0, 0
    for _, v in ipairs(deficits or {}) do if (v or 0) > d then d = v end end
    for _, v in ipairs(hits or {}) do if (v or 0) > h then h = v end end
    local mh = d + h
    if mh <= 0 then mh = 1 end -- never a zero-health target: nothing to divide by
    return mh
end

--------------------------------------------------------------------------------
-- Planner ruling 2, 2026-09-28 (FOREVER-PLAN.md, rulings for M3): a HEAL
-- event's source is unknown. Pair it with the player's own casts by time and
-- target -- a direct heal within [cast-0.3, cast+1.0] on the cast's target; a
-- HoT's ticks at cast + tickPeriod*k, matched only when the heal is at most
-- twice the kit's own tick (a size guard against matching an unrelated
-- heal), and ended by a recast of the same family on the same target
-- (including a pre-pull HoT the recast lands on top of). Everything a claim
-- does not reach is foreign.
--
-- Lead review 1, 2026-09-28: what the tick TIMER does across a recast is
-- UNKNOWN on Forever. Two readings are both defensible -- the ruling's own
-- words ("cast + 3k" from the recast, a fresh cadence) and what
-- Engine/SimModel.lua actually does on TBC (a refresh extends a HoT but does
-- NOT restart its tick timer, so the OLD application's cadence keeps
-- ticking). Rather than guess which one the Forever client does, every
-- recast claims BOTH cadences -- its own fresh one (c.t + P*k, k = 1..ticks)
-- and, when it lands over an already-ticking application of the same family
-- and target, the continuing cadence that application itself carries
-- forward -- each claim still size-guarded and consumed at most once, so
-- only whichever cadence the real heal events follow is ever actually
-- matched; the other cadence's claims simply go unconsumed. No claim lands
-- at the recast's own instant (neither cadence ticks there).
--
-- Lead review 2, 2026-09-28: review 1's fix only carried the cadence one
-- recast deep -- it read the immediately-replaced application's OWN cadence
-- (c.t + P), which is wrong once THAT application was itself a recast. On
-- Forever the tick timer is never restarted (Engine/SimModel.lua), so the
-- cadence a third application must continue is the FIRST application's,
-- carried through every refresh in between. Every application therefore
-- carries an `inherited` cadence: its own fresh one when it lands on
-- nothing active, else whatever the application it replaces itself
-- inherited (not that application's own cadence) -- so a chain of recasts
-- of any length keeps tracing back to the original application.
--
-- Returns `own` (HEAL event index -> true) and `counts` (own/foreign/
-- ownDirect/ownTick/prepull totals) for the scenario's `attribution` field.
--------------------------------------------------------------------------------
function SM.AttributeHeals(rec, kit)
    local ev, n = rec.ev or {}, rec.n or 0
    local form = "caster" -- Forever has no Tree of Life (T15's Kit_Forever.lua Facts)
    local k = (kit and kit[form]) or {}

    -- Own casts of a spell the healing kit knows, in time order (the stream
    -- already is).
    local casts = {}
    for i = 1, n do
        if ev.kind[i] == V3.OWNCAST then
            local id, tgt, t = ev.x[i], ev.tgt[i], ev.t[i]
            local sd = MD.SpellData.spells[id]
            local e = sd and k[id]
            if sd and e and tgt and tgt > 0 then
                casts[#casts + 1] = { t = t, tgt = tgt, family = sd.family, e = e }
            end
        end
    end

    -- Is `family`/`tgt` already ticking at time `t`, from the pre-pull read
    -- or from an own cast recorded before `casts[beforeIdx]`? Its own
    -- duration (tickPeriod*ticks, the kit's own numbers) is the window --
    -- the same span Engine/SimModel.lua's own ApplyHot treats as active.
    -- Returns "cast", j (the index into `casts`) or "prepull", a (the aura
    -- entry) -- or nil if nothing is active. Does NOT compute a cadence
    -- itself (Lead review 2): the caller must trace through `inherited` to
    -- find the cadence that application actually carries forward.
    local function FindActive(t, tgt, family, beforeIdx)
        for j = beforeIdx - 1, 1, -1 do
            local c = casts[j]
            if c.tgt == tgt and c.family == family and c.e.tickPeriod and c.e.ticks then
                local dur = c.e.tickPeriod * c.e.ticks
                if t > c.t and t < c.t + dur then
                    return "cast", j
                end
            end
        end
        for _, a in ipairs(rec.initial and rec.initial.auras or {}) do
            if a.tgt == tgt then
                local sd = MD.SpellData.spells[a.spellId]
                local e2 = sd and k[a.spellId]
                if sd and sd.family == family and (a.remaining or 0) > t and e2 and e2.tickPeriod then
                    return "prepull", a
                end
            end
        end
        return nil
    end

    -- The cadence a fresh (non-recast) application produces on its own:
    -- {anchor, tickPeriod, prepull = false}, anchor already being the
    -- FIRST tick of that cadence (cast time + one tickPeriod).
    local function OwnCadenceOf(cst)
        return { anchor = cst.t + cst.e.tickPeriod, tickPeriod = cst.e.tickPeriod, prepull = false }
    end

    -- The cadence a pre-pull aura's own remaining ticks produce, counted
    -- back from its expiry (same arithmetic as the pre-pull claim loop
    -- below): {anchor, tickPeriod, prepull = true}, or nil if the kit does
    -- not know its tick shape.
    local function PrepullCadenceOf(a)
        local sd = MD.SpellData.spells[a.spellId]
        local e2 = sd and k[a.spellId]
        if not (e2 and e2.tickPeriod) then return nil end
        local remaining = a.remaining or 0
        local ticksLeft = math.max(1, math.floor(remaining / e2.tickPeriod + 0.5))
        local nextTick = remaining - (ticksLeft - 1) * e2.tickPeriod
        if nextTick < 0 then nextTick = 0 end
        return { anchor = nextTick, tickPeriod = e2.tickPeriod, prepull = true }
    end

    -- `inherited[i]`: the cadence casts[i] itself carries forward to
    -- whatever LATER recast replaces it (Lead review 2) -- its own fresh
    -- cadence when it landed on nothing active, else whatever the
    -- application it replaced itself inherited (never that application's
    -- own cadence). Filled in cast order as the main loop below processes
    -- each cast, so a chain of recasts of any length keeps tracing back to
    -- the very first application.
    local inherited = {}

    -- The smallest `anchor + tickPeriod*m` (m = 0, 1, 2, ...) that is >= t --
    -- the next tick a continuing cadence produces at or after the recast.
    local function NextOnCadence(anchor, tickPeriod, t)
        if anchor >= t then return anchor end
        local m = math.ceil((t - anchor) / tickPeriod)
        return anchor + tickPeriod * m
    end

    -- claims: {t0, t1, tgt, kindTag = "direct"|"tick", maxAmt, prepull}
    local claims = {}
    local function AddClaim(t0, t1, tgt, kindTag, maxAmt, isPrepull)
        claims[#claims + 1] = { t0 = t0, t1 = t1, tgt = tgt, kindTag = kindTag,
                                 maxAmt = maxAmt, prepull = isPrepull }
    end

    for i, c in ipairs(casts) do
        if c.e.direct then
            AddClaim(c.t - 0.3, c.t + 1.0, c.tgt, "direct", nil, false)
        elseif not c.e.tick then
            -- Swiftmend and any other kindless-but-healing kit entry: one
            -- lump claim, same window as a direct heal.
            AddClaim(c.t - 0.3, c.t + 1.0, c.tgt, "direct", nil, false)
        end
        if c.e.tick and c.e.tickPeriod and c.e.ticks then
            local ticks = math.floor(c.e.ticks + 0.5)
            -- ends at the NEXT own cast of the same family/target (Facts)
            local cutoff = math.huge
            for j = i + 1, #casts do
                local o = casts[j]
                if o.tgt == c.tgt and o.family == c.family then cutoff = o.t; break end
            end
            -- Every application's own cadence (Planner ruling 2, k = 1..ticks
            -- from its own cast time) -- unconditional; a recast is no
            -- exception (Lead review 1).
            local ownEnd = c.t + c.e.tickPeriod * ticks
            for kk = 1, ticks do
                local when = c.t + c.e.tickPeriod * kk
                if when >= cutoff then break end
                AddClaim(when - 0.4, when + 0.4, c.tgt, "tick", c.e.tick * 2, false)
            end
            -- What this application itself carries forward (Lead review 2):
            -- its own fresh cadence when nothing is active under it, else
            -- the cadence the application it replaces itself inherited --
            -- never that application's own cadence, so a chain of recasts
            -- keeps tracing back to the very first application.
            local kind, ref = FindActive(c.t, c.tgt, c.family, i)
            local myInherited
            if kind == "cast" then
                myInherited = inherited[ref] or OwnCadenceOf(casts[ref])
            elseif kind == "prepull" then
                myInherited = PrepullCadenceOf(ref)
            else
                myInherited = OwnCadenceOf(c)
            end
            inherited[i] = myInherited

            -- A recast over an already-ticking application ALSO claims the
            -- cadence it inherited (not its own fresh one a second time),
            -- up to this application's own end or the next recast -- what
            -- Engine/SimModel.lua's own tick timer actually does.
            if kind and myInherited then
                local windowEnd = math.min(cutoff, ownEnd)
                local when = NextOnCadence(myInherited.anchor, myInherited.tickPeriod, c.t)
                while when < windowEnd do
                    AddClaim(when - 0.4, when + 0.4, c.tgt, "tick", c.e.tick * 2, myInherited.prepull)
                    when = when + myInherited.tickPeriod
                end
            end
        end
    end

    -- Pre-pull HoTs: ticks counted back from their own expiry (the same
    -- ticksLeft/nextTick arithmetic Engine/SimModel.lua's own init.auras
    -- handling uses), ended the same way by a recast.
    for _, a in ipairs(rec.initial and rec.initial.auras or {}) do
        if a.tgt and a.tgt > 0 then
            local sd = MD.SpellData.spells[a.spellId]
            local e = sd and k[a.spellId]
            if sd and e and e.tick and e.tickPeriod then
                local remaining = a.remaining or 0
                local ticksLeft = math.max(1, math.floor(remaining / e.tickPeriod + 0.5))
                local nextTick = remaining - (ticksLeft - 1) * e.tickPeriod
                if nextTick < 0 then nextTick = 0 end
                local cutoff = math.huge
                for _, c in ipairs(casts) do
                    if c.tgt == a.tgt and c.family == sd.family then cutoff = c.t; break end
                end
                for j = 0, ticksLeft - 1 do
                    local when = nextTick + e.tickPeriod * j
                    if when >= cutoff then break end
                    AddClaim(when - 0.4, when + 0.4, a.tgt, "tick", e.tick * 2, true)
                end
            end
        end
    end

    table.sort(claims, function(x, y) return x.t0 < y.t0 end)

    local consumed, own = {}, {}
    local counts = { own = 0, foreign = 0, ownDirect = 0, ownTick = 0, prepull = 0 }
    for i = 1, n do
        if ev.kind[i] == V3.HEAL then
            local t, tgt, amt = ev.t[i], ev.tgt[i], ev.amt[i]
            local matched
            for ci, cl in ipairs(claims) do
                if not consumed[ci] and cl.tgt == tgt and t >= cl.t0 and t <= cl.t1
                    and (cl.kindTag ~= "tick" or (amt or 0) <= cl.maxAmt + 1e-6) then
                    matched, consumed[ci] = cl, true
                    break
                end
            end
            if matched then
                own[i] = true
                counts.own = counts.own + 1
                if matched.kindTag == "direct" then
                    counts.ownDirect = counts.ownDirect + 1
                else
                    counts.ownTick = counts.ownTick + 1
                    if matched.prepull then counts.prepull = counts.prepull + 1 end
                end
            else
                counts.foreign = counts.foreign + 1
            end
        end
    end

    return own, counts
end

--------------------------------------------------------------------------------
-- ReconstructHp: the shared arithmetic behind both SM.ScenarioV3's own
-- `recordedHp` field and SM.RecordedHp below (T16a) -- a target's stand-in
-- max (Planner ruling 1) and its health on a 2s grid from every landed amount,
-- own and foreign alike. Pure, no kit needed: neither computation reads which
-- heals were own.
--------------------------------------------------------------------------------
local function ReconstructHp(rec)
    local roster = rec.roster or {}
    local nT = #roster
    local ev, n = rec.ev or {}, rec.n or 0

    local hits, sizingDeficit, sizingMax = {}, {}, {}
    for i = 1, nT do sizingDeficit[i], sizingMax[i] = 0, 0 end
    for i = 1, n do
        local kind, tgt, amt = ev.kind[i], ev.tgt[i], ev.amt[i]
        if kind == V3.DMG and tgt and tgt > 0 then
            hits[tgt] = hits[tgt] or {}
            hits[tgt][#hits[tgt] + 1] = amt or 0
            sizingDeficit[tgt] = (sizingDeficit[tgt] or 0) + (amt or 0)
            if sizingDeficit[tgt] > (sizingMax[tgt] or 0) then sizingMax[tgt] = sizingDeficit[tgt] end
        elseif kind == V3.HEAL and tgt and tgt > 0 then
            sizingDeficit[tgt] = math.max(0, (sizingDeficit[tgt] or 0) - (amt or 0))
        end
    end

    local maxHP, maxEstimated, anyEstimated = {}, {}, false
    for i = 1, nT do
        local r = roster[i] or {}
        if r.maxSecret == false and type(r.maxHP) == "number" and r.maxHP > 0 then
            maxHP[i], maxEstimated[i] = r.maxHP, false
        else
            maxHP[i] = SM.EstimateMaxHP({ sizingMax[i] or 0 }, hits[i] or {})
            maxEstimated[i] = true
            anyEstimated = true
        end
    end

    local dur = rec.dur or 0
    local gridT = {}
    do
        local t = 0
        while t <= dur + 1e-9 do gridT[#gridT + 1] = t; t = t + 2 end
    end

    local recon, hpOut, maxOut = {}, {}, {}
    for i = 1, nT do recon[i], hpOut[i], maxOut[i] = 0, {}, {} end
    local ei = 1
    for _, gt in ipairs(gridT) do
        while ei <= n and ev.t[ei] <= gt + 1e-9 do
            local kind, tgt, amt = ev.kind[ei], ev.tgt[ei], ev.amt[ei]
            if tgt and tgt > 0 then
                if kind == V3.DMG then
                    recon[tgt] = (recon[tgt] or 0) + (amt or 0)
                elseif kind == V3.HEAL then
                    recon[tgt] = math.max(0, (recon[tgt] or 0) - (amt or 0))
                elseif kind == V3.DIED then
                    recon[tgt] = maxHP[tgt] or recon[tgt]
                end
            end
            ei = ei + 1
        end
        for i = 1, nT do
            local h = (maxHP[i] or 1) - (recon[i] or 0)
            if h < 0 then h = 0 end
            hpOut[i][#hpOut[i] + 1] = h
            maxOut[i][#maxOut[i] + 1] = maxHP[i] or 0
        end
    end

    return { maxHP = maxHP, maxEstimated = maxEstimated, anyEstimated = anyEstimated,
             t = gridT, hp = hpOut, max = maxOut }
end

--------------------------------------------------------------------------------
-- SM.RecordedHp(rec, kit): T13d's reconstruction, in v2's own `rec.hp` shape
-- (`{t, hp = {[i] = {...}}, max = {[i] = {...}}}`) so Engine/SimPlanner.lua's
-- two `rec.hp` readers (the recorder's real-health ticks, and the max-health
-- fallback in `SP.FromRecordings`) work unchanged on a v3 stream that never
-- carried `rec.hp` at all. `kit` is accepted for symmetry with
-- SM.ScenarioFromRecording's own signature but unused: the reconstruction
-- never needs to know which heals were own.
--------------------------------------------------------------------------------
function SM.RecordedHp(rec, kit)
    if not rec or not rec.roster then return nil end
    local h = ReconstructHp(rec)
    return { t = h.t, hp = h.hp, max = h.max }
end

--------------------------------------------------------------------------------
-- SM.ScenarioV3: a v3 stream -> the v2 scenario shape, plus recordedHp,
-- attribution and maxEstimated (Files table).
--------------------------------------------------------------------------------
function SM.ScenarioV3(rec, kit)
    local K = SM.K -- the engine's own numbering (FHEAL = 2, etc.)
    local roster = rec.roster or {}
    local nT = #roster
    local trackedSet = {}
    for _, idx in ipairs(rec.tracked or {}) do trackedSet[idx] = true end

    local ownSet, attrCounts = SM.AttributeHeals(rec, kit)

    local ev, n = rec.ev or {}, rec.n or 0
    local outEv = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    local function Push(t, kind, tgt, amt, x)
        local m = #outEv.t + 1
        outEv.t[m], outEv.kind[m], outEv.tgt[m], outEv.amt[m], outEv.x[m] = t, kind, tgt, amt, x
    end

    -- Per target: every hit (for danger/EstimateMaxHP), whether it was ever
    -- hit or healed (for `tracked`), and the plain running deficit used to
    -- size the stand-in max (Planner ruling 1) -- DMG/HEAL only, DIED not
    -- reset here (nothing needs the true max yet).
    local hits, hitOrHealed, sizingDeficit, sizingMax = {}, {}, {}, {}
    for i = 1, nT do sizingDeficit[i], sizingMax[i] = 0, 0 end

    for i = 1, n do
        local kind, tgt, amt, x = ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i]
        if kind == V3.DMG then
            Push(ev.t[i], K.DMG, tgt, amt, x)
            if tgt and tgt > 0 then
                hitOrHealed[tgt] = true
                hits[tgt] = hits[tgt] or {}
                hits[tgt][#hits[tgt] + 1] = amt or 0
                sizingDeficit[tgt] = (sizingDeficit[tgt] or 0) + (amt or 0)
                if sizingDeficit[tgt] > (sizingMax[tgt] or 0) then sizingMax[tgt] = sizingDeficit[tgt] end
            end
        elseif kind == V3.HEAL then
            if tgt and tgt > 0 then
                hitOrHealed[tgt] = true
                sizingDeficit[tgt] = math.max(0, (sizingDeficit[tgt] or 0) - (amt or 0))
            end
            if not ownSet[i] then Push(ev.t[i], K.FHEAL, tgt, amt, x) end
        elseif kind == V3.OWNCAST then
            Push(ev.t[i], K.OWNCAST, tgt, amt, x)
        elseif kind == V3.CASTSTART then
            Push(ev.t[i], K.CASTSTART, tgt, amt, x)
        elseif kind == V3.CANCEL then
            Push(ev.t[i], K.CANCEL, tgt, amt, x)
        elseif kind == V3.DIED then
            Push(ev.t[i], K.DIED, tgt, amt, x)
        end
    end

    -- Planner ruling 1: a plain max stays plain; a secret one is stood in
    -- for. `maxEstimated` on the scenario is true when any target needed one.
    local maxHP, maxEstimated, anyEstimated = {}, {}, false
    for i = 1, nT do
        local r = roster[i] or {}
        if r.maxSecret == false and type(r.maxHP) == "number" and r.maxHP > 0 then
            maxHP[i], maxEstimated[i] = r.maxHP, false
        else
            maxHP[i] = SM.EstimateMaxHP({ sizingMax[i] or 0 }, hits[i] or {})
            maxEstimated[i] = true
            anyEstimated = true
        end
    end

    local dangerHits = (MD.db and MD.db.simDangerHits) or 1
    local targets = {}
    for i = 1, nT do
        local r = roster[i] or {}
        local list = hits[i]
        local danger
        if list and #list > 0 and maxHP[i] > 0 then
            local biggest = 0
            for _, v in ipairs(list) do if v > biggest then biggest = v end end
            danger = math.min(1, (biggest * dangerHits) / maxHP[i])
        end
        targets[i] = {
            name = r.name, role = r.role, maxHP = maxHP[i], maxEstimated = maxEstimated[i],
            danger = danger, hp0 = maxHP[i],
            tracked = (trackedSet[i] == true) and (hitOrHealed[i] == true) or false,
        }
    end

    -- script/fixed: same split as the v2 path (Engine/SimModel.lua's own
    -- ScenarioFromRecording) -- script stays complete, fixed is what the
    -- healing kit does not price.
    local script, fixed = {}, {}
    for i = 1, n do
        if ev.kind[i] == V3.OWNCAST then
            local id = ev.x[i]
            local cost = (ev.amt[i] or -1) >= 0 and ev.amt[i] or nil
            local entry = { ev.t[i], id, cost, ev.tgt[i] }
            script[#script + 1] = entry
            if not MD.SpellData.spells[id] then
                local kindLabel = "unknown"
                if MD.ClassifyCast then
                    local _, kk = MD:ClassifyCast(id)
                    kindLabel = kk or "unknown"
                end
                fixed[#fixed + 1] = { ev.t[i], id, cost, ev.tgt[i], kindLabel }
            end
        end
    end

    -- initial: Forever has no unreported regen (Dreamstate is TBC) and no
    -- Tree of Life (Facts). An aura whose spell the kit does not know is
    -- dropped; the lead's hand-out amendment's `tgt` is what maps it.
    local rinit = rec.initial or {}
    local auras = {}
    for _, a in ipairs(rinit.auras or {}) do
        if a.tgt and a.tgt > 0 and MD.SpellData.spells[a.spellId] then
            auras[#auras + 1] = { target = a.tgt, spellID = a.spellId, stacks = a.stacks, remaining = a.remaining }
        end
    end
    local mn = rec.mana or {}
    local initial = {
        mana = rinit.mana or 0, form = "caster",
        apiBase = mn.base and mn.base[1] or 0, apiCasting = mn.cast and mn.cast[1] or 0,
        energize = 0, auras = auras, known = rinit.known,
    }

    local rates = {}
    for i = 1, #(mn.t or {}) do rates[i] = { mn.t[i], mn.base[i] or 0, mn.cast[i] or 0 } end

    -- recordedHp: a deficit from every landed amount (own and foreign alike
    -- -- they all landed), floored at full, sampled every two seconds,
    -- starting at full at the pull (Facts).
    local dur = rec.dur or 0
    local gridT = {}
    do
        local t = 0
        while t <= dur + 1e-9 do gridT[#gridT + 1] = t; t = t + 2 end
    end

    local recon, hpOut = {}, {}
    for i = 1, nT do recon[i], hpOut[i] = 0, {} end
    local ei = 1
    for _, gt in ipairs(gridT) do
        while ei <= n and ev.t[ei] <= gt + 1e-9 do
            local kind, tgt, amt = ev.kind[ei], ev.tgt[ei], ev.amt[ei]
            if tgt and tgt > 0 then
                if kind == V3.DMG then
                    recon[tgt] = (recon[tgt] or 0) + (amt or 0)
                elseif kind == V3.HEAL then
                    recon[tgt] = math.max(0, (recon[tgt] or 0) - (amt or 0))
                elseif kind == V3.DIED then
                    recon[tgt] = maxHP[tgt] or recon[tgt]
                end
            end
            ei = ei + 1
        end
        for i = 1, nT do
            local h = (maxHP[i] or 1) - (recon[i] or 0)
            if h < 0 then h = 0 end
            hpOut[i][#hpOut[i] + 1] = h
        end
    end

    return {
        dur = dur, pool = rec.pool or 0,
        initial = initial, energizeAssumed = false,
        targets = targets, ev = outEv, rates = rates, fixed = fixed,
        incoming = {}, threat = {}, -- secret by policy (Facts, plan §5)
        sampleT = mn.t, hpSampleT = gridT, kit = kit,
        floor = (MD.db and MD.db.simFloor) or 0.30,
        script = script,
        recordedHp = { t = gridT, hp = hpOut },
        attribution = attrCounts,
        maxEstimated = anyEstimated,
    }
end

--------------------------------------------------------------------------------
-- Wrap SM.ScenarioFromRecording: a v3 stream goes to ScenarioV3, everything
-- else (every v2/TBC recording) takes the road it always has.
--------------------------------------------------------------------------------
local V2ScenarioFromRecording = SM.ScenarioFromRecording
function SM.ScenarioFromRecording(rec, kit)
    if rec and rec.v == 3 then return SM.ScenarioV3(rec, kit) end
    return V2ScenarioFromRecording(rec, kit)
end

--------------------------------------------------------------------------------
-- MD:ClassifyCast(id) -> label, kind -- only if no flavour defined it yet
-- (TBC's own is Data/DruidSpells.lua 66, per T13d's Facts). `book.spells[id]`
-- carries no kind of its own (Spells/Book.lua's BuildEntry never sets one);
-- the kind lives on the FAMILY (Book:GroupFamilies, one per book.families
-- entry, keyed by name), read off via the spell's own name. A heal family
-- answers "heal", a damage family "damage", a kindless book family
-- (Swiftmend has no numbers at all to parse) "utility", and a spell the book
-- never saw at all "unknown".
--------------------------------------------------------------------------------
if MD.ClassifyCast == nil then
    function MD:ClassifyCast(id)
        local book = MD.Book and MD.Book:Get()
        local entry = book and book.spells[id]
        local fam = entry and book.families[entry.name]
        if not entry then return "unknown", "unknown" end
        if fam and fam.kind == "heal" then return "heal", "heal" end
        if fam and fam.kind == "damage" then return "damage", "damage" end
        return "utility", "utility"
    end
end
