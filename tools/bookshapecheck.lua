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
-- Under tbc (4 checks):
--  11. the three files load from the TBC TOC; Words.GCD is 1.5 with no MD.Book;
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
    druid = { n = 900, bytes = 400487, h1 = 4209107753, h2 = 3722721600 },
    class = { n = 354, bytes = 174286, h1 = 2384515562, h2 = 297317080 },
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

local function TbcChecks()
    -- 11 ----------------------------------------------------------------------
    T.section("11. the files on the TBC TOC")
    do
        local listed = {}
        for _, f in ipairs(S.TocFiles("SpellTuner_TBC.toc")) do listed[f] = true end
        local W = MD.Words
        local ok = MD.Coefficients ~= nil and MD.BookShape ~= nil and W ~= nil and MD.Book == nil
            and listed["Spells/Coefficients.lua"] and listed["Spells/BookShape.lua"] and listed["Spells/Words.lua"]
            and W.GCD == 1.5
        check("11. Coefficients, BookShape and Words load from the TBC TOC; Words.GCD 1.5 with no MD.Book", ok,
            Show({ coef = MD.Coefficients ~= nil, shape = MD.BookShape ~= nil, words = W ~= nil,
                   book = MD.Book ~= nil, gcd = W and W.GCD }))
    end

    -- 12 / 13 -----------------------------------------------------------------
    local okD, druid = Try(DruidTranscript)
    if not okD then druid = { "raised: " .. tostring(druid) } end
    local okC, class = Try(ClassTranscript)
    if not okC then class = { "raised: " .. tostring(class) } end
    if mode == "print" then
        for _, l in ipairs(druid) do print("druid\t" .. l) end
        for _, l in ipairs(class) do print("class\t" .. l) end
        os.exit(0)
    end
    local dD, dC = Digest(druid), Digest(class)
    if mode == "golden" then
        print("local GOLDEN = {")
        print(string.format("    druid = { n = %d, bytes = %d, h1 = %d, h2 = %d },", dD.n, dD.bytes, dD.h1, dD.h2))
        print(string.format("    class = { n = %d, bytes = %d, h1 = %d, h2 = %d },", dC.n, dC.bytes, dC.h1, dC.h2))
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
end

if S.flavour == "forever" then ForeverChecks() else TbcChecks() end
T.done()
