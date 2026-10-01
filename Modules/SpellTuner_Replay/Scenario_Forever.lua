-- T13d (docs/tasks/T13d-scenario-v3.md): a v3 stream (T13,
-- Modules/SpellTuner_Recorder/Recorder_Forever.lua) becomes a scenario of
-- exactly the shape Engine/SimModel.lua already runs. Pure: no client call,
-- no MD.API, no GetTime() here -- MD:ClassifyCast reads MD.Book, which is the
-- adapter's own job, not this file's. Never mutates `rec`.
local _, MD = ...
local SM = MD.SimModel
-- T101: Kit.MULTI_TARGET, the kit types that reach more than their target
-- (Engine/Kit.lua, listed before this file by the module's TOCs)
local Kit = MD.Kit

-- The v3 stream's own event-kind numbers, published once by the Recorder
-- module's Stream_Forever.lua (T66, P22, review A18) -- this module depends on
-- that one, so it is always loaded first. HEAL (15) never reaches SM.K --
-- SM.Run only knows FHEAL (2), which the engine generates its own heals to
-- match; a HEAL of unknown source is this file's job to turn into either
-- nothing (own) or an FHEAL (foreign).
local STREAM = MD.StreamV3
if type(STREAM) ~= "table" or type(STREAM.K) ~= "table" then
    error("Scenario_Forever.lua: MD.StreamV3 is missing -- the Recorder module's Stream_Forever.lua loads first")
end
local V3 = STREAM.K

-- T66: asserted at load, because a persisted stream cannot be renumbered
-- after the fact. A v3 HEAL equal to any SM.K value would be read as that
-- kind wherever a v3 stream meets the engine's own numbering; and the kinds a
-- v3 stream shares with SM.K must keep SM.K's numbers, because
-- SM.DangerHitFromOthers reads a v3 stream's damage by SM.K.DMG.
for name, value in pairs(SM.K) do
    if value == V3.HEAL then
        error(string.format("Scenario_Forever.lua: StreamV3.K.HEAL (%s) collides with SM.K.%s",
            tostring(V3.HEAL), name))
    end
end
for _, name in ipairs({ "DMG", "OWNCAST", "CASTSTART", "CANCEL", "DIED" }) do
    if V3[name] ~= SM.K[name] then
        error(string.format("Scenario_Forever.lua: StreamV3.K.%s (%s) is not SM.K.%s (%s)",
            name, tostring(V3[name]), name, tostring(SM.K[name])))
    end
end

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
-- review-replay R29: a pre-pull HoT's remaining ticks. It ticks at its expiry
-- and every period before that, down to anything still after the pull --
-- ceil(remaining / period) ticks, the first at remaining - (n - 1) * period.
-- Engine/SimModel.lua's own init.auras arithmetic rounds instead, which drops
-- that first tick whenever frac(remaining / period) is under a half; so the
-- claims below and the engine (handed these two numbers on each aura by
-- SM.ScenarioV3) count the same ticks, at the times they really land.
--------------------------------------------------------------------------------
local function PrepullTicks(remaining, period)
    local ticksLeft = math.max(1, math.ceil(remaining / period - 1e-6))
    local firstTick = remaining - (ticksLeft - 1) * period
    if firstTick < 0 then firstTick = 0 end
    return ticksLeft, firstTick
end

-- review-replay R28: the engine's HoT slot for a kit entry (Engine/
-- SimModel.lua's LandCast: "hybrid" rolls the Regrowth slot, "hot" the
-- Rejuvenation one) -- what a Swiftmend can eat.
-- T96 (docs/SPEC-next.md 2.1): the hot map is the KIT's profile's
-- (SM.HotFamilyOf: MD.Profiles.ForKit(kit), the druid's when the kit names
-- none), never the logged-in player's -- the same slot the engine rolls.
local function SlotOf(kit, e)
    if e.type ~= "hybrid" and e.type ~= "hot" and e.type ~= "lifebloom" then return nil end
    return SM.HotFamilyOf(kit, e)
end

-- The crit multiplier Engine/SimModel.lua's DirectAmount uses (vanilla's
-- 1.5, UNVERIFIED on Forever -- the engine's own assumption, not a new one).
local CRIT_MULT = 1.5

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
-- review-replay R28: a HoT's claims also end at the Swiftmend that eats it
-- (Regrowth first, else Rejuvenation -- the engine's own rule), since the
-- engine ticks it no further. R30: a direct claim takes the heal in its
-- window nearest the cast's own value (or its crit), not whichever heal
-- arrived first -- a foreign tick landing just before an own Healing Touch
-- no longer takes its claim; the tick claims then share what is left, first
-- fit as before.
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
-- T101 (docs/SPEC-next.md 4.2 P2, 4.5): a heal that reaches several targets
-- makes several claims at the same instant, one per target it reaches under
-- the engine's own assumption -- a `group` heal (and a channel over the party)
-- one on every member of the caster's party, a `chain` heal its target and
-- then up to `jumps` claims on any OTHER member (whom it jumped to is not in
-- the stream: each jump claim takes the heal nearest its own share, one per
-- member), a `selfAndTarget` heal its target and the caster. And an own cast
-- of a heal the kit does not carry (MD:ClassifyCast says "heal": a heal on
-- the caster alone, a refused reach) claims the heal landing with it on its
-- target (on the caster, when its text heals only the caster): the healer's
-- own heal, which no kit entry claims, replayed AS RECORDED (SM.K.OWNREPLAY,
-- principle 8) instead of being called somebody else's.
--
-- Returns `own` (HEAL event index -> true), `counts` (own/foreign/
-- ownDirect/ownTick/prepull totals, and T101's `recorded`) for the scenario's
-- `attribution` field, and `replayed` (HEAL event index -> true: the own heals
-- no kit entry claims).
--------------------------------------------------------------------------------
-- T101 (4.5): the caster's party in a v3 stream -- every tracked member (the
-- Forever recorder is party-only: in a raid it tracks the player alone) --
-- and the caster: roster index 1, the `player` token the recorder lists
-- first, when its max was read plain (the player's own; a party member's is
-- secret, or read through a status bar, `maxVia`). nil when that is not so:
-- a self-and-target heal then reaches its target only (the lower bound).
local function PartyOf(rec)
    local out = {}
    for _, idx in ipairs(rec.tracked or {}) do out[#out + 1] = idx end
    table.sort(out)
    return out
end
local function CasterOf(rec)
    local r = rec.roster and rec.roster[1]
    if type(r) == "table" and r.maxSecret == false and r.maxVia == nil then return 1 end
    return nil
end
SM.CasterOfV3 = CasterOf

function SM.AttributeHeals(rec, kit)
    local ev, n = rec.ev or {}, rec.n or 0
    local form = "caster" -- Forever has no Tree of Life (T15's Kit_Forever.lua Facts)
    local k = (kit and kit[form]) or {}
    local party, caster = PartyOf(rec), CasterOf(rec)

    -- Own casts of a spell the healing kit knows, in time order (the stream
    -- already is). T101: and the own heals the kit does not carry.
    local casts, unmodelled = {}, {}
    for i = 1, n do
        if ev.kind[i] == V3.OWNCAST then
            local id, tgt, t = ev.x[i], ev.tgt[i], ev.t[i]
            local sd = MD.SpellData.spells[id]
            local e = sd and k[id]
            if sd and e and e.type == "group" then
                -- a group heal reaches the party whoever it was cast on
                casts[#casts + 1] = { t = t, tgt = tgt or -1, family = sd.family, e = e, id = id }
            elseif sd and e and e.type == "channel" and e.party then
                casts[#casts + 1] = { t = t, tgt = tgt or -1, family = sd.family, e = e, id = id }
            elseif sd and e and tgt and tgt > 0 then
                casts[#casts + 1] = { t = t, tgt = tgt, family = sd.family, e = e, id = id }
            elseif not e and MD.ClassifyCast then
                local _, kind = MD:ClassifyCast(id)
                if kind == "heal" then
                    local on = tgt
                    local book = MD.Book and MD.Book:Get()
                    local be = book and book.spells and book.spells[id]
                    if be and be.targets == "caster" then on = caster end
                    if on and on > 0 then unmodelled[#unmodelled + 1] = { t = t, tgt = on, id = id } end
                end
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
        local _, nextTick = PrepullTicks(a.remaining or 0, e2.tickPeriod)
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

    -- R28: which HoT slot each Swiftmend eats, walking the casts in order
    -- with each target's slots' end times (a pre-pull aura's own remaining,
    -- an application's own duration, a Swiftmend ending the slot it ate) --
    -- `c.consumes` is that slot's name, and `c.eats` what it landed for.
    do
        local untilT = {}
        local function Slots(tgt)
            untilT[tgt] = untilT[tgt] or {}
            return untilT[tgt]
        end
        for _, a in ipairs(rec.initial and rec.initial.auras or {}) do
            local e2 = a.tgt and k[a.spellId]
            local slot = e2 and MD.SpellData.spells[a.spellId] and SlotOf(kit, e2)
            if slot and (a.remaining or 0) > 0 then
                local sl = Slots(a.tgt)
                if (a.remaining or 0) > (sl[slot] or 0) then sl[slot] = a.remaining end
            end
        end
        for _, c in ipairs(casts) do
            local slot = SlotOf(kit, c.e)
            local sl = Slots(c.tgt)
            if slot and c.e.tickPeriod and c.e.ticks then
                sl[slot] = c.t + c.e.tickPeriod * c.e.ticks
            elseif c.e.type == "instant" then
                if c.t < (sl.Regrowth or 0) and c.e.swiftmendRegrowth then
                    c.consumes, c.eats, sl.Regrowth = "Regrowth", c.e.swiftmendRegrowth, c.t
                elseif c.t < (sl.Rejuvenation or 0) and c.e.swiftmendRejuv then
                    c.consumes, c.eats, sl.Rejuvenation = "Rejuvenation", c.e.swiftmendRejuv, c.t
                end
            end
        end
    end

    -- claims: {t0, t1, tgt, kindTag = "direct"|"tick", maxAmt, prepull,
    -- expect, crit} -- `expect` (a direct claim's own value, when the kit
    -- has one) and `crit` (whether it can crit) choose among the heals in a
    -- direct claim's window (R30).
    local claims = {}
    local function AddClaim(t0, t1, tgt, kindTag, maxAmt, isPrepull, expect, crit)
        claims[#claims + 1] = { t0 = t0, t1 = t1, tgt = tgt, kindTag = kindTag,
                                 maxAmt = maxAmt, prepull = isPrepull, expect = expect, crit = crit }
    end

    -- T96 (decision 11): when the next cast of ANY spell begins or succeeds
    -- after `t` -- where the engine breaks a channel (SM:Run's BreakChannel)
    local function NextOwnCastAfter(t, spellID)
        for i = 1, n do
            local kind = ev.kind[i]
            if ev.t[i] > t and (kind == V3.OWNCAST or kind == V3.CASTSTART) and ev.x[i] ~= spellID then
                return ev.t[i]
            end
        end
        return math.huge
    end

    -- T101: the claims a heal reaching several targets makes, beside the
    -- usual ones (below) on its own target.
    local function AddMultiClaims(c)
        local e, ty = c.e, c.e.type
        if ty == "group" then
            for _, j in ipairs(party) do
                if (e.direct or 0) > 0 then
                    AddClaim(c.t - 0.3, c.t + 1.0, j, "direct", nil, false, e.direct, (e.directCrit or 0) > 0)
                end
                if e.tick and e.tickPeriod and e.ticks then
                    local ticks = math.floor(e.ticks + 0.5)
                    -- until the next own cast of the same family (it reapplies
                    -- on the whole party)
                    local cutoff = math.huge
                    for _, o in ipairs(casts) do
                        if o.t > c.t and o.family == c.family then cutoff = o.t; break end
                    end
                    for kk = 1, ticks do
                        local when = c.t + e.tickPeriod * kk
                        if when >= cutoff then break end
                        AddClaim(when - 0.4, when + 0.4, j, "tick", e.tick * 2, false)
                    end
                end
            end
        elseif ty == "chain" then
            AddClaim(c.t - 0.3, c.t + 1.0, c.tgt, "direct", nil, false, e.direct, (e.directCrit or 0) > 0)
            local siblings = { used = { [c.tgt] = true } }
            local share = 1
            for _ = 1, (e.jumps or 0) do
                share = share * (e.falloff or 0)
                claims[#claims + 1] = { t0 = c.t - 0.3, t1 = c.t + 1.0, tgt = nil, kindTag = "direct",
                                        expect = (e.direct or 0) * share, crit = (e.directCrit or 0) > 0,
                                        siblings = siblings, anyOf = party }
            end
        elseif ty == "selfAndTarget" then
            AddClaim(c.t - 0.3, c.t + 1.0, c.tgt, "direct", nil, false, e.direct, (e.directCrit or 0) > 0)
            if caster and caster ~= c.tgt then
                AddClaim(c.t - 0.3, c.t + 1.0, caster, "direct", nil, false, e.direct, (e.directCrit or 0) > 0)
            end
        end
    end

    for i, c in ipairs(casts) do
        local chTick, chN, chPeriod = SM.ChannelShape(c.e)
        if Kit.MULTI_TARGET[c.e.type] then
            AddMultiClaims(c)
        elseif chTick then
            -- T96 (decision 11): a channel the engine lands (SM.ChannelShape)
            -- claims its ticks on its target, one per period from the cast,
            -- until the next cast breaks it -- the ticks the engine heals with,
            -- so they are not replayed a second time as foreign healing. A
            -- channel the engine cannot land keeps the lump claim below.
            -- T101: a channel over the party claims each tick on every member.
            local cutoff = NextOwnCastAfter(c.t, c.id)
            for kk = 1, chN do
                local when = c.t + chPeriod * kk
                if when >= cutoff then break end
                if c.e.party then
                    for _, j in ipairs(party) do
                        AddClaim(when - 0.4, when + 0.4, j, "tick", chTick * 2, false)
                    end
                else
                    AddClaim(when - 0.4, when + 0.4, c.tgt, "tick", chTick * 2, false)
                end
            end
        elseif c.e.direct then
            AddClaim(c.t - 0.3, c.t + 1.0, c.tgt, "direct", nil, false,
                c.e.direct, (c.e.directCrit or 0) > 0)
        elseif not c.e.tick then
            -- Swiftmend and any other kindless-but-healing kit entry: one
            -- lump claim, same window as a direct heal.
            AddClaim(c.t - 0.3, c.t + 1.0, c.tgt, "direct", nil, false, c.eats, false)
        end
        if c.e.tick and c.e.tickPeriod and c.e.ticks and not Kit.MULTI_TARGET[c.e.type] then
            local ticks = math.floor(c.e.ticks + 0.5)
            -- ends at the NEXT own cast of the same family/target (Facts),
            -- or at the Swiftmend that eats this HoT (R28)
            local mySlot = SlotOf(kit, c.e)
            local cutoff = math.huge
            for j = i + 1, #casts do
                local o = casts[j]
                if o.tgt == c.tgt and (o.family == c.family or (mySlot and o.consumes == mySlot)) then
                    cutoff = o.t; break
                end
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

    -- Pre-pull HoTs: ticks counted back from their own expiry (PrepullTicks,
    -- the count SM.ScenarioV3 hands Engine/SimModel.lua's init.auras too --
    -- R29), ended the same way by a recast or by the Swiftmend that eats it.
    for _, a in ipairs(rec.initial and rec.initial.auras or {}) do
        if a.tgt and a.tgt > 0 then
            local sd = MD.SpellData.spells[a.spellId]
            local e = sd and k[a.spellId]
            if sd and e and e.tick and e.tickPeriod then
                local ticksLeft, nextTick = PrepullTicks(a.remaining or 0, e.tickPeriod)
                local mySlot = SlotOf(kit, e)
                local cutoff = math.huge
                for _, c in ipairs(casts) do
                    if c.tgt == a.tgt and (c.family == sd.family or (mySlot and c.consumes == mySlot)) then
                        cutoff = c.t; break
                    end
                end
                for j = 0, ticksLeft - 1 do
                    local when = nextTick + e.tickPeriod * j
                    if when >= cutoff then break end
                    AddClaim(when - 0.4, when + 0.4, a.tgt, "tick", e.tick * 2, true)
                end
            end
        end
    end

    -- T101: the own heals no kit entry claims, one each, in the direct window
    for _, u in ipairs(unmodelled) do
        AddClaim(u.t - 0.3, u.t + 1.0, u.tgt, "recorded", nil, false)
    end

    table.sort(claims, function(x, y) return x.t0 < y.t0 end)

    -- R30, pass 1: each direct claim, in time order, takes the heal in its
    -- window on its target nearest its own value (or that value's crit); a
    -- claim with no value of its own takes the earliest, as before. Ties go
    -- to the earlier heal.
    local healIdx = {}
    for i = 1, n do if ev.kind[i] == V3.HEAL then healIdx[#healIdx + 1] = i end end
    local takenBy = {} -- HEAL event index -> the claim that took it
    local function AnyOfHas(list, tgt)
        for _, j in ipairs(list) do if j == tgt then return true end end
        return false
    end
    for _, cl in ipairs(claims) do
        if cl.kindTag == "direct" or cl.kindTag == "recorded" then
            local best, bestScore
            for _, i in ipairs(healIdx) do
                local t = ev.t[i]
                -- T101: a chain's jump claims any member of the party its
                -- siblings have not taken (cl.tgt nil)
                local onTarget
                if cl.tgt == nil then
                    local tg = ev.tgt[i]
                    onTarget = tg and AnyOfHas(cl.anyOf or {}, tg) and not cl.siblings.used[tg]
                else
                    onTarget = ev.tgt[i] == cl.tgt
                end
                if not takenBy[i] and onTarget and t >= cl.t0 and t <= cl.t1 then
                    local score = 0
                    if cl.expect then
                        local amt = ev.amt[i] or 0
                        score = math.abs(amt - cl.expect)
                        if cl.crit then
                            local d = math.abs(amt - cl.expect * CRIT_MULT)
                            if d < score then score = d end
                        end
                    end
                    if not best or score < bestScore then best, bestScore = i, score end
                end
            end
            if best then
                takenBy[best] = cl
                if cl.siblings then cl.siblings.used[ev.tgt[best]] = true end
            end
        end
    end

    -- Pass 2: every heal no direct claim took, in stream order, against the
    -- tick claims, first fit under the size guard.
    local consumed, own, replayed = {}, {}, {}
    local counts = { own = 0, foreign = 0, ownDirect = 0, ownTick = 0, prepull = 0, recorded = 0 }
    for i = 1, n do
        if ev.kind[i] == V3.HEAL then
            local t, tgt, amt = ev.t[i], ev.tgt[i], ev.amt[i]
            local matched = takenBy[i]
            if not matched then
                for ci, cl in ipairs(claims) do
                    if cl.kindTag == "tick" and not consumed[ci] and cl.tgt == tgt
                        and t >= cl.t0 and t <= cl.t1 and (amt or 0) <= cl.maxAmt + 1e-6 then
                        matched, consumed[ci] = cl, true
                        break
                    end
                end
            end
            if matched then
                own[i] = true
                counts.own = counts.own + 1
                if matched.kindTag == "recorded" then
                    -- T101: the healer's, replayed as recorded
                    replayed[i] = true
                    counts.recorded = counts.recorded + 1
                elseif matched.kindTag == "direct" then
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

    return own, counts, replayed
end

--------------------------------------------------------------------------------
-- T17b (docs/tasks/T17b-party-max-leave-one-out.md): the sizing arithmetic
-- behind a stand-in max, once. Per roster index: every DMG amount (`hits`),
-- the largest running deficit -- DMG adding, HEAL subtracting, floored at 0
-- -- (`sizingMax`), and whether the target was ever hit or healed.
--------------------------------------------------------------------------------
local function SizeRec(rec)
    local nT = #(rec.roster or {})
    local ev, n = rec.ev or {}, rec.n or 0
    local hits, sizingDeficit, sizingMax, hitOrHealed = {}, {}, {}, {}
    for i = 1, nT do sizingDeficit[i], sizingMax[i] = 0, 0 end
    for i = 1, n do
        local kind, tgt, amt = ev.kind[i], ev.tgt[i], ev.amt[i]
        if kind == V3.DMG and tgt and tgt > 0 then
            hitOrHealed[tgt] = true
            hits[tgt] = hits[tgt] or {}
            hits[tgt][#hits[tgt] + 1] = amt or 0
            sizingDeficit[tgt] = (sizingDeficit[tgt] or 0) + (amt or 0)
            if sizingDeficit[tgt] > (sizingMax[tgt] or 0) then sizingMax[tgt] = sizingDeficit[tgt] end
        elseif kind == V3.HEAL and tgt and tgt > 0 then
            hitOrHealed[tgt] = true
            sizingDeficit[tgt] = math.max(0, (sizingDeficit[tgt] or 0) - (amt or 0))
        end
    end
    return hits, sizingMax, hitOrHealed
end

--------------------------------------------------------------------------------
-- T17b, the planner's amendment to ruling 1: a party member's max for coaching
-- comes from OTHER recordings of the same name (and level), never from the
-- fight being coached -- so a burst late in the fight cannot change what the
-- plan does before it. Leave-one-out, as Engine/Intuition.lua's IN:Build: the
-- exclusion is a required argument. Returns value, source, count -- a plain
-- max in any other recording ("recorded", the largest), else
-- SM.EstimateMaxHP over those recordings' own sizing, one per recording
-- ("others") -- or nil when nobody else has this person. An entry that took
-- no damage in its recording carries no sizing and is not counted.
--------------------------------------------------------------------------------
function SM.PartyMaxFromOthers(recs, excludeID, name, level)
    if excludeID == nil then error("SM.PartyMaxFromOthers: excludeID is required", 2) end
    if type(name) ~= "string" or type(recs) ~= "table" then return nil end
    local plainBest, plainN = nil, 0
    local sizings, allHits, estN = {}, {}, 0
    for _, r in ipairs(recs) do
        if type(r) == "table" and r.id ~= excludeID and r.v == STREAM.V and type(r.roster) == "table" then
            local hits, sizingMax
            for i, e in ipairs(r.roster) do
                if type(e) == "table" and e.name == name
                    and not (type(level) == "number" and type(e.level) == "number" and e.level ~= level) then
                    if e.maxSecret == false and type(e.maxHP) == "number" and e.maxHP > 0 then
                        plainN = plainN + 1
                        if plainBest == nil or e.maxHP > plainBest then plainBest = e.maxHP end
                    else
                        if not hits then hits, sizingMax = SizeRec(r) end
                        if hits[i] and #hits[i] > 0 then
                            estN = estN + 1
                            sizings[#sizings + 1] = sizingMax[i] or 0
                            for _, a in ipairs(hits[i]) do allHits[#allHits + 1] = a end
                        end
                    end
                end
            end
        end
    end
    if plainBest ~= nil then return plainBest, "recorded", plainN end
    if estN > 0 then return SM.EstimateMaxHP(sizings, allHits), "others", estN end
    return nil
end

-- The one chooser both ReconstructHp and SM.ScenarioV3 use, so the two never
-- disagree: plain in this recording -> that; else, when the recording has an
-- id and other recordings know this person -> theirs; else this fight's own
-- estimate as before. `others` nil means MD.cdb.recordings ({} for none).
local function ChooseMaxes(rec, others, hits, sizingMax)
    if others == nil then others = MD.cdb and MD.cdb.recordings end
    local roster = rec.roster or {}
    local maxHP, maxEstimated, maxSource, anyEstimated = {}, {}, {}, false
    for i = 1, #roster do
        local r = roster[i] or {}
        if r.maxSecret == false and type(r.maxHP) == "number" and r.maxHP > 0 then
            maxHP[i], maxEstimated[i], maxSource[i] = r.maxHP, false, "recorded"
        else
            local v, src
            if rec.id ~= nil and type(others) == "table" then
                local v1, src1 = SM.PartyMaxFromOthers(others, rec.id, r.name, r.level)
                if v1 ~= nil then v, src = v1, src1 end
            end
            if v == nil then
                v, src = SM.EstimateMaxHP({ sizingMax[i] or 0 }, hits[i] or {}), "this fight"
            end
            maxHP[i], maxEstimated[i], maxSource[i] = v, true, src
            anyEstimated = true
        end
    end
    return maxHP, maxEstimated, maxSource, anyEstimated
end

--------------------------------------------------------------------------------
-- ReconstructHp: the shared arithmetic behind both SM.ScenarioV3's own
-- `recordedHp` field and SM.RecordedHp below (T16a) -- a target's stand-in
-- max (Planner ruling 1) and its health on a 2s grid from every landed amount,
-- own and foreign alike. Pure, no kit needed: neither computation reads which
-- heals were own. T66 (P22, review A18): the ONE copy -- ScenarioV3 used to
-- carry the grid loop a second time; it now reads this, and the sizing
-- (`hits`, `hitOrHealed`) comes back with it.
--------------------------------------------------------------------------------
local function ReconstructHp(rec, others)
    local roster = rec.roster or {}
    local nT = #roster
    local ev, n = rec.ev or {}, rec.n or 0

    local hits, sizingMax, hitOrHealed = SizeRec(rec)
    local maxHP, maxEstimated, maxSource, anyEstimated = ChooseMaxes(rec, others, hits, sizingMax)

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

    return { maxHP = maxHP, maxEstimated = maxEstimated, maxSource = maxSource,
             anyEstimated = anyEstimated, t = gridT, hp = hpOut, max = maxOut,
             hits = hits, hitOrHealed = hitOrHealed }
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
function SM.RecordedHp(rec, kit, others)
    if not rec or not rec.roster then return nil end
    local h = ReconstructHp(rec, others)
    return { t = h.t, hp = h.hp, max = h.max }
end

--------------------------------------------------------------------------------
-- SM.ScenarioV3: a v3 stream -> the v2 scenario shape, plus recordedHp,
-- attribution and maxEstimated (Files table). T66 (P22, review A18): also
-- `ownHeals` (the attribution's own set: HEAL event index -> true), so gate 8
-- reads what this scenario attributed instead of attributing a second time,
-- and `reconstructed = true` -- the scenario's own word that its health is
-- rebuilt, which Engine/SimPlanner.lua and UI/ReplayWindow.lua read instead
-- of testing the stream's version by number. `recordedHp` carries `max`
-- too, in `rec.hp`'s shape.
--------------------------------------------------------------------------------
function SM.ScenarioV3(rec, kit, others)
    local K = SM.K -- the engine's own numbering (FHEAL = 2, etc.)
    local roster = rec.roster or {}
    local nT = #roster
    local trackedSet = {}
    for _, idx in ipairs(rec.tracked or {}) do trackedSet[idx] = true end

    local ownSet, attrCounts, replayedSet = SM.AttributeHeals(rec, kit)

    local ev, n = rec.ev or {}, rec.n or 0
    local outEv = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    local function Push(t, kind, tgt, amt, x)
        local m = #outEv.t + 1
        outEv.t[m], outEv.kind[m], outEv.tgt[m], outEv.amt[m], outEv.x[m] = t, kind, tgt, amt, x
    end

    -- Per target: every hit (for danger/EstimateMaxHP), whether it was ever
    -- hit or healed (for `tracked`), the running deficit that sizes a
    -- stand-in max (Planner ruling 1), the max chosen from it (Planner ruling
    -- 1 and its T17b amendment: a plain max stays plain; a secret one comes
    -- from other recordings of that person, else is stood in for from this
    -- fight) and the health on the grid -- all ReconstructHp's.
    local h = ReconstructHp(rec, others)
    local hits, hitOrHealed = h.hits, h.hitOrHealed
    local maxHP, maxEstimated, maxSource, anyEstimated = h.maxHP, h.maxEstimated, h.maxSource, h.anyEstimated

    for i = 1, n do
        local kind, tgt, amt, x = ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i]
        if kind == V3.DMG then
            Push(ev.t[i], K.DMG, tgt, amt, x)
        elseif kind == V3.HEAL then
            if replayedSet[i] then
                -- T101: an own heal no kit entry claims, replayed as recorded
                Push(ev.t[i], K.OWNREPLAY, tgt, amt, x)
            elseif not ownSet[i] then
                Push(ev.t[i], K.FHEAL, tgt, amt, x)
            end
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

    -- `danger` is the SCORE's line (the whole fight's biggest hit); a plan
    -- decides on SM.DangerLine, the biggest hit so far (T20, review R6).
    local dangerHits = (MD.db and MD.db.simDangerHits) or 1
    local priorStore = others
    if priorStore == nil then priorStore = MD.cdb and MD.cdb.recordings end
    local targets = {}
    local casterIdx = CasterOf(rec)   -- T101 (4.5): whom a self-and-target heal also reaches
    for i = 1, nT do
        local r = roster[i] or {}
        local list = hits[i]
        local danger
        if list and #list > 0 and maxHP[i] > 0 then
            local biggest = 0
            for _, v in ipairs(list) do if v > biggest then biggest = v end end
            danger = math.min(1, (biggest * dangerHits) / maxHP[i])
        end
        -- T20b: the biggest hit that person (same name, same level) took in
        -- OTHER recordings, over this scenario's max for them. Never this
        -- recording (by id); no id, no prior. `if`, not `and/or`: two returns.
        local dangerPrior
        if rec.id ~= nil and maxHP[i] > 0 then
            local hit = SM.DangerHitFromOthers(priorStore, rec.id, r.name, r.level)
            if hit ~= nil then dangerPrior = math.min(1, hit * dangerHits / maxHP[i]) end
        end
        targets[i] = {
            name = r.name, role = r.role, maxHP = maxHP[i], maxEstimated = maxEstimated[i],
            maxSource = maxSource[i], danger = danger, dangerPrior = dangerPrior, hp0 = maxHP[i],
            tracked = (trackedSet[i] == true) and (hitOrHealed[i] == true) or false,
            caster = (i == casterIdx) or nil,
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
            local entry = { target = a.tgt, spellID = a.spellId, stacks = a.stacks, remaining = a.remaining }
            -- R29: the engine ticks it where the claims above do.
            local e = kit and kit.caster and kit.caster[a.spellId]
            if e and e.tickPeriod then
                entry.ticksLeft, entry.firstTick = PrepullTicks(a.remaining or 0, e.tickPeriod)
            end
            auras[#auras + 1] = entry
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
    -- starting at full at the pull (Facts) -- ReconstructHp's grid.
    local dur = rec.dur or 0
    local gridT = h.t

    -- The tracked targets whose max had to come from this very fight: the
    -- plan coached on this scenario is then not causal (T17b), and says so.
    local maxForesees = {}
    for i = 1, nT do
        if targets[i].tracked and targets[i].maxSource == "this fight" then
            maxForesees[#maxForesees + 1] = targets[i].name or "?"
        end
    end
    if #maxForesees == 0 then maxForesees = nil end

    return {
        dur = dur, pool = rec.pool or 0,
        maxForesees = maxForesees,
        initial = initial, energizeAssumed = false,
        targets = targets, ev = outEv, rates = rates, fixed = fixed,
        incoming = {}, threat = {}, -- secret by policy (Facts, plan §5)
        sampleT = mn.t, hpSampleT = gridT, kit = kit,
        floor = (MD.db and MD.db.simFloor) or 0.30,
        script = script,
        recordedHp = { t = gridT, hp = h.hp, max = h.max },
        reconstructed = true,
        attribution = attrCounts,
        ownHeals = ownSet,
        maxEstimated = anyEstimated,
    }
end

--------------------------------------------------------------------------------
-- The v3 road, registered (T66, P22, review A18) where this file used to wrap
-- SM.ScenarioFromRecording: Engine/SimModel.lua picks the builder by the
-- stream's version and forwards every argument after `kit` as it came (T46:
-- T20b's `others` store). The reconstruction answers SM.RecordedHealth for a
-- v3 stream, which never carries `rec.hp`.
--------------------------------------------------------------------------------
SM.scenarioBuilders[STREAM.V] = function(rec, kit, ...) return SM.ScenarioV3(rec, kit, ...) end
SM.healthReconstructors[STREAM.V] = function(rec) return SM.RecordedHp(rec) end

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
