-- tools/run.sh [--flavour forever|tbc] tools/perfcheck.lua
--
-- The performance rules of docs/review/perf-full-0.18.1.md, held (0.18.2):
--
--   forever
--   1. a cast never scans the book; it reads one cost (P1)
--   2. no time rule: an unchanged book is never read again (P3)
--   3. a player aura is a soft mark: no scan in combat, one after it (P4)
--   4. a rescan that moved no entry fires no BOOK_CHANGED (P4)
--   5. a description is parsed once; the tooltip read once per hard change (F2)
--   6. ranks not learned yet only once a view asked (rule 3)
--   7. the sweeper: a text that changed is a soft mark, never a scan (rule 1)
--   8. every other class's generated data dropped at login (M1)
--   9. Feeds.Poll builds nothing while nobody listens (F5)
--  10. the adapter: every return kept, a secret taints, no table per call (F4)
--  11. ManaModel.Face(state, now, out) fills `out` as a fresh face reads (F5)
--  14. /st dump has a perf line (scans, last scan ms, entries, memory)
--   tbc
--  12. fight recording off by default; an old install's `true` turned off once (M2)
--  13. the clock's state: two tables alternated, a reader one tick back keeps its values
HARNESS_FLAVOUR = { "forever", "tbc" }
HARNESS_PRUNE_CLASS_DATA = true -- section 8: the login prune runs here

local here = arg[0]:match("^(.*)/[^/]+$")
local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-74s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end
local function T(name, fn)
    local good, cond, detail = pcall(fn)
    if not good then check(name, false, "raised: " .. tostring(cond)) return end
    check(name, cond == true, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local ST = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local forever = S.flavour == "forever"

local function InFight(fn)
    S.inCombat, ST.inCombat = true, true
    S.Fire("PLAYER_REGEN_DISABLED")
    local a, b = fn()
    S.inCombat, ST.inCombat = false, false
    S.Fire("PLAYER_REGEN_ENABLED")
    return a, b
end

if forever then
    local Book = ST.Book

    T("1 a cast never scans the book; it reads one cost", function()
        Book:MarkDirty(); Book:Get()
        local scans = Book.scans
        local mana0 = ST.Pool.model.mana
        InFight(function()
            for _ = 1, 5 do S.Cast(5185); S.Fire("UNIT_AURA", "player") end
        end)
        return Book.scans == scans and ST.Pool.model.mana < mana0,
            string.format("scans %s->%s mana %s->%s", scans, Book.scans, mana0, ST.Pool.model.mana)
    end)

    T("2 no time rule: an unchanged book is never read again", function()
        Book:MarkDirty(); Book:Get()
        local scans = Book.scans
        for _ = 1, 20 do S.Tick(0.5); Book:Get() end
        return Book.scans == scans, "scans +" .. (Book.scans - scans)
    end)

    T("3 a player aura in combat: no scan; after the fight, one", function()
        Book:MarkDirty(); Book:Get()
        local scans = Book.scans
        local during = InFight(function()
            for _ = 1, 10 do S.Fire("UNIT_AURA", "player"); Book:Get() end
            return Book.scans
        end)
        Book:Get(); Book:Get()
        return during == scans and Book.scans == scans + 1, string.format("during +%d after +%d",
            during - scans, Book.scans - scans)
    end)

    T("4 a rescan that moved no entry fires no BOOK_CHANGED; a moved one does", function()
        Book:MarkDirty(); Book:Get()
        local fired = 0
        ST:RegisterCallback("BOOK_CHANGED", function() fired = fired + 1 end)
        Book:MarkDirty(); Book:Get()
        local quiet = fired
        local was = S.bonusHealing
        S.bonusHealing = (S.bonusHealing or 0) + 123
        Book:MarkDirty(); Book:Get()
        local moved = fired
        S.bonusHealing = was
        Book:MarkDirty(); Book:Get()
        return quiet == 0 and moved == 1, string.format("quiet %d moved %d", quiet, moved)
    end)

    T("5 a description parsed once; the tooltip read once until a hard mark", function()
        local P, real = ST.Parse, ST.Parse.Description
        local parses, tips = 0, 0
        P.Description = function(...) parses = parses + 1 return real(...) end
        local realTip = ST.API.SpellTooltipData
        ST.API.SpellTooltipData = function(...) tips = tips + 1 return realTip(...) end
        Book:MarkDirty(); Book:Get()
        local p1, t1 = parses, tips
        Book:MarkSoft(); Book:Get()
        Book:MarkSoft(); Book:Get()
        local p2, t2 = parses, tips
        Book:MarkDirty(); Book:Get()
        local t3 = tips
        P.Description, ST.API.SpellTooltipData = real, realTip
        return p2 == p1 and t2 == t1 and t1 > 0 and t3 == t1 * 2,
            string.format("parses %d->%d tips %d->%d->%d", p1, p2, t1, t2, t3)
    end)

    T("6 ranks not learned yet: none until a view asks (Book:WantFuture)", function()
        return Book.wantFuture == false and Book:AddFutureRanks({}, {}) == 0
    end)

    T("7 the sweeper: a changed text is a soft mark, not a scan", function()
        local txt = "Heals a friendly target for 100 to 120."
        S.AddSpell(99001, "Perf Mend", "Rank 1", function() return txt end, { cast = 1500, cost = 50, level = 5 })
        Book:MarkDirty(); Book:Get()
        local scans = Book.scans
        txt = "Heals a friendly target for 130 to 150."
        local n = 0
        for _ = 1, 40 do
            S.Tick(0.5)
            n = n + 1
            if Book._soft then break end
        end
        local soft, still = Book._soft == true, Book.scans == scans
        Book:Get()
        local e = Book:Peek().spells[99001]
        return soft and still and e and e.min == 130, string.format("soft %s after %d ticks, scans +%d, min %s",
            tostring(soft), n, Book.scans - scans, tostring(e and e.min))
    end)

    T("8 every other class's generated data dropped at login", function()
        local own = ST.player.class
        local bad = {}
        for _, key in ipairs(ST.CLASS_TABLES) do
            local t = ST[key]
            if type(t) == "table" then
                for c in pairs(t) do if c ~= own then bad[#bad + 1] = key .. "." .. c end end
            end
        end
        local rows = 0
        for _ in pairs(ST.CoefRules or {}) do rows = rows + 1 end
        return #bad == 0 and ST.classDataPruned == own and rows > 0 and rows < 200,
            string.format("left %s, coef rows %d", table.concat(bad, ","), rows)
    end)

    T("9 Feeds.Poll builds nothing while nobody listens", function()
        local F, real, n = ST.Feeds, ST.Feeds.Text, 0
        F.Text = function(...) n = n + 1 return real(...) end
        F.Poll()
        F.Text = real
        return n == 0, "texts built " .. n
    end)

    T("10 the adapter: every return kept, a secret taints, no table per call", function()
        _G.PerfCheckFn = function() return 1, nil, nil end
        local count = select("#", ST.API.Call("PerfCheckFn"))
        _G.PerfCheckSecret = function() return 1, S.Secret() end
        local a, why = ST.API.Call("PerfCheckSecret")
        _G.PerfCheckOne = function(x) return x end
        collectgarbage("collect"); collectgarbage("stop")
        local m0 = collectgarbage("count")
        for i = 1, 2000 do ST.API.Call("PerfCheckOne", i) end
        local bytes = (collectgarbage("count") - m0) * 1024 / 2000
        collectgarbage("restart")
        return count == 3 and a == nil and why == "secret" and bytes < 8,
            string.format("returns %d secret %s/%s bytes/call %.1f", count, tostring(a), tostring(why), bytes)
    end)

    T("11 ManaModel.Face(state, now, out) fills out as a fresh face reads", function()
        local now = GetTime()
        local state = ST.Pool:Project(now)
        local fresh = ST.ManaModel.Face(state, now)
        local out = { stale = "x" }
        local same = ST.ManaModel.Face(state, now, out)
        local good = same == out and out.stale == nil
        for k, v in pairs(fresh) do
            if type(v) ~= "table" and out[k] ~= v then good = false end
        end
        for k in pairs(out) do if fresh[k] == nil then good = false end end
        return good
    end)

    T("14 /st dump has a perf line: scans, the last scan's time, entries, memory", function()
        local line
        for _, e in ipairs(ST:DumpLines()) do
            if e.key == "perf" then line = e.fn() end
        end
        return type(line) == "string" and line:find("^perf: book scans %d+, last [%d%.%-]+ ms, %d+ entries") ~= nil,
            tostring(line)
    end)
else
    T("12 fight recording: off by default; an old install's true turned off once", function()
        local def = ST.DEFAULTS.recordFights == false
        local said = {}
        local realPrint = ST.Print
        ST.Print = function(_, msg) said[#said + 1] = tostring(msg) end
        ST.db.recordFightsOff2, ST.db.recordFights = nil, true
        ST:Fire("MD_READY")
        local off = ST.db.recordFights == false and #said >= 1
        ST.db.recordFights = true
        ST:Fire("MD_READY")
        local kept = ST.db.recordFights == true
        ST.Print = realPrint
        ST.db.recordFights = false
        local line = false
        for _, s in ipairs(said) do if s:find("Record fights", 1, true) then line = true end end
        return def and off and kept and line, string.format("default %s off %s kept %s line %s", tostring(def),
            tostring(off), tostring(kept), tostring(line))
    end)

    T("13 the clock's state: two tables alternated; one tick back keeps its values", function()
        S.Tick(0.5)
        local a = ST:GetManaState()
        local aMana = a and a.mana
        S.Tick(0.5)
        local b = ST:GetManaState()
        S.Tick(0.5)
        local c = ST:GetManaState()
        return a and b and a ~= b and c == a and b.mana ~= nil and aMana ~= nil
    end)
end

--------------------------------------------------------------------------------
-- 15. /st perf, the profiler (Engine/Perf.lua, 2026-11-16), both lines
--------------------------------------------------------------------------------
do
    local PROF, Perf = ST.Prof, ST.Perf
    local realPrint = ST.Print
    ST.Print = function() end
    local function Burn(ms)
        local t = debugprofilestop() + ms
        while debugprofilestop() < t do end
    end
    local function Stat(label)
        for _, s in pairs(Perf.data.stats) do if s.label == label then return s end end
    end

    T("15a off by default: nothing timed, no data", function()
        ST:Fire("MD_READY")
        return PROF.on == false and Perf.data == nil, tostring(PROF.on)
    end)

    ST:RegisterCallback("PERFCHECK_INNER", function()
        Burn(3)
        local t = {}
        for i = 1, 3000 do t[i] = { i } end
    end)
    ST:RegisterCallback("PERFCHECK_OUTER", function()
        Burn(2)
        ST:Fire("PERFCHECK_INNER")
    end)
    ST:RegisterCallback("PERFCHECK_RAISE", function() error("perfcheck: a raising handler") end)

    T("15b on: a callback and the one it fires, each its self time and where it registered", function()
        Perf.Command("on")
        collectgarbage("stop")
        ST:Fire("PERFCHECK_OUTER")
        collectgarbage("restart")
        local o, i = Stat("fire PERFCHECK_OUTER"), Stat("fire PERFCHECK_INNER")
        local good = PROF.on and SpellTunerDB.perf.on == true and o and i and o.calls == 1 and i.calls == 1
            and i.ms >= 2.5 and o.ms >= 1.5 and o.ms < o.max - 2 and o.max >= 4.5
            and (tostring(o.site):find("perfcheck.lua:%d+") ~= nil or type(debugstack) ~= "function")
            and i.kb > 10
        return good == true, o and i and string.format("outer self %.1f max %.1f site %s; inner %.1f ms %.0f KB",
            o.ms, o.max, tostring(o.site), i.ms, i.kb) or "missing"
    end)

    T("15c the 0.5 s tick is timed; a long frame is kept as a hitch", function()
        S.Tick(0.5)
        local tick = Stat("tick")
        local n0 = Perf.data.eventN
        S.Tick(0.2)
        local e = Perf.data.events[(Perf.data.eventN - 1) % Perf.KEEP_EVENTS + 1]
        return tick ~= nil and tick.calls >= 1 and Perf.data.eventN > n0 and e.frame >= 199
            and Perf.data.frameHist[100] >= 1, string.format("tick %s, hitches %d -> %d",
            tostring(tick and tick.calls), n0, Perf.data.eventN)
    end)

    T("15d a raising handler is still sunk once and leaves no frame behind", function()
        local errs = #(S.clientErrors or {})
        local okFire = pcall(ST.Fire, ST, "PERFCHECK_RAISE")
        ST:Fire("PERFCHECK_INNER")
        return PROF.Current() == nil and Stat("fire PERFCHECK_RAISE") ~= nil
            and Stat("fire PERFCHECK_INNER").calls == 2, string.format("fire ok %s, errors %d -> %d, current %s",
            tostring(okFire), errs, #(S.clientErrors or {}), tostring(PROF.Current()))
    end)

    if forever then
        T("15e a book scan is noted with its mark and the handler that set it", function()
            ST:RegisterCallback("PERFCHECK_MARK", function()
                ST.Book:MarkDirty()
                ST.Book:Get()
            end)
            ST:Fire("PERFCHECK_MARK")
            local hit
            for kind, keys in pairs(Perf.data.notes) do
                if kind:find("book scans", 1, true) then
                    for key in pairs(keys) do
                        if key:find("hard, fire PERFCHECK_MARK -> fire PERFCHECK_MARK", 1, true) then hit = key end
                    end
                end
            end
            return hit ~= nil, tostring(hit)
        end)
    end

    T("15f the report: totals, handlers by self time with their file, hitches; kept in saved variables", function()
        local text = Perf.Report()
        local good = text:find("SpellTuner perf report", 1, true) and text:find("by self time", 1, true)
            and text:find("fire PERFCHECK_INNER", 1, true)
            and (text:find("perfcheck.lua:", 1, true) or type(debugstack) ~= "function")
            and text:find("hitches", 1, true) and SpellTunerDB.perf.report == text and not text:find("|", 1, true)
        return good and true or false, string.format("head %s self %s inner %s site %s hitches %s kept %s pipe %s",
            tostring(text:find("SpellTuner perf report", 1, true) ~= nil), tostring(text:find("by self time", 1, true) ~= nil),
            tostring(text:find("fire PERFCHECK_INNER", 1, true) ~= nil), tostring(text:find("perfcheck.lua:", 1, true) ~= nil),
            tostring(text:find("hitches", 1, true) ~= nil), tostring(SpellTunerDB.perf.report == text),
            tostring(text:find("|", 1, true) ~= nil))
    end)

    T("15g off: nothing more is timed, the data stays; on again starts fresh", function()
        Perf.Command("off")
        local calls = Stat("fire PERFCHECK_INNER").calls
        ST:Fire("PERFCHECK_INNER")
        local stayed = PROF.on == false and SpellTunerDB.perf.on == nil and Stat("fire PERFCHECK_INNER").calls == calls
        Perf.Command("on")
        local fresh = Stat("fire PERFCHECK_INNER") == nil
        Perf.Command("off")
        return stayed and fresh, string.format("stayed %s fresh %s", tostring(stayed), tostring(fresh))
    end)
    ST.Print = realPrint
end

print("")
print(string.format("%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
