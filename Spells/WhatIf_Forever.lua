-- Spells/WhatIf_Forever.lua (T122, docs/tasks/T122-what-if.md): the What if's
-- provider on Forever. The Forever main TOCs, after Spells/WhatIf.lua.
--
-- The client's own spell text already carries the caster's gear and talents
-- (Q1), so the what-if book is the live book COPIED and moved, never rescanned:
--   +Healing   each heal rank's value moves by its own share of the change
--              (entry.bonus.counts -- measured when Spells/Book.lua's
--              MeasureBonus's fit of the plain readings is narrow (T131), else Spells/
--              Coefficients.lua's estimate; a rank with neither stays put),
--              its parts moved with it, then per mana / per second
--              re-derived through Book.Numbers and the rank rules re-run
--              (Book.RULE_FIELDS);
--   +Spell damage (T124)
--              each damage rank the same way by its share of the change in
--              its school's bonus (entry.bonus.counts: measured when
--              MeasureBonus's fit of the plain readings of that school's
--              spell damage, else estimated; the live side the school on
--              screen, WI.LiveDamage; every school moves by one delta);
--   Crit %     each valued heal rank's `crit` (a chance, 0..1) -- the values
--              are averages without crit (the card's Crit pair names it);
--   Mana / Regen while casting
--              the pool casts to OOM are counted from (from full).
--   Talents (T134, docs/tasks/T134-forever-launch-talents.md)
--              a typed rank moves each rank's numbers from the live ranks to
--              the typed ones, by the generated tables (Data/Talents_Forever.lua,
--              PRELIMINARY): a multiplier scales the parts and the share by
--              typed / live, a cast talent moves the cast, a cost talent the
--              cost (percents added, assumed), an expiry talent re-prices Bloom
--              at the typed Spirit x the stat talents' typed / live. Crit,
--              regen, a +healing-from-a-stat talent and a spell a
--              talent teaches do not move (the sentence says so). Off when the
--              live ranks were not read: a ratio needs them.
-- The live book, its generation and its entries are never written.
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

--------------------------------------------------------------------------------
-- T134: what each talent of the class can move, from the generated tables.
--------------------------------------------------------------------------------
local TALENT_PREFIX = "talent:"
local SPIRIT_KEY = "spirit"

local talentIndex, talentIndexClass

local function TalentIndex()
    local class = ST.player and ST.player.class
    if talentIndexClass == class and talentIndex then return talentIndex end
    local byName, order = {}, {}
    local function Info(name)
        local i = byName[name]
        if not i then
            i = { name = name, max = 0, cast = {}, dur = {} }
            byName[name] = i
            order[#order + 1] = name
        end
        return i
    end
    local function Grow(i, list)
        if type(list) == "table" and #list > i.max then i.max = #list end
    end
    for k, r in pairs(ST.TalentRules and ST.TalentRules[class] or {}) do
        local i = Info(r.talent or k)
        i.cast[#i.cast + 1] = r
        Grow(i, r.castPerRank)
    end
    -- T136: a longer spell, one rule per group of spells
    for k, r in pairs(ST.TalentDurations and ST.TalentDurations[class] or {}) do
        local i = Info(r.talent or k)
        i.dur[#i.dur + 1] = r
        Grow(i, r.secPerRank)
    end
    for field, tbl in pairs({ mult = ST.TalentMults, cost = ST.TalentCosts,
                              expiry = ST.TalentExpiry, stat = ST.TalentStats }) do
        for k, r in pairs(type(tbl) == "table" and tbl[class] or {}) do
            local i = Info(k)
            i[field] = r
            Grow(i, r.pctPerRank)
        end
    end
    table.sort(order)
    talentIndex, talentIndexClass = { byName = byName, order = order }, class
    return talentIndex
end

local function Has(list, name)
    for _, n in ipairs(type(list) == "table" and list or {}) do
        if n == name then return true end
    end
    return false
end

-- T136: a part that runs over time and is not a channel (a channel's ticks are its cast)
local function OverTime(part)
    return type(part) == "table" and ((part.over ~= nil and type(part.dur) == "number" and part.dur > 0)
        or (part.tick ~= nil and type(part.periodDur) == "number" and part.periodDur > 0))
end

local function DurRuleHits(rule, e)
    if e.castKind == "channeled" or not Has(rule.spells, e.name) then return false end
    local p = type(e.parsed) == "table" and e.parsed or {}
    return OverTime(p.heal) or OverTime(p.damage)
end

local function CastRuleHits(rule, e)
    return type(e.cast) == "number" and e.castKind ~= "channeled" and Has(rule.spells, e.name)
end

-- Does this talent move this rank at all?
local function Touches(info, e)
    local kind = Book.EntryKind(e)
    for _, rule in ipairs(info.cast) do
        if CastRuleHits(rule, e) then return true end
    end
    for _, rule in ipairs(info.dur) do
        if DurRuleHits(rule, e) then return true end
    end
    if kind and info.mult and Book.MultMatches(info.mult.scope, e, kind) then return true end
    if kind and info.cost and Book.ScopeMatches(info.cost.scope, e, kind) then return true end
    if info.expiry and Has(info.expiry.scope.spells, e.name) then return true end
    return false
end

local function LiveRanks()
    if not (Book and Book.Talents) then return nil end
    local ranks = Book:Talents()
    return (type(ranks) == "table") and ranks or nil
end

local function Rows()
    if not LiveRanks() then return nil end
    local index, rows, spirit = TalentIndex(), {}, false
    for _, name in ipairs(index.order) do
        local i = index.byName[name]
        if i.max > 0 then
            rows[#rows + 1] = { key = TALENT_PREFIX .. name, label = name, talent = name,
                                min = 0, max = i.max, step = 1, bigStep = 1, compact = true }
            if i.expiry then spirit = true end
        end
    end
    if spirit then
        rows[#rows + 1] = { key = SPIRIT_KEY, label = "Spirit", min = 0, step = 25, bigStep = 100 }
    end
    return (#rows > 0) and rows or nil
end

function provider.classRows() return Rows() end
provider.classTitle = "TALENTS"

-- T134: only the talents that move a rank of the family on screen (the drawer
-- is a window high); Spirit with a talent that reads it, or raises it.
function provider.classRowsFor(fam)
    local rows = Rows()
    if not rows or type(fam) ~= "table" then return rows end
    local index, out, spirit = TalentIndex(), {}, false
    for _, row in ipairs(rows) do
        local i = row.talent and index.byName[row.talent]
        if i then
            local hit = false
            for _, e in ipairs(fam.ranks or {}) do
                if Touches(i, e) then hit = true break end
            end
            if hit then
                out[#out + 1] = row
                if i.expiry then spirit = true end
            end
        end
    end
    if spirit then
        for _, name in ipairs(index.order) do
            local i = index.byName[name]
            if i.stat and i.max > 0 then
                out[#out + 1] = { key = TALENT_PREFIX .. name, label = name, talent = name,
                                  min = 0, max = i.max, step = 1, bigStep = 1, compact = true }
            end
        end
        out[#out + 1] = { key = SPIRIT_KEY, label = "Spirit", min = 0, step = 25, bigStep = 100 }
    end
    return (#out > 0) and out or nil
end

-- The percent a rank gives under a rule (rank 0: none), nil above the rule.
local function PctAt(rule, r)
    if type(r) ~= "number" or r <= 0 then return 0 end
    return rule.pctPerRank[r]
end

-- The plan one what-if book moves by, or nil when nothing talent-like is typed.
local function TalentPlan()
    local live = LiveRanks()
    if not live then return nil end
    local index = TalentIndex()
    local what, changed = {}, {}
    for k, v in pairs(live) do what[k] = v end
    for _, name in ipairs(index.order) do
        local typed = WI:Get(TALENT_PREFIX .. name)
        if typed ~= nil and typed ~= (live[name] or 0) then
            what[name] = typed
            changed[#changed + 1] = index.byName[name]
        end
    end
    local typedSpirit = WI:Get(SPIRIT_KEY)
    if #changed == 0 and typedSpirit == nil then return nil end
    local spirit = typedSpirit
    if spirit == nil then spirit = Book:Spirit() end
    if type(spirit) == "number" then
        for _, i in ipairs(changed) do
            if i.stat then
                local a, b = PctAt(i.stat, live[i.name]), PctAt(i.stat, what[i.name])
                if a and b then spirit = spirit * (1 + b / 100) / (1 + a / 100) end
            end
        end
    end
    return { live = live, what = what, changed = changed, spirit = spirit, index = index }
end

-- T136: d seconds more of the over-time part, the same amount a second: the
-- amount over time grows by (dur + d) / dur; a tick part ticks d seconds longer.
local function LongerPart(part, d)
    local out = {}
    for k, v in pairs(part) do out[k] = v end
    if out.over ~= nil and type(out.dur) == "number" and out.dur > 0 then
        local dur = math.max(0, out.dur + d)
        out.over = out.over * dur / out.dur
        out.dur = dur
    elseif out.tick ~= nil and type(out.periodDur) == "number" then
        out.periodDur = math.max(0, out.periodDur + d)
    end
    return out
end

local function ScalePart(part, ratio, tickRatio)
    if type(part) ~= "table" then return part end
    local out = {}
    for k, v in pairs(part) do out[k] = v end
    if out.min ~= nil then out.min = out.min * ratio end
    if out.max ~= nil then out.max = out.max * ratio end
    if out.over ~= nil then out.over = out.over * ratio * tickRatio end
    if out.tick ~= nil then out.tick = out.tick * ratio * tickRatio end
    return out
end

-- Moves the copy `w` of entry `e` by the plan; true when a number moved.
local function ApplyTalents(w, e, kind, plan)
    local dirty = false
    local entryKind = Book.EntryKind(e)
    local castMove, durMove = 0, 0
    -- each half by the talents that reach it: Twin Disciplines both, a heal talent one
    local function Ratios(part)
        local r, t = 1, 1
        for _, i in ipairs(plan.changed) do
            if i.mult and Book.MultMatches(i.mult.scope, e, part) then
                local a, b = PctAt(i.mult, plan.live[i.name] or 0), PctAt(i.mult, plan.what[i.name] or 0)
                if a and b then
                    local f = (1 + b / 100) / (1 + a / 100)
                    if i.mult.scope.periodic then t = t * f else r = r * f end
                end
            end
        end
        return r, t
    end
    for _, i in ipairs(plan.changed) do
        local L, W = plan.live[i.name] or 0, plan.what[i.name] or 0
        for _, rule in ipairs(i.dur) do
            if DurRuleHits(rule, e) then
                local a = (L > 0) and rule.secPerRank[L] or 0
                local b = (W > 0) and rule.secPerRank[W] or 0
                if a and b then durMove = durMove + b - a end
            end
        end
        for _, rule in ipairs(i.cast) do
            if CastRuleHits(rule, e) then
                local a = (L > 0) and rule.castPerRank[L] or 0
                local b = (W > 0) and rule.castPerRank[W] or 0
                if a and b then castMove = castMove + a - b end
            end
        end
    end
    if entryKind and (kind == "heal" or kind == "damage") then
        local parsed
        for _, part in ipairs({ "heal", "damage" }) do
            local r, t = Ratios(part)
            if e.parsed[part] ~= nil and (r ~= 1 or t ~= 1) then
                if not parsed then
                    parsed = {}
                    for k, v in pairs(e.parsed) do parsed[k] = v end
                end
                parsed[part] = ScalePart(parsed[part], r, t)
            end
        end
        local r = Ratios("heal")
        if type(e.parsed.absorb) == "number" and r ~= 1 then
            if not parsed then
                parsed = {}
                for k, v in pairs(e.parsed) do parsed[k] = v end
            end
            parsed.absorb = parsed.absorb * r
        end
        -- T136: a longer spell, after the multipliers (they commute)
        if durMove ~= 0 then
            for _, part in ipairs({ "heal", "damage" }) do
                local src = (parsed or e.parsed)[part]
                if OverTime(src) then
                    if not parsed then
                        parsed = {}
                        for k, v in pairs(e.parsed) do parsed[k] = v end
                    end
                    parsed[part] = LongerPart(src, durMove)
                end
            end
        end
        if parsed then
            w.parsed = parsed
            dirty = true
        end
    end
    if castMove ~= 0 then
        w.cast = math.max(0, e.cast + castMove)
        w.castKind = (w.cast > 0) and "cast" or "instant" -- review m1: an instant is said as one
        dirty = true
    end
    -- the cost: every cost talent that names this rank, percents added (assumed)
    local amount = type(e.cost) == "table" and e.cost.amount
    if type(amount) == "number" and entryKind then
        local sumL, sumW = 0, 0
        for _, name in ipairs(plan.index.order) do
            local i = plan.index.byName[name]
            if i.cost and Book.ScopeMatches(i.cost.scope, e, entryKind) then
                sumL = sumL + (PctAt(i.cost, plan.live[name] or 0) or 0)
                sumW = sumW + (PctAt(i.cost, plan.what[name] or 0) or 0)
            end
        end
        if sumL ~= sumW and sumL < 100 then
            local cost = {}
            for k, v in pairs(e.cost) do cost[k] = v end
            cost.amount = math.floor(amount * (100 - math.min(sumW, 100)) / (100 - sumL) + 0.5)
            w.cost = cost
            dirty = true
        end
    end
    -- Bloom at the typed ranks and the typed Spirit
    local ex = Book.ExpiryFor(e, plan.what, plan.spirit)
    local old, new = e.expiryHeal, ex
    if (old and old.amount) ~= (new and new.amount) or (old and old.words) ~= (new and new.words) then
        w.expiryHeal = ex
        dirty = true
    end
    if dirty then
        Book.Numbers(w, kind)
        local b = e.bonus
        -- the share moves with the amount: the multiplier is on the whole spell
        if type(b) == "table" and type(b.counts) == "number" and type(e.textValue) == "number"
            and e.textValue > 0 and type(w.textValue) == "number" and w.textValue ~= e.textValue then
            local nb = {}
            for k, v in pairs(b) do nb[k] = v end
            nb.counts = b.counts * w.textValue / e.textValue
            nb.amount = (type(nb.of) == "number") and nb.counts * nb.of or nil
            nb.movedFrom = b.counts
            w.bonus = nb
        end
    end
    return dirty
end

function provider.Live()
    local out = {}
    local ranks = LiveRanks()
    if ranks then
        for _, name in ipairs(TalentIndex().order) do
            out[TALENT_PREFIX .. name] = ranks[name] or 0
        end
    end
    if Book and Book.Spirit then out[SPIRIT_KEY] = Book:Spirit() end
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
local function CopyEntry(e, move, crit, kind, plan)
    local w = {}
    for k, v in pairs(e) do w[k] = v end
    local talented = plan and kind and ApplyTalents(w, e, kind, plan) or false
    local b = w.bonus
    local d = 0
    local delta = move and move.delta or 0
    local typed = move and move.typed or nil
    if delta ~= 0 and type(b) == "table" and type(b.counts) == "number" and type(w.parsed) == "table" then
        d = b.counts * delta
        local parsed = {}
        for k, v in pairs(w.parsed) do parsed[k] = v end
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
    local plan = TalentPlan() -- T134

    local spells, families = {}, {}
    for name, fam in pairs(live.families or {}) do
        local nf = {}
        for k, v in pairs(fam) do nf[k] = v end
        nf.ranks = {}
        for i, e in ipairs(fam.ranks or {}) do
            local w = CopyEntry(e, moves[fam.kind or ""], crit, fam.kind, plan)
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

-- T134: under the rows, what they move; no rows when the live ranks are unread.
function provider.classNote(fam)
    if not LiveRanks() then
        return "Your talents were not read yet, so a talent can't be tried here."
    end
    if type(fam) == "table" and not provider.classRowsFor(fam) then
        return "No talent moves this spell in the What if."
    end
    return "Preliminary, from talentsforever. Not moved: crit, regen, stat-to-bonus talents,"
        .. " procs, Oath of Light, spells a talent teaches."
end

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
