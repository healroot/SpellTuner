-- tools/run.sh tools/bookcheck.lua
--
-- T7 (docs/tasks/T7-spell-book.md): Spells/Book.lua against the stub's
-- spellbook (T7a's fixed five slots plus the extra spells this suite adds via
-- S.AddSpell). Forever only -- the book walk is a Forever-only file.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local Book = MD.Book

--------------------------------------------------------------------------------
-- fixtures -- six extra spells beyond T7a's fixed five (5185, 774, 5176, 1058,
-- the slot-4 error row), each naming which acceptance item it is for.
--------------------------------------------------------------------------------

-- item 2/6/7: a second rank of Healing Touch, dominating rank 1 on both
-- per-mana and per-second -- the "max rank IS suggested" half of item 7.
S.AddSpell(90002, "Healing Touch", "Rank 2",
    function() return "Heals a friendly target for 90 to 110." end,
    { cast = 2000, cost = 50, level = 10 })

-- item 4: a family the book lists from rank 2 only -- rank 1 is a gap.
S.AddSpell(90010, "GapFamily", "Rank 2",
    function() return "Heals a friendly target for 20 to 30." end,
    { cast = 0, cost = 15, level = 1 })

-- item 5: a percentage-of-base-mana cost.
S.AddSpell(90020, "PercentSpell", "Rank 1",
    function() return "Causes 10 to 12 Fire damage to the target." end,
    { cast = 1500, cost = 0, costPercent = 5, level = 1 })

-- item 5: a free spell (an empty cost list).
S.AddSpell(90030, "FreeSpell", "Rank 1",
    function() return "Heals a friendly target for 5 to 8." end,
    { cast = 0, noCost = true, level = 1 })

-- item 2/9: a passive with no heal/damage numbers at all -- Book must never
-- crash on a family with no kind.
S.AddSpell(90040, "PassiveSpell", "Passive",
    function() return "A permanent racial passive." end,
    { cast = 0, noCost = true, level = 1 })

-- item 10: a spell the character has not learned yet.
S.AddSpell(90050, "LaterSpell", "Rank 1",
    function() return "Heals a friendly target for 100 to 120." end,
    { cast = 1500, cost = 60, level = 20, known = false })

-- item 9 (skip logic): a flyout row -- Book must never list it at all.
S.AddSpell(90060, "FlyoutThing", "Rank 1",
    function() return "Heals a friendly target for 1 to 2." end,
    { cast = 0, noCost = true, level = 1, itemType = Enum.SpellBookItemType.Flyout })

-- item 7: a constructed family where the max rank is NOT the suggested one --
-- rank 1 is far more mana-efficient (10 HPM vs 2 HPM) while rank 2 has the
-- higher per-second and is still worth at least 40% of rank 2's own value
-- (200 >= 0.4 * 500), so the 40%-floor rule picks rank 1 over the max rank.
--   R1: (195+205)/2 = 200 heal / 20 mana = 10 HPM; /1.5s cast = 133.33 HPS
--   R2: (495+505)/2 = 500 heal / 250 mana = 2 HPM; /1.5s cast = 333.33 HPS
-- neither dominates the other (R1 wins HPM, R2 wins HPS), so both survive
-- Pareto and the 40% floor is what decides it.
S.AddSpell(90070, "SubFamily", "Rank 1",
    function() return "Heals a friendly target for 195 to 205." end,
    { cast = 1500, cost = 20, level = 1 })
S.AddSpell(90071, "SubFamily", "Rank 2",
    function() return "Heals a friendly target for 495 to 505." end,
    { cast = 1500, cost = 250, level = 10 })

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function FindEntry(book, id) return book.spells[id] end

local function FindFamily(book, name) return book.families[name] end

local function ApproxEq(a, b, eps)
    eps = eps or 1e-9
    if a == math.huge and b == math.huge then return true end
    if type(a) ~= "number" or type(b) ~= "number" then return a == b end
    return math.abs(a - b) < eps
end

-- MD.API.Has caches a resolved function OBJECT forever, by design (the real
-- client's API surface does not change mid-session) -- so reassigning a
-- global AFTER Book has already scanned once (and so already asked Has for
-- it) changes nothing: Call() keeps invoking the stale cached reference. To
-- test "this function is missing/raises/answers a secret", the mutation has
-- to be in place BEFORE the very first ask, which means a brand new MD
-- table (a fresh Client/API.lua load -> a fresh, empty Has cache) rather
-- than the long-lived one every other item in this suite shares.
local function FreshBook(mutate)
    local restore = mutate()
    local freshMD = {}
    S.Load(S.loadedFiles, "SpellTuner", freshMD)
    local book = freshMD.Book:Scan()
    if restore then restore() end
    return book
end

--------------------------------------------------------------------------------
-- 1: the book is read through the skill lines, and by walking slots when they
-- do not answer -- the same spells either way
--------------------------------------------------------------------------------
do
    local bookLines = Book:Scan()
    local bookWalk = FreshBook(function()
        local saved = C_SpellBook.GetNumSpellBookSkillLines
        C_SpellBook.GetNumSpellBookSkillLines = function() return 0 end -- out of 1..20: forces the walk
        return function() C_SpellBook.GetNumSpellBookSkillLines = saved end
    end)

    local function IdSet(b)
        local set = {}
        for id in pairs(b.spells) do set[id] = true end
        return set
    end
    local a, b = IdSet(bookLines), IdSet(bookWalk)
    local same = true
    for id in pairs(a) do if not b[id] then same = false end end
    for id in pairs(b) do if not a[id] then same = false end end

    check("the book is read through the skill lines, and by walking slots when they do not answer",
        bookLines.read.via == "skilllines" and bookWalk.read.via == "walk" and same,
        "via=" .. tostring(bookLines.read.via) .. "/" .. tostring(bookWalk.read.via))
end

--------------------------------------------------------------------------------
-- 2: a family holds its ranks in rank order, each with its own id, text,
-- level and cast
--------------------------------------------------------------------------------
do
    local book = Book:Scan()
    local fam = FindFamily(book, "Healing Touch")
    local good = fam ~= nil and #fam.ranks == 2
        and fam.ranks[1].id == 5185 and fam.ranks[1].rank == 1
        and fam.ranks[1].rankText == "Rank 1" and fam.ranks[1].level == 1
        and fam.ranks[1].cast == 1.5
        and fam.ranks[2].id == 90002 and fam.ranks[2].rank == 2
        and fam.ranks[2].rankText == "Rank 2" and fam.ranks[2].level == 10
        and fam.ranks[2].cast == 2.0
    check("a family holds its ranks in rank order, each with its own id, text, level and cast",
        good, fam and string.format("#ranks=%d", #fam.ranks) or "no family")
end

--------------------------------------------------------------------------------
-- 3: every value comes from the spell's own description
--------------------------------------------------------------------------------
do
    local before = Book:Scan()
    local rejuvBefore = FindEntry(before, 774).value
    local htBefore = FindEntry(before, 5185).value

    S.bonusHealing = 10
    local after = Book:Scan()
    S.bonusHealing = 0
    local rejuvAfter = FindEntry(after, 774).value
    local htAfter = FindEntry(after, 5185).value

    check("every value comes from the spell's own description",
        rejuvAfter == rejuvBefore + 10 and htAfter == htBefore,
        string.format("rejuv %s -> %s, ht %s -> %s", tostring(rejuvBefore), tostring(rejuvAfter),
            tostring(htBefore), tostring(htAfter)))
end

--------------------------------------------------------------------------------
-- 4: a rank the book does not list is a gap
--------------------------------------------------------------------------------
do
    local book = Book:Scan()
    local fam = FindFamily(book, "GapFamily")
    local good = fam ~= nil and #fam.gaps == 1 and fam.gaps[1] == 1
    check("a rank the book does not list is a gap", good,
        fam and ("gaps=" .. table.concat(fam.gaps, ",")) or "no family")
end

--------------------------------------------------------------------------------
-- 5: cost is an amount, a percentage of base mana, free or unknown
--------------------------------------------------------------------------------
do
    local book = Book:Scan()
    local htR1 = FindEntry(book, 5185)
    local pct = FindEntry(book, 90020)
    local free = FindEntry(book, 90030)

    local amountGood = htR1.costState == "ok" and htR1.cost.amount == 25 and htR1.cost.percent == nil
    local pctGood = pct.costState == "ok" and pct.cost.percent == 5 and pct.cost.amount == nil
    local freeGood = free.costState == "free" and free.cost.free == true

    -- "unknown": both the cost-list function and the tooltip fallback absent
    -- for a whole scan -- Book must answer absent rather than inventing a cost.
    local bookNoCost = FreshBook(function()
        local savedCost, savedTip = C_Spell.GetSpellPowerCost, C_TooltipInfo.GetSpellByID
        C_Spell.GetSpellPowerCost = nil
        C_TooltipInfo.GetSpellByID = nil
        return function() C_Spell.GetSpellPowerCost, C_TooltipInfo.GetSpellByID = savedCost, savedTip end
    end)
    local unknownEntry = FindEntry(bookNoCost, 5185)
    local unknownGood = unknownEntry.costState == "absent" and unknownEntry.cost == nil

    check("cost is an amount, a percentage of base mana, free or unknown",
        amountGood and pctGood and freeGood and unknownGood,
        string.format("amount=%s pct=%s free=%s unknown=%s",
            tostring(amountGood), tostring(pctGood), tostring(freeGood), tostring(unknownGood)))
end

--------------------------------------------------------------------------------
-- 6: per mana, per second and casts to OOM follow the rules
--------------------------------------------------------------------------------
do
    local book = Book:Scan()
    local pool = { max = 200, regenCasting = 10 }
    Book:Rows(FindFamily(book, "Healing Touch"), pool)
    Book:Rows(FindFamily(book, "Rejuvenation"), pool)

    local htR1, htR2 = FindEntry(book, 5185), FindEntry(book, 90002)
    local rejuv = FindEntry(book, 774)

    -- Healing Touch R1: (40+55)/2 = 47.5 heal / 25 mana; interval = max(1.5
    -- cast, 1.5 GCD) = 1.5. net = 25 - 10*1.5 = 10; floor((200-25)/10)+1 = 18.
    local r1Good = ApproxEq(htR1.value, 47.5) and ApproxEq(htR1.perMana, 47.5 / 25)
        and ApproxEq(htR1.perSec, 47.5 / 1.5) and htR1.casts == 18

    -- Healing Touch R2: (90+110)/2 = 100 / 50 mana; interval = max(2.0, 1.5) = 2.0.
    -- net = 50 - 10*2 = 30; floor((200-50)/30)+1 = 6.
    local r2Good = ApproxEq(htR2.value, 100) and ApproxEq(htR2.perMana, 2.0)
        and ApproxEq(htR2.perSec, 50) and htR2.casts == 6

    -- Rejuvenation R1: a pure over-time part (over=32, dur=12, no min/max) ->
    -- interval = dur = 12. net = 25 - 10*12 = -95 <= 0 -> casts = inf.
    local rejuvGood = ApproxEq(rejuv.value, 32) and ApproxEq(rejuv.perMana, 32 / 25)
        and ApproxEq(rejuv.perSec, 32 / 12) and rejuv.casts == math.huge

    check("per mana, per second and casts to OOM follow the rules",
        r1Good and r2Good and rejuvGood,
        string.format("htR1(perMana=%s perSec=%s casts=%s) htR2(perMana=%s perSec=%s casts=%s) rejuv(perMana=%s perSec=%s casts=%s)",
            tostring(htR1.perMana), tostring(htR1.perSec), tostring(htR1.casts),
            tostring(htR2.perMana), tostring(htR2.perSec), tostring(htR2.casts),
            tostring(rejuv.perMana), tostring(rejuv.perSec), tostring(rejuv.casts)))
end

--------------------------------------------------------------------------------
-- 7: the dominated and the suggested rank follow the TBC rule
--------------------------------------------------------------------------------
do
    local book = Book:Scan()
    local pool = { max = 200, regenCasting = 10 }
    local htFam = FindFamily(book, "Healing Touch")
    local subFam = FindFamily(book, "SubFamily")
    Book:Rows(htFam, pool)
    Book:Rows(subFam, pool)

    local htR1, htR2 = FindEntry(book, 5185), FindEntry(book, 90002)
    local subR1, subR2 = FindEntry(book, 90070), FindEntry(book, 90071)

    -- Healing Touch: R2 beats R1 on both axes -> R1 dominated, max rank (R2) suggested.
    local maxSuggestedGood = htR1.dominated == true and htR2.suggested == true and htFam.suggested == htR2

    -- SubFamily: neither dominates, but R1's 10 HPM beats R2's 2 HPM and R1's
    -- value (200) is still >= 40% of R2's (500) -> R1 suggested, not the max rank.
    local notMaxSuggestedGood = subR1.dominated ~= true and subR2.dominated ~= true
        and subR1.suggested == true and subR2.suggested ~= true and subFam.suggested == subR1

    check("the dominated and the suggested rank follow the TBC rule",
        maxSuggestedGood and notMaxSuggestedGood,
        string.format("ht: R1.dominated=%s R2.suggested=%s | sub: R1.suggested=%s R2.suggested=%s",
            tostring(htR1.dominated), tostring(htR2.suggested), tostring(subR1.suggested), tostring(subR2.suggested)))
end

--------------------------------------------------------------------------------
-- 8: a description secret in combat keeps the last value read, marked stale
--------------------------------------------------------------------------------
do
    S.inCombat = false
    local before = Book:Scan()
    local goodBefore = FindEntry(before, 5185).descState == "ok" and not FindEntry(before, 5185).stale

    S.inCombat = true
    local during = Book:Scan()
    S.inCombat = false
    local e = FindEntry(during, 5185)
    local goodDuring = e.descState == "secret" and e.stale == true
        and e.desc == FindEntry(before, 5185).desc

    check("a description secret in combat keeps the last value read, marked stale",
        goodBefore and goodDuring,
        string.format("before.descState=%s during.descState=%s during.stale=%s",
            tostring(FindEntry(before, 5185).descState), tostring(e.descState), tostring(e.stale)))
end

--------------------------------------------------------------------------------
-- 9: a raising row, a secret or an absent function never breaks the scan
--------------------------------------------------------------------------------
-- T7a's own slot-4 fixture (a table whose __index raises on every field) is
-- built for Client/Probe.lua's own direct, named-field reads under pcall --
-- Lua 5.1's pairs()/next() never invoke __index (verified: a table with no
-- raw keys yields zero iterations, no raise), so a generic, shape-agnostic
-- Copy() genuinely cannot discover or trip that trap; the row copies to {},
-- has no numeric spellID, and is silently skipped (never counted) exactly
-- like any other shape-invalid row. Reported in this task's Report. What
-- Book's OWN read path can and does route to read.errors/read.secret is a
-- call that answers "error"/"secret" through the adapter itself, which this
-- item tests directly: the book row FUNCTION raising, and (item 12 covers a
-- genuinely secret table) a function going missing entirely.
do
    local okScan, book = pcall(function() return Book:Scan() end)

    local bookRaisingRow = FreshBook(function()
        local saved = C_SpellBook.GetSpellBookItemInfo
        C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
            if slot == 4 then error("spellbook row unreadable (stub)") end
            return saved(slot, bank)
        end
        return function() C_SpellBook.GetSpellBookItemInfo = saved end
    end)
    local errorsCounted = bookRaisingRow.read.errors >= 1

    -- Wrath's cast is 1500ms everywhere in the stub; with C_Spell.GetSpellInfo
    -- absent for the whole scan, Book must fall back to the tooltip data's
    -- own cast line instead.
    local bookNoInfo = FreshBook(function()
        local saved = C_Spell.GetSpellInfo
        C_Spell.GetSpellInfo = nil
        return function() C_Spell.GetSpellInfo = saved end
    end)
    local wrath = FindEntry(bookNoInfo, 5176)
    local fallbackGood = wrath ~= nil and wrath.cast == 1.5

    check("a raising row, a secret or an absent function never breaks the scan",
        okScan and errorsCounted and fallbackGood,
        string.format("okScan=%s errors=%s wrath.cast=%s",
            tostring(okScan), tostring(bookRaisingRow.read.errors), tostring(wrath and wrath.cast)))
end

--------------------------------------------------------------------------------
-- 10: a spell not yet learned is listed, not known
--------------------------------------------------------------------------------
do
    local book = Book:Scan()
    local e = FindEntry(book, 90050)
    check("a spell not yet learned is listed, not known",
        e ~= nil and e.known == false, e and tostring(e.known) or "not listed")
end

--------------------------------------------------------------------------------
-- 11: the talent seam is empty and applies what is put in it
--------------------------------------------------------------------------------
do
    local emptyGood = type(Book.adjust) == "table" and #Book.adjust == 0

    table.insert(Book.adjust, function(entry, family)
        if entry.id == 5185 then entry.talentSeamTouched = true end
    end)
    local book = Book:Scan()
    table.remove(Book.adjust)

    local applied = FindEntry(book, 5185).talentSeamTouched == true
    local emptyAfter = #Book.adjust == 0

    check("the talent seam is empty and applies what is put in it",
        emptyGood and applied and emptyAfter,
        string.format("emptyGood=%s applied=%s emptyAfter=%s", tostring(emptyGood), tostring(applied), tostring(emptyAfter)))
end

--------------------------------------------------------------------------------
-- 12: nothing the book hands out is secret
--------------------------------------------------------------------------------
do
    local function IsSecretAny(v)
        local sv = (type(issecretvalue) == "function") and select(2, pcall(issecretvalue, v)) or false
        local st = (type(issecrettable) == "function") and select(2, pcall(issecrettable, v)) or false
        return sv == true or st == true
    end
    local function Walk(v, seen, bad)
        if IsSecretAny(v) then bad.n = bad.n + 1; return end
        if type(v) == "table" then
            if seen[v] then return end
            seen[v] = true
            for k, val in pairs(v) do
                if IsSecretAny(k) then bad.n = bad.n + 1 end
                Walk(val, seen, bad)
            end
        end
    end

    S.inCombat = false
    local bookOut = Book:Scan()
    S.inCombat = true
    local bookIn = Book:Scan()
    S.inCombat = false

    local bad = { n = 0 }
    Walk(bookOut, {}, bad)
    Walk(bookIn, {}, bad)

    check("nothing the book hands out is secret", bad.n == 0, "secret values found: " .. bad.n)
end

--------------------------------------------------------------------------------
-- 13: the scan is cached until the book changes or two seconds pass
--------------------------------------------------------------------------------
do
    Book:MarkDirty()
    S.now = 100
    local first = Book:Get()

    S.now = 101
    local stillCached = Book:Get()

    S.now = 102.1
    local rescanned = Book:Get()

    S.now = 102.2
    Book:MarkDirty()
    local dirtyForces = Book:Get()

    check("the scan is cached until the book changes or two seconds pass",
        first == stillCached and rescanned ~= first and dirtyForces ~= rescanned,
        string.format("first==stillCached=%s rescanned~=first=%s dirtyForces~=rescanned=%s",
            tostring(first == stillCached), tostring(rescanned ~= first), tostring(dirtyForces ~= rescanned)))
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
