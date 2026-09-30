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
-- The kit's shape, its validator, Snapshot and Restore (Engine/Kit.lua, listed
-- before this file by the module's TOCs; T63, P19).
local Kit = MD.Kit

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
    -- T63 (P19): a rank whose cast time the book could not read is a value
    -- missing like any other (Kit.Validate asks every type for a cast); the
    -- engine could not time it and Engine/Practice.lua refuses it.
    if type(be.cast) ~= "number" then e.dataMissing = true end

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

-- The index a kit is read with (MD.SpellData's fields), installed as a whole
-- by both paths below: a fresh build and a cached kit handed out again (so
-- whatever KitRestore installed meanwhile never outlives the next SpellKit).
local function InstallIndex(index)
    SD.spells, SD.families, SD.known, SD.all, SD.maxRank, SD.skipped =
        index.spells, index.families, index.known, index.all, index.maxRank, index.skipped
    -- The engine's own dashboard order (Data/SpellData.lua's familyOrder,
    -- minus the two excluded families) -- fixed, not derived from the book.
    SD.familyOrder = { "HealingTouch", "Rejuvenation", "Regrowth" }
    -- No Lifebloom on Forever (Facts), so no alias id for its bloom either.
    SD.bloomID = nil
end

-- T63 (P19, review A11): the kit is built once per spellbook generation
-- (Spells/Book.lua's Book.generation, bumped by every scan that changes an
-- entry) and crit reading -- the only input that is not in the book -- and
-- the same table is handed out while neither moves. Before, every call (ten
-- call sites, several per coach) rebuilt it and rewrote cdb.kit. A book table
-- without a generation (a caller's own) is never cached.
local cache = {}

local function Build(book, crit, critMissing)
    local spells, families, known, all, maxRank, skipped, bookByID = BuildIndex(book)
    local index = { spells = spells, families = families, known = known, all = all,
                    maxRank = maxRank, skipped = skipped }

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

    return Kit.Check(kit, "Kit_Forever SpellKit"), index
end

local function SpellKit(self, opts)
    local book = MD.Book:Get()
    local crit, critMissing = CritFraction()
    local gen = book.generation

    local rebuilt = false
    if gen == nil or cache.kit == nil or cache.generation ~= gen
        or cache.crit ~= crit or cache.critMissing ~= critMissing then
        cache.kit, cache.index = Build(book, crit, critMissing)
        cache.generation, cache.crit, cache.critMissing = gen, crit, critMissing
        rebuilt = true
    end
    InstallIndex(cache.index)

    -- The last kit this character built, kept for the offline tools
    -- (tools/import.lua): a recording made before recordings carried their
    -- own kit (Kit.Snapshot) is replayed offline with this one, and the tool
    -- says so. Written when the kit changed (T63) -- or into a character
    -- database it has not been written to yet -- never on every call.
    if MD.cdb and (rebuilt or cache.cdb ~= MD.cdb) then
        MD.cdb.kit = Kit.Snapshot(cache.kit)
        cache.cdb = MD.cdb
    end

    return cache.kit
end

--------------------------------------------------------------------------------
-- The kit as plain data (the recordings pipeline, docs/TOOLS.md section 2):
-- Kit.Snapshot (Engine/Kit.lua), the one record both clients keep, of `kit`
-- (default: the current SpellKit). Kept on every Forever pull and practice
-- fight at the moment it is stored (`rec.kit`) and as the last kit built
-- (cdb.kit), because the kit is built from the live spellbook and nothing
-- offline can rebuild it: the spellbook tools/import.lua would see is the
-- stub's. The MD.SpellData index is NOT copied: KitRestore rebuilds the part
-- a replay reads from the entries themselves.
--------------------------------------------------------------------------------
function RM.KitSnapshot(kit)
    return Kit.Snapshot(kit or RM:SpellKit())
end

-- A snapshot back into a kit AND the MD.SpellData index (Kit.Restore with
-- Forever's families, labels and plan exclusions), installed as SpellKit
-- installs its own. For the offline tools; the game never needs it.
local LABEL = {}
for name, key in pairs(FAMILY_KEY) do LABEL[key] = name end
local RESTORE_POLICY = { types = FAMILY_TYPE, labels = LABEL, exclude = { Tranquility = true } }

function RM.KitRestore(snap)
    local kit, index = Kit.Restore(snap, RESTORE_POLICY)
    InstallIndex(index)
    return kit
end

-- Only where no flavour has a kit of its own: this file must never replace
-- Engine/RankMath.lua's.
--
-- T59 (P15, review A6a): and with the kit, the practice policy this kit
-- implies (Engine/Practice.lua reads it as MD.Practice.policy; the TBC value
-- is that file's default). The kit is the live spellbook's, so a family can be
-- missing from it (`kitIsLive`); no bindings ship (the TBC defaults are the
-- TBC author's Cell click-casting); a recording is stamped "forever". Provided
-- here, before the Practice module loads (it needs this one), and only where
-- this file's kit is the kit.
if RM.SpellKit == nil then
    RM.SpellKit = SpellKit
    MD:Provide("PracticePolicy", { defaultBinds = {}, kitIsLive = true, client = "forever" })
end
