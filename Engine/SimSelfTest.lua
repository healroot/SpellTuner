-- The engine's shipped self-tests (TBC TOC only): /md simrun (MD:RunSimRun,
-- the mechanics Engine/SimModel.lua is trusted on) and /md simreplay (the BF-1
-- fixture replay, or one recording's validation report). tools/simcheck.lua
-- runs both offline and reads their verdicts back.
--
-- T56 (P12, review A2): moved out of Verify.lua unchanged.
local _, MD = ...

--------------------------------------------------------------------------------
-- /md simrun -- self-tests for Engine/SimModel.lua (docs/SPEC-v0.7.md 3.8).
--
-- Nine assertions about mechanics nobody can eyeball once the engine is inside
-- a search: does a Rejuvenation heal what the dashboard says it heals, does a
-- refresh drop the ticks it should, does one Lifebloom stack bloom once, does
-- Swiftmend eat the right HoT, does a corpse stop taking heals, does the
-- five-second rule switch rates at 5.0, does the GCD hold two instants 1.5s
-- apart, and does Run allocate. Everything downstream trusts these.
--------------------------------------------------------------------------------
local function SimTargets(n, maxHP, hp0)
    local t = {}
    for i = 1, n do t[i] = { name = "T" .. i, maxHP = maxHP, hp0 = hp0, tracked = true } end
    return t
end

local function Near(a, b, tol)
    return math.abs((a or 0) - (b or 0)) <= tol
end

function MD:RunSimRun()
    local SM, RM, SD = MD.SimModel, MD.RankMath, MD.SpellData
    if not (SM and RM and SD) then MD:Print("simrun: engine not loaded.") return 0, 1 end

    -- The kit's caster half is built with inTree = false, so the rows it is
    -- compared against must be too -- otherwise running this in Tree form
    -- fails every heal assertion for the wrong reason.
    local kit = RM:SpellKit()
    local ctx = RM:Context({ live = true, healer = { inTree = false } })
    local out, fails = {}, 0
    local function Check(name, ok, detail)
        if not ok then fails = fails + 1 end
        out[#out + 1] = string.format("%-28s %s%s", name, ok and "ok" or "FAIL",
            detail and (" - " .. detail) or "")
    end

    local BIG = 1000000
    local rejuvID = SD.maxRank.Rejuvenation
    local regrowthID = SD.maxRank.Regrowth
    local lifebloomID = SD.maxRank.Lifebloom
    local swiftmendID = SD.maxRank.Swiftmend
    local caster = kit.caster

    -- 1. one Rejuvenation heals what the dashboard row says it heals
    if rejuvID and caster[rejuvID] then
        local e = caster[rejuvID]
        local row = RM:RowFor(rejuvID, ctx)
        local sc = { dur = 30, pool = 50000, initial = { mana = 50000, form = "caster" },
                     targets = SimTargets(1, BIG, 1), kit = kit }
        local r = SM:Run(sc, SM.ScriptPlan({ { 0, rejuvID, e.cost, 1 } }))
        Check("1 rejuv total heal", Near(r.healed, row.heal, 1),
            string.format("sim %.1f vs row %.1f", r.healed, row.heal))
        Check("1 rejuv mana", Near(r.manaSpent, e.cost, 0.01),
            string.format("spent %.0f vs cost %d", r.manaSpent, e.cost))
    else
        Check("1 rejuv", false, "Rejuvenation not known")
    end

    -- 2. chain-cast to OOM matches the dashboard's closed form
    if regrowthID and caster[regrowthID] then
        local e = caster[regrowthID]
        local mana = math.max(e.cost * 6, 8000)
        local regen = ctx.castingRegen
        local expected = RM:CastsToOOM(e.cost, e.cast, mana, regen)
        local sc = { dur = (expected + 2) * e.cast, pool = mana,
                     initial = { mana = mana, apiBase = regen, apiCasting = regen, form = "caster" },
                     targets = SimTargets(1, BIG, 1), kit = kit }
        local r = SM:Run(sc, SM.ChainPlan(regrowthID, 1, kit, "caster"))
        Check("2 chain casts to OOM", r.casts == expected,
            string.format("sim %d vs closed form %s", r.casts, tostring(expected)))
    else
        Check("2 chain casts to OOM", false, "Regrowth not known")
    end

    -- 3. a refresh drops the ticks that were still pending
    if rejuvID and caster[rejuvID] then
        local e = caster[rejuvID]
        local expected = 2 + e.ticks
        local sc = { dur = 40, pool = 50000, initial = { mana = 50000, form = "caster" },
                     targets = SimTargets(1, BIG, 1), kit = kit }
        local r = SM:Run(sc, SM.ScriptPlan({ { 0, rejuvID, e.cost, 1 }, { 6.5, rejuvID, e.cost, 1 } }))
        Check("3 refresh loses ticks", r.ticks == expected,
            string.format("%d ticks, expected %d", r.ticks, expected))
    end

    -- 4. a Lifebloom stack blooms exactly once
    if lifebloomID and caster[lifebloomID] then
        local e = caster[lifebloomID]
        local sc = { dur = 25, pool = 50000, initial = { mana = 50000, form = "caster" },
                     targets = SimTargets(1, BIG, 1), kit = kit }
        local r = SM:Run(sc, SM.ScriptPlan({ { 0, lifebloomID, e.cost, 1 },
                                             { 1, lifebloomID, e.cost, 1 },
                                             { 2, lifebloomID, e.cost, 1 } }))
        Check("4 lifebloom blooms once", r.blooms == 1, string.format("%d bloom(s)", r.blooms))

        -- v0.14.4: and it blooms for ONE application, whatever the stack --
        -- unlike the ticks beside it, which ARE `st.tick * st.stacks`.
        -- Measured, not recalled: pairing every bloom in the 22-parse Warcraft
        -- Logs corpus with the last tick before it (the tick size names the
        -- stack) gives the same bloom at 1, 2 and 3 stacks --
        --   Nightbane #55  231 / 462 / 694 tick -> 1501 bloom, all three
        --   Nightbane #55  308 / 616 / 923 tick -> 1967 bloom, all three
        --   Malchezaar     264 / 528 / 826 tick -> 1653 / 1654 / 1705
        -- v0.14.2 had scaled it by the stack, reading a 2.1x spread in one
        -- parse's blooms as stack scaling when it was crits (x1.5 exactly) and
        -- +healing procs (the same x1.30 and x1.40 appear on Regrowth's and
        -- Rejuvenation's ticks in the same fight).
        --
        -- The test measures the bloom directly rather than inferring it from a
        -- tick count: the same chain is run twice, once with the bloom zeroed,
        -- and the difference is what bloomed.
        -- SM:Run hands back a POOLED result table, so read the totals out
        -- before starting the next run (the trap that made v0.13.0's first
        -- comparison report five perfect ties)
        local function totalOf(casts, k)
            local rr = SM:Run({ dur = 25, pool = 50000, initial = { mana = 50000, form = "caster" },
                                targets = SimTargets(1, BIG, 1), kit = k or kit },
                              SM.ScriptPlan(casts))
            return (rr.healed or 0) + (rr.overhealed or 0)
        end
        local noBloom = { crit = kit.crit, caster = {}, tree = kit.tree }
        for id, row in pairs(caster) do noBloom.caster[id] = row end
        local lbCopy = {}
        for k2, v in pairs(e) do lbCopy[k2] = v end
        lbCopy.bloom = 0
        noBloom.caster[lifebloomID] = lbCopy
        local chain = { { 0, lifebloomID, e.cost, 1 },
                        { 1, lifebloomID, e.cost, 1 },
                        { 2, lifebloomID, e.cost, 1 } }
        local t3 = totalOf(chain)
        local t3n = totalOf(chain, noBloom)
        -- v0.14.2: refreshing a HoT must NOT push the next tick back. TBC's
        -- periodic timer keeps its own cadence across a refresh; ours restarted
        -- it, so a Lifebloom rolled every 1.5s against a 1s tick fired two
        -- ticks in three -- which is exactly the 67% of the log's tick count a
        -- real parse reproduced (tools/reproduce.lua).
        local rolled = SM:Run({ dur = 12, pool = 50000, initial = { mana = 50000, form = "caster" },
                                targets = SimTargets(1, BIG, 1), kit = kit },
                              SM.ScriptPlan({ { 0, lifebloomID, e.cost, 1 },
                                              { 1.5, lifebloomID, e.cost, 1 },
                                              { 3.0, lifebloomID, e.cost, 1 },
                                              { 4.5, lifebloomID, e.cost, 1 } }))
        -- covered from t=0 to t=11.5 at one tick a second
        -- ticks at 1,2,3,4 then seven more from the last refresh = 11. Resetting
        -- the timer on every refresh loses one of them.
        Check("4c a refresh does not delay the next tick", (rolled.ticks or 0) >= 11,
            string.format("%d ticks over 11.5s of 1s-period Lifebloom, expected 11",
                rolled.ticks or 0))

        Check("4b the bloom is one application's, not the stack's",
            math.abs((t3 - t3n) - (e.bloom or 0)) < 1,
            string.format("a 3-stack Lifebloom bloomed for %.0f; one application is %.0f, the whole stack would be %.0f",
                t3 - t3n, e.bloom or 0, 3 * (e.bloom or 0)))
    end

    -- 5. Swiftmend eats Regrowth before Rejuvenation
    if swiftmendID and caster[swiftmendID] and caster[swiftmendID].swiftmendRegrowth then
        local sm = caster[swiftmendID]
        local sc = { dur = 25, pool = 50000, initial = { mana = 50000, form = "caster" },
                     targets = SimTargets(1, BIG, 1), kit = kit }
        local r = SM:Run(sc, SM.ScriptPlan({ { 0, regrowthID, caster[regrowthID].cost, 1 },
                                             { 0.1, rejuvID, caster[rejuvID].cost, 1 },
                                             { 0.2, swiftmendID, sm.cost, 1 } }))
        local got = r.healByFamily.Swiftmend or 0
        Check("5 swiftmend eats regrowth", Near(got, sm.swiftmendRegrowth, 1),
            string.format("%.0f vs regrowth %.0f / rejuv %.0f", got,
                sm.swiftmendRegrowth or 0, sm.swiftmendRejuv or 0))
    end

    -- 6. nothing lands on a corpse
    if rejuvID and caster[rejuvID] then
        local e = caster[rejuvID]
        local sc = { dur = 20, pool = 50000, initial = { mana = 50000, form = "caster" },
                     targets = { { name = "T1", maxHP = 1000, hp0 = 1000, tracked = true } },
                     kit = kit, grace = 0, floor = 0,
                     ev = { t = { 1 }, kind = { MD.SimModel.K.DMG }, tgt = { 1 }, amt = { 5000 }, x = { 0 } } }
        local r = SM:Run(sc, SM.ScriptPlan({ { 2, rejuvID, e.cost, 1 } }))
        Check("6 no heals on a corpse", (r.healByFamily.Rejuvenation or 0) == 0 and r.deaths.n == 1,
            string.format("healed %.0f, deaths %d", r.healByFamily.Rejuvenation or 0, r.deaths.n))
    end

    -- 7. the five-second rule switches rates at 5.0
    if rejuvID and caster[rejuvID] then
        local e = caster[rejuvID]
        local M0, B, C = 40000, 40, 10
        local sc = { dur = 12, pool = 100000,
                     initial = { mana = M0, apiBase = B, apiCasting = C, form = "caster" },
                     targets = SimTargets(1, BIG, 1), kit = kit, sampleT = { 5, 10 } }
        local r = SM:Run(sc, SM.ScriptPlan({ { 0, rejuvID, e.cost, 1 } }))
        local want5 = M0 - e.cost + C * 5
        local want10 = want5 + B * 5
        Check("7 5SR rate switch", Near(r.manaCurve[1], want5, 0.5) and Near(r.manaCurve[2], want10, 0.5),
            string.format("%.0f/%.0f vs %.0f/%.0f", r.manaCurve[1] or -1, r.manaCurve[2] or -1, want5, want10))
    end

    -- 8. the GCD holds two instants 1.5s apart
    if rejuvID and caster[rejuvID] then
        local function ChainFor(dur)
            local sc = { dur = dur, pool = 100000, initial = { mana = 100000, form = "caster" },
                         targets = SimTargets(1, BIG, 1), kit = kit }
            return SM:Run(sc, SM.ChainPlan(rejuvID, 1, kit, "caster")).casts
        end
        local a, b = ChainFor(1.4), ChainFor(1.6)
        Check("8 gcd 1.5s", a == 1 and b == 2, string.format("1.4s -> %d, 1.6s -> %d", a, b))
    end

    -- 9. Run's cost does not grow with the timeline.
    --
    -- Measured per run over many runs, not once: a single run right after a
    -- collect reports the collector's own bookkeeping as if it were ours (4.1 KB
    -- against a true 2.1). What matters is that a 1,500-event fight costs the
    -- same as an empty one -- the loop reads the recorded arrays by index and
    -- allocates nothing. The fixed ~2 KB is Run's own local closures, built
    -- once per call.
    if rejuvID and caster[rejuvID] then
        local e = caster[rejuvID]
        local n, reps = 1500, 50
        local evT, evK, evTg, evA, evX = {}, {}, {}, {}, {}
        for i = 1, n do
            evT[i], evK[i], evTg[i], evA[i], evX[i] = i * 0.02, MD.SimModel.K.FHEAL, 1, 10, 0
        end
        local heavy = { dur = 35, pool = 100000, initial = { mana = 100000, form = "caster" },
                        targets = SimTargets(1, BIG, 1), kit = kit,
                        ev = { t = evT, kind = evK, tgt = evTg, amt = evA, x = evX } }
        local light = { dur = 35, pool = 100000, initial = { mana = 100000, form = "caster" },
                        targets = SimTargets(1, BIG, 1), kit = kit }
        local script = SM.ScriptPlan({ { 0, rejuvID, e.cost, 1 } })
        local function PerRun(sc)
            SM:Run(sc, script)
            collectgarbage("collect")
            local before = collectgarbage("count")
            for _ = 1, reps do SM:Run(sc, script) end
            return (collectgarbage("count") - before) / reps
        end
        local heavyKB, lightKB = PerRun(heavy), PerRun(light)
        Check("9 run cost is flat", heavyKB < 4 and math.abs(heavyKB - lightKB) < 0.5,
            string.format("%.2f KB/run with %d events, %.2f KB/run with none", heavyKB, n, lightKB))
    end

    MD:Print(string.format("simrun: %d test(s), %s", #out,
        fails == 0 and "all ok" or (fails .. " FAILED")))
    for _, line in ipairs(out) do
        MD:Print("  " .. line)
        MD:Debug("sim", "simrun %s", line)
    end
    -- T47 (Q3): the verdict, for tools/simcheck.lua's exit code
    return #out, fails
end

--------------------------------------------------------------------------------
-- /md simreplay fixture -- replay Data/SimFixture_BF1.lua and report how well
-- the engine reproduces the mana curve the log actually recorded.
--
-- Three numbers, because they answer three different questions:
--   spend     the recorded costs, summed by the engine. Must be exact; if it
--             is not, the script or the cost handling is broken.
--   modelled  the fit using ONLY what GetManaRegen reports. This is what the
--             addon's own regen model can predict, and on BF-1 it is short by
--             design -- the log carries ~23 mana/s of periodic energize the
--             API never mentions (see the fixture header).
--   measured  the fit with that energize included. THIS is the engine gate
--             (mean <= 2%, max <= 5% of pool): five-second-rule handling,
--             per-cast deduction, ordering and curve shape, with the rate
--             argument taken out of the question.
--------------------------------------------------------------------------------
local function ReplayFixture(fx)
    local SM, RM = MD.SimModel, MD.RankMath
    local sampleT, sampleM = {}, {}
    for i, m in ipairs(fx.mana) do sampleT[i], sampleM[i] = m[1], m[2] end

    local targets = {}
    for i, r in ipairs(fx.roster or {}) do
        targets[i] = { name = r.name, role = r.role, maxHP = 10000, hp0 = 10000, tracked = false }
    end

    local function RunWith(energize)
        local sc = {
            dur = fx.dur, pool = fx.pool,
            initial = { mana = fx.initial.mana, apiBase = fx.initial.apiBase,
                        apiCasting = fx.initial.apiCasting, energize = energize,
                        form = fx.initial.form, auras = fx.initial.auras },
            targets = targets, forms = fx.forms, sampleT = sampleT,
            kit = RM:SpellKit(),
        }
        local r = SM:Run(sc, SM.ScriptPlan(fx.casts))
        local sum, worst, worstT = 0, 0, 0
        for i = 1, #sampleT do
            local d = math.abs((r.manaCurve[i] or 0) - sampleM[i])
            sum = sum + d
            if d > worst then worst, worstT = d, sampleT[i] end
        end
        return sum / math.max(1, #sampleT) / fx.pool, worst / fx.pool, worstT, r
    end

    -- Order matters: the result belongs to the pool slot, so the run whose
    -- result is still read must be the last one.
    local mMean, mMax, mAt = RunWith(0)
    local eMean, eMax, eAt, eRes = RunWith(fx.initial.energize or 0)

    local recorded = 0
    for _, c in ipairs(fx.casts) do recorded = recorded + (c[3] or 0) end

    local spendExact = math.abs(eRes.manaSpent - recorded) < 1
    local fit = eMean <= 0.02 and eMax <= 0.05
    local lines = {
        string.format("fixture %s: %d casts, %.1fs, pool %d", fx.name or "?", #fx.casts, fx.dur, fx.pool),
        string.format("  spend    sim %.0f vs recorded %d  (%s)", eRes.manaSpent, recorded,
            spendExact and "exact" or "MISMATCH"),
        string.format("  modelled mean %.1f%%  max %.1f%% at %.1fs   (GetManaRegen only)",
            mMean * 100, mMax * 100, mAt),
        string.format("  measured mean %.1f%%  max %.1f%% at %.1fs   (+ %.1f mana/s energize) -> %s",
            eMean * 100, eMax * 100, eAt, fx.initial.energize or 0,
            fit and "PASS" or "FAIL"),
    }
    return lines, spendExact and fit
end

function MD:RunSimReplay(arg)
    if not (MD.SimModel and MD.RankMath) then MD:Print("simreplay: engine not loaded.") return false end
    if arg == nil or arg == "" or arg == "fixture" or arg == "bf1" then
        local fx = MD.SimFixtures and MD.SimFixtures.BF1
        if not fx then MD:Print("simreplay: no fixture loaded.") return false end
        local lines, pass = ReplayFixture(fx)
        for _, line in ipairs(lines) do
            MD:Print(line)
            MD:Debug("sim", "simreplay %s", line)
        end
        -- T47 (Q3): the fixture's verdict -- spend exact and the fit inside its gate
        return pass
    end
    local rec, label = MD:GetRecording(arg)
    if not rec then
        MD:Print("simreplay: no recording " .. tostring(arg) .. " (try /md simreplay fixture).")
        return
    end
    for _, line in ipairs(MD:ValidationReport(rec, label)) do
        MD:Print(line)
        MD:Debug("sim", "simreplay %s", line)
    end
end
