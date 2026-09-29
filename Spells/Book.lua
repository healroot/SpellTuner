-- T7 (docs/tasks/T7-spell-book.md, M2 of docs/ROADMAP-FOREVER.md): the
-- spellbook, read only through MD.API, grouped into families of ranks with
-- the numbers a healer compares ranks by. Forever TOCs only -- reaches the
-- client only through MD.API and never indexes a client table (every value
-- Book reads is either a plain scalar Has/Call already cleared, or a field
-- of a table MD.API.Copy already built, never the client's own table).
local _, MD = ...
local Parse = MD.Parse

MD.Book = MD.Book or {}
local Book = MD.Book

-- The global cooldown, same constant Engine/RankMath.lua's TBC dashboard
-- uses (1.5s) -- ported as-is (Facts), to be checked against a real cast bar
-- once one exists to read (T12).
local GCD = 1.5

-- The suggested-rank floor (Facts, ported from Engine/RankMath.lua's
-- Compute()): below 40% of the highest known rank's value, cast-count
-- pressure is assumed to outweigh efficiency.
local SUGGESTED_FLOOR = 0.4

-- The book walk the probe proved (Facts): only when every skill line's own
-- copy answers numeric bounds is the line-based read trusted; anything else
-- (a missing function, a non-numeric bound, `numLines` out of 1..20) falls
-- back to the 1..500 walk the probe also proved.
local MIN_LINES, MAX_LINES = 1, 20
local MAX_WALK_SLOT = 500

--------------------------------------------------------------------------------
-- The talent seam (Q6, Facts): empty. The client's own spell text is assumed
-- to carry every talent it applies (a heal's numbers already move with the
-- caster's talents, same as with level and gear -- Q1). If a level-10+ probe
-- report ever shows a talent that changes a spell's effect WITHOUT changing
-- its description, that talent's own adjustment is added here, as one more
-- function(entry, family) in this list, and nowhere else in Book.
--------------------------------------------------------------------------------
Book.adjust = {}

--------------------------------------------------------------------------------
-- Small helpers -- every one reads only what MD.API already handed out plain.
--------------------------------------------------------------------------------

-- The tooltip data's own cast/cost lines are read by pattern, not by a fixed
-- line index: the shape past the book walk itself is UNVERIFIED (Facts), so
-- assuming "the cast line is line 3" would be one more guess Book cannot
-- afford. Parse.Cast/Parse.Cost are anchored (^...$), so a description or
-- name line never matches either by accident.
local function TooltipCastInfo(tip)
    if type(tip) ~= "table" or type(tip.lines) ~= "table" then return nil, nil end
    for _, line in ipairs(tip.lines) do
        if type(line) == "table" and type(line.leftText) == "string" then
            local secs, kind = Parse.Cast(line.leftText)
            if secs ~= nil then return secs, kind end
        end
    end
    return nil, nil
end

-- Review R13: the powers a cost line or a cost row can name besides mana.
-- A spell that costs one of these costs NO mana -- it is "free" as far as
-- the mana pool goes (the clock spends nothing, no per mana, no casts to
-- OOM), and keeps what it does cost as cost.power / cost.powerAmount for
-- the pane and the tooltip to name. Type numbers: Enum.PowerType (retail
-- 12.x documented, the same table that makes mana type 0 -- Facts); the
-- words are the tooltip cost lines of talentsforever's beta client
-- 1.60.1.70009 descriptions ("10 Rage", "25 Focus", "45 Energy").
local OTHER_POWER_BY_TYPE = { [1] = "Rage", [2] = "Focus", [3] = "Energy" }
local OTHER_POWER_WORD = { Rage = true, Focus = true, Energy = true }

local function NoManaCost(power, amount)
    return { free = true, power = power, powerAmount = amount }
end

-- The first tooltip line that is a cost: a mana one as Parse.Cost reads it,
-- a Rage / Focus / Energy one as no mana; any other "N Word" line is not a
-- cost line at all and the walk goes on.
local function TooltipCostInfo(tip)
    if type(tip) ~= "table" or type(tip.lines) ~= "table" then return nil end
    for _, line in ipairs(tip.lines) do
        if type(line) == "table" and type(line.leftText) == "string" then
            local cost = Parse.Cost(line.leftText)
            if cost ~= nil then
                if cost.power == "Mana" then return cost end
                if OTHER_POWER_WORD[cost.power] and type(cost.amount) == "number" then
                    return NoManaCost(cost.power, cost.amount)
                end
            end
        end
    end
    return nil
end

local function HasTickPart(parsed)
    if type(parsed) ~= "table" then return false end
    if type(parsed.heal) == "table" and parsed.heal.tick ~= nil then return true end
    if type(parsed.damage) == "table" and parsed.damage.tick ~= nil then return true end
    return false
end

-- The mana-type cost row ({type, cost, costPercent, ...}); Facts: "mana is
-- type == 0".
local function ManaCostEntry(list)
    for _, e in ipairs(list) do
        if type(e) == "table" and e.type == 0 then return e end
    end
    return nil
end

-- Review R13: a list with no mana row but a Rage / Focus / Energy row with a
-- plain cost is a spell that costs no mana.
local function OtherPowerEntry(list)
    for _, e in ipairs(list) do
        if type(e) == "table" and type(e.type) == "number" and OTHER_POWER_BY_TYPE[e.type]
            and type(e.cost) == "number" and e.cost > 0 then
            return e
        end
    end
    return nil
end

-- cost, costState -- Rule (Facts, == shapes item 5): an amount from the mana
-- entry's cost when > 0, plus a percent from costPercent when > 0; {free =
-- true} for an empty cost list OR a call that returned no value and no
-- reason at all (m2 lines 252-259, 274-285: every no-cost spell in the book
-- returned nothing, never an empty list) -- else the tooltip data's own cost
-- line; else nil/"absent". Review R13: a Rage / Focus / Energy cost, from
-- either place, is "free" with cost.power / cost.powerAmount -- never an
-- amount of mana.
local function ResolveCost(list, listReason, tip)
    if listReason == "secret" then return nil, "secret" end
    if list == nil and listReason == nil then return { free = true }, "free" end
    if type(list) == "table" then
        if #list == 0 then return { free = true }, "free" end
        local mana = ManaCostEntry(list)
        if mana then
            local cost = {}
            if type(mana.cost) == "number" and mana.cost > 0 then cost.amount = mana.cost end
            if type(mana.costPercent) == "number" and mana.costPercent > 0 then cost.percent = mana.costPercent end
            if cost.amount ~= nil or cost.percent ~= nil then return cost, "ok" end
        else
            local other = OtherPowerEntry(list)
            if other then return NoManaCost(OTHER_POWER_BY_TYPE[other.type], other.cost), "free" end
        end
    end
    local fromTip = TooltipCostInfo(tip)
    if fromTip ~= nil then
        if fromTip.free then return fromTip, "free" end
        return fromTip, "ok"
    end
    return nil, "absent"
end

-- The chain-cast interval a rank's per-second and casts-to-OOM numbers are
-- computed against (Facts): the part's own periodDur for a channel, the
-- max(cast, GCD) chain interval for a direct/hybrid spell (one with a
-- min/max), else the part's own dur for a pure over-time spell. An absorb
-- (no part table at all) has no HoT shape to read, so it is treated as the
-- direct/hybrid case -- one instant effect, same as a direct heal.
local function IntervalFor(entry, part)
    if entry.castKind == "channeled" then
        return part and part.periodDur or nil
    end
    if part and (part.min ~= nil or part.max ~= nil) then
        return math.max(entry.cast or 0, GCD)
    end
    if part and part.dur ~= nil then
        return part.dur
    end
    return math.max(entry.cast or 0, GCD)
end

-- value, part -- what a rank's numbers are computed from: the family's own
-- kind names which half of Parse.Description's result is the relevant part
-- (Facts); an absorb has no part table, only a plain amount.
local function PartValue(entry, familyKind)
    if type(entry.parsed) ~= "table" then return nil, nil end
    if familyKind == "heal" then
        if entry.parsed.heal ~= nil then return Parse.Total(entry.parsed.heal), entry.parsed.heal end
        if entry.parsed.absorb ~= nil then return entry.parsed.absorb, nil end
    elseif familyKind == "damage" then
        if entry.parsed.damage ~= nil then return Parse.Total(entry.parsed.damage), entry.parsed.damage end
    end
    return nil, nil
end

-- Facts, ported from Engine/RankMath.lua's CastsToOOM: inf when the spell is
-- free or regen alone covers the chain, 0 when the pool cannot afford even
-- one cast, else the floor of the chain plus the first cast. nil when any
-- input Book needs is itself missing -- never guessed at 0.
local function CastsToOOM(cost, interval, mana, regen)
    if cost == nil or interval == nil or mana == nil or regen == nil then return nil end
    if cost <= 0 then return math.huge end
    local net = cost - regen * interval
    if net <= 0 then return math.huge end
    if mana < cost then return 0 end
    return math.floor((mana - cost) / net) + 1
end

--------------------------------------------------------------------------------
-- Enumeration
--------------------------------------------------------------------------------

-- via, slots (a plain array of slot numbers) -- Facts: the skill-line read is
-- trusted only when every line's own copy answers numeric bounds; anything
-- else falls back to the 1..500 walk the probe also proved.
function Book:Enumerate()
    local numLines = MD.API.SpellBookSkillLines()
    if type(numLines) == "number" and numLines >= MIN_LINES and numLines <= MAX_LINES then
        local slots, allGood = {}, true
        for i = 1, numLines do
            local info = MD.API.SpellBookSkillLineInfo(i)
            if type(info) ~= "table" or type(info.itemIndexOffset) ~= "number"
                or type(info.numSpellBookItems) ~= "number" then
                allGood = false
                break
            end
            if info.isGuild ~= true then
                for s = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    slots[#slots + 1] = s
                end
            end
        end
        if allGood then return "skilllines", slots end
    end

    local slots = {}
    for s = 1, MAX_WALK_SLOT do slots[#slots + 1] = s end
    return "walk", slots
end

--------------------------------------------------------------------------------
-- One rank
--------------------------------------------------------------------------------

-- Stale values in combat (Facts): when a rescan finds a description that is
-- not readable right now but the PREVIOUS scan had it readable, the entry
-- keeps the old desc/parsed and says so -- a healer's dashboard should never
-- go blank mid-fight just because the client secreted the text for a tick.
-- Review R41: a previous entry that was itself stale carries its kept values
-- forward too -- otherwise only the first unreadable rescan kept them, and
-- the second (2 s later, or on the next player UNIT_AURA) lost them.
local function ApplyStale(entry, prevSpells)
    local prev = prevSpells and prevSpells[entry.id]
    if prev and (prev.descState == "ok" or prev.stale == true) and entry.descState ~= "ok" then
        entry.desc = prev.desc
        entry.parsed = prev.parsed
        entry.stale = true
    end
end

function Book:BuildEntry(row, slot, bank, futureConst, prevSpells)
    local id = row.spellID
    local entry = { id = id, slot = slot }

    -- == shapes item 3 (m2 lines 252-259): kept as read, for the pane (T10c)
    -- to leave passives out; skillLineIndex is absent on General's own rows,
    -- so a plain number-or-nil is all Book can promise here.
    entry.passive = (row.isPassive == true)
    entry.skillLine = (type(row.skillLineIndex) == "number") and row.skillLineIndex or nil

    local name = MD.API.SpellName(id)
    entry.name = (type(name) == "string") and name or nil

    local rankText = MD.API.SpellSubtext(id)
    entry.rankText = (type(rankText) == "string") and rankText or nil
    entry.rank = Parse.Rank(entry.rankText)

    local known = MD.API.SpellKnown(id)
    if type(known) == "boolean" then
        entry.known = known
    elseif futureConst ~= nil and row.itemType == futureConst then
        entry.known = false
    else
        entry.known = true
    end

    local lowRank = MD.API.SpellBookItemIsLowRank(slot, bank)
    entry.lowRank = (type(lowRank) == "boolean") and lowRank or nil

    local desc, descReason = MD.API.SpellDescription(id)
    if type(desc) == "string" then
        entry.desc = Parse.Clean(desc)
        entry.parsed = Parse.Description(desc)
        entry.descState = (entry.desc == "") and "empty" or "ok"
    elseif descReason == "secret" then
        entry.descState = "secret"
    else
        entry.descState = "absent"
    end
    ApplyStale(entry, prevSpells)

    local level = MD.API.SpellLevelLearned(id)
    entry.level = (type(level) == "number") and level or nil

    entry.icon = (type(row.iconID) == "number") and row.iconID or nil

    local tip = MD.API.SpellTooltipData(id)

    local info = MD.API.SpellInfo(id)
    local tipSecs, tipKind = TooltipCastInfo(tip)
    if type(info) == "table" and type(info.castTime) == "number" then
        entry.cast = info.castTime / 1000
    else
        entry.cast = tipSecs
    end

    if tipKind == "channeled" then
        entry.castKind = "channeled"
    elseif entry.cast == 0 then
        entry.castKind = HasTickPart(entry.parsed) and "channeled" or "instant"
    elseif entry.cast ~= nil then
        entry.castKind = "cast"
    end

    local costList, costReason = MD.API.SpellPowerCost(id)
    entry.cost, entry.costState = ResolveCost(costList, costReason, tip)

    return entry
end

--------------------------------------------------------------------------------
-- A single spell by id, outside the player's book (T9): a chat link, or
-- someone else's action bar. There is no slot to read (SpellBookItemInfo,
-- SpellBookItemIsLowRank both need one), so only the id-keyed calls run; and
-- no family to compare against, so no row number that needs one or a mana
-- pool (dominated, suggested, casts to OOM) is set here -- those stay nil
-- rather than guessed from nothing.
--------------------------------------------------------------------------------
function Book:ReadSpell(id)
    if type(id) ~= "number" then return nil end
    local entry = { id = id }

    local name = MD.API.SpellName(id)
    if type(name) ~= "string" then return nil end
    entry.name = name

    local rankText = MD.API.SpellSubtext(id)
    entry.rankText = (type(rankText) == "string") and rankText or nil
    entry.rank = Parse.Rank(entry.rankText)

    local desc, descReason = MD.API.SpellDescription(id)
    if type(desc) == "string" then
        entry.desc = Parse.Clean(desc)
        entry.parsed = Parse.Description(desc)
        entry.descState = (entry.desc == "") and "empty" or "ok"
    elseif descReason == "secret" then
        entry.descState = "secret"
    else
        entry.descState = "absent"
    end

    local level = MD.API.SpellLevelLearned(id)
    entry.level = (type(level) == "number") and level or nil

    local tip = MD.API.SpellTooltipData(id)
    local info = MD.API.SpellInfo(id)
    local tipSecs, tipKind = TooltipCastInfo(tip)
    if type(info) == "table" and type(info.castTime) == "number" then
        entry.cast = info.castTime / 1000
    else
        entry.cast = tipSecs
    end

    if tipKind == "channeled" then
        entry.castKind = "channeled"
    elseif entry.cast == 0 then
        entry.castKind = HasTickPart(entry.parsed) and "channeled" or "instant"
    elseif entry.cast ~= nil then
        entry.castKind = "cast"
    end

    local costList, costReason = MD.API.SpellPowerCost(id)
    entry.cost, entry.costState = ResolveCost(costList, costReason, tip)

    -- The kind (heal/damage), the same rule GroupFamilies uses per family,
    -- read off this one entry's own parsed text.
    local kind
    if type(entry.parsed) == "table" and (entry.parsed.heal ~= nil or entry.parsed.absorb ~= nil) then
        kind = "heal"
    elseif type(entry.parsed) == "table" and entry.parsed.damage ~= nil then
        kind = "damage"
    end
    entry.kind = kind

    if kind then
        local value, part = PartValue(entry, kind)
        local interval = IntervalFor(entry, part)
        entry.value = value
        entry.min = part and part.min
        entry.max = part and part.max
        entry.over = part and part.over
        entry.dur = part and part.dur
        entry.interval = interval

        local amount = entry.cost and entry.cost.amount
        entry.perMana = (value ~= nil and amount ~= nil and amount > 0) and (value / amount) or nil
        entry.perSec = (value ~= nil and interval ~= nil and interval > 0) and (value / interval) or nil
    end

    return entry
end

--------------------------------------------------------------------------------
-- Families
--------------------------------------------------------------------------------

function Book:GroupFamilies(spells)
    local ids = {}
    for id in pairs(spells) do ids[#ids + 1] = id end
    -- Slot order first: a stable, purely-Book-owned tiebreak for entries that
    -- tie on rank (unranked ones), never an ordering read off the client.
    table.sort(ids, function(a, b) return spells[a].slot < spells[b].slot end)

    local families, order = {}, {}
    for _, id in ipairs(ids) do
        local e = spells[id]
        if e.name then
            local fam = families[e.name]
            if not fam then
                fam = { name = e.name, ranks = {} }
                families[e.name] = fam
                order[#order + 1] = e.name
            end
            fam.ranks[#fam.ranks + 1] = e
        end
    end
    table.sort(order)

    for _, name in ipairs(order) do
        local fam = families[name]
        table.sort(fam.ranks, function(a, b)
            local ra, rb = a.rank or math.huge, b.rank or math.huge
            if ra ~= rb then return ra < rb end
            return a.slot < b.slot
        end)

        for _, e in ipairs(fam.ranks) do
            for _, fn in ipairs(Book.adjust) do
                pcall(fn, e, fam)
            end
        end

        local kind
        for _, e in ipairs(fam.ranks) do
            if type(e.parsed) == "table" and (e.parsed.heal ~= nil or e.parsed.absorb ~= nil) then
                kind = "heal"
                break
            end
        end
        if not kind then
            for _, e in ipairs(fam.ranks) do
                if type(e.parsed) == "table" and e.parsed.damage ~= nil then
                    kind = "damage"
                    break
                end
            end
        end
        fam.kind = kind

        local maxKnown
        for _, e in ipairs(fam.ranks) do
            if e.known and e.rank and (not maxKnown or e.rank > maxKnown.rank) then maxKnown = e end
        end
        fam.maxKnown = maxKnown

        -- A gap: a rank number below the highest LISTED rank that the book
        -- simply does not list (untrained, or hidden -- Facts: Book cannot
        -- tell which).
        local listed, maxListed = {}, 0
        for _, e in ipairs(fam.ranks) do
            if e.rank then
                listed[e.rank] = true
                if e.rank > maxListed then maxListed = e.rank end
            end
        end
        local gaps = {}
        for r = 1, maxListed - 1 do
            if not listed[r] then gaps[#gaps + 1] = r end
        end
        fam.gaps = gaps
    end

    return families, order
end

--------------------------------------------------------------------------------
-- Row numbers (Facts, ported from Engine/RankMath.lua's Compute())
--------------------------------------------------------------------------------

-- Casts to OOM for one entry Rows has already filled (its interval) against
-- any pool, WITHOUT writing it anywhere (review R38): the Spellbook pane
-- counts against the clock's modelled pool through this, so the entries
-- Book:Get() shares with the spell tooltip, the clock and the modules keep
-- the from-full count Book:Scan() gave them.
function Book:CastsFor(entry, pool)
    if type(entry) ~= "table" or type(pool) ~= "table" then return nil end
    local amount = entry.cost and entry.cost.amount
    return CastsToOOM(amount, entry.interval, pool.mana or pool.max, pool.regenCasting)
end

function Book:Rows(family, pool)
    if not family.kind then return end

    for _, e in ipairs(family.ranks) do
        local value, part = PartValue(e, family.kind)
        local interval = IntervalFor(e, part)
        e.value = value
        e.min = part and part.min
        e.max = part and part.max
        e.over = part and part.over
        e.dur = part and part.dur
        e.interval = interval

        local amount = e.cost and e.cost.amount
        e.perMana = (value ~= nil and amount ~= nil and amount > 0) and (value / amount) or nil
        e.perSec = (value ~= nil and interval ~= nil and interval > 0) and (value / interval) or nil
        e.casts = Book:CastsFor(e, pool)
        e.dominated = nil
        e.suggested = nil
    end

    -- Pareto dominance on (perMana, perSec), known ranks only.
    for i, ri in ipairs(family.ranks) do
        if ri.known and ri.perMana and ri.perSec then
            for j, rj in ipairs(family.ranks) do
                if i ~= j and rj.known and rj.perMana and rj.perSec
                    and rj.perMana >= ri.perMana and rj.perSec >= ri.perSec
                    and (rj.perMana > ri.perMana or rj.perSec > ri.perSec) then
                    ri.dominated = true
                    break
                end
            end
        end
    end

    -- Suggested: the known, non-dominated rank with the highest per-mana
    -- whose value is still at least SUGGESTED_FLOOR of the highest known
    -- rank's, else the highest known rank itself.
    local maxKnown = family.maxKnown
    local suggested
    if maxKnown and maxKnown.value then
        for _, e in ipairs(family.ranks) do
            if e.known and e.perMana and e.perSec and not e.dominated
                and e.value ~= nil and e.value >= SUGGESTED_FLOOR * maxKnown.value then
                if not suggested or e.perMana > suggested.perMana then suggested = e end
            end
        end
    end
    suggested = suggested or maxKnown
    if suggested then suggested.suggested = true end
    family.suggested = suggested
end

--------------------------------------------------------------------------------
-- The mana pool fallback (T11 hands the clock's own modelled pool instead).
--------------------------------------------------------------------------------

function Book:DefaultPool()
    local pool = {}
    local maxMana = MD.API.UnitPowerMax("player", 0)
    if type(maxMana) == "number" then pool.max = maxMana end

    local _, regenCasting = MD.API.ManaRegen()
    if type(regenCasting) == "number" then
        pool.regenCasting = regenCasting
        Book._lastRegenCasting = regenCasting
    elseif Book._lastRegenCasting ~= nil then
        -- ManaRegen() goes secret in combat (Facts) -- the last plain reading
        -- Book itself saw is kept rather than losing casts-to-OOM entirely
        -- for the whole fight.
        pool.regenCasting = Book._lastRegenCasting
    end
    return pool
end

--------------------------------------------------------------------------------
-- Scan / cache
--------------------------------------------------------------------------------

function Book:Scan()
    local via, slotList = Book:Enumerate()
    local read = { via = via, slots = #slotList, spells = 0, secret = 0, errors = 0 }

    local bank = MD.API.Constant("Enum.SpellBookSpellBank.Player")
    local flyoutConst = MD.API.Constant("Enum.SpellBookItemType.Flyout")
    local petConst = MD.API.Constant("Enum.SpellBookItemType.PetAction")
    local futureConst = MD.API.Constant("Enum.SpellBookItemType.FutureSpell")

    local prevSpells = Book._prevSpells
    local spells = {}

    for _, slot in ipairs(slotList) do
        local row, reason = MD.API.SpellBookItemInfo(slot, bank)
        if reason == "secret" then
            read.secret = read.secret + 1
        elseif reason == "error" then
            read.errors = read.errors + 1
        elseif type(row) == "table" and type(row.spellID) == "number" then
            if row.itemType ~= flyoutConst and row.itemType ~= petConst then
                local entry = Book:BuildEntry(row, slot, bank, futureConst, prevSpells)
                spells[entry.id] = entry
                read.spells = read.spells + 1
            end
        end
    end

    local families, order = Book:GroupFamilies(spells)
    local pool = Book:DefaultPool()
    for _, name in ipairs(order) do
        Book:Rows(families[name], pool)
    end

    local book = { families = families, order = order, spells = spells, read = read }
    Book._cache = book
    Book._cacheTime = GetTime()
    Book._prevSpells = spells
    Book._dirty = false

    MD:Debug("other", "book scan via=%s spells=%d secret=%d errors=%d",
        read.via, read.spells, read.secret, read.errors)
    return book
end

function Book:MarkDirty()
    Book._dirty = true
end

-- Rescanned when dirty, or when the cache is older than 2 seconds (Facts).
-- GetTime() is read the same way Core_Forever.lua already does (a plain,
-- always-present client clock, no adapter binding of its own).
local CACHE_SECONDS = 2
function Book:Get()
    if Book._dirty or not Book._cache or (GetTime() - (Book._cacheTime or 0)) >= CACHE_SECONDS then
        Book:Scan()
    end
    return Book._cache
end

function Book:Entry(id)
    return Book:Get().spells[id]
end

MD:On("SPELLS_CHANGED", function() Book:MarkDirty() end)
MD:On("PLAYER_LEVEL_UP", function() Book:MarkDirty() end)
MD:On("PLAYER_EQUIPMENT_CHANGED", function() Book:MarkDirty() end)
MD:On("UNIT_AURA", function(unit)
    if not MD.API.IsSecret(unit) and unit == "player" then Book:MarkDirty() end
end)
