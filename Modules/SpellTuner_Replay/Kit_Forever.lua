-- T15 (docs/tasks/T15-kit-from-book.md): the engine's spell kit, built from
-- the spellbook Spells/Book.lua already read, instead of a hand-kept static
-- table (Data/SpellData.lua, TBC only). Reaches the client only through
-- MD.Book (already adapter-clean, T7) and MD.API -- nothing here ever indexes
-- a client table.
--
-- Only creates MD.SpellData / MD.RankMath if a flavour has not already
-- (Facts: neither exists before this module loads on Forever).
local _, MD = ...

if MD.SpellData == nil then MD.SpellData = {} end
if MD.RankMath == nil then MD.RankMath = {} end
local SD, RM = MD.SpellData, MD.RankMath

-- The book's own English name -> the engine's family key
-- (Engine/SimPlanner.lua 49, Engine/SimSolver.lua 212). Only Healing Touch
-- differs; every other modelled family is spelled the same both places.
local FAMILY_KEY = {
    ["Healing Touch"] = "HealingTouch",
    ["Regrowth"]       = "Regrowth",
    ["Rejuvenation"]   = "Rejuvenation",
    ["Swiftmend"]      = "Swiftmend",
    ["Tranquility"]    = "Tranquility",
}

-- family key -> the shape SimModel.lua switches on. Forever has no Lifebloom
-- and no Tree of Life (Facts), so those two shapes never appear here.
local FAMILY_TYPE = {
    HealingTouch = "direct",
    Regrowth     = "hybrid",
    Rejuvenation = "hot",
    Swiftmend    = "instant",
    Tranquility  = "channel",
}

-- Vanilla's tick period for a HoT is 3s (docs/REFERENCES-FOREVER.md);
-- UNVERIFIED on Forever -- the client's own text carries no tick period
-- ("48 over 12 sec"), only the total and the duration. /st measure (T12b)
-- infers the real period in game; docs/TESTING.md §38 asks for it.
local TICK_PERIOD = 3

-- The global cooldown (Facts, ported the same way Spells/Book.lua's own GCD
-- constant is -- to be checked against a real cast bar once one exists, T12).
local GCD = 1.5

-- Swiftmend's own description parses to nothing (no numbers at all -- "for an
-- amount equal to the full duration of the periodic effect"), so the book
-- files it kindless; picked up by name here, as TBC's static kit does
-- (SD.maxRank.Swiftmend).
local function BuildIndex(book)
    local spells, families, known, all, maxRank, skipped = {}, {}, {}, {}, {}, {}
    local bookByID = {}

    for _, name in ipairs(book.order or {}) do
        local fam = book.families[name]
        local key = FAMILY_KEY[name]
        if key then
            -- Tranquility is in the kit but not in the engine's plans, as on TBC.
            families[key] = { type = FAMILY_TYPE[key], label = name, exclude = (key == "Tranquility") or nil }
            known[key], all[key] = {}, {}
            for _, e in ipairs(fam.ranks) do
                if e.id and e.rank then
                    spells[e.id] = {
                        family = key, rank = e.rank,
                        cost = (type(e.cost) == "table") and e.cost.amount or nil,
                        cast = e.cast, level = e.level,
                    }
                    bookByID[e.id] = e
                    all[key][#all[key] + 1] = e.id
                    if e.known then known[key][#known[key] + 1] = e.id end
                end
            end
            local function ByRank(a, b) return spells[a].rank < spells[b].rank end
            table.sort(all[key], ByRank)
            table.sort(known[key], ByRank)
            local top = known[key][#known[key]]
            if top then maxRank[key] = top end
        elseif fam.kind == "heal" then
            -- A healing family the book found but the engine has no slot for
            -- (Wild Growth: a group HoT). Named so a caller can see what was
            -- left out, never guessed into a slot it does not fit.
            skipped[#skipped + 1] = name
        end
    end

    return spells, families, known, all, maxRank, skipped, bookByID
end

-- kit.crit = MD.API.SpellCritChance(4) (Nature) as a fraction, when plain;
-- else the last plain reading this session saw; else 0 with critMissing set.
-- Never the secret value itself (Client/API.lua's Call already refuses to
-- hand one back -- this only decides what to show instead).
local lastCrit
local function CritFraction()
    local crit = MD.API.SpellCritChance(4)
    if type(crit) == "number" then
        lastCrit = crit / 100
        return lastCrit, nil
    end
    if lastCrit ~= nil then return lastCrit, nil end
    return 0, true
end

-- One kit entry for a known rank, from the book's own numbers
-- (Spells/Book.lua's Rows already flattened entry.min/max/over/dur for
-- everything but Tranquility, whose shape survives only in entry.parsed.heal
-- -- Book:Rows never totals a tick shape into min/max/over/dur).
local function KitEntry(family, be, crit)
    local e = { family = family, rank = be.rank, type = FAMILY_TYPE[family], gcd = GCD }

    if type(be.cost) == "table" and type(be.cost.amount) == "number" then
        e.cost = be.cost.amount
    else
        e.dataMissing = true
    end
    e.cast, e.castBase = be.cast, be.cast

    if family == "HealingTouch" then
        if type(be.min) == "number" and type(be.max) == "number" then
            e.direct = (be.min + be.max) / 2
            e.directCrit = crit
        else
            e.dataMissing = true
        end
    elseif family == "Rejuvenation" then
        if type(be.over) == "number" and type(be.dur) == "number" and be.dur > 0 then
            e.ticks = be.dur / TICK_PERIOD
            e.tickPeriod, e.duration = TICK_PERIOD, be.dur
            e.tick = be.over / e.ticks
        else
            e.dataMissing = true
        end
    elseif family == "Regrowth" then
        local haveDirect = type(be.min) == "number" and type(be.max) == "number"
        local haveOver = type(be.over) == "number" and type(be.dur) == "number" and be.dur > 0
        if haveDirect and haveOver then
            e.direct = (be.min + be.max) / 2
            e.directCrit = crit
            e.ticks = be.dur / TICK_PERIOD
            e.tickPeriod, e.duration = TICK_PERIOD, be.dur
            e.tick = be.over / e.ticks
        else
            e.dataMissing = true
        end
    elseif family == "Tranquility" then
        local heal = type(be.parsed) == "table" and be.parsed.heal
        if type(heal) == "table" and type(heal.tick) == "number"
            and type(heal.period) == "number" and heal.period > 0
            and type(heal.periodDur) == "number" then
            e.channelTick = heal.tick
            e.channelTicks = heal.periodDur / heal.period
        else
            e.dataMissing = true
        end
    end
    -- Swiftmend ("instant"): no value fields of its own text at all -- priced
    -- below, once Rejuvenation and Regrowth are known.

    return e
end

local function SpellKit(self, opts)
    local book = MD.Book:Get()
    local spells, families, known, all, maxRank, skipped, bookByID = BuildIndex(book)

    SD.spells, SD.families, SD.known, SD.all, SD.maxRank, SD.skipped =
        spells, families, known, all, maxRank, skipped
    -- The engine's own dashboard order (Data/SpellData.lua's familyOrder,
    -- minus the two excluded families) -- fixed, not derived from the book.
    SD.familyOrder = { "HealingTouch", "Rejuvenation", "Regrowth" }
    -- No Lifebloom on Forever (Facts), so no alias id for its bloom either.
    SD.bloomID = nil

    local crit, critMissing = CritFraction()
    local kit = { caster = {}, tree = {}, crit = crit }
    if critMissing then kit.critMissing = true end
    local out = kit.caster

    for family, ids in pairs(known) do
        for _, id in ipairs(ids) do
            out[id] = KitEntry(family, bookByID[id], crit)
        end
    end

    -- Swiftmend eats the WHOLE remaining HoT on Forever (Facts: not TBC's
    -- 12s/18s caps) -- valued off the highest known rank of each, same
    -- reasoning as the TBC kit (Engine/RankMath.lua).
    local smID = maxRank.Swiftmend
    local sm = smID and out[smID]
    if sm then
        local rejuv = maxRank.Rejuvenation and out[maxRank.Rejuvenation]
        local regrowth = maxRank.Regrowth and out[maxRank.Regrowth]
        if rejuv and type(rejuv.tick) == "number" and type(rejuv.ticks) == "number" then
            sm.swiftmendRejuv = rejuv.tick * rejuv.ticks
        end
        if regrowth and type(regrowth.tick) == "number" and type(regrowth.ticks) == "number" then
            sm.swiftmendRegrowth = regrowth.tick * regrowth.ticks
        end
        sm.cast = 1.5
    end

    -- The last kit this character built, kept for the offline tools
    -- (tools/import.lua): a recording made before recordings carried their
    -- own kit (KitSnapshot below) is replayed offline with this one, and the
    -- tool says so. A few dozen plain numbers, rewritten on every build.
    if MD.cdb then MD.cdb.kit = RM.KitSnapshot(kit) end

    return kit
end

--------------------------------------------------------------------------------
-- The kit as plain data, for a SavedVariables file (the recordings pipeline,
-- docs/TOOLS.md §2): every entry of `kit` (default: a fresh SpellKit) and the
-- MD.SpellData index the engine reads names and families from, copied, with
-- the time and the character's level. Kept on every Forever recording and
-- practice fight at the moment it is stored (`rec.kit`), because the kit is
-- built from the live spellbook and nothing offline can rebuild it: the
-- spellbook tools/import.lua would see is the stub's. Pure copies; nothing
-- here reads the client.
--------------------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

function RM.KitSnapshot(kit)
    kit = kit or RM:SpellKit()
    return {
        at = time and time() or 0,
        level = MD.player and MD.player.level or 0,
        crit = kit.crit, critMissing = kit.critMissing,
        caster = Copy(kit.caster or {}),
        sd = { spells = Copy(SD.spells), families = Copy(SD.families), known = Copy(SD.known),
               all = Copy(SD.all), maxRank = Copy(SD.maxRank), skipped = Copy(SD.skipped),
               familyOrder = Copy(SD.familyOrder) },
    }
end

-- Only where no flavour has a kit of its own: this file must never replace
-- Engine/RankMath.lua's.
if RM.SpellKit == nil then RM.SpellKit = SpellKit end
