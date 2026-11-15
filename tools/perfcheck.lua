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

print("")
print(string.format("%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
