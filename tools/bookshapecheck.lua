-- tools/run.sh [--flavour forever|tbc] tools/bookshapecheck.lua [--print | --golden]
--
-- T117 (docs/SPEC-one-ui.md 3.1, 4.3; docs/tasks/T117-book-contract.md): the
-- book contract and the +healing rules, once.
--
-- Under forever (10 checks):
--   1. Spells/BookShape.lua, Spells/Coefficients.lua and Spells/Words.lua load;
--      the stub's druid book passes BookShape.Validate, then each of
--      tools/stub_books.lua's priest, shaman and paladin books, alone and beside
--      the druid's;
--   2. an undeclared field, a wrong type, an `ids` entry missing from `spells`
--      and a variant row placed in `spells` are each refused, naming the id and
--      the field;
--   3. every entry names its family (`family == name`, families[e.family] holds
--      it);
--   4. the estimated +healing share (Coefficients.Estimate, no downrank): Healing
--      Touch Rank 1 by cast / 3.5 x the sub-20 factor, Rejuvenation by its
--      duration / 15; a free spell and an Other spell carry none;
--   5. `calc` is the one line "read from the spell's text" on a valued entry;
--   6. Book:Bonus("heal"): plain out of combat, the last plain reading (stale) in
--      combat or when secret, nil before any; "damage" nil;
--   7. Book:Pool(): the clock's modelled pool, else DefaultPool with mana = max;
--   8. a +healing reading moving with the text unchanged leaves the generation;
--   9. BookShape.CheckMethods passes on the book and names a missing method;
--  10. Words.Bonus in its three styles over the three sources, Words.Signed.
--
-- Under tbc (18 checks):
--  11. the three files load from the TBC TOC; Words.GCD is 1.5;
--  12. THE GOLDEN: every row of RankMath:Compute() (the druid at levels 40, 64
--      and 70; live, Tree of Life off and on; every Lifebloom variant), every
--      RankMath:Explain, the druid's SpellKit and DamageMath.Compute for every
--      druid damage rank of the fixture below, serialised with %.17g. Captured
--      with --golden on the parent (e93d367) before the first edit; equal byte
--      for byte after (two independent 32-bit polynomial hashes, the line
--      count and the byte count of the transcript; --print writes the whole
--      transcript, for a diff when it fails);
--  13. the same for a priest's, a shaman's and a paladin's rows (ClassRow) and
--      kits, from tools/tbcclasscheck.lua's fixture, the caps granted in the
--      suite as tbcclasscheck grants them;
--  14. the coefficient literals live in Spells/Coefficients.lua only: neither
--      Engine/RankMath.lua nor Engine/DamageMath.lua carries `/ 3.5`, `/ 15`,
--      `0.0375` or `GROUP_COEF = <number>` outside a comment.
--
-- T118 (docs/tasks/T118-tbc-book.md): TBC's MD.Book, Spells/Book_Model.lua.
--  15. MD.Book exists on TBC, CheckMethods passes, Get() passes Validate at
--      levels 40, 64 and 70, caster and Tree of Life;
--  16. every heal entry equals its RankMath:Compute({ live = true }) row (value,
--      per mana, per second, casts, cost, cast, known, suggested, dominated),
--      Lifebloom's x2 / x3 rows as the entry's variants;
--  17. with overheal seeded, afterOverheal is the row's effHeal / effHpm /
--      effHps, frac and scope; without, nil;
--  18. bonus from the model: Healing Touch 12 at +700 with Empowered Touch 2
--      counts 1.2 of 700 = 840 "x1.20 Empowered Touch"; a downranked rank and
--      a sub-20 rank name their factors;
--  19. calc is Tip:Spell(id, true)'s Shift lines, plain (direct, HoT, hybrid,
--      Lifebloom, a downranked rank, Tree of Life) -- T121: Tip:Spell is
--      deleted, so the comparison is with its lines captured on d6691fe at
--      +450 healing (CALC_GOLDEN), no longer a live call;
--  20. Tranquility and Swiftmend are noSeed heal families with no value;
--      Swiftmend's calc is its two Eats lines (T121: the golden captured on
--      d6691fe from Tip:Spell(18562, true));
--  21. a druid's walked Wrath and Moonfire are damage families whose entries
--      are DamageMath.Compute's expected / dpm / dps, the suggested rank
--      RankRules', the bonus's why ending VERIFY;
--  22. Other: a costed spell no family claims (Innervate, Mark of the Wild by
--      rank); a passive and a free spell are not listed;
--  23. Get() ignores MD.sim; Get({ whatIf = true }) is Compute() under it,
--      uncached, with no BOOK_CHANGED and the generation still; SuggestedRanks
--      is live under a what-if that moves a suggested rank, and leaves
--      RankMath.info (the last Compute's context) where it was;
--  24. a gear change that moves a value fires BOOK_CHANGED once and bumps the
--      generation; an unchanged rebuild (the same gear, TALENTS_CHANGED, a
--      party member's gear) does neither;
--  25. a priest without the rank table: Other only, valid;
--  26. T123: MD.FamiliesTBC (T118's alias) is nil;
--  27. T123: a priest's, a shaman's and a paladin's book (tools/tbcclasscheck.lua's
--      fixture with its damage rows) passes BookShape.Validate: the source's
--      heal families, then the profile's damage families in its damageOrder;
--  28. T123: the druid's MD.Book (levels 64 and 70, caster and Tree of Life,
--      the DAMAGE ranks and two Other spells walked) byte for byte as the
--      parent (49494eb) built it.
HARNESS_FLAVOUR = { "forever", "tbc" }
local here = arg[0]:match("^(.*)/[^/]+$")
local mode = "check"
for i = 2, #arg do
    if arg[i] == "--print" then mode = "print" elseif arg[i] == "--golden" then mode = "golden" end
end

local T = dofile(here .. "/lib/t.lua")
local function check(name, cond, detail)
    if cond or detail == "" then detail = nil end
    return T.check(name, cond, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0
local S = _G.STUB
local ROOT = S.root or "."

local function Show(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return tostring(v) end
    if depth > 2 then return "{...}" end
    local o = {}
    for k, x in pairs(v) do o[#o + 1] = tostring(k) .. "=" .. Show(x, depth + 1) end
    table.sort(o)
    return "{" .. table.concat(o, ",") .. "}"
end
local function Near(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-12) end
local function Has(list, needle)
    for _, s in ipairs(list or {}) do
        if type(s) == "string" and s:find(needle, 1, true) then return true end
    end
    return false
end
-- A step that raises is a failed step with its message, never a stopped suite.
local function Try(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return false, tostring(a) end
    return true, a, b, c
end

--------------------------------------------------------------------------------
-- FOREVER
--------------------------------------------------------------------------------
local function ForeverChecks()
    local BS, Coef, W, Book = MD.BookShape, MD.Coefficients, MD.Words, MD.Book

    -- 1 -----------------------------------------------------------------------
    T.section("1. the contract loads and every book passes it")
    do
        local ok, why = BS ~= nil and Coef ~= nil and W ~= nil, "MD.BookShape / MD.Coefficients / MD.Words missing"
        local notes = {}
        if ok then
            local function One(label)
                Book:MarkDirty()
                local okGet, book = Try(function() return Book:Get() end)
                if not okGet then return false, label .. ": Get raised " .. tostring(book) end
                local valid, problems = BS.Validate(book)
                local n = 0
                for _ in pairs(book.spells) do n = n + 1 end
                notes[#notes + 1] = string.format("%s: %d spells, %d families", label, n, #book.order)
                if not valid then return false, label .. ": " .. table.concat(problems or {}, "; ") end
                if n == 0 then return false, label .. ": an empty book" end
                return true
            end
            ok, why = One("druid")
            local Books = dofile(here .. "/stub_books.lua")
            for _, class in ipairs({ "priest", "shaman", "paladin" }) do
                for _, alone in ipairs({ true, false }) do
                    if ok then
                        local restore = Books.Install(Books.Load(class), { alone = alone, MD = MD })
                        ok, why = One(class .. (alone and " alone" or " beside the druid"))
                        restore()
                        if MD.API.Invalidate then MD.API.Invalidate() end
                    end
                end
            end
            Book:MarkDirty()
            Book:Get()
        end
        for _, n in ipairs(notes) do print("    " .. n) end
        check("1. BookShape, Coefficients and Words load; the druid's and three class books pass Validate",
            ok, why)
    end

    -- the free spell and the Other spell checks 4 and 5 read
    S.AddSpell(768, "Cat Form", nil, function() return "Shapeshift into cat form." end, { noCost = true, level = 20 })
    S.AddSpell(1126, "Mark of the Wild", "Rank 1",
        function() return "Increases the friendly target's armor by 25 for 30 min." end, { cost = 20, level = 1 })
    if Book then Book:MarkDirty() end

    -- 2 -----------------------------------------------------------------------
    T.section("2. what Validate refuses")
    do
        local ok, why = BS ~= nil, "no MD.BookShape"
        if ok then
            -- a deep copy (shared references kept shared), mutated, never the live book
            local function Copy(v, memo)
                if type(v) ~= "table" then return v end
                memo = memo or {}
                if memo[v] then return memo[v] end
                local out = {}
                memo[v] = out
                for k, x in pairs(v) do out[Copy(k, memo)] = Copy(x, memo) end
                return out
            end
            local live = Book:Get()
            local cases = {
                { "an undeclared field", function(b) b.spells[5185].bogusField = 1 end, { "5185", "bogusField" } },
                { "a wrong type", function(b) b.spells[5185].rank = "one" end, { "5185", "rank" } },
                { "an id missing from spells", function(b)
                    local fam = b.families[b.spells[5185].family or "Healing Touch"]
                    fam.ids[#fam.ids + 1] = 999999
                end, { "999999", "Healing Touch" } },
                { "a variant row in spells", function(b)
                    local row = { variant = 2, variantLabel = "x2", value = 10 }
                    b.spells[774].variants = { row }
                    b.spells[777777] = row
                end, { "777777", "variant" } },
            }
            for _, c in ipairs(cases) do
                local b = Copy(live)
                c[2](b)
                local valid, problems = BS.Validate(b)
                local named = not valid
                for _, needle in ipairs(c[3]) do
                    if not Has(problems, needle) then named = false end
                end
                print(string.format("    %-28s %s", c[1], table.concat(problems or { "(accepted)" }, "; ")))
                if not named then ok, why = false, c[1] .. ": " .. Show(problems) end
            end
            -- Check raises with its caller's name
            local b = Copy(live)
            b.spells[5185].bogusField = 1
            local raised, err = pcall(BS.Check, b, "the suite")
            if raised or not tostring(err):find("the suite", 1, true) then
                ok, why = false, "Check did not raise naming its caller: " .. tostring(err)
            end
            -- the live book still passes (the copies were the ones changed)
            if not BS.Validate(live) then ok, why = false, "the live book was changed" end
        end
        check("2. an undeclared field, a wrong type, a missing id and a variant in spells are refused by name",
            ok, why)
    end

    -- 3 -----------------------------------------------------------------------
    T.section("3. every entry names its family")
    do
        local ok, why = Book ~= nil, "no book"
        local n = 0
        if ok then
            local book = Book:Get()
            for id, e in pairs(book.spells) do
                local fam = e.family and book.families[e.family]
                local inFam = false
                for _, r in ipairs(fam and fam.ranks or {}) do if r == e then inFam = true end end
                if e.family ~= e.name or not inFam then
                    ok, why = false, string.format("%d: family %s, name %s, in its family %s", id,
                        tostring(e.family), tostring(e.name), tostring(inFam))
                end
                n = n + 1
            end
            local rs = Book:ReadSpell(5185)
            if not rs or rs.family ~= "Healing Touch" then ok, why = false, "ReadSpell(5185).family " .. tostring(rs and rs.family) end
        end
        check("3. family == name on every entry (" .. n .. "), and families[e.family] holds it", ok, why)
    end

    -- 4 -----------------------------------------------------------------------
    T.section("4. the estimated +healing share")
    do
        local ok, why = Book ~= nil and Coef ~= nil, "no book or no Coefficients"
        if ok then
            local book = Book:Get()
            local ht, rj = book.spells[5185], book.spells[774]
            local htB, rjB = ht and ht.bonus, rj and rj.bonus
            print("    Healing Touch 1: " .. Show(htB))
            print("    Rejuvenation 1:  " .. Show(rjB))
            local htWant = 1.5 / 3.5 * (1 - (20 - 1) * 0.0375)
            local rjWant = 12 / 15 * (1 - (20 - 4) * 0.0375)
            if not (htB and Near(htB.counts, htWant) and htB.from == "estimated"
                and htB.why == "cast 1.5 / 3.5 x 0.29") then
                ok, why = false, "Healing Touch: " .. Show(htB) .. " want counts " .. htWant
            elseif not (rjB and Near(rjB.counts, rjWant) and rjB.from == "estimated"
                and rjB.why == "over 12 s / 15 x 0.40") then
                ok, why = false, "Rejuvenation: " .. Show(rjB) .. " want counts " .. rjWant
            elseif not (type(htB.of) == "number" and Near(htB.amount, htB.counts * htB.of)) then
                ok, why = false, "Healing Touch's amount is not counts x the bonus: " .. Show(htB)
            elseif book.spells[768] == nil or book.spells[768].bonus ~= nil then
                ok, why = false, "the free spell: " .. Show(book.spells[768] and book.spells[768].bonus)
            elseif book.spells[1126] == nil or book.spells[1126].bonus ~= nil then
                ok, why = false, "the Other spell: " .. Show(book.spells[1126] and book.spells[1126].bonus)
            elseif Coef.Estimate({ level = 70 }, "none") ~= nil then
                ok, why = false, "a shape with no rule gave a share"
            end
            local none, reason = Coef.Estimate({ level = 70 }, "none")
            print("    no rule: " .. tostring(none) .. ", " .. tostring(reason))
            if ok and reason ~= "no rule for none" then ok, why = false, "the reason: " .. tostring(reason) end
        end
        check("4. Healing Touch 1 by cast / 3.5 x 0.29, Rejuvenation by 12 / 15; a free and an Other spell carry none",
            ok, why)
    end

    -- 5 -----------------------------------------------------------------------
    T.section("5. calc")
    do
        local ok, why = Book ~= nil, "no book"
        local valued, plain = 0, 0
        if ok then
            for id, e in pairs(Book:Get().spells) do
                if e.value ~= nil then
                    valued = valued + 1
                    if not (type(e.calc) == "table" and #e.calc == 1 and e.calc[1] == "read from the spell's text") then
                        ok, why = false, id .. ": " .. Show(e.calc)
                    end
                else
                    plain = plain + 1
                    if e.calc ~= nil then ok, why = false, id .. " has no value but a calc" end
                end
            end
        end
        check(string.format("5. calc on the %d valued entries, none on the other %d", valued, plain),
            ok and valued > 0 and plain > 0, why)
    end

    -- 6 -----------------------------------------------------------------------
    T.section("6. Book:Bonus")
    do
        local ok, why = Book ~= nil and type(Book.Bonus) == "function", "no Book:Bonus"
        if ok then
            local savedB, savedSecret, savedIn, savedS = S.bonusHealing, S.bonusHealingSecretInCombat, MD.inCombat, S.inCombat
            local steps = {}
            local function Step(label, wantA, wantStale, fn)
                fn()
                local a, stale = Book:Bonus("heal")
                steps[#steps + 1] = string.format("%s -> %s, %s", label, tostring(a), tostring(stale))
                if a ~= wantA or (wantA ~= nil and (stale == true) ~= wantStale) then
                    ok, why = false, label .. ": " .. tostring(a) .. ", " .. tostring(stale)
                end
            end
            Book._lastBonus = nil
            Step("before any reading, in combat", nil, nil, function() MD.inCombat = true end)
            Step("out of combat, 120", 120, false, function() MD.inCombat = false; S.bonusHealing = 120 end)
            Step("in combat, the gear says 300", 120, true, function() MD.inCombat = true; S.bonusHealing = 300 end)
            Step("out of combat, the read secret", 120, true, function()
                MD.inCombat = false; S.inCombat = true; S.bonusHealingSecretInCombat = true
            end)
            Step("out of combat, plain again", 300, false, function()
                S.inCombat = false; S.bonusHealingSecretInCombat = false
            end)
            local d = Book:Bonus("damage", "Nature")
            steps[#steps + 1] = "damage -> " .. tostring(d)
            if d ~= nil then ok, why = false, "damage answered " .. tostring(d) end
            for _, s in ipairs(steps) do print("    " .. s) end
            S.bonusHealing, S.bonusHealingSecretInCombat, MD.inCombat, S.inCombat = savedB, savedSecret, savedIn, savedS
            Book:Bonus("heal")
        end
        check("6. Bonus: plain out of combat, the last plain one stale in combat or secret, nil before any", ok, why)
    end

    -- 7 -----------------------------------------------------------------------
    T.section("7. Book:Pool")
    do
        local ok, why = Book ~= nil and type(Book.Pool) == "function", "no Book:Pool"
        if ok then
            local clock = MD.Clock and MD.Clock:Pool() or {}
            local p = Book:Pool()
            print("    with the clock: " .. Show(p) .. " (the clock " .. Show(clock) .. ")")
            if not (p.modelled == true and type(clock.max) == "number" and p.max == clock.max
                and p.mana == clock.mana and p.regenCasting == clock.regenCasting) then
                ok, why = false, "with the clock: " .. Show(p)
            end
            local savedClock = MD.Clock
            MD.Clock = nil
            local q = Book:Pool()
            local d = Book:DefaultPool()
            MD.Clock = savedClock
            print("    without:        " .. Show(q))
            if ok and not (q.modelled == false and q.max == d.max and q.mana == d.max
                and q.regenCasting == d.regenCasting and type(q.max) == "number") then
                ok, why = false, "without the clock: " .. Show(q)
            end
        end
        check("7. Pool: the clock's modelled pool, else DefaultPool with mana = max", ok, why)
    end

    -- 8 -----------------------------------------------------------------------
    T.section("8. the generation")
    do
        local ok, why = Book ~= nil, "no book"
        if ok then
            local savedB, savedShift = S.bonusHealing, S.descShift
            Book:MarkDirty()
            local b0 = Book:Get()
            local gen0 = Book.generation
            local amount0 = b0.spells[5185] and b0.spells[5185].bonus and b0.spells[5185].bonus.amount
            -- +100 healing; Rejuvenation 1's text (32 + bonus + shift) held where it was
            S.bonusHealing = savedB + 100
            S.descShift = savedShift - 100
            Book:MarkDirty()
            local b1 = Book:Get()
            local amount1 = b1.spells[5185] and b1.spells[5185].bonus and b1.spells[5185].bonus.amount
            print(string.format("    generation %s -> %s, Healing Touch's amount %s -> %s", tostring(gen0),
                tostring(Book.generation), tostring(amount0), tostring(amount1)))
            if Book.generation ~= gen0 then ok, why = false, "the generation moved" end
            if ok and not (type(amount0) == "number" and type(amount1) == "number" and amount1 > amount0) then
                ok, why = false, "the reading did not reach the entry"
            end
            -- the text moving still moves it
            S.descShift = savedShift
            Book:MarkDirty()
            Book:Get()
            if ok and Book.generation == gen0 then ok, why = false, "a text change did not move it" end
            S.bonusHealing = savedB
            Book:MarkDirty()
            Book:Get()
        end
        check("8. +healing moving with the text unchanged leaves Book.generation; the text moving moves it", ok, why)
    end

    -- 9 -----------------------------------------------------------------------
    T.section("9. the methods")
    do
        local ok, why = BS ~= nil and type(BS.CheckMethods) == "function", "no CheckMethods"
        if ok then
            local okAll, err = pcall(BS.CheckMethods, Book, "the suite")
            if not okAll then ok, why = false, "the book: " .. tostring(err) end
            local copy = {}
            for k, v in pairs(Book) do copy[k] = v end
            copy.Pool = nil
            local raised, err2 = pcall(BS.CheckMethods, copy, "the suite")
            print("    without Pool: " .. tostring(err2))
            if ok and (raised or not tostring(err2):find("Pool", 1, true)) then
                ok, why = false, "no raise naming Pool: " .. tostring(err2)
            end
            local names = table.concat(BS.METHODS or {}, " ")
            print("    METHODS: " .. names)
            for _, m in ipairs({ "Get", "Entry", "ReadSpell", "Rows", "CastsFor", "Compare", "DefaultPool",
                                 "Half", "HalfOf", "GCD", "IntervalFor", "Pool", "Bonus" }) do
                if ok and not (" " .. names .. " "):find(" " .. m .. " ", 1, true) then
                    ok, why = false, "METHODS lacks " .. m
                end
            end
        end
        check("9. CheckMethods passes on MD.Book; without Pool it raises naming it", ok, why)
    end

    -- 10 ----------------------------------------------------------------------
    T.section("10. Words.Bonus, Words.Signed")
    do
        local ok, why = W ~= nil and type(W.Bonus) == "function" and type(W.Signed) == "function",
            "no Words.Bonus / Signed"
        if ok then
            local at = os.time({ year = 2026, month = 10, day = 2, hour = 12 })
            local model = { bonus = { counts = 1.2, from = "model", amount = 840, of = 700, why = "x1.20 Empowered Touch" } }
            local est = { bonus = { counts = 0.12, from = "estimated", why = "cast 1.5 / 3.5 x 0.29" } }
            local meas = { bonus = { counts = 0.31, from = "measured", at = at } }
            local want = {
                { model, "card", "heal", "840 of your 700 (x1.20 Empowered Touch)" },
                { model, "how", "heal", "+Healing counts 120% (x1.20 Empowered Touch)" },
                { model, "tip", "heal", "120%" },
                { est, "card", "heal", "counts ~12% estimated (cast 1.5 / 3.5 x 0.29)" },
                { est, "how", "heal", "+Healing counts ~12%, estimated" },
                { est, "tip", "heal", "~12%" },
                { meas, "card", "heal", "31% measured: your gear change, 2 Oct" },
                { meas, "how", "heal", "+Healing counts 31%, measured 2 Oct" },
                { meas, "how", "damage", "+Damage counts 31%, measured 2 Oct" },
                { meas, "tip", "heal", "31%" },
            }
            for _, c in ipairs(want) do
                local okW, got = Try(W.Bonus, c[1], c[2], c[3])
                print(string.format("    %-10s %-5s %-7s %s", c[1].bonus.from, c[2], c[3], tostring(got)))
                if not okW or got ~= c[4] then
                    ok, why = false, string.format("%s %s: %s, want %s", c[1].bonus.from, c[2], tostring(got), c[4])
                elseif got:find("[^\32-\126]") or got:find("|", 1, true) then
                    ok, why = false, "not ASCII or a pipe: " .. got
                end
            end
            if W.Bonus({}, "card") ~= nil then ok, why = false, "no bonus gave words" end
            if ok and not (W.BonusLabel("heal") == "+Healing" and W.BonusLabel("damage") == "+Damage") then
                ok, why = false, "BonusLabel"
            end
            if ok and not (W.Signed(5) == "+5%" and W.Signed(-3) == "-3%" and W.Signed(4.6) == "+5%") then
                ok, why = false, "Signed: " .. tostring(W.Signed(5)) .. " " .. tostring(W.Signed(-3))
            end
        end
        check("10. Words.Bonus card / how / tip over model, estimated and measured; Signed", ok, why)
    end
end

--------------------------------------------------------------------------------
-- TBC
--------------------------------------------------------------------------------

-- %.17g numbers, sorted keys, nested tables inline: the same bytes for the
-- same numbers, whatever order pairs() gives.
local function Ser(v, depth)
    depth = depth or 0
    local tv = type(v)
    if tv == "number" then return string.format("%.17g", v) end
    if tv == "string" then return string.format("%q", v) end
    if tv == "boolean" or tv == "nil" then return tostring(v) end
    if tv ~= "table" then return tv end
    if depth > 5 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k], depth + 1) end
    return "{" .. table.concat(out, ",") .. "}"
end

-- Two independent 32-bit polynomial hashes over the transcript's bytes (exact
-- in doubles: h < 2^32, x 131 + 255 < 2^53), plus its line and byte counts.
local function Digest(lines)
    local h1, h2, bytes = 0, 0, 0
    for _, l in ipairs(lines) do
        local s = l .. "\n"
        bytes = bytes + #s
        for i = 1, #s do
            local b = s:byte(i)
            h1 = (h1 * 31 + b) % 4294967296
            h2 = (h2 * 131 + b) % 4294967291
        end
    end
    return { n = #lines, bytes = bytes, h1 = h1, h2 = h2 }
end

-- The golden, captured with --golden on e93d367 (before the first edit).
local GOLDEN = {
    -- T118: re-based for the two calc fields RowFor's explain now carries
    -- (talentName, tickPeriod); every other byte equal to the e93d367
    -- transcript (bytes = 400487, h1 = 4209107753, h2 = 3722721600), checked
    -- line by line with --print
    druid = { n = 900, bytes = 417569, h1 = 553152855, h2 = 1166058324 },
    class = { n = 354, bytes = 174286, h1 = 2384515562, h2 = 297317080 },
    -- T123: the druid's MD.Book (check 28), captured with --golden on 49494eb
    book = { n = 284, bytes = 184989, h1 = 1369451877, h2 = 4050973907 },
}

-- Druid damage ranks: id -> family, cast (ms), learn level (nil: the client
-- says nothing), description. Wrath R1 / R10 and the max ranks are the
-- client's own words (tools/spelltip.lua's), the rest restated in the same
-- shape for a low and a mid rank of each family.
local DAMAGE = {
    { 5176,  "Wrath",        1500,  1,   "Causes 13 to 16 Nature damage to the target." },
    { 6780,  "Wrath",        2000,  14,  "Causes 51 to 58 Nature damage to the target." },
    { 9912,  "Wrath",        2000,  nil, "Causes 278 to 312 Nature damage to the target." },
    { 9875,  "Starfire",     3500,  40,  "Causes 255 to 302 Arcane damage to the target." },
    { 26986, "Starfire",     3500,  67,  "Causes 540 to 636 Arcane damage to the target." },
    { 8921,  "Moonfire",     0,     4,   "Burns the enemy for 9 to 12 Arcane damage and then an additional 12 Arcane damage over 9 sec." },
    { 8925,  "Moonfire",     0,     22,  "Burns the enemy for 61 to 73 Arcane damage and then an additional 104 Arcane damage over 12 sec." },
    { 26988, "Moonfire",     0,     70,  "Burns the enemy for 305 to 357 Arcane damage and then an additional 600 Arcane damage over 12 sec." },
    { 5570,  "Insect Swarm", 0,     20,  "The enemy target is swarmed by insects, decreasing their chance to hit by 2% and causing 108 Nature damage over 12 sec." },
    { 27013, "Insect Swarm", 0,     70,  "The enemy target is swarmed by insects, decreasing their chance to hit by 2% and causing 792 Nature damage over 12 sec." },
    { 16914, "Hurricane",    10000, 40,  "Creates a violent storm in the target area causing 72 Nature damage to enemies every 1 sec, and increasing the time between attacks of enemies by 25%. Lasts 10 sec. Druid must channel to maintain the spell." },
    { 27012, "Hurricane",    10000, 70,  "Creates a violent storm in the target area causing 206 Nature damage to enemies every 1 sec, and increasing the time between attacks of enemies by 25%. Lasts 10 sec. Druid must channel to maintain the spell." },
}

local function DruidTranscript()
    local RM, SD, DM = MD.RankMath, MD.SpellData, MD.DamageMath
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local ids = {}
    for id in pairs(SD.spells) do ids[#ids + 1] = id end
    table.sort(ids)
    local savedSim, savedLevel, savedPL = MD.sim, S.level, MD.player.level
    for _, level in ipairs({ 40, 64, 70 }) do
        S.level, MD.player.level = level, level
        for _, sim in ipairs({ { "live", nil }, { "tree off", { tree = false } }, { "tree on", { tree = true } } }) do
            MD.sim = sim[2]
            local tag = "L" .. level .. " " .. sim[1]
            local res = RM:Compute()
            local fams = {}
            for fam in pairs(res) do fams[#fams + 1] = fam end
            table.sort(fams)
            for _, fam in ipairs(fams) do
                local r = res[fam]
                Add(tag .. " compute " .. fam .. " " .. Ser({ label = r.label, tol = r.tol,
                    suggestedID = r.suggestedID, callout = r.callout }))
                for i, row in ipairs(r.rows) do Add(tag .. " compute " .. fam .. " #" .. i .. " " .. Ser(row)) end
            end
            for _, id in ipairs(ids) do
                local s = SD.spells[id]
                local info = SD.families[s.family]
                Add(tag .. " explain " .. id .. " " .. Ser(RM:Explain(id)))
                if info and info.type == "lifebloom" then
                    for v = 2, 3 do Add(tag .. " explain " .. id .. " x" .. v .. " " .. Ser(RM:Explain(id, v))) end
                end
            end
        end
        MD.sim = nil
        Add("L" .. level .. " kit " .. Ser(RM:SpellKit({ live = true })))
    end

    -- the damage spells
    local realInfo, realBonus, realLevel = _G.GetSpellInfo, _G.GetSpellBonusDamage, _G.GetSpellLevelLearned
    local byId = {}
    for _, d in ipairs(DAMAGE) do byId[d[1]] = d end
    _G.GetSpellInfo = function(id)
        local d = byId[id]
        if d then return d[2], nil, "icon", d[3] end
        return realInfo(id)
    end
    _G.GetSpellBonusDamage = function(school) return school == 7 and 310 or 300 end
    _G.GetSpellLevelLearned = function(id) return byId[id] and byId[id][4] end
    local TAL = MD.harnessTalents
    local names = { "Moonfury", "Vengeance", "Wrath of Cenarius", "Improved Moonfire", "Focused Starlight" }
    local saved = {}
    for _, k in ipairs(names) do saved[k] = TAL[k] end
    for _, level in ipairs({ 64, 70 }) do
        S.level, MD.player.level = level, level
        for _, talents in ipairs({ 0, 5 }) do
            for _, k in ipairs(names) do TAL[k] = talents end
            if talents == 5 then TAL["Improved Moonfire"], TAL["Focused Starlight"] = 2, 2 end
            for _, d in ipairs(DAMAGE) do
                local base = DM.Parse(d[2], "340 Mana\n" .. d[5])
                Add(string.format("L%d T%d damage %d %s parse %s", level, talents, d[1], d[2], Ser(base)))
                Add(string.format("L%d T%d damage %d %s %s", level, talents, d[1], d[2],
                    Ser(DM.Compute(d[1], d[2], base))))
            end
        end
    end
    for k, v in pairs(saved) do TAL[k] = v end
    _G.GetSpellInfo, _G.GetSpellBonusDamage, _G.GetSpellLevelLearned = realInfo, realBonus, realLevel
    MD.sim, S.level, MD.player.level = savedSim, savedLevel, savedPL
    return lines
end

local function ClassTranscript()
    local RM = MD.RankMath
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    TBCCLASS_LIBRARY = true
    local lib = dofile(here .. "/tbcclasscheck.lua")
    local function LoadIf(cond, files) if not cond then S.Load(files, "SpellTuner", MD) end end
    LoadIf(MD.Profiles.byClass.PRIEST ~= nil,
        { "Data/Profile_Priest_TBC.lua", "Data/Profile_Shaman_TBC.lua", "Data/Profile_Paladin_TBC.lua" })
    LoadIf(MD.Parse ~= nil, { "Spells/Parse.lua" })
    LoadIf(MD.BookTBC ~= nil, { "Spells/Book_TBC.lua" })
    for _, c in ipairs({ "PRIEST", "SHAMAN", "PALADIN" }) do
        local caps = MD.Profiles.byClass[c].caps
        caps.rankTable, caps.tooltip = true, true
    end
    local CASES = {
        { "PRIEST", { ["Spiritual Healing"] = 5, ["Empowered Healing"] = 5, ["Divine Fury"] = 5, ["Improved Renew"] = 3 },
          { castTaken = { Heal = 0.5, ["Greater Heal"] = 0.5 } } },
        { "SHAMAN", { ["Purification"] = 5, ["Improved Chain Heal"] = 2, ["Improved Healing Wave"] = 5,
                      ["Tidal Mastery"] = 5 }, { castTaken = { ["Healing Wave"] = 0.5 } } },
        { "PALADIN", { ["Healing Light"] = 3, ["Sanctified Light"] = 3 }, {} },
    }
    for _, case in ipairs(CASES) do
        local class = case[1]
        for _, level in ipairs({ 60, 70 }) do
            S.level = level
            local rows, restore = lib.Install(S, MD, class, case[3])
            MD:SetTalents(case[2])
            S.units.player.class = class
            MD:DetectProfile()
            MD:Fire("CORE_LOGIN")
            local src = MD.BookTBC:Rebuild()
            local ids = {}
            for id in pairs(rows) do ids[#ids + 1] = id end
            table.sort(ids)
            local tag = class .. " L" .. level
            local res = RM:Compute()
            local fams = {}
            for fam in pairs(res) do fams[#fams + 1] = fam end
            table.sort(fams)
            for _, fam in ipairs(fams) do
                local r = res[fam]
                Add(tag .. " compute " .. fam .. " " .. Ser({ label = r.label, suggestedID = r.suggestedID,
                    callout = r.callout }))
                for i, row in ipairs(r.rows) do Add(tag .. " compute " .. fam .. " #" .. i .. " " .. Ser(row)) end
            end
            for _, id in ipairs(ids) do Add(tag .. " explain " .. id .. " " .. Ser(RM:Explain(id, nil, { live = true }))) end
            Add(tag .. " kit " .. Ser(RM.ClassKit({ live = true }, src)))
            restore()
        end
    end
    MD:SetTalents(MD.harnessTalents)
    S.level = 64
    S.units.player.class = "DRUID"
    MD:DetectProfile()
    MD:Fire("CORE_LOGIN")
    return lines
end

--------------------------------------------------------------------------------
-- T118 (docs/tasks/T118-tbc-book.md): MD.Book on TBC, Spells/Book_Model.lua
--------------------------------------------------------------------------------

-- The book now: rebuilt at once (Book:Refresh, the book's own door for what
-- moved without an event -- the suite's level and form), else Get().
local function Fresh()
    local Book = MD.Book
    if type(Book) ~= "table" then error("no MD.Book on TBC", 0) end
    if type(Book.Refresh) == "function" then return Book:Refresh() end
    return Book:Get()
end

local function Bool(v) return v == true end

-- every entry of the heal families against the rows of `results`
local function HealMismatches(book, results)
    local bad = {}
    local n = 0
    for key, res in pairs(results) do
        local fam = book.families[key]
        if not fam then
            bad[#bad + 1] = "no family " .. key
        else
            for _, row in ipairs(res.rows) do
                local e = book.spells[row.id]
                if not row.variant then
                    n = n + 1
                    if not e then
                        bad[#bad + 1] = key .. " " .. row.id .. " missing"
                    elseif not (e.value == row.heal and e.perMana == row.hpm and e.perSec == row.hps
                            and e.casts == row.casts and e.cost.amount == row.cost and e.cast == row.cast
                            and Bool(e.known) == Bool(row.known) and Bool(e.suggested) == Bool(row.suggested)
                            and Bool(e.dominated) == Bool(row.dominated) and e.family == key) then
                        bad[#bad + 1] = key .. " " .. row.id .. " " .. Show({ value = e.value, heal = row.heal,
                            pm = e.perMana, hpm = row.hpm, ps = e.perSec, hps = row.hps, c = e.casts, rc = row.casts })
                    end
                else
                    local v = e and e.variants and e.variants[row.variant - 1]
                    if not (v and v.variant == row.variant and v.value == row.heal and v.perMana == row.hpm
                            and v.perSec == row.hps and v.casts == row.casts) then
                        bad[#bad + 1] = key .. " " .. row.id .. " x" .. row.variant
                    end
                end
            end
        end
    end
    return bad, n
end

-- a TBC spellbook in the stub: { id, name, sub, cost, cast (ms), level, desc }
-- rows, installed as the client globals Spells/Book_TBC.lua reads; the
-- adapter's answers and the book reader's caches forgotten on the way in and
-- out
local BOOK_NAMES = { "GetNumSpellTabs", "GetSpellTabInfo", "GetSpellBookItemName", "GetSpellBookItemInfo",
    "GetSpellInfo", "GetSpellDescription", "GetSpellPowerCost", "GetSpellLevelLearned", "GetSpellBonusDamage" }
local function InstallBook(rows, opts)
    opts = opts or {}
    local saved = {}
    for _, n in ipairs(BOOK_NAMES) do saved[n] = rawget(_G, n) end
    local byId = {}
    for _, r in ipairs(rows) do byId[r.id] = r end
    local prevInfo, prevCost, prevLevel = saved.GetSpellInfo, saved.GetSpellPowerCost, saved.GetSpellLevelLearned
    _G.GetNumSpellTabs = function() return 1 end
    _G.GetSpellTabInfo = function(tab) if tab == 1 then return "General", "icon", 0, #rows end end
    _G.GetSpellBookItemName = function(slot)
        local r = rows[slot]
        if not r then return nil end
        return r.name, r.sub, r.id
    end
    _G.GetSpellBookItemInfo = function(slot) local r = rows[slot]; if r then return "SPELL", r.id end end
    _G.GetSpellInfo = function(id)
        local r = byId[id]
        if r then return r.name, r.sub, "icon", r.cast or 0, 0, 30, id end
        if prevInfo then return prevInfo(id) end
    end
    _G.GetSpellDescription = function(id) local r = byId[id]; return r and r.desc or "" end
    _G.GetSpellPowerCost = function(id)
        local r = byId[id]
        if r then
            if r.cost then return { { type = 0, cost = r.cost } } end
            return {}
        end
        if prevCost then return prevCost(id) end
    end
    _G.GetSpellLevelLearned = function(id)
        local r = byId[id]
        if r then return r.level end
        if prevLevel then return prevLevel(id) end
    end
    _G.GetSpellBonusDamage = function(school) return opts.damage or (school == 7 and 310 or 300) end
    local function Forget()
        for _, n in ipairs(BOOK_NAMES) do if MD.API.Invalidate then MD.API.Invalidate(n) end end
        local B = MD.BookTBC
        if B and type(B.Forget) == "function" then B.Forget() end
    end
    Forget()
    return function()
        for _, n in ipairs(BOOK_NAMES) do _G[n] = saved[n] end
        Forget()
    end
end

-- T123 (check 28): the druid's MD.Book as the parent (49494eb) built it --
-- the harness druid at levels 64 and 70, caster and Tree of Life, with every
-- DAMAGE rank above and two Other spells in the walk: the order, each
-- family's fields and every entry, serialised. Captured with --golden on the
-- parent before the first edit; T123 moves the damage section onto
-- DM.FamiliesFor(class), which for the druid is DM.families in the old order.
local function BookTranscript()
    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    local rows, ranks = {}, {}
    for _, d in ipairs(DAMAGE) do
        ranks[d[2]] = (ranks[d[2]] or 0) + 1
        rows[#rows + 1] = { id = d[1], name = d[2], sub = "Rank " .. ranks[d[2]], cost = 100 + 20 * #rows,
                            cast = d[3], level = d[4], desc = d[5] }
    end
    rows[#rows + 1] = { id = 29166, name = "Innervate", cost = 94, cast = 0, level = 40,
        desc = "Increases the target's Mana regeneration by 400% and allows 100% of the target's Mana regeneration to continue while casting. Lasts 20 sec." }
    rows[#rows + 1] = { id = 26990, name = "Mark of the Wild", sub = "Rank 8", cost = 445, cast = 0, level = 70,
        desc = "Increases the friendly target's armor by 340, all attributes by 14 and all resistances by 25 for 30 min." }
    local savedLevel, savedPL, savedTree = S.level, MD.player.level, MD.InTreeForm
    local restore = InstallBook(rows)
    for _, level in ipairs({ 64, 70 }) do
        for _, tree in ipairs({ false, true }) do
            S.level, MD.player.level = level, level
            MD.InTreeForm = function() return tree end
            local tag = "L" .. level .. (tree and " tree" or " caster")
            local book = Fresh()
            Add(tag .. " order " .. table.concat(book.order, ","))
            for _, key in ipairs(book.order) do
                local fam = book.families[key]
                Add(tag .. " family " .. key .. " " .. Ser({ key = fam.key, name = fam.name, kind = fam.kind,
                    school = fam.school, shape = fam.shape, noSeed = fam.noSeed, ids = fam.ids,
                    maxKnown = fam.maxKnown and fam.maxKnown.id, suggested = fam.suggested and fam.suggested.id }))
                for i, e in ipairs(fam.ranks) do Add(tag .. " family " .. key .. " #" .. i .. " " .. Ser(e)) end
            end
        end
    end
    restore()
    S.level, MD.player.level, MD.InTreeForm = savedLevel, savedPL, savedTree
    pcall(Fresh)
    return lines
end

-- A calc line as plain words: colours out, white space collapsed (the form
-- checks 19 and 20's goldens -- Tip:Spell's Shift lines, captured on d6691fe
-- before T121 deleted it -- are written in).
local function Plain(s) return (T.Strip(s):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
local function PlainList(list)
    local out = {}
    for i, s in ipairs(list or {}) do out[i] = Plain(s) end
    return out
end
local function SameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function BookChecks(dB)
    local BS, RM, SD, DM, RR = MD.BookShape, MD.RankMath, MD.SpellData, MD.DamageMath, MD.RankRules
    local Book = MD.Book
    local savedLevel, savedPL, savedTree, savedSim = S.level, MD.player.level, MD.InTreeForm, MD.sim

    -- 15 ----------------------------------------------------------------------
    T.section("15. MD.Book on TBC")
    do
        local okAll, why = Book ~= nil, Book == nil and "no MD.Book on TBC" or nil
        if okAll then
            local okM, err = Try(BS.CheckMethods, Book, "bookshapecheck")
            if not okM then okAll, why = false, err end
        end
        if okAll then
            for _, level in ipairs({ 40, 64, 70 }) do
                for _, tree in ipairs({ false, true }) do
                    S.level, MD.player.level = level, level
                    MD.InTreeForm = function() return tree end
                    local okB, book = Try(Fresh)
                    local valid, problems = false, { tostring(book) }
                    if okB then valid, problems = BS.Validate(book) end
                    print(string.format("    level %d %s: %s", level, tree and "tree" or "caster",
                        valid and ((okB and #book.order or 0) .. " families") or Show(problems)))
                    if not valid then okAll, why = false, "level " .. level .. ": " .. Show(problems) end
                end
            end
        end
        S.level, MD.player.level, MD.InTreeForm = savedLevel, savedPL, savedTree
        pcall(Fresh)
        check("15. MD.Book on TBC: CheckMethods, and Get() valid at 40 / 64 / 70, caster and tree", okAll, why)
    end

    -- 16 ----------------------------------------------------------------------
    T.section("16. every heal entry is its RankMath row")
    do
        local okB, book = Try(Fresh)
        local bad, n = { tostring(book) }, 0
        if okB then
            local res = RM:Compute({ live = true })
            bad, n = HealMismatches(book, res)
            if next(res) == nil then bad[#bad + 1] = "Compute gave nothing" end
        end
        print(string.format("    %d ranks compared, %d differ", n, #bad))
        check("16. value / perMana / perSec / casts / cost / cast / known / marks equal the rows, variants too",
            okB and #bad == 0 and n > 30, Show(bad))
    end

    -- 17 ----------------------------------------------------------------------
    T.section("17. afterOverheal")
    do
        local OH = MD.Overheal
        local savedF, savedK = OH.Fraction, OH.KindFraction
        OH.Fraction = function() return 0.3, 20, "rank" end
        OH.KindFraction = function(_, _, kind) return kind == "bloom" and 0.5 or 0.2, 20, "kind" end
        local okB, book = Try(Fresh)
        local res = RM:Compute({ live = true })
        local bad, seen = {}, 0
        if not okB then bad[1] = tostring(book) end
        for key, r in pairs(okB and res or {}) do
            for _, row in ipairs(r.rows) do
                if not row.variant then
                    local e = book.spells[row.id]
                    local a = e and e.afterOverheal
                    seen = seen + 1
                    if not (a and a.value == row.effHeal and a.perMana == row.effHpm and a.perSec == row.effHps
                            and a.frac == row.overheal.frac and a.scope == row.overheal.scope) then
                        bad[#bad + 1] = key .. " " .. row.id
                    end
                end
            end
        end
        OH.Fraction, OH.KindFraction = savedF, savedK
        local okC, clean = Try(Fresh)
        local leftover = 0
        for _, e in pairs(okC and clean.spells or {}) do if e.afterOverheal then leftover = leftover + 1 end end
        check("17. afterOverheal is the row's eff* with overheal seeded, nil without",
            okB and okC and seen > 30 and #bad == 0 and leftover == 0,
            Show({ bad = bad, seen = seen, leftover = leftover }))
    end

    -- 18 ----------------------------------------------------------------------
    T.section("18. bonus (model)")
    do
        local savedBonus = _G.GetSpellBonusHealing
        _G.GetSpellBonusHealing = function() return 700 end
        S.level, MD.player.level = 70, 70
        local okB, book = Try(Fresh)
        local function B(id)
            local e = okB and book.spells[id]
            return e and e.bonus or {}
        end
        local b, b7, b3 = B(26978), B(8903), B(5187)
        print("    HT R12 " .. Show(b))
        print("    HT R7  " .. Show(b7))
        print("    HT R3  " .. Show(b3))
        local C = MD.Coefficients
        local want7 = string.format("x1.20 Empowered Touch, downrank %.2f", C.Downrank(38, 70))
        local want3 = string.format("x1.20 Empowered Touch, downrank %.2f, level 14 x%.2f",
            C.Downrank(14, 70), C.Sub20(14))
        _G.GetSpellBonusHealing = savedBonus
        S.level, MD.player.level = savedLevel, savedPL
        pcall(Fresh)
        check("18. HT R12 at +700: counts 1.2, of 700, amount 840, x1.20 Empowered Touch; downrank and sub-20 named",
            okB and Near(b.counts, 1.2) and b.from == "model" and b.of == 700 and Near(b.amount, 840, 1e-9)
                and b.why == "x1.20 Empowered Touch" and b7.why == want7 and b3.why == want3
                and Near(b7.counts, 1.2 * C.Penalty(38, 70)),
            Show({ b, b7.why, b3.why, want7, want3 }))
    end

    -- 19 ----------------------------------------------------------------------
    T.section("19. calc is Tip:Spell's Shift lines (golden)")
    do
        -- T121: Tip:Spell(id, true)'s Shift lines, plain, captured on d6691fe
        -- before the builder was deleted (the harness's druid, +450 healing;
        -- a single-part spell's term label dropped, as the book prints it)
        local GON = "then x 1.10 Gift of Nature"
        local TREE = "+healing includes 95 Tree of Life aura"
        local CALC_GOLDEN = {
            [26978] = { { "2582 base + 540", "450 healing x 1.000 coef x 1.20 Emp. Touch", GON },
                        { "2582 base + 654", "545 healing x 1.000 coef x 1.20 Emp. Touch", GON, TREE } },
            [8903] = { { "1029 base + 413", "450 healing x 1.000 coef x 0.77 downrank x 1.20 Emp. Touch", GON },
                       { "1029 base + 501", "545 healing x 1.000 coef x 0.77 downrank x 1.20 Emp. Touch", GON, TREE } },
            [26981] = { { "932 base + 432", "450 healing x 0.800 coef x 1.20 Emp. Rejuvenation",
                          "then x 1.26 Gift of Nature, Improved Rejuvenation" },
                        { "932 base + 523", "545 healing x 0.800 coef x 1.20 Emp. Rejuvenation",
                          "then x 1.26 Gift of Nature, Improved Rejuvenation", TREE } },
            [9858] = { { "direct 1061 base + 128", "450 healing x 0.285 coef", "HoT 1064 base + 379",
                         "450 healing x 0.701 coef x 1.20 Emp. Rejuvenation", GON },
                       { "direct 1061 base + 155", "545 healing x 0.285 coef", "HoT 1064 base + 458",
                         "545 healing x 0.701 coef x 1.20 Emp. Rejuvenation", GON, TREE } },
            [33763] = { { "HoT 273 base + 280", "450 healing x 0.519 coef x 1.20 Emp. Rejuvenation",
                          "bloom 600 base + 185", "450 healing x 0.342 coef x 1.20 Emp. Rejuvenation", GON },
                        { "HoT 273 base + 339", "545 healing x 0.519 coef x 1.20 Emp. Rejuvenation",
                          "bloom 600 base + 224", "545 healing x 0.342 coef x 1.20 Emp. Rejuvenation", GON, TREE } },
        }
        local bad, n = {}, 0
        -- HT 12, HT 7 (downranked), Rejuvenation 12, Regrowth 9, Lifebloom
        local CASES = { 26978, 8903, 26981, 9858, 33763 }
        for ti, tree in ipairs({ false, true }) do
            MD.InTreeForm = function() return tree end
            local okB, book = Try(Fresh)
            for _, id in ipairs(CASES) do
                local e = okB and book.spells[id]
                if okB and e then
                    n = n + 1
                    local want = CALC_GOLDEN[id][ti]
                    local got = PlainList(e.calc)
                    if not SameList(want, got) then
                        bad[#bad + 1] = id .. (tree and " tree" or "") .. ": " .. Show(got) .. " want " .. Show(want)
                    end
                    if id == 26978 and not tree then
                        for _, l in ipairs(e.calc or {}) do print("    " .. l) end
                    end
                else
                    bad[#bad + 1] = id .. " no entry"
                end
            end
        end
        MD.InTreeForm = savedTree
        pcall(Fresh)
        check("19. calc equals Tip:Spell(id, true)'s Shift lines (golden): direct, hot, hybrid, bloom, downranked, tree",
            #bad == 0 and n == 10, Show(bad))
    end

    -- 20 ----------------------------------------------------------------------
    T.section("20. Tranquility and Swiftmend")
    do
        local okB, book = Try(Fresh)
        local tq = okB and book.families.Tranquility
        local sm = okB and book.families.Swiftmend
        local okT = tq and sm and tq.noSeed == true and sm.noSeed == true and tq.kind == "heal" and sm.kind == "heal"
            and tq.shape == "channel" and sm.shape == "none"
        local valueless = true
        for _, fam in ipairs({ tq or {}, sm or {} }) do
            for _, e in ipairs(fam.ranks or {}) do
                if e.value ~= nil or type(e.cost) ~= "table" or type(e.level) ~= "number" or e.castKind == nil then
                    valueless = false
                end
            end
        end
        local smE = sm and sm.ranks and sm.ranks[1]
        -- T121: Tip:Spell(18562, true)'s Eats lines, plain, captured on d6691fe
        local want = { "Eats Rejuvenation 1725 (12s of its ticks)", "Eats Regrowth 1360 (18s of its ticks)" }
        local got = PlainList(smE and smE.calc)
        for _, l in ipairs(smE and smE.calc or {}) do print("    " .. l) end
        check("20. Tranquility and Swiftmend: noSeed heal families, no value; Swiftmend's calc is Tip:Spell's Eats lines",
            okT and valueless and #want == 2 and SameList(want, got),
            Show({ okT = okT, valueless = valueless, got = got, want = want }))
    end

    -- 21 ----------------------------------------------------------------------
    T.section("21. damage")
    do
        local ROWS, ranks = {}, {}
        for _, d in ipairs(DAMAGE) do
            if d[2] == "Wrath" or d[2] == "Moonfire" then
                ranks[d[2]] = (ranks[d[2]] or 0) + 1
                ROWS[#ROWS + 1] = { id = d[1], name = d[2], sub = "Rank " .. ranks[d[2]], cost = 100 + 20 * #ROWS,
                                    cast = d[3], level = d[4], desc = d[5] }
            end
        end
        local restore = InstallBook(ROWS)
        local okB, book = Try(Fresh)
        local bad = {}
        if not okB then bad[1] = tostring(book) end
        local F = { eff = "perMana", rate = "perSec", value = "value",
                    eligible = function(e) return e.known and e.perMana and e.perSec end }
        for _, name in ipairs({ "Wrath", "Moonfire" }) do
            local fam = okB and book.families[name]
            if not (fam and fam.kind == "damage" and fam.school and #fam.ranks >= 2) then
                bad[#bad + 1] = "family " .. name .. " " .. Show(fam and { kind = fam.kind, school = fam.school,
                    n = #fam.ranks })
            else
                for _, e in ipairs(fam.ranks) do
                    local c = DM.Compute(e.id, name, DM.Parse(name, e.desc))
                    if not (c and e.value == c.expected and e.perMana == c.dpm and e.perSec == c.dps
                            and e.bonus and type(e.bonus.why) == "string" and e.bonus.why:find("VERIFY$")
                            and e.bonus.from == "model") then
                        bad[#bad + 1] = name .. " " .. e.id .. " " .. Show({ v = e.value, x = c and c.expected,
                            pm = e.perMana, dpm = c and c.dpm, why = e.bonus and e.bonus.why })
                    end
                end
                local copies = {}
                for i, e in ipairs(fam.ranks) do
                    local x = {}
                    for k, v in pairs(e) do x[k] = v end
                    x.dominated, x.suggested = nil, nil
                    copies[i] = x
                end
                RR.Pareto(copies, F)
                local top
                for i, e in ipairs(fam.ranks) do if e == fam.maxKnown then top = copies[i] end end
                local s = RR.Suggested(copies, top, F)
                if not (s and fam.suggested and s.id == fam.suggested.id and fam.suggested.suggested == true) then
                    bad[#bad + 1] = name .. " suggested " .. tostring(s and s.id) .. " vs "
                        .. tostring(fam.suggested and fam.suggested.id)
                end
                print("    " .. name .. ": " .. #fam.ranks .. " ranks, suggested " .. tostring(fam.suggested and fam.suggested.id))
            end
        end
        -- the header's +damage: the pane hands the family's school NAME; the
        -- client takes the school's id (Nature 4, Arcane 7)
        local realBD = _G.GetSpellBonusDamage
        _G.GetSpellBonusDamage = function(school) return ({ [4] = 300, [7] = 310 })[school] end
        local nat, arc, none = MD.Book:Bonus("damage", "Nature"), MD.Book:Bonus("damage", "Arcane"),
            MD.Book:Bonus("damage", "Nowhere")
        _G.GetSpellBonusDamage = realBD
        print("    Bonus damage: Nature " .. tostring(nat) .. ", Arcane " .. tostring(arc) .. ", unknown " .. tostring(none))
        if not (nat == 300 and arc == 310 and none == nil) then
            bad[#bad + 1] = "Bonus by school name " .. Show({ nat, arc, none })
        end
        local valid, problems = false, nil
        if okB then valid, problems = BS.Validate(book) end
        restore()
        pcall(Fresh)
        check("21. damage entries are DM.Compute's expected / dpm / dps; suggested by RankRules; why ends VERIFY; Book:Bonus takes a school name",
            okB and #bad == 0 and valid, Show({ bad, problems }))
    end

    -- 22 ----------------------------------------------------------------------
    T.section("22. Other")
    do
        local ROWS = {
            { id = 29166, name = "Innervate", cost = 94, cast = 0, level = 40,
              desc = "Increases the target's Mana regeneration by 400% and allows 100% of the target's Mana regeneration to continue while casting. Lasts 20 sec." },
            { id = 5232, name = "Mark of the Wild", sub = "Rank 2", cost = 50, cast = 0, level = 10,
              desc = "Increases the friendly target's armor by 65, all attributes by 2 and all resistances by 0 for 30 min." },
            { id = 26990, name = "Mark of the Wild", sub = "Rank 8", cost = 445, cast = 0, level = 70,
              desc = "Increases the friendly target's armor by 340, all attributes by 14 and all resistances by 25 for 30 min." },
            { id = 17061, name = "Furor", sub = "Passive", cost = 30, level = 10, desc = "Gives you a chance to gain rage." },
            { id = 6603, name = "Attack", cast = 0, level = 1, desc = "Hits the target." },
        }
        local restore = InstallBook(ROWS)
        local okB, book = Try(Fresh)
        local inn = okB and book.families.Innervate
        local motw = okB and book.families["Mark of the Wild"]
        local okO = inn and motw and inn.kind == nil and inn.shape == "none" and #motw.ranks == 2
            and motw.ranks[1].id == 5232 and motw.ranks[2].id == 26990 and motw.ranks[2].cost.amount == 445
            and inn.ranks[1].known == true and type(inn.ranks[1].desc) == "string"
            and book.families.Furor == nil and book.families.Attack == nil
        local valid, problems = false, nil
        if okB then valid, problems = BS.Validate(book) end
        if okB then print("    order " .. table.concat(book.order, ",")) end
        restore()
        pcall(Fresh)
        check("22. Other: Innervate and Mark of the Wild listed with a cost; a passive and a free spell are not",
            okO and valid, Show({ ok = okO, problems = problems }))
    end

    -- 23 ----------------------------------------------------------------------
    T.section("23. live; the what-if through one door")
    do
        MD.sim = {}
        local okB, live = Try(Fresh)
        local liveMap = {}
        for fam, r in pairs(RM:Compute({ live = true })) do
            if r.suggestedID then liveMap[fam] = SD.spells[r.suggestedID].rank end
        end
        local gen0 = Book and Book.generation
        local fired = 0
        MD:RegisterCallback("BOOK_CHANGED", function() fired = fired + 1 end)
        local bad = {}
        if not okB then bad[1] = tostring(live) end
        -- a what-if that moves a suggested rank, so the live map is a real test
        local SIMS = { { heal = 150 }, { heal = 0 }, { heal = 3000 }, { mana = 600 }, { crit = 60 } }
        local chosen
        for _, sim in ipairs(SIMS) do
            MD.sim = sim
            local m = {}
            for fam, r in pairs(RM:Compute()) do
                if r.suggestedID then m[fam] = SD.spells[r.suggestedID].rank end
            end
            MD.sim = {}
            for fam, rank in pairs(m) do if liveMap[fam] ~= rank then chosen = sim end end
            if chosen then break end
        end
        MD.sim = { heal = 150 }
        local okL, book = Try(Fresh)
        local okW, wi = Try(function() return Book:Get({ whatIf = true }) end)
        local simRes = RM:Compute()
        if okL then
            local b2, n2 = HealMismatches(book, RM:Compute({ live = true }))
            if #b2 > 0 or n2 == 0 then bad[#bad + 1] = "live under MD.sim: " .. Show(b2) end
        else
            bad[#bad + 1] = "live: " .. tostring(book)
        end
        if okW and okL then
            local b3, n3 = HealMismatches(wi, simRes)
            if #b3 > 0 or n3 == 0 then bad[#bad + 1] = "whatIf: " .. Show(b3) end
            if wi == book then bad[#bad + 1] = "whatIf is the live book" end
            if wi.generation ~= Book.generation then bad[#bad + 1] = "whatIf generation" end
        else
            bad[#bad + 1] = "whatIf: " .. tostring(wi)
        end
        if Book and Book.generation ~= gen0 then
            bad[#bad + 1] = "generation moved " .. tostring(gen0) .. " -> " .. tostring(Book.generation)
        end
        if fired ~= 0 then bad[#bad + 1] = "BOOK_CHANGED fired " .. fired end
        if chosen then MD.sim = chosen end
        local infoBefore = { tag = "the last Compute's context" }
        RM.info = infoBefore
        local sugg = RM:SuggestedRanks()
        if RM.info ~= infoBefore then bad[#bad + 1] = "SuggestedRanks left RankMath.info moved" end
        MD.sim = savedSim
        for fam, rank in pairs(liveMap) do if sugg[fam] ~= rank then bad[#bad + 1] = "SuggestedRanks " .. fam end end
        if not chosen then bad[#bad + 1] = "no what-if moved a suggested rank" end
        print("    what-if that moves a rank: " .. Show(chosen))
        check("23. Get() ignores MD.sim, Get({ whatIf }) reads it uncached and unannounced; SuggestedRanks is live",
            #bad == 0, Show(bad))
    end

    -- 24 ----------------------------------------------------------------------
    T.section("24. BOOK_CHANGED and the generation")
    do
        pcall(Fresh)
        local fired = 0
        MD:RegisterCallback("BOOK_CHANGED", function() fired = fired + 1 end)
        local gen0 = Book and Book.generation or -1
        local savedBonus = _G.GetSpellBonusHealing
        _G.GetSpellBonusHealing = function() return 520 end
        S.Fire("UNIT_INVENTORY_CHANGED", "player")
        local afterGear, genGear = fired, Book and Book.generation
        S.Fire("UNIT_INVENTORY_CHANGED", "player")
        MD:Fire("TALENTS_CHANGED")
        local afterSame, genSame = fired, Book and Book.generation
        S.Fire("UNIT_INVENTORY_CHANGED", "party1")
        local afterParty = fired
        _G.GetSpellBonusHealing = savedBonus
        S.Fire("UNIT_INVENTORY_CHANGED", "player")
        local afterBack, genBack = fired, Book and Book.generation
        local seen = { afterGear = afterGear, afterSame = afterSame, afterParty = afterParty, afterBack = afterBack,
                       gen0 = gen0, genGear = genGear, genSame = genSame, genBack = genBack }
        print("    " .. Show(seen))
        check("24. gear moving a value fires BOOK_CHANGED once and bumps the generation; an unchanged rebuild does neither",
            afterGear == 1 and genGear == gen0 + 1 and afterSame == 1 and genSame == genGear and afterParty == 1
                and afterBack == 2 and genBack == gen0 + 2, Show(seen))
    end

    -- 25 ----------------------------------------------------------------------
    T.section("25. a class without the rank table")
    do
        local ROWS = {
            { id = 25213, name = "Greater Heal", sub = "Rank 7", cost = 825, cast = 3000, level = 68,
              desc = "A slow casting spell that heals a single target for 2396 to 2784." },
            { id = 25389, name = "Power Word: Fortitude", sub = "Rank 7", cost = 700, cast = 0, level = 70,
              desc = "Power infuses the target increasing their Stamina by 79 for 30 min." },
        }
        local restore = InstallBook(ROWS)
        -- as shipped (T123) the priest's file grants the rank table: taken
        -- away for this check's own run, then given back
        local caps = MD.Profiles.byClass.PRIEST.caps
        local savedRT, savedTip = caps.rankTable, caps.tooltip
        caps.rankTable, caps.tooltip = nil, nil
        S.units.player.class = "PRIEST"
        MD:DetectProfile()
        MD:Fire("CORE_LOGIN")
        local okB, book = Try(Fresh)
        local kinds = {}
        for key, fam in pairs(okB and book.families or {}) do
            if fam.kind ~= nil then kinds[#kinds + 1] = key .. "=" .. fam.kind end
        end
        local valid, problems = false, nil
        if okB then valid, problems = BS.Validate(book) end
        local listed = okB and book.families["Power Word: Fortitude"] ~= nil
        restore()
        caps.rankTable, caps.tooltip = savedRT, savedTip
        S.units.player.class = "DRUID"
        MD:DetectProfile()
        MD:Fire("CORE_LOGIN")
        pcall(Fresh)
        check("25. a priest without the rank table: Other only (no heal, no damage), valid",
            okB and #kinds == 0 and listed and valid, Show({ kinds = kinds, listed = listed, problems = problems }))
    end

    -- 26 ----------------------------------------------------------------------
    T.section("26. MD.FamiliesTBC is gone")
    check("26. MD.FamiliesTBC (T118's alias) is nil: every reader reads MD.Book", MD.FamiliesTBC == nil,
        type(MD.FamiliesTBC))

    -- 27 ----------------------------------------------------------------------
    T.section("27. a priest's, a shaman's and a paladin's book, damage included")
    do
        TBCCLASS_LIBRARY = true
        local lib = dofile(here .. "/tbcclasscheck.lua")
        -- what each class's profile prices from tools/tbcclasscheck.lua's
        -- damage fixture, in the profile's damageOrder (Mind Flay: no
        -- channel shape DM.Parse reads, dropped from the profile)
        local WANT = {
            PRIEST = { "Smite", "Holy Fire", "Mind Blast", "Shadow Word: Pain" },
            SHAMAN = { "Lightning Bolt", "Chain Lightning", "Earth Shock", "Flame Shock", "Frost Shock" },
            PALADIN = { "Exorcism", "Holy Wrath", "Consecration" },
        }
        local bad = {}
        local savedLevel = S.level
        for _, class in ipairs({ "PRIEST", "SHAMAN", "PALADIN" }) do
            S.level = 70
            local okI, rows, undo = Try(lib.Install, S, MD, class, { damage = true })
            if not okI then
                bad[#bad + 1] = class .. " install: " .. tostring(rows)
            else
                S.units.player.class = class
                MD:DetectProfile()
                MD:Fire("CORE_LOGIN")
                if MD.BookTBC and MD.BookTBC.Rebuild then MD.BookTBC:Rebuild() end
                local okB, book = Try(Fresh)
                if not okB then
                    bad[#bad + 1] = class .. ": " .. tostring(book)
                else
                    local valid, problems = BS.Validate(book)
                    if not valid then bad[#bad + 1] = class .. ": " .. Show(problems) end
                    local heals, damage, seenDamage, healAfter = {}, {}, false, false
                    for _, key in ipairs(book.order) do
                        local fam = book.families[key]
                        if fam.kind == "damage" then
                            seenDamage = true
                            damage[#damage + 1] = key
                            for _, e in ipairs(fam.ranks) do
                                if type(e.value) ~= "number" then
                                    bad[#bad + 1] = class .. " " .. key .. " " .. e.id .. " no value"
                                end
                            end
                        elseif fam.kind == "heal" then
                            heals[#heals + 1] = key
                            if seenDamage then healAfter = true end
                        end
                    end
                    local src = MD.RankMath:Source()
                    local wantHeals = table.concat(src and src.familyOrder or {}, ",")
                    if table.concat(heals, ",") ~= wantHeals or healAfter or #heals == 0 then
                        bad[#bad + 1] = class .. " heals " .. table.concat(heals, ",") .. " want " .. wantHeals
                    end
                    if table.concat(damage, ",") ~= table.concat(WANT[class], ",") then
                        bad[#bad + 1] = class .. " damage " .. table.concat(damage, ",") .. " want "
                            .. table.concat(WANT[class], ",")
                    end
                    print(string.format("    %s: %d heal and %d damage families", class, #heals, #damage))
                end
                undo()
            end
        end
        S.level = savedLevel
        S.units.player.class = "DRUID"
        MD:DetectProfile()
        MD:Fire("CORE_LOGIN")
        if MD.BookTBC and MD.BookTBC.Rebuild then MD.BookTBC:Rebuild() end
        pcall(Fresh)
        check("27. each class book passes BookShape.Validate: its heals, then its damage families in the profile's order",
            #bad == 0, table.concat(bad, "; "))
    end

    -- 28 ----------------------------------------------------------------------
    T.section("28. the druid's book, as on the parent")
    local function Same(a, b) return a.n == b.n and a.bytes == b.bytes and a.h1 == b.h1 and a.h2 == b.h2 end
    check(string.format("28. the druid's MD.Book (heals, damage, Other), %d lines, as on the parent", dB.n),
        Same(dB, GOLDEN.book), Show(dB) .. " vs golden " .. Show(GOLDEN.book))
end

local function TbcChecks()
    -- 11 ----------------------------------------------------------------------
    T.section("11. the files on the TBC TOC")
    do
        local listed = {}
        for _, f in ipairs(S.TocFiles("SpellTuner_TBC.toc")) do listed[f] = true end
        local W = MD.Words
        -- T118: MD.Book is TBC's too now (Spells/Book_Model.lua, check 15);
        -- Words.GCD is 1.5 either way
        local ok = MD.Coefficients ~= nil and MD.BookShape ~= nil and W ~= nil
            and listed["Spells/Coefficients.lua"] and listed["Spells/BookShape.lua"] and listed["Spells/Words.lua"]
            and W.GCD == 1.5
        check("11. Coefficients, BookShape and Words load from the TBC TOC; Words.GCD 1.5", ok,
            Show({ coef = MD.Coefficients ~= nil, shape = MD.BookShape ~= nil, words = W ~= nil,
                   book = MD.Book ~= nil, gcd = W and W.GCD }))
    end

    -- 12 / 13 -----------------------------------------------------------------
    local okD, druid = Try(DruidTranscript)
    if not okD then druid = { "raised: " .. tostring(druid) } end
    local okC, class = Try(ClassTranscript)
    if not okC then class = { "raised: " .. tostring(class) } end
    local okB, bookLines = Try(BookTranscript)
    if not okB then bookLines = { "raised: " .. tostring(bookLines) } end
    if mode == "print" then
        for _, l in ipairs(druid) do print("druid\t" .. l) end
        for _, l in ipairs(class) do print("class\t" .. l) end
        for _, l in ipairs(bookLines) do print("book\t" .. l) end
        os.exit(0)
    end
    local dD, dC, dB = Digest(druid), Digest(class), Digest(bookLines)
    if mode == "golden" then
        print("local GOLDEN = {")
        print(string.format("    druid = { n = %d, bytes = %d, h1 = %d, h2 = %d },", dD.n, dD.bytes, dD.h1, dD.h2))
        print(string.format("    class = { n = %d, bytes = %d, h1 = %d, h2 = %d },", dC.n, dC.bytes, dC.h1, dC.h2))
        print(string.format("    book = { n = %d, bytes = %d, h1 = %d, h2 = %d },", dB.n, dB.bytes, dB.h1, dB.h2))
        print("}")
        os.exit(0)
    end
    local function Same(a, b) return a.n == b.n and a.bytes == b.bytes and a.h1 == b.h1 and a.h2 == b.h2 end
    T.section("12. the druid golden")
    check(string.format("12. the druid's Compute / Explain / SpellKit / DamageMath, %d lines, as on the parent", dD.n),
        okD and Same(dD, GOLDEN.druid), Show(dD) .. " vs golden " .. Show(GOLDEN.druid))
    T.section("13. the class golden")
    check(string.format("13. a priest's, shaman's and paladin's ClassRow and kit, %d lines, as on the parent", dC.n),
        okC and Same(dC, GOLDEN.class), Show(dC) .. " vs golden " .. Show(GOLDEN.class))

    -- 14 ----------------------------------------------------------------------
    T.section("14. the coefficient literals")
    do
        local found = {}
        for _, rel in ipairs({ "Engine/RankMath.lua", "Engine/DamageMath.lua" }) do
            local fh = io.open(ROOT .. "/" .. rel, "r")
            local n = 0
            for line in (fh and fh:lines() or function() return nil end) do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                -- GROUP_COEF stays as an alias (`= MD.Coefficients.GROUP`): its
                -- number is the literal refused
                for _, lit in ipairs({ "/ 3%.5", "/ 15", "0%.0375", "GROUP_COEF = [%d%.]" }) do
                    if code:find(lit) then found[#found + 1] = rel .. ":" .. n .. " " .. lit end
                end
            end
            if fh then fh:close() end
        end
        for _, f in ipairs(found) do print("    " .. f) end
        check("14. no `/ 3.5`, `/ 15`, `0.0375` or `GROUP_COEF = <n>` in RankMath or DamageMath's code", #found == 0,
            #found .. " found")
    end

    -- 15-26 (T118) ------------------------------------------------------------
    local okK, err = Try(BookChecks, dB)
    if not okK then check("15-28. the TBC book's checks ran", false, err) end
end

if S.flavour == "forever" then ForeverChecks() else TbcChecks() end
T.done()
