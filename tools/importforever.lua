-- tools/importforever.lua -- tools/import.lua's Forever half. Not run on its
-- own: import.lua reads the arguments and the file, decides the file is a
-- WoW: Forever one (`--flavour forever`, or what only Forever writes), and
-- hands over in the global IMPORT.
--
-- The addon is loaded through the harness's forever flavour (the Mainline TOC
-- under the stub's forever profile) with the three modules on -- the Recorder,
-- the Replay module's engine chain (Kit_Forever, SimModel, Scenario_Forever,
-- Gates_Forever, the planner and the solver) and Practice -- over the file's
-- own database, and every command runs the code the game runs:
--
--   list                    every recording (1 = newest) and practice fight (p1 = newest),
--                           with its kit and its validate verdict
--   validate N|pN           the Forever gate report, as /st validate prints it
--   replay N|pN             both columns of the replay window as text: what each spent,
--                           regenerated, overhealed, the lowest health, deaths, the mana at
--                           the end and the seconds outside the five-second rule; the mana
--                           every 2 s side by side; every cast (yours with its label, the
--                           plan's with its rule and reason) and the plan's long waits
--   coach N|pN [force]      the search and the card, as /st coach prints it
--   report N|pN             the fight replayed (what you played) beside every strategy in
--                           SP.STRATEGY_SET: spent, regen, used, end, owed, deaths, floor,
--                           lowest, casts (tools/reportlines.lua, shared with the TBC half)
--   export N|pN             the fight as a SavedVariables file of its own (importable with
--                           --file) and the replay text, into .logs/forever/
--
-- --strategy <key> picks the suggested column the way the replay window's chooser does:
-- a planner (rules, rules-hots, solver-blind, solver-prior, solver-sight, solver-frugal,
-- solver-near -- built on demand, no search) or one reading of the search (safe, health,
-- cheap, regen). Without it, replay and export search first, as opening the window does.
-- With it, coach prints that strategy's own card instead of the search's.
--
-- THE KIT. On Forever the spell kit is built from the live spellbook, which offline is
-- the stub's (Healing Touch R1, Rejuvenation R1-R2 -- no Healing Touch R2, no level).
-- So each fight is replayed with, in order: the kit it was stored with (`rec.kit`,
-- MD.SimModel.KitSnapshot, since the recordings pipeline), else -- a practice fight stored
-- before then -- the kit read back off its own heals, else the character's last kit
-- (`cdb.kit`, written whenever the game builds one), else the stub's book -- and every line
-- that prints a number says which. RM.KitRestore (Kit_Forever.lua) rebuilds the
-- MD.SpellData index from the kit's entries: nothing else of the book is stored.
local I = IMPORT
local here, db, opts, cmd = I.here, I.db, I.opts, I.cmd

local function Say(fmt, ...) print(select("#", ...) > 0 and string.format(fmt, ...) or fmt) end
local function Strip(s)
    return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|"))
end

--------------------------------------------------------------------------------
-- The character, chosen before the addon loads (it adds the stub's own).
--------------------------------------------------------------------------------
local chars = {}
for key, c in pairs(db.char or {}) do
    if type(c) == "table" then
        chars[#chars + 1] = { key = key, nr = #(c.recordings or {}), np = #(c.practice or {}) }
    end
end
table.sort(chars, function(a, b)
    if a.nr + a.np ~= b.nr + b.np then return a.nr + a.np > b.nr + b.np end
    return a.key < b.key
end)
local charKey = opts.char or (chars[1] and chars[1].key)
local cdb = charKey and db.char and db.char[charKey]
if not cdb then
    Say("import: no character %s in %s", tostring(opts.char or "with data"), I.file)
    os.exit(2)
end
-- kept before anything can rebuild it: Kit_Forever.lua writes cdb.kit whenever
-- the kit is built, and offline that would be the stub's book
local savedKit = cdb.kit

HARNESS_FLAVOUR = "forever"
-- the login's own chat ("Recorder: loaded", ...) is not the report's
local realPrint = print
print = function() end
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
print = realPrint
local S = _G.STUB

-- The chat the engine prints to (the coach's "searching..." line and the
-- like), kept out of the report unless a command wants it.
local chat = {}
_G.DEFAULT_CHAT_FRAME.AddMessage = function(_, m) chat[#chat + 1] = m end

MD.cdb = cdb
MD.player.charKey = charKey
-- the engine's plans and the coach are druid-only; a Forever recording
-- carries no class of its own, and the kit it carries is a druid's
MD.player.isDruid, MD.player.class = true, "DRUID"
if not (MD:ModuleState("SpellTuner_Practice") == "loaded") then MD:SetModule("SpellTuner_Practice", true) end
local RM, SD, SM, SP, RT = MD.RankMath, MD.SpellData, MD.SimModel, MD.SimPlanner, MD.ReplayTrace
if not (RM and SM and SP and RT and MD.Practice) then
    Say("import: the Forever modules did not load (%s)", table.concat(chat, "; "))
    os.exit(2)
end
cdb.kit = savedKit

--------------------------------------------------------------------------------
-- The kit
--------------------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local stubSpellKit = RM.SpellKit
-- The snapshot is the kit itself (MD.SimModel.KitSnapshot); RM.KitRestore
-- (Kit_Forever.lua) rebuilds the MD.SpellData index the engine reads from its
-- entries, so every command below sees the fight's own spells.
local function UseSnapshot(snap)
    RM.SpellKit = function() return RM.KitRestore(snap) end
end

local FAMILIES = { "HealingTouch", "Rejuvenation", "Regrowth", "Swiftmend", "Tranquility" }
local function KitDesc(snap)
    local top = {}
    for _, e in pairs(snap.caster or {}) do
        if e.family and (e.rank or 0) > (top[e.family] or 0) then top[e.family] = e.rank end
    end
    local fams = {}
    for _, fam in ipairs(FAMILIES) do
        if top[fam] then fams[#fams + 1] = fam .. " R" .. tostring(top[fam]) end
    end
    return string.format("level %s, %s, crit %.1f%%", tostring(snap.level or "?"),
        #fams > 0 and table.concat(fams, " ") or "no healing spells", (snap.crit or 0) * 100)
end

-- A practice fight stored before fights carried their kit (0.16.1 and
-- earlier) still says exactly what every cast did: the engine wrote each own
-- heal down as the kit priced it (Engine/Practice.lua's onHeal, crits as their
-- expectation), each cast's cost, and a cast bar's start. So the kit of every
-- spell the fight CAST is read back off its own events -- a direct heal's
-- amount (crit already in it, so the entry's own crit is 0), a HoT's tick, its
-- period and the longest run of ticks one application made, a cast bar's
-- length -- and named from rec.names ("HealingTouch r2"). A spell it never
-- cast is not in it. Answers nil when there is nothing to read.
local FAMILY_TYPE = { HealingTouch = "direct", Regrowth = "hybrid", Rejuvenation = "hot",
                      Swiftmend = "instant", Tranquility = "channel" }
local function InferFromPractice(rec)
    if not (rec.practice and rec.v == 2 and rec.ev and rec.names) then return nil end
    local K = SM.K
    local ev = rec.ev
    local caster, skipped = {}, {}
    local function Entry(id)
        if caster[id] ~= nil then return caster[id] or nil end
        local fam, rank = tostring(rec.names[id] or ""):match("^(%a+) r(%d+)$")
        if not (fam and FAMILY_TYPE[fam]) then
            caster[id] = false
            skipped[#skipped + 1] = tostring(rec.names[id] or id)
            return nil
        end
        local e = { family = fam, rank = tonumber(rank), type = FAMILY_TYPE[fam], gcd = 1.5, directCrit = 0 }
        caster[id] = e
        return e
    end
    local startAt, lastApply, run, runMax, lastTick = {}, {}, {}, {}, {}
    for i = 1, rec.n or 0 do
        local kind, x, t, tgt, amt = ev.kind[i], ev.x[i], ev.t[i], ev.tgt[i], ev.amt[i]
        local id = (x and x >= 100000) and (x - 100000) or x   -- a rolled crit's flag
        if kind == K.CASTSTART then
            startAt[id] = t
        elseif kind == K.OWNCAST then
            local e = Entry(id)
            if e then
                if (amt or -1) >= 0 then e.cost = amt end
                local cast = (e.type == "direct" or e.type == "hybrid") and startAt[id] and (t - startAt[id]) or 0
                if cast > (e.cast or 0) then e.cast, e.castBase = cast, cast end
                if e.type == "hot" or e.type == "hybrid" then
                    local key = id .. ":" .. tostring(tgt)
                    lastApply[key], run[key], lastTick[key] = t, 0, nil
                end
                startAt[id] = nil
            end
        elseif kind == K.OWNHEAL then
            local e = Entry(id)
            if e and not e.direct then e.direct = amt end
        elseif kind == K.OWNTICK then
            local e = Entry(id)
            if e then
                e.tick = e.tick or amt
                local key = id .. ":" .. tostring(tgt)
                local from = lastTick[key] or lastApply[key]
                if from and t - from > 0 and (not e.tickPeriod or t - from < e.tickPeriod) then
                    e.tickPeriod = math.floor((t - from) * 100 + 0.5) / 100
                end
                lastTick[key] = t
                run[key] = (run[key] or 0) + 1
                if run[key] > (runMax[id] or 0) then runMax[id] = run[key] end
            end
        end
    end
    local known, maxRank = {}, {}
    local any = false
    for id, e in pairs(caster) do
        if e then
            any = true
            if e.type == "hot" or e.type == "hybrid" then
                e.ticks = runMax[id]
                if e.ticks and e.tickPeriod then e.duration = e.ticks * e.tickPeriod end
                if not (e.tick and e.ticks and e.tickPeriod) then e.dataMissing = true end
            end
            if (e.type == "direct" or e.type == "hybrid") and not e.direct then e.dataMissing = true end
            if not e.cost then e.dataMissing = true end
            if (e.rank or 0) > (known[e.family] or 0) then known[e.family], maxRank[e.family] = e.rank, id end
        end
    end
    if not any then return nil end
    for id, e in pairs(caster) do if not e then caster[id] = nil end end
    -- Swiftmend eats the highest cast rank of each HoT, as Kit_Forever.lua's own
    local sw = maxRank.Swiftmend and caster[maxRank.Swiftmend]
    if sw then
        local rj = maxRank.Rejuvenation and caster[maxRank.Rejuvenation]
        local rg = maxRank.Regrowth and caster[maxRank.Regrowth]
        if rj and rj.tick and rj.ticks then sw.swiftmendRejuv = rj.tick * rj.ticks end
        if rg and rg.tick and rg.ticks then sw.swiftmendRegrowth = rg.tick * rg.ticks end
    end
    return { at = rec.id, level = "?", crit = 0, caster = caster, tree = {}, inferred = true, skipped = skipped }
end

-- Installs the kit this fight should be replayed with; answers a short word
-- for the tables and a line for the reports.
local function UseKitFor(rec)
    if type(rec.kit) == "table" then
        UseSnapshot(rec.kit)
        return "recorded", "kit:   recorded with the fight (" .. KitDesc(rec.kit) .. ")"
    end
    local inferred = InferFromPractice(rec)
    if inferred then
        UseSnapshot(inferred)
        return "inferred", string.format("kit:   read back off the fight's own heals (%s; crit is inside each " ..
            "heal%s) - it was stored before fights carried their kit, and a spell it never cast is not in it",
            KitDesc(inferred), #inferred.skipped > 0 and ("; not read: " .. table.concat(inferred.skipped, ", ")) or "")
    elseif type(savedKit) == "table" then
        UseSnapshot(savedKit)
        return "last", string.format("kit:   NOT this fight's - the character's last kit (%s, built %s); " ..
            "this fight was stored before recordings carried their own", KitDesc(savedKit),
            os.date("%Y-%m-%d %H:%M", savedKit.at or 0))
    end
    RM.SpellKit = stubSpellKit
    return "STUB", "kit:   NOT this fight's - the stub's spellbook (Healing Touch R1, Rejuvenation R1-R2); " ..
        "this file carries no kit: update SpellTuner, open any replay in game, /reload"
end

--------------------------------------------------------------------------------
-- Addresses: N a recording, pN a practice fight (MD:GetRecording's own)
--------------------------------------------------------------------------------
local spec = opts.spec or tostring(I.n or 1)
local function Get()
    local rec, label = MD:GetRecording(spec)
    if not rec then
        Say("no %s %s (%d recording(s), %d practice fight(s)). Try: list",
            spec:match("^p") and "practice fight" or "recording", spec,
            #MD.FightRecorder:List(), #MD.Practice.List())
        os.exit(1)
    end
    return rec, label
end

local function When(id) return id and os.date("%Y-%m-%d %H:%M", id) or "?" end

local function Verdict(rec)
    local ok, v = pcall(SM.Validate, SM, rec, RM:SpellKit())
    if not ok then return "error: " .. Strip(v) end
    if not v then return "?" end
    if v.ok then return "ok" end
    for _, g in ipairs(v.gates) do if not g.ok then return g.name .. ": " .. Strip(g.text) end end
    return "failed"
end

local function CastsOf(rec)
    local n, mana = 0, 0
    for i = 1, (rec.n or 0) do
        if rec.ev.kind[i] == 3 then   -- OWNCAST in both v2 and v3
            n = n + 1
            if (rec.ev.amt[i] or 0) > 0 then mana = mana + rec.ev.amt[i] end
        end
    end
    return n, mana
end

local function SpellName(id, names)
    local sd = SD.spells[id]
    if sd then return sd.family .. " R" .. tostring(sd.rank) end
    if names and names[id] then return Strip(names[id]) end
    return "spell " .. tostring(id)
end

--------------------------------------------------------------------------------
-- The suggested column: a strategy by key, one reading of the search, or the
-- search itself (what opening the window does).
--------------------------------------------------------------------------------
local OBJECTIVE = {}
for _, o in ipairs(SP.OBJECTIVES) do OBJECTIVE[o.key] = o end

local function RunFrames(isDone, limit)
    local frames = 0
    while not isDone() and frames < limit do S.Tick(0.016); frames = frames + 1 end
    return frames
end

-- the search, as /st coach runs it; answers the card's lines
local function Search(rec, label, force)
    local done, lines = false, nil
    SP.CoachAsync(rec, { n = label, force = force }, function(l) lines = l; done = true end)
    local frames = RunFrames(function() return done end, 50000)
    if not done then Say("coach: the search did not finish in %d frames", frames); os.exit(1) end
    return lines, frames
end

local function StrategyList()
    local keys = {}
    for _, e in ipairs(SP.STRATEGY_SET) do keys[#keys + 1] = e.key end
    for _, o in ipairs(SP.OBJECTIVES) do keys[#keys + 1] = o.key end
    return table.concat(keys, ", ")
end

-- answers plan, name, why (nil plan: none, and why says so)
local function PlanFor(rec, label, validation)
    local key = opts.strategy
    local entry = key and SP.Strategy(key)
    if entry then
        local kit = RM:SpellKit()
        local sc = SM.ScenarioFromRecording(rec, kit)
        local plan = SP.MakeStrategy(entry, SP.BindsFromRecording(rec), kit,
            { scenario = sc, seed = rec.id or 1, encounter = rec.encounter, zone = rec.zone,
              recs = MD.cdb.recordings, excludeID = rec.id })
        if not plan then return nil, entry.label, "the strategy built no plan on this file" end
        SP.plans[rec.id] = plan
        SP.strategyPick[rec.id] = key
        return plan, entry.label, entry.why
    end
    if key and not OBJECTIVE[key] and key ~= "search" then
        Say("unknown strategy %q. One of: %s, search", key, StrategyList())
        os.exit(2)
    end
    if not (opts.force or (validation and validation.ok)) then
        return nil, nil, "the fight does not replay, so nothing is suggested (force draws it anyway)"
    end
    Search(rec, label, opts.force)
    local obj = key and OBJECTIVE[key]
    if obj then
        local w = SP.strategies[rec.id] and SP.strategies[rec.id][key]
        if not w then return nil, nil, "the search produced no " .. obj.name .. " plan" end
        SP.plans[rec.id] = w.plan
        SP.strategyPick[rec.id] = key
        return w.plan, "Search: " .. obj.name, obj.what
    end
    local p = SP.plans[rec.id]
    return p, "the search's best", "what opening the replay window coaches"
end

--------------------------------------------------------------------------------
-- One column of the replay window, read off its trace the way the window does
-- (Engine/ReplayTrace.lua), plus when it was outside the five-second rule.
--------------------------------------------------------------------------------
local TK = SM.TK
local function Column(trace, scenario)
    local st = RT.New(trace, scenario)
    st:Seek(trace.dur or 0)
    local spent, lowest, deaths = st:Score()
    local oh = st:Overheal()
    -- the five-second rule: 5 s after every cast that cost mana, regen is the
    -- casting rate; the rest of the fight is the window a healer regenerates in
    local fsr = {}
    for i = 1, trace.nEv do
        if trace.ev.kind[i] == TK.CAST and (trace.ev.b[i] or 0) > 0 then fsr[#fsr + 1] = trace.ev.t[i] end
    end
    local function Outside(t)
        local last
        for _, ct in ipairs(fsr) do if ct <= t + 1e-9 then last = ct else break end end
        return not last or t >= last + 5 - 1e-9
    end
    local out = 0
    for k = 1, trace.n do if Outside((k - 1) * trace.dt) then out = out + trace.dt end end
    return { spent = spent, regen = st:Regen(), overheal = oh, lowest = lowest, deaths = deaths,
             manaEnd = st:Mana(), outside = out, Outside = Outside, state = st, trace = trace }
end

local function ColumnLine(name, c, extra)
    return string.format("%-10s %6d %6d %8s %6d%% %5d %8d %9.1fs%s", name, c.spent + 0.5, c.regen + 0.5,
        c.overheal and string.format("%d%%", c.overheal * 100 + 0.5) or "-", c.lowest * 100 + 0.5,
        c.deaths, (c.manaEnd or 0) + 0.5, c.outside, extra or "")
end
local COLUMN_HEAD = string.format("%-10s %6s %6s %8s %7s %5s %8s %10s", "column", "spent", "regen",
    "overheal", "lowest", "dead", "mana end", "out of 5SR")

-- The whole text: validation, both columns, mana over time, every cast.
local function ReplayLines(rec, label, kitLine)
    local lines = {}
    local function Add(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    local kit = RM:SpellKit()
    local validation = SM:Validate(rec, kit)
    local casts, mana = CastsOf(rec)
    Add("%s %s: %s, %s, %.1fs, %d own casts, %d mana recorded%s", rec.practice and "practice" or "recording",
        label, Strip(rec.zone or "?"), When(rec.id), rec.dur or 0, casts, mana,
        rec.v == 3 and "  (v3: health reconstructed from UNIT_COMBAT)" or "")
    Add("%s", kitLine)
    for _, line in ipairs(MD:ValidationReport(rec, label)) do Add("  %s", Strip(line)) end
    Add("")

    local plan, planName, planWhy = PlanFor(rec, label, validation)
    local rp = SP.Replay(rec, { dt = 0.25, plan = plan, force = plan ~= nil })
    local L = Column(rp.left.trace, rp.scenario)
    local R = rp.right and Column(rp.right.trace, rp.scenario)

    Add("%s", COLUMN_HEAD)
    Add("%s", ColumnLine("YOU", L))
    if R then
        Add("%s", ColumnLine("SUGGESTED", R, string.format("   %s, %d binds", planName or "plan",
            plan.BindCount and plan:BindCount() or 0)))
        Add("  suggested: %s - %s", planName or "plan", Strip(planWhy or ""))
    else
        Add("SUGGESTED  none - %s", Strip(planWhy or "no plan"))
    end
    Add("")

    -- the mana, side by side; * = outside the five-second rule at that moment
    local step = 2
    while (rec.dur or 0) / step > 60 do step = step * 2 end
    Add("mana every %ds (* = outside the five-second rule, regenerating at the full rate)", step)
    Add("%7s  %6s %6s %6s %s", "t", "you", "spent", "regen", R and string.format(" | %6s %6s %6s", "plan", "spent", "regen") or "")
    local t = 0
    local dur = rp.left.trace.dur or 0
    while t <= dur + 1e-9 do
        L.state:Seek(t)
        local lm, ls = L.state:Mana() or 0, (L.state:Score())
        local row = string.format("%7.1f  %5d%s %6d %6d", t, lm + 0.5, L.Outside(t) and "*" or " ", ls + 0.5,
            L.state:Regen() + 0.5)
        if R then
            R.state:Seek(t)
            local rm, rs = R.state:Mana() or 0, (R.state:Score())
            row = row .. string.format("  | %5d%s %6d %6d", rm + 0.5, R.Outside(t) and "*" or " ", rs + 0.5,
                R.state:Regen() + 0.5)
        end
        Add("%s", row)
        t = t + step
    end
    Add("")

    -- your casts, with the classifier's label and why
    local names = rec.names
    Add("your casts%s", rp.casts and "  (labels against the suggested plan)" or "")
    Add("%7s  %-18s %-12s %5s  %s", "t", "cast", "target", "cost", "label")
    local ci = 0
    local Lt = rp.left.trace
    for i = 1, Lt.nEv do
        if Lt.ev.kind[i] == TK.CAST then
            ci = ci + 1
            local tgt = rec.roster[Lt.ev.tgt[i]] and rec.roster[Lt.ev.tgt[i]].name or "-"
            local c = rp.casts and rp.casts[ci]
            Add("%7.2f  %-18s %-12s %5d  %s", Lt.ev.t[i], SpellName(Lt.ev.a[i], names), Strip(tgt),
                Lt.ev.b[i] or 0, c and c.label or "")
            local why = c and SP.CastWhy(c, names)
            if why then Add("%7s  %s", "", Strip(why)) end
        end
    end
    if R then
        Add("")
        Add("the plan's casts and waits of 2s or more")
        Add("%7s  %-18s %-12s %5s  %s", "t", "cast", "target", "cost", "why")
        local Rt = rp.right.trace
        for i = 1, Rt.nEv do
            local kind = Rt.ev.kind[i]
            local reason = Rt.reasons and Rt.reasons[i]
            local why = reason and SP.ReasonText(reason, names)
            if kind == TK.CAST then
                local tgt = rec.roster[Rt.ev.tgt[i]] and rec.roster[Rt.ev.tgt[i]].name or "-"
                local rule = SP.RULE_NAMES[Rt.ev.why[i]]
                Add("%7.2f  %-18s %-12s %5d  %s", Rt.ev.t[i], SpellName(Rt.ev.a[i], names), Strip(tgt),
                    Rt.ev.b[i] or 0, Strip(why or rule or ""))
            elseif kind == TK.WAIT and (Rt.ev.a[i] or 0) >= 2 then
                Add("%7.2f  %-18s %-12s %5s  %s", Rt.ev.t[i], string.format("wait %.1fs", Rt.ev.a[i]), "", "",
                    Strip(why or ""))
            end
        end
    end
    return lines, rp, L, R, plan, planName, planWhy
end

--------------------------------------------------------------------------------
-- The header every command prints
--------------------------------------------------------------------------------
Say("file:  %s", I.file)
Say("client: forever (%s)", opts.flavour and ("--flavour " .. opts.flavour) or ("read from the file: " .. I.detectedWhy))
Say("char:  %s   (%d recording(s), %d practice fight(s))", charKey, #(cdb.recordings or {}), #(cdb.practice or {}))
if #chars > 1 then
    local others = {}
    for _, c in ipairs(chars) do if c.key ~= charKey then others[#others + 1] = c.key end end
    Say("       also in the file: %s (--char)", table.concat(others, ", "))
end
Say("")

if cmd == "list" then
    local function Table(title, list, prefix)
        Say("%s", title)
        if #list == 0 then Say("  none"); return end
        Say("%-5s %-16s %-24s %7s %5s %6s %7s %-8s %s", "#", "when", "zone", "dur", "casts", "spent",
            "tracked", "kit", "validate")
        for i, r in ipairs(list) do
            local word = UseKitFor(r)
            local casts, mana = CastsOf(r)
            Say("%-5s %-16s %-24s %6.1fs %5d %6d %7d %-8s %s%s", prefix .. i, When(r.id), Strip(r.zone or "?"):sub(1, 24),
                r.dur or 0, casts, mana, #(r.tracked or {}), word, Verdict(r), r.pinned and "  [pinned]" or "")
        end
    end
    Table("recordings (v3 streams, newest first)", MD.FightRecorder:List(), "")
    Say("")
    Table("practice fights (newest first)", MD.Practice.List(), "p")
    Say("")
    Say("kit: recorded = the kit the fight was stored with; inferred = read back off a practice fight's own")
    Say("     heals (it was stored before fights carried their kit); last = the character's last kit (cdb.kit),")
    Say("     not necessarily this fight's; STUB = the stub's spellbook - the numbers are not yours.")

elseif cmd == "validate" then
    local rec, label = Get()
    local _, kitLine = UseKitFor(rec)
    Say("%s", kitLine)
    for _, line in ipairs(MD:ValidationReport(rec, label)) do Say("%s", Strip(line)) end

elseif cmd == "replay" then
    local rec, label = Get()
    local _, kitLine = UseKitFor(rec)
    local lines = ReplayLines(rec, label, kitLine)
    for _, line in ipairs(lines) do Say("%s", line) end

elseif cmd == "coach" then
    local rec, label = Get()
    local _, kitLine = UseKitFor(rec)
    Say("%s", kitLine)
    local entry = opts.strategy and (SP.Strategy(opts.strategy) or OBJECTIVE[opts.strategy])
    if opts.strategy and not entry then
        Say("unknown strategy %q. One of: %s", opts.strategy, StrategyList())
        os.exit(2)
    end
    if not entry then
        local lines, frames = Search(rec, label, opts.force)
        for _, line in ipairs(lines) do Say("%s", Strip(line)) end
        if SP.plans[rec.id] then Say("(the search ran across %d stub frames)", frames) end
    else
        -- one strategy's own card: the replay window's two columns for it, and
        -- every cast of yours labelled against it
        local validation = SM:Validate(rec, RM:SpellKit())
        if not (opts.force or validation.ok) then
            Say("coach: this fight does not replay, so there is nothing to suggest.")
            for _, g in ipairs(validation.gates) do
                if not g.ok then Say("  %s: %s", g.name, Strip(g.text)) end
            end
            Say("  coach %s force --strategy %s to see the card anyway.", label, opts.strategy)
            os.exit(0)
        end
        opts.force = true
        local _, rp, L, R, plan, planName, planWhy = ReplayLines(rec, label, kitLine)
        Say("strategy: %s - %s", planName or opts.strategy, Strip(planWhy or ""))
        if not plan then os.exit(0) end
        local binds = {}
        for _, fam in ipairs(SP.BINDABLE) do
            if plan.binds[fam] then binds[#binds + 1] = SpellName(plan.binds[fam], rec.names) end
        end
        Say("  binds: %s", #binds > 0 and table.concat(binds, ", ") or "none")
        Say("  %s", COLUMN_HEAD)
        Say("  %s", ColumnLine("you", L))
        Say("  %s", ColumnLine("plan", R))
        local d = R.spent - L.spent
        Say("  the plan spends %d %s than you, regenerates %d %s, ends %d %s, and is outside the 5SR %.1fs %s",
            math.abs(d) + 0.5, d > 0 and "more" or "less", math.abs(R.regen - L.regen) + 0.5,
            R.regen >= L.regen and "more" or "less", math.abs((R.manaEnd or 0) - (L.manaEnd or 0)) + 0.5,
            (R.manaEnd or 0) >= (L.manaEnd or 0) and "higher" or "lower", math.abs(R.outside - L.outside),
            R.outside >= L.outside and "longer" or "shorter")
        local counts = {}
        for _, c in ipairs(rp.casts or {}) do counts[c.label or "?"] = (counts[c.label or "?"] or 0) + 1 end
        local keys = {}
        for k, v in pairs(counts) do keys[#keys + 1] = k .. " " .. v end
        table.sort(keys)
        Say("  your casts against it: %s", #keys > 0 and table.concat(keys, ", ") or "none labelled")
    end

elseif cmd == "report" then
    local rec, label = Get()
    local _, kitLine = UseKitFor(rec)
    local casts = CastsOf(rec)
    Say("%s %s: %s, %s, %.1fs, %d own casts%s", rec.practice and "practice" or "recording", label,
        Strip(rec.zone or "?"), When(rec.id), rec.dur or 0, casts,
        rec.client and string.format("  (played on %s, level %s, SpellTuner %s%s)", rec.client,
            tostring(rec.level or "?"), tostring(rec.version or "?"), rec.build and (", build " .. rec.build) or "")
        or "")
    Say("%s", kitLine)
    for _, line in ipairs(dofile(here .. "/reportlines.lua")(MD, rec, RM:SpellKit())) do Say("  %s", Strip(line)) end

elseif cmd == "export" then
    local rec, label = Get()
    local _, kitLine = UseKitFor(rec)
    local lines = ReplayLines(rec, label, kitLine)
    local dir = opts.out or ((arg[1] or ".") .. "/.logs/forever")
    os.execute(string.format("mkdir -p %q", dir))
    local base = string.format("%s/%s-%s", dir, label, tostring(rec.id))
    -- the fight alone, as a SavedVariables file: `--file <it>.lua` imports it
    -- again, with the kit it was replayed with beside it
    local one = { char = { [charKey] = { kit = savedKit } } }
    one.char[charKey][rec.practice and "practice" or "recordings"] = { rec }
    one.session = db.session
    local W = dofile(here .. "/svwrite.lua")
    W.Write(base .. ".lua", { SpellTunerDB = one })
    local f = assert(io.open(base .. ".txt", "w"))
    f:write("file:  ", I.file, "\n", "char:  ", charKey, "\n\n")
    for _, line in ipairs(lines) do f:write(line, "\n") end
    f:close()
    Say("wrote %s.lua (the fight, importable with --file) and %s.txt (%d lines: the gates, both columns, " ..
        "the mana and every cast)", base, base, #lines)

elseif cmd == "runs" or cmd == "gates" or cmd == "spells" then
    Say("%s: not on Forever - runs are not recorded there yet, and the spell summary is TBC's", cmd)
    os.exit(1)

else
    Say("unknown command %q. On Forever: list, validate, replay, coach, report, export (N or pN); --strategy one of %s",
        cmd, StrategyList())
    os.exit(1)
end
