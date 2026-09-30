-- tools/run.sh tools/solvercheck.lua
--
-- The solver (docs/SPEC-v0.13.md): a spell is a series of deposits, and the
-- cast to make is the one that removes the most missing-health-seconds per
-- mana. These assertions are about the PROPERTIES the design claims, not about
-- particular numbers -- an overhealing cast must score below a clean one with
-- no overheal term anywhere in the code, and the same deficit must pull a
-- different spell depending only on how the damage is spread.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local SM, SP, SV = MD.SimModel, MD.SimPlanner, MD.SimSolver
local K = SM.K

-- the shared scripted pull, so there is a real recording to classify against
dofile(here .. "/fakepull.lua")(MD, _G.STUB)

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-46s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local kit = MD.RankMath:SpellKit({ live = true })
local binds = SP.MaxRankBinds()

--------------------------------------------------------------------------------
-- 1. Deposits
--------------------------------------------------------------------------------
do
    local caster = kit.caster
    local lb = caster[binds.Lifebloom]
    local dep, n = SV.Deposits(lb, nil)
    local total = 0
    for i = 1, n do total = total + dep[i][2] end
    local want = (lb.tick or 0) * (lb.ticks or 0) + (lb.bloom or 0)
    check("a spell's deposits sum to what it heals",
        math.abs(total - want) < 1, string.format("%.0f vs %.0f", total, want))
    check("every deposit lands after the cast finishes", (function()
        for i = 1, n do if dep[i][1] < (lb.cast or 1.5) - 1e-9 then return false end end
        return true
    end)())

    local rj = caster[binds.Rejuvenation]
    local d2, n2 = SV.Deposits(rj, nil)
    check("a HoT deposits once per tick", n2 == (rj.ticks or 0), string.format("%d of %d", n2, rj.ticks or 0))

    local rg = caster[binds.Regrowth]
    local d3, n3 = SV.Deposits(rg, nil)
    check("a hybrid deposits its direct heal first",
        n3 == (rg.ticks or 0) + 1 and math.abs(d3[1][2] - rg.direct) < 1,
        string.format("%d deposits, first %.0f", n3, d3[1][2]))

    -- a Lifebloom on top of two stacks deposits three stacks' worth
    local st = { active = true, stacks = 2, family = "Lifebloom" }
    local d4, n4 = SV.Deposits(lb, st)
    check("Lifebloom onto 2 stacks deposits 3 stacks' worth",
        math.abs(d4[1][2] - lb.tick * 3) < 1,
        string.format("%.0f vs %.0f", d4[1][2], lb.tick * 3))
end

--------------------------------------------------------------------------------
-- 2. The gap does the work three separate terms used to do
--------------------------------------------------------------------------------
do
    local maxHP = 10000
    -- a full target: every deposit is overheal, so it saves nothing
    local dep = { { 1.5, 3000 } }
    local full = SV.Gap(maxHP, maxHP, 0, nil, {}, 0, nil, 0, 0, 12)
    local fullWith = SV.Gap(maxHP, maxHP, 0, nil, {}, 0, dep, 1, 0, 12)
    check("a cast into a full target saves nothing", math.abs(full - fullWith) < 1e-6,
        string.format("%.0f vs %.0f", full, fullWith))

    -- the same cast into a real deficit saves the whole integral it fills
    local hurt = SV.Gap(4000, maxHP, 0, nil, {}, 0, nil, 0, 0, 12)
    local hurtWith = SV.Gap(4000, maxHP, 0, nil, {}, 0, dep, 1, 0, 12)
    check("the same cast into a deficit saves real health-seconds",
        hurt - hurtWith > 1000, string.format("%.0f saved", hurt - hurtWith))

    -- half of it overheals: it must save strictly less, with no overheal term
    local dep2 = { { 1.5, 12000 } }
    local overWith = SV.Gap(4000, maxHP, 0, nil, {}, 0, dep2, 1, 0, 12)
    local savedClean = hurt - hurtWith
    local savedOver = hurt - overWith
    check("an oversized cast saves less per point than a fitting one",
        savedOver / 12000 < savedClean / 3000,
        string.format("%.3f vs %.3f per point", savedOver / 12000, savedClean / 3000))

    -- a deposit that lands late is worth less than the same one landing now
    local now = SV.Gap(4000, maxHP, 0, nil, {}, 0, { { 0.5, 3000 } }, 1, 0, 12)
    local late = SV.Gap(4000, maxHP, 0, nil, {}, 0, { { 9.0, 3000 } }, 1, 0, 12)
    check("a deposit landing sooner saves more than the same one landing late",
        (hurt - now) > (hurt - late), string.format("%.0f vs %.0f", hurt - now, hurt - late))
end

--------------------------------------------------------------------------------
-- 3. The decision: same deficit, different damage shape, different spell
--------------------------------------------------------------------------------
local function state(hp, rate, seenFor)
    local S = { nT = 1, tracked = { true }, dead = {}, hp = { hp }, maxHP = { 10000 },
                hots = { {} }, dmg = {}, threat = {}, incoming = {} }
    local ring = { t = {}, a = {}, total = 0, hits = 0, firstAt = 0, biggest = 0 }
    for i = 1, 64 do ring.t[i], ring.a[i] = -100, 0 end
    if rate > 0 then
        local per = rate * 1.0
        for i = 1, 5 do
            ring.t[i], ring.a[i] = (seenFor or 5) - i, per
            ring.total = ring.total + per
            ring.hits = ring.hits + 1
            if per > ring.biggest then ring.biggest = per end
        end
        ring.firstAt = 0
    end
    S.dmg[1] = ring
    return S
end

do
    local plan = SV.NewPlan(binds, { minValue = 0.1, horizon = 12 }, kit)
    -- deeply hurt, nothing incoming: the gap is NOW, so a direct heal wins
    local hurtQuiet = state(3000, 0)
    local id1 = plan:Decide(hurtQuiet, 10, 99999, "caster")
    local sd1 = id1 and MD.SpellData.spells[id1]
    check("a deep deficit with no incoming pulls a direct heal",
        sd1 ~= nil and (sd1.family == "Regrowth" or sd1.family == "HealingTouch"
                        or sd1.family == "Swiftmend"),
        sd1 and (sd1.family .. " r" .. sd1.rank) or tostring(id1))

    -- barely hurt but bleeding: the gap is AHEAD, so a HoT wins
    local trickle = state(9200, 300)
    local id2 = plan:Decide(trickle, 10, 99999, "caster")
    local sd2 = id2 and MD.SpellData.spells[id2]
    check("a small deficit with damage coming pulls a HoT",
        sd2 ~= nil and (sd2.family == "Lifebloom" or sd2.family == "Rejuvenation"),
        sd2 and (sd2.family .. " r" .. sd2.rank) or tostring(id2))
    check("the two answers differ on demand alone, not on a threshold",
        id1 ~= id2, string.format("%s vs %s", tostring(id1), tostring(id2)))

    -- full and quiet: nothing is worth casting
    local calm = state(10000, 0)
    check("nobody hurt, nothing coming: it waits",
        plan:Decide(calm, 10, 99999, "caster") == nil)

    -- the efficiency floor is the mana dial
    local greedy = SV.NewPlan(binds, { minValue = 0.01, horizon = 12 }, kit)
    local stingy = SV.NewPlan(binds, { minValue = 1000, horizon = 12 }, kit)
    local weak = state(9700, 40)
    check("a low floor spends on a thin target", greedy:Decide(weak, 10, 99999, "caster") ~= nil)
    check("a high floor keeps the mana", stingy:Decide(weak, 10, 99999, "caster") == nil)
end

--------------------------------------------------------------------------------
-- 4. Causality: the solver may not see the future either
--------------------------------------------------------------------------------
do
    local function scenarioWithBurst(burst)
        local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
        local n = 0
        local function add(at, amt)
            n = n + 1
            ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = at, K.DMG, 1, amt, 0
        end
        for at = 2, 38, 4 do add(at, 300) end
        if burst then for at = 40, 48 do add(at, 1200) end end
        return { dur = 60, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kit, floor = 0.30, ev = ev,
                 targets = { { name = "T", role = "TANK", maxHP = 10000, hp0 = 10000, tracked = true } } }
    end
    local function castsOf(sc)
        local out = {}
        SP.RunPlan(sc, SV.NewPlan(binds, { minValue = 0.5, horizon = 12 }, kit),
            { critMode = "ev", onCast = function(_, at, id)
                out[#out + 1] = string.format("%.2f:%d", at, id) end })
        return out
    end
    local quiet, loud = castsOf(scenarioWithBurst(false)), castsOf(scenarioWithBurst(true))
    local diverged
    for j = 1, math.min(#quiet, #loud) do
        local at = tonumber(quiet[j]:match("^([%d%.]+)"))
        if quiet[j] ~= loud[j] then diverged = diverged or at end
    end
    check("the solver casts something", #quiet > 0, string.format("%d casts", #quiet))
    check("a burst at 40s changes nothing the solver does before it",
        diverged == nil or diverged >= 39.9,
        diverged and string.format("diverged at %.1fs", diverged) or "identical until the burst")
end

--------------------------------------------------------------------------------
-- 4b. T20 (review R6): the danger line a plan DECIDES on is the biggest hit
-- taken so far; the score keeps the whole fight's. A measured scenario carries
-- `danger` computed exactly as the TBC builder does from the scenario's own hits.
--------------------------------------------------------------------------------
do
    local dangerHits = (MD.db and MD.db.simDangerHits) or 1
    -- 600 every 2 s from 2 s to 38 s, and (optionally) one 7000 hit at 40 s
    local function measured(bigAt, maxHP, step, small, big, fheal)
        local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
        local n, biggest = 0, 0
        local function add(at, amt)
            n = n + 1
            ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = at, K.DMG, 1, amt, 0
            if amt > biggest then biggest = amt end
        end
        for at = 2, 38, step do add(at, small) end
        if bigAt then add(bigAt, big) end
        -- (optional) a foreign healer keeping the tank alive with no cast of
        -- ours: 19 hits of 600 would kill 10000 before the hit at 40 s lands
        if fheal then
            for at = 3, 39, step do
                n = n + 1
                ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = at, K.FHEAL, 1, fheal, 0
            end
            -- the engine reads events by cursor: keep them in time order
            local order = {}
            for j = 1, n do order[j] = j end
            table.sort(order, function(x, y)
                if ev.t[x] ~= ev.t[y] then return ev.t[x] < ev.t[y] end
                return x < y
            end)
            local sorted = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
            for j = 1, n do
                local o = order[j]
                sorted.t[j], sorted.kind[j], sorted.tgt[j], sorted.amt[j], sorted.x[j] =
                    ev.t[o], ev.kind[o], ev.tgt[o], ev.amt[o], ev.x[o]
            end
            ev = sorted
        end
        return { dur = 60, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kit, floor = 0.30, ev = ev,
                 targets = { { name = "T", role = "TANK", maxHP = maxHP, hp0 = maxHP, tracked = true,
                               danger = math.min(1, biggest * dangerHits / maxHP) } } }
    end
    -- a plan that reads the line the engine hands it and casts nothing
    local function readings(sc)
        local seen = {}
        local plan = { Decide = function(_, S, t)
            local line
            if SM.DangerLine then line = SM.DangerLine(S, 1) end
            seen[#seen + 1] = { t = t, line = line }
            return nil
        end }
        SP.RunPlan(sc, plan, { critMode = "ev" })
        return seen
    end
    local function span(seen, from, to)
        local lo, hi, n = 2, -1, 0
        for _, r in ipairs(seen) do
            if r.t >= from and r.t <= to then
                n = n + 1
                if type(r.line) ~= "number" then return nil, n end
                if r.line < lo then lo = r.line end
                if r.line > hi then hi = r.line end
            end
        end
        return { lo = lo, hi = hi }, n
    end
    local function flat(seen, from, to, want)
        local r, n = span(seen, from, to)
        return r ~= nil and n > 0 and math.abs(r.lo - want) < 1e-9 and math.abs(r.hi - want) < 1e-9,
            r and string.format("%d reads, %.3f..%.3f", n, r.lo, r.hi) or ("no number in " .. n .. " reads")
    end

    local seen = readings(measured(40, 10000, 2, 600, 7000, 500))
    local a1, d1 = flat(seen, 0, 1.9, 0.30)
    local a2, d2 = flat(seen, 2.1, 39.9, 0.06)
    local a3, d3 = flat(seen, 40.1, 59, 0.70)
    check("the danger line a plan reads is the biggest hit so far", a1 and a2 and a3,
        "before: " .. d1 .. "; between: " .. d2 .. "; after: " .. d3)

    local sc = measured(40, 10000, 2, 600, 7000, 500)
    sc.targets[1].dangerPrior = 0.5
    local seenP = readings(sc)
    local p1, e1 = flat(seenP, 0, 1.9, 0.5)
    local p2, e2 = flat(seenP, 2.1, 39.9, 0.06)
    check("before the first hit the line is the scenario's prior when it has one", p1 and p2,
        "before: " .. e1 .. "; from 2 s: " .. e2)

    local function castsOf(sc2)
        local out = {}
        SP.RunPlan(sc2, SV.NewPlan(binds, { minValue = 0.5, horizon = 12 }, kit),
            { critMode = "ev", onCast = function(_, at, id)
                out[#out + 1] = string.format("%.2f:%d", at, id) end })
        return out
    end
    local q, l = castsOf(measured(nil, 10000, 2, 600, 0)), castsOf(measured(40, 10000, 2, 600, 7000))
    local diverged
    for j = 1, math.min(#q, #l) do
        local at = math.min(tonumber(q[j]:match("^([%d%.]+)")), tonumber(l[j]:match("^([%d%.]+)")))
        if q[j] ~= l[j] then diverged = diverged or at end
    end
    if not diverged and #q ~= #l then
        local at = tonumber(((#q > #l) and q[#l + 1] or l[#q + 1]):match("^([%d%.]+)"))
        diverged = at
    end
    check("a hit bigger than any before it changes nothing the solver does before it",
        #q > 0 and (diverged == nil or diverged >= 39.9),
        string.format("%d and %d casts, ", #q, #l) ..
        (diverged and string.format("diverged at %.1fs", diverged) or "identical until the hit"))

    -- the score: whole-fight line. Nothing cast, the tank at 75% sitting under
    -- the 80% line the 8000 hit at 40 s will draw, though the causal line
    -- before 40 s is 1%.
    local sc3 = measured(40, 10000, 2, 100, 8000)
    sc3.targets[1].hp0 = 7500
    local r = SM:Run(sc3, nil, { critMode = "ev" })
    check("the score still counts seconds under the whole-fight line",
        sc3.targets[1].danger == 0.8 and r.floorSeconds >= 30,
        string.format("danger %.2f, floorSeconds %.1f", sc3.targets[1].danger, r.floorSeconds or -1))
end

--------------------------------------------------------------------------------
-- 4c. T20b: before a target's first hit, its danger line comes from OTHER
-- recordings of the same person (leave-one-out, by id); never the one built.
--------------------------------------------------------------------------------
do
    local dangerHits = (MD.db and MD.db.simDangerHits) or 1
    -- a hand-made TBC recording: roster Healroot + <name>, DMG events on the
    -- second, given as { { t, amount }, ... }
    local function rec(id, name, hits)
        local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
        local n = 0
        for _, h in ipairs(hits) do
            n = n + 1
            ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = h[1], K.DMG, 2, h[2], 0
        end
        return { id = id, zone = "Test", dur = 60, pool = 9000, n = n, ev = ev,
                 roster = { { name = "Healroot", role = "HEALER", maxHP = 3000 },
                            { name = name, role = "TANK", maxHP = 10000 } },
                 tracked = { 1, 2 },
                 initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 mana = { t = {}, base = {}, cast = {} } }
    end
    local A, B, C = 7100000001, 7100000002, 7100000003
    local recA = rec(A, "Tank", { { 4, 300 }, { 20, 5000 } })
    local store = { recA, rec(B, "Tank", { { 5, 2000 }, { 9, 700 } }), rec(C, "Bob", { { 6, 9000 } }) }

    local hit, cnt
    if SM.DangerHitFromOthers then
        local h, c = SM.DangerHitFromOthers(store, A, "Tank")
        hit, cnt = h, c
    end
    check("the danger prior is the biggest hit that person took in other recordings",
        hit == 2000 and cnt == 1, string.format("hit=%s recordings=%s", tostring(hit), tostring(cnt)))

    local okNil = false
    if SM.DangerHitFromOthers then okNil = pcall(SM.DangerHitFromOthers, store, nil, "Tank") end
    local noId = rec(nil, "Tank", { { 4, 300 }, { 20, 5000 } })
    local scNoId = SM.ScenarioFromRecording(noId, kit, store)
    check("the prior's exclusion is required",
        okNil == false and scNoId.targets[2].dangerPrior == nil,
        string.format("pcall=%s prior=%s", tostring(okNil), tostring(scNoId.targets[2].dangerPrior)))

    local function readings(sc)
        local seen = {}
        SP.RunPlan(sc, { Decide = function(_, S, t)
            seen[#seen + 1] = { t = t, line = SM.DangerLine(S, 2) }
            return nil
        end }, { critMode = "ev" })
        return seen
    end
    local function range(seen, from, to)
        local lo, hi, n = 2, -1, 0
        for _, r in ipairs(seen) do
            if r.t >= from and r.t <= to and type(r.line) == "number" then
                n = n + 1
                if r.line < lo then lo = r.line end
                if r.line > hi then hi = r.line end
            end
        end
        return lo, hi, n
    end
    local want = math.min(1, 2000 * dangerHits / 10000)
    local scA = SM.ScenarioFromRecording(recA, kit, store)
    local seenA = readings(scA)
    local l1, h1, n1 = range(seenA, 0, 3.9)
    local l2, h2, n2 = range(seenA, 4.1, 19.9)
    local l3, h3, n3 = range(seenA, 20.1, 59)
    local exp2 = math.min(1, 300 * dangerHits / 10000)
    local exp3 = math.min(1, 5000 * dangerHits / 10000)
    local function near(a, b) return math.abs(a - b) < 1e-9 end
    local readsOk = n1 > 0 and n2 > 0 and n3 > 0 and near(l1, want) and near(h1, want)
        and near(l2, exp2) and near(h2, exp2) and near(l3, exp3) and near(h3, exp3)

    -- the same recording without its 5000 hit: same prior, same reads before 20 s
    local recA2 = rec(A, "Tank", { { 4, 300 } })
    local scA2 = SM.ScenarioFromRecording(recA2, kit, store)
    local seenA2 = readings(scA2)
    local same = scA2.targets[2].dangerPrior == scA.targets[2].dangerPrior
    local nb = 0
    for _, r in ipairs(seenA) do
        if r.t < 20 then
            nb = nb + 1
            local o = seenA2[nb]
            if not o or o.t ~= r.t or o.line ~= r.line then same = false end
        end
    end
    check("before the first hit a plan reads the prior from other recordings",
        near(scA.targets[2].dangerPrior or -1, want) and readsOk and same and nb > 0,
        string.format("prior=%s want=%s before=%.3f/%.3f/%d between=%.3f/%d after=%.3f/%d identical-before-20s=%s",
            tostring(scA.targets[2].dangerPrior), tostring(want), l1, h1, n1, l2, n2, l3, n3, tostring(same)))
end

--------------------------------------------------------------------------------
-- 5. Healer intuition: a prior from OTHER fights, never from this one
--------------------------------------------------------------------------------
do
    local IN = MD.Intuition
    -- three fake recordings in one zone: the tank eats 400/s from the pull
    local function fakeRec(id, tankDps)
        local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
        local n = 0
        for at = 1, 30 do
            n = n + 1
            ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = at, K.DMG, 1, tankDps, 0
        end
        return { id = id, zone = "Test Keep", dur = 30, n = n, ev = ev,
                 roster = { { name = "T", role = "TANK", maxHP = 4000 },
                            { name = "H", role = "HEALER", maxHP = 4000 } } }
    end
    local recs = { fakeRec(1, 400), fakeRec(2, 400), fakeRec(3, 400) }

    local prior = IN:Build(recs, nil)
    -- the prior speaks in FRACTIONS of max health: 400/s on a 4000hp tank is 10%
    local r = IN:Rate(prior, "Test Keep", "TANK", 0)
    check("the prior learns the tank takes damage from the pull",
        r > 0.05 and r < 0.2, string.format("%.1f%% of health per second", r * 100))
    check("the prior is a fraction, so it travels to another character",
        math.abs(r * 12000 - 1200) < 200,
        string.format("%.0f/s on a 12k tank vs %.0f/s on the 4k one it learned from",
            r * 12000, r * 4000))
    check("it says nothing about a role nobody recorded",
        IN:Rate(prior, "Test Keep", "DAMAGER", 0) == 0)

    -- THE invariant: a fight may not teach itself
    local held = IN:Build(recs, 2)
    check("holding a fight out drops it from the prior",
        held.fights == 2 and held.skipped == 1,
        string.format("%d used, %d held", held.fights, held.skipped))
    local only = IN:Build({ recs[2] }, 2)
    check("a fight held out of a corpus of one leaves NO prior",
        IN:Rate(only, "Test Keep", "TANK", 0) == 0,
        string.format("%.0f", IN:Rate(only, "Test Keep", "TANK", 0)))

    -- one fight is an anecdote
    local single = IN:Build({ recs[1] }, nil)
    check("one fight is not enough to be a prior",
        IN:Rate(single, "Test Keep", "TANK", 0) == 0)

    -- the prior fades as the fight provides real evidence
    local far = IN:Rate(prior, "Test Keep", "TANK", 60)
    check("the prior still answers later in the fight", far > 0,
        string.format("%.1f%%", far * 100))

    -- and it must not make the solver clairvoyant: same scenario, same answer,
    -- whether or not a burst it never saw is coming
    local function scen(burst)
        local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
        local n = 0
        local function add(at, amt)
            n = n + 1
            ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = at, K.DMG, 1, amt, 0
        end
        for at = 2, 38, 4 do add(at, 300) end
        if burst then for at = 40, 48 do add(at, 1200) end end
        return { dur = 60, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kit, floor = 0.30, ev = ev,
                 targets = { { name = "T", role = "TANK", maxHP = 10000, hp0 = 10000, tracked = true } } }
    end
    local function castsOf(sc)
        local out = {}
        SP.RunPlan(sc, SV.NewPlan(binds, { minValue = 0.5, horizon = 12,
            prior = prior, zone = "Test Keep" }, kit),
            { critMode = "ev", onCast = function(_, at, id)
                out[#out + 1] = string.format("%.2f:%d", at, id) end })
        return out
    end
    local quiet, loud = castsOf(scen(false)), castsOf(scen(true))
    local diverged
    for j = 1, math.min(#quiet, #loud) do
        if quiet[j] ~= loud[j] then
            diverged = diverged or tonumber(quiet[j]:match("^([%d%.]+)"))
        end
    end
    check("a prior does not make the solver clairvoyant",
        diverged == nil or diverged >= 39.9,
        diverged and string.format("diverged at %.1fs", diverged) or "identical until the burst")

    -- the point of the whole thing: it acts at the pull, before any hit lands
    local blind = SV.NewPlan(binds, { minValue = 0.5, horizon = 12 }, kit)
    local wise = SV.NewPlan(binds, { minValue = 0.5, horizon = 12,
                                     prior = prior, zone = "Test Keep" }, kit)
    local S0 = { nT = 2, tracked = { true, true }, dead = {}, hp = { 10000, 10000 },
                 maxHP = { 10000, 10000 }, hots = { {}, {} }, dmg = {}, danger = {},
                 role = { "TANK", "HEALER" }, threat = {}, incoming = {}, danger = {} }
    for i = 1, 2 do
        local ring = { t = {}, a = {}, total = 0, hits = 0, firstAt = nil, biggest = 0 }
        for j = 1, 64 do ring.t[j], ring.a[j] = -100, 0 end
        S0.dmg[i] = ring
    end
    check("with no prior the solver waits at the pull",
        blind:Decide(S0, 0, 99999, "caster") == nil)
    local id, tgt = wise:Decide(S0, 0, 99999, "caster")
    check("with a prior it pre-heals the tank before the first hit",
        id ~= nil and tgt == 1,
        id and ((MD.SpellData.spells[id] or {}).family or tostring(id)) or "still waited")
end

--------------------------------------------------------------------------------
-- 6. Deformed foresight: it must SEE the burst and must NOT see it clearly
--------------------------------------------------------------------------------
do
    local FS = MD.Foresight
    -- one clean burst: 8000 damage in a single second at t=40, nothing else
    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    local n = 0
    local function add(at, amt)
        n = n + 1
        ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = at, K.DMG, 1, amt, 0
    end
    for at = 2, 60, 4 do add(at, 200) end
    add(40, 8000)
    local sc = { dur = 70, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kit, floor = 0.30, ev = ev,
                 targets = { { name = "T", role = "TANK", maxHP = 10000, hp0 = 10000, tracked = true } } }

    local fs = FS.Build(sc, { seed = 7 })
    check("foresight builds from the fight", fs ~= nil and fs.nT == 1)

    -- it knows something is coming: the rate ahead of the burst beats a quiet spot
    local before = FS.Rate(fs, 1, 34, 12)
    local quiet = FS.Rate(fs, 1, 10, 12)
    check("it knows a burst is coming before it lands", before > quiet * 2,
        string.format("%.0f/s at 34s vs %.0f/s at 10s", before, quiet))

    -- ...and it cannot place it: the bucket before the burst is already lit
    local early = FS.Rate(fs, 1, 34, 4)
    check("it cannot place the burst inside its own second", early > quiet,
        string.format("%.0f/s already at 34s", early))

    -- ...and it cannot size it: the deformed peak is off the truth
    local peakBin = 0
    for b = 1, fs.nBins do if fs.bins[1][b] > peakBin then peakBin = fs.bins[1][b] end end
    local truth = 8000 + 200
    check("it cannot size the burst either", math.abs(peakBin - truth) / truth > 0.10,
        string.format("%.0f vs %.0f = %.0f%% off", peakBin, truth,
            100 * math.abs(peakBin - truth) / truth))

    -- nothing beyond sight
    check("it sees nothing beyond its horizon", FS.Rate(fs, 1, 0, 12) < before,
        string.format("%.0f at the pull", FS.Rate(fs, 1, 0, 12)))

    -- deterministic: a replay must reproduce
    local again = FS.Build(sc, { seed = 7 })
    local same = true
    for b = 1, fs.nBins do if math.abs(fs.bins[1][b] - again.bins[1][b]) > 1e-9 then same = false end end
    check("the same fight deforms the same way every time", same)
    local other = FS.Build(sc, { seed = 8 })
    local diff = false
    for b = 1, fs.nBins do if math.abs(fs.bins[1][b] - other.bins[1][b]) > 1e-9 then diff = true end end
    check("a different seed deforms differently", diff)

    -- the honest label: a plan with foresight admits it is not causal
    local blind = SV.NewPlan(binds, { minValue = 15, horizon = 18 }, kit)
    local seer = SV.NewPlan(binds, { minValue = 15, horizon = 18, foresight = fs }, kit)
    check("a plan without foresight does not claim it", blind.foresees == false)
    check("a plan with foresight admits it", seer.foresees == true)

    -- and the point: it heals INTO the burst rather than after it
    local function firstCastAfter(plan, from)
        local at
        SP.RunPlan(sc, plan, { critMode = "ev", onCast = function(_, t2)
            if not at and t2 >= from then at = t2 end end })
        return at
    end
    local a = firstCastAfter(SV.NewPlan(binds, { minValue = 15, horizon = 18 }, kit), 30)
    local b = firstCastAfter(SV.NewPlan(binds, { minValue = 15, horizon = 18, foresight = fs }, kit), 30)
    check("foresight moves the answer earlier, not later",
        (a == nil and b ~= nil) or (a and b and b <= a + 1e-9),
        string.format("blind %s, foresighted %s", tostring(a), tostring(b)))
end

--------------------------------------------------------------------------------
-- 7. The explainer: the solver decided on a number, so it can name the number
--------------------------------------------------------------------------------
do
    local plan = SV.NewPlan(binds, { minValue = 0.1, horizon = 12 }, kit)
    local seen = {}
    local S1 = state(3000, 400)
    plan:Decide(S1, 10, 99999, "caster")
    seen[#seen + 1] = plan.reason
    local S2 = state(10000, 0)
    plan:Decide(S2, 10, 99999, "caster")
    seen[#seen + 1] = plan.reason
    local stingy = SV.NewPlan(binds, { minValue = 1e6, horizon = 12 }, kit)
    stingy:Decide(state(9700, 40), 10, 99999, "caster")
    seen[#seen + 1] = stingy.reason

    local allNumbered, anyPipe, rules = true, false, {}
    for _, r in ipairs(seen) do
        local txt = SP.ReasonText(r, {})
        rules[#rules + 1] = tostring(r.rule)
        if type(txt) ~= "string" or not txt:find("%d") then allNumbered = false end
        if txt and txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):find("|", 1, true) then
            anyPipe = true
        end
    end
    check("every solver decision renders a sentence with a number in it",
        allNumbered, "rules " .. table.concat(rules, ","))
    check("no bare pipe in a solver sentence", not anyPipe)
    check("the planner delegates the solver's rules to the solver",
        SP.ReasonText({ rule = 7, deficit = 1200, rate = 350, saved = 3400,
                        cost = 220, value = 15.5 }, {}):find("per mana") ~= nil,
        SP.ReasonText({ rule = 7, deficit = 1200, rate = 350, saved = 3400,
                        cost = 220, value = 15.5 }, {}))
    check("each solver rule has a name for the replay's hover",
        SP.RULE_NAMES[7] and SP.RULE_NAMES[8] and SP.RULE_NAMES[9] ~= nil)
    print("   " .. tostring(SP.ReasonText({ rule = 7, deficit = 1200, rate = 350,
        saved = 3400, cost = 220, value = 15.5 }, {})))
    print("   " .. tostring(SP.ReasonText({ rule = 8, deficit = 6600, rate = 900,
        below = 0.34, freeIn = 2.5, cost = 220 }, {})))
    print("   " .. tostring(SP.ReasonText({ rule = 9, target = 1, deficit = 400,
        value = 12.1, later = 18.4 }, {})))
end

--------------------------------------------------------------------------------
-- 8. The strategy set is what a human picks between
--------------------------------------------------------------------------------
do
    check("there are strategies to choose from", #SP.STRATEGY_SET >= 4,
        tostring(#SP.STRATEGY_SET))
    local kinds = {}
    for _, e in ipairs(SP.STRATEGY_SET) do kinds[e.kind] = true end
    check("both planners are represented", kinds.rules and kinds.solver)
    local sc = { dur = 20, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kit, floor = 0.30, ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} },
                 targets = { { name = "T", role = "TANK", maxHP = 10000, hp0 = 10000, tracked = true } } }
    local built, labelled = 0, 0
    for _, e in ipairs(SP.STRATEGY_SET) do
        local plan = SP.MakeStrategy(e, binds, kit, { scenario = sc, seed = 1 })
        if plan then built = built + 1 end
        if e.why and #e.why > 10 then labelled = labelled + 1 end
    end
    check("every strategy builds a plan", built == #SP.STRATEGY_SET,
        string.format("%d of %d", built, #SP.STRATEGY_SET))
    check("every strategy says what it is for", labelled == #SP.STRATEGY_SET)
    local sight = SP.Strategy("solver-sight")
    local plan = SP.MakeStrategy(sight, binds, kit, { scenario = sc, seed = 1 })
    check("the foresighted strategy is flagged as not causal", plan.foresees == true)
    local plain = SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit, { scenario = sc, seed = 1 })
    check("the others are not", plain.foresees == false)
end

--------------------------------------------------------------------------------
-- 9. The shipped prior: somebody else's experience, in fractions of health
--------------------------------------------------------------------------------
do
    local IN = MD.Intuition
    local t = MD.IntuitionTBC
    check("a prior ships with the addon", t ~= nil and (t.fights or 0) >= 10,
        t and string.format("%d fights, %d encounters", t.fights or 0, t.encounters or 0) or "missing")
    check("it was merged from many encounters, not one raid",
        (t.encounters or 0) >= 8, tostring(t.encounters))
    check("it is blurred, not exact", (t.blurred or 0) > 0,
        string.format("quantised to %.1f%% of health per second", (t.blurred or 0) * 100))
    check("a tank opens harder than the fight sustains",
        t.all.TANK.open > t.all.TANK.rest,
        string.format("%.1f%% then %.1f%%", t.all.TANK.open * 100, t.all.TANK.rest * 100))
    check("nobody but the tank is expected to take damage at the pull",
        t.all.DAMAGER.open == 0 and t.all.HEALER.open == 0)
    check("it carries how much it varies, so it can be doubted",
        (t.all.TANK.spread or 0) > 1, string.format("%.1fx between encounters",
            t.all.TANK.spread or 0))

    local prior = IN:Load(t)
    check("the shipped prior loads into the same shape Build makes",
        IN:Rate(prior, nil, "TANK", 0) > 0.02,
        string.format("%.1f%% of health per second", IN:Rate(prior, nil, "TANK", 0) * 100))

    -- it lands on a character it never saw: a 4k tank and a 13k tank
    local frac = IN:Rate(prior, nil, "TANK", 0)
    check("the same prior scales to any character",
        math.abs(frac * 4000 - 340) < 120 and math.abs(frac * 13000 - 1170) < 400,
        string.format("%.0f/s on a 4k tank, %.0f/s on a 13k one", frac * 4000, frac * 13000))

    -- and it does the job: pre-heal the TANK at the pull, with no damage yet
    local function pullState()
        local S = { nT = 2, tracked = { true, true }, dead = {}, hp = { 12000, 8000 },
                    maxHP = { 12000, 8000 }, hots = { {}, {} }, dmg = {}, danger = {},
                    role = { "TANK", "HEALER" }, threat = {}, incoming = {} }
        for i = 1, 2 do
            local ring = { t = {}, a = {}, total = 0, hits = 0, firstAt = nil, biggest = 0 }
            for j = 1, 64 do ring.t[j], ring.a[j] = -100, 0 end
            S.dmg[i] = ring
        end
        return S
    end
    local sc = { dur = 30, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kit, floor = 0.30, ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} },
                 targets = { { name = "T", role = "TANK", maxHP = 12000, hp0 = 12000, tracked = true } } }
    local blind = SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit, { scenario = sc })
    local wise = SP.MakeStrategy(SP.Strategy("solver-corpus"), binds, kit, { scenario = sc })
    check("the corpus strategy carries the shipped prior", wise.prior ~= nil)
    check("it is still causal -- it never reads this fight", wise.foresees == false)
    check("with the shipped prior the solver opens on the tank",
        blind:Decide(pullState(), 0, 99999, "caster") == nil
        and select(2, wise:Decide(pullState(), 0, 99999, "caster")) == 1,
        (function()
            local id, tgt = wise:Decide(pullState(), 0, 99999, "caster")
            return id and string.format("target %s, %s", tostring(tgt),
                (MD.SpellData.spells[id] or {}).family or id) or "waited"
        end)())
end

--------------------------------------------------------------------------------
-- 10. The classifier must survive a solver plan (v0.13.10)
--
-- SP.Classify labels recorded casts against a plan, and it read plan.rollStacks
-- -- a THRESHOLD-RULES parameter the solver does not have. Since v0.13.7 the
-- replay's chooser can hand it a solver plan, and it took the window down live
-- with "attempt to compare nil with number".
--------------------------------------------------------------------------------
do
    local rec = MD.FightRecorder:Get(1)
    check("there is a recording to classify", rec ~= nil)
    if rec then
        for _, entry in ipairs(SP.STRATEGY_SET) do
            local kit2 = MD.RankMath:SpellKit({ live = true })
            local sc = SM.ScenarioFromRecording(rec, kit2)
            local plan = SP.MakeStrategy(entry, SP.MaxRankBinds(), kit2,
                { scenario = sc, seed = rec.id or 1 })
            local okRun, err = pcall(SP.Classify, rec, sc, plan, kit2)
            check("Classify survives " .. entry.key, okRun, tostring(err))
        end
        -- The exact shape that crashed live: control reaches the rollStacks
        -- test only when the plan wants NOTHING at that cast (so every earlier
        -- branch misses) and a Lifebloom is already rolling on the target. A
        -- bare table with a Decide that returns nil is the minimal plan that
        -- does it -- and it has no rollStacks at all, which is the point: the
        -- classifier must not assume the fields of the threshold rules.
        do
            local kitX = MD.RankMath:SpellKit({ live = true })
            local nothing = { Decide = function() return nil end,
                              BindCount = function() return 0 end,
                              Reset = function() end, binds = {}, kit = kitX }
            -- the fixture casts Lifebloom once, so it never lands on a live
            -- one. Roll it: four casts inside a single Lifebloom's seven
            -- seconds, which is what the author's log had (stacks = 3).
            local rec2 = {}
            for k, v in pairs(rec) do rec2[k] = v end
            rec2.ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
            for i = 1, rec.n do
                rec2.ev.t[i], rec2.ev.kind[i] = rec.ev.t[i], rec.ev.kind[i]
                rec2.ev.tgt[i], rec2.ev.amt[i], rec2.ev.x[i] =
                    rec.ev.tgt[i], rec.ev.amt[i], rec.ev.x[i]
            end
            rec2.n = rec.n
            local lb = SP.MaxRankBinds().Lifebloom
            local last = rec.ev.t[rec.n] or 0
            for i = 1, 4 do
                rec2.n = rec2.n + 1
                rec2.ev.t[rec2.n] = last + i * 1.5
                rec2.ev.kind[rec2.n] = K.OWNCAST
                rec2.ev.tgt[rec2.n], rec2.ev.amt[rec2.n], rec2.ev.x[rec2.n] = 1, 220, lb
            end
            rec2.dur = math.max(rec.dur or 0, last + 8)
            local scX = SM.ScenarioFromRecording(rec2, kitX)
            local okS, clsOrErr = pcall(SP.Classify, rec2, scX, nothing, kitX)
            check("Classify survives a plan with no rollStacks at all",
                okS, tostring(clsOrErr))
            local labels = {}
            for _, c in ipairs((okS and clsOrErr and clsOrErr.casts) or {}) do
                labels[#labels + 1] = c.label
            end
            -- (a "stack" label would only appear for a plan that HAS a roll
            -- target; the point here is that a plan without one does not crash)
            check("...and it really did classify the casts", #labels >= 3,
                string.format("%d cast(s): %s", #labels, table.concat(labels, ",")))
        end

        -- and the whole replay path, which is what actually broke
        local kit2 = MD.RankMath:SpellKit({ live = true })
        local sc = SM.ScenarioFromRecording(rec, kit2)
        SP.plans[rec.id] = SP.MakeStrategy(SP.Strategy("solver-blind"),
            SP.MaxRankBinds(), kit2, { scenario = sc, seed = rec.id or 1 })
        local okRep, err2 = pcall(SP.Replay, rec, { dt = 0.25, force = true })
        check("SP.Replay survives a solver plan", okRep, tostring(err2))
        SP.plans[rec.id] = nil
    end
end

--------------------------------------------------------------------------------
-- 9. T46 (P2): the search reaches every seed, the solver prices Swiftmend the
-- way the engine lands it, and a preempted plan is asked again when it is free.
--------------------------------------------------------------------------------
do
    -- B6: `noDirect` is in the search's key, so the HoTs-only seed is evaluated
    local rec = MD.FightRecorder:Get(1)
    local kitS = MD.RankMath:SpellKit()
    local sc = SM.ScenarioFromRecording(rec, kitS)
    local realNew, built, hotsOnly = SP.NewPlan, 0, 0
    SP.NewPlan = function(b, params, k)
        built = built + 1
        if params and params.noDirect then hotsOnly = hotsOnly + 1 end
        return realNew(b, params, k)
    end
    local done = false
    SP.Search(sc, { kit = kitS, binds = SP.MaxRankBinds(), maxEvals = 60 }, nil,
        function() done = true end)
    local frames = 0
    while not done and frames < 20000 do _G.STUB.Tick(0.016); frames = frames + 1 end
    SP.NewPlan = realNew
    check("a HoTs-only (noDirect) plan is built during the search",
        done and hotsOnly > 0, string.format("%d plan(s) built, %d HoTs-only", built, hotsOnly))

    -- ...and no two seeds are the same point
    local seeds = SP.SearchSeeds and SP.SearchSeeds()
    local keys, dup = {}, nil
    for _, p in ipairs(seeds or {}) do
        local k = SP.ParamKey(p)
        if keys[k] then dup = k end
        keys[k] = true
    end
    check("the search's seeds are distinct points",
        seeds ~= nil and #seeds >= 3 and dup == nil,
        seeds and string.format("%d seed(s)%s", #seeds, dup and (", duplicate " .. dup) or "") or "no SP.SearchSeeds")
end

do
    -- B8: both HoTs rolling, the engine's Swiftmend eats Regrowth (SimModel's
    -- LandCast, TBC's rule); the solver must price that one. Eating the
    -- Rejuvenation here would be worth 5000, the Regrowth 1.
    local SMID = MD.SpellData.maxRank.Swiftmend
    local entry = { family = "Swiftmend", type = "instant", cost = 100, cast = 1.5,
                    swiftmendRejuv = 5000, swiftmendRegrowth = 1 }
    local kitB = { caster = { [SMID] = entry } }
    local plan = SV.NewPlan({ Swiftmend = SMID }, { minValue = 0, horizon = 12 }, kitB)
    local St = state(5000, 0)
    local function hot(fam)
        return { active = true, spellID = 0, tick = 0, tickPeriod = 3, ticksLeft = 0, expires = 30,
                 stacks = 1, bloom = 0, gen = 1, family = fam }
    end
    St.hots[1][SM.HOT_INDEX.Rejuvenation] = hot("Rejuvenation")
    St.hots[1][SM.HOT_INDEX.Regrowth] = hot("Regrowth")
    local _, id, _, saved = plan:Best(St, 10, 99999, "caster", 0)
    check("with both HoTs rolling the solver's Swiftmend eats Regrowth, as the engine does",
        id == SMID and saved ~= nil and saved < 100,
        string.format("id=%s saved=%s", tostring(id), tostring(saved)))
    check("the solver writes nothing onto the shared kit entry",
        entry.swiftmendAmount == nil, "swiftmendAmount=" .. tostring(entry.swiftmendAmount))
end

do
    -- B7: a 2.9 s cast started at 0 and preempted by a fixed cast at 0.5 frees
    -- the healer at 2.0 (the fixed cast's global cooldown); the plan is asked
    -- then, not at the cancelled cast's landing time
    local HT = MD.SpellData.maxRank.HealingTouch
    local kitP = { caster = { [HT] = { family = "HealingTouch", type = "direct", cast = 2.9,
                                       cost = 100, direct = 500 } } }
    local asked = {}
    local plan = { Decide = function(_, S2, at)
        asked[#asked + 1] = at
        return HT, 1, 2
    end, noReaction = true }
    local sc = { dur = 8, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kitP, floor = 0.30, ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} },
                 targets = { { name = "T", role = "TANK", maxHP = 10000, hp0 = 2000, tracked = true } },
                 fixed = { { 0.5, 8921, 50, -1 } } }
    SM:Run(sc, plan, { critMode = "ev" })
    local shown = {}
    for j = 1, math.min(4, #asked) do shown[j] = string.format("%.2f", asked[j]) end
    check("after a fixed cast preempts a 2.9 s cast at 0.5 s, the plan is asked at 2.0",
        asked[1] == 0 and asked[2] ~= nil and math.abs(asked[2] - 2.0) < 1e-6,
        "asked at " .. table.concat(shown, ", "))
end

do
    -- B7 follow-up: after the preemption the plan answers with ANOTHER cast
    -- that has a cast time (Regrowth, 2.0 s at 2.0). The cancelled Healing
    -- Touch's landing event is still in the heap at 2.9; it must not land the
    -- cancelled spell and swallow the Regrowth. What lands is the Regrowth, at
    -- its own time, and the Healing Touch never succeeds.
    local HT = MD.SpellData.maxRank.HealingTouch
    local RG = MD.SpellData.maxRank.Regrowth
    local kitP = { caster = {
        [HT] = { family = "HealingTouch", type = "direct", cast = 2.9, cost = 100, direct = 500 },
        [RG] = { family = "Regrowth", type = "direct", cast = 2.0, cost = 70, direct = 300 } } }
    local n = 0
    local plan = { Decide = function()
        n = n + 1
        if n == 1 then return HT, 1, 2 end
        if n == 2 then return RG, 1, 2 end
        return nil
    end, noReaction = true }
    local sc = { dur = 8, pool = 9000, initial = { mana = 9000, apiBase = 10, apiCasting = 4 },
                 kit = kitP, floor = 0.30, ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} },
                 targets = { { name = "T", role = "TANK", maxHP = 10000, hp0 = 2000, tracked = true } },
                 fixed = { { 0.5, 8921, 50, -1 } } }
    local tr = {}
    SM:Run(sc, plan, { critMode = "ev", trace = tr })
    local T, TK = tr.built, SM.TK
    local rgAt, htCast, seen = nil, false, {}
    for i = 1, T.nEv do
        if T.ev.kind[i] == TK.CAST then
            seen[#seen + 1] = string.format("%.2f:%s", T.ev.t[i], tostring(T.ev.a[i]))
            if T.ev.a[i] == RG then rgAt = T.ev.t[i] end
            if T.ev.a[i] == HT then htCast = true end
        end
    end
    check("a Regrowth committed at 2.0 after the preemption lands at 4.0, its own time",
        rgAt ~= nil and math.abs(rgAt - 4.0) < 1e-6, "casts " .. table.concat(seen, ", "))
    check("the preempted Healing Touch never succeeds (its stale landing is dropped)",
        not htCast, "casts " .. table.concat(seen, ", "))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
if #fails > 0 then for _, m in ipairs(fails) do print("  FAIL " .. m) end; os.exit(1) end
