-- Spells/WhatIf_Forever.lua (T122, docs/tasks/T122-what-if.md): the What if's
-- provider on Forever. The Forever main TOCs, after Spells/WhatIf.lua.
--
-- The client's own spell text already carries the caster's gear and talents
-- (Q1), so the what-if book is the live book COPIED and moved, never rescanned:
--   +Healing   each heal rank's value moves by its own share of the change
--              (entry.bonus.counts -- measured when Spells/Book.lua's
--              MeasureBonus has seen two plain readings, else Spells/
--              Coefficients.lua's estimate; a rank with neither stays put),
--              its parts moved with it, then per mana / per second
--              re-derived through Book.Numbers and the rank rules re-run
--              (Book.RULE_FIELDS);
--   Crit %     each valued heal rank's `crit` (a chance, 0..1) -- the values
--              are averages without crit (the card's Crit pair names it);
--   Mana / Regen while casting
--              the pool casts to OOM are counted from (from full).
-- The live book, its generation and its entries are never written.
-- No class rows: a talent is already in the text.
local _, MD = ...

local WI = MD.WhatIf
if not WI then return end

local Book = MD.Book
local RR = MD.RankRules

local function LiveBonus()
    if not (Book and Book.Bonus) then return nil end
    local v = Book:Bonus("heal")
    return (type(v) == "number") and v or nil
end

local provider = {}

function provider.Live()
    local out = {}
    out.heal = LiveBonus()
    local school = MD.ClassProfile and MD.ClassProfile.critSchool or 2
    local crit = MD.API.SpellCritChance and MD.API.SpellCritChance(school)
    if type(crit) == "number" and crit == crit then out.crit = crit end
    local pool = Book and Book.Pool and Book:Pool()
    if type(pool) == "table" then
        out.mana = pool.max
        if type(pool.regenCasting) == "number" then out.casting = pool.regenCasting * 5 end
    end
    local base = MD.API.ManaRegen and MD.API.ManaRegen()
    if type(base) ~= "number" and MD.Pool and MD.Pool.LastRegen then base = MD.Pool:LastRegen() end
    if type(base) == "number" then out.base = base * 5 end
    return out
end

-- A part moved by d: a range by d at both ends, else the amount over time,
-- else each tick by its share; a hybrid split by the halves' sizes.
local function CopyPart(part)
    if type(part) ~= "table" then return part end
    local out = {}
    for k, v in pairs(part) do out[k] = v end
    return out
end

local function ShiftPart(part, d)
    if type(part) ~= "table" or d == 0 then return end
    local hit = part.min ~= nil or part.max ~= nil
    local direct = hit and (((part.min or 0) + (part.max or 0)) / 2) or 0
    local over = part.over or 0
    local dHit, dOver = 0, 0
    if hit and part.over ~= nil and direct + over > 0 then
        dHit = d * direct / (direct + over)
        dOver = d - dHit
    elseif hit then
        dHit = d
    elseif part.over ~= nil then
        dOver = d
    elseif part.tick ~= nil and part.periodDur ~= nil and part.period ~= nil and part.period > 0 then
        local n = math.floor(part.periodDur / part.period)
        if n > 0 then part.tick = part.tick + d / n end
        return
    end
    if dHit ~= 0 then
        if part.min ~= nil then part.min = part.min + dHit end
        if part.max ~= nil then part.max = part.max + dHit end
    end
    if dOver ~= 0 then part.over = part.over + dOver end
end

local function CopyEntry(e, dHeal, typedHeal, crit, kind)
    local w = {}
    for k, v in pairs(e) do w[k] = v end
    local b = e.bonus
    local d = 0
    if kind == "heal" and dHeal ~= 0 and type(b) == "table" and type(b.counts) == "number"
        and type(e.parsed) == "table" then
        d = b.counts * dHeal
        local parsed = {}
        for k, v in pairs(e.parsed) do parsed[k] = v end
        if parsed.heal ~= nil then
            parsed.heal = CopyPart(parsed.heal)
            ShiftPart(parsed.heal, d)
        elseif type(parsed.absorb) == "number" then
            parsed.absorb = parsed.absorb + d
        end
        w.parsed = parsed
    end
    if type(b) == "table" and kind == "heal" and typedHeal ~= nil then
        local nb = {}
        for k, v in pairs(b) do nb[k] = v end
        nb.of = typedHeal
        nb.amount = (type(b.counts) == "number") and b.counts * typedHeal or nil
        w.bonus = nb
    end
    if d ~= 0 then Book.Numbers(w, kind) end
    if crit ~= nil and kind == "heal" and w.value ~= nil then w.crit = crit / 100 end
    return w
end

function provider.Book()
    if not (Book and Book.Get) then return nil end
    local live = Book:Get()
    if type(live) ~= "table" then return nil end
    local liveHeal = LiveBonus()
    local typedHeal = WI:Get("heal")
    local dHeal = (typedHeal ~= nil and liveHeal ~= nil) and (typedHeal - liveHeal) or 0
    local crit = WI:Get("crit")
    local pool = WI:Pool(Book:Pool())
    local castPool = { max = pool.max, regenCasting = pool.regenCasting }

    local spells, families = {}, {}
    for name, fam in pairs(live.families or {}) do
        local nf = {}
        for k, v in pairs(fam) do nf[k] = v end
        nf.ranks = {}
        for i, e in ipairs(fam.ranks or {}) do
            local w = CopyEntry(e, dHeal, typedHeal, crit, fam.kind)
            w.casts = Book:CastsFor(w, castPool)
            nf.ranks[i] = w
            spells[e.id] = w
            if fam.maxKnown == e then nf.maxKnown = w end
        end
        if fam.kind then
            for _, w in ipairs(nf.ranks) do
                w.dominated, w.dominatedBy, w.suggested = nil, nil, nil
            end
            RR.Pareto(nf.ranks, Book.RULE_FIELDS)
            local suggested = RR.Suggested(nf.ranks, nf.maxKnown, Book.RULE_FIELDS)
            if suggested then suggested.suggested = true end
            nf.suggested = suggested
            RR.DominatedBy(nf.ranks, suggested, Book.RULE_FIELDS)
        end
        families[name] = nf
    end
    -- a spell outside every family (none on this line today) is copied as is
    for id, e in pairs(live.spells or {}) do
        if spells[id] == nil then spells[id] = CopyEntry(e, 0, nil, nil, nil) end
    end
    return { families = families, order = live.order, spells = spells, read = live.read,
             generation = live.generation, whatIf = true }
end

provider.classRows = nil
provider.classNote = "Your talents are already in the spells' text, so there is no class row."

-- "2 of 3 ranks measured, 1 estimated" -- the +healing shares the move rests on.
function provider.ranksNote(fam)
    if WI:Get("heal") == nil or type(fam) ~= "table" then return nil end
    local measured, estimated = 0, 0
    local ranks = fam.ranks or {}
    for _, e in ipairs(ranks) do
        local from = type(e.bonus) == "table" and e.bonus.from
        if from == "measured" then measured = measured + 1
        elseif from == "estimated" then estimated = estimated + 1 end
    end
    if #ranks == 0 then return nil end
    return measured .. " of " .. #ranks .. " ranks measured, " .. estimated .. " estimated"
end

WI.provider = provider
