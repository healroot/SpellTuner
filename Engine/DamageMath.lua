-- Damage math for the spell tooltip (v0.15.3): what a druid's damage spell
-- actually does at THIS character's spell damage, crit and talents -- the same
-- job UI/Tooltip.lua's Tip:Spell does for heals, for Wrath, Starfire, Moonfire,
-- Insect Swarm and Hurricane.
--
-- WHERE THE BASE NUMBERS COME FROM. Not from this file. Data/SpellData.lua's
-- rule is that a spell value comes from the client or a measurement, never from
-- memory, and the heal table was verified that way; nobody has verified a
-- damage table. But the client already prints each rank's base damage in its
-- own tooltip -- TBC's spell tooltips are static, "Causes 278 to 312 Nature
-- damage", before any spell damage -- which is exactly the gap a Dynamic
-- Tooltip-style addon fills. So the base values are READ from the tooltip being
-- shown (DM.Parse), and only the rules that turn a base into a hit live here:
-- the coefficient, the talents, crit, the downrank penalty.
--
-- What IS from memory, and marked VERIFY until an in-game hit confirms it:
--   * the coefficient rules below are the SAME ones Engine/RankMath.lua uses for
--     heals (cast/3.5, duration/15, the amount-weighted hybrid split -- which
--     reproduces the community's Moonfire 0.15 / 0.52 exactly, as it reproduces
--     Regrowth's), plus a halving for a channelled area spell (Hurricane);
--     T117: all of them, the penalties included, are Spells/Coefficients.lua's
--     (the numbers unchanged);
--   * the DoT tick periods (Moonfire 3s, Insect Swarm 2s);
--   * the Balance talents in TALENTS.
-- A wrong one here costs a tooltip line, never a model number: nothing in the
-- engine, the planner or the recorder reads this file.
local _, MD = ...

local DM = {}
MD.DamageMath = DM

-- school ids as GetSpellBonusDamage / GetSpellCritChance take them
local NATURE, ARCANE = 4, 7

--   kind      direct | hybrid (a hit plus a DoT) | dot | channel
--   baseCast  the cast time the coefficient is taken from (instants are 1.5)
--   tick      seconds between DoT / channel ticks (VERIFY)
DM.families = {
    ["Wrath"]        = { school = NATURE, schoolName = "Nature", kind = "direct", baseCast = 2.0 },
    ["Starfire"]     = { school = ARCANE, schoolName = "Arcane", kind = "direct", baseCast = 3.5 },
    ["Moonfire"]     = { school = ARCANE, schoolName = "Arcane", kind = "hybrid", baseCast = 1.5, tick = 3 },
    ["Insect Swarm"] = { school = NATURE, schoolName = "Nature", kind = "dot",    baseCast = 1.5, tick = 2 },
    ["Hurricane"]    = { school = NATURE, schoolName = "Nature", kind = "channel", baseCast = 1.5, tick = 1, aoe = true },
}

-- The Balance talents that touch these spells, per rank. VERIFY.
--   mult     damage multiplier            coef   added to the spell damage coefficient
--   crit     added crit chance            vengeance  crit bonus +20% per rank
local TALENTS = {
    { name = "Moonfury",          per = 0.02, what = "mult", spells = { Wrath = true, Starfire = true, Moonfire = true } },
    { name = "Improved Moonfire", per = 0.05, what = "mult", spells = { Moonfire = true } },
    { name = "Improved Moonfire", per = 0.05, what = "crit", spells = { Moonfire = true } },
    { name = "Focused Starlight", per = 0.02, what = "crit", spells = { Wrath = true, Starfire = true } },
    { name = "Wrath of Cenarius", per = 0.04, what = "coef", spells = { Starfire = true } },
    { name = "Wrath of Cenarius", per = 0.02, what = "coef", spells = { Wrath = true } },
    { name = "Vengeance",         per = 0.20, what = "vengeance", spells = { Wrath = true, Starfire = true, Moonfire = true } },
}

function DM.Family(name)
    if type(name) ~= "string" then return nil end
    return DM.families[name] and name or nil
end

--------------------------------------------------------------------------------
-- Reading the base values out of the client's own description.
--   Wrath / Starfire  "Causes 278 to 312 Nature damage to the target."
--   Moonfire          "Burns the enemy for 305 to 357 Arcane damage and then an
--                      additional 600 Arcane damage over 12 sec."
--   Insect Swarm      "...causing 792 Nature damage over 12 sec."
--   Hurricane         "...causing 206 Nature damage to enemies every 1 sec...
--                      Lasts 10 sec."
-- Returns nil when the text does not carry what the family needs: a wrong
-- parse would print a confident wrong number, and no line at all is better.
--------------------------------------------------------------------------------
function DM.Parse(family, text)
    local f = DM.families[family]
    if not f or type(text) ~= "string" then return nil end
    local out = {}
    local lo, hi = text:match("(%d+) to (%d+)")
    if lo then out.min, out.max = tonumber(lo), tonumber(hi) end
    local dot, dur = text:match("(%d+) %a+ damage over (%d+) sec")
    if dot then out.dot, out.dur = tonumber(dot), tonumber(dur) end
    local tick, every = text:match("(%d+) %a+ damage[^%.]-every (%d+) sec")
    if tick then out.tickBase, out.every = tonumber(tick), tonumber(every) end
    local lasts = text:match("[Ll]asts (%d+) sec")
    if lasts then out.lasts = tonumber(lasts) end
    -- the cost line the client prints ("340 Mana"): the fallback when the live
    -- cost API has nothing for this id
    local mana = text:match("(%d+) Mana")
    if mana then out.mana = tonumber(mana) end

    if f.kind == "direct" and not out.min then return nil end
    if f.kind == "hybrid" and not (out.min and out.dot) then return nil end
    if f.kind == "dot" and not out.dot then return nil end
    if f.kind == "channel" and not (out.tickBase and out.lasts) then return nil end
    return out
end

--------------------------------------------------------------------------------
-- One rank, computed. `base` is DM.Parse's result; everything else is read
-- live. Same shape of answer as a RankMath row's calc, so the tooltip reads
-- both the same way.
--------------------------------------------------------------------------------
local function Live(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

function DM.Compute(spellID, family, base)
    local f = DM.families[family]
    if not (f and base) then return nil end
    local bonus = Live(GetSpellBonusDamage, f.school) or 0
    local crit = (Live(GetSpellCritChance, f.school) or 0) / 100

    -- talents
    local mult, coefAdd, critAdd, vengeance = 1, 0, 0, 0
    local used = {}
    for _, t in ipairs(TALENTS) do
        if t.spells[family] then
            local r = MD:TalentRank(t.name)
            if r > 0 then
                if t.what == "mult" then mult = mult * (1 + t.per * r)
                elseif t.what == "coef" then coefAdd = coefAdd + t.per * r
                elseif t.what == "crit" then critAdd = critAdd + t.per * r
                elseif t.what == "vengeance" then vengeance = t.per * r end
                used[#used + 1] = string.format("%s %d", t.name, r)
            end
        end
    end
    crit = math.min(1, crit + critAdd)
    local critMult = 1 + 0.5 * (1 + vengeance)

    -- downranking: the same penalty as a heal, if the client says the rank's level
    local C = MD.Coefficients
    local level = Live(GetSpellLevelLearned, spellID)
    local pen, penKnown = 1, false
    local player = MD.player and MD.player.level or 70
    if level and level > 0 then
        penKnown = true
        pen = C.Penalty(level, player)
    end

    local c = { family = family, school = f.schoolName, bonus = bonus, crit = crit, critMult = critMult,
                mult = mult, coefAdd = coefAdd, talents = used, penalty = pen, penaltyKnown = penKnown,
                level = level, kind = f.kind, aoe = f.aoe }

    local cDirect = C.Direct(f.baseCast)
    if f.kind == "direct" then
        c.coef = cDirect + coefAdd
        c.add = bonus * c.coef * pen
        c.min, c.max = (base.min + c.add) * mult, (base.max + c.add) * mult
        c.avg = (c.min + c.max) / 2
        c.total = c.avg
        c.expected = c.avg * (1 + crit * (critMult - 1))
    elseif f.kind == "hybrid" then
        local avgBase = (base.min + base.max) / 2
        local dCoef, hCoef = C.Hybrid(f.baseCast, base.dur, avgBase, base.dot)
        c.coef = dCoef + coefAdd
        c.dotCoef = hCoef
        c.add = bonus * c.coef * pen
        c.dotAdd = bonus * c.dotCoef * pen
        c.min, c.max = (base.min + c.add) * mult, (base.max + c.add) * mult
        c.avg = (c.min + c.max) / 2
        c.dotTotal = (base.dot + c.dotAdd) * mult
        c.dur, c.every = base.dur, f.tick
        c.ticks = math.floor(base.dur / f.tick + 0.5)
        c.tick = c.dotTotal / c.ticks
        c.total = c.avg + c.dotTotal
        -- the DoT never crits
        c.expected = c.avg * (1 + crit * (critMult - 1)) + c.dotTotal
    elseif f.kind == "dot" then
        c.dotCoef = C.Hot(base.dur)
        c.dotAdd = bonus * c.dotCoef * pen
        c.dotTotal = (base.dot + c.dotAdd) * mult
        c.dur, c.every = base.dur, f.tick
        c.ticks = math.floor(base.dur / f.tick + 0.5)
        c.tick = c.dotTotal / c.ticks
        c.total, c.expected = c.dotTotal, c.dotTotal
    elseif f.kind == "channel" then
        -- a channelled area spell: duration/3.5, halved for hitting everything
        c.ticks = math.floor(base.lasts / base.every + 0.5)
        c.dotCoef = C.Channel(base.lasts, f.aoe)
        c.dotAdd = bonus * c.dotCoef * pen
        c.tick = (base.tickBase + c.dotAdd / c.ticks) * mult
        c.dotTotal = c.tick * c.ticks
        c.dur, c.every = base.lasts, base.every
        c.total, c.expected = c.dotTotal, c.dotTotal
    end

    -- cost and time: the live cost; the cast the client reports now (talents
    -- that shorten it included), else the base; Nature's Grace averaged in the
    -- way the heal tooltip averages it
    c.cost = (MD.SpellData and MD.SpellData:GetCost(spellID)) or base.mana or 0
    local cast
    if GetSpellInfo then
        -- name, rank, icon, castTime (ms) -- pcall puts its own flag first
        local ok, _, _, _, castMs = pcall(GetSpellInfo, spellID)
        if ok and type(castMs) == "number" and castMs > 0 then cast = castMs / 1000 end
    end
    if f.kind == "channel" then cast = base.lasts
    elseif not cast then cast = (f.kind == "direct") and f.baseCast or 1.5 end
    if cast < 1.5 then cast = 1.5 end
    c.cast = cast
    local ctx = MD.RankMath and MD.RankMath:Context({ live = true })
    c.castAvg = (ctx and f.kind == "direct") and ctx.ExpectedCast(cast, crit) or cast
    c.dpm = c.cost > 0 and c.expected / c.cost or nil
    c.dps = c.expected / c.castAvg
    return c
end
