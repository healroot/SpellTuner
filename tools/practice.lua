-- tools/run.sh tools/practice.lua
--
-- A practice session (Engine/Practice.lua) played by a script against a fake
-- clock. What it holds down:
--   * the damage generator is deterministic in its seed and delivers roughly
--     what the setup asked for;
--   * the session obeys the game: the GCD, the spell queue window, mana, a dead
--     target, Swiftmend with nothing to eat;
--   * the live trace can be read WHILE the fight is running;
--   * the recording replays through the ordinary engine to exactly the health
--     and mana the player saw -- same engine, so no gate may fail -- and the
--     coach answers it;
--   * stopping early keeps what happened and nothing after it.
local here = arg[0]:match("^(.*)/[^/]+$")
HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local S = _G.STUB
local PR, SM, SD, SP = MD.Practice, MD.SimModel, MD.SpellData, MD.SimPlanner

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-58s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local LB, REJ, RG, SWM = SD.maxRank.Lifebloom, SD.maxRank.Rejuvenation, SD.maxRank.Regrowth, SD.maxRank.Swiftmend

-- damage -------------------------------------------------------------------------
local setup = PR.DefaultSetup("5", 64)
setup.dur = 60
check("a party is five, and exactly one of them is you", #setup.targets == 5 and (function()
    local n = 0
    for _, tg in ipairs(setup.targets) do if tg.you then n = n + 1 end end
    return n == 1
end)())
local d1, d2, d3 = PR.BuildDamage(setup, 7), PR.BuildDamage(setup, 7), PR.BuildDamage(setup, 8)
local same = #d1.t == #d2.t
for i = 1, #d1.t do if d1.t[i] ~= d2.t[i] or d1.amt[i] ~= d2.amt[i] then same = false end end
check("the same seed is the same fight", same, #d1.t .. " events")
local differs = #d1.t ~= #d3.t
for i = 1, math.min(#d1.t, #d3.t) do if d1.amt[i] ~= d3.amt[i] then differs = true end end
check("another seed is another fight", differs)
local sorted = true
for i = 2, #d1.t do if d1.t[i] < d1.t[i - 1] then sorted = false end end
check("the timeline is in time order", sorted)
do
    -- the tank's steady damage, spikes and AoE off: close to dps x maxHP x time
    local s2 = PR.DefaultSetup("2", 70)
    s2.dur, s2.aoe = 300, nil
    s2.targets[1].spike, s2.targets[2].spike = 0, 0
    local ev = PR.BuildDamage(s2, 3)
    local sum = 0
    for i = 1, #ev.t do if ev.tgt[i] == 1 then sum = sum + ev.amt[i] end end
    local want = s2.targets[1].dps * s2.targets[1].maxHP * (300 - 1.5)
    check("steady damage delivers what the setup asked (within 10%)", math.abs(sum / want - 1) < 0.10,
        string.format("%.0f vs %.0f", sum, want))
end
do
    local s3 = PR.DefaultSetup("5", 70)
    s3.dur, s3.otherHealing = 60, 0.5
    local ev = PR.BuildDamage(s3, 5)
    local dmg, heal = 0, 0
    for i = 1, #ev.t do
        if ev.kind[i] == SM.K.DMG then dmg = dmg + ev.amt[i] elseif ev.kind[i] == SM.K.FHEAL then heal = heal + ev.amt[i] end
    end
    check("other healers give back their share", heal > 0.4 * dmg and heal < 0.5 * dmg + 1,
        string.format("%.0f of %.0f", heal, dmg))
end

-- a session, played ---------------------------------------------------------------
local errors = {}
local s = PR.New(setup, { seed = 11, onError = function(msg) errors[#errors + 1] = msg end, noStore = true })
check("a new session is ready, not running", s.state == "ready")
s:Start()
check("started", s.state == "running")

local TANK, MELEE, YOU = 1, 3, 2
-- press(t, spell, target): at that clock time
local script = {
    { 1.0, LB, TANK },
    { 2.0, REJ, MELEE },         -- 1.0s into the GCD: more than the queue window -> refused
    { 2.3, REJ, MELEE },         -- 0.2s before the GCD ends: queued, goes off at 2.5
    { 4.2, SWM, YOU },           -- nothing on you to eat
    { 6.0, RG, TANK },           -- a 2s cast
    { 7.8, LB, TANK },           -- queued at the end of the cast
    { 12.0, SWM, MELEE },        -- eats the Rejuvenation
}
local nextI, dt = 1, 0.05
local midTrace
while s.state == "running" do
    local p = script[nextI]
    if p and s.clock >= p[1] - 1e-9 then
        s:Cast(p[2], p[3])
        nextI = nextI + 1
    end
    s:Update(dt)
    if not midTrace and s.clock >= 10 and s.trace == nil then
        -- read the LIVE trace the way the window does, mid-fight
        local tr = s.S and s:LiveTrace()
        if tr then
            local st = MD.ReplayTrace.New(tr, s.scenario)
            st:Advance(s.clock)
            midTrace = { hp = st:Hp(TANK), mana = st:Mana(), hot = st:Hot(TANK, SM.HOT_INDEX.Lifebloom),
                         filled = tr.filled, n = tr.n }
        end
    end
end
check("played to the end", s.state == "done" and s.clock >= setup.dur - 1e-6, s.state .. " at " .. s.clock)
check("the live trace was readable mid-fight", midTrace and midTrace.hp and midTrace.mana
    and midTrace.filled <= midTrace.n, midTrace and string.format("hp %.2f, mana %d, grid %d/%d",
        midTrace.hp or -1, midTrace.mana or -1, midTrace.filled or -1, midTrace.n or -1))
check("a HoT on the live trace knows when it ends", midTrace and midTrace.hot and midTrace.hot.remaining > 0
    and midTrace.hot.remaining <= 7, midTrace and midTrace.hot and string.format("%.1fs", midTrace.hot.remaining))

local rec = s.rec
check("a recording came out", rec ~= nil)
local function has(msg) for _, e in ipairs(errors) do if e == msg then return true end end return false end
check("a press deep in the GCD is refused", has("Another action is in progress"), table.concat(errors, "; "))
check("Swiftmend with nothing to eat is refused", has("Nothing to consume"))

local K = SM.K
local castsAt = {}
for i = 1, rec.n do
    if rec.ev.kind[i] == K.OWNCAST then castsAt[#castsAt + 1] = { rec.ev.t[i], rec.ev.x[i], rec.ev.tgt[i] } end
end
check("five presses were cast", #castsAt == 5, tostring(#castsAt))
local function near(a, b) return a and b and math.abs(a - b) < 0.06 end
check("the queued press went off when the GCD ended", castsAt[2] and castsAt[2][2] == REJ and near(castsAt[2][1], 2.5),
    castsAt[2] and string.format("%.2f", castsAt[2][1]))
check("a cast lands when its bar ends", castsAt[3] and castsAt[3][2] == RG and near(castsAt[3][1], 8.0),
    castsAt[3] and string.format("%.2f", castsAt[3][1]))
check("the press queued during the cast went off after it", castsAt[4] and castsAt[4][2] == LB and near(castsAt[4][1], 8.0),
    castsAt[4] and string.format("%.2f", castsAt[4][1]))
check("Swiftmend ate the Rejuvenation", castsAt[5] and castsAt[5][2] == SWM)
do
    -- T46 (P2, review B5): the practice window paints this trace, so the
    -- Rejuvenation Swiftmend ate must end on it at the Swiftmend, not run on to
    -- its nominal expiry with the Swiftmend-ready dot still offering it
    local tr, endAt = s:LiveTrace(), nil
    local smAt = castsAt[5] and castsAt[5][1]
    for i = 1, (tr and tr.nEv or 0) do
        if tr.ev.kind[i] == SM.TK.HOT_END and tr.ev.tgt[i] == MELEE
           and tr.ev.a[i] == SM.HOT_INDEX.Rejuvenation then endAt = endAt or tr.ev.t[i] end
    end
    local st = tr and MD.ReplayTrace.New(tr, s.scenario)
    if st and smAt then st:Seek(smAt + 1) end
    check("the practice trace ends the HoT Swiftmend ate, at the Swiftmend",
        endAt ~= nil and smAt ~= nil and near(endAt, smAt)
        and st:Hot(MELEE, SM.HOT_INDEX.Rejuvenation) == nil,
        string.format("Swiftmend at %s, HOT_END at %s", tostring(smAt), tostring(endAt)))
end
local starts = 0
for i = 1, rec.n do if rec.ev.kind[i] == K.CASTSTART then starts = starts + 1 end end
check("the cast bar is recorded for the cast, not for instants", starts == 1, tostring(starts))
local ticks, heals = 0, 0
for i = 1, rec.n do
    if rec.ev.kind[i] == K.OWNTICK then ticks = ticks + 1 elseif rec.ev.kind[i] == K.OWNHEAL then heals = heals + 1 end
end
check("heals are written down the way the combat log would carry them", ticks > 10 and heals >= 3,
    ticks .. " ticks, " .. heals .. " direct")
do
    -- T59 (P15, review A30): the practice writer carries the two fields
    -- Engine/FightRecorder.lua's stream has. `names` is keyed by spell id (the
    -- replay window and the reason texts read it offline); every roster index
    -- carries its name, and every spell id the healer's own events name is in
    -- `names`, the bloom's own id (33778) and ticks included.
    local own = { [K.OWNCAST] = true, [K.CASTSTART] = true, [K.OWNHEAL] = true, [K.OWNTICK] = true }
    local missing = {}
    for i = 1, #rec.roster do
        if type(rec.roster[i].name) ~= "string" then missing[#missing + 1] = "roster " .. i end
    end
    for i = 1, rec.n do
        local x = rec.ev.x[i]
        if x >= 100000 then x = x - 100000 end   -- a crit's flag (FightRecorder's CRIT_FLAG)
        if own[rec.ev.kind[i]] and type(rec.names) == "table" and type(rec.names[x]) ~= "string" then
            missing[#missing + 1] = "spell " .. tostring(x)
        end
    end
    check("the stream names every roster index and every spell its own events carry",
        type(rec.names) == "table" and #missing == 0, table.concat(missing, ", "))
    local threat = 0
    for i = 1, rec.n do if rec.ev.kind[i] == K.THREAT then threat = threat + 1 end end
    check("...and carries a threatOn table, empty: practice has no threat",
        type(rec.threatOn) == "table" and next(rec.threatOn) == nil and threat == 0,
        type(rec.threatOn) .. ", " .. threat .. " threat events")
end

-- replay: the ordinary engine, from the recording alone ----------------------------
local kit = MD.RankMath:SpellKit({ live = true })
local v = SM:Validate(rec, kit)
local failed = {}
for _, g in ipairs(v.gates) do if not g.ok then failed[#failed + 1] = g.name .. ": " .. tostring(g.text) end end
check("every gate passes: it is the same engine", v.ok, table.concat(failed, "; "))
local sc = SM.ScenarioFromRecording(rec, kit)
local r = SM:Run(sc, nil, { critMode = "ev" })
local worst = 0
for i = 1, #rec.tracked do
    local n = #rec.hp.t
    local want = rec.hp.hp[i][n]
    local got = r.hpCurve[i] and r.hpCurve[i][#r.hpCurve[i]]
    if want and got then worst = math.max(worst, math.abs(want - got)) end
end
check("the replay ends on the health the player saw", worst < 1, string.format("worst %.3f hp", worst))
check("and on the mana", math.abs((r.manaEnd or 0) - rec.mana.v[#rec.mana.v]) < 60,
    string.format("%.0f vs %.0f (last 2s sample)", r.manaEnd or 0, rec.mana.v[#rec.mana.v]))

-- coach it ----------------------------------------------------------------------
local card = SP.Coach(rec, { n = "p1" })
check("the coach answers a practice fight", card and #card > 8 and not card[1]:find("does not replay"),
    card and card[1])

-- a death, and a press on the dead -------------------------------------------------
do
    local s4setup = PR.DefaultSetup("2", 64)
    s4setup.dur = 30
    s4setup.aoe = nil
    local tank = s4setup.targets[1]
    tank.dps, tank.spike, tank.spikeEvery, tank.jitter = 0.5, 0, 0, 0     -- half its health a second
    local errs = {}
    local s4 = PR.New(s4setup, { seed = 2, noStore = true, onError = function(m) errs[#errs + 1] = m end })
    s4:Start()
    local pressed = false
    while s4.state == "running" do
        if math.abs(s4.clock - 1) < 0.05 then s4:Cast(REJ, 2) end      -- one real cast, on yourself
        if not pressed and s4.clock >= 8 then s4:Cast(REJ, 1); pressed = true end
        s4:Update(0.1)
    end
    check("an unhealed tank dies", #s4.rec.deaths == 1, tostring(#s4.rec.deaths))
    local dead = false
    for _, e in ipairs(errs) do if e == "Target is dead" then dead = true end end
    check("a heal on the dead is refused", dead, table.concat(errs, "; "))
    local later = 0
    for i = 1, s4.rec.n do
        if s4.rec.ev.kind[i] == K.DMG and s4.rec.ev.tgt[i] == 1 and s4.rec.ev.t[i] > s4.rec.deaths[1][2] then later = later + 1 end
    end
    check("the damage the dead would have taken is kept", later > 10, later .. " hits after the death")
    local v4 = SM:Validate(s4.rec, kit)
    check("a death does not stop a practice fight being coached", v4.ok)
end

-- out of mana ----------------------------------------------------------------------
do
    local s5 = PR.New(PR.DefaultSetup("1", 64), { seed = 3, noStore = true })
    s5.setup.dur = 20
    local errs = {}
    s5.opts.onError = function(m) errs[#errs + 1] = m end
    s5.scenario.initial.mana = 10
    s5:Start()
    local pressed = false
    while s5.state == "running" do
        if not pressed and s5.clock >= 3 then s5:Cast(RG, 1); pressed = true end
        s5:Update(0.1)
    end
    check("no mana, no cast", errs[1] == "Not enough mana", tostring(errs[1]))
end

-- stopping early -------------------------------------------------------------------
do
    MD.cdb.practice = {}
    local s6 = PR.New(PR.DefaultSetup("5", 64), { seed = 4 })
    s6:Start()
    while s6.clock < 15 do
        if math.abs(s6.clock - 3) < 0.03 then s6:Cast(LB, 1) end
        s6:Update(0.05)
    end
    s6:Stop()
    local r6 = s6.rec
    check("stopping keeps the fight so far", r6 and s6.state == "done" and math.abs(r6.dur - 15) < 0.06,
        r6 and string.format("%.2fs", r6.dur))
    local after = 0
    for i = 1, r6.n do if r6.ev.t[i] > r6.dur then after = after + 1 end end
    check("and nothing after it", after == 0, after .. " events after the end")
    check("it is marked unfinished", r6.practice and r6.practice.finished == false)
    check("an early stop still replays", SM:Validate(r6, kit).ok)
    check("it is kept and addressed as p1", MD:GetRecording("p1") == r6)
    -- T62 (P18): p1 reaches the practice provider through the one router
    -- (Engine/Recordings.lua), not a second parser of its own
    local REC = MD.Recordings
    check("...through the router's practice provider",
        REC ~= nil and REC.Provider("p") ~= nil and REC.Provider("p").List == PR.List
        and REC.Get("p1") == r6 and REC.List("p")[1] == r6,
        REC and "provider " .. tostring(REC.Provider("p")) or "no MD.Recordings")
    check("practice never touches the ring of real fights", #(MD.cdb.recordings or {}) == 0)
    for k = 1, PR.MAX_KEPT + 2 do
        local x = PR.New(PR.DefaultSetup("1", 64), { seed = k })
        x.startedAt = 2000000000 + k
        x:Start(); x:Cast(LB, 1); x:Update(0.2); x:Stop()
    end
    check("only the newest " .. PR.MAX_KEPT .. " are kept", #MD.cdb.practice == PR.MAX_KEPT
        and PR.Get(1).id == 2000000000 + PR.MAX_KEPT + 2, tostring(#MD.cdb.practice))

    -- 2026-09-29: practice fights a report can be built from. The record
    -- carries the kit it was simulated with, the client and the version, and
    -- replays with that kit -- mana included -- with nothing else loaded.
    check("a practice record carries the kit it was simulated with",
        type(r6.kit) == "table" and type(r6.kit.caster) == "table" and r6.kit.caster[LB] ~= nil
        and r6.kit.caster[LB].cost == s6.kit.caster[LB].cost)
    check("...and the client, level and version", r6.client ~= nil and r6.level ~= nil and r6.version ~= nil,
        string.format("%s / %s / %s", tostring(r6.client), tostring(r6.level), tostring(r6.version)))
    local ra = SM:Run(SM.ScenarioFromRecording(r6, r6.kit), nil, { critMode = "ev" })
    local worst, nS = 0, 0
    for k, v in ipairs(r6.mana.v) do
        local m = ra.manaCurve[k]
        if m then nS = nS + 1; worst = math.max(worst, math.abs(m - v)) end
    end
    check("...and replays with that kit to the mana the session wrote",
        SM:Validate(r6, r6.kit).ok and nS == #r6.mana.v and nS > 0 and worst < 1,
        string.format("%d samples, worst %.2f mana off", nS, worst))

    -- pinned: the next eight do not push it out, and at most MAX_PINNED stay pinned
    local oldest = MD.cdb.practice[#MD.cdb.practice]
    check("a practice fight can be pinned", PR.Pin(oldest) == true and oldest.pinned == true)
    for k = 1, PR.MAX_KEPT do
        local x = PR.New(PR.DefaultSetup("1", 64), { seed = 50 + k })
        x.startedAt = 2050000000 + k
        x:Start(); x:Cast(LB, 1); x:Update(0.2); x:Stop()
    end
    local still = false
    for _, r in ipairs(MD.cdb.practice) do if r == oldest then still = true end end
    check("...and the next " .. PR.MAX_KEPT .. " do not push it out", still and #MD.cdb.practice == PR.MAX_KEPT,
        tostring(#MD.cdb.practice))
    for i = 1, PR.MAX_PINNED - 1 do PR.Pin(MD.cdb.practice[i], true) end
    local okPin, why = PR.Pin(MD.cdb.practice[PR.MAX_PINNED + 1], true)
    check("...and no more than " .. PR.MAX_PINNED .. " are pinned", okPin == false and why ~= nil, tostring(why))
    for _, r in ipairs(MD.cdb.practice) do r.pinned = false end
end

-- nothing played, nothing kept ------------------------------------------------------
do
    local before = #MD.cdb.practice
    local x = PR.New(PR.DefaultSetup("1", 64), { seed = 99 })
    x.startedAt = 2100000000
    x:Start(); x:Update(0.2); x:Stop()
    check("a fight with no casts is not kept", x.rec == nil and #MD.cdb.practice == before
        and PR.Get(1).id ~= 2100000000)
end

-- bindings -----------------------------------------------------------------------
do
    MD.db.practiceBinds = nil
    local b, id = PR.BindFor("BUTTON5")
    check("Button5 is Lifebloom, as in your Cell click-casting", b and id == LB)
    local _, rj = PR.BindFor("ALT-BUTTON5")
    check("Alt-Button5 is your highest Rejuvenation", rj == REJ)
    local _, r5 = PR.BindFor("SHIFT-BUTTON5")
    check("Shift-Button5 is Rejuvenation Rank 5, the downranked one", r5 and SD.spells[r5].rank == 5
        and SD.spells[r5].family == "Rejuvenation")
    check("modifiers are spelled the way the client spells them", PR.Mods(true, true, true) .. "1" == "ALT-CTRL-SHIFT-1")
    check("an unbound press is nothing", PR.BindFor("CTRL-Q") == nil)
    MD.db.practiceBinds[1].rank = 99
    local _, fallback = PR.BindFor("BUTTON5")
    check("a rank you do not know falls back to your highest", fallback == LB)
end

-- importing bindings ---------------------------------------------------------------
do
    -- the author's own Cell click-castings and macros, as they are on disk
    S.macros["Main overtime"] = "#showtooltip\n/cast [known:33763,@mouseover,help]Lifebloom;" ..
        "[@mouseover,help]Rejuvenation;[form:3,@mouseover,harm][form:3,harm]Rake;" ..
        "[known:5570,@mouseover,harm][known:5570,harm]Insect Swarm;[@mouseover,harm][harm]Moonfire;" ..
        "[known:33763]Lifebloom;Rejuvenation"
    S.macros["efficient Rej"] = "#showtooltip\n/cancelform [stance:6]\n/cast [@mouseover, help, exists][]  Rejuvenation(Rank 5)"
    S.macros["iner"] = "#showtooltip\n/cast [@mouseover,help][] Innervate"
    _G.CellCharacterDB = { clickCastings = {
        useCommon = true, class = "DRUID",
        common = {
            { "type5", "macro", "Main overtime" },
            { "type1", "target" },
            { "type2", "togglemenu" },
            { "shift-type5", "macro", "efficient Rej" },
            { "type4", "macro", "iner" },
            { "type-altR", "spell", 20484 },
            { "alt-type-SCROLLUP", "macro", "Main overtime" },
            { "alt-type5", "spell", SD.maxRank.Regrowth },
        },
        [1] = { { "type1", "target" } },
    } }
    local list, report = PR.ImportCell()
    check("Cell's bindings import", list ~= nil and report.added == 3,
        report and (report.error or (report.added .. " added, " .. #report.skipped .. " skipped")))
    local by = {}
    for _, b in ipairs(list or {}) do by[b.key] = b end
    check("a mouse button macro becomes its first heal", by.BUTTON5 and by.BUTTON5.family == "Lifebloom",
        by.BUTTON5 and by.BUTTON5.family)
    check("a downranked macro keeps its rank", by["SHIFT-BUTTON5"] and by["SHIFT-BUTTON5"].family == "Rejuvenation"
        and by["SHIFT-BUTTON5"].rank == 5)
    check("a spell id binding is read straight", by["ALT-BUTTON5"] and by["ALT-BUTTON5"].family == "Regrowth")
    local said = table.concat(report.skipped, " | ")
    check("targeting, the menu and Innervate are skipped, and say why",
        said:find("target") and said:find("togglemenu") and said:find("iner"), said)
    check("the mouse wheel is skipped by name", said:find("wheel") ~= nil, said)
    check("Rebirth on a keyboard binding is skipped, not guessed", said:find("ALT%-R") ~= nil, said)
    -- v0.15.4: an import goes ON TOP of what is there. Start from the defaults
    -- plus one binding of the player's own that Cell knows nothing about.
    MD.db.practiceBinds = nil
    table.insert(PR.Binds(), { key = "CTRL-E", family = "Swiftmend" })
    local before = #PR.Binds()
    local added, replaced, same = PR.ApplyImport(list)
    check("an import adds on top: nothing new here, one replaced, two already the same",
        added == 0 and replaced == 1 and same == 2, string.format("%d / %d / %d", added, replaced, same))
    check("so the list is as long as before", #PR.Binds() == before, #PR.Binds() .. " vs " .. before)
    check("the key both had now casts the imported spell", select(2, PR.BindFor("ALT-BUTTON5")) == SD.maxRank.Regrowth)
    check("a binding the import never mentioned is kept", select(2, PR.BindFor("CTRL-E")) == SWM
        and select(2, PR.BindFor("BUTTON1")) == SD.maxRank.Regrowth)
    local _, id = PR.BindFor("SHIFT-BUTTON5")
    check("and the rank survives the round trip", id and SD.spells[id].rank == 5)
    local a2 = PR.ApplyImport({ { key = "F", family = "HealingTouch" }, { key = "F", family = "Lifebloom" } })
    check("a new key is appended, and inside one import the later entry wins", a2 == 1
        and PR.Binds()[#PR.Binds()].key == "F" and select(2, PR.BindFor("F")) == LB)

    _G.CellCharacterDB = nil
    local none, why = PR.ImportCell()
    check("no Cell, no pretence", none == nil and why.error ~= nil, why and why.error)

    _G.CliqueDB3 = { profiles = { ["Penek - Spineshatter"] = { binds = {
        { key = "BUTTON1", type = "spell", spell = "Regrowth(Rank 5)" },
        { key = "ALT-BUTTON2", type = "spell", spell = "Healing Touch" },
        { key = "CTRL-Q", type = "spell", spell = "Rebirth" },
        { key = "SHIFT-MOUSEWHEELUP", type = "spell", spell = "Rejuvenation" },
        { key = "BUTTON3", type = "target" },
    } } } }
    local clist, crep = PR.ImportClique()
    check("Clique's bindings import", clist and crep.added == 2, crep and (crep.error or crep.added .. " added"))
    check("Clique keys are already the client's spelling", clist[1].key == "BUTTON1" and clist[1].rank == 5)
    check("a spell this addon does not model is skipped", table.concat(crep.skipped, " | "):find("Rebirth") ~= nil)
    _G.CliqueDB3 = nil
    MD.db.practiceBinds = nil
end

-- importing the game's own keybindings ---------------------------------------------
do
    MD.db.practiceBinds = nil
    S.macros["Main overtime"] = "#showtooltip\n/cast [known:33763,@mouseover,help]Lifebloom;[@mouseover,help]Rejuvenation"
    S.macros["efficient regrow"] = "#showtooltip\n/cancelform [stance:6]\n/cast [@mouseover, help, exists][]  Regrowth(Rank 5)"
    S.macros["HT"] = "/cast [@mouseover,help,nodead][] Healing Touch"
    S.macros["Def"] = "/cast Barkskin"
    S.macroOrder = { "Main overtime", "efficient regrow", "HT", "Def" }
    -- the author's own bars: ElvUI bar 2 and Blizzard's bottom-right, with a
    -- frame carrying the slot the way every bar addon answers it
    local elv = CreateFrame("Frame", "ElvUI_Bar2Button9")
    elv.GetAttribute = function(_, k) return k == "action" and 74 or nil end
    local bt4 = CreateFrame("Frame", "BT4Button13")
    bt4.GetAttribute = function(_, k) return k == "action" and 75 or nil end
    S.actions = {
        [49] = { "macro", 1 },      -- MULTIACTIONBAR2BUTTON1 -> "Main overtime"
        [74] = { "macro", 2 },      -- ElvUI bar 2 button 9   -> "efficient regrow"
        [75] = { "spell", SD.maxRank.Rejuvenation },
        [3]  = { "macro", 3 },      -- ACTIONBUTTON3          -> "HT" (mouseover)
        [4]  = { "macro", 4 },      -- ACTIONBUTTON4          -> Barkskin, no heal
        [13] = { "item", 22795 },   -- MULTIACTIONBAR4BUTTON1
    }
    S.bindings = {
        { "MULTIACTIONBAR2BUTTON1", "BUTTON5" },
        { "ELVUIBAR2BUTTON9", "BUTTON4" },
        { "CLICK BT4Button13:LeftButton", "SHIFT-R" },
        { "ACTIONBUTTON3", "ALT-CTRL-SHIFT-F" },
        { "ACTIONBUTTON4", "SHIFT-F11" },
        { "MULTIACTIONBAR4BUTTON1", "ALT-F11" },
        { "MOVEFORWARD", "W" },
        { "ACTIONBUTTON3", "MOUSEWHEELUP" },
    }
    local list, report = PR.ImportKeybinds()
    local by = {}
    for _, b in ipairs(list or {}) do by[b.key] = b end
    check("the game's own keybindings import", report.added == 4, report.error or tostring(report.added))
    check("a mouseover macro on Blizzard's bar becomes its first heal",
        by.BUTTON5 and by.BUTTON5.family == "Lifebloom", by.BUTTON5 and by.BUTTON5.family)
    check("an ElvUI bar is followed through its frame to the slot",
        by.BUTTON4 and by.BUTTON4.family == "Regrowth" and by.BUTTON4.rank == 5)
    check("a CLICK binding on a bar addon's button too",
        by["SHIFT-R"] and by["SHIFT-R"].family == "Rejuvenation")
    check("three modifiers keep the client's order",
        by["ALT-CTRL-SHIFT-F"] and by["ALT-CTRL-SHIFT-F"].family == "HealingTouch")
    local said = table.concat(report.skipped, " | ")
    check("a macro with no heal in it is skipped by name", said:find("SHIFT%-F11") ~= nil, said)
    check("an item binding is skipped", said:find("ALT%-F11") ~= nil, said)
    check("the mouse wheel is skipped", said:find("MOUSEWHEEL") ~= nil, said)
    check("a binding that is not an action button is ignored in silence",
        not said:find("^W:") and by.W == nil)
    local notes = table.concat(report.notes, " | ")
    check("a binding that casts on your target says so", notes:find("SHIFT%-R") ~= nil, notes)
    check("and a mouseover one does not", not notes:find("BUTTON5"), notes)
    local ka, kr, ks = PR.ApplyImport(list)
    check("applying it adds three on top of the defaults and finds BUTTON5 already Lifebloom",
        ka == 3 and kr == 0 and ks == 1 and #PR.Binds() == 9 and PR.BindFor("BUTTON4").family == "Regrowth" and PR.BindFor("BUTTON4").rank == 5,
        string.format("%d / %d / %d, %d binds", ka, kr, ks, #PR.Binds()))
    S.bindings, S.actions, MD.db.practiceBinds = {}, {}, nil
end

-- the search's engine is untouched --------------------------------------------------
check("a run with no pace and no player is unchanged", (function()
    local sc2 = PR.New(PR.DefaultSetup("5", 64), { seed = 9, noStore = true }).scenario
    local a = SM:Run(sc2, SP.DefaultPlan and SP.DefaultPlan() or nil, { critMode = "ev" })
    return a and a.casts ~= nil
end)())

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
