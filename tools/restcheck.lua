-- tools/run.sh tools/restcheck.lua
--
-- The coach values regen (2026-09-29, docs/DECISIONS.md). The author, after a
-- practice fight at level 10: "I've found the coach issue, it does not tolerate
-- non casting window to regen. It will be less relevant on higher level, but as
-- a concept it is critical."
--
-- What these assertions hold down:
--   1. the engine's mana accounting: what the pool paid and got back, after the
--      floor and the cap, and what a fight USED (start - end + the regen a rule
--      still running at the end has yet to cost)
--   2. the solver's price: a cast's cost PLUS the regen it forfeits, in units --
--      out of the rule, inside it, at a full pool, with the two rates equal
--   3. nothing changes where there is nothing to forfeit: base == casting
--      decides cast for cast as the regen-blind solver does
--   4. the rule state reaches Decide as the healer sees it: published by cursor,
--      after the cast the classifier is judging, and a rate sample at 30 s
--      changes no decision before 30 s
--   5. the danger rule still owns danger: a target projected far through the
--      floor gets rule 8 (a shipped bug found on the way), and the price never
--      reaches a decision rule 8 makes
--   6. the author's own practice fight (tools/data/practice/1790701698.lua) and
--      a synthetic level 10 party: the coach now leaves windows to regenerate,
--      ends with more mana and uses less, at no cost in deaths, seconds in
--      danger or lowest health
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local SM, SP, SV, PR = MD.SimModel, MD.SimPlanner, MD.SimSolver, MD.Practice
local K = SM.K

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-58s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end
local function near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6) end
local function num(v) return type(v) == "number" and string.format("%.2f", v) or tostring(v) end

-- A level 10 Forever druid (the author's book, 2026-09-29): Healing Touch R2
-- and Rejuvenation R2 bound, 364 mana, GetManaRegen 11.5 out of the rule and
-- 0.001 inside it (probe, build 70009).
local POOL, BASE, CAST = 364, 11.5, 0.001
local L10 = {
    [5185] = { family = "HealingTouch", rank = 1, type = "direct", cost = 25, cast = 1.5, gcd = 1.5, direct = 47.5, directCrit = 0 },
    [5186] = { family = "HealingTouch", rank = 2, type = "direct", cost = 55, cast = 2.0, gcd = 1.5, direct = 102.5, directCrit = 0 },
    [774]  = { family = "Rejuvenation", rank = 1, type = "hot", cost = 25, cast = 1.5, gcd = 1.5, tick = 8, ticks = 4, tickPeriod = 3, duration = 12 },
    [1058] = { family = "Rejuvenation", rank = 2, type = "hot", cost = 40, cast = 1.5, gcd = 1.5, tick = 12, ticks = 4, tickPeriod = 3, duration = 12 },
}
local kit10 = { caster = L10, tree = L10, crit = 0 }
local binds10 = { HealingTouch = 5186, Rejuvenation = 1058 }

-- The regen-blind solver: exactly the price it had before 2026-09-29.
local realForfeit = SV.Forfeit
local function Blind(fn)
    SV.Forfeit = function() return 0 end
    local ok2, a, b, c = pcall(fn)
    SV.Forfeit = realForfeit
    assert(ok2, a)
    return a, b, c
end

local function Casts(sc, plan, opts)
    local list = {}
    opts = opts or {}
    opts.critMode = "ev"
    opts.onCast = function(_, t, id, ti) list[#list + 1] = { t, id, ti } end
    local r = SP.RunPlan(sc, plan, opts)
    local snap = {}
    for k, v in pairs(r) do if type(v) ~= "table" then snap[k] = v end end
    snap.deaths, snap.lowest = r.deaths.n, r.lowest.hp
    snap.owed = SP.ManaOwed(r, plan)
    return list, snap
end

local function SameCasts(a, b, before)
    local n = 0
    for i = 1, math.max(#a, #b) do
        local x, y = a[i], b[i]
        if before and (not x or x[1] >= before) and (not y or y[1] >= before) then break end
        if not x or not y or math.abs(x[1] - y[1]) > 1e-6 or x[2] ~= y[2] or x[3] ~= y[3] then
            return false, string.format("cast %d: %s vs %s", i,
                x and string.format("%.1f/%d>%d", x[1], x[2], x[3] or 0) or "none",
                y and string.format("%.1f/%d>%d", y[1], y[2], y[3] or 0) or "none")
        end
        n = n + 1
    end
    return true, string.format("%d casts", n)
end

-- the synthetic practice party the author plays, at level 10 health
local function Party(tankDps, spike, seed, dur, base, casting)
    local setup = PR.DefaultSetup("5", 10)
    setup.dur = dur
    for _, tg in ipairs(setup.targets) do
        if tg.kind == "TANK" then tg.dps = tankDps end
        tg.spike = (tg.spike or 0) * spike
    end
    local sampleT, hpT = {}, {}
    for t = 0, dur, 2 do sampleT[#sampleT + 1] = t end
    for t = 0, dur, 5 do hpT[#hpT + 1] = t end
    local targets = {}
    for i, tg in ipairs(setup.targets) do
        targets[i] = { name = tg.name, role = tg.role, maxHP = tg.maxHP, hp0 = tg.maxHP, tracked = true }
    end
    return { dur = dur, pool = POOL,
             initial = { mana = POOL, apiBase = base or BASE, apiCasting = casting or CAST,
                         form = "caster", energize = 0 },
             targets = targets, ev = PR.BuildDamage(setup, seed), floor = 0.30, grace = 6,
             sampleT = sampleT, hpSampleT = hpT, kit = kit10, synthetic = true }
end

local function Frugal(kit, binds)
    return SP.MakeStrategy(SP.Strategy("solver-frugal"), binds, kit, {})
end
-- frugal exactly as it shipped before this change: no price, floor 30
local function OldFrugal(kit, binds)
    return SV.NewPlan(binds, { minValue = 30, horizon = 18 }, kit)
end

--------------------------------------------------------------------------------
-- 1. Accounting
--------------------------------------------------------------------------------
do
    -- one target, a scripted fight: a cast the pool cannot fully pay (an
    -- over-draw), regen into a full pool (the cap), a potion into a nearly full
    -- one (the cap on K.CD), and a cast in the last second (the rule's tail)
    local sc = {
        dur = 30, pool = 100,
        initial = { mana = 60, apiBase = 10, apiCasting = 1, form = "caster", energize = 0 },
        targets = { { name = "T", maxHP = 1000, hp0 = 500, tracked = true } },
        ev = { t = { 8 }, kind = { K.CD }, tgt = { 0 }, amt = { 90 }, x = { 0 } },
        kit = kit10, floor = 0.30, grace = 6,
        script = { { 1, 5186, 80, 1 }, { 29.5, 1058, 40, 1 } },
    }
    local r = SM:Run(sc, nil, { critMode = "ev" })
    check("1a manaStart is the pool at the pull", r.manaStart == 60, num(r.manaStart))
    check("1b manaSpent is the gross cost of every cast", near(r.manaSpent, 120), num(r.manaSpent))
    -- 60 + 1 s of regen = 70 in the pool when the 80-mana cast lands
    check("1c paid is what the pool actually lost (70 of the 80)", near(r.paid, 70 + 40), num(r.paid))
    check("1d the identity: start - end = paid - regen - potion",
        r.manaStart and near(r.manaStart - r.manaEnd, (r.paid or 0) - (r.regenGained or 0) - (r.cdGained or 0), 1e-6),
        string.format("%s vs %s", num(r.manaStart and (r.manaStart - r.manaEnd)),
            num((r.paid or 0) - (r.regenGained or 0) - (r.cdGained or 0))))
    -- at 8 s: 0 after the cast, 5 s in the rule at 1/s, 2 s out at 10/s = 25
    check("1e the potion is counted after the cap (75 of its 90)", near(r.cdGained, 75), num(r.cdGained))
    -- the cast at 29.5 leaves 4.5 s of the rule running after the end
    check("1f fsrLeft: the rule still running at the end", near(r.fsrLeft, 4.5), num(r.fsrLeft))
    local want = math.min((10 - 1) * 4.5, 100 - (r.manaEnd or 0))
    check("1g ruleDebt = (base - casting) x tail, capped by the room", near(r.ruleDebt, want),
        string.format("%s vs %s", num(r.ruleDebt), num(want)))
    check("1h manaUsed = start - end + ruleDebt",
        r.manaStart and near(r.manaUsed, r.manaStart - r.manaEnd + (r.ruleDebt or 0)), num(r.manaUsed))

    sc.initial.apiCasting = 10
    local r2 = SM:Run(sc, nil, { critMode = "ev" })
    check("1i with base == casting there is no rule debt", r2.ruleDebt == 0, num(r2.ruleDebt))
end

--------------------------------------------------------------------------------
-- 2. The price, in units
--------------------------------------------------------------------------------
do
    local R = BASE - CAST
    local hot, direct = L10[1058], L10[5186]
    local function S(fsr, mana)
        return { fsrUntil = fsr, regenBase = BASE, regenCasting = CAST, manaMax = POOL, energize = 0 }, mana
    end
    local s, m = S(-1, 100)
    check("2a out of the rule, an instant forfeits R x 5",
        near(SV.Forfeit and SV.Forfeit(s, 10, m, hot, 0), R * 5), num(SV.Forfeit and SV.Forfeit(s, 10, m, hot, 0)))
    s, m = S(10 + 3.5, 100)
    check("2b with 3.5 s of the rule left, an instant forfeits R x 1.5",
        near(SV.Forfeit and SV.Forfeit(s, 10, m, hot, 0), R * 1.5), num(SV.Forfeit and SV.Forfeit(s, 10, m, hot, 0)))
    s, m = S(10 + 3.5, 100)
    check("2c a 2 s cast lands with 1.5 s left: R x 3.5",
        near(SV.Forfeit and SV.Forfeit(s, 10, m, direct, 0), R * 3.5), num(SV.Forfeit and SV.Forfeit(s, 10, m, direct, 0)))
    s, m = S(10 + 8, 100)
    check("2d a rule already running past land + 5 forfeits nothing",
        SV.Forfeit and SV.Forfeit(s, 10, m, hot, 0) == 0)
    s, m = S(-1, POOL)
    check("2e at a full pool the price is the cost alone",
        SV.Forfeit and SV.Forfeit(s, 10, m, direct, 0) == 0)
    s, m = S(-1, POOL - 20)
    local f = SV.Forfeit and SV.Forfeit(s, 10, m, hot, 0)
    check("2f near the cap only what the pool could hold is lost", near(f, 20 - CAST * 5), num(f))
    s = { fsrUntil = -1, regenBase = 20, regenCasting = 20, manaMax = POOL, energize = 0 }
    check("2g with base == casting the price is the cost",
        SV.Forfeit and SV.Forfeit(s, 10, 100, direct, 0) == 0)
    -- TBC: the in-rule rate is large, so what both branches regain inside the
    -- rule leaves less room for the forfeit near the cap
    s = { fsrUntil = -1, regenBase = 82.7, regenCasting = 38.4, manaMax = 8000, energize = 0 }
    local tbc = SV.Forfeit and SV.Forfeit(s, 10, 8000 - 300, hot, 0)
    check("2h TBC near the cap: room minus in-rule regen", near(tbc, 300 - 38.4 * 5), num(tbc))
end

--------------------------------------------------------------------------------
-- 3. Nothing to forfeit, nothing changes
--------------------------------------------------------------------------------
do
    local sc = Party(0.006, 1, 4, 48, 11.5, 11.5)
    local a = Casts(sc, SV.NewPlan(binds10, { minValue = 20, horizon = 18 }, kit10))
    local b = Blind(function() return Casts(sc, SV.NewPlan(binds10, { minValue = 20, horizon = 18 }, kit10)) end)
    local same, d = SameCasts(a, b)
    check("3a base == casting: cast for cast the regen-blind solver", same and #a > 0, d)

    -- the shared scripted TBC pull, a whole second recording with its own rates
    dofile(here .. "/fakepull.lua")(MD, _G.STUB)
    local rec = MD.FightRecorder:List()[1]
    local kit = MD.RankMath:SpellKit({ live = true })
    local sc2 = SM.ScenarioFromRecording(rec, kit)
    sc2.initial.apiCasting = sc2.initial.apiBase
    sc2.rates = nil
    local plan = function() return SP.MakeStrategy(SP.Strategy("solver-blind"), SP.MaxRankBinds(), kit, { scenario = sc2 }) end
    local c1 = Casts(sc2, plan())
    local c2 = Blind(function() return Casts(sc2, plan()) end)
    same, d = SameCasts(c1, c2)
    check("3b ...and on a TBC recording with the rates made equal", same and #c1 > 0, d)
end

--------------------------------------------------------------------------------
-- 4. What Decide may read, and when
--------------------------------------------------------------------------------
do
    local sc = Party(0.006, 1, 4, 30)
    local seen = {}
    local plan = { Decide = function(_, S, t)
        seen[#seen + 1] = { t = t, fsr = S.fsrUntil, base = S.regenBase, cast = S.regenCasting, max = S.manaMax }
        if #seen == 1 then return 1058, 1, 7 end
        return nil
    end, BindCount = function() return 1 end }
    SP.RunPlan(sc, plan, { critMode = "ev" })
    check("4a Decide reads the pool and the two rates",
        seen[1] and seen[1].max == POOL and seen[1].base == BASE and seen[1].cast == CAST)
    check("4b ...and the rule: none running at the pull", seen[1] and seen[1].fsr and seen[1].fsr < 0,
        num(seen[1] and seen[1].fsr))
    check("4c after its own cast at 0 the rule runs until 5", seen[2] and near(seen[2].fsr, 5),
        num(seen[2] and seen[2].fsr))

    -- the classifier asks the plan in lockstep, inside the cast's success: it
    -- must see the rule as it was BEFORE the cast it is judging
    local before = {}
    local sc2 = Party(0.006, 1, 4, 20)
    sc2.script = { { 2, 5186, 55, 1 }, { 4, 5186, 55, 1 } }
    SM:Run(sc2, nil, { critMode = "ev", onCast = function(S, t) before[#before + 1] = { t, S.fsrUntil } end })
    check("4d the lockstep hook sees the rule before the cast",
        before[1] and (before[1][2] or 99) < 2 and before[2] and near(before[2][2], 2 + 5),
        string.format("%s / %s", num(before[1] and before[1][2]), num(before[2] and before[2][2])))

    -- a rate sample at 30 s (an Innervate, say) is applied by cursor: no
    -- decision before 30 s may differ
    local plain = Party(0.008, 1, 4, 48)
    local inner = Party(0.008, 1, 4, 48)
    inner.rates = { { 30, 60, 60 } }
    local a = Casts(plain, Frugal(kit10, binds10))
    local b = Casts(inner, Frugal(kit10, binds10))
    local same, d = SameCasts(a, b, 30)
    check("4e a rate sample at 30 s changes no decision before it", same, d)
    local diff = not SameCasts(a, b)
    check("4f ...and it does change what the plan reads after it", diff)
end

--------------------------------------------------------------------------------
-- 5. The danger rule owns danger
--------------------------------------------------------------------------------
do
    -- a tank the forecast puts far through the floor under every cast: the
    -- shipped rule 8 compared each candidate's low with -1, so a target that
    -- deep got no pick at all and the value rule decided instead
    local sc = {
        dur = 20, pool = POOL,
        initial = { mana = POOL, apiBase = BASE, apiCasting = CAST, form = "caster", energize = 0 },
        targets = { { name = "Tank", role = "TANK", maxHP = 1428, hp0 = 1428, tracked = true } },
        ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} },
        kit = kit10, floor = 0.30, grace = 6,
    }
    for k = 0, 8 do
        local i = #sc.ev.t + 1
        sc.ev.t[i], sc.ev.kind[i], sc.ev.tgt[i], sc.ev.amt[i], sc.ev.x[i] = k * 0.5, K.DMG, 1, 110, 0
    end
    local rules = {}
    local plan = Frugal(kit10, binds10)
    local orig = plan.Decide
    plan.Decide = function(self, S, t, mana, form)
        local id, ti, rule = orig(self, S, t, mana, form)
        if t >= 4 and t < 5 and not rules.first then rules.first = { rule = rule, id = id, reason = self.reason } end
        return id, ti, rule
    end
    SP.RunPlan(sc, plan, { critMode = "ev" })
    check("5a a target projected far through the floor gets rule 8",
        rules.first and rules.first.rule == 8,
        rules.first and string.format("rule %s", tostring(rules.first.rule)) or "no decision")

    -- no banking while somebody is in danger: wherever rule 8 decides, the
    -- priced solver decides exactly what the regen-blind one does
    local fx = dofile(here .. "/data/practice/1790701698.lua")
    local sc2 = SM.ScenarioFromRecording(fx.rec, fx.kit)
    local function Rule8(priced)
        local p = Frugal(fx.kit, SP.MaxRankBinds(fx.rec.initial.known))
        local o = p.Decide
        local out = {}
        p.Decide = function(self, S, t, mana, form)
            local id, ti, rule = o(self, S, t, mana, form)
            if rule == 8 then out[#out + 1] = { t, id, ti } end
            return id, ti, rule
        end
        if priced then SP.RunPlan(sc2, p, { critMode = "ev" }) else Blind(function() SP.RunPlan(sc2, p, { critMode = "ev" }) end) end
        return out, p
    end
    local r8 = Rule8(true)
    check("5b the author's fight: rule 8 fires in the priced plan", #r8 > 0, string.format("%d", #r8))
    local allNominal = true
    for _, d in ipairs(r8) do if d.forfeit then allNominal = false end end
    -- and the reason rule 8 writes never carries a forfeit
    local p = Frugal(fx.kit, SP.MaxRankBinds(fx.rec.initial.known))
    local o = p.Decide
    p.Decide = function(self, S, t, mana, form)
        local id, ti, rule = o(self, S, t, mana, form)
        if rule == 8 and self.reason and self.reason.forfeit then allNominal = false end
        return id, ti, rule
    end
    SP.RunPlan(sc2, p, { critMode = "ev" })
    check("5c rule 8 prices at the nominal cost, never the forfeit", allNominal)
end

--------------------------------------------------------------------------------
-- 6. The author's fight, and a synthetic level 10 party
--------------------------------------------------------------------------------
do
    local fx = dofile(here .. "/data/practice/1790701698.lua")
    local rec, kit = fx.rec, fx.kit
    local v = SM:Validate(rec, kit)
    check("6a the fixture replays: every gate passes with its kit", v and v.ok,
        v and not v.ok and (function()
            for _, g in ipairs(v.gates) do if not g.ok then return g.name .. ": " .. (g.text or "") end end
        end)() or nil)
    local sc = SM.ScenarioFromRecording(rec, kit)
    local youR = SM:Run(sc, nil, { critMode = "ev" })
    -- the result belongs to the engine's pool slot: copy it before the next run
    local you = { manaSpent = youR.manaSpent, regenGained = youR.regenGained, manaUsed = youR.manaUsed,
                  manaEnd = youR.manaEnd, lowest = { hp = youR.lowest.hp } }
    check("6b ...to the mana the author saw (21 at 47.9 s)", near(you.manaEnd, 21, 1), num(you.manaEnd))
    local binds = SP.MaxRankBinds(rec.initial.known)
    local _, old = Blind(function() return Casts(sc, OldFrugal(kit, binds)) end)
    local _, new = Casts(sc, Frugal(kit, binds))
    print(string.format("    you spent %d regen %d used %d end %d lowest %d%%",
        you.manaSpent, you.regenGained or -1, you.manaUsed or -1, you.manaEnd, you.lowest.hp * 100))
    for _, x in ipairs({ { "old frugal", old }, { "new frugal", new } }) do
        local r = x[2]
        print(string.format("    %-10s spent %d regen %d used %d end %d owed %d dead %d floor %.1f lowest %d%%",
            x[1], r.manaSpent, r.regenGained or -1, r.manaUsed or -1, r.manaEnd, r.owed, r.deaths,
            r.floorSeconds, r.lowest * 100))
    end
    check("6c the coach now regenerates more", (new.regenGained or 0) > (old.regenGained or 0) + 20,
        string.format("%s vs %s", num(new.regenGained), num(old.regenGained)))
    check("6d ...ends with more mana", new.manaEnd > old.manaEnd + 20,
        string.format("%s vs %s", num(new.manaEnd), num(old.manaEnd)))
    check("6e ...and uses less of the pool", (new.manaUsed or 1e9) < (old.manaUsed or 0),
        string.format("%s vs %s", num(new.manaUsed), num(old.manaUsed)))
    check("6f ...at no cost in deaths or seconds in danger",
        new.deaths <= old.deaths and new.floorSeconds <= old.floorSeconds + 1e-9)
    check("6g ...or lowest health", new.lowest >= old.lowest - 1e-9,
        string.format("%d%% vs %d%%", new.lowest * 100, old.lowest * 100))
    check("6h ...and it owes less for the health it leaves missing", new.owed <= old.owed + 1e-6,
        string.format("%.0f vs %.0f", new.owed, old.owed))

    -- the synthetic party the analysis reproduced it on: tank 0.6% of max a
    -- second, spikes on, seed 4
    local sp = Party(0.006, 1, 4, 48)
    local _, o2 = Blind(function() return Casts(sp, OldFrugal(kit10, binds10)) end)
    local _, n2 = Casts(sp, Frugal(kit10, binds10))
    check("6i synthetic seed 4: more mana at the end",
        n2.manaEnd > o2.manaEnd, string.format("%.0f vs %.0f", n2.manaEnd, o2.manaEnd))
    check("6j ...at no cost in deaths or seconds in danger",
        n2.deaths <= o2.deaths and n2.floorSeconds <= o2.floorSeconds + 1e-9,
        string.format("%d/%.1f vs %d/%.1f", n2.deaths, n2.floorSeconds, o2.deaths, o2.floorSeconds))

    -- and over 180 of them, spikes off to heavy: no more deaths, more mana
    local agg = { old = { d = 0, e = 0, u = 0 }, new = { d = 0, e = 0, u = 0 } }
    for _, td in ipairs({ 0.004, 0.006, 0.008, 0.010, 0.012 }) do
        for _, spk in ipairs({ 0, 0.5, 1 }) do
            for seed = 1, 12 do
                local s = Party(td, spk, seed, 48)
                local _, a = Blind(function() return Casts(s, OldFrugal(kit10, binds10)) end)
                local _, b = Casts(s, Frugal(kit10, binds10))
                agg.old.d, agg.old.e, agg.old.u = agg.old.d + a.deaths, agg.old.e + a.manaEnd, agg.old.u + (a.manaUsed or 0)
                agg.new.d, agg.new.e, agg.new.u = agg.new.d + b.deaths, agg.new.e + b.manaEnd, agg.new.u + (b.manaUsed or 0)
            end
        end
    end
    check("6k 180 synthetic fights: no more deaths than before", agg.new.d <= agg.old.d,
        string.format("%d vs %d", agg.new.d, agg.old.d))
    check("6l ...more mana at the end, less of the pool used",
        agg.new.e > agg.old.e and agg.new.u < agg.old.u,
        string.format("end %.0f vs %.0f, used %.0f vs %.0f", agg.new.e / 180, agg.old.e / 180,
            agg.new.u / 180, agg.old.u / 180))
end

--------------------------------------------------------------------------------
-- 7. The score ranks what left the pool
--------------------------------------------------------------------------------
do
    local stub = { BindCount = function() return 2 end }
    local function R(spent, manaEnd)
        return { manaSpent = spent, manaStart = 364, manaEnd = manaEnd, manaUsed = 364 - manaEnd,
                 deaths = { n = 0 }, floorSeconds = 0, endDeficit = 0, deficitArea = 1,
                 healed = 1000, overhealed = 50 }
    end
    -- the author's screenshot at 0:43.9: YOU spent 425, regen 137, 76 left;
    -- the coach spent 385, regen 45, 24 left
    local you, coach = R(425, 76), R(385, 24)
    check("7a 425 spent / 76 left beats 385 spent / 24 left",
        SP.Better(SP.Score(you, stub, 0), SP.Score(coach, stub, 0)),
        string.format("%s vs %s", num(SP.Score(you, stub, 0)[3]), num(SP.Score(coach, stub, 0)[3])))
    local all = true
    for _, obj in ipairs(SP.OBJECTIVES) do
        if not SP.Better(obj.score(you, stub, 0), obj.score(coach, stub, 0)) then all = false end
    end
    check("7b ...under every objective, not only the default", all)
    check("7c a result with gross spend only is ranked on it, as before",
        SP.ManaUsed({ manaSpent = 500 }) == 500 and SP.ManaUsed({ manaSpent = 500, manaUsed = 120 }) == 120)

    -- the stated bias: the owed term is priced at the best heal per mana with
    -- no regen forfeit, so ending a Healing Touch R2 short (owed 102.5 / 1.86)
    -- scores below paying for it out of the rule (55 + 57.5). A fact about the
    -- tuple, held here so a change to it is a decision rather than an accident.
    local plan = SV.NewPlan(binds10, {}, kit10)
    local healed = { manaUsed = 300 + 55 + 57.5, endDeficit = 0, deaths = { n = 0 }, floorSeconds = 0 }
    local short = { manaUsed = 300, endDeficit = 102.5, deaths = { n = 0 }, floorSeconds = 0 }
    check("7d stated bias: owed carries no forfeit, so ending hurt scores lower",
        SP.Score(short, plan, 0)[3] < SP.Score(healed, plan, 0)[3],
        string.format("%.1f vs %.1f", SP.Score(short, plan, 0)[3], SP.Score(healed, plan, 0)[3]))

    -- the search's abort: a plan that spends MORE but ends HIGHER may not be
    -- killed for its gross spend -- not by a later Innervate rate sample, not
    -- by a recorded potion
    local function Sc(extra)
        local sc = {
            dur = 30, pool = 1000,
            initial = { mana = 1000, apiBase = 0, apiCasting = 0, form = "caster", energize = 0 },
            targets = { { name = "T", maxHP = 1000, hp0 = 500, tracked = true } },
            ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} },
            kit = kit10, floor = 0.30, grace = 6,
            script = { { 1, 5186, 200, 1 }, { 3, 5186, 200, 1 }, { 5, 5186, 200, 1 } },
        }
        if extra then extra(sc) end
        return sc
    end
    local r = SM:Run(Sc(function(sc) sc.rates = { { 20, 100, 100 } } end), nil, { critMode = "ev", abortAbove = 300 })
    check("7e abort: spends 600 but an Innervate at 20 s refills it -- not aborted",
        not r.aborted and (r.manaUsed or 1e9) < 300, string.format("aborted %s, used %s", tostring(r.aborted), num(r.manaUsed)))
    r = SM:Run(Sc(function(sc) sc.ev = { t = { 25 }, kind = { K.CD }, tgt = { 0 }, amt = { 700 }, x = { 0 } } end),
        nil, { critMode = "ev", abortAbove = 300 })
    check("7f abort: ...nor a recorded potion at 25 s",
        not r.aborted and (r.manaUsed or 1e9) < 300, string.format("aborted %s, used %s", tostring(r.aborted), num(r.manaUsed)))
    r = SM:Run(Sc(), nil, { critMode = "ev", abortAbove = 300 })
    check("7g abort: nothing can come back, so it still stops", r.aborted == true)

    -- a run: the rule the pull left running regenerates at the casting rate in
    -- the gap after it, once
    local realScen = SM.ScenarioFromRecording
    local scen = {}
    SM.ScenarioFromRecording = function(rec) return scen[rec] end
    local function Pull(lastCast)
        local sc = Sc()
        sc.dur, sc.initial.apiBase, sc.initial.apiCasting, sc.initial.mana = 10, 10, 0, 500
        sc.script = { { lastCast, 5186, 100, 1 } }
        return sc
    end
    local p1 = { dur = 10, runT0 = 0, initial = { apiBase = 10, apiCasting = 0, energize = 0, mana = 500 } }
    local p2 = { dur = 10, runT0 = 20, initial = { apiBase = 10, apiCasting = 0, energize = 0, mana = 500 } }
    local run = { pool = 1000, pulls = { p1, p2 }, ev = { t = {} }, stats = {} }
    scen[p1], scen[p2] = Pull(9.9), Pull(1)
    local okRun, chain = pcall(SM.ChainRun, run, kit10, { drinkRate = 1, policy = { below = 0, upTo = 0.95 } })
    local gap = okRun and chain.gaps[1]
    local gained = gap and (gap.manaEnd - gap.manaStart)
    check("7h a run: the pull's last-second cast delays the gap's regen by its tail",
        near(gained, 10 * 10 - 10 * 4.9, 1e-6), okRun and num(gained) or tostring(chain))
    check("7i ...and the run's used is its own start less its own end",
        okRun and near(chain.manaUsed, chain.manaStart - chain.manaEnd), okRun and num(chain.manaUsed) or nil)
    SM.ScenarioFromRecording = realScen
    local a = { deaths = 0, floorSeconds = 0, addedTime = 0, drinks = 1, manaSpent = 5000, manaUsed = 1000 }
    local b = { deaths = 0, floorSeconds = 0, addedTime = 0, drinks = 1, manaSpent = 4000, manaUsed = 1500 }
    check("7j the run score ranks mana used: more spent but less used wins",
        SP.Better(SP.ChainScore(a, stub, 0), SP.ChainScore(b, stub, 0)))

    -- the replay window's header leads with it
    local fx = dofile(here .. "/data/practice/1790701698.lua")
    local rp = SP.Replay(fx.rec, { kit = fx.kit, dt = 0.25 })
    local st = MD.ReplayTrace.New(rp.left.trace, rp.scenario)
    st:Seek(43.9)
    local used = st.Used and st:Used()
    check("7k the replay's USED at 0:43.9 is the pool at the pull less the pool now",
        used and near(used, 364 - st:Mana(), 1e-6) and near(used, st.spent - st:Regen(), 1e-6),
        string.format("used %s, spent %s, regen %s", num(used), num(st.spent), num(st:Regen())))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then for _, m in ipairs(fails) do print("  FAIL " .. m) end; os.exit(1) end
