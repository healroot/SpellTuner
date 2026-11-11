-- tools/run.sh --flavour forever tools/futureranks.lua
--
-- Ranks not learned yet (Spells/Book.lua's AddFutureRanks, Data/Ranks_Forever.lua):
--
--   1. a family's ranks the spellbook does not list come from ST.FutureRanks,
--      read by id (the client's text, cost, cast, level): known = false,
--      future = true, valued; never a mark, never maxKnown; the contract holds
--   2. left out: an id the client calls known, one it names otherwise, one it
--      does not know, a family the player has none of; the setting off
--   3. an unloaded text ("") asks the client to load it, once; the next scan reads it
--   4. the table's level when the client names none
--   5. the bonus fit never takes a reading from a rank not learned yet
--   6. What if Level: a rank learned by the typed level competes, one above it
--      does not (a learned one included); the live book unwritten
--   7. the penalty: none for a rank learned above the level it is priced at,
--      the share x P(typed) / P(live) once the typed level passes learn + 17
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
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
-- Forever values average crit in (Spells/Book.lua's CritFactor, tools/critcheck.lua);
-- this suite's numbers are the text's, so the stub's spell crit is 0 here
if type(S.crit) == "table" then for school = 1, 7 do S.crit[school] = 0 end end
local Book, WI = ST.Book, ST.WhatIf

S.level, ST.player.level, ST.player.class = 12, 12, "DRUID"
S.bonusHealing = 100

-- The stub's book: Healing Touch rank 1 (5185), Rejuvenation ranks 1 and 2
-- (774, 1058), Wrath rank 1 (5176). The table is the test's own, so the
-- generated file's numbers never move these checks.
ST.FutureRanks = {
    DRUID = {
        ["Healing Touch"] = {
            [1] = { id = 5185, level = 1 },
            [2] = { id = 5186, level = 8 },
            [3] = { id = 5187, level = 14 },
            [4] = { id = 5188, level = 20 },  -- the client does not know it
            [5] = { id = 5189, level = 26 },  -- the client names it otherwise
            [6] = { id = 6778, level = 32 },  -- the client says it is known
        },
        ["Rejuvenation"] = {
            [1] = { id = 774, level = 4 }, [2] = { id = 1058, level = 10 },
            [3] = { id = 1430, level = 16 },   -- text not loaded at first
        },
        ["Regrowth"] = { [1] = { id = 8936, level = 12 } }, -- no rank in the book
        ["Moonfire"] = { [1] = { id = 8921, level = 4 } },
    },
}

local htText = "Heals a friendly target for 94 to 119."
S.AddSpell(5186, "Healing Touch", "Rank 2", function() return htText end,
    { noSlot = true, known = false, cast = 2000, cost = 55, level = 8 })
S.AddSpell(5187, "Healing Touch", "Rank 3", function() return "Heals a friendly target for 204 to 253." end,
    { noSlot = true, known = false, cast = 2500, cost = 110, level = 0 }) -- no level from the client
S.AddSpell(5189, "Healing Wave", "Rank 5", function() return "Heals for 500." end,
    { noSlot = true, known = false, cast = 3000, cost = 200, level = 26 })
S.AddSpell(6778, "Healing Touch", "Rank 6", function() return "Heals a friendly target for 900 to 1000." end,
    { noSlot = true, cast = 3500, cost = 300, level = 32 }) -- known (the stub's default)
local rjLoaded = false
S.AddSpell(1430, "Rejuvenation", "Rank 3", function() return rjLoaded and "Heals the target for 116 over 12 sec." or "" end,
    { noSlot = true, known = false, cast = 0, cost = 75, level = 16 })
S.AddSpell(8936, "Regrowth", "Rank 1", function() return "Heals a friendly target for 93 to 107." end,
    { noSlot = true, known = false, cast = 2000, cost = 80, level = 12 })

local function Fresh()
    Book:MarkDirty()
    return Book:Get()
end

local function RankOf(fam, r)
    for _, e in ipairs(fam.ranks) do if e.rank == r then return e end end
    return nil
end

-- 1 ---------------------------------------------------------------------------
T("1 the ranks not learned yet join their family, read by id", function()
    local book = Fresh()
    local fam = book.families["Healing Touch"]
    local r2, r3 = RankOf(fam, 2), RankOf(fam, 3)
    local good = #fam.ranks == 3 and r2 and r3 and r2.id == 5186 and r3.id == 5187
        and r2.known == false and r2.future == true and r3.known == false
        and r2.value ~= nil and r2.perMana ~= nil and r2.cost and r2.cost.amount == 55
        and r2.cast == 2 and r2.level == 8 and book.read.future == 3
    return good == true, string.format("ranks=%d r2=%s v=%s future=%s", #fam.ranks, tostring(r2 and r2.id),
        tostring(r2 and r2.value), tostring(book.read.future))
end)

T("1 a rank not learned yet holds no mark and is never maxKnown", function()
    local fam = Book:Get().families["Healing Touch"]
    local r1 = RankOf(fam, 1)
    local marked = false
    for _, e in ipairs(fam.ranks) do
        if e.known == false and (e.suggested or e.dominated or fam.maxRank == e or fam.effRank == e) then
            marked = true
        end
    end
    return fam.maxKnown == r1 and fam.suggested == r1 and not marked, "maxKnown=" .. tostring(fam.maxKnown and fam.maxKnown.rank)
end)

T("1 every entry passes the book contract (the scan checks it)", function()
    local book = Fresh()
    local errs = ST.BookShape.Validate(book, Book._seamFields)
    return type(errs) ~= "table" or #errs == 0, type(errs) == "table" and table.concat(errs, "; ") or nil
end)

-- 2 ---------------------------------------------------------------------------
T("2 left out: unknown to the client, named otherwise, known, no family", function()
    local book = Book:Get()
    local s = book.spells
    return s[5188] == nil and s[5189] == nil and s[6778] == nil and s[8936] == nil
        and book.families["Regrowth"] == nil and book.families["Healing Wave"] == nil
end)

T("2 the setting off: no rank not learned yet", function()
    ST.db.spellsFutureRanks = false
    local book = Fresh()
    local n = #book.families["Healing Touch"].ranks
    ST.db.spellsFutureRanks = nil
    local back = #Fresh().families["Healing Touch"].ranks
    return n == 1 and book.read.future == 0 and back == 3, "off=" .. n .. " on=" .. back
end)

-- 3 ---------------------------------------------------------------------------
T("3 an unloaded text asks the client to load it once; the next scan reads it", function()
    local asked = 0
    for _, id in ipairs(S.loadRequests) do if id == 1430 then asked = asked + 1 end end
    Fresh(); Fresh()
    local again = 0
    for _, id in ipairs(S.loadRequests) do if id == 1430 then again = again + 1 end end
    local before = Book:Get().spells[1430]
    rjLoaded = true
    local after = Fresh().spells[1430]
    return asked == 1 and again == 1 and before.descState == "empty" and before.value == nil
        and after.descState == "ok" and after.value == 116,
        string.format("asked=%d again=%d before=%s after=%s", asked, again, tostring(before.descState),
            tostring(after.value))
end)

-- 4 ---------------------------------------------------------------------------
T("4 the table's level when the client names none", function()
    local r3 = Book:Get().spells[5187]
    return r3.level == 14, "level=" .. tostring(r3.level)
end)

-- 5 ---------------------------------------------------------------------------
T("5 the bonus fit takes no reading from a rank not learned yet", function()
    ST.cdb.bonusCounts = {}
    S.bonusHealing = 120; Fresh()
    S.bonusHealing = 100; Fresh()
    local store = ST.cdb.bonusCounts
    return store[5186] == nil and store[5187] == nil and store[1430] == nil
end)

-- 6 ---------------------------------------------------------------------------
local function WhatIfFam(level)
    WI:Clear()
    WI:Set("level", level)
    return WI:Book().families["Healing Touch"]
end

T("6 What if Level 14: ranks 2 and 3 compete, the live book unwritten", function()
    local fam = WhatIfFam(14)
    local r2, r3 = RankOf(fam, 2), RankOf(fam, 3)
    local live = Book:Get().families["Healing Touch"]
    return r2.known == true and r3.known == true and fam.maxKnown == r3
        and (fam.suggested == r2 or fam.suggested == r3 or fam.suggested == RankOf(fam, 1))
        and RankOf(live, 3).known == false and live.maxKnown == RankOf(live, 1),
        "maxKnown=" .. tostring(fam.maxKnown and fam.maxKnown.rank) .. " best=" .. tostring(fam.suggested and fam.suggested.rank)
end)

T("6 What if Level 10: rank 3 (learn at 14) still does not compete", function()
    local fam = WhatIfFam(10)
    local r3 = RankOf(fam, 3)
    local rj = WI:Book().families["Rejuvenation"]
    return RankOf(fam, 2).known == true and r3.known == false and not r3.suggested
        and fam.maxRank ~= r3 and fam.effRank ~= r3 and RankOf(rj, 2).known == true
end)

T("6 What if Level 5: a learned rank above it (Rejuvenation 2, at 10) does not compete", function()
    WI:Clear(); WI:Set("level", 5)
    local rj = WI:Book().families["Rejuvenation"]
    local ok2 = RankOf(rj, 1).known == true and RankOf(rj, 2).known == false and rj.maxKnown == RankOf(rj, 1)
    WI:Clear()
    return ok2 == true
end)

-- 7 ---------------------------------------------------------------------------
T("7 no penalty for a rank learned above the level it is priced at", function()
    local Coef = ST.Coefficients
    -- live level 12: rank 3 (learn 14) and rank 2 (learn 8, start 25) both P 1
    return Coef.LevelPenalty(5187, 14, 12, "heal") == 1 and Coef.LevelPenalty(5186, 8, 12, "heal") == 1
        and Coef.LevelPenalty(5187, 14, 31, "heal") == 1
end)

T("7 What if Level 40: the share x P(40) / P(12) -- rank 2 x0.25, rank 3 x0.55", function()
    local live = Book:Get().families["Healing Touch"]
    local l2, l3 = RankOf(live, 2), RankOf(live, 3)
    if not (l2.bonus and type(l2.bonus.counts) == "number" and l3.bonus and type(l3.bonus.counts) == "number") then
        return false, "no live share"
    end
    local fam = WhatIfFam(40)
    local w2, w3 = RankOf(fam, 2), RankOf(fam, 3)
    WI:Clear()
    local function near(a, b) return math.abs(a - b) < 1e-6 end
    return near(w2.bonus.counts, l2.bonus.counts * 0.25) and near(w3.bonus.counts, l3.bonus.counts * 0.55)
        and w2.value < l2.value,
        string.format("r2 %.4f -> %.4f, r3 %.4f -> %.4f", l2.bonus.counts, w2.bonus.counts,
            l3.bonus.counts, w3.bonus.counts)
end)

print("")
print(string.format("%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("FAIL " .. f) end
os.exit(#fails == 0 and 0 or 1)
