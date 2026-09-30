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
    { cast = 0, noCost = true, level = 1, passive = true })

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

--------------------------------------------------------------------------------
-- 14 (T9): ReadSpell reads a spell by id alone -- in the book or not, no
-- family, no row number a family or a mana pool would supply
--------------------------------------------------------------------------------
do
    -- 5185 is one of T7a's fixed slots, so ReadSpell's own id-only path must
    -- agree with what the family-aware scan already found for it.
    local book = Book:Scan()
    local viaBook = FindEntry(book, 5185)
    local viaRead = Book:ReadSpell(5185)
    local sameGood = viaRead ~= nil and viaRead.name == "Healing Touch" and viaRead.rank == 1
        and ApproxEq(viaRead.value, 47.5) and ApproxEq(viaRead.cost.amount, 25)
        and viaRead.cast == 1.5 and viaRead.casts == nil
        and viaRead.value == viaBook.value

    -- 90060 is the flyout fixture from item 9 -- Book:Scan() never lists it
    -- (a row the book walk itself skips), but its id-keyed client calls still
    -- answer, which is exactly what a chat link needs.
    local notInBook = FindEntry(book, 90060) == nil
    local standalone = Book:ReadSpell(90060)
    local standaloneGood = notInBook and standalone ~= nil and standalone.name == "FlyoutThing"
        and standalone.value ~= nil

    -- an id nothing answers a name for (no such spell) is nil, not a guess.
    local nothingGood = Book:ReadSpell(999999) == nil

    check("ReadSpell reads a spell by id alone, in the book or not, with no row number",
        sameGood and standaloneGood and nothingGood,
        string.format("sameGood=%s standaloneGood=%s nothingGood=%s",
            tostring(sameGood), tostring(standaloneGood), tostring(nothingGood)))
end

--------------------------------------------------------------------------------
-- 15 (T7b, == shapes item 5/3): a spell whose cost call returns nothing is
-- free, and a passive row is marked passive
--------------------------------------------------------------------------------
do
    local book = Book:Scan()
    local free = FindEntry(book, 90030)
    local passive = FindEntry(book, 90040)
    local fixed = FindEntry(book, 5185)

    local freeGood = free.costState == "free"
    local passiveGood = passive.passive == true
    local fixedGood = fixed.passive == false

    check("a spell whose cost call returns nothing is free, and a passive row is marked passive",
        freeGood and passiveGood and fixedGood,
        string.format("free.costState=%s passive.passive=%s fixed.passive=%s",
            tostring(free.costState), tostring(passive.passive), tostring(fixed.passive)))
end

--------------------------------------------------------------------------------
-- 16 (review R13): a Rage or Energy cost is not a mana cost -- the spell
-- costs no mana (free, as far as the pool goes), keeps what it does cost,
-- and gets no per-mana or casts-to-OOM number; from the cost list and from
-- the tooltip's own cost line alike. Texts and cost lines: talentsforever's
-- beta client 1.60.1.70009 (Rend: "10 Rage"; Claw: "45 Energy").
--------------------------------------------------------------------------------
S.AddSpell(90080, "Rend", "Rank 1",
    function() return "Wounds the target causing them to bleed for 15 damage over 9 sec." end,
    { cast = 0, level = 4, costLine = "10 Rage",
      costList = { { type = 1, name = "RAGE", cost = 10, minCost = 10, costPercent = 0, costPerSec = 0,
                     requiredAuraID = 0, hasRequiredAura = false } } })
S.AddSpell(90081, "Claw", "Rank 1",
    function() return "Claw the enemy for 110% normal damage plus 29. Awards 1 combo point." end,
    { cast = 0, level = 20, costLine = "45 Energy",
      costList = { { type = 3, name = "ENERGY", cost = 45, minCost = 45, costPercent = 0, costPerSec = 0,
                     requiredAuraID = 0, hasRequiredAura = false } } })
do
    local function NoMana(e, power, amount)
        return e ~= nil and e.costState == "free" and type(e.cost) == "table" and e.cost.amount == nil
            and e.cost.percent == nil and e.cost.power == power and e.cost.powerAmount == amount
    end
    local function Show(e)
        if not e then return "nil" end
        return string.format("%s amount=%s power=%s powerAmount=%s perMana=%s casts=%s", tostring(e.costState),
            tostring(e.cost and e.cost.amount), tostring(e.cost and e.cost.power),
            tostring(e.cost and e.cost.powerAmount), tostring(e.perMana), tostring(e.casts))
    end

    local book = Book:Scan()
    Book:Rows(FindFamily(book, "Rend"), { max = 200, regenCasting = 10 })
    local rend, claw = FindEntry(book, 90080), FindEntry(book, 90081)
    local listGood = NoMana(rend, "Rage", 10) and NoMana(claw, "Energy", 45)
        and FindFamily(book, "Rend").kind == "damage" and rend.perMana == nil and rend.casts == nil

    -- the cost list absent for the whole scan: the tooltip's "10 Rage" line
    -- is all there is, and it is not mana either.
    local bookTip = FreshBook(function()
        local saved = C_Spell.GetSpellPowerCost
        C_Spell.GetSpellPowerCost = nil
        return function() C_Spell.GetSpellPowerCost = saved end
    end)
    local rendTip, clawTip = FindEntry(bookTip, 90080), FindEntry(bookTip, 90081)
    local tipGood = NoMana(rendTip, "Rage", 10) and NoMana(clawTip, "Energy", 45)
        and FindEntry(bookTip, 5185).cost.amount == 25 -- a "25 Mana" line still is mana

    local read = Book:ReadSpell(90080)
    local readGood = NoMana(read, "Rage", 10) and read.perMana == nil

    check("a Rage or Energy cost is not a mana cost",
        listGood and tipGood and readGood,
        string.format("list: rend %s | claw %s; tooltip: rend %s; ReadSpell: %s",
            Show(rend), Show(claw), Show(rendTip), Show(read)))
end

--------------------------------------------------------------------------------
-- 17 (review R41): a description secret for several rescans in a row keeps
-- the last value read on every one of them, not only the first
--------------------------------------------------------------------------------
do
    S.inCombat = false
    local before = FindEntry(Book:Scan(), 5185)
    S.inCombat = true
    local first = FindEntry(Book:Scan(), 5185)
    local second = FindEntry(Book:Scan(), 5185)
    local third = FindEntry(Book:Scan(), 5185)
    S.inCombat = false
    local after = FindEntry(Book:Scan(), 5185)

    local function Kept(e)
        return e.descState == "secret" and e.stale == true and e.desc == before.desc
            and type(e.parsed) == "table" and e.parsed == before.parsed and ApproxEq(e.value, before.value)
    end
    check("a description secret for several rescans keeps the last value read on each",
        Kept(first) and Kept(second) and Kept(third)
        and after.descState == "ok" and not after.stale,
        string.format("stale %s/%s/%s value %s/%s/%s (before %s), after %s",
            tostring(first.stale), tostring(second.stale), tostring(third.stale),
            tostring(first.value), tostring(second.value), tostring(third.value), tostring(before.value),
            tostring(after.descState)))
end

--------------------------------------------------------------------------------
-- T38 (docs/SPEC-forever-ui.md 3.5, docs/tasks/T38-one-spell-view.md): what a
-- family's own view reads off the book -- Book:Compare(a, b) for the decision
-- strip's one factual line, family.shape for the header's words, and
-- entry.dominatedBy for a dominated rank. The fixtures are added here, last,
-- so no item above sees them. Texts: the probe's Moonfire R1, talentsforever's
-- Tranquility R4 and Power Word: Shield R1 (tools/data/parse-fixture.lua).
--------------------------------------------------------------------------------
S.AddSpell(90090, "HybridSpell", "Rank 1",
    function() return "Burns the enemy for 9 to 12 Arcane damage and then an additional 12 Arcane damage over 9 sec." end,
    { cast = 1500, cost = 25, level = 4 })
S.AddSpell(90091, "TickSpell", "Rank 1",
    function() return "Regenerates all nearby party members within 20 yards for 285 every 2 sec for 10 sec. Druid must channel to maintain the spell." end,
    { cast = 0, cost = 300, level = 30 })
S.AddSpell(90092, "ShieldSpell", "Rank 1",
    function() return "Draws on the soul of the party member to shield them, absorbing 48 damage. Lasts 30 sec." end,
    { cast = 0, cost = 45, level = 6 })
Book:MarkDirty()

local function T38(name, fn)
    local good, cond, detail = pcall(fn)
    if not good then check(name, false, "raised: " .. tostring(cond)) return end
    check(name, cond == true, detail)
end

-- 18: Compare's numbers for Healing Touch R1 against R2 (5185: 40-55 for 25
-- mana, a 1.5 s cast; 90002: 90-110 for 50, a 2.0 s cast): R1 heals 47.5 at
-- 1.90 per mana and 31.7 per second, R2 100 at 2.00 and 50.
T38("Compare: Healing Touch R1 against R2, in percent", function()
    local book = Book:Get()
    local c = Book:Compare(FindEntry(book, 5185), FindEntry(book, 90002))
    local good = type(c) == "table" and ApproxEq(c.perMana, -5, 1e-6) and ApproxEq(c.value, 47.5, 1e-6)
        and ApproxEq(c.cast, -25, 1e-6) and ApproxEq(c.perSec, (47.5 / 1.5 / 50 - 1) * 100, 1e-6)
    return good, c and string.format("perMana=%s value=%s cast=%s perSec=%s", tostring(c.perMana),
        tostring(c.value), tostring(c.cast), tostring(c.perSec)) or "no answer"
end)

-- 19: a side that lacks a number leaves that number nil (never 0), a cast
-- compared only between two timed casts, and anything but two entries nil
T38("Compare leaves out what either side lacks, and never raises", function()
    local book = Book:Get()
    local ht1, rj1, rj2 = FindEntry(book, 5185), FindEntry(book, 774), FindEntry(book, 1058)
    local noValue = { rank = 3, known = true, cast = 0, castKind = "instant" } -- no value, no per mana
    local a = Book:Compare(rj1, rj2)   -- two instant HoTs: no cast clause
    local b = Book:Compare(ht1, noValue)
    local good = a ~= nil and ApproxEq(a.value, 32 / 56 * 100, 1e-6) and a.cast == nil
        and b ~= nil and b.value == nil and b.perMana == nil and b.cast == nil
        and Book:Compare(nil, ht1) == nil and Book:Compare(ht1, "x") == nil
    return good, string.format("rj value=%s cast=%s; noValue value=%s perMana=%s", tostring(a and a.value),
        tostring(a and a.cast), tostring(b and b.value), tostring(b and b.perMana))
end)

-- 20: every family's shape, from its own text
T38("shape per family: direct, hot, hybrid, none", function()
    local book = Book:Get()
    local want = {
        ["Healing Touch"] = "direct", ["Wrath"] = "direct", ["Rejuvenation"] = "hot",
        ["TickSpell"] = "hot", ["HybridSpell"] = "hybrid", ["ShieldSpell"] = "direct",
        ["PassiveSpell"] = "none",
    }
    local bad = {}
    for name, shape in pairs(want) do
        local fam = FindFamily(book, name)
        if not fam or fam.shape ~= shape then
            bad[#bad + 1] = name .. "=" .. tostring(fam and fam.shape)
        end
    end
    table.sort(bad)
    return #bad == 0, #bad == 0 and "all seven" or table.concat(bad, ", ")
end)

-- 21: a dominated rank names the rank that beats it (by id, a plain number);
-- a rank nothing beats names none
T38("dominatedBy names the rank that beats a dominated one", function()
    local book = Book:Get()
    local ht1, ht2 = FindEntry(book, 5185), FindEntry(book, 90002)
    local rj1, rj2 = FindEntry(book, 774), FindEntry(book, 1058)
    local sub1, sub2 = FindEntry(book, 90070), FindEntry(book, 90071)
    local good = ht1.dominatedBy == 90002 and ht2.dominatedBy == nil
        and rj1.dominatedBy == 1058 and rj2.dominatedBy == nil
        and sub1.dominatedBy == nil and sub2.dominatedBy == nil
    return good, string.format("ht1=%s rj1=%s ht2=%s sub=%s/%s", tostring(ht1.dominatedBy),
        tostring(rj1.dominatedBy), tostring(ht2.dominatedBy), tostring(sub1.dominatedBy), tostring(sub2.dominatedBy))
end)

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
