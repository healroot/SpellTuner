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

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
