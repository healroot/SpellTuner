-- bash tools/run.sh tools/practicereport.lua [list | report N | export N] [options]
--
-- Practice fights (Simulate -> Practice, Engine/Practice.lua) offline, so a
-- fight the author played can be looked at, and kept, the way a bug report is
-- (2026-09-29, the author: "to measure it, I would like to have practice
-- recordings so we can improve the code from such reports").
--
--   list          every practice fight of the character: p1 is the newest
--   report N      pN replayed through the engine (what you played) beside every
--                 strategy in SP.STRATEGY_SET on the same fight: mana spent,
--                 regenerated, USED (what left the pool), at the end, still owed,
--                 deaths, seconds one hit from death, lowest health, casts
--   export N      pN as a fixture: tools/data/practice/<id>.lua, the record and
--                 the kit it was simulated with, which is everything needed to
--                 replay it exactly -- mana included -- with no game and no book
--
-- Options: --file <path>     the SavedVariables file (default: $MD_SAVEDVARS, then
--                            .logs/SpellTuner.lua, then the author's WoW: Forever
--                            beta install, then the anniversary one)
--          --char <key>      "Name-Realm" (default: the character with the most
--                            practice fights)
--          --fixture <path>  read an exported fixture instead of a SavedVariables file
--
-- SavedVariables reach the disk only on /reload or logout: /reload after the
-- fight you want to send, then run this.
--
-- The kit. A practice fight recorded since 2026-09-29 carries the kit it was
-- simulated with (`rec.kit`); an older one does not, and on Forever that kit
-- came from the live spellbook, which this tool has no access to. For those,
-- the kit is RECONSTRUCTED from the fight's own events -- a cast's cost is its
-- OWNCAST amount, its cast time the gap from CASTSTART to OWNCAST, a direct
-- heal the amount it landed for (crits are expectations in practice, so that is
-- the value it was simulated with), a HoT's tick the amount of each tick and
-- its period the gap between them -- and the report says which. Either way the
-- report checks it: the gates replay the fight, and a wrong kit fails them.
local here = arg[0]:match("^(.*)/[^/]+$")

local cmd, n, opts = "report", 1, {}
do
    local i = 2   -- arg[1] is the checkout root (tools/run.sh)
    while i <= #arg do
        local a = arg[i]
        if a == "--file" then opts.file = arg[i + 1]; i = i + 1
        elseif a == "--char" then opts.char = arg[i + 1]; i = i + 1
        elseif a == "--fixture" then opts.fixture = arg[i + 1]; i = i + 1
        elseif a:match("^p?%d+$") then n = tonumber(a:match("%d+"))
        elseif a:match("^%a+$") then cmd = a end
        i = i + 1
    end
end

local function exists(p) local f = io.open(p, "r"); if f then f:close(); return true end return false end

-- the practice fights, from a fixture or from the game's file
local recs, charKey, source = {}, nil, nil
if opts.fixture then
    local fx = dofile(opts.fixture)
    recs[1] = fx.rec
    recs[1].kit = recs[1].kit or fx.kit
    source = opts.fixture
else
    local file = opts.file or os.getenv("MD_SAVEDVARS")
    if not file then
        local candidates = { ".logs/SpellTuner.lua" }
        for _, flav in ipairs({ "_classic_beta_", "_anniversary_" }) do
            local p = io.popen('ls "/mnt/e/Blizzard/World of Warcraft/' .. flav
                .. '/WTF/Account"/*/SavedVariables/SpellTuner.lua 2>/dev/null')
            if p then for line in p:lines() do candidates[#candidates + 1] = line end; p:close() end
        end
        for _, c in ipairs(candidates) do if exists(c) then file = c; break end end
    end
    if not file or not exists(file) then
        print("practicereport: no SavedVariables file. Pass --file <path> or --fixture <path>, or set MD_SAVEDVARS.")
        os.exit(2)
    end
    dofile(file)
    local db = _G.SpellTunerDB or _G.ManaDemonDB
    if not db then print("practicereport: " .. file .. " holds no SpellTunerDB."); os.exit(2) end
    local chars = {}
    for key, c in pairs(db.char or {}) do chars[#chars + 1] = { key = key, n = #(c.practice or {}) } end
    table.sort(chars, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.key < b.key end)
    charKey = opts.char or (chars[1] and chars[1].key)
    local c = charKey and db.char[charKey]
    if not c or #(c.practice or {}) == 0 then
        print("practicereport: no practice fights in " .. file .. (charKey and (" for " .. charKey) or ""))
        os.exit(2)
    end
    for _, r in ipairs(c.practice) do recs[#recs + 1] = r end
    table.sort(recs, function(a, b) return (a.id or 0) > (b.id or 0) end)
    source = file
end

HARNESS_FLAVOUR = "tbc"
local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua"); arg[0] = a0
local SM, SP = MD.SimModel, MD.SimPlanner
local K = SM.K

--------------------------------------------------------------------------------
-- The kit
--------------------------------------------------------------------------------
local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.floor((#list + 1) / 2)]
end

local function FamilyOf(rec, id)
    local sd = MD.SpellData.spells[id]
    if sd then return sd.family, sd.rank end
    local name = rec.names and rec.names[id]
    local fam, rank = name and name:match("^(%a+) r(%d+)$")
    return fam, tonumber(rank)
end

-- the shapes Engine/SimModel.lua switches on, by family
local TYPES = { HealingTouch = "direct", Regrowth = "hybrid", Rejuvenation = "hot",
                Swiftmend = "instant", Lifebloom = "lifebloom" }

function ReconstructKit(rec)
    local ev = rec.ev
    local cost, castGap, direct, ticks, tickGap = {}, {}, {}, {}, {}
    local started, lastTick = {}, {}
    for i = 1, (rec.n or #ev.t) do
        local k, t, x, amt, tg = ev.kind[i], ev.t[i], ev.x[i], ev.amt[i], ev.tgt[i]
        if k == K.CASTSTART then
            started[x] = t
        elseif k == K.OWNCAST then
            if (amt or -1) >= 0 then cost[x] = cost[x] or {}; table.insert(cost[x], amt) end
            castGap[x] = castGap[x] or {}
            table.insert(castGap[x], started[x] and (t - started[x]) or 0)
            started[x] = nil
        elseif k == K.OWNHEAL or k == K.OWNTICK then
            local id = x % 100000
            local crit = x >= 100000
            if not crit then
                if k == K.OWNHEAL then
                    direct[id] = direct[id] or {}; table.insert(direct[id], amt)
                else
                    ticks[id] = ticks[id] or {}; table.insert(ticks[id], amt)
                    local key = id .. ":" .. tg
                    if lastTick[key] then
                        tickGap[id] = tickGap[id] or {}
                        table.insert(tickGap[id], t - lastTick[key])
                    end
                    lastTick[key] = t
                end
            end
        end
    end
    local caster = {}
    for id, costs in pairs(cost) do
        local fam, rank = FamilyOf(rec, id)
        local e = { family = fam, rank = rank, type = TYPES[fam] or "direct", gcd = 1.5,
                    cost = median(costs), directCrit = 0 }
        local gap = median(castGap[id] or {}) or 0
        if e.type == "direct" or e.type == "hybrid" then
            e.cast = gap > 0 and math.floor(gap * 10 + 0.5) / 10 or 1.5
            e.castBase = e.cast
        else
            e.cast = 1.5
        end
        if direct[id] then e.direct = median(direct[id]) end
        if ticks[id] then
            e.tick = median(ticks[id])
            local period = median(tickGap[id] or {}) or 3
            e.tickPeriod = math.floor(period + 0.5)
            -- the longest run of ticks one application produced is its length;
            -- a refresh cuts a run short, so the longest is the whole of it
            local runLen, best, last = {}, 0, {}
            for i = 1, (rec.n or #ev.t) do
                if ev.kind[i] == K.OWNCAST and ev.x[i] == id then runLen[ev.tgt[i]] = 0 end
                if ev.kind[i] == K.OWNTICK and ev.x[i] % 100000 == id then
                    local tg = ev.tgt[i]
                    runLen[tg] = (runLen[tg] or 0) + 1
                    if runLen[tg] > best then best = runLen[tg] end
                end
            end
            e.ticks = best
            e.duration = best * e.tickPeriod
        end
        caster[id] = e
    end
    return { caster = caster, tree = caster, crit = 0 }
end

local function KitOf(rec)
    if rec.kit and rec.kit.caster then return rec.kit, "stored with the fight" end
    return ReconstructKit(rec), "RECONSTRUCTED from the fight's own events (recorded before 2026-09-29)"
end

--------------------------------------------------------------------------------
-- Serialising a fixture: sorted keys, so two exports of one fight are one diff
--------------------------------------------------------------------------------
local function Ser(v, ind, out)
    local t = type(v)
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
        else out[#out + 1] = string.format("%.17g", v) end
    elseif t == "string" then out[#out + 1] = string.format("%q", v)
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        local isArray = #keys == #v
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = "\n" .. ind .. "  "
            if not isArray then
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then out[#out + 1] = k .. " = "
                else out[#out + 1] = "["; Ser(k, "", out); out[#out + 1] = "] = " end
            end
            Ser(v[k], ind .. "  ", out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "\n" .. ind .. "}"
    else
        out[#out + 1] = "nil"
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------
local function Line(i, r)
    return string.format("p%d  %s  %-18s %5.1fs  %2d casts  %4d mana spent  pool %d  regen %.2f/%.3f  kit %s%s%s",
        i, os.date("!%Y-%m-%d %H:%M UTC", r.id or 0), r.zone or "?", r.dur or 0, r.ownCasts or 0,
        r.spent or 0, r.pool or 0, r.initial and r.initial.apiBase or 0,
        r.initial and r.initial.apiCasting or 0, r.kit and "stored" or "not stored",
        r.pinned and "  PINNED" or "",
        r.client and string.format("  (%s, level %s, %s%s)", r.client, tostring(r.level or "?"),
            tostring(r.version or "?"), r.build and (", build " .. r.build) or "") or "")
end

print("practicereport: " .. source .. (charKey and (" - " .. charKey) or ""))
if cmd == "list" then
    for i, r in ipairs(recs) do print(Line(i, r)) end
    return
end

local rec = recs[n]
if not rec then print(string.format("practicereport: no p%d (%d kept)", n, #recs)); os.exit(2) end
local kit, kitSource = KitOf(rec)
print(Line(n, rec))
print("  kit: " .. kitSource)

if cmd == "export" then
    local fx = { rec = rec, kit = kit, kitSource = kitSource,
                 exported = "tools/practicereport.lua export, from " .. (source:match("([^/]+/[^/]+)$") or source) }
    local out = { "-- A practice fight, exported by tools/practicereport.lua (see its header).\n",
                  "-- Read with dofile: it returns { rec, kit, kitSource, exported }.\n", "return " }
    Ser(fx, "", out)
    out[#out + 1] = "\n"
    os.execute("mkdir -p tools/data/practice")
    local path = string.format("tools/data/practice/%d.lua", rec.id or 0)
    local f = assert(io.open(path, "w"))
    f:write(table.concat(out))
    f:close()
    print("  written: " .. path)
    return
end

-- report
local v = SM:Validate(rec, kit)
print(string.format("  gates: %s", v and (v.ok and "PASS" or "FAIL") or "?"))
for _, g in ipairs(v and v.gates or {}) do
    if not g.ok then print("    " .. g.name .. ": " .. (g.text or "")) end
end
local sc = SM.ScenarioFromRecording(rec, kit)
local pool = sc.pool or 0
local function Row(name, r, plan)
    local owed = plan and SP.ManaOwed(r, plan) or 0
    print(string.format("  %-32s %5.0f %5.0f %5.0f %5.0f %5.0f %2d %5.1f %4.0f%% %3d %4.0f",
        name, r.manaSpent or 0, r.regenGained or 0, r.manaUsed or 0, r.manaEnd or 0, owed,
        r.deaths and r.deaths.n or 0, r.floorSeconds or 0, (r.lowest and r.lowest.hp or 1) * 100,
        r.casts or 0, r.lowestMana or 0))
end
print(string.format("  %-32s %5s %5s %5s %5s %5s %2s %5s %5s %3s %4s", "", "spent", "regen", "used",
    "end", "owed", "dd", "floor", "low", "cst", "lowM"))
local binds = SP.MaxRankBinds(rec.initial and rec.initial.known)
-- what you still owe is priced like every row's: at the best heal per mana the
-- same binds buy (SP.ManaOwed)
Row("you (the replay)", SM:Run(sc, nil, { critMode = "ev" }), SP.NewPlan(binds, {}, kit))
for _, entry in ipairs(SP.STRATEGY_SET) do
    local plan = SP.MakeStrategy(entry, binds, kit, { scenario = sc, seed = rec.id or 1 })
    if plan then Row(entry.label, SP.RunPlan(sc, plan, { critMode = "ev" }), plan) end
end
print(string.format("  pool %d; used = what left the pool (start - end, plus the regen a rule still running at the end has yet to cost)", pool))
