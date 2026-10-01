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

-- T89 (docs/SPEC-next.md 2.1): every table below that names a family is the
-- druid profile's (Data/Profile_Druid_Forever.lua), derived at file load BY
-- NAME -- never from MD.ClassProfile, the logged-in player's: the kit a druid's
-- book builds is the druid's whoever reads it. Each equals the constant it
-- replaced (tools/profilecheck.lua).
local DRUID = MD.Profiles.Require("DRUID", "Kit_Forever.lua")

-- T96 (docs/SPEC-next.md 2.1, S1 step 2): the kit carries the profile it was
-- built by -- the one its families come from (the druid's, by name, above) --
-- so the engine reads that profile's HoT slots and families
-- (MD.Profiles.ForKit), never the logged-in player's.
local KIT_PROFILE = DRUID.class

-- The book's own English name -> the engine's family key
-- (Engine/SimPlanner.lua 49, Engine/SimSolver.lua 212). Only Healing Touch
-- differs; every other modelled family is spelled the same both places:
-- Healing Touch -> HealingTouch; Regrowth, Rejuvenation, Swiftmend and
-- Tranquility -> themselves.
local FAMILY_KEY = DRUID:FamilyKeys()

-- family key -> the shape SimModel.lua switches on. Forever has no Lifebloom
-- and no Tree of Life (Facts), so those two shapes never appear here:
-- HealingTouch direct, Regrowth hybrid, Rejuvenation hot, Swiftmend instant,
-- Tranquility channel.
local FAMILY_TYPE = DRUID:KitTypes()

-- The families in the kit but not in the engine's plans (Tranquility, as on
-- TBC): the profile's `exclude` marks.
local EXCLUDE = {}
for key, def in pairs(DRUID.families) do
    if def.exclude then EXCLUDE[key] = true end
end

-- The engine's own dashboard order (Data/SpellData.lua's familyOrder on TBC,
-- minus the two excluded families and Lifebloom): HealingTouch, Rejuvenation,
-- Regrowth.
local FAMILY_ORDER = DRUID.order

-- The school whose crit chance the kit's direct heals take (Nature).
local CRIT_SCHOOL = DRUID.critSchool

-- For tools/profilecheck.lua, which holds them equal to the old constants.
RM.FAMILY_KEY, RM.FAMILY_TYPE = FAMILY_KEY, FAMILY_TYPE

-- Vanilla's tick period for a HoT is 3s (docs/REFERENCES-FOREVER.md);
-- UNVERIFIED on Forever -- the client's own text carries no tick period
-- ("48 over 12 sec"), only the total and the duration. /st measure (T12b)
-- infers the real period in game; docs/TESTING.md §38 asks for it.
local TICK_PERIOD = 3
-- T101 (docs/SPEC-next.md 4.2 P2): a duration that is no multiple of 3 s
-- (Wild Growth's 7 s) ticks every whole second instead -- the total spread
-- evenly, UNIFORM ticks (VERIFY: docs/REFERENCES-FOREVER.md 4 says Wild
-- Growth ticks every 1 s and front-loads them; the curve is not in the text,
-- so none is invented). Every duration the druid's own HoTs have (12, 15,
-- 21 s) keeps the 3 s ticks.
local FINE_TICK_PERIOD = 1

-- The global cooldown (Facts, ported the same way Spells/Book.lua's own GCD
-- constant is -- to be checked against a real cast bar once one exists, T12).
local GCD = 1.5

--------------------------------------------------------------------------------
-- T101 (docs/SPEC-next.md 2.1, 4.2 P2, 4.5): the kit is the LOGGED-IN
-- player's (2.1: the live kit builder is one of the three readers of the
-- logged-in profile) -- the registered profile of MD.player.class, else the
-- generic one -- and it is built from the book in two ways:
--   * the families the profile names, by name, with the profile's kit type
--     (the druid's exactly as before: FAMILY_KEY / FAMILY_TYPE above are its);
--   * every other HEAL family the book reads, by SHAPE: what its highest
--     known rank's own text says it is and whom it reaches (Spells/Book.lua's
--     entry.targets, Parse.Targets) --
--       single target   direct, hot, hybrid (or a channel) as the text reads
--       the party       group (a direct part, a HoT part or both); a channel
--                       over the party stays a channel with `party`
--       a chain         chain (its jumps and falloff from the text)
--       the target and the caster   selfAndTarget
--     keyed by its name without spaces or punctuation ("Prayer of Healing"
--     -> PrayerOfHealing), labelled by its name. What no type models is
--     named in SD.skipped instead of guessed into one: an absorb (T109), a
--     heal on the caster alone, one only below a health line or with charges,
--     a reach the parser refused.
-- A profile carries names and types only; a number is always the text's.
--------------------------------------------------------------------------------
local function LiveProfile()
    local class = MD.player and MD.player.class
    if type(class) ~= "string" or class == "" then return DRUID, DRUID.class end
    local p = MD.Profiles.byClass[class]
    if p then return p, class end
    return MD.Profiles.Get(class), class
end

-- "Prayer of Healing" -> "PrayerOfHealing", "Light's Vigil" -> "LightsVigil"
local function KeyOf(name)
    local key = name:gsub("'", ""):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
    return (key:gsub("[^%w]", ""))
end
RM.KeyOf = KeyOf

-- A key back into words, for a restored snapshot (which carries no names):
-- "WildGrowth" -> "Wild Growth". The live index carries the book's own name.
local function WordsOf(key)
    return (tostring(key):gsub("(%l)(%u)", "%1 %2"))
end

-- The kit type a heal family the profile does not name is modelled as, from
-- its highest known rank's text -- or nil and why not.
local function ShapeOf(fam)
    local e = fam.maxKnown
    if not e then
        for _, r in ipairs(fam.ranks or {}) do
            if type(r.parsed) == "table" and r.parsed.heal ~= nil then e = r; break end
        end
    end
    if not e then return nil, "no rank read" end
    local heal = type(e.parsed) == "table" and e.parsed.heal
    if type(heal) ~= "table" then return nil, "an absorb" end
    if e.targets == nil then return nil, "a reach the text does not say plainly" end
    local reach = e.reach or {}
    if reach.belowPct or reach.charges then return nil, "a condition no kit type models" end
    local channel = e.castKind == "channeled" and heal.tick ~= nil
    local shape = fam.shape
    local t = e.targets
    if t == "caster" then return nil, "a heal on the caster alone" end
    if t == "party" then
        if channel then return "channel" end
        if shape == "direct" or shape == "hot" or shape == "hybrid" then return "group" end
    elseif t == "chain" then
        if shape == "direct" then return "chain" end
    elseif t == "selfAndTarget" then
        if shape == "direct" then return "selfAndTarget" end
    elseif t == "single" then
        if channel then return "channel" end
        if shape == "direct" or shape == "hot" or shape == "hybrid" then return shape end
    end
    return nil, "a shape no kit type models"
end

-- Swiftmend's own description parses to nothing (no numbers at all -- "for an
-- amount equal to the full duration of the periodic effect"), so the book
-- files it kindless; picked up by name here, as TBC's static kit does
-- (SD.maxRank.Swiftmend).
local function BuildIndex(book, prof)
    local spells, families, known, all, maxRank, skipped = {}, {}, {}, {}, {}, {}
    local bookByID = {}
    local keyOf, typeOf = prof:FamilyKeys(), prof:KitTypes()
    local defs = prof.families or {}
    local order = {}
    for i, key in ipairs(prof.order or {}) do order[i] = key end
    local byShape = {}

    for _, name in ipairs(book.order or {}) do
        local fam = book.families[name]
        local key, ktype = keyOf[name], nil
        if key then
            ktype = typeOf[key]
        elseif fam.kind == "heal" then
            ktype = ShapeOf(fam)
            key = ktype and KeyOf(name) or nil
            if key and (families[key] or defs[key]) then key = nil end
            if key then byShape[#byShape + 1] = key end
        end
        if key then
            -- Tranquility is in the kit but not in the engine's plans, as on TBC.
            local def = defs[key]
            families[key] = { type = ktype, label = name, exclude = (def and def.exclude) or nil }
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
            -- A healing family the book found but no kit type models (an
            -- absorb, a heal on the caster alone, ...). Named so a caller can
            -- see what was left out, never guessed into a type it does not fit.
            skipped[#skipped + 1] = name
        end
    end
    -- the profile's dashboard order, then the families read by shape
    table.sort(byShape)
    for _, key in ipairs(byShape) do order[#order + 1] = key end

    return spells, families, known, all, maxRank, skipped, bookByID, order
end

-- kit.crit = MD.API.SpellCritChance(4) (Nature) as a fraction, when plain;
-- else the last plain reading this session saw; else 0 with critMissing set.
-- Never the secret value itself (Client/API.lua's Call already refuses to
-- hand one back -- this only decides what to show instead).
local lastCrit
local function CritFraction(school)
    local crit = MD.API.SpellCritChance(school or CRIT_SCHOOL)
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
--
-- T96 (docs/SPEC-next.md 2.1, R-arch 3.2): the value fields are filled by the
-- family's KIT TYPE (the profile's `kit`), not by its name: KitEntryFor[type]
-- (e, be, crit, def) writes them, or marks the entry dataMissing. A family
-- whose type has no filler carries only its cost and cast (Swiftmend's
-- "instant": no value of its own text at all -- priced below, once Rejuvenation
-- and Regrowth are known). A family's own cooldown (the profile's) is copied
-- onto every rank: the engine's per-family cooldown (SM.CooldownOf).
local function ReadDirect(e, be, crit)
    if type(be.min) == "number" and type(be.max) == "number" then
        e.direct = (be.min + be.max) / 2
        e.directCrit = crit
        return true
    end
    return false
end

local function ReadOver(e, be)
    if type(be.over) == "number" and type(be.dur) == "number" and be.dur > 0 then
        local period = TICK_PERIOD
        if be.dur % TICK_PERIOD ~= 0 and be.dur % FINE_TICK_PERIOD == 0 then period = FINE_TICK_PERIOD end
        e.ticks = be.dur / period
        e.tickPeriod, e.duration = period, be.dur
        e.tick = be.over / e.ticks
        return true
    end
    return false
end

local KitEntryFor = {
    direct = function(e, be, crit)
        if not ReadDirect(e, be, crit) then e.dataMissing = true end
    end,
    hot = function(e, be)
        if not ReadOver(e, be) then e.dataMissing = true end
    end,
    hybrid = function(e, be, crit)
        local haveDirect = type(be.min) == "number" and type(be.max) == "number"
        local haveOver = type(be.over) == "number" and type(be.dur) == "number" and be.dur > 0
        if haveDirect and haveOver then
            ReadDirect(e, be, crit)
            ReadOver(e, be)
        else
            e.dataMissing = true
        end
    end,
    -- T96 (decision 11): the channel lands its ticks in the engine, one every
    -- `tickPeriod` -- the text's own period ("98 every 2 sec for 10 sec").
    channel = function(e, be)
        local heal = type(be.parsed) == "table" and be.parsed.heal
        if type(heal) == "table" and type(heal.tick) == "number"
            and type(heal.period) == "number" and heal.period > 0
            and type(heal.periodDur) == "number" then
            e.channelTick = heal.tick
            e.channelTicks = heal.periodDur / heal.period
            e.tickPeriod = heal.period
        else
            e.dataMissing = true
        end
    end,
    -- T101 (4.5): a heal on every living member of the caster's party -- a
    -- direct part (Prayer of Healing, Holy Nova), a HoT part (Wild Growth) or
    -- both; each member's amount is the text's, never multiplied here
    group = function(e, be, crit)
        local direct = ReadDirect(e, be, crit)
        local over = ReadOver(e, be)
        if not (direct or over) then e.dataMissing = true end
    end,
    -- T101 (4.5): the target, then the reach's jumps at its falloff (Chain
    -- Heal: 2 jumps, 50 %)
    chain = function(e, be, crit)
        local reach = type(be.reach) == "table" and be.reach or {}
        if ReadDirect(e, be, crit) and type(reach.jumps) == "number" and type(reach.falloff) == "number" then
            e.jumps, e.falloff = reach.jumps, reach.falloff
        else
            e.dataMissing = true
        end
    end,
    -- T101 (4.5): the target and the caster (Binding Heal)
    selfAndTarget = function(e, be, crit)
        if not ReadDirect(e, be, crit) then e.dataMissing = true end
    end,
}
-- For tools/kitcheck.lua (one filler per kit type the druid profile names).
RM.KitEntryFor = KitEntryFor

local function KitEntry(family, be, crit, def, ktype)
    local e = { family = family, rank = be.rank, type = ktype, gcd = GCD }

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

    local fill = ktype and KitEntryFor[ktype]
    if fill then fill(e, be, crit, def) end
    -- T101: a channel whose text reaches the party lands on all of it (4.5)
    if ktype == "channel" and be.targets == "party" then e.party = true end
    -- the profile's cooldown (Swiftmend's 15), else the book's own (T95: the
    -- tooltip line -- Holy Shock 10 s, Riptide 6 s): the engine's per-family
    -- cooldown (SM.CooldownOf), which a plan and a practice press respect
    if def and def.cooldown then
        e.cooldown = def.cooldown
    elseif type(be.cooldown) == "number" and be.cooldown > 0 then
        e.cooldown = be.cooldown
    end

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
    -- (T89: the druid profile's `order`, copied fresh as before. T101: the
    -- kit's profile's, then the families read by shape; a restored
    -- snapshot's index carries none and takes the druid's.)
    local order = {}
    for i, key in ipairs(index.order or FAMILY_ORDER) do order[i] = key end
    SD.familyOrder = order
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

local function Build(book, crit, critMissing, prof, stamp)
    local spells, families, known, all, maxRank, skipped, bookByID, order = BuildIndex(book, prof)
    local index = { spells = spells, families = families, known = known, all = all,
                    maxRank = maxRank, skipped = skipped, order = order }

    -- T101: stamped with the class whose profile (or, with no profile file,
    -- whose book by shape) the families came from -- "DRUID" for a druid
    local kit = { caster = {}, tree = {}, crit = crit, profile = stamp or KIT_PROFILE }
    if critMissing then kit.critMissing = true end
    local out = kit.caster
    local defs = prof.families or {}

    for family, ids in pairs(known) do
        local ktype = families[family] and families[family].type
        for _, id in ipairs(ids) do
            out[id] = KitEntry(family, bookByID[id], crit, defs[family], ktype)
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
    local prof, stamp = LiveProfile()
    local crit, critMissing = CritFraction(prof.critSchool)
    local gen = book.generation

    local rebuilt = false
    if gen == nil or cache.kit == nil or cache.generation ~= gen
        or cache.crit ~= crit or cache.critMissing ~= critMissing
        or cache.profile ~= prof or cache.stamp ~= stamp then
        cache.kit, cache.index = Build(book, crit, critMissing, prof, stamp)
        cache.generation, cache.crit, cache.critMissing = gen, crit, critMissing
        cache.profile, cache.stamp = prof, stamp
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
-- T101: every entry under its own type (a snapshot of a priest's kit, or of a
-- druid's Wild Growth, keeps its families in the index -- a druid's families
-- carry exactly FAMILY_TYPE's types, so a druid snapshot restores as before),
-- labelled by the druid's names, else by its key in words.
local LABEL = setmetatable({}, { __index = function(_, key) return WordsOf(key) end })
for name, key in pairs(FAMILY_KEY) do LABEL[key] = name end
local RESTORE_POLICY = { labels = LABEL, exclude = EXCLUDE }

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
--
-- T96 (docs/SPEC-next.md 2.1, 4.4): and MD.KitLive() -> true, n | false, "kit"
-- -- whether the live kit prices at least one heal (n: how many ranks), the
-- Forever half of MD.ClassProfile:Can("coach") (T99 asks it). Provided only
-- here, in the LoadOnDemand Replay module: with the module off there is no
-- provider, and the caller says the module is off.
local function PricesAHeal(e)
    if type(e) ~= "table" or e.dataMissing then return false end
    if EXCLUDE[e.family] or Kit.UNPRICED[e.family] then return false end
    return (e.direct or 0) > 0 or ((e.tick or 0) > 0 and (e.ticks or 0) > 0)
        or (e.channelTick or 0) > 0
        or (e.swiftmendRejuv or 0) > 0 or (e.swiftmendRegrowth or 0) > 0
end

local function KitLive()
    local built, kit = pcall(RM.SpellKit, RM)
    if not built or type(kit) ~= "table" then return false, "kit" end
    local n = 0
    for _, e in pairs(kit.caster or {}) do
        if PricesAHeal(e) then n = n + 1 end
    end
    if n > 0 then return true, n end
    return false, "kit"
end

if RM.SpellKit == nil then
    RM.SpellKit = SpellKit
    MD:Provide("PracticePolicy", { defaultBinds = {}, kitIsLive = true, client = "forever" })
    MD:Provide("KitLive", KitLive)
end
