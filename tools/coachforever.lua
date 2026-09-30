-- tools/run.sh tools/coachforever.lua
--
-- T17 (docs/tasks/T17-coach-forever.md): the coach and the solver on a v3
-- (Forever) recording -- SP.Coach finds a plan, the plan never binds a
-- family the player did not have (and, on this kit, never Lifebloom --
-- Forever has none, plan Sec1.1), SP.Card renders ASCII with no bare pipe
-- and names the gates it rests on, SP.Classify labels every recorded cast,
-- the solver (Engine/SimSolver.lua) runs as a strategy on the Forever kit,
-- the causality invariant still holds on a v3 scenario, SP.Mark/SP.Progress
-- keep a zone's mark, and the asynchronous coach (SP.CoachAsync) fills the
-- replay window's suggested column. Forever only, on tools/foreverfixture.lua
-- streams plus a hand-built v3 recording for the causality check.
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
S.crit[4] = 0 -- zero Nature crit: the fixture's own-heal amounts are the engine's exact figures

local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

MD:SetModule("SpellTuner_Replay", true) -- loads Recorder, Kit/Scenario/Gates, the engine chain and this module's commands

local buildFixture = dofile(here .. "/foreverfixture.lua")
local SM, SP, SV = MD.SimModel, MD.SimPlanner, MD.SimSolver
local kit = MD.RankMath:SpellKit()

--------------------------------------------------------------------------------
-- The clean recording, consistent (tools/reviewforever.lua's own pattern):
-- the meter and mana curve are set to what the engine itself produces
-- replaying the fixture's own casts, so this recording passes every gate.
--------------------------------------------------------------------------------
local function DeepCopy(a)
    local t = {}
    for i = 1, #a do t[i] = a[i] end
    return t
end
local baseSc = SM.ScenarioFromRecording(buildFixture(), kit)
local baseRun = SM:Run(baseSc, nil, { critMode = "ev" })
local baseSimOwn = (baseRun.healed or 0) - ((baseRun.healByFamily and baseRun.healByFamily.foreign) or 0)
local baseManaCurve = DeepCopy(baseRun.manaCurve)

local recGood = buildFixture({ meter = { own = baseSimOwn, others = 0, bySource = {}, bySpell = {}, read = "current" } })
recGood.id = 2000000000
recGood.zone = "Blood Furnace"
recGood.mana.v = DeepCopy(baseManaCurve)
MD.cdb.recordings = { recGood }

--------------------------------------------------------------------------------
-- 1: the coach finds a plan for a clean v3 recording
--------------------------------------------------------------------------------
local card, validation, cls, best = SP.Coach(recGood, { n = 1 })
check("the coach finds a plan for a clean v3 recording",
    type(card) == "table" and #card > 0 and best ~= nil and validation ~= nil and validation.ok == true,
    "validation=" .. tostring(validation and validation.ok) .. " best=" .. tostring(best))

--------------------------------------------------------------------------------
-- 2: the plan binds only families the player had at that pull, and never
--    Lifebloom
--------------------------------------------------------------------------------
do
    -- `known` names one id per family -- the top rank the player had at that
    -- pull -- so a lower rank of the SAME family (774, the Rejuvenation R1
    -- the fixture also casts) is a legitimate bind; a family absent from
    -- `known` altogether, or a rank ABOVE what `known` names, is not.
    local known = recGood.initial.known
    local SD = MD.SpellData
    local badBind
    for _, fam in ipairs(SP.BINDABLE) do
        local id = best.binds[fam]
        if id then
            local sd = SD.spells[id]
            local knownID = known[fam]
            local knownSd = knownID and SD.spells[knownID]
            if not (sd and knownSd and sd.family == knownSd.family and sd.rank <= knownSd.rank) then
                badBind = fam .. "=" .. tostring(id)
            end
        end
    end
    check("the plan binds only families the player had at that pull, and never Lifebloom",
        badBind == nil and best.binds.Lifebloom == nil,
        "badBind=" .. tostring(badBind) .. " lifebloom=" .. tostring(best.binds.Lifebloom))
end

--------------------------------------------------------------------------------
-- 3: the card renders, ASCII, with no bare pipe, naming the gates it rests on
--------------------------------------------------------------------------------
do
    local function Pipes(s)
        local stripped = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "")
        return stripped:find("|", 1, true) ~= nil
    end
    local function NonAscii(s) return s:find("[^ -~]") ~= nil end
    local bad, sawGates = {}, false
    for _, line in ipairs(card) do
        if Pipes(line) then bad[#bad + 1] = "bare pipe: " .. line end
        if NonAscii(line) then bad[#bad + 1] = "not ASCII: " .. line end
        if line:find("gates", 1, true) then sawGates = true end
    end
    check("the card renders, ASCII, with no bare pipe, naming the gates it rests on",
        #bad == 0 and sawGates, bad[1])
end

--------------------------------------------------------------------------------
-- 4: every recorded cast gets a label
--------------------------------------------------------------------------------
do
    local ownCasts = 0
    for i = 1, (recGood.n or 0) do
        if recGood.ev.kind[i] == 3 then ownCasts = ownCasts + 1 end -- V3 OWNCAST
    end
    local labelled = #(cls.casts or {})
    local allLabelled = true
    for _, c in ipairs(cls.casts or {}) do
        if not c.label then allLabelled = false end
    end
    check("every recorded cast gets a label",
        labelled == ownCasts and labelled > 0 and allLabelled,
        string.format("labelled=%d ownCasts=%d", labelled, ownCasts))
end

--------------------------------------------------------------------------------
-- 5: the solver runs as a strategy on the Forever kit
--------------------------------------------------------------------------------
do
    local binds = SP.BindsFromRecording(recGood, kit)
    local sc = SM.ScenarioFromRecording(recGood, kit)
    local entry = SP.Strategy("solver-blind")
    local solverPlan = entry and SP.MakeStrategy(entry, binds, kit, { scenario = sc })
    local okRun, r = pcall(function() return SP.RunPlan(sc, solverPlan, { critMode = "ev" }) end)
    check("the solver runs as a strategy on the Forever kit",
        entry ~= nil and solverPlan ~= nil and solverPlan.kind == "solver"
        and okRun and type(r) == "table" and type(r.manaSpent) == "number",
        "entry=" .. tostring(entry) .. " okRun=" .. tostring(okRun) .. " err=" .. tostring(not okRun and r or nil))
end

--------------------------------------------------------------------------------
-- R23 (review 2026-09-29): Data/Intuition_TBC.lua is on the TBC TOC only, so
-- on Forever there is no shipped prior. "Solver: intuition from many raids"
-- is not offered, and a corpus strategy handed in anyway is refused rather
-- than silently run as the no-intuition solver under the prior's name.
--------------------------------------------------------------------------------
do
    local offered = false
    for _, e in ipairs(SP.STRATEGY_SET) do
        if e.params and e.params.corpus then offered = true end
    end
    local binds = SP.BindsFromRecording(recGood, kit)
    local sc = SM.ScenarioFromRecording(recGood, kit)
    local handIn = { key = "solver-corpus", label = "Solver: intuition from many raids", kind = "solver",
                     why = "test", params = { minValue = 15, horizon = 18, corpus = true } }
    local plan = SP.MakeStrategy(handIn, binds, kit, { scenario = sc })
    check("R23: with no shipped prior the many-raids strategy is neither offered nor run without it",
        MD.IntuitionTBC == nil and not offered and SP.Strategy("solver-corpus") == nil and plan == nil,
        "offered=" .. tostring(offered) .. " plan=" .. tostring(plan))
end

--------------------------------------------------------------------------------
-- 6: a burst at 20 s changes nothing the plan does before it (the invariant
--    on a v3 scenario)
--------------------------------------------------------------------------------
do
    local V3K = { DMG = 1, HEAL = 15, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9 }
    -- opts: id, level (the Tank's), name (the Tank's), secret (default true:
    -- the party member's max is secret on Forever, so the causality
    -- assertion runs with it secret -- T17b), maxHP (when not secret).
    local function scenarioRec(burst, opts)
        opts = opts or {}
        local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
        local n = 0
        local function push(t, kind, tgt, amt, x)
            n = n + 1
            ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = t, kind, tgt, amt, x
        end
        for t = 2, 18, 4 do push(t, V3K.DMG, 2, 300, 0) end
        if burst then
            for t = 20, 28, 4 do push(t, V3K.DMG, 2, 1200, 0) end
        end
        local mana = { t = {}, v = {}, base = {}, cast = {} }
        for t = 2, 40, 2 do
            local i = #mana.t + 1
            mana.t[i], mana.v[i], mana.base[i], mana.cast[i] = t, 9000, 69.24, 28.33
        end
        return {
            v = 3, client = "forever", id = opts.id or (burst and 9000000002 or 9000000001), zone = "Test",
            t0 = 0, dur = 40, pool = 9000,
            roster = {
                { name = "Healroot", guid = "Player-1", class = "DRUID", role = "HEALER",
                  level = 64, maxHP = 375, maxSecret = false },
                { name = opts.name or "Tank", guid = "Party-1-guid", class = "WARRIOR", role = "TANK",
                  level = opts.level or 64,
                  maxHP = (opts.secret == false) and (opts.maxHP or 10000) or -1,
                  maxSecret = opts.secret ~= false },
            },
            tracked = { 1, 2 },
            ev = ev, n = n,
            mana = mana, manaModelled = true,
            deaths = {}, restriction = {}, names = {},
            initial = {
                mana = 9000, form = "caster",
                known = { HealingTouch = 5185, Rejuvenation = 1058 },
                auras = {},
            },
            meter = { own = 0, others = 0, bySource = {}, bySpell = {}, read = "current" },
            unreadable = 0, truncated = false, raid = false, pinned = false,
        }
    end

    local binds = SP.MaxRankBinds({ HealingTouch = 5185, Rejuvenation = 1058 })
    local plan = SP.NewPlan(binds, { swiftmendBelow = 0.30, directBelow = 0.45, rollStacks = 3,
        hotBelow = 0.80, filler = false }, kit)

    -- The store for this assertion: ONE other recording of Tank (same level,
    -- a different id, no burst), and neither the quiet nor the loud one --
    -- they are two versions of one fight. Restored afterwards.
    local savedStore = MD.cdb.recordings
    MD.cdb.recordings = { scenarioRec(false, { id = 9000000003 }) }

    local function castsOf(burst)
        local out = {}
        local sc = SM.ScenarioFromRecording(scenarioRec(burst), kit)
        SP.RunPlan(sc, plan, { critMode = "ev",
            onCast = function(_, at, id) out[#out + 1] = string.format("%.2f:%d", at, id) end })
        return out
    end

    local quiet, loud = castsOf(false), castsOf(true)
    MD.cdb.recordings = savedStore
    local diverged
    for j = 1, math.min(#quiet, #loud) do
        local at = tonumber(quiet[j]:match("^([%d%.]+)"))
        if quiet[j] ~= loud[j] then diverged = diverged or at end
    end
    check("a burst at 20 s changes nothing the plan does before it",
        diverged == nil or diverged >= 19.9,
        diverged and string.format("diverged at %.1fs", diverged) or "identical until the burst")

    -- T20 (review R6): the same two recordings through the SOLVER, whose
    -- at-risk line came from the whole fight's biggest hit.
    MD.cdb.recordings = { scenarioRec(false, { id = 9000000003 }) }
    local function solverCasts(burst)
        local out = {}
        local sc = SM.ScenarioFromRecording(scenarioRec(burst), kit)
        local sp = SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit,
            { scenario = sc, seed = 1 })
        SP.RunPlan(sc, sp, { critMode = "ev",
            onCast = function(_, at, id) out[#out + 1] = string.format("%.2f:%d", at, id) end })
        return out
    end
    local sq, sl = solverCasts(false), solverCasts(true)
    MD.cdb.recordings = savedStore
    local sdiv
    for j = 1, math.min(#sq, #sl) do
        local at = math.min(tonumber(sq[j]:match("^([%d%.]+)")), tonumber(sl[j]:match("^([%d%.]+)")))
        if sq[j] ~= sl[j] then sdiv = sdiv or at end
    end
    if not sdiv and #sq ~= #sl then
        sdiv = tonumber(((#sq > #sl) and sq[#sl + 1] or sl[#sq + 1]):match("^([%d%.]+)"))
    end
    check("a burst above every earlier hit changes nothing the solver does before it",
        #sq > 0 and (sdiv == nil or sdiv >= 19.9),
        string.format("%d and %d casts, ", #sq, #sl) ..
        (sdiv and string.format("diverged at %.1fs", sdiv) or "identical until the burst"))
end

--------------------------------------------------------------------------------
-- 9-11 (T17b): where a party member's max comes from. Hand-made v3 recordings
-- with the Tank's max secret; the store is set per assertion and restored.
--------------------------------------------------------------------------------
do
    local V3K = { DMG = 1 }
    -- five hits of `amt` on roster index 2, two seconds' worth of mana rows
    local function tankRec(id, name, level, amt, secret, maxHP, burst)
        local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
        local n = 0
        local function push(t, kind, tgt, a, x)
            n = n + 1
            ev.t[n], ev.kind[n], ev.tgt[n], ev.amt[n], ev.x[n] = t, kind, tgt, a, x
        end
        for t = 2, 18, 4 do push(t, V3K.DMG, 2, amt, 0) end
        if burst then push(30, V3K.DMG, 2, 9000, 0) end
        local mana = { t = { 2 }, v = { 9000 }, base = { 69.24 }, cast = { 28.33 } }
        return {
            v = 3, client = "forever", id = id, zone = "Test", t0 = 0, dur = 40, pool = 9000,
            roster = {
                { name = "Healroot", guid = "Player-1", class = "DRUID", role = "HEALER",
                  level = 64, maxHP = 375, maxSecret = false },
                { name = name, guid = "Party-1-guid", class = "WARRIOR", role = "TANK",
                  level = level, maxHP = maxHP or -1, maxSecret = secret ~= false },
            },
            tracked = { 1, 2 }, ev = ev, n = n, mana = mana, manaModelled = true,
            deaths = {}, restriction = {}, names = {},
            initial = { mana = 9000, form = "caster", known = { HealingTouch = 5185 }, auras = {} },
            meter = { own = 0, others = 0, bySource = {}, bySpell = {}, read = "current" },
            unreadable = 0, truncated = false, raid = false, pinned = false,
        }
    end
    local saved = MD.cdb.recordings

    -- 9: same name AND level only, never the one coached
    do
        local coached = tankRec(9100000001, "Tank", 64, 300, true, nil, true)
        local sameLevel = tankRec(9100000002, "Tank", 64, 300, true) -- sizing 1500, hits 300
        local otherLevel = tankRec(9100000003, "Tank", 60, 2000, true)
        local otherName = tankRec(9100000004, "Bob", 64, 4000, true)
        MD.cdb.recordings = { coached, sameLevel, otherLevel, otherName }
        local want = SM.EstimateMaxHP({ 1500 }, { 300, 300, 300, 300, 300 })
        local a = SM.ScenarioFromRecording(coached, kit).targets[2]
        local calm = tankRec(9100000001, "Tank", 64, 300, true) -- the coached one without its burst
        MD.cdb.recordings = { calm, sameLevel, otherLevel, otherName }
        local b = SM.ScenarioFromRecording(calm, kit).targets[2]
        check("a party member's max comes from other recordings of the same name and level, never the one coached",
            a.maxHP == want and a.maxSource == "others" and b.maxHP == want and b.maxSource == "others",
            string.format("want=%s burst=%s/%s calm=%s/%s", tostring(want), tostring(a.maxHP),
                tostring(a.maxSource), tostring(b.maxHP), tostring(b.maxSource)))
    end

    -- 10: a plain max elsewhere is taken as it is
    do
        local coached = tankRec(9100000011, "Tank", 64, 300, true)
        local plain = tankRec(9100000012, "Tank", 64, 300, false, 5000)
        MD.cdb.recordings = { coached, plain }
        local t = SM.ScenarioFromRecording(coached, kit).targets[2]
        check("a plain max in another recording is taken as it is",
            t.maxHP == 5000 and t.maxSource == "recorded",
            string.format("maxHP=%s source=%s", tostring(t.maxHP), tostring(t.maxSource)))
    end

    -- 11: the exclusion is required; a recording with no id is not trusted
    do
        local other = tankRec(9100000022, "Tank", 64, 300, true)
        local recs = { other }
        local okCall = pcall(SM.PartyMaxFromOthers, recs, nil, "Tank", 64)
        local noId = tankRec(nil, "Tank", 64, 300, true)
        MD.cdb.recordings = { other, noId }
        local t = SM.ScenarioFromRecording(noId, kit).targets[2]
        check("the exclusion is required",
            okCall == false and t.maxSource == "this fight",
            string.format("pcall=%s source=%s", tostring(okCall), tostring(t.maxSource)))
    end

    -- T20b: a target's danger prior is the biggest hit that person took in
    -- OTHER recordings of the same name and level, over this scenario's max
    do
        local dangerHits = (MD.db and MD.db.simDangerHits) or 1
        local coached = tankRec(9100000031, "Tank", 64, 300, true, nil, true)
        local sameLevel = tankRec(9100000032, "Tank", 64, 700, false, 5000) -- biggest hit H = 700
        local otherLevel = tankRec(9100000033, "Tank", 60, 2000, true)      -- a bigger hit, another level
        MD.cdb.recordings = { coached, sameLevel, otherLevel }
        local t = SM.ScenarioFromRecording(coached, kit).targets[2]
        local want = math.min(1, 700 * dangerHits / t.maxHP)
        local noId = tankRec(nil, "Tank", 64, 300, true, nil, true)
        MD.cdb.recordings = { noId, sameLevel, otherLevel }
        local u = SM.ScenarioFromRecording(noId, kit).targets[2]
        check("a Forever target's danger prior comes from other recordings of the same name and level",
            t.dangerPrior == want and u.dangerPrior == nil,
            string.format("prior=%s want=%s (maxHP %s) noId=%s", tostring(t.dangerPrior), tostring(want),
                tostring(t.maxHP), tostring(u.dangerPrior)))

        -- T46 (P2, review A18): the store handed in as the third argument
        -- reaches the v3 builder. The Replay module's wrapper was `(rec, kit)`
        -- and dropped it, so a curated leave-one-out store was ignored and the
        -- prior came from MD.cdb.recordings (here: nothing but the coached fight).
        MD.cdb.recordings = { coached }
        local v = SM.ScenarioFromRecording(coached, kit, { coached, sameLevel, otherLevel }).targets[2]
        check("the store passed as ScenarioFromRecording's third argument reaches the v3 builder",
            v.dangerPrior ~= nil and v.dangerPrior == t.dangerPrior,
            string.format("passed=%s via cdb=%s", tostring(v.dangerPrior), tostring(t.dangerPrior)))
    end

    MD.cdb.recordings = saved
end

--------------------------------------------------------------------------------
-- 7: the zone's marks are kept and read back
--------------------------------------------------------------------------------
do
    local mark = MD.cdb.coachMarks and MD.cdb.coachMarks[recGood.zone]
    local wroteOnCoach = mark ~= nil and mark.t ~= nil

    -- a mark for a DIFFERENT zone must not clobber this one -- the same
    -- consistent recording (so it too clears every gate), just relabelled.
    local otherRec = buildFixture({ meter = { own = baseSimOwn, others = 0, bySource = {}, bySpell = {}, read = "current" } })
    otherRec.id = 2100000000
    otherRec.zone = "Ramparts"
    otherRec.mana.v = DeepCopy(baseManaCurve)
    local _, otherValidation = SP.Coach(otherRec, { n = 2 })
    local stillHere = MD.cdb.coachMarks[recGood.zone] ~= nil
    local otherHere = MD.cdb.coachMarks["Ramparts"] ~= nil

    -- read back: three later fights in the same zone let SP.Progress speak
    MD.fightHistory = MD.fightHistory or {}
    for i = 1, 3 do
        MD.fightHistory[#MD.fightHistory + 1] = { zone = recGood.zone, t = (mark and mark.t or 0) + i,
            hpBuckets = { 10, 5, 2 } }
    end
    local progress = SP.Progress(recGood.zone)

    check("the zone's marks are kept and read back",
        wroteOnCoach and stillHere and otherHere and type(progress) == "string",
        string.format("wrote=%s stillHere=%s otherHere=%s progress=%s",
            tostring(wroteOnCoach), tostring(stillHere), tostring(otherHere), tostring(progress)))
end

--------------------------------------------------------------------------------
-- 8: the asynchronous coach finishes and fills the replay window's suggested
--    column
--------------------------------------------------------------------------------
do
    MD.cdb.recordings = { recGood }
    SlashCmdList.SPELLTUNER("coach 1 force")
    local frames = 0
    while MD.coachSearch and frames < 20000 do S.Tick(0.016); frames = frames + 1 end
    assert(MD.coachSearch == nil, "coach search never finished (" .. frames .. " frames)")
    SlashCmdList.SPELLTUNER("replay 1")
    local W = MD.Replay._state()
    check("the asynchronous coach finishes and fills the replay window's suggested column",
        W.right ~= nil and W.right.state ~= nil and W.rp.right ~= nil,
        string.format("frames=%d right=%s", frames, tostring(W.right)))
    if W.frame then W.frame:Hide() end
end

--------------------------------------------------------------------------------
-- 12, 13 (T17b): the plan is flagged foresees, and the card says so, only
-- when a party member's max had to come from the fight being coached.
--------------------------------------------------------------------------------
do
    local saved = MD.cdb.recordings
    local function causalLines(c)
        local starts, any = 0, 0
        local first
        for _, line in ipairs(c) do
            if line:find("  NOT causal - sees this fight:", 1, true) == 1 then starts = starts + 1; first = first or line end
            if line:find("NOT causal", 1, true) then any = any + 1 end
        end
        return starts, any, first
    end

    MD.cdb.recordings = { recGood }
    local c12, _, _, best12 = SP.Coach(recGood, { n = 1 })
    local starts12, _, first12 = causalLines(c12 or {})
    print("--- the card, store holding only the coached recording:")
    for _, line in ipairs(c12 or {}) do print("    " .. line) end
    check("with no other recording of them, the plan is flagged foresees and its card says so",
        best12 ~= nil and best12.foresees == true and starts12 == 1
        and first12 ~= nil and first12:find("Tank", 1, true) ~= nil,
        "foresees=" .. tostring(best12 and best12.foresees) .. " lines=" .. starts12)

    local another = buildFixture({ meter = { own = baseSimOwn, others = 0, bySource = {}, bySpell = {}, read = "current" } })
    another.id = 2300000000
    another.zone = "Blood Furnace"
    another.mana.v = DeepCopy(baseManaCurve)
    MD.cdb.recordings = { recGood, another }
    local c13, v13, _, best13 = SP.Coach(recGood, { n = 1, force = true })
    local _, any13 = causalLines(c13 or {})
    check("with another recording of them, the plan is not flagged and the card says nothing",
        best13 ~= nil and best13.foresees ~= true and any13 == 0,
        "foresees=" .. tostring(best13 and best13.foresees) .. " lines=" .. any13)
    MD.cdb.recordings = saved
end

--------------------------------------------------------------------------------
-- review-replay R26: the coach card's own colour codes reach chat as colour
-- codes -- not escaped into literal "||cff888888" text -- while everything
-- else stays escaped (no bare pipe).
-- review-replay R12: "/st coach N health" (the card's own hint) picks that
-- strategy from the last search without searching again; before any search
-- it says to run one first.
--------------------------------------------------------------------------------
do
    local saved = MD.cdb.recordings
    MD.cdb.recordings = { recGood }
    local lines = CapturedChat(function()
        SlashCmdList.SPELLTUNER("coach 1")
        local f = 0
        while MD.coachSearch and f < 20000 do S.Tick(0.016); f = f + 1 end
    end)
    local sawColour, escaped, bare = false, nil, nil
    for _, l in ipairs(lines) do
        if l:find("|cff888888", 1, true) and not l:find("||cff888888", 1, true) then sawColour = true end
        if l:find("||c", 1, true) or l:find("||r", 1, true) then escaped = escaped or l end
        local stripped = l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "")
        if stripped:find("|", 1, true) then bare = bare or l end
    end
    check("the coach card's colour codes reach chat unescaped, with no bare pipe (R26)",
        sawColour and escaped == nil and bare == nil,
        "sawColour=" .. tostring(sawColour) .. " escaped=" .. tostring(escaped) .. " bare=" .. tostring(bare))

    local w = SP.strategies[recGood.id] and SP.strategies[recGood.id].health
    SP.plans[recGood.id] = nil
    local picked = CapturedChat(function() SlashCmdList.SPELLTUNER("coach 1 health") end)
    local startedSearch = MD.coachSearch ~= nil
    if MD.coachSearch then MD.coachSearch:Cancel(); MD.coachSearch = nil end
    local saidIt = false
    for _, l in ipairs(picked) do if l:find("Highest health", 1, true) then saidIt = true end end

    local savedStrat = SP.strategies[recGood.id]
    SP.strategies[recGood.id] = nil
    local none = CapturedChat(function() SlashCmdList.SPELLTUNER("coach 1 cheap") end)
    local startedSearch2 = MD.coachSearch ~= nil
    if MD.coachSearch then MD.coachSearch:Cancel(); MD.coachSearch = nil end
    SP.strategies[recGood.id] = savedStrat
    local saidFirst = false
    for _, l in ipairs(none) do if l:find("no strategies", 1, true) then saidFirst = true end end
    MD.cdb.recordings = saved

    check("/st coach N health plays that strategy without searching again, and says to search first (R12)",
        w ~= nil and SP.plans[recGood.id] == w.plan and not startedSearch and saidIt
        and not startedSearch2 and saidFirst,
        string.format("winner=%s plan=%s searched=%s said=%s searched2=%s saidFirst=%s", tostring(w),
            tostring(SP.plans[recGood.id] == (w and w.plan)), tostring(startedSearch), tostring(saidIt),
            tostring(startedSearch2), tostring(saidFirst)))
end

--------------------------------------------------------------------------------
-- The record, not an assertion (acceptance 2): solver vs rules on the
-- fixture.
--------------------------------------------------------------------------------
do
    local binds = SP.BindsFromRecording(recGood, kit)
    local sc = SM.ScenarioFromRecording(recGood, kit)
    local rulesPlan = SP.NewPlan(binds, { swiftmendBelow = 0.30, directBelow = 0.45, rollStacks = 3,
        hotBelow = 0.80, filler = false }, kit)
    local solverPlan = SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit, { scenario = sc })
    -- a run's result belongs to the engine's pool slot, so the first is copied
    -- before the second runs (until 2026-09-29 both columns printed the solver's)
    local r1 = SP.RunPlan(sc, rulesPlan, { critMode = "ev" })
    local rulesR = { manaSpent = r1.manaSpent, deaths = { n = r1.deaths.n }, floorSeconds = r1.floorSeconds }
    local solverR = SP.RunPlan(sc, solverPlan, { critMode = "ev" })
    print(string.format(
        "solver vs rules on the fixture: mana %d vs %d, deaths %d vs %d, floor seconds %.1f vs %.1f",
        solverR.manaSpent or 0, rulesR.manaSpent or 0,
        (solverR.deaths and solverR.deaths.n) or 0, (rulesR.deaths and rulesR.deaths.n) or 0,
        solverR.floorSeconds or 0, rulesR.floorSeconds or 0))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
