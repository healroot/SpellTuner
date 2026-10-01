-- tools/run.sh tools/gatecheck.lua
--
-- T14 (docs/tasks/T14-gates-v3.md): the eight gates on a v3 recording
-- (Modules/SpellTuner_Replay/Gates_Forever.lua), on tools/foreverfixture.lua
-- (the hand-built v3 stream T14, T16 and T17 all reuse). Forever only.
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

MD:SetModule("SpellTuner_Replay", true) -- loads Kit_Forever.lua, Scenario_Forever.lua, Gates_Forever.lua
local SM = MD.SimModel
local kit = MD.RankMath:SpellKit()

local buildFixture = dofile(here .. "/foreverfixture.lua")

local function ByName(v, name)
    for _, g in ipairs(v.gates) do if g.name == name then return g end end
    return nil
end

local function DeepCopy(a)
    local t = {}
    for i = 1, #a do t[i] = a[i] end
    return t
end

-- Baseline: the engine's own mana model on the default fixture, captured once
-- so the "clean fixture" tests can hand the recorded stream exactly what the
-- engine itself produces (a consistency check on a KNOWN-consistent pair,
-- rather than restating the arithmetic).
local baseRec = buildFixture()
local baseSc = SM.ScenarioFromRecording(baseRec, kit)
local baseRun = SM:Run(baseSc, nil, { critMode = "ev" })
local baseSimOwn = (baseRun.healed or 0) - ((baseRun.healByFamily and baseRun.healByFamily.foreign) or 0)
-- SM:Run reuses a pooled state table (Engine/SimModel.lua: "per-run state
-- from a reused pool slot"), so `baseRun.manaCurve` is only good until the
-- NEXT :Run call -- copied out immediately, before test 1's SM:Validate calls
-- (which call :Run themselves) can overwrite it in place.
local baseManaCurve = DeepCopy(baseRun.manaCurve)

--------------------------------------------------------------------------------
-- 1: a v3 recording is validated by the Forever gates, a v2 one by the old
--------------------------------------------------------------------------------
do
    local v3rec = buildFixture()
    local v3 = SM:Validate(v3rec, kit)
    local v3Names = {}
    for _, g in ipairs(v3.gates) do v3Names[g.name] = true end
    local v3Ok = v3 ~= nil and #v3.gates == 8 and v3Names["heals attributed"] == true
        and v3Names["mana mean"] and v3Names["mana max"] and v3Names["health curves"]
        and v3Names["no tracked death"] and v3Names["foreign healing"]
        and v3Names["model calibrated"] and v3Names["spend coverage"]

    local v2rec = {
        v = 2, dur = 10, pool = 100,
        roster = { { name = "P", maxHP = 100, maxSecret = false } }, tracked = { 1 },
        ev = { t = { 1 }, kind = { SM.K.DMG }, tgt = { 1 }, amt = { 10 }, x = { 0 } }, n = 1,
        mana = { t = {}, v = {}, base = {}, cast = {} },
        hp = { t = {}, hp = { [1] = {} }, max = { [1] = { 100 } } },
        initial = { mana = 100, form = "caster" },
        deaths = {}, foreignShare = 0,
    }
    local v2 = SM:Validate(v2rec, kit)
    local v2Names = {}
    for _, g in ipairs(v2.gates) do v2Names[g.name] = true end
    local v2Ok = v2 ~= nil and v2Names["heals attributed"] == nil and v2Names["mana curve"] ~= nil

    check("a v3 recording is validated by the Forever gates, a v2 one by the old",
        v3Ok and v2Ok, string.format("v3 gates=%d v2 has attribution=%s",
            v3 and #v3.gates or -1, tostring(v2Names["heals attributed"])))
end

--------------------------------------------------------------------------------
-- 2: the mana gates pass on a clean fixture and say the pool is modelled
--------------------------------------------------------------------------------
do
    local rec = buildFixture()
    rec.mana.v = DeepCopy(baseManaCurve)
    local v = SM:Validate(rec, kit)
    local mean, max = ByName(v, "mana mean"), ByName(v, "mana max")
    check("the mana gates pass on a clean fixture and say the pool is modelled",
        mean and mean.ok and max and max.ok
        and mean.text:find("modelled pool", 1, true) and max.text:find("modelled pool", 1, true),
        string.format("mean=%s (%s) max=%s (%s)",
            tostring(mean and mean.ok), mean and mean.text or "nil",
            tostring(max and max.ok), max and max.text or "nil"))
end

--------------------------------------------------------------------------------
-- 3: the health gate scores the reconstruction and says when a max is
--    estimated
--------------------------------------------------------------------------------
do
    local rec = buildFixture()
    local v = SM:Validate(rec, kit)
    local hc = ByName(v, "health curves")
    check("the health gate scores the reconstruction and says when a max is estimated",
        hc and hc.ok and hc.text:find("max estimated", 1, true) ~= nil,
        hc and string.format("ok=%s text=%s", tostring(hc.ok), hc.text) or "no gate")
end

--------------------------------------------------------------------------------
-- 4: foreign healing is the damage meter's share, and no meter reading fails
--    the gate
--------------------------------------------------------------------------------
do
    local passRec = buildFixture() -- default meter: own=400, others=0 -> 0%
    local vPass = SM:Validate(passRec, kit)
    local passGate = ByName(vPass, "foreign healing")

    local shareRec = buildFixture({ meter = { own = 200, others = 100, bySource = {}, bySpell = {}, read = "current" } })
    local vShare = SM:Validate(shareRec, kit)
    local shareGate = ByName(vShare, "foreign healing")

    local noneRec = buildFixture({ meter = { read = "none", why = "damage meter closed" } })
    local vNone = SM:Validate(noneRec, kit)
    local noneGate = ByName(vNone, "foreign healing")

    check("foreign healing is the damage meter's share, and no meter reading fails the gate",
        passGate and passGate.ok
        and shareGate and not shareGate.ok and math.abs(shareGate.value - (1 / 3)) < 1e-6
        and noneGate and not noneGate.ok and noneGate.text:find("no damage meter reading", 1, true) ~= nil,
        string.format("pass=%s share=%s(%s) none=%s(%s)",
            tostring(passGate and passGate.ok),
            tostring(shareGate and shareGate.ok), tostring(shareGate and shareGate.value),
            tostring(noneGate and noneGate.ok), noneGate and noneGate.text or "nil"))
end

--------------------------------------------------------------------------------
-- 5: the model is calibrated against the meter's own total, and a drift past
--    the limit fails
--------------------------------------------------------------------------------
do
    local passRec = buildFixture({ meter = { own = baseSimOwn, others = 0, bySource = {}, bySpell = {}, read = "current" } })
    local vPass = SM:Validate(passRec, kit)
    local passGate = ByName(vPass, "model calibrated")

    local driftRec = buildFixture({ meter = { own = baseSimOwn * 3, others = 0, bySource = {}, bySpell = {}, read = "current" } })
    local vDrift = SM:Validate(driftRec, kit)
    local driftGate = ByName(vDrift, "model calibrated")

    check("the model is calibrated against the meter's own total, and a drift past the limit fails",
        passGate and passGate.ok and driftGate and not driftGate.ok,
        string.format("baseSimOwn=%.1f pass=%s(%s) drift=%s(%s)", baseSimOwn,
            tostring(passGate and passGate.ok), passGate and passGate.text or "nil",
            tostring(driftGate and driftGate.ok), driftGate and driftGate.text or "nil"))
end

--------------------------------------------------------------------------------
-- 6: spend coverage counts the book's damage and utility casts as replayed
--------------------------------------------------------------------------------
do
    local rec = buildFixture()
    local v = SM:Validate(rec, kit)
    local sc = ByName(v, "spend coverage")
    -- default fixture: HealingTouch(25) + Rejuv R1(25) + Rejuv R2(40) all
    -- kit-priced (modelled); Wrath(20) is a damage spell with no kit slot,
    -- classified "damage" by the book and counted as replayed. Everything
    -- spent is accounted for.
    check("spend coverage counts the book's damage and utility casts as replayed",
        sc and sc.ok and sc.value and sc.value >= 0.99 and sc.text:find("replayed as cast", 1, true) ~= nil,
        sc and string.format("ok=%s value=%s text=%s", tostring(sc.ok), tostring(sc.value), sc.text) or "no gate")
end

--------------------------------------------------------------------------------
-- 7: the attribution gate fails when the paired own total falls short of the
--    meter, and checks the long side only when amounts are effective
--------------------------------------------------------------------------------
do
    -- Shortfall: the meter counts far more own healing than the attribution
    -- paired with a cast (own heals the attribution called foreign).
    local shortRec = buildFixture({ meter = { own = 500, others = 0, bySource = {}, bySpell = {}, read = "current" } })
    local vShort = SM:Validate(shortRec, kit)
    local shortGate = ByName(vShort, "heals attributed")

    -- Long side: the meter counts far LESS than the paired total. While
    -- SM.HEAL_AMOUNT ~= "effective" this must NOT fail -- only the shortfall
    -- is checked.
    local longRec = buildFixture({ meter = { own = 50, others = 0, bySource = {}, bySpell = {}, read = "current" } })
    local vLongUnknown = SM:Validate(longRec, kit)
    local longGateUnknown = ByName(vLongUnknown, "heals attributed")

    -- Once a heal amount is known to be effective, the same over-count fails.
    local savedHealAmount = SM.HEAL_AMOUNT
    SM.HEAL_AMOUNT = "effective"
    local vLongEffective = SM:Validate(longRec, kit)
    local longGateEffective = ByName(vLongEffective, "heals attributed")
    SM.HEAL_AMOUNT = savedHealAmount

    check("the attribution gate fails when the paired own total falls short of the meter, and checks the long side only when amounts are effective",
        shortGate and not shortGate.ok
        and longGateUnknown and longGateUnknown.ok
        and longGateUnknown.text:find("only a shortfall is checked", 1, true) ~= nil
        and longGateEffective and not longGateEffective.ok,
        string.format("short=%s(%s) longUnknown=%s(%s) longEffective=%s(%s)",
            tostring(shortGate and shortGate.ok), shortGate and shortGate.text or "nil",
            tostring(longGateUnknown and longGateUnknown.ok), longGateUnknown and longGateUnknown.text or "nil",
            tostring(longGateEffective and longGateEffective.ok), longGateEffective and longGateEffective.text or "nil"))
end

--------------------------------------------------------------------------------
-- 8: every gate text is ASCII with no bare pipe
--------------------------------------------------------------------------------
do
    local recs = {
        buildFixture(),
        buildFixture({ meter = { own = 200, others = 100, bySource = {}, bySpell = { [5185] = 250 }, read = "current" } }),
        buildFixture({ meter = { read = "none", why = "closed" } }),
        buildFixture({ meterOverridden = true }), -- meter == nil
    }
    local allAscii = true
    local offender
    for _, rec in ipairs(recs) do
        local v = SM:Validate(rec, kit)
        for _, g in ipairs(v.gates) do
            if g.text then
                if g.text:find("|", 1, true) then allAscii = false; offender = g.name .. ": " .. g.text end
                for i = 1, #g.text do
                    if g.text:byte(i) > 126 then allAscii = false; offender = g.name .. ": " .. g.text end
                end
            end
        end
    end
    check("every gate text is ASCII with no bare pipe", allAscii, offender)
end

--------------------------------------------------------------------------------
-- review-replay R27: a target excluded from the health gate whose max is the
-- stand-in says so beside its percentages (Planner ruling 1: every percentage
-- from an estimated max says "estimated"). The thresholds are pushed below
-- zero for this one call so the fixture's tank (secret max) is excluded.
--------------------------------------------------------------------------------
do
    local savedMean, savedMax = MD.db.simGateHpMean, MD.db.simGateHpMax
    MD.db.simGateHpMean, MD.db.simGateHpMax = -1, -1
    local v = SM:Validate(buildFixture(), kit)
    MD.db.simGateHpMean, MD.db.simGateHpMax = savedMean, savedMax
    local why = v.excluded[2] or ""
    check("an excluded target's health percentages say when its max is estimated (R27)",
        why:find("of max health", 1, true) ~= nil and why:find("estimated", 1, true) ~= nil,
        why)
end

--------------------------------------------------------------------------------
-- T66 (P22, review A18): the roads are a registry keyed by the stream's
-- version. A version nobody registered is refused by name on both entries --
-- never read as a v2 stream, whose numbers mean other things.
--------------------------------------------------------------------------------
do
    local rec = buildFixture()
    rec.v = 9
    local okSc, errSc = pcall(SM.ScenarioFromRecording, rec, kit)
    local okV, errV = pcall(SM.Validate, SM, rec, kit)
    errSc, errV = tostring(errSc), tostring(errV)
    check("a recording of an unknown version (v = 9) raises a named error (T66)",
        not okSc and not okV
        and errSc:find("no scenario builder for a v9 recording", 1, true) ~= nil
        and errV:find("no validator for a v9 recording", 1, true) ~= nil,
        string.format("scenario: %s %s ; validate: %s %s", tostring(okSc), errSc, tostring(okV), errV))
end

--------------------------------------------------------------------------------
-- T66 (P22, review A18): gate 8 reads the attribution the scenario already
-- made -- one SM.AttributeHeals per validation, where there were two.
--------------------------------------------------------------------------------
do
    local real, calls = SM.AttributeHeals, 0
    SM.AttributeHeals = function(...) calls = calls + 1; return real(...) end
    local v = SM:Validate(buildFixture(), kit)
    SM.AttributeHeals = real
    local g = ByName(v, "heals attributed")
    check("one validation attributes the heals once, and gate 8 still reads them (T66)",
        calls == 1 and g ~= nil and g.text:find("paired with your casts", 1, true) ~= nil,
        string.format("calls=%d gate=%s", calls, g and g.text or "nil"))
end

--------------------------------------------------------------------------------
-- T71 (P27, review A31): every gate carries a `short` -- its own verdict in a
-- few words, what the Review list's Result cell shows -- on both roads: the
-- v3 gates (a clean fixture, one with no meter reading, one with a death),
-- the v2 gates (the author's practice fight, tools/data/practice/, and a v2
-- stream with no mana samples). A short is ASCII, has no pipe, is at most 32
-- characters, and is not just the gate's name (a gate that named none would
-- get the name from SM.NewValidation).
--------------------------------------------------------------------------------
do
    local cases = {}
    cases[#cases + 1] = { "v3 clean", SM:Validate(buildFixture(), kit) }
    cases[#cases + 1] = { "v3 no meter", SM:Validate(buildFixture({ meterOverridden = true }), kit) }
    local dead = buildFixture()
    dead.deaths = { { t = 5, tgt = 1 } }
    cases[#cases + 1] = { "v3 death", SM:Validate(dead, kit) }
    local fx = dofile(here .. "/data/practice/1790701698.lua")
    local okP, vP = pcall(SM.Validate, SM, fx.rec, fx.kit)
    cases[#cases + 1] = { "v2 practice", okP and vP or nil }
    cases[#cases + 1] = { "v2 no samples", SM:Validate({
        v = 2, dur = 10, pool = 100,
        roster = { { name = "P", maxHP = 100, maxSecret = false } }, tracked = { 1 },
        ev = { t = { 1 }, kind = { SM.K.DMG }, tgt = { 1 }, amt = { 10 }, x = { 0 } }, n = 1,
        mana = { t = {}, v = {}, base = {}, cast = {} },
        hp = { t = {}, hp = { [1] = {} }, max = { [1] = { 100 } } },
        initial = { mana = 100, form = "caster" },
        deaths = {}, foreignShare = 0,
    }, kit) }
    local bad, gates, seen = nil, 0, {}
    for _, c in ipairs(cases) do
        local v = c[2]
        if not v then bad = bad or (c[1] .. ": no validation"); break end
        for _, g in ipairs(v.gates) do
            gates = gates + 1
            seen[#seen + 1] = g.short
            local s = g.short
            if type(s) ~= "string" or s == "" or s == g.name or #s > 32
                or s:find("[^ -~]") or s:find("|", 1, true) then
                bad = bad or string.format("%s / %s: short=%s", c[1], g.name, tostring(s))
            end
        end
    end
    check("T71: every gate, v3 and v2, carries a short verdict (ASCII, no pipe, not its name)",
        bad == nil and gates >= 30,
        bad or string.format("%d gates: %s", gates, table.concat(seen, "; ")))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
