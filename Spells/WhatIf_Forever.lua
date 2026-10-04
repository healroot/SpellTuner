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
--   +Spell damage (T124)
--              each damage rank the same way by its share of the change in
--              its school's bonus (entry.bonus.counts: measured when
--              MeasureBonus has seen two plain readings of that school's
--              spell damage, else estimated; the live side the school on
--              screen, WI.LiveDamage; every school moves by one delta);
--   Crit %     each valued heal rank's `crit` (a chance, 0..1) -- the values
--              are averages without crit (the card's Crit pair names it);
--   Mana / Regen while casting
--              the pool casts to OOM are counted from (from full).
-- The live book, its generation and its entries are never written.
-- No class rows: a talent is already in the text.
local _, ST = ...

local WI = ST.WhatIf
if not WI then return end

local Book = ST.Book
local RR = ST.RankRules

local function LiveBonus()
    if not (Book and Book.Bonus) then return nil end
    local v = Book:Bonus("heal")
    return (type(v) == "number") and v or nil
end

local provider = {}

function provider.Live()
    local out = {}
    out.heal = LiveBonus()
    out.damage = WI.LiveDamage(Book) -- T124: the school on screen
    local school = ST.ClassProfile and ST.ClassProfile.critSchool or 2
    local crit = ST.API.SpellCritChance and ST.API.SpellCritChance(school)
    if type(crit) == "number" and crit == crit then out.crit = crit end
    local pool = Book and Book.Pool and Book:Pool()
    if type(pool) == "table" then
        out.mana = pool.max
        if type(pool.regenCasting) == "number" then out.casting = pool.regenCasting * 5 end
    end
    local base = ST.API.ManaRegen and ST.API.ManaRegen()
    if type(base) ~= "number" and ST.Pool and ST.Pool.LastRegen then base = ST.Pool:LastRegen() end
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

-- T124: the stat a family of `kind` moves with -- +Healing for a heal,
-- +Spell damage for a damage family; { d = typed - live, typed } or nil.
local function CopyEntry(e, move, crit, kind)
    local w = {}
    for k, v in pairs(e) do w[k] = v end
    local b = e.bonus
    local d = 0
    local delta = move and move.delta or 0
    local typed = move and move.typed or nil
    if delta ~= 0 and type(b) == "table" and type(b.counts) == "number" and type(e.parsed) == "table" then
        d = b.counts * delta
        local parsed = {}
        for k, v in pairs(e.parsed) do parsed[k] = v end
        if kind == "heal" then
            if parsed.heal ~= nil then
                parsed.heal = CopyPart(parsed.heal)
                ShiftPart(parsed.heal, d)
            elseif type(parsed.absorb) == "number" then
                parsed.absorb = parsed.absorb + d
            end
        elseif kind == "damage" and parsed.damage ~= nil then
            parsed.damage = CopyPart(parsed.damage)
            ShiftPart(parsed.damage, d)
        end
        w.parsed = parsed
    end
    -- the bonus this rank is priced at: its own school's (or +healing's)
    -- live reading plus the delta -- the typed value only where the entry
    -- names no reading; with no live reading at all nothing moved, so the
    -- entry's own bonus is left as it is
    if type(b) == "table" and typed ~= nil and not move.noLive then
        local nb = {}
        for k, v in pairs(b) do nb[k] = v end
        nb.of = (type(b.of) == "number") and (b.of + delta) or typed
        nb.amount = (type(b.counts) == "number") and b.counts * nb.of or nil
        w.bonus = nb
    end
    if d ~= 0 then Book.Numbers(w, kind) end
    if crit ~= nil and kind == "heal" and w.value ~= nil then w.crit = crit / 100 end
    return w
end

-- { delta, typed } for the stat of `kind` that is typed, else nil; the live
-- side read once per build (`live` caches it).
local function Move(kind, live)
    local key = (kind == "heal" or kind == "damage") and kind or nil
    if not key then return nil end
    local typed = WI:Get(key)
    if typed == nil then return nil end
    local base = live[key]
    -- no live reading: nothing moves and the bonus is not rewritten
    if type(base) ~= "number" then return { delta = 0, typed = typed, noLive = true } end
    return { delta = typed - base, typed = typed }
end

function provider.Book()
    if not (Book and Book.Get) then return nil end
    local live = Book:Get()
    if type(live) ~= "table" then return nil end
    local liveStats = { heal = LiveBonus(), damage = WI.LiveDamage(Book) }
    local moves = { heal = Move("heal", liveStats), damage = Move("damage", liveStats) }
    local crit = WI:Get("crit")
    local pool = WI:Pool(Book:Pool())
    local castPool = { max = pool.max, regenCasting = pool.regenCasting }

    local spells, families = {}, {}
    for name, fam in pairs(live.families or {}) do
        local nf = {}
        for k, v in pairs(fam) do nf[k] = v end
        nf.ranks = {}
        for i, e in ipairs(fam.ranks or {}) do
            local w = CopyEntry(e, moves[fam.kind or ""], crit, fam.kind)
            w.casts = Book:CastsFor(w, castPool)
            nf.ranks[i] = w
            spells[e.id] = w
            if fam.maxKnown == e then nf.maxKnown = w end
        end
        nf.maxRank, nf.effRank = nil, nil
        if fam.kind then
            for _, w in ipairs(nf.ranks) do
                w.dominated, w.dominatedBy, w.suggested = nil, nil, nil
            end
            RR.Pareto(nf.ranks, Book.RULE_FIELDS)
            -- T127: the three marks on the what-if numbers (RR.Marks)
            local suggested, maxMark, effMark = RR.Marks(nf.ranks, nf.maxKnown, Book.RULE_FIELDS, fam.kind)
            if suggested then suggested.suggested = true end
            nf.suggested = suggested
            nf.maxRank, nf.effRank = maxMark, effMark
            RR.DominatedBy(nf.ranks, suggested, Book.RULE_FIELDS)
        end
        families[name] = nf
    end
    -- a spell outside every family (none on this line today) is copied as is
    for id, e in pairs(live.spells or {}) do
        if spells[id] == nil then spells[id] = CopyEntry(e, nil, nil, nil) end
    end
    return { families = families, order = live.order, spells = spells, read = live.read,
             generation = live.generation, whatIf = true }
end

provider.classRows = nil
provider.classNote = "Your talents are already in the spells' text, so there is no class row."

-- "2 of 3 ranks measured, 1 estimated" -- the shares the move rests on: a
-- heal family's while +Healing is typed, a damage family's while +Spell
-- damage is (T124; MeasureBonus measures damage ranks too, against their
-- school's spell damage -- an either-or heal's damage half stays estimated).
function provider.ranksNote(fam)
    if type(fam) ~= "table" then return nil end
    if fam.kind ~= "heal" and fam.kind ~= "damage" then return nil end
    if WI:Get(fam.kind) == nil then return nil end
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
