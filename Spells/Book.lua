-- T7 (docs/tasks/T7-spell-book.md, M2 of docs/ROADMAP-FOREVER.md): the
-- spellbook, read only through MD.API, grouped into families of ranks with
-- the numbers a healer compares ranks by. Forever TOCs only -- reaches the
-- client only through MD.API and never indexes a client table (every value
-- Book reads is either a plain scalar Has/Call already cleared, or a field
-- of a table MD.API.Copy already built, never the client's own table).
local _, MD = ...
local Parse = MD.Parse
-- T67 (P23, review A13): the Pareto filter, the suggested rank and casts to
-- OOM are Spells/RankRules.lua's, shared with the TBC dashboard.
local RR = MD.RankRules

MD.Book = MD.Book or {}
local Book = MD.Book

-- The global cooldown, same constant Engine/RankMath.lua's TBC dashboard
-- uses (1.5s) -- ported as-is (Facts), to be checked against a real cast bar
-- once one exists to read (T12).
local GCD = 1.5
Book.GCD = GCD -- T67: Spells/Words.lua's per-second words read it

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

-- T95 (docs/SPEC-next.md 4.2 P1): the cooldown a tooltip line states on its
-- right ("10 sec cooldown", beside the cast line), in seconds -- the first
-- right text Parse.Cooldown reads whole (an "N yd range" or a rank text is
-- not one). `readable` is false when the tooltip data itself did not come
-- back (absent, secret, raised): the caller then carries the last cooldown
-- read rather than taking "no cooldown" for an answer.
local function TooltipCooldown(tip)
    if type(tip) ~= "table" or type(tip.lines) ~= "table" then return nil, false end
    for _, line in ipairs(tip.lines) do
        if type(line) == "table" and type(line.rightText) == "string" then
            local secs = Parse.Cooldown(line.rightText)
            if secs ~= nil and secs > 0 then return secs, true end
        end
    end
    return nil, true
end

-- T95: the cooldown, in seconds, and where it was read. By default the
-- tooltip line's right text (the one shape the export and the probe have
-- shown); GetSpellBaseCooldown (MD.API.BaseCooldown, Client/API_Forever.lua)
-- only once MD.API.BASE_CD_READS is true -- false until T87's Forever report
-- shows it answers plain (the BAR_READS_MAX pattern; the integrator flips
-- it). A base read of 0 or nothing falls through to the tooltip line.
-- `prev` is the previous scan's entry for this id: an unreadable tooltip
-- keeps its cooldown, as a secret description keeps its text (ApplyStale).
local function ReadCooldown(id, tip, prev)
    if MD.API.BASE_CD_READS == true and type(MD.API.BaseCooldown) == "function" then
        local ms = MD.API.BaseCooldown(id)
        if type(ms) == "number" and ms == ms and ms > 0 then return ms / 1000, "base" end
    end
    local secs, readable = TooltipCooldown(tip)
    if secs then return secs, "tooltip" end
    if not readable and prev and type(prev.cooldown) == "number" then
        return prev.cooldown, prev.cooldownFrom
    end
    return nil, nil
end

-- T95 (4.2 P1, 4.5): whom a heal reaches and its per-target lockout, from the
-- entry's own text (the kept one when stale): entry.targets is
-- Parse.Targets' word ("single", "party", "chain", "selfAndTarget",
-- "caster"), entry.reach its whole answer (count, jumps, falloff, range,
-- from, partyOnly, belowPct, charges), entry.targetsWhy the reason when it
-- refused (an unrecognised reach is never taken for "single"). Only a text
-- that heals or absorbs is asked: a damage spell's reach is not a heal's.
-- entry.lockout is Parse.Lockout's seconds ("cannot be shielded again for
-- 15 sec"), from any text.
local function ApplyReach(entry)
    entry.targets, entry.reach, entry.targetsWhy, entry.lockout = nil, nil, nil, nil
    if type(entry.desc) ~= "string" or entry.desc == "" then return end
    entry.lockout = Parse.Lockout(entry.desc)
    local p = entry.parsed
    if type(p) ~= "table" or (p.heal == nil and p.absorb == nil) then return end
    local t, why = Parse.Targets(entry.desc)
    if type(t) == "table" then
        entry.targets = t.targets
        entry.reach = t
    else
        entry.targetsWhy = why
    end
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
--
-- T95 (docs/SPEC-next.md 4.2 P1): and never shorter than the spell's cooldown
-- -- max(cast, GCD, cooldown) for a direct spell, max(its own duration,
-- cooldown) for one over time -- so per second and casts to OOM no longer
-- assume a Holy Shock every GCD. The second return is "cooldown" when the
-- cooldown is what sets the interval (the words then say "every 10 s").
local function BaseInterval(entry, part)
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

local function IntervalFor(entry, part)
    local base = BaseInterval(entry, part)
    local cd = entry.cooldown
    if base ~= nil and type(cd) == "number" and cd > base then
        return cd, "cooldown"
    end
    return base, nil
end
Book.IntervalFor = IntervalFor -- T95: Spells/Words.lua and the tooltip's Other lines

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

-- One rank's numbers for its family's kind (Rows and ReadSpell share it):
-- the value and its parts, the interval (T95: never under the cooldown, and
-- `intervalBy` "cooldown" when the cooldown sets it), per mana and per second.
-- Per mana and per second are ONE target's, whatever entry.targets says (T95,
-- decision 12: a group or bounce heal's reach is said in words, never
-- multiplied in).
--
-- T95 (4.2 P6, shown by role in T110): an either-or spell -- a heal family
-- whose text also deals damage (Holy Shock, Holy Nova) -- keeps its damage
-- half too, as entry.alt = { kind = "damage", value, min, max, over, dur,
-- interval, perMana, perSec }; nothing shows it yet.
local function Numbers(e, kind)
    local value, part = PartValue(e, kind)
    local interval, by = IntervalFor(e, part)
    e.value = value
    e.min = part and part.min
    e.max = part and part.max
    e.over = part and part.over
    e.dur = part and part.dur
    e.interval = interval
    e.intervalBy = by

    local amount = e.cost and e.cost.amount
    e.perMana = (value ~= nil and amount ~= nil and amount > 0) and (value / amount) or nil
    e.perSec = (value ~= nil and interval ~= nil and interval > 0) and (value / interval) or nil

    e.alt = nil
    if kind == "heal" and type(e.parsed) == "table" and e.parsed.damage ~= nil then
        local dv, dp = PartValue(e, "damage")
        if dv ~= nil then
            local di = IntervalFor(e, dp)
            e.alt = {
                kind = "damage", value = dv,
                min = dp and dp.min, max = dp and dp.max, over = dp and dp.over, dur = dp and dp.dur,
                interval = di,
                perMana = (amount ~= nil and amount > 0) and (dv / amount) or nil,
                perSec = (di ~= nil and di > 0) and (dv / di) or nil,
            }
        end
    end
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

    -- T95: the cooldown, the reach and the lockout.
    entry.cooldown, entry.cooldownFrom = ReadCooldown(id, tip, prevSpells and prevSpells[id])
    ApplyReach(entry)

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
-- T67: the previous entry ReadSpell answered for each id it could name, the
-- `prevSpells` its ApplyStale reads (one entry per id ever read: a chat link
-- or a bar's spell, a handful of ids).
Book._readSpells = Book._readSpells or {}

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
    -- T67 (P23, review A15's R41 gap): the last readable text is carried
    -- through a secret description here too, as BuildEntry carries it, from
    -- this path's own previous reads -- a spell outside the book (a chat
    -- link, another bar) no longer goes blank in combat.
    ApplyStale(entry, Book._readSpells)

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

    -- T95: the cooldown, the reach and the lockout, as BuildEntry reads them.
    entry.cooldown, entry.cooldownFrom = ReadCooldown(id, tip, Book._readSpells[id])
    ApplyReach(entry)

    -- The kind (heal/damage), the same rule GroupFamilies uses per family,
    -- read off this one entry's own parsed text.
    local kind
    if type(entry.parsed) == "table" and (entry.parsed.heal ~= nil or entry.parsed.absorb ~= nil) then
        kind = "heal"
    elseif type(entry.parsed) == "table" and entry.parsed.damage ~= nil then
        kind = "damage"
    end
    entry.kind = kind

    if kind then Numbers(entry, kind) end

    Book._readSpells[id] = entry
    return entry
end

--------------------------------------------------------------------------------
-- Families
--------------------------------------------------------------------------------

-- T38 (docs/SPEC-forever-ui.md 3.5): what a family's value is made of, for the
-- words of its view's header and the card's pairs -- "direct" (a range, or an
-- absorb: one effect at once), "hot" (an amount over a duration, or a tick
-- every period: over time only), "hybrid" (a range and an amount over time)
-- or "none" (no kind: nothing the text values). Read off the family's own
-- relevant part (heal or damage, by its kind), the highest known rank's
-- first, else the first rank that has one; nothing is assumed.
local function PartShape(e, kind)
    if type(e.parsed) ~= "table" then return nil end
    local part
    if kind == "heal" then
        part = e.parsed.heal
        if part == nil and e.parsed.absorb ~= nil then return "direct" end
    else
        part = e.parsed.damage
    end
    if type(part) ~= "table" then return nil end
    local hit = part.min ~= nil or part.max ~= nil
    local over = part.over ~= nil or part.tick ~= nil
    if hit and over then return "hybrid" end
    if hit then return "direct" end
    if over then return "hot" end
    return nil
end

local function ShapeOf(fam)
    if not fam.kind then return "none" end
    if fam.maxKnown then
        local s = PartShape(fam.maxKnown, fam.kind)
        if s then return s end
    end
    for _, e in ipairs(fam.ranks) do
        local s = PartShape(e, fam.kind)
        if s then return s end
    end
    return "none"
end

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
                -- T35 (docs/SPEC-forever-ui.md 3.3): the family's key is its
                -- name (enUS only, and a family has no one stable id), and
                -- ids holds every rank's id -- Spells/Tabs.lua keeps them
                -- beside the key, the fallback should the name ever change.
                fam = { name = e.name, key = e.name, ranks = {}, ids = {} }
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
        for i, e in ipairs(fam.ranks) do fam.ids[i] = e.id end

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
        -- T95 (4.2 P6): an either-or heal family (Holy Shock, Holy Nova) keeps
        -- its damage half beside it (each rank's entry.alt, Numbers above);
        -- T110 shows the half that matches the player's role.
        fam.altKind = nil
        if kind == "heal" then
            for _, e in ipairs(fam.ranks) do
                if type(e.parsed) == "table" and e.parsed.damage ~= nil then
                    fam.altKind = "damage"
                    break
                end
            end
        end

        local maxKnown
        for _, e in ipairs(fam.ranks) do
            if e.known and e.rank and (not maxKnown or e.rank > maxKnown.rank) then maxKnown = e end
        end
        fam.maxKnown = maxKnown
        fam.shape = ShapeOf(fam)

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
    return RR.CastsToOOM(amount, entry.interval, pool.mana or pool.max, pool.regenCasting)
end

-- T67: the book's entries for Spells/RankRules.lua -- per mana and per
-- second, the value the floor is a share of, and only known ranks that have
-- both numbers.
local RULE_FIELDS = {
    eff = "perMana", rate = "perSec", value = "value",
    eligible = function(e) return e.known and e.perMana and e.perSec end,
}

function Book:Rows(family, pool)
    if not family.kind then return end

    for _, e in ipairs(family.ranks) do
        Numbers(e, family.kind)
        e.casts = Book:CastsFor(e, pool)
        e.dominated = nil
        e.dominatedBy = nil -- T38
        e.suggested = nil
    end

    -- Pareto dominance on (perMana, perSec), known ranks with both numbers;
    -- suggested: the known, non-dominated rank with the highest per mana
    -- whose value is still at least MD.Rules.SUGGESTED_FLOOR of the highest
    -- known rank's, else the highest known rank itself; T38 (docs/SPEC-
    -- forever-ui.md 3.5): a dominated rank names the rank that beats it, by
    -- its spell id (a plain number, never a second path to a table) -- the
    -- suggested rank when it is one of them, else the one of them with the
    -- best per mana. T67: all three are Spells/RankRules.lua's.
    RR.Pareto(family.ranks, RULE_FIELDS)
    local suggested = RR.Suggested(family.ranks, family.maxKnown, RULE_FIELDS)
    if suggested then suggested.suggested = true end
    family.suggested = suggested
    RR.DominatedBy(family.ranks, suggested, RULE_FIELDS)
end

--------------------------------------------------------------------------------
-- The half a role casts an either-or spell for (T110, docs/SPEC-next.md 4.2
-- P6; R-classes item 2: "show the half matching the player's role")
--------------------------------------------------------------------------------

-- One rank's damage half as an entry of its own: a shallow copy of the heal
-- entry with Numbers run for "damage" (the value, its parts, the interval --
-- the cooldown still pacing it --, per mana, per second), the heal's reach
-- dropped (a heal's targets are not the damage's), `half` "damage" and `of`
-- the heal entry it came from. The book's own entry is never written: the
-- book's generation and every consumer of Book:Get() see what they saw.
local function DamageHalf(e, pool)
    local v = {}
    for k, x in pairs(e) do v[k] = x end
    v.kind = "damage"
    Numbers(v, "damage")
    v.targets, v.reach, v.targetsWhy = nil, nil, nil
    v.dominated, v.dominatedBy, v.suggested = nil, nil, nil
    v.casts = Book:CastsFor(v, pool)
    v.half, v.of = "damage", e
    return v
end

-- The family a role sees. A heal family that keeps a damage half (altKind,
-- T95) seen by the "damage" role is a view of that half: every rank through
-- DamageHalf, the dominance, the suggested rank and the beaten-by ids
-- Spells/RankRules.lua gives the damage numbers, kind "damage", altKind
-- "heal", `half` "damage", `of` the family; its key, name, ids and gaps are
-- the family's. Every other family, and every other role, is the family
-- itself. Built at each call, written nowhere.
function Book:Half(family, role, pool)
    if type(family) ~= "table" or role ~= "damage" or family.kind ~= "heal"
        or family.altKind ~= "damage" then
        return family
    end
    pool = pool or Book:DefaultPool()
    local view = {}
    for k, x in pairs(family) do view[k] = x end
    view.kind, view.altKind, view.half, view.of = "damage", "heal", "damage", family
    view.ranks, view.maxKnown, view.suggested = {}, nil, nil
    for i, e in ipairs(family.ranks or {}) do
        local v = DamageHalf(e, pool)
        view.ranks[i] = v
        if e == family.maxKnown then view.maxKnown = v end
    end
    view.shape = ShapeOf(view)
    RR.Pareto(view.ranks, RULE_FIELDS)
    local suggested = RR.Suggested(view.ranks, view.maxKnown, RULE_FIELDS)
    if suggested then suggested.suggested = true end
    view.suggested = suggested
    RR.DominatedBy(view.ranks, suggested, RULE_FIELDS)
    return view
end

-- The same for one entry with no family (Book:ReadSpell's): its damage half
-- for the "damage" role when it keeps one (entry.alt), else the entry.
function Book:HalfOf(entry, role, pool)
    if type(entry) ~= "table" or role ~= "damage" or entry.kind ~= "heal"
        or type(entry.alt) ~= "table" then
        return entry
    end
    return DamageHalf(entry, pool or Book:DefaultPool())
end

-- T38 (docs/SPEC-forever-ui.md 3.5): how rank `a` stands against rank `b`,
-- for the decision strip's one factual line -- plain numbers in percent, each
-- nil when either side lacks what it needs (never a 0 standing in for a
-- number the book does not have):
--   perMana -- a's per mana against b's, minus one (+2 = 2% more per mana)
--   perSec  -- the same for per second
--   value   -- a's value as a percent of b's (47 = 47% of the heal)
--   cast    -- a's cast time against b's, minus one (-25 = a 25% shorter
--              cast); only between two timed casts ("cast" kind, time > 0)
-- nil when a or b is not an entry. It says how they differ, never which to
-- cast.
local function Ratio(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or y == 0 or x ~= x or y ~= y then return nil end
    return x / y
end

function Book:Compare(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local out = {}
    local r = Ratio(a.perMana, b.perMana)
    if r then out.perMana = (r - 1) * 100 end
    r = Ratio(a.perSec, b.perSec)
    if r then out.perSec = (r - 1) * 100 end
    r = Ratio(a.value, b.value)
    if r then out.value = r * 100 end
    if a.castKind == "cast" and b.castKind == "cast" then
        r = Ratio(a.cast, b.cast)
        if r and a.cast > 0 then out.cast = (r - 1) * 100 end
    end
    return out
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
    elseif MD.Pool and MD.Pool.LastRegen then
        -- ManaRegen() goes secret in combat (Facts) -- the last plain reading
        -- is kept rather than losing casts-to-OOM entirely for the whole
        -- fight. T68 (P24, review A29): the reading is the modelled pool's
        -- (Engine/ManaPool_Forever.lua, read at login and every tick out of
        -- combat), not a copy this file cached from its own calls.
        local _, lastCasting = MD.Pool:LastRegen()
        if type(lastCasting) == "number" then pool.regenCasting = lastCasting end
    end
    return pool
end

--------------------------------------------------------------------------------
-- Scan / cache
--------------------------------------------------------------------------------

-- T63 (P19 of docs/PLAN-refactor-ux.md, review A11): the book's generation, a
-- counter bumped by every scan that changes an entry -- one added or gone, or
-- any field of one different from the previous scan's, after Rows (so the
-- numbers Book.adjust and the family rules derive count too). One field is
-- left out: `casts`, the casts-to-OOM count against the mana pool of the
-- moment, which moves with max mana and regen and is not the spell's. A
-- rescan of an unchanged book leaves it where it was, so a consumer that
-- builds from the book (Kit_Forever.lua's SpellKit) rebuilds only when there
-- is something new. The first scan counts as a change. Also carried on each
-- book table Scan returns (`book.generation`).
Book.generation = Book.generation or 0

local SIG_SKIP = { casts = true }

-- A deterministic string for one value: tables by sorted key, numbers to 17
-- significant digits, strings length-prefixed (so no two values share a
-- signature by an accident of concatenation). Only Book's own copies and
-- plain values reach here.
local function Sig(v, out, depth)
    local tv = type(v)
    if tv == "number" then
        out[#out + 1] = "n" .. string.format("%.17g", v)
    elseif tv == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif tv == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif tv == "table" then
        if depth > 6 then out[#out + 1] = "?"; return end
        local keys = {}
        for k in pairs(v) do
            if not (depth == 0 and SIG_SKIP[k]) then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            if ta == "number" or ta == "string" then return a < b end
            return tostring(a) < tostring(b)
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            Sig(k, out, depth + 1)
            out[#out + 1] = "="
            Sig(v[k], out, depth + 1)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = tv
    end
end

local function EntrySig(entry)
    local out = {}
    Sig(entry, out, 0)
    return table.concat(out)
end

function Book:Scan()
    -- T35: a scan after MarkDirty (or the first) is a changed book; the
    -- 2-second rescans of an unchanged one are not.
    local changed = Book._dirty or not Book._cache
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

    -- T63: the generation moves when any entry did (see Book.generation).
    local prevSigs = Book._prevSigs
    local sigs, entryChanged = {}, (prevSigs == nil)
    for id, entry in pairs(spells) do
        local sig = EntrySig(entry)
        sigs[id] = sig
        if not entryChanged and prevSigs[id] ~= sig then entryChanged = true end
    end
    if not entryChanged then
        for id in pairs(prevSigs) do
            if sigs[id] == nil then entryChanged = true; break end
        end
    end
    if entryChanged then Book.generation = Book.generation + 1 end
    Book._prevSigs = sigs

    local book = { families = families, order = order, spells = spells, read = read,
                   generation = Book.generation }
    Book._cache = book
    Book._cacheTime = GetTime()
    Book._prevSpells = spells
    Book._dirty = false

    MD:Debug("other", "book scan via=%s spells=%d secret=%d errors=%d",
        read.via, read.spells, read.secret, read.errors)
    -- T35: Spells/Tabs.lua reconciles the spell list here (a newly learned
    -- heal appended), after the cache is in place.
    if changed then MD:Fire("BOOK_CHANGED", book) end
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
