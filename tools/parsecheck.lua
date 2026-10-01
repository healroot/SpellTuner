-- tools/run.sh tools/parsecheck.lua
--
-- T8: Spells/Parse.lua against tools/data/parse-fixture.lua, the lead's
-- specification. Forever only -- the parser is class-agnostic, static Lua,
-- and has nothing to do with the TBC client.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")
local ROOT = arg[1] or "."

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-72s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local P = MD.Parse
local fixture = dofile(ROOT .. "/tools/data/parse-fixture.lua")

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

-- fields a part may carry; used to check "no field the fixture does not name"
-- in both directions (present-in-fixture-and-not-in-read, and vice versa).
local PART_FIELDS = { "min", "max", "over", "dur", "tick", "period", "periodDur", "school" }

local function PartsEqual(expected, got)
    if expected == nil then return got == nil end
    if type(got) ~= "table" then return false end
    for _, f in ipairs(PART_FIELDS) do
        if expected[f] ~= got[f] then return false end
    end
    return true
end

local function Fmt(v)
    if v == nil then return "nil" end
    if type(v) == "table" then
        local parts = {}
        for _, f in ipairs(PART_FIELDS) do
            if v[f] ~= nil then parts[#parts + 1] = f .. "=" .. tostring(v[f]) end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

-- every number literal appearing in text, commas removed, as a set of numbers.
local function NumbersIn(text)
    local clean = text:gsub(",", "")
    local set = {}
    for n in clean:gmatch("%d+%.?%d*") do
        set[tonumber(n)] = true
    end
    return set
end

-- "period" is excluded here: Arcane Missiles' "each second" states a period
-- of 1 without the digit 1 ever appearing in the text (Hurricane's "every 1
-- sec" does carry the literal digit, and is still checked via this list
-- since it appears under "period" too -- excluding the field costs nothing
-- there). The other five fields are always read off a digit run.
local NUMBER_FIELDS = { "min", "max", "over", "dur", "tick", "periodDur" }

local function NumbersInPart(part)
    local nums = {}
    for _, f in ipairs(NUMBER_FIELDS) do
        if type(part[f]) == "number" then nums[#nums + 1] = part[f] end
    end
    return nums
end

--------------------------------------------------------------------------------
-- 1: every pinned description reads exactly its heal, damage and absorb
--------------------------------------------------------------------------------
do
    local allGood = true
    local detail = nil
    for _, e in ipairs(fixture.descriptions) do
        if not e.none and not e.loose and not e.refuse then
            local got = P.Description(e.text)
            local wantHeal, wantDamage, wantAbsorb = e.heal, e.damage, e.absorb
            local good = true
            if got == nil then
                good = (wantHeal == nil and wantDamage == nil and wantAbsorb == nil)
            else
                good = PartsEqual(wantHeal, got.heal) and PartsEqual(wantDamage, got.damage)
                    and wantAbsorb == got.absorb
            end
            if not good then
                allGood = false
                if not detail then
                    detail = string.format("%s: %q -> heal %s damage %s absorb %s",
                        e.src, e.text,
                        Fmt(got and got.heal), Fmt(got and got.damage), Fmt(got and got.absorb))
                end
            end
        end
    end
    check("every pinned description reads exactly its heal, damage and absorb", allGood, detail)
end

--------------------------------------------------------------------------------
-- 2: a description with no amount reads nil
--------------------------------------------------------------------------------
do
    local allGood = true
    local detail = nil
    for _, e in ipairs(fixture.descriptions) do
        if e.none then
            local got = P.Description(e.text)
            if got ~= nil then
                allGood = false
                if not detail then detail = e.src .. ": " .. Fmt(got) end
            end
        end
    end
    check("a description with no amount reads nil", allGood, detail)
end

--------------------------------------------------------------------------------
-- 2b (review B4, T50): a text whose amount is one tick of an unrecognised
-- periodic clause, or is offered "or N healing" to an ally, is refused -- one
-- check per fixture entry marked `refuse`, so each wording fails on its own.
--------------------------------------------------------------------------------
for _, e in ipairs(fixture.descriptions) do
    if e.refuse then
        local got = P.Description(e.text)
        local detail = nil
        if got ~= nil then
            detail = string.format("heal %s damage %s absorb %s", Fmt(got.heal), Fmt(got.damage), Fmt(got.absorb))
        end
        check("refused, not read as one direct hit: " .. e.src, got == nil, detail)
    end
end

--------------------------------------------------------------------------------
-- 3: no number is ever invented
--------------------------------------------------------------------------------
do
    local allGood = true
    local detail = nil
    for _, e in ipairs(fixture.descriptions) do
        local got = P.Description(e.text)
        if got ~= nil then
            local allowed = NumbersIn(e.text)
            for _, key in ipairs({ "heal", "damage" }) do
                local part = got[key]
                if part ~= nil then
                    for _, n in ipairs(NumbersInPart(part)) do
                        if not allowed[n] then
                            allGood = false
                            if not detail then
                                detail = e.src .. ": " .. key .. " has " .. tostring(n) .. " not in text"
                            end
                        end
                    end
                end
            end
            if got.absorb ~= nil and not allowed[got.absorb] then
                allGood = false
                if not detail then detail = e.src .. ": absorb has " .. tostring(got.absorb) .. " not in text" end
            end
        end
    end
    check("no number is ever invented", allGood, detail)
end

--------------------------------------------------------------------------------
-- 4: Parse never raises, whatever it is given
--------------------------------------------------------------------------------
do
    local weird = { nil, 5, {}, "", string.rep("1 2 ", 500) }
    -- T91: the readers by name, so a missing one fails here rather than
    -- ending ipairs early on a nil.
    local names = { "Clean", "Description", "Cost", "Cast", "Rank",
        "Targets", "Cooldown", "Lockout", "ManaSource" }
    local allGood = true
    local detail = nil
    local function tryAll(v, label)
        for _, name in ipairs(names) do
            local f = P[name]
            local raised = type(f) ~= "function" or not pcall(f, v)
            if raised then
                allGood = false
                if not detail then detail = "Parse." .. name .. " raised on " .. label end
            end
        end
    end
    for i, v in ipairs(weird) do tryAll(v, "weird[" .. i .. "]") end
    tryAll(nil, "nil")
    for _, e in ipairs(fixture.descriptions) do tryAll(e.text, e.src) end
    for _, e in ipairs(fixture.costs) do tryAll(e.text, e.text) end
    for _, e in ipairs(fixture.casts) do tryAll(e.text, e.text) end
    for _, e in ipairs(fixture.ranks) do tryAll(e.text, e.text) end
    for _, e in ipairs(fixture.targets) do tryAll(e.text, e.src) end
    for _, e in ipairs(fixture.cooldowns) do tryAll(e.text, e.src) end
    for _, e in ipairs(fixture.manaSources) do tryAll(e.text, e.src) end
    check("Parse never raises, whatever it is given", allGood, detail)
end

--------------------------------------------------------------------------------
-- 5: escape codes are stripped before reading
--------------------------------------------------------------------------------
do
    local d = P.Description("|cffffffffHeals|r a friendly target for 40 to 55.|nIt is quoted.")
    local escGood = d ~= nil and PartsEqual({ min = 40, max = 55 }, d.heal)
    local cleaned = P.Clean("a |TInterface\\Icons\\x:0|t b")
    local cleanGood = cleaned == "a b"
    check("escape codes are stripped before reading", escGood and cleanGood,
        "heal=" .. Fmt(d and d.heal) .. " clean=" .. Fmt(cleaned))
end

--------------------------------------------------------------------------------
-- 6: costs read as an amount or a percentage of base mana
--------------------------------------------------------------------------------
do
    local allGood = true
    local detail = nil
    for _, e in ipairs(fixture.costs) do
        local got = P.Cost(e.text)
        local good
        if e.cost == nil then
            good = got == nil
        else
            good = type(got) == "table" and got.amount == e.cost.amount
                and got.percent == e.cost.percent and got.power == e.cost.power
        end
        if not good then
            allGood = false
            if not detail then detail = e.text .. " -> " .. Fmt(got) end
        end
    end
    check("costs read as an amount or a percentage of base mana", allGood, detail)
end

--------------------------------------------------------------------------------
-- 7: cast lines read as seconds and a kind
--------------------------------------------------------------------------------
do
    local allGood = true
    local detail = nil
    for _, e in ipairs(fixture.casts) do
        local secs, kind = P.Cast(e.text)
        local good
        if e.secs == nil then
            good = secs == nil
        elseif e.instant then
            good = secs == 0 and kind == "instant"
        elseif e.channeled then
            good = secs == 0 and kind == "channeled"
        else
            good = secs == e.secs and kind == "cast"
        end
        if not good then
            allGood = false
            if not detail then detail = e.text .. " -> " .. tostring(secs) .. ", " .. tostring(kind) end
        end
    end
    check("cast lines read as seconds and a kind", allGood, detail)
end

--------------------------------------------------------------------------------
-- 8: rank texts read as a number or nil
--------------------------------------------------------------------------------
do
    local allGood = true
    local detail = nil
    for _, e in ipairs(fixture.ranks) do
        local got = P.Rank(e.text)
        if got ~= e.rank then
            allGood = false
            if not detail then detail = e.text .. " -> " .. tostring(got) end
        end
    end
    check("rank texts read as a number or nil", allGood, detail)
end

--------------------------------------------------------------------------------
-- 9: Total and Duration follow the text
--------------------------------------------------------------------------------
do
    local regrowth = P.Description("Heals a friendly target for 965 to 1,077 and another 994 over 21 sec.")
    local regrowthGood = regrowth ~= nil and P.Total(regrowth.heal) == 2015 and P.Duration(regrowth.heal) == 21

    local tranq = P.Description("Regenerates all nearby party members within 20 yards for 285 every 2 sec for 10 sec. Druid must channel to maintain the spell.")
    local tranqGood = tranq ~= nil and P.Total(tranq.heal) == 1425 and P.Duration(tranq.heal) == 10

    local noPeriodDur = P.Total({ tick = 25, period = 1 })
    local tickGood = noPeriodDur == nil

    local wrath = P.Description("Causes 15 to 18 Nature damage to the target.")
    local wrathGood = wrath ~= nil and P.Duration(wrath.damage) == nil

    check("Total and Duration follow the text",
        regrowthGood and tranqGood and tickGood and wrathGood,
        string.format("regrowth=%s tranq=%s tick=%s wrathDur=%s",
            tostring(regrowth and P.Total(regrowth.heal)), tostring(tranq and P.Total(tranq.heal)),
            tostring(noPeriodDur), tostring(wrath and P.Duration(wrath.damage))))
end

--------------------------------------------------------------------------------
-- 11 (T7b, m2 lines 91/154/161): the client's grammar escape is expanded and
-- a reactive damage clause is not a cast's damage
--------------------------------------------------------------------------------
do
    local motw1 = P.Clean("Increases the friendly target's armor by 34 for 1 |4hour:hrs;.")
    local motw1Good = motw1 == "Increases the friendly target's armor by 34 for 1 hour."

    local motw2 = P.Clean("Increases the friendly target's armor by 88 for 2 |4hour:hrs;.")
    local motw2Good = motw2 ~= nil and motw2:sub(-10) == "for 2 hrs."

    local bare = P.Clean("|4hour:hrs;")
    local bareGood = bare == "hrs"

    local thorns = P.Description(
        "Thorns sprout from the friendly target causing 4 Nature damage to attackers when hit. Lasts 10 min.")
    local thornsGood = thorns == nil

    check("the client's grammar escape is expanded and a reactive damage clause is not a cast's damage",
        motw1Good and motw2Good and bareGood and thornsGood,
        string.format("motw1=%q motw2=%q bare=%q thorns=%s",
            tostring(motw1), tostring(motw2), tostring(bare), Fmt(thorns)))
end

--------------------------------------------------------------------------------
-- 12 (review R35): a ward's absorb and a reactive aura's per-hit damage are
-- not a cast's damage either -- only "to attackers" (Thorns, item 11) was
-- refused before. Texts: talentsforever.com's data.json, source "beta
-- client 1.60.1.70009" (tools/.cache/talentsforever.json, spell_desc), the
-- rank 1 of each. Hammer of Wrath is the control: "strikes an enemy for N to
-- M Holy damage" is a cast's own damage and must still read.
--------------------------------------------------------------------------------
do
    local refused = {
        { "Frost Ward", "Absorbs 162 Frost damage. Lasts 30 sec." },
        { "Shadow Ward", "Absorbs 290 shadow damage. Lasts 30 sec." },
        { "Mana Shield", "Absorbs 120 physical damage, draining mana instead. Drains 2 mana per damage absorbed. Lasts 1 min." },
        { "Lightning Shield", "The caster is surrounded by 3 balls of lightning. When a spell, melee or ranged attack hits the caster, the attacker will be struck for 13 Nature damage. This expends one lightning ball. Only one ball will fire every few seconds. Lasts 10 min." },
        { "Retribution Aura", "Causes 7 Holy damage to any creature that strikes a party member within 30 yards. Players may only have one Aura on them per Paladin at any one time." },
        { "Fire Shield", "Surrounds the target in a shield of fire. Every strike against the target causes 5 Fire damage to the attacker. Lasts 3 min. Your pet cannot cast Fire Shield on itself." },
        { "Holy Shield", "Increases chance to block by 20% for 10 sec, and deals 110 Holy damage for each attack blocked while active. Damage caused by Holy Shield causes 20% additional threat. Each block expends a charge. 4 charges." },
        { "Touch of Weakness", "The next melee attack against the caster will cause 8 Shadow damage and reduce the attacker's melee attack power by 43 for 2 min." },
    }
    local bad = {}
    for _, r in ipairs(refused) do
        local got = P.Description(r[2])
        if got ~= nil and got.damage ~= nil then bad[#bad + 1] = r[1] .. "=" .. Fmt(got.damage) end
    end

    local hammer = P.Description("Hurls a hammer that strikes an enemy for 286 to 314 Holy damage. Only usable on enemies that have 20% or less health.")
    local hammerGood = hammer ~= nil and hammer.damage ~= nil and hammer.damage.min == 286 and hammer.damage.max == 314
        and hammer.damage.school == "Holy"

    check("a ward's absorb and a reactive aura's per-hit damage are not a cast's damage",
        #bad == 0 and hammerGood,
        string.format("read as damage: %s; hammer=%s", (#bad == 0) and "none" or table.concat(bad, ", "),
            Fmt(hammer and hammer.damage)))
end

--------------------------------------------------------------------------------
-- 13 (T91, docs/SPEC-next.md 4.2 P0 d): the description rows the fixture
-- names with `check` -- a decimal amount is one number, and a "your next"
-- sentence after the cast's own text leaves that text read. (Execute's
-- "15 additional damage" and Light's Vigil's "Your next Holy Shock ..." are
-- `refuse` rows: item 2b checks each.)
--------------------------------------------------------------------------------
for _, e in ipairs(fixture.descriptions) do
    if e.check then
        local got = P.Description(e.text)
        local good = got ~= nil and PartsEqual(e.heal, got.heal) and PartsEqual(e.damage, got.damage)
            and e.absorb == got.absorb
        check(e.check, good, string.format("%s -> heal %s damage %s", e.src,
            Fmt(got and got.heal), Fmt(got and got.damage)))
    end
end

-- A whole table, every key sorted, for the T91 rows below.
local function FmtTable(t)
    if type(t) ~= "table" then return tostring(t) end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(t[k]) end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Equal in both directions: every wanted field read, nothing else.
local function SameTable(want, got)
    if type(got) ~= "table" then return false end
    for k, v in pairs(want) do if got[k] ~= v then return false end end
    for k, v in pairs(got) do if want[k] ~= v then return false end end
    return true
end

-- Calls Parse[name] if the parser has it; a missing reader or a raise is
-- reported as such, never as a reading.
local function Try(name, text)
    local f = P[name]
    if type(f) ~= "function" then return false, "Parse." .. name .. " missing" end
    local okc, a, b = pcall(f, text)
    if not okc then return false, "raised: " .. tostring(a) end
    return true, a, b
end

--------------------------------------------------------------------------------
-- 14 (T91, 4.2 P1 / 4.5): whom a heal reaches, one check per fixture row --
-- the party (the target's, the caster's, with the range the text gives), a
-- chain with its count and falloff, the target and the caster, the caster
-- alone, one target with a lockout or a health condition; a wording no shape
-- claims is refused with a reason, never read as one target.
--------------------------------------------------------------------------------
for _, e in ipairs(fixture.targets) do
    local okt, got, why = Try("Targets", e.text)
    if not okt then got, why = nil, nil end
    if e.refuse then
        check("T91 targets, refused: " .. e.src, okt and got == nil and type(why) == "string",
            "got " .. FmtTable(got) .. " why " .. tostring(why))
    else
        check("T91 targets: " .. e.src .. " -> " .. FmtTable(e.want), okt and SameTable(e.want, got),
            "got " .. FmtTable(got) .. (why and (" why " .. tostring(why)) or ""))
    end
end

--------------------------------------------------------------------------------
-- 15 (T91): a tooltip line's right text reads as a cooldown in seconds, every
-- unit the export uses; any other right text is nil
--------------------------------------------------------------------------------
do
    local allGood, detail = true, nil
    for _, e in ipairs(fixture.cooldowns) do
        local okc, got = Try("Cooldown", e.text)
        if not okc or got ~= e.secs then
            allGood = false
            if not detail then
                detail = string.format("%q -> %s, want %s", e.text, tostring(got), tostring(e.secs))
            end
        end
    end
    check("T91: cooldown lines read as seconds; other right texts nil", allGood, detail)
end

--------------------------------------------------------------------------------
-- 16 (T91): the lockout phrase -- Power Word: Shield's "cannot be shielded
-- again for 15 sec" is 15; a text without one (Renew, Holy Shock) is nil
--------------------------------------------------------------------------------
do
    local ok1, pws = Try("Lockout", "Draws on the soul of the party member to shield them, absorbing 928 damage. Lasts 30 sec. While the shield holds, spellcasting will not be interrupted by damage. Once shielded, the target cannot be shielded again for 15 sec.")
    local ok2, renew = Try("Lockout", "Heals the target of 45 damage over 15 sec.")
    local ok3, shock = Try("Lockout", "Blasts the target with Holy energy, causing 129 to 139 Holy damage to an enemy, or 110 to 118 healing to an ally.")
    check("T91: the lockout phrase reads as seconds (PW:S 15), nil without one",
        ok1 and ok2 and ok3 and pws == 15 and renew == nil and shock == nil,
        string.format("pws=%s renew=%s shock=%s", tostring(pws), tostring(renew), tostring(shock)))
end

--------------------------------------------------------------------------------
-- 17 (T91, 4.2 P4): the two mana-source shapes, one check per fixture row --
-- "restores N mana every P sec" with the source's own duration, Innervate's
-- regeneration increase with what continues while casting; everything else
-- (a conversion, a drain, a shape missing a part) nil
--------------------------------------------------------------------------------
for _, e in ipairs(fixture.manaSources) do
    local okm, got = Try("ManaSource", e.text)
    if e.none then
        check("T91 mana source, none: " .. e.src, okm and got == nil, "got " .. FmtTable(got))
    else
        check("T91 mana source: " .. e.src .. " -> " .. FmtTable(e.want), okm and SameTable(e.want, got),
            "got " .. FmtTable(got))
    end
end

--------------------------------------------------------------------------------
-- 18 (T91): the new readers invent no number -- every count, range, percent,
-- amount and period they return is in the text (falloff is the text's percent
-- over 100, jumps its count less one, a duration the text's number times its
-- unit: each checked back against that number)
--------------------------------------------------------------------------------
do
    local allGood, detail = true, nil
    local function fail(msg)
        allGood = false
        if not detail then detail = msg end
    end
    local function need(src, field, n, allowed)
        if n ~= nil and not allowed[n] then fail(src .. ": " .. field .. "=" .. tostring(n) .. " not in text") end
    end
    local function needDur(src, d, allowed)
        if d == nil then return end
        for _, u in ipairs({ 1, 60, 3600 }) do if allowed[d / u] then return end end
        fail(src .. ": dur=" .. tostring(d) .. " is no number of the text in any unit")
    end
    for _, e in ipairs(fixture.targets) do
        local okt, t = Try("Targets", e.text)
        if not okt then fail(e.src .. ": " .. tostring(t))
        elseif type(t) == "table" then
            local allowed = NumbersIn(e.text)
            need(e.src, "range", t.range, allowed)
            need(e.src, "count", t.count, allowed)
            need(e.src, "belowPct", t.belowPct, allowed)
            need(e.src, "charges", t.charges, allowed)
            need(e.src, "lockout", t.lockout, allowed)
            need(e.src, "falloff*100", t.falloff and t.falloff * 100, allowed)
            need(e.src, "jumps+1", t.jumps and t.jumps + 1, allowed)
        end
    end
    for _, e in ipairs(fixture.manaSources) do
        local okm, m = Try("ManaSource", e.text)
        if not okm then fail(e.src .. ": " .. tostring(m))
        elseif type(m) == "table" then
            local allowed = NumbersIn(e.text)
            need(e.src, "mana", m.mana, allowed)
            need(e.src, "period", m.period, allowed)
            need(e.src, "regenPct", m.regenPct, allowed)
            need(e.src, "castingPct", m.castingPct, allowed)
            needDur(e.src, m.dur, allowed)
        end
    end
    check("T91: Targets and ManaSource invent no number", allGood, detail)
end

--------------------------------------------------------------------------------
-- 10: the Forever TOC loads Spells/Parse.lua before the UI
--------------------------------------------------------------------------------
do
    local function CheckToc(name)
        local files = _G.STUB.TocFiles(name)
        local coreIdx, parseIdx, uiIdx
        for i, f in ipairs(files) do
            if f == "Core_Forever.lua" then coreIdx = i end
            if f == "Spells/Parse.lua" then parseIdx = i end
            if f == "UI/Style.lua" then uiIdx = i end
        end
        return coreIdx ~= nil and parseIdx ~= nil and uiIdx ~= nil and coreIdx < parseIdx and parseIdx < uiIdx
    end
    local mainlineGood = CheckToc("SpellTuner_Mainline.toc")
    local plainGood = CheckToc("SpellTuner.toc")
    check("the Forever TOC loads Spells/Parse.lua before the UI", mainlineGood and plainGood)
end

--------------------------------------------------------------------------------
-- loose entries: report what the parser read, for the lead to decide on
--------------------------------------------------------------------------------
-- Fmt() is a part formatter; a loose entry's result is the whole
-- Description() table ({ heal, damage, absorb }), formatted one part at a
-- time so the lead sees exactly what would go into the fixture as a pin.
local function FmtResult(got)
    if got == nil then return "nil" end
    local bits = {}
    if got.heal ~= nil then bits[#bits + 1] = "heal=" .. Fmt(got.heal) end
    if got.damage ~= nil then bits[#bits + 1] = "damage=" .. Fmt(got.damage) end
    if got.absorb ~= nil then bits[#bits + 1] = "absorb=" .. tostring(got.absorb) end
    if #bits == 0 then return "nil" end
    return table.concat(bits, " ")
end

print()
for _, e in ipairs(fixture.descriptions) do
    if e.loose then
        local got = P.Description(e.text)
        print("loose " .. e.src .. ": " .. FmtResult(got))
    end
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
