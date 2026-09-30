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
    local funcs = { P.Clean, P.Description, P.Cost, P.Cast, P.Rank }
    local allGood = true
    local detail = nil
    local function tryAll(v, label)
        for _, f in ipairs(funcs) do
            local raised = not pcall(f, v)
            if raised then
                allGood = false
                if not detail then detail = "raised on " .. label end
            end
        end
    end
    for i, v in ipairs(weird) do tryAll(v, "weird[" .. i .. "]") end
    tryAll(nil, "nil")
    for _, e in ipairs(fixture.descriptions) do tryAll(e.text, e.src) end
    for _, e in ipairs(fixture.costs) do tryAll(e.text, e.text) end
    for _, e in ipairs(fixture.casts) do tryAll(e.text, e.text) end
    for _, e in ipairs(fixture.ranks) do tryAll(e.text, e.text) end
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
