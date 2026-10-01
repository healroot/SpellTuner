-- tools/run.sh tools/scenariocheck.lua
--
-- T13d (docs/tasks/T13d-scenario-v3.md): a v3 stream (T13) becomes a
-- scenario of the engine's own shape (Modules/SpellTuner_Replay/
-- Scenario_Forever.lua). Forever only.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-95s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
S.crit[4] = 0 -- zero Nature crit: DirectAmount(e) == e.direct exactly (critMode = "ev")

MD:SetModule("SpellTuner_Replay", true) -- loads Kit_Forever.lua and Scenario_Forever.lua
local SM = MD.SimModel
local kit = MD.RankMath:SpellKit() -- also builds MD.SpellData.spells, which ScenarioV3 reads

local buildFixture = dofile(here .. "/foreverfixture.lua")

local function FindEvent(sc, kind, pred)
    local ev = sc.ev
    for i = 1, #ev.t do
        if ev.kind[i] == kind then
            local row = { t = ev.t[i], tgt = ev.tgt[i], amt = ev.amt[i], x = ev.x[i] }
            if not pred or pred(row) then return row end
        end
    end
    return nil
end
local function CountEvent(sc, kind)
    local ev, c = sc.ev, 0
    for i = 1, #ev.t do if ev.kind[i] == kind then c = c + 1 end end
    return c
end

--------------------------------------------------------------------------------
-- 1: a v3 stream becomes a scenario of the engine's shape, and a v2 one
--    takes the old road
--------------------------------------------------------------------------------
local rec = buildFixture()
local sc = SM.ScenarioFromRecording(rec, kit)

local shapeOk = type(sc) == "table"
    and type(sc.dur) == "number" and type(sc.pool) == "number"
    and type(sc.initial) == "table" and sc.initial.form == "caster"
    and type(sc.initial.auras) == "table" and type(sc.initial.known) == "table"
    and type(sc.targets) == "table" and #sc.targets == 2
    and type(sc.ev) == "table" and type(sc.ev.t) == "table"
    and type(sc.rates) == "table" and type(sc.fixed) == "table"
    and type(sc.incoming) == "table" and #sc.incoming == 0
    and type(sc.threat) == "table" and #sc.threat == 0
    and sc.sampleT == rec.mana.t and type(sc.hpSampleT) == "table"
    and sc.kit == kit and type(sc.floor) == "number"
    and type(sc.script) == "table"
    and type(sc.recordedHp) == "table" and type(sc.recordedHp.t) == "table" and type(sc.recordedHp.hp) == "table"
    and type(sc.attribution) == "table"
    and type(sc.maxEstimated) == "boolean"

local v2rec = {
    dur = 10, pool = 100, roster = { { name = "P", maxHP = 100, maxSecret = false } }, tracked = { 1 },
    ev = { t = { 1 }, kind = { SM.K.DMG }, tgt = { 1 }, amt = { 10 }, x = { 0 } }, n = 1,
    mana = { t = {}, base = {}, cast = {} }, initial = { mana = 100, form = "caster" },
}
local v2sc = SM.ScenarioFromRecording(v2rec, kit)
local v2Ok = type(v2sc) == "table" and v2sc.recordedHp == nil and v2sc.attribution == nil
    and v2sc.dur == 10 and #v2sc.ev.t == 1 and v2sc.ev.kind[1] == SM.K.DMG
    and v2sc.targets[1].maxHP == 100

check("a v3 stream becomes a scenario of the engine's shape, and a v2 one takes the old road",
    shapeOk and v2Ok, string.format("shapeOk=%s v2Ok=%s", tostring(shapeOk), tostring(v2Ok)))

--------------------------------------------------------------------------------
-- 2: a heal landing with an own direct cast on its target is own; the
--    others are foreign
--------------------------------------------------------------------------------
do
    local own, counts = SM.AttributeHeals(rec, kit)
    -- HEAL event 3 in the stream (index order: DMG, CASTSTART, OWNCAST, HEAL@t=2)
    local directIdx
    for i = 1, rec.n do
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 2 and rec.ev.tgt[i] == 1 then directIdx = i end
    end
    local foreignIdx
    for i = 1, rec.n do
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 2.5 and rec.ev.tgt[i] == 2 then foreignIdx = i end
    end
    check("a heal landing with an own direct cast on its target is own; the others are foreign",
        directIdx and own[directIdx] == true and foreignIdx and own[foreignIdx] ~= true
        and counts.ownDirect == 1,
        string.format("own[direct]=%s own[foreign]=%s ownDirect=%s",
            tostring(directIdx and own[directIdx]), tostring(foreignIdx and own[foreignIdx]), tostring(counts.ownDirect)))
end

--------------------------------------------------------------------------------
-- 3: a HoT's ticks by cadence are own; a heal between them is foreign
--------------------------------------------------------------------------------
do
    local own = SM.AttributeHeals(rec, kit)
    local tick1, between, tick2
    for i = 1, rec.n do
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 10 then tick1 = i end
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 11.5 then between = i end
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 13 then tick2 = i end
    end
    check("a HoT's ticks by cadence are own; a heal between them is foreign",
        tick1 and own[tick1] == true and tick2 and own[tick2] == true
        and between and own[between] ~= true,
        string.format("tick1=%s between=%s tick2=%s",
            tostring(tick1 and own[tick1]), tostring(between and own[between]), tostring(tick2 and own[tick2])))
end

--------------------------------------------------------------------------------
-- 4: a HoT recast on the same target ends the first one's ticks
--------------------------------------------------------------------------------
do
    local own = SM.AttributeHeals(rec, kit)
    -- Cast C (the recast, at t=17.5, OFF cast B's own tick boundary at t=19)
    -- claims cast B's own continuing cadence (t=19, 22, 25, 28 -- what
    -- Engine/SimModel.lua's own tick timer, unreset by a refresh, actually
    -- produces -- Lead review 1). The foreign heal landing at the recast's
    -- own instant (17.5) is neither cadence's tick and stays foreign.
    local atRecast, at19
    for i = 1, rec.n do
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 17.5 then atRecast = i end
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 19 then at19 = i end
    end
    -- The recast's OWN cadence (Planner ruling 2's own words, cast + 3k) is
    -- also accepted -- a second, hand-built stream (a fresh foreverfixture
    -- call, override recastCadence) where the recorded ticks follow that
    -- cadence instead of the engine's kept one; both must attribute own.
    local newRec = buildFixture({ recastCadence = "new" })
    local newOwn = SM.AttributeHeals(newRec, kit)
    local at205, at235
    for i = 1, newRec.n do
        if newRec.ev.kind[i] == 15 and newRec.ev.t[i] == 20.5 then at205 = i end
        if newRec.ev.kind[i] == 15 and newRec.ev.t[i] == 23.5 then at235 = i end
    end

    -- Lead review 2: a chain of THREE applications (opts.chain) -- every
    -- recast's ticks must trace back to the FIRST application's cadence,
    -- not the immediately-replaced one's, however many recasts deep.
    local chainRec = buildFixture({ chain = true })
    local chainOwn = SM.AttributeHeals(chainRec, kit)
    local chainTimes = { 10, 13, 16, 19, 20.5, 22, 25, 26.5, 28, 29.5 }
    local chainAllOwn = true
    for _, ct in ipairs(chainTimes) do
        local idx
        for i = 1, chainRec.n do
            if chainRec.ev.kind[i] == 15 and chainRec.ev.t[i] == ct then idx = i end
        end
        if not (idx and chainOwn[idx] == true) then chainAllOwn = false end
    end

    local ok = atRecast and own[atRecast] ~= true and at19 and own[at19] == true and rec.ev.amt[at19] == 14
        and at205 and newOwn[at205] == true and at235 and newOwn[at235] == true
        and chainAllOwn
    check("a HoT recast on the same target ends the first one's ticks",
        ok, string.format("atRecast=%s at19=%s amt19=%s at205(new cadence)=%s at235(new cadence)=%s chainAllOwn=%s",
            tostring(atRecast and own[atRecast]), tostring(at19 and own[at19]), tostring(at19 and rec.ev.amt[at19]),
            tostring(at205 and newOwn[at205]), tostring(at235 and newOwn[at235]), tostring(chainAllOwn)))
end

--------------------------------------------------------------------------------
-- 5: a pre-pull HoT from the out-of-combat read ticks from the start and
--    its ticks are own
--------------------------------------------------------------------------------
do
    local own, counts = SM.AttributeHeals(rec, kit)
    local t3, t6
    for i = 1, rec.n do
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 3 then t3 = i end
        if rec.ev.kind[i] == 15 and rec.ev.t[i] == 6 then t6 = i end
    end
    check("a pre-pull HoT from the out-of-combat read ticks from the start and its ticks are own",
        t3 and own[t3] == true and t6 and own[t6] == true and counts.prepull == 2,
        string.format("t3=%s t6=%s prepull=%s", tostring(t3 and own[t3]), tostring(t6 and own[t6]),
            tostring(counts.prepull)))
end

--------------------------------------------------------------------------------
-- 6: health is a deficit from every landed amount, floored at full, sampled
--    every two seconds
--------------------------------------------------------------------------------
do
    local hp2 = sc.recordedHp.hp[2]
    local t = sc.recordedHp.t
    -- maxHP[2] is estimated: the largest deficit lived through (692, at
    -- t=4: 500 dmg - 100 foreign heal - 8 tick + 300 dmg) plus the biggest
    -- single hit (500) = 1192 (Planner ruling 1).
    local expectMax = 1192
    local function At(time)
        for i = 1, #t do if math.abs(t[i] - time) < 1e-6 then return hp2[i] end end
        return nil
    end
    check("health is a deficit from every landed amount, floored at full, sampled every two seconds",
        At(0) == expectMax and At(2) == expectMax - 500 and At(4) == expectMax - 692
        and At(30) ~= nil and #t == #hp2 and (t[2] - t[1]) == 2,
        string.format("max=%s at0=%s at2=%s at4=%s", tostring(sc.targets[2].maxHP), tostring(At(0)), tostring(At(2)), tostring(At(4))))
end

--------------------------------------------------------------------------------
-- 7: a party member's max is the stated estimate and marked; the player's
--    is the recorded one
--------------------------------------------------------------------------------
check("a party member's max is the stated estimate and marked; the player's is the recorded one",
    sc.targets[1].maxHP == 375 and sc.targets[1].maxEstimated == false
    and sc.targets[2].maxHP == 1192 and sc.targets[2].maxEstimated == true
    and sc.maxEstimated == true,
    string.format("p1=%s,%s p2=%s,%s any=%s", tostring(sc.targets[1].maxHP), tostring(sc.targets[1].maxEstimated),
        tostring(sc.targets[2].maxHP), tostring(sc.targets[2].maxEstimated), tostring(sc.maxEstimated)))

--------------------------------------------------------------------------------
-- 8: casts the healing kit does not price are fixed points with their kind
--    from the book
--------------------------------------------------------------------------------
do
    local wrath
    for _, f in ipairs(sc.fixed) do if f[2] == 5176 then wrath = f end end
    check("casts the healing kit does not price are fixed points with their kind from the book",
        wrath ~= nil and wrath[1] == 20 and wrath[3] == 20 and wrath[4] == 2 and wrath[5] == "damage",
        string.format("wrath=%s", wrath and table.concat({ wrath[1], wrath[2], tostring(wrath[3]), wrath[4], wrath[5] }, ",") or "nil"))
end

--------------------------------------------------------------------------------
-- 9: the engine replays the scenario to the reconstructed health when the
--    kit matches the heals
--------------------------------------------------------------------------------
do
    local r = SM:Run(sc, nil, { critMode = "ev" })
    local function Compare(ti)
        local a, b = r.hpCurve[ti], sc.recordedHp.hp[ti]
        if not a or not b or #a ~= #b then return false, "length mismatch" end
        local maxHP = sc.targets[ti].maxHP
        local maxDev, sumDev = 0, 0
        for i = 1, #a do
            local d = math.abs(a[i] - b[i])
            if d > maxDev then maxDev = d end
            sumDev = sumDev + d
        end
        local meanDev = sumDev / #a
        local okMax = maxDev <= maxHP * 0.01
        local okMean = meanDev <= maxHP * 0.01
        return okMax and okMean, string.format("maxDev=%.2f meanDev=%.2f (maxHP*1%%=%.2f)", maxDev, meanDev, maxHP * 0.01)
    end
    local ok1, d1 = Compare(1)
    local ok2, d2 = Compare(2)
    check("the engine replays the scenario to the reconstructed health when the kit matches the heals",
        ok1 and ok2, string.format("t1: %s | t2: %s", d1, d2))
end

--------------------------------------------------------------------------------
-- review-replay (docs/review/2026-09-29-forever-review.md): three small v3
-- streams on the tank (roster 2), hand-built so only the claim at issue can
-- take the heal.
--------------------------------------------------------------------------------
local function MiniRec(events, auras)
    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    for i, e in ipairs(events) do
        ev.t[i], ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i] = e[1], e[2], e[3], e[4], e[5]
    end
    local mana = { t = {}, v = {}, base = {}, cast = {} }
    for t = 2, 30, 2 do
        local i = #mana.t + 1
        mana.t[i], mana.v[i], mana.base[i], mana.cast[i] = t, 1000, 69.24, 28.33
    end
    return {
        v = 3, client = "forever", id = 1757100000, zone = "Test", t0 = 0, dur = 30, pool = 1000,
        roster = {
            { name = "Healroot", guid = "Player-1", class = "DRUID", role = "HEALER",
              level = 64, maxHP = 375, maxSecret = false },
            { name = "Tank", guid = "Party-1-guid", class = "WARRIOR", role = "TANK",
              level = 64, maxHP = 2000, maxSecret = false },
        },
        tracked = { 1, 2 }, ev = ev, n = #events, mana = mana, manaModelled = true,
        deaths = {}, restriction = {}, names = {},
        initial = { mana = 1000, form = "caster", known = { HealingTouch = 5185, Rejuvenation = 1058 },
                    auras = auras or {} },
        meter = { own = 0, others = 0, bySource = {}, bySpell = {}, read = "current" },
        unreadable = 0, truncated = false, raid = false, pinned = false,
    }
end
local function HealAt(r, t)
    for i = 1, r.n do if r.ev.kind[i] == 15 and r.ev.t[i] == t then return i end end
end

--------------------------------------------------------------------------------
-- 10 (R28): Swiftmend eats the Rejuvenation, so the HoT's later tick times
--     claim nothing -- a foreign heal landing on one of them stays foreign.
--     The stub's book has no Swiftmend; one is added to a copy of the kit
--     and to the spell index for this assertion only, shaped as
--     Kit_Forever.lua builds it (type "instant", swiftmendRejuv).
--------------------------------------------------------------------------------
do
    local SMID = 18562
    local SD = MD.SpellData
    SD.spells[SMID] = { family = "Swiftmend", rank = 1 }
    local caster = setmetatable({ [SMID] = { family = "Swiftmend", type = "instant", swiftmendRejuv = 32, cast = 1.5 } },
        { __index = kit.caster })
    local smKit = { caster = caster, tree = kit.tree, crit = kit.crit }
    local r = MiniRec({
        { 1, 1, 2, 400, 0 },
        { 10, 6, 2, 0, 774 }, { 10, 3, 2, 25, 774 },
        { 13, 15, 2, 8, 0 },                         -- Rejuvenation tick 1 (own)
        { 14, 6, 2, 0, SMID }, { 14, 3, 2, 10, SMID },
        { 14, 15, 2, 24, 0 },                        -- Swiftmend's lump (own)
        { 16.1, 15, 2, 8, 0 },                       -- a priest's Renew tick: foreign
    })
    local own = SM.AttributeHeals(r, smKit)
    SD.spells[SMID] = nil
    local i13, i14, i16 = HealAt(r, 13), HealAt(r, 14), HealAt(r, 16.1)
    check("Swiftmend ends the HoT it eats: a heal on one of its later tick times is foreign (R28)",
        own[i13] == true and own[i14] == true and own[i16] ~= true,
        string.format("tick=%s swiftmend=%s after=%s", tostring(own[i13]), tostring(own[i14]), tostring(own[i16])))
end

--------------------------------------------------------------------------------
-- 11 (R29): a pre-pull HoT with 10 s left ticks at 1, 4, 7 and 10 --
--     ceil(10/3) ticks counted back from its expiry, not a rounded 3 -- and
--     the engine ticks it there too, so the replay still reaches the
--     reconstructed health.
--------------------------------------------------------------------------------
do
    local r = MiniRec({
        { 0.5, 1, 2, 400, 0 },
        { 1, 15, 2, 8, 0 }, { 4, 15, 2, 8, 0 }, { 7, 15, 2, 8, 0 }, { 10, 15, 2, 8, 0 },
    }, { { token = "party1", spellId = 774, remaining = 10, stacks = 1, tgt = 2 } })
    local own, counts = SM.AttributeHeals(r, kit)
    local allOwn = own[HealAt(r, 1)] and own[HealAt(r, 4)] and own[HealAt(r, 7)] and own[HealAt(r, 10)]
    local sc2 = SM.ScenarioFromRecording(r, kit)
    local run = SM:Run(sc2, nil, { critMode = "ev" })
    local a, b = run.hpCurve[2], sc2.recordedHp.hp[2]
    local maxDev = 0
    for i = 1, math.min(#a, #b) do
        local d = math.abs(a[i] - b[i]); if d > maxDev then maxDev = d end
    end
    check("a pre-pull HoT's first remaining tick is own, and the engine ticks it too (R29)",
        allOwn == true and counts.prepull == 4 and #a == #b and maxDev < 1e-6,
        string.format("allOwn=%s prepull=%s maxDev=%s", tostring(allOwn), tostring(counts.prepull), tostring(maxDev)))
end

--------------------------------------------------------------------------------
-- 12 (R30): a foreign HoT tick landing in the window just before an own
--     Healing Touch's heal does not take the Healing Touch's claim -- the
--     heal nearest the cast's own value does.
--------------------------------------------------------------------------------
do
    local r = MiniRec({
        { 1, 1, 2, 400, 0 },
        { 8.5, 6, 2, 0, 5185 }, { 10, 3, 2, 25, 5185 },
        { 9.8, 15, 2, 9, 0 },                        -- a priest's Renew tick: foreign
        { 10.05, 15, 2, 47.5, 0 },                   -- the Healing Touch (own)
    })
    local own, counts = SM.AttributeHeals(r, kit)
    local iF, iHT = HealAt(r, 9.8), HealAt(r, 10.05)
    check("a foreign heal before an own direct heal does not take its claim (R30)",
        own[iHT] == true and own[iF] ~= true and counts.ownDirect == 1 and counts.foreign == 1,
        string.format("ht=%s foreign=%s ownDirect=%s foreignCount=%s", tostring(own[iHT]), tostring(own[iF]),
            tostring(counts.ownDirect), tostring(counts.foreign)))
end

--------------------------------------------------------------------------------
-- 13, 14 (T49, P5, B15): the recorder keeps a cross-realm member's `name`
--     bare and adds `realm` beside it, so a recording made before the realm
--     existed and one made after still name the same person: both are found
--     by SM.PartyMaxFromOthers and by SM.DangerHitFromOthers (the count says
--     both matched, the value that the newer one's bigger number was read).
--------------------------------------------------------------------------------
do
    local coached = MiniRec({ { 1, 1, 2, 300, 0 } })
    coached.id = 100
    local old = MiniRec({ { 1, 1, 2, 400, 0 } })          -- before T49: a bare "Tank", no realm
    old.id = 200
    local new = MiniRec({ { 1, 1, 2, 600, 0 } })          -- after: "Tank" with its realm beside it
    new.id = 300
    new.roster[2].realm = "X"
    new.roster[2].maxHP = 2500
    local recs = { coached, old, new }
    local mx, how, n = SM.PartyMaxFromOthers(recs, coached.id, "Tank", 64)
    check("an old bare-name recording and a new one with a realm are one person for the party max (B15)",
        mx == 2500 and how == "recorded" and n == 2,
        string.format("max=%s via=%s n=%s", tostring(mx), tostring(how), tostring(n)))
    local hit, hn = SM.DangerHitFromOthers(recs, coached.id, "Tank", 64)
    check("...and for the danger prior (B15)", hit == 600 and hn == 2,
        string.format("hit=%s n=%s", tostring(hit), tostring(hn)))
end

--------------------------------------------------------------------------------
-- T96 (docs/SPEC-next.md 2.1, decision 11): the engine runs on the KIT's
-- profile, never the logged-in player's, and a channel lands its ticks.
--------------------------------------------------------------------------------
-- A copy of the kit with extra caster entries (and their ids in the spell
-- index, as check 10 does), handed back with a function that undoes the index.
local function KitWith(entries, profile)
    local SD = MD.SpellData
    local extra = {}
    for id, e in pairs(entries) do extra[id] = e; SD.spells[id] = { family = e.family, rank = e.rank } end
    local caster = setmetatable(extra, { __index = kit.caster })
    local k = { caster = caster, tree = kit.tree, crit = kit.crit, profile = profile }
    return k, function() for id in pairs(entries) do SD.spells[id] = nil end end
end
local function HotEvents(trace)
    local out = {}
    for i = 1, trace.nEv do
        if trace.ev.kind[i] == SM.TK.HOT then
            out[#out + 1] = string.format("%g:%d", trace.ev.t[i], trace.ev.a[i])
        end
    end
    return table.concat(out, " ")
end

-- 15: a recorded Tranquility lands its ticks -- shaped as Kit_Forever.lua
--     builds it (channel: 98 every 2 s for 10 s) -- on its target, the
--     attribution claims them as the healer's own (so they are not replayed a
--     second time as foreign healing), the replay reaches the reconstructed
--     health, and a later cast breaks the channel.
do
    local TQ = 90203
    local tq = { family = "Tranquility", rank = 1, type = "channel", gcd = 1.5, cost = 375,
                 cast = 0, castBase = 0, channelTick = 98, channelTicks = 5, tickPeriod = 2 }
    local tqKit, undo = KitWith({ [TQ] = tq })
    local r = MiniRec({
        { 1, 1, 2, 1500, 0 },
        { 3, 3, 2, 375, TQ },
        { 5, 15, 2, 98, 0 }, { 7, 15, 2, 98, 0 }, { 9, 15, 2, 98, 0 }, { 11, 15, 2, 98, 0 }, { 13, 15, 2, 98, 0 },
    })
    local _, counts = SM.AttributeHeals(r, tqKit)
    local sc2 = SM.ScenarioFromRecording(r, tqKit)
    local run = SM:Run(sc2, nil, { critMode = "ev" })
    local healed = run.healByFamily and run.healByFamily.Tranquility or 0
    local a, b = run.hpCurve[2], sc2.recordedHp.hp[2]
    local maxDev = 0
    for i = 1, math.min(#a, #b) do
        local d = math.abs(a[i] - b[i]); if d > maxDev then maxDev = d end
    end
    -- broken at t = 8 by a Healing Touch: the ticks at 5 and 7 only
    local broken = MiniRec({
        { 1, 1, 2, 1500, 0 },
        { 3, 3, 2, 375, TQ },
        { 5, 15, 2, 98, 0 }, { 7, 15, 2, 98, 0 },
        { 8, 3, 2, 25, 5185 }, { 8, 15, 2, 47.5, 0 },
    })
    local scB = SM.ScenarioFromRecording(broken, tqKit)
    local runB = SM:Run(scB, nil, { critMode = "ev" })
    local healedB = runB.healByFamily and runB.healByFamily.Tranquility or 0
    undo()
    check("T96: a recorded Tranquility lands its ticks as own; a later cast breaks it (decision 11)",
        healed == 5 * 98 and counts.ownTick == 5 and counts.foreign == 0
        and #a == #b and maxDev < 1e-6 and healedB == 2 * 98,
        string.format("healed=%s ownTick=%s foreign=%s maxDev=%s broken=%s", tostring(healed),
            tostring(counts.ownTick), tostring(counts.foreign), tostring(maxDev), tostring(healedB)))
end

-- A test class whose two HoTs sit in the OPPOSITE slots to the druid's
-- fallback by type (its hybrid in slot 1, its HoT in slot 2), registered once.
local P = MD.Profiles
if not P.byClass.T96HEALER then
    P.Register("T96HEALER", {
        label = "Test healer", caps = { clock = true },
        families = {
            Riptide = { names = { "Riptide" }, kit = "hybrid", hot = true },
            Renew = { names = { "Renew" }, kit = "hot", hot = true },
        },
        hotSlots = { "Riptide", "Renew" },
    })
end
local RIPTIDE, RENEW = 96001, 96002
local riptide = { family = "Riptide", rank = 1, type = "hybrid", gcd = 1.5, cost = 30, cast = 0, castBase = 0,
                  direct = 50, directCrit = 0, tick = 10, ticks = 4, tickPeriod = 3, duration = 12 }
local renew = { family = "Renew", rank = 1, type = "hot", gcd = 1.5, cost = 30, cast = 0,
                tick = 12, ticks = 5, tickPeriod = 3, duration = 15 }

-- 16: the hot map (Scenario_Forever's and the engine's) is the kit's profile's
do
    local testKit = { caster = { [RIPTIDE] = riptide, [RENEW] = renew }, tree = {}, crit = 0, profile = "T96HEALER" }
    local plain = { caster = { [RIPTIDE] = riptide, [RENEW] = renew }, tree = {}, crit = 0 }
    local ok1 = SM.HotSlots ~= nil and SM.HotFamilyOf ~= nil
    local slots = ok1 and SM.HotSlots(testKit)
    local druid = ok1 and SM.HotSlots(kit)
    local fam = ok1 and SM.HotFamilyOf(testKit, riptide)
    local famR = ok1 and SM.HotFamilyOf(testKit, renew)
    local famPlainR = ok1 and SM.HotFamilyOf(plain, riptide)
    local regrowthLike = { family = "Regrowth", type = "hybrid" }
    check("T96: the hot map is the kit's profile's; a kit naming none is the druid's",
        ok1 and slots.name[1] == "Riptide" and slots.name[2] == "Renew"
        and slots.index.Riptide == 1 and slots.index.Renew == 2
        and fam == "Riptide" and famR == "Renew" and famPlainR == "Regrowth"
        and druid.index.Rejuvenation == SM.HOT_INDEX.Rejuvenation
        and druid.index.Regrowth == SM.HOT_INDEX.Regrowth and druid.index.Lifebloom == SM.HOT_INDEX.Lifebloom
        and SM.HotFamilyOf(kit, regrowthLike) == "Regrowth"
        -- T101: the hot map; the slots table itself also carries the kit's
        -- own extra families (Riptide, Renew: SM.HotSlots(kit).extras)
        and SM.HotSlots(plain).index == SM.HotSlots({}).index
        and MD.Profiles.ForKit(plain) == MD.Profiles.Get("DRUID"),
        string.format("slots=%s,%s riptide=%s renew=%s plainRiptide=%s", tostring(slots and slots.name[1]),
            tostring(slots and slots.name[2]), tostring(fam), tostring(famR), tostring(famPlainR)))
end

-- 17: a recording replayed with a kit whose profile is the test class takes
--     that class's slots -- Riptide in 1, Renew in 2 -- while the logged-in
--     profile is the druid's; the same entries in a kit naming no profile take
--     the druid's (hybrid 2, hot 1). The replay's state machine names them.
do
    local loggedIn = MD.ClassProfile
    local testKit, undo = KitWith({ [RIPTIDE] = riptide, [RENEW] = renew }, "T96HEALER")
    local plainKit = KitWith({ [RIPTIDE] = riptide, [RENEW] = renew })
    local r = MiniRec({
        { 1, 1, 2, 1500, 0 },
        { 2, 3, 2, 30, RIPTIDE },
        { 4, 3, 2, 30, RENEW },
    })
    local scT = SM.ScenarioFromRecording(r, testKit)
    local runT = SM:Run(scT, nil, { critMode = "ev", trace = { dt = 0.5 } })
    local hotsT = HotEvents(runT.trace)
    local st = MD.ReplayTrace.New(runT.trace, scT)
    st:Seek(5)
    local named = st.HotFamily and st:HotFamily(1) == "Riptide" and st:HotFamily(2) == "Renew"
        and st:Hot(2, 1) ~= nil and st:Hot(2, 2) ~= nil
    local scP = SM.ScenarioFromRecording(r, plainKit)
    local runP = SM:Run(scP, nil, { critMode = "ev", trace = { dt = 0.5 } })
    local hotsP = HotEvents(runP.trace)
    undo()
    check("T96: a test class's kit replays in its own slots while the druid is logged in",
        loggedIn ~= nil and loggedIn == MD.Profiles.Get("DRUID") and MD.ClassProfile == loggedIn
        and hotsT == "2:1 4:2" and hotsP == "2:2 4:1" and named == true,
        string.format("loggedIn=%s test=[%s] plain=[%s] named=%s", tostring(loggedIn and loggedIn.class),
            hotsT, hotsP, tostring(named)))
end

--------------------------------------------------------------------------------
-- T101 (docs/SPEC-next.md 4.2 P2, 4.5): a heal that reaches several targets
-- claims one heal per target it reaches, all at the same instant; and an own
-- heal no kit entry claims is replayed as recorded -- the healer's, not
-- somebody else's (principle 8).
--------------------------------------------------------------------------------
-- MiniRec's two plus a third party member (a rogue), every one tracked.
local function MiniRec3(events)
    local r = MiniRec(events)
    r.roster[3] = { name = "Rogue", guid = "Party-2-guid", class = "ROGUE", role = "DAMAGER",
                    level = 64, maxHP = 1500, maxSecret = false }
    r.tracked = { 1, 2, 3 }
    return r
end

-- 18: one Prayer of Healing (a `group` entry, shaped as Kit_Forever.lua builds
--     it from the book) cast on the tank: the three heals landing at its
--     success, one on each party member, are three same-instant claims -- all
--     own, none foreign -- and the replay heals the three of them.
do
    local PH = 96101
    local poh = { family = "PrayerOfHealing", rank = 1, type = "group", gcd = 1.5, cost = 400, cast = 3,
                  castBase = 3, direct = 300, directCrit = 0 }
    local pohKit, undo = KitWith({ [PH] = poh })
    local r = MiniRec3({
        { 1, 1, 1, 350, 0 }, { 1, 1, 2, 500, 0 }, { 1, 1, 3, 400, 0 },
        { 5, 6, 2, 0, PH }, { 8, 3, 2, 400, PH },
        { 8, 15, 1, 300, 0 }, { 8, 15, 2, 300, 0 }, { 8, 15, 3, 300, 0 },
        { 9, 15, 2, 120, 0 },                           -- somebody else's heal
    })
    local own, counts = SM.AttributeHeals(r, pohKit)
    local sc3 = SM.ScenarioFromRecording(r, pohKit)
    local run = SM:Run(sc3, nil, { critMode = "ev" })
    local healed = run.healByFamily and run.healByFamily.PrayerOfHealing or 0
    local fheals = CountEvent(sc3, SM.K.FHEAL)
    local ownAt8 = 0
    for i = 1, r.n do if r.ev.kind[i] == 15 and r.ev.t[i] == 8 and own[i] then ownAt8 = ownAt8 + 1 end end
    undo()
    check("T101: three same-instant claims for one PoH",
        counts.own == 3 and counts.ownDirect == 3 and counts.foreign == 1 and ownAt8 == 3
        and fheals == 1 and math.abs(healed - 900) < 1e-6,
        string.format("own=%s direct=%s foreign=%s at8=%d fheals=%d healed=%s", tostring(counts.own),
            tostring(counts.ownDirect), tostring(counts.foreign), ownAt8, fheals, tostring(healed)))
end

-- 19: a cast of a heal the kit does not carry (a heal on the caster only --
--     Desperate Prayer's reach, which no kit type models) is the healer's
--     own: its heal is replayed exactly as recorded (SM.K.OWNREPLAY, never a
--     foreign heal), counted as own, and the engine lands it.
do
    local DP = 96102
    S.AddSpell(DP, "Desperate Prayer", "Rank 1",
        function() return "Instantly heals the caster for 300 to 340." end, { cast = 0, cost = 0, level = 10 })
    MD.Book:MarkDirty()
    local live = MD.RankMath:SpellKit()
    local inKit = live.caster[DP] ~= nil or MD.SpellData.spells[DP] ~= nil
    local r = MiniRec({
        { 1, 1, 1, 330, 0 },
        { 5, 3, 1, 0, DP },
        { 5, 15, 1, 320, 0 },
    })
    local own, counts = SM.AttributeHeals(r, live)
    local sc4 = SM.ScenarioFromRecording(r, live)
    local replayed = SM.K.OWNREPLAY and FindEvent(sc4, SM.K.OWNREPLAY)
    local fheals = CountEvent(sc4, SM.K.FHEAL)
    local run = SM:Run(sc4, nil, { critMode = "ev" })
    local landed = run.healByFamily and run.healByFamily.recorded or 0
    local healIdx = HealAt(r, 5)
    check("T101: an unclaimed own heal is replayed as recorded",
        not inKit and healIdx and own[healIdx] == true and counts.recorded == 1 and counts.foreign == 0
        and replayed and replayed.amt == 320 and replayed.tgt == 1 and replayed.t == 5 and fheals == 0
        and math.abs(landed - 320) < 1e-6,
        string.format("inKit=%s own=%s recorded=%s foreign=%s replayed=%s fheals=%d landed=%s",
            tostring(inKit), tostring(healIdx and own[healIdx]), tostring(counts.recorded),
            tostring(counts.foreign), tostring(replayed and replayed.amt), fheals, tostring(landed)))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
