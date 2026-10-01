-- tools/run.sh tools/classcoach.lua
--
-- T106 (docs/SPEC-next.md 4.3 and section 11): a class is granted `coach` and
-- `practice` when its committed book fixture passes this suite. For each of the
-- three Forever classes after the druid -- Paladin, Shaman, Priest (decision 7's
-- order) -- with its level 60 book (tools/stub_books.lua, talentsforever's
-- extract of the beta client's own texts):
--
--   1. the class logs in with its own profile (Data/Profile_<Class>_Forever.lua)
--      and is granted coach and practice;
--   2. the book becomes a valid kit stamped with the class's profile, every
--      family the profile names in it with the profile's kit type, the
--      profile's dashboard order and HoT slots;
--   3. a synthetic five-man fight -- damage on the party, the class's heals cast
--      on it, a spell the kit does not model cast too, recorded as the Forever
--      recorder writes a v3 stream -- replays through the eight gates;
--   4. the solver coaches it: its plan casts the class's heals, nobody dies,
--      it is the card's best, and the card names the spells the kit does not
--      model and (Shaman, Priest) the group assumption (4.5);
--   5. practice runs it: bindings for the class's heals, a session played
--      against the fake clock, and the practice recording replays through the
--      gates with the class's kit;
--   6. the causality test holds: a burst of damage late in the fight changes
--      nothing the solver casts before it.
--
-- The three profile files are listed by the Forever main TOCs (the integrator's
-- line, T106); until they are, this suite loads them where the TOC will.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")
local T = dofile(here .. "/lib/t.lua")
-- A detail is printed only for a failure (tools/profilecheck.lua's rule).
local function check(name, cond, detail)
    if cond or detail == "" then detail = nil end
    return T.check(name, cond, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB

local P = MD.Profiles
local PROFILE_FILES = {
    PALADIN = "Data/Profile_Paladin_Forever.lua",
    SHAMAN = "Data/Profile_Shaman_Forever.lua",
    PRIEST = "Data/Profile_Priest_Forever.lua",
}
local loadError = {}
for _, class in ipairs({ "PALADIN", "SHAMAN", "PRIEST" }) do
    if P.byClass[class] == nil then
        local okL, err = pcall(S.Load, { PROFILE_FILES[class] }, "SpellTuner", MD)
        if not okL then loadError[class] = tostring(err) end
    end
end

MD:SetModule("SpellTuner_Replay", true)
MD:SetModule("SpellTuner_Practice", true)
-- No crit: every heal the engine lands is its text's exact average, so the
-- recorded heals below are the engine's own figures.
for school = 1, 7 do S.crit[school] = 0 end

local SM, SP, SV, PR, RM, Kit = MD.SimModel, MD.SimPlanner, MD.SimSolver, MD.Practice, MD.RankMath, MD.Kit
local V3 = MD.StreamV3.K
local Books = dofile(here .. "/stub_books.lua")

local function LogIn(class)
    S.units.player.class = class
    MD:DetectProfile()
    MD:Fire("CORE_LOGIN")
end

local function Copy(a)
    local t = {}
    for i = 1, #a do t[i] = a[i] end
    return t
end

local function Has(lines, text)
    for _, l in ipairs(lines or {}) do
        if type(l) == "string" and l:find(text, 1, true) then return l end
    end
    return nil
end

local function AsciiCard(lines)
    for _, l in ipairs(lines or {}) do
        local okA, why = T.Ascii(l)
        if not okA then return false, l .. ": " .. tostring(why) end
    end
    return true
end

--------------------------------------------------------------------------------
-- The synthetic fight: who is in it, what hits them, what the healer casts.
--------------------------------------------------------------------------------
local ME, TANK, ROGUE, MAGE, HUNTER = 1, 2, 3, 4, 5
local DUR = 60

local function Roster(class)
    return {
        { name = "Healer", guid = "Player-1", class = class, role = "HEALER", level = 60,
          maxHP = 3200, maxSecret = false },
        { name = "Tank", guid = "Party-1-guid", class = "WARRIOR", role = "TANK", level = 60,
          maxHP = 6500, maxSecret = false },
        { name = "Rogue", guid = "Party-2-guid", class = "ROGUE", role = "DAMAGER", level = 60,
          maxHP = 3800, maxSecret = false },
        { name = "Mage", guid = "Party-3-guid", class = "MAGE", role = "DAMAGER", level = 60,
          maxHP = 3000, maxSecret = false },
        { name = "Hunter", guid = "Party-4-guid", class = "HUNTER", role = "DAMAGER", level = 60,
          maxHP = 3400, maxSecret = false },
    }
end

-- The damage, the same for every class: the tank hit every 2 s, two group-wide
-- hits (what a group heal is for), a few hits on the damage dealers.
local function Damage(burst)
    local out = {}
    for t = 1, DUR - 6, 2 do out[#out + 1] = { t, TANK, 260 + (t * 37) % 160 } end
    for _, at in ipairs({ 14, 34 }) do
        for _, who in ipairs({ ME, TANK, ROGUE, MAGE, HUNTER }) do out[#out + 1] = { at + 0.25, who, 700 } end
    end
    out[#out + 1] = { 22.5, ROGUE, 900 }
    out[#out + 1] = { 27.5, MAGE, 650 }
    out[#out + 1] = { 41.5, HUNTER, 800 }
    if burst then
        for t = 45, 52 do out[#out + 1] = { t + 0.1, ROGUE, 1500 } end
    end
    return out
end

-- The id of a family's highest known rank in the kit's index, and its entry.
local function Top(kit, family)
    local id = MD.SpellData.maxRank[family]
    return id, id and kit.caster[id]
end

-- The book's id of a spell by name (its highest rank listed), for a cast the
-- kit does not model.
local function BookID(name)
    local book = MD.Book:Get()
    local fam = book.families[name]
    local best
    for _, e in ipairs(fam and fam.ranks or {}) do
        if e.known and e.id and (not best or (e.rank or 0) > (best.rank or 0)) then best = e end
    end
    return best and best.id
end

-- A v3 recording (Modules/SpellTuner_Recorder/Recorder_Forever.lua's shape) of
-- `casts` -- { t, family | {name = book name}, target } -- over the damage, with
-- `heals` (the engine's own landings, { t, target, amount }) as HEAL events and
-- `extraHeals` (a heal no kit entry claims) beside them.
local function Recording(class, kit, casts, heals, opts)
    opts = opts or {}
    local events = {}
    local function push(t, kind, tgt, amt, x) events[#events + 1] = { t, kind, tgt, amt, x } end
    for _, d in ipairs(Damage(opts.burst)) do push(d[1], V3.DMG, d[2], d[3], 0) end
    local names = {}
    for _, c in ipairs(casts) do
        local id, e
        if type(c[2]) == "table" then
            id = BookID(c[2].name)
            local be = MD.Book:Get().spells[id]
            e = { cost = be and type(be.cost) == "table" and be.cost.amount or 0, cast = be and be.cast or 0 }
            names[id] = c[2].name
        else
            id, e = Top(kit, c[2])
        end
        if id then
            if (e.cast or 0) > 0 then push(c[1] - e.cast, V3.CASTSTART, c[3], 0, id) end
            push(c[1], V3.OWNCAST, c[3], e.cost or 0, id)
        end
    end
    for _, h in ipairs(heals or {}) do push(h[1], V3.HEAL, h[2], h[3], 0) end
    for _, h in ipairs(opts.extraHeals or {}) do push(h[1], V3.HEAL, h[2], h[3], 0) end
    -- stable by time, then by the order pushed (a cast before its own heal)
    for i, e in ipairs(events) do e[6] = i end
    table.sort(events, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[6] < b[6]
    end)
    local ev = { t = {}, kind = {}, tgt = {}, amt = {}, x = {} }
    for i, e in ipairs(events) do
        ev.t[i], ev.kind[i], ev.tgt[i], ev.amt[i], ev.x[i] = e[1], e[2], e[3], e[4], e[5]
    end
    local mana = { t = {}, v = {}, base = {}, cast = {} }
    for t = 2, DUR, 2 do
        local i = #mana.t + 1
        mana.t[i], mana.v[i], mana.base[i], mana.cast[i] = t, opts.pool or 6000, 12, 4
    end
    local ownCasts, spent = 0, 0
    for i = 1, #events do
        if ev.kind[i] == V3.OWNCAST then ownCasts, spent = ownCasts + 1, spent + (ev.amt[i] or 0) end
    end
    return {
        v = 3, client = "forever", id = opts.id or 1790000000, zone = "Scholomance",
        ownCasts = ownCasts, spent = spent,
        t0 = 0, dur = DUR, pool = opts.pool or 6000, profile = class,
        roster = Roster(class), tracked = { 1, 2, 3, 4, 5 },
        ev = ev, n = #events, mana = mana, manaModelled = true,
        deaths = {}, restriction = {}, names = names,
        initial = { mana = opts.pool or 6000, form = "caster", known = {}, auras = {} },
        meter = opts.meter or { own = 0, others = 0, bySource = {}, bySpell = {}, read = "current" },
        unreadable = 0, truncated = false, raid = false, pinned = false,
        kit = Kit.Snapshot(kit),
    }
end

-- The fight made consistent (tools/coachforever.lua's own pattern): the own
-- heals are where the engine lands them replaying the recorded casts, the
-- modelled mana is the engine's own curve and the meter's own total what the
-- engine healed -- so a correct class kit passes every gate.
local function Fight(class, kit, casts, opts)
    opts = opts or {}
    local rec0 = Recording(class, kit, casts, {}, opts)
    local heals = {}
    SM:Run(SM.ScenarioFromRecording(rec0, kit, {}), nil, { critMode = "ev",
        onHeal = function(t, ti, amount, _, family)
            if family ~= "foreign" and family ~= "recorded" then heals[#heals + 1] = { t, ti, amount } end
        end })
    local rec = Recording(class, kit, casts, heals, opts)
    local run = SM:Run(SM.ScenarioFromRecording(rec, kit, {}), nil, { critMode = "ev" })
    local own = (run.healed or 0) - ((run.healByFamily and run.healByFamily.foreign) or 0)
    rec.meter = { own = own, others = 0, bySource = {}, bySpell = {}, read = "current" }
    rec.mana.v = Copy(run.manaCurve)
    return rec
end

local function GatesText(v)
    local out = {}
    for _, g in ipairs(v and v.gates or {}) do
        if not g.ok then out[#out + 1] = g.name .. ": " .. tostring(g.text) end
    end
    return table.concat(out, "; ")
end

--------------------------------------------------------------------------------
-- The three classes: the heals each one casts in the fight (family, the time
-- the cast succeeds, the target) and the spells its kit does not model.
--------------------------------------------------------------------------------
local CLASSES = {
    {
        class = "PALADIN", label = "Paladin", book = "paladin", group = false,
        casts = {
            { 3, "HolyLight", TANK }, { 6, "FlashOfLight", TANK }, { 9, "HolyShock", TANK },
            { 12, "HolyLight", TANK }, { 16, "FlashOfLight", ROGUE }, { 18, "HolyShock", MAGE },
            { 21, "HolyLight", TANK }, { 24, "FlashOfLight", HUNTER }, { 28, { name = "Divine Favor" }, ME },
            { 29, "HolyShock", ROGUE }, { 32, "HolyLight", TANK }, { 37, "FlashOfLight", ME },
            { 40, "HolyShock", TANK }, { 44, "HolyLight", TANK },
        },
        unmodelled = { "Divine Favor" },
    },
    {
        class = "SHAMAN", label = "Shaman", book = "shaman", group = true,
        casts = {
            { 3, "HealingWave", TANK }, { 4, "Riptide", TANK }, { 8, "LesserHealingWave", TANK },
            { 12, "HealingWave", TANK }, { 17.5, "ChainHeal", MAGE }, { 20, "Riptide", ROGUE },
            { 24, "LesserHealingWave", ROGUE }, { 26, { name = "Nature's Swiftness" }, ME },
            { 29, "HealingWave", TANK }, { 37.5, "ChainHeal", ME }, { 40, "Riptide", TANK },
            { 44, "HealingWave", TANK },
        },
        unmodelled = { "Nature's Swiftness" },
    },
    {
        class = "PRIEST", label = "Priest", book = "priest", group = true,
        casts = {
            { 2, "Renew", TANK }, { 5, "Heal", TANK }, { 8, { name = "Power Word: Shield" }, TANK },
            { 11, "GreaterHeal", TANK }, { 17.5, "PrayerOfHealing", ME }, { 20, "FlashHeal", ROGUE },
            { 23, "BindingHeal", MAGE }, { 26, "Renew", TANK }, { 30, "GreaterHeal", TANK },
            { 36, "HolyNova", ME }, { 38, { name = "Desperate Prayer" }, ME }, { 42, "Heal", HUNTER },
        },
        unmodelled = { "Power Word: Shield", "Desperate Prayer" },
        -- Desperate Prayer heals the caster: the heal lands with its cast and is
        -- replayed exactly as recorded (Scenario_Forever.lua, T101)
        extraHeals = function() return { { 38, ME, 1400 } } end,
    },
}

local results = {}

local function RunClass(C)
    local class, label = C.class, C.label
    T.section(label)
    local undo = Books.Install(Books.Load(C.book), { alone = true, MD = MD })
    LogIn(class)
    local prof = P.byClass[class]

    ----------------------------------------------------------------------------
    -- 1. the profile, and what it grants
    ----------------------------------------------------------------------------
    local canCoach, whyCoach = MD.ClassProfile:Can("coach")
    local canPractise, whyPractise = MD.ClassProfile:Can("practice")
    check(label .. ": logs in with its own profile, granted coach and practice",
        prof ~= nil and MD.ClassProfile == prof and canCoach == true and canPractise == true,
        loadError[class] or string.format("profile=%s coach=%s/%s practice=%s/%s", tostring(prof and prof.class),
            tostring(canCoach), tostring(whyCoach), tostring(canPractise), tostring(whyPractise)))
    if not prof then undo(); LogIn("DRUID"); return end

    ----------------------------------------------------------------------------
    -- 2. the book fixture -> a valid kit stamped with the class's profile
    ----------------------------------------------------------------------------
    local built, kit = pcall(function() return RM:SpellKit() end)
    if not built then kit = nil end
    local valid, problems = false, nil
    if kit then valid, problems = Kit.Validate(kit) end
    local wrong = {}
    for key, def in pairs(prof and prof.families or {}) do
        local fam = MD.SpellData.families and MD.SpellData.families[key]
        local id, e
        if kit then id, e = Top(kit, key) end
        if not fam or fam.type ~= def.kit or not e or e.dataMissing then
            wrong[#wrong + 1] = key .. "=" .. tostring(fam and fam.type) .. (e and e.dataMissing and " (no value)" or "")
        end
    end
    table.sort(wrong)
    check(label .. ": the book becomes a valid kit stamped " .. class .. ", every family the profile's kit type",
        built and valid and kit.profile == class and P.ForKit(kit) == prof and #wrong == 0,
        string.format("built=%s valid=%s first=%s profile=%s wrong=[%s]", tostring(built),
            tostring(valid), tostring(problems and problems[1]), tostring(kit and kit.profile),
            table.concat(wrong, " ")))
    if not (built and kit) then undo(); LogIn("DRUID"); return end

    do
        local order = MD.SpellData.familyOrder or {}
        local prefix = true
        for i, key in ipairs(prof.order or {}) do if order[i] ~= key then prefix = false end end
        local slots = SM.HotSlots(kit)
        local slotsOk = true
        for i, key in ipairs(prof.hotSlots or {}) do
            if slots.index[key] ~= i then slotsOk = false end
        end
        local unmodelledOut = true
        for _, name in ipairs(C.unmodelled) do
            local id = BookID(name)
            if not id or kit.caster[id] or MD.SpellData.spells[id] then unmodelledOut = false end
        end
        check(label .. ": the profile's order and HoT slots; the unmodelled spells are not in the kit",
            prefix and slotsOk and unmodelledOut,
            string.format("order=%s slots=%s unmodelled out=%s", table.concat(order, ","),
                tostring(slotsOk), tostring(unmodelledOut)))
    end

    ----------------------------------------------------------------------------
    -- 3. a synthetic fight replays through the eight gates
    ----------------------------------------------------------------------------
    local rec = Fight(class, kit, C.casts, {
        id = 1790000000 + #results, extraHeals = C.extraHeals and C.extraHeals() or nil })
    MD.cdb.recordings = { rec }
    local v = SM:Validate(rec, kit)
    local nGates = v and #v.gates or 0
    check(label .. ": the synthetic fight replays through the eight gates",
        v ~= nil and v.ok == true and nGates == 8,
        string.format("ok=%s gates=%d failed: %s", tostring(v and v.ok), nGates, GatesText(v)))

    ----------------------------------------------------------------------------
    -- 4. the solver coaches it
    ----------------------------------------------------------------------------
    local binds = SP.BindsFromRecording(rec, kit)
    local okCoach, card, validation, cls, best = pcall(SP.Coach, rec, { n = 1 })
    if not okCoach then card = { tostring(card) } end
    local solver = okCoach and best and best.kind == "solver" and best
        or SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit)
    local sc = SM.ScenarioFromRecording(rec, kit)
    local casts, castFams = 0, {}
    local r = SP.RunPlan(sc, solver, { critMode = "ev", onCast = function(_, _, id)
        casts = casts + 1
        local sd = MD.SpellData.spells[id]
        if sd then castFams[sd.family] = true end
    end })
    local famList = {}
    for fam in pairs(castFams) do famList[#famList + 1] = fam end
    table.sort(famList)
    check(label .. ": the solver coaches it -- its plan casts the class's heals and nobody dies",
        okCoach and casts > 0 and #famList >= 2 and r.deaths.n == 0,
        string.format("coach=%s casts=%d families=%s deaths=%d first=%s", tostring(okCoach), casts,
            table.concat(famList, ","), r.deaths.n, tostring(card and card[1])))
    check(label .. ": the card's best is a solver plan, no threshold-rule rows (the druid's tactics)",
        okCoach and best ~= nil and best.kind == "solver" and validation and validation.ok == true
        and Has(card, "  solver ") ~= nil and Has(card, "max rank") == nil and Has(card, "your binds") == nil,
        string.format("best=%s", tostring(best and (best.kind or "rules"))))
    local okAscii, badLine = AsciiCard(card)
    check(label .. ": the card is ASCII with no bare pipe", okCoach and okAscii, badLine)
    do
        local named = {}
        for _, name in ipairs(C.unmodelled) do
            if not Has(card, name) then named[#named + 1] = name end
        end
        check(label .. ": the card names the spells the kit does not model",
            okCoach and #named == 0, "not named: " .. table.concat(named, ", "))
    end
    do
        -- the live command: /st coach 1 searches across frames (SP.CoachAsync)
        -- and prints the card; the plan it leaves for the replay is the solver's
        local said = {}
        local frame = _G.DEFAULT_CHAT_FRAME
        local orig = frame.AddMessage
        frame.AddMessage = function(_, m) said[#said + 1] = T.Strip(m) end
        SP.plans[rec.id] = nil
        MD:RunCoach("1")
        local n = 0
        while MD.coachSearch and n < 20000 do S.Tick(0.016); n = n + 1 end
        frame.AddMessage = orig
        local plan = SP.plans[rec.id]
        check(label .. ": /st coach 1 coaches it with the solver and names what is not modelled",
            plan ~= nil and plan.kind == "solver" and MD.coachSearch == nil
            and Has(said, "the cheapest heal that holds them above it") ~= nil
            and Has(said, "not modelled, kept as recorded: " .. C.unmodelled[1]) ~= nil,
            string.format("plan=%s lines=%d last=%s", tostring(plan and (plan.kind or "rules")), #said,
                tostring(said[#said])))
    end
    local groupLine = Has(card, SP.GROUP_ASSUMPTION or "?")
    if C.group then
        check(label .. ": the card carries the group assumption", groupLine ~= nil)
    else
        check(label .. ": the card carries no group assumption (no heal reaches several targets)",
            okCoach and groupLine == nil)
    end

    ----------------------------------------------------------------------------
    -- 5. practice runs it
    ----------------------------------------------------------------------------
    do
        local keys, binding = { "1", "2", "3", "4", "5", "6", "7", "8" }, {}
        for i, key in ipairs(prof.order) do binding[i] = { key = keys[i], family = key } end
        MD.db.practiceBinds = binding
        local shown = PR.Binds()
        local setup = PR.DefaultSetup("5", 60)
        setup.dur, setup.fixedSeed = 40, 7
        local errs = {}
        local sess = PR.New(PR.CopySetup(setup), { seed = setup.fixedSeed, noStore = true,
            onError = function(m) errs[#errs + 1] = m end })
        sess:Start()
        -- one press per family in turn, on whoever is lowest, every 3 s
        local nextAt, turn = 0.5, 0
        while sess.state == "running" do
            if sess.clock >= nextAt and sess.S then
                turn = turn % #prof.order + 1
                local low, lowFrac = 1, 2
                for i = 1, sess.S.nT do
                    local f = sess.S.maxHP[i] > 0 and sess.S.hp[i] / sess.S.maxHP[i] or 2
                    if not sess.S.dead[i] and f < lowFrac then low, lowFrac = i, f end
                end
                sess:Cast(PR.SpellFor(binding[turn]), low)
                nextAt = nextAt + 3
            end
            sess:Update(0.05)
        end
        local prec = sess.rec
        local own = 0
        for i = 1, (prec and prec.n or 0) do
            if prec.ev.kind[i] == SM.K.OWNCAST then own = own + 1 end
        end
        local pv = prec and SM:Validate(prec)
        check(label .. ": practice binds the class's heals and plays a session",
            #shown == #prof.order and prec ~= nil and own >= 6 and prec.kit and prec.kit.profile == class,
            string.format("binds=%d rec=%s casts=%d kit=%s errors=[%s]", #shown, tostring(prec ~= nil), own,
                tostring(prec and prec.kit and prec.kit.profile), table.concat(errs, "; ")))
        check(label .. ": the practice fight replays through the gates",
            pv ~= nil and pv.ok == true, GatesText(pv))
    end

    ----------------------------------------------------------------------------
    -- 6. the causality test: a burst at 45 s changes nothing cast before it
    ----------------------------------------------------------------------------
    do
        local function CastsOf(burst)
            local recB = Recording(class, kit, C.casts, {}, { burst = burst, id = 1790000100 })
            local scB = SM.ScenarioFromRecording(recB, kit, {})
            local plan = SP.MakeStrategy(SP.Strategy("solver-blind"), binds, kit)
            local out = {}
            SP.RunPlan(scB, plan, { critMode = "ev", onCast = function(_, at, id, ti)
                out[#out + 1] = string.format("%.2f:%d:%s", at, id, tostring(ti)) end })
            return out
        end
        local quiet, loud = CastsOf(false), CastsOf(true)
        local diverged
        for j = 1, math.min(#quiet, #loud) do
            local at = tonumber(quiet[j]:match("^([%d%.]+)"))
            if quiet[j] ~= loud[j] then diverged = diverged or at end
        end
        check(label .. ": the causality test holds (a burst at 45 s changes nothing cast before it)",
            #quiet > 0 and (diverged == nil or diverged >= 44.9),
            string.format("%d casts; diverged at %s", #quiet, tostring(diverged)))
    end

    results[#results + 1] = class
    undo()
    LogIn("DRUID")
end

for _, C in ipairs(CLASSES) do RunClass(C) end

T.done()
