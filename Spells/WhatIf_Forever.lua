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
--   Crit %     each valued rank's `crit` (a chance, 0..1) moved by typed - live
--              (heals: the typed one; a damage school by the same step), and
--              its numbers re-derived -- the values average crit in (Spells/
--              Book.lua's CritFactor, direct and ticks alike, 2026-11-11);
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
--              T138: the drawer shows no talent rows any more -- the talent
--              plan (UI/TalentPlanner.lua) is the one place a talent is typed;
--              the keys stay rows here so the plan's values are accepted.
--   Level (T138) a heal rank's +healing share at the typed level: the share was
--              read (or estimated) under the live level's penalty
--              (Coefficients.LevelPenalty), so it moves by the ratio of the
--              two; nothing else moves. A rank is available at the typed
--              level when it is learned at or below it (Available): a rank
--              not learned yet (Spells/Book.lua's AddFutureRanks) competes for
--              the marks there, a learned one above the typed level does not.
--              A rank learned above the level it is priced at has no penalty
--              (P 1 below the start), one the typed level passes has it.
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
local LEVEL_KEY = "level"
local LEVEL_MAX = 60 -- Forever's cap (vanilla content)

local function PlayerLevel()
    local l = ST.player and ST.player.level
    return (type(l) == "number" and l > 0) and l or nil
end

local function LevelRow()
    return { key = LEVEL_KEY, label = "Level", min = 1, max = math.max(LEVEL_MAX, PlayerLevel() or 0),
             step = 1, bigStep = 5 }
end
local function SpiritRow()
    return { key = SPIRIT_KEY, label = "Spirit", min = 0, step = 25, bigStep = 100 }
end

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
                              expiry = ST.TalentExpiry, stat = ST.TalentStats,
                              -- 2026-11-11: crit chance, crit size, +bonus from Intellect
                              crit = ST.TalentCrit, critBonus = ST.TalentCritBonus,
                              statBonus = ST.TalentStatBonus }) do
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
    -- 2026-11-11: crit, crit size, Intellect (crit for every valued rank) and
    -- +bonus from Intellect (the heals or damage it names)
    if kind and info.crit and Book.CritScopeHits(info.crit.scope, e, kind) then return true end
    if kind and info.critBonus and Book.CritScopeHits(info.critBonus.scope, e, kind) then return true end
    if kind and info.stat and info.stat.scope.stat == "Intellect" then return true end
    if kind and info.statBonus and Has(info.statBonus.scope.kinds, kind) then return true end
    return false
end

local function LiveRanks()
    if not (Book and Book.Talents) then return nil end
    local ranks = Book:Talents()
    return (type(ranks) == "table") and ranks or nil
end

-- Every key the What if accepts beyond the stats: Level always, the talents
-- (typed by the plan) and Spirit only when the live ranks were read.
-- D (2026-11-16): the rows are the same until the class, the level or
-- whether the live ranks read changes, so they are built once for those --
-- TP:Modelled asked for them once per talent per paint (106 builds, 0.9 MB
-- a What if change in the author's report). Readers never write to them.
local rowsMemo, rowsKey
local function Rows()
    local live = LiveRanks() ~= nil
    local key = tostring(ST.player and ST.player.class) .. ":" .. tostring(PlayerLevel()) .. ":" .. tostring(live)
    if rowsMemo and rowsKey == key then return rowsMemo end
    local rows = { LevelRow() }
    rowsMemo, rowsKey = rows, key
    if not live then return rows end
    local index, spirit = TalentIndex(), false
    for _, name in ipairs(index.order) do
        local i = index.byName[name]
        if i.max > 0 then
            rows[#rows + 1] = { key = TALENT_PREFIX .. name, label = name, talent = name,
                                min = 0, max = i.max, step = 1, bigStep = 1, compact = true }
            if i.expiry then spirit = true end
        end
    end
    if spirit then rows[#rows + 1] = SpiritRow() end
    return rows
end

function provider.classRows() return Rows() end
provider.classTitle = "LEVEL AND TALENTS"

-- Does any talent of the class move a rank of this family?
local function FamilyTouched(fam)
    if type(fam) ~= "table" then return false end
    local index = TalentIndex()
    for _, name in ipairs(index.order) do
        local i = index.byName[name]
        for _, e in ipairs(fam.ranks or {}) do
            if i.max > 0 and Touches(i, e) then return true end
        end
    end
    return false
end

-- T138: the drawer's rows -- Level, and Spirit when a talent that reads it
-- (Bloom) touches the family on screen. No talent row: the plan types them.
function provider.classRowsFor(fam)
    local out = { LevelRow() }
    if not (LiveRanks() and type(fam) == "table") then return out end
    local index = TalentIndex()
    for _, name in ipairs(index.order) do
        local i = index.byName[name]
        if i.expiry and i.max > 0 then
            for _, e in ipairs(fam.ranks or {}) do
                if Has(i.expiry.scope.spells, e.name) then
                    out[#out + 1] = SpiritRow()
                    return out
                end
            end
        end
    end
    return out
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
    -- a stat talent moves its own stat only (2026-11-11: Intellect talents too)
    local function Moved(stat, value)
        if type(value) ~= "number" then return value end
        for _, i in ipairs(changed) do
            if i.stat and i.stat.scope.stat == stat then
                local a, b = PctAt(i.stat, live[i.name]), PctAt(i.stat, what[i.name])
                if a and b then value = value * (1 + b / 100) / (1 + a / 100) end
            end
        end
        return value
    end
    spirit = Moved("Spirit", spirit)
    -- 2026-11-11: Intellect -- the crit it gives (Coef.INT_PER_CRIT, assumed)
    -- and the +bonus a talent takes from it (Natural Instinct), live to planned
    local liveInt = Book.Intellect and Book:Intellect() or nil
    local planInt = Moved("Intellect", liveInt)
    local bonus = { heal = 0, damage = 0 }
    if type(liveInt) == "number" then
        for _, name in ipairs(index.order) do
            local i = index.byName[name]
            if i.statBonus and i.statBonus.scope.stat == "Intellect" then
                local a, b = PctAt(i.statBonus, live[name] or 0), PctAt(i.statBonus, what[name] or 0)
                if a and b then
                    local d = b / 100 * planInt - a / 100 * liveInt
                    for _, k in ipairs(i.statBonus.scope.kinds or {}) do bonus[k] = (bonus[k] or 0) + d end
                end
            end
        end
    end
    return { live = live, what = what, changed = changed, spirit = spirit, index = index,
             liveInt = liveInt, int = planInt, bonus = bonus }
end

-- 2026-11-11: the crit a plan moves rank `e` by (a fraction) and its crit
-- multiplier at the plan's ranks: every crit talent that reaches it, live to
-- planned, plus the planned Intellect's crit at Coef.INT_PER_CRIT (assumed).
local function PlanCrit(plan, e, kind)
    if not plan or not kind then return 0, nil end
    local a = Book.CritTalentAdd(e, kind, plan.live, true)
    local b = Book.CritTalentAdd(e, kind, plan.what, true)
    local d = b - a
    local Coef = ST.Coefficients
    local ratio = Coef and Coef.INT_PER_CRIT and Coef.INT_PER_CRIT[ST.player and ST.player.class]
    if type(ratio) == "number" and ratio > 0 and type(plan.int) == "number" and type(plan.liveInt) == "number" then
        d = d + (plan.int - plan.liveInt) / ratio / 100
    end
    return d, Book.CritMultFor(e, kind, plan.what)
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
    out[LEVEL_KEY] = PlayerLevel()
    out.heal = LiveBonus()
    out.damage = WI.LiveDamage(Book) -- T124: the school on screen
    local school = ST.ClassProfile and ST.ClassProfile.critSchool or 2
    local crit = ST.API.SpellCritChance and ST.API.SpellCritChance(school)
    if type(crit) == "number" and crit == crit then
        out.crit = crit
    elseif Book and Book.CritNow then -- secret in combat: the last plain reading
        local c = Book.CritNow("heal")
        if type(c) == "number" then out.crit = c * 100 end
    end
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

-- T138: a heal rank's share at the typed level, from its live one (read or
-- estimated under the live level's penalty), by the ratio of the penalties;
-- nil when nothing moves, or when the live share is 0 (what it was before the
-- penalty took it is not known).
local function LevelShare(e, kind, lvl, counts)
    if not lvl or kind ~= "heal" or type(counts) ~= "number" then return nil end
    local Coef = ST.Coefficients
    if not (Coef and Coef.LevelPenalty) then return nil end
    local pa = Coef.LevelPenalty(e.id, e.level, lvl.live, kind)
    local pb = Coef.LevelPenalty(e.id, e.level, lvl.typed, kind)
    if pa == pb or pa <= 0 then return nil end
    return counts * pb / pa
end

-- Whether rank `e` is available at the typed level: learned at or below it.
-- No level typed, or a rank with no learn level: as the live book has it.
local function Available(e, lvl)
    if not lvl or type(e.level) ~= "number" then return e.known end
    return e.level <= lvl.typed
end

-- T124: the stat a family of `kind` moves with -- +Healing for a heal,
-- +Spell damage for a damage family; { d = typed - live, typed } or nil.
local function CopyEntry(e, move, crit, kind, plan, lvl)
    local w = {}
    for k, v in pairs(e) do w[k] = v end
    local talented = plan and kind and ApplyTalents(w, e, kind, plan) or false
    local b = w.bonus
    local d = 0
    local delta = move and move.delta or 0
    local typed = move and move.typed or nil
    local counts = type(b) == "table" and b.counts or nil
    -- T138: the level moves the share; the value moves by the share's change
    -- at the live bonus (no live bonus read: the level moves nothing)
    local levelCounts = LevelShare(e, kind, lvl, counts)
    if levelCounts and type(b.of) ~= "number" then levelCounts = nil end
    if levelCounts then d = (levelCounts - counts) * b.of end
    local share = levelCounts or counts
    if delta ~= 0 and type(share) == "number" then d = d + share * delta end
    if d ~= 0 and type(w.parsed) ~= "table" then d = 0 end
    if d ~= 0 then
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
    local bonusTyped = typed ~= nil and not move.noLive
    if type(b) == "table" and (bonusTyped or levelCounts) then
        local nb = {}
        for k, v in pairs(b) do nb[k] = v end
        if bonusTyped then nb.of = (type(b.of) == "number") and (b.of + delta) or typed end
        if levelCounts then nb.counts, nb.atLevel = levelCounts, lvl.typed end
        nb.amount = (type(nb.counts) == "number" and type(nb.of) == "number") and nb.counts * nb.of or nil
        w.bonus = nb
    end
    -- the crit chance at the typed Crit %: moved by typed - live (crit is
    -- { typed, live } in percent), a rank with no reading at the typed one
    -- 2026-11-11: and by the plan's crit talents and Intellect, and its crit size
    local critMoved = false
    local planD, planMult = 0, nil
    if plan and (kind == "heal" or kind == "damage") then planD, planMult = PlanCrit(plan, e, kind) end
    if (crit ~= nil or planD ~= 0) and (kind == "heal" or kind == "damage") and w.value ~= nil then
        local c = e.crit
        if crit ~= nil then
            if type(e.crit) == "number" and type(crit.live) == "number" then
                c = e.crit + (crit.typed - crit.live) / 100
            else
                c = crit.typed / 100
            end
        end
        if type(c) == "number" then
            c = math.max(0, math.min(1, c + planD))
            if c ~= e.crit then w.crit, critMoved = c, true end
        end
    end
    local oldMult = (type(e.critMult) == "number") and e.critMult or Book.CRIT_MULT
    if planMult and planMult ~= oldMult then
        w.critMult = (planMult ~= Book.CRIT_MULT) and planMult or nil
        critMoved = true
    end
    if d ~= 0 or critMoved then Book.Numbers(w, kind) end
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

local bookMemo, bookKey
function provider.Book()
    if not (Book and Book.Get) then return nil end
    if Book.WantFuture then Book:WantFuture() end -- a typed Level lets them compete
    local live = Book:Get()
    if type(live) ~= "table" then return nil end
    local liveStats = { heal = LiveBonus(), damage = WI.LiveDamage(Book) }
    local moves = { heal = Move("heal", liveStats), damage = Move("damage", liveStats) }
    local plan = TalentPlan() -- T134
    -- 2026-11-11: +bonus from Intellect the plan moves (Natural Instinct), on top
    -- of a typed +Healing / +Spell damage; nothing without a live bonus reading
    for kind, add in pairs(plan and plan.bonus or {}) do
        if add ~= 0 and type(liveStats[kind]) == "number" then
            local m = moves[kind]
            if m and not m.noLive then
                m.delta = m.delta + add
            elseif not m then
                moves[kind] = { delta = add, typed = liveStats[kind] + add }
            end
        end
    end
    local typedCrit = WI:Get("crit")
    local crit = nil
    if typedCrit ~= nil then
        local liveCrit = Book.CritNow and Book.CritNow("heal")
        crit = { typed = typedCrit, live = (type(liveCrit) == "number") and liveCrit * 100 or nil }
    end
    local pool = WI:Pool(Book:Pool())
    local castPool = { max = pool.max, regenCasting = pool.regenCasting }
    local typedLevel, liveLevel = WI:Get(LEVEL_KEY), PlayerLevel()
    local lvl = (typedLevel ~= nil and liveLevel ~= nil and typedLevel ~= liveLevel)
        and { live = liveLevel, typed = typedLevel } or nil -- T138

    -- D (2026-11-16): one what-if book per What if change. The Spells pane
    -- asks for it from the view, every rail row and every cell's hover; it is
    -- built again only when what it is built from moved: the live book (its
    -- table or generation), the typed values (WI.serial), the live readings
    -- it moves from, the pool.
    local key = string.format("%s:%s:%s:%s:%s:%s:%s:%s:%s", tostring(live), tostring(live.generation),
        tostring(WI.serial), tostring(liveStats.heal), tostring(liveStats.damage),
        tostring(crit and crit.live), tostring(castPool.max), tostring(castPool.regenCasting), tostring(liveLevel))
    if bookMemo and bookKey == key then return bookMemo end

    local spells, families = {}, {}
    for name, fam in pairs(live.families or {}) do
        local nf = {}
        for k, v in pairs(fam) do nf[k] = v end
        nf.ranks = {}
        nf.maxKnown = nil
        for i, e in ipairs(fam.ranks or {}) do
            local w = CopyEntry(e, moves[fam.kind or ""], crit, fam.kind, plan, lvl)
            w.casts = Book:CastsFor(w, castPool)
            w.known = Available(e, lvl)
            nf.ranks[i] = w
            spells[e.id] = w
            if w.known and w.rank and (not nf.maxKnown or w.rank > nf.maxKnown.rank) then nf.maxKnown = w end
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
    bookMemo, bookKey = { families = families, order = live.order, spells = spells, read = live.read,
             generation = live.generation, whatIf = true }, key
    return bookMemo
end

-- T134, T138: under the rows -- what the level moves, the talents the plan
-- typed (the plan is the one place to change them), what is not modelled.
function provider.classNote(fam)
    local out = {}
    local typedLevel = WI:Get(LEVEL_KEY)
    if typedLevel ~= nil then
        out[#out + 1] = "Level " .. typedLevel .. ": the ranks learned by then compete, each heal rank's"
            .. " +healing share at that level's penalty."
    end
    local live = LiveRanks()
    if not live then
        out[#out + 1] = "Your talents were not read yet, so a talent plan can't be tried here."
        return table.concat(out, " ")
    end
    local index, planned = TalentIndex(), {}
    for _, name in ipairs(index.order) do
        local v = WI:Get(TALENT_PREFIX .. name)
        if v ~= nil and v ~= (live[name] or 0) then planned[#planned + 1] = name .. " " .. v end
    end
    if #planned > 0 then
        out[#out + 1] = "Talents from your plan: " .. table.concat(planned, ", ") .. "."
    else
        out[#out + 1] = "Your own talents; Talent plan... tries a build."
    end
    if type(fam) == "table" and not FamilyTouched(fam) then
        out[#out + 1] = "No talent moves this spell in the What if."
    else
        out[#out + 1] = "Preliminary, from talentsforever; Intellect to crit at vanilla's level-60 rate. Not moved: regen,"
            .. " procs, Oath of Light, spells a talent teaches."
    end
    return table.concat(out, " ")
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
