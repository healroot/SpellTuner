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
-- 6: a burst at 20 s changes nothing the plan does before it (the invariant
--    on a v3 scenario)
--------------------------------------------------------------------------------
do
    local V3K = { DMG = 1, HEAL = 15, OWNCAST = 3, CASTSTART = 6, CANCEL = 7, DIED = 9 }
    local function scenarioRec(burst)
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
            v = 3, client = "forever", id = burst and 9000000002 or 9000000001, zone = "Test",
            t0 = 0, dur = 40, pool = 9000,
            roster = {
                { name = "Healroot", guid = "Player-1", class = "DRUID", role = "HEALER",
                  level = 64, maxHP = 375, maxSecret = false },
                { name = "Tank", guid = "Party-1-guid", class = "WARRIOR", role = "TANK",
                  level = 64, maxHP = 10000, maxSecret = false },
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

    local function castsOf(burst)
        local out = {}
        local sc = SM.ScenarioFromRecording(scenarioRec(burst), kit)
        SP.RunPlan(sc, plan, { critMode = "ev",
            onCast = function(_, at, id) out[#out + 1] = string.format("%.2f:%d", at, id) end })
        return out
    end

    local quiet, loud = castsOf(false), castsOf(true)
    local diverged
    for j = 1, math.min(#quiet, #loud) do
        local at = tonumber(quiet[j]:match("^([%d%.]+)"))
        if quiet[j] ~= loud[j] then diverged = diverged or at end
    end
    check("a burst at 20 s changes nothing the plan does before it",
        diverged == nil or diverged >= 19.9,
        diverged and string.format("diverged at %.1fs", diverged) or "identical until the burst")
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
-- The record, not an assertion (acceptance 2): solver vs rules on the
-- fixture.
--------------------------------------------------------------------------------
do
    local binds = SP.BindsFromRecording(recGood, kit)
    local sc = SM.ScenarioFromRecording(recGood, kit)
    local rulesPlan = SP.NewPlan(binds, { swiftmendBelow = 0.30, directBelow = 0.45, rollStacks = 3,
        hotBelow = 0.80, filler = false }, kit)
    local solverPlan = SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit, { scenario = sc })
    local rulesR = SP.RunPlan(sc, rulesPlan, { critMode = "ev" })
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
