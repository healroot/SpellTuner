-- T118 (docs/tasks/T118-tbc-book.md, docs/SPEC-one-ui.md 3.2): MD.Book on
-- TBC -- the book contract T117 wrote (Spells/BookShape.lua), built out of
-- the model the TBC line already has, so the Spells pane (T120) and the
-- tooltip block (T121) can be one file on both lines.
--
-- AN ADAPTER, NOT A SECOND MODEL. Every heal number is the RankMath row's
-- (RankMath:Compute({ live = true })), field for field; every damage number
-- is Engine/DamageMath.lua's DM.Compute; the text, cooldown, reach and
-- lockout of a rank come from the scan tooltip through Spells/Book_TBC.lua's
-- B.Read (Spells/Parse.lua's readers, as on Forever). Nothing is computed
-- twice.
--
--   heals   RankMath's families in SD.familyOrder, Lifebloom's rolling
--           stacks as `variants`; Tranquility and Swiftmend (SpellData's
--           `exclude`) as heal families with `noSeed` and no value
--           (Swiftmend's calc: the two "Eats" lines)
--   damage  the logged-in class's (DM.FamiliesFor: the druid's DM.families,
--           else -- T123 -- the class profile's `damage`), walked from the
--           spellbook in DM.OrderFor's order, each rank read from its own
--           text; wherever the rank table is granted
--   Other   every walked spell no family claims that is not passive and
--           costs mana, one family per name (Forever's Other rule, T10c)
--
-- LIVE. Get() never reads MD.sim. Get({ whatIf = true }) is the one door
-- the What if (T122) reaches the book through: built from RankMath:Compute()
-- (which reads MD.sim), never cached, never announced, the generation left
-- alone.
--
-- The generation (Spells/Book.lua's rule): bumped by a build whose
-- signature -- every family key, and per entry its id, known, value, cost,
-- cast, per mana, per second, suggested and dominated marks -- differs from
-- the last; the pool-dependent casts and the measured afterOverheal are left
-- out. A moved signature fires BOOK_CHANGED with the book (Spells/Tabs.lua
-- reconciles the spell list there, on both lines now). Rebuilt on
-- SPELLS_REBUILT, TALENTS_CHANGED, FORM_CHANGED, UNIT_INVENTORY_CHANGED
-- (player) and PLAYER_LEVEL_UP once the book has been read; there is no
-- OVERHEAL_CHANGED, so the 2-s cache (Book:Get) catches the rest.
--
-- TBC TOC only, in Spells/Families_TBC.lua's place (after Engine/RankMath.lua
-- and Spells/Tabs.lua; Engine/DamageMath.lua is read at run time).
local _, MD = ...

local BS = MD.BookShape

local Book = {}
MD.Book = Book

Book.GCD = 1.5
Book.generation = 0
Book._cache = nil
Book._cacheTime = nil
Book._sig = nil
Book._bonus = nil

local CACHE_SECONDS = 2
local NG_NOTE = "Nature's Grace averaged"

local function Now()
    local t = type(GetTime) == "function" and GetTime() or 0
    return type(t) == "number" and t or 0
end

local function R(v) return math.floor((v or 0) + 0.5) end

local function Profile() return MD.ClassProfile end
local function CanRankTable()
    local p = Profile()
    return p ~= nil and p:Can("rankTable") == true
end

local function Reader() return MD.BookTBC end

-- B.Read(id), or an empty read when the reader is absent
local function Read(id)
    local B = Reader()
    local r = B and type(B.Read) == "function" and B.Read(id) or nil
    return type(r) == "table" and r or {}
end

local function SpellName(id)
    local fn = MD.API and MD.API.SpellName
    if type(fn) ~= "function" then return nil end
    local n = fn(id)
    return type(n) == "string" and n ~= "" and n or nil
end

local function Icon(id)
    local fn = MD.API and MD.API.SpellTexture
    if type(fn) ~= "function" then return nil end
    local tex = fn(id)
    if type(tex) == "string" or type(tex) == "number" then return tex end
    return nil
end

local function Cost(amount)
    amount = type(amount) == "number" and amount or 0
    return { amount = amount, power = 0 }, amount > 0 and "ok" or "free"
end

-- the text and the reads Spells/Book_TBC.lua made for this rank
local function ApplyRead(e, id)
    local r = Read(id)
    if type(r.desc) == "string" and r.desc ~= "" then
        e.desc, e.descState = r.desc, "ok"
    else
        e.descState = "empty"
    end
    if type(r.cooldown) == "number" then e.cooldown = r.cooldown end
    if type(r.targets) == "string" then e.targets = r.targets end
    if type(r.reach) == "table" then e.reach = r.reach end
    if type(r.targetsWhy) == "string" then e.targetsWhy = r.targetsWhy end
    if type(r.lockout) == "number" then e.lockout = r.lockout end
    return r
end

--------------------------------------------------------------------------------
-- Heal entries: bonus and calc from the explained row
--------------------------------------------------------------------------------

local SHAPE = { direct = "direct", hot = "hot", hybrid = "hybrid", lifebloom = "bloom",
                channel = "channel", instant = "none" }
-- a class row's types (RankMath.ClassRow): one target's direct heal
local CLASS_DIRECT = { group = true, chain = true, selfAndTarget = true }
local INSTANT = { hot = true, lifebloom = true, instant = true }

-- Tip:Spell's words for the bonus multipliers (UI/Tip_TBC.lua; T121 deletes
-- its copy)
local SHORT = { ["Empowered Rejuvenation"] = "Emp. Rejuvenation", ["Empowered Touch"] = "Emp. Touch" }

-- the share of +healing the rank gets: every factor RankMath applies to it
local function HealBonus(c, level, playerLevel)
    if type(c) ~= "table" or type(c.bonus) ~= "number" then return nil end
    local pen, mult = c.penalty or 1, c.bonusMult or 1
    local counts, amount
    if c.kind == "direct" or c.kind == "hot" then
        if type(c.coef) ~= "number" then return nil end
        counts = c.coef * pen * mult
        amount = c.bonusOut
    elseif c.kind == "hybrid" then
        counts = (c.directCoef + c.hotCoef * mult) * pen
        amount = c.directBonus + c.hotBonus
    elseif c.kind == "lifebloom" then
        counts = (c.hotCoef + c.bloomCoef) * pen * mult
        amount = c.hotBonus + c.bloomBonus
    else
        return nil
    end
    local why = {}
    if mult > 1.0001 and type(c.bonusMultName) == "string" and c.bonusMultName ~= "" then
        why[#why + 1] = string.format("x%.2f %s%s", mult, c.bonusMultName,
            c.kind == "hybrid" and " (HoT)" or "")
    end
    local C = MD.Coefficients
    if C and type(level) == "number" and type(playerLevel) == "number" then
        local d = C.Downrank(level, playerLevel)
        if d < 0.999 then why[#why + 1] = string.format("downrank %.2f", d) end
        local s = C.Sub20(level)
        if s < 0.999 then why[#why + 1] = string.format("level %d x%.2f", level, s) end
    end
    return { counts = counts, from = "model", amount = amount, of = c.bonus,
             why = #why > 0 and table.concat(why, ", ") or nil }
end

-- Tip:Spell's Shift lines (UI/Tip_TBC.lua), plain: one term per part --
-- the label only where there are two parts --, the talent multiplier, the
-- Tree of Life aura
local function HealCalc(c, treeAura)
    if type(c) ~= "table" then return nil end
    local out = {}
    local function term(label, base, bonus, amount, coef, mult, multName)
        local t = string.format("%d healing x %.3f coef", R(bonus), coef)
        if (c.penalty or 1) < 0.999 then t = t .. string.format(" x %.2f downrank", c.penalty) end
        if mult and mult > 1.0001 then
            t = t .. string.format(" x %.2f %s", mult, SHORT[multName] or multName or "")
        end
        out[#out + 1] = string.format("%s%d base + %d", label and (label .. " ") or "", R(base), R(amount))
        out[#out + 1] = "  " .. t
    end
    local base = (c.base or 0) + (c.relicFlat or 0)
    if c.kind == "direct" or c.kind == "hot" then
        term(nil, base, c.bonus, c.bonusOut, c.coef, c.bonusMult, c.bonusMultName)
    elseif c.kind == "hybrid" then
        term("direct", base, c.bonus, c.directBonus, c.directCoef)
        term("HoT", c.hotBase, c.bonus, c.hotBonus, c.hotCoef, c.bonusMult, c.bonusMultName)
    elseif c.kind == "lifebloom" then
        term("HoT", base, c.bonus, c.hotBonus, c.hotCoef, c.bonusMult, c.bonusMultName)
        term("bloom", c.bloomBase, c.bonus, c.bloomBonus, c.bloomCoef, c.bonusMult, c.bonusMultName)
    else
        return nil
    end
    if (c.talentMult or 1) > 1.0001 then
        local name = type(c.talentName) == "string" and c.talentName or ""
        out[#out + 1] = (string.format("  then x %.2f %s", c.talentMult, name):gsub("%s+$", ""))
    end
    if (treeAura or 0) > 0 then
        out[#out + 1] = string.format("  +healing includes %d Tree of Life aura", R(treeAura))
    end
    return out
end

local function AfterOverheal(row)
    if not row.overheal then return nil end
    return { value = row.effHeal, perMana = row.effHpm, perSec = row.effHps,
             frac = row.overheal.frac, scope = row.overheal.scope }
end

-- the book's field map for Spells/RankRules.lua (Spells/Book.lua's)
local BOOK_FIELDS = {
    eff = "perMana", rate = "perSec", value = "value",
    eligible = function(e) return e.known and e.perMana and e.perSec end,
}

local function HealFamily(book, src, key, res, ctx)
    local RM, RR = MD.RankMath, MD.RankRules
    local info = src.families[key]
    local fam = { key = key, name = info.label or key, kind = "heal", shape = SHAPE[info.type] or "direct",
                  ids = {}, ranks = {} }
    if CLASS_DIRECT[info.type] then fam.shape = "direct" end
    local last
    for _, row in ipairs(res.rows) do
        if row.variant then
            if last and last.id == row.id then
                last.variants = last.variants or {}
                last.variants[#last.variants + 1] = {
                    variant = row.variant, variantLabel = "x" .. row.variant,
                    value = row.heal, perMana = row.hpm, perSec = row.hps, casts = row.casts,
                    cost = row.cost, cast = row.cast, afterOverheal = AfterOverheal(row),
                }
            end
        else
            local id = row.id
            local e = { id = id, family = key, name = SpellName(id) or fam.name,
                        rank = row.rank, rankText = row.rank and ("Rank " .. row.rank) or nil,
                        level = row.level, known = row.known == true, icon = Icon(id),
                        value = row.heal, perMana = row.hpm, perSec = row.hps, casts = row.casts,
                        cast = row.cast, castKind = INSTANT[info.type] and "instant" or "cast",
                        castNote = row.ng and NG_NOTE or nil,
                        interval = row.cast, intervalBy = "cast",
                        dominated = row.dominated and true or nil, suggested = row.suggested and true or nil,
                        afterOverheal = AfterOverheal(row) }
            e.cost, e.costState = Cost(row.cost)
            ApplyRead(e, id)
            local ex = RM:RowFor(id, ctx, nil, true)
            local c = ex and ex.calc
            if c then
                if c.kind == "direct" or c.kind == "hybrid" then
                    e.min, e.max, e.crit = c.min, c.max, c.crit
                end
                if c.kind == "hot" then
                    e.over, e.dur = row.heal, c.duration
                elseif c.kind == "hybrid" or c.kind == "lifebloom" then
                    e.over, e.dur = c.hot, c.duration
                end
                -- a class row paced by its cooldown (Holy Shock): per second
                -- is over that interval (RankMath.ClassRow)
                if type(c.interval) == "number" and c.interval > row.cast then
                    e.interval, e.intervalBy = c.interval, "cooldown"
                end
                e.bonus = HealBonus(c, row.level, ctx.playerLevel)
                e.calc = HealCalc(c, ctx.treeAura)
            end
            fam.ids[#fam.ids + 1] = id
            fam.ranks[#fam.ranks + 1] = e
            book.spells[id] = e
            if e.known then fam.maxKnown = e end
            if res.suggestedID == id then fam.suggested = e end
            last = e
        end
    end
    RR.DominatedBy(fam.ranks, fam.suggested, BOOK_FIELDS)
    return fam
end

-- Swiftmend's worth: the HoT it eats, the highest known rank of each, at
-- these stats (Tip:Spell's "Eats" lines, computed as it computes them)
local function EatsLines(src, ctx)
    local RM = MD.RankMath
    local out = {}
    local function eat(family, seconds, label)
        local id = src.maxRank and src.maxRank[family]
        local row = id and RM:RowFor(id, ctx, nil, true)
        local c = row and row.calc
        if not c then return end
        local hot = (c.kind == "hybrid") and c.hot or row.heal
        local ticks = (c.kind == "hybrid") and (c.duration / 3) or c.ticks
        local n = math.min(ticks, seconds / 3)
        out[#out + 1] = string.format("Eats %s  %d  (%ds of its ticks)", label, R(hot / ticks * n), seconds)
    end
    eat("Rejuvenation", 12, "Rejuvenation")
    eat("Regrowth", 18, "Regrowth")
    return #out > 0 and out or nil
end

-- Tranquility, Swiftmend: offered by the picker, never seeded; no value
local function PlainHealFamily(book, src, key, ctx)
    local info = src.families[key]
    local all = src.all[key]
    local fam = { key = key, name = info.label or key, kind = "heal", shape = SHAPE[info.type] or "none",
                  noSeed = true, ids = {}, ranks = {} }
    local castKind = (info.type == "channel") and "channeled" or (INSTANT[info.type] and "instant" or "cast")
    local eats = (key == "Swiftmend" and src == MD.SpellData) and EatsLines(src, ctx) or nil
    for _, id in ipairs(all) do
        local s = src.spells[id] or {}
        local cost = ctx.CostFor and ctx.CostFor(id) or s.cost
        local e = { id = id, family = key, name = SpellName(id) or fam.name,
                    rank = s.rank, rankText = s.rank and ("Rank " .. s.rank) or nil,
                    level = s.level, known = (src.knownSet and src.knownSet[id]) == true, icon = Icon(id),
                    cast = type(s.cast) == "number" and s.cast or nil, castKind = castKind, calc = eats }
        e.cost, e.costState = Cost(cost)
        ApplyRead(e, id)
        fam.ids[#fam.ids + 1] = id
        fam.ranks[#fam.ranks + 1] = e
        book.spells[id] = e
        if e.known then fam.maxKnown = e end
    end
    return fam
end

--------------------------------------------------------------------------------
-- Damage: Engine/DamageMath.lua over the walked spellbook
--------------------------------------------------------------------------------

local DAMAGE_SHAPE = { direct = "direct", hybrid = "hybrid", dot = "hot", channel = "channel" }

local function DamageWhy(c, f)
    local parts = {}
    if c.kind == "direct" then
        parts[1] = string.format("cast %.1f / 3.5", f.baseCast)
    elseif c.kind == "hybrid" then
        parts[1] = "split by amount"
    elseif c.kind == "dot" then
        parts[1] = string.format("duration %d / 15", c.dur or 0)
    elseif c.kind == "channel" then
        parts[1] = c.aoe and "channel, halved for an area" or "channel"
    end
    if (c.coefAdd or 0) > 0 then parts[#parts + 1] = string.format("+%.2f coef from talents", c.coefAdd) end
    if c.penaltyKnown and (c.penalty or 1) < 0.999 then
        parts[#parts + 1] = string.format("downrank %.2f", c.penalty)
    end
    parts[#parts + 1] = "VERIFY"
    return table.concat(parts, ", ")
end

-- Tip:Damage's Shift lines (the old UI/Tip_TBC.lua's), plain. T123: a
-- class family's (c.talentsModelled == false) says no talent is modelled,
-- and its VERIFY sentence names no Balance talent.
local function DamageCalc(c)
    local out = { "base damage: read from this tooltip" }
    if c.coef then
        out[#out + 1] = string.format("hit  +%d = %d spell damage x %.3f coef%s", R(c.add), R(c.bonus),
            c.coef, (c.coefAdd or 0) > 0 and string.format(" (%.2f from talents)", c.coefAdd) or "")
    end
    if c.dotCoef then
        out[#out + 1] = string.format("%s  +%d = %d spell damage x %.3f coef%s",
            c.kind == "channel" and "channel" or "DoT", R(c.dotAdd), R(c.bonus), c.dotCoef,
            c.aoe and " (halved: it hits everything)" or "")
    end
    if (c.mult or 1) > 1.0001 then out[#out + 1] = string.format("then x %.2f from talents", c.mult) end
    local seen, names = {}, {}
    for _, t in ipairs(c.talents or {}) do
        if not seen[t] then seen[t] = true; names[#names + 1] = t end
    end
    if #names > 0 then out[#out + 1] = "talents: " .. table.concat(names, ", ") end
    if c.talentsModelled == false then out[#out + 1] = "talents not modelled (VERIFY)" end
    if not c.penaltyKnown then
        out[#out + 1] = "the client does not say this rank's level: no downrank penalty applied"
    end
    if c.talentsModelled == false then
        out[#out + 1] = "VERIFY: coefficients and tick periods are the"
    else
        out[#out + 1] = "VERIFY: coefficients, tick periods and Balance talents are the"
    end
    out[#out + 1] = "standard TBC rules, not yet checked against a hit on this client"
    return out
end

local function RankOf(sub)
    local P = MD.Parse
    if type(sub) ~= "string" or not P or type(P.Rank) ~= "function" then return nil end
    local n = P.Rank(sub)
    return type(n) == "number" and n or nil
end

local function ByRank(a, b)
    local ra, rb = a.rank or 0, b.rank or 0
    if ra ~= rb then return ra < rb end
    return a.id < b.id
end

local function DamageFamilies(book, walk, pool)
    local DM, RR = MD.DamageMath, MD.RankRules
    if not DM then return {} end
    local class = MD.player and MD.player.class
    local families = DM.FamiliesFor(class)
    local byName = {}
    for _, hit in ipairs(walk) do
        local key = DM.Family(hit.name, class)
        if key and not book.spells[hit.id] then
            byName[key] = byName[key] or {}
            byName[key][#byName[key] + 1] = hit
        end
    end
    local order = {}
    for _, key in ipairs(DM.OrderFor(class)) do
        local hits = byName[key]
        local f = families[key]
        if hits and f then
            local fam = { key = key, name = key, kind = "damage", school = DM.SchoolName(key, class),
                          shape = DAMAGE_SHAPE[f.kind] or "direct", ids = {}, ranks = {} }
            for _, hit in ipairs(hits) do
                local id = hit.id
                local e = { id = id, family = key, name = hit.name, rank = RankOf(hit.sub),
                            rankText = hit.sub, known = true, icon = Icon(id), school = fam.school }
                local r = ApplyRead(e, id)
                local base = e.desc and DM.Parse(key, e.desc, class) or nil
                local c = base and DM.Compute(id, key, base, class) or nil
                if c then
                    e.value, e.perMana, e.perSec = c.expected, c.dpm, c.dps
                    e.min, e.max, e.crit = c.min, c.max, c.crit
                    e.cost, e.costState = Cost(c.cost)
                    e.cast = c.cast
                    e.castKind = (f.kind == "channel") and "channeled"
                        or ((f.kind == "direct") and "cast" or "instant")
                    if c.castAvg and c.castAvg < c.cast - 0.001 then e.castNote = NG_NOTE end
                    e.interval, e.intervalBy = c.cast, "cast"
                    if type(c.level) == "number" then e.level = c.level end
                    if c.kind == "hybrid" or c.kind == "dot" or c.kind == "channel" then
                        e.over, e.dur = c.dotTotal, c.dur
                    end
                    e.casts = MD.RankMath:CastsToOOM(c.cost, c.cast, pool.max, pool.regenCasting)
                    e.bonus = { counts = ((c.coef or 0) + (c.dotCoef or 0)) * (c.penalty or 1), from = "model",
                                of = c.bonus, amount = (c.add or 0) + (c.dotAdd or 0), why = DamageWhy(c, f) }
                    e.calc = DamageCalc(c)
                else
                    e.descState = e.desc and "unread" or "empty"
                    e.cost, e.costState = Cost(r.cost)
                    if type(r.level) == "number" then e.level = r.level end
                    if type(r.cast) == "number" then e.cast = r.cast end
                end
                fam.ranks[#fam.ranks + 1] = e
                book.spells[id] = e
            end
            table.sort(fam.ranks, ByRank)
            for i, e in ipairs(fam.ranks) do
                fam.ids[i] = e.id
                if e.known then fam.maxKnown = e end
            end
            RR.Pareto(fam.ranks, BOOK_FIELDS)
            local s = RR.Suggested(fam.ranks, fam.maxKnown, BOOK_FIELDS)
            if s then s.suggested = true end
            fam.suggested = s
            RR.DominatedBy(fam.ranks, s, BOOK_FIELDS)
            book.families[key] = fam
            order[#order + 1] = key
        end
    end
    return order
end

--------------------------------------------------------------------------------
-- Other: what the walk lists that no family claims
--------------------------------------------------------------------------------

local function OtherFamilies(book, walk)
    local byName, names = {}, {}
    for _, hit in ipairs(walk) do
        if not hit.passive and not book.spells[hit.id] and book.families[hit.name] == nil then
            local r = Read(hit.id)
            if type(r.cost) == "number" and r.cost > 0 then
                if not byName[hit.name] then
                    byName[hit.name] = { key = hit.name, name = hit.name, shape = "none", ids = {}, ranks = {} }
                    names[#names + 1] = hit.name
                end
                local fam = byName[hit.name]
                local e = { id = hit.id, family = hit.name, name = hit.name, rank = RankOf(hit.sub),
                            rankText = hit.sub, known = true, icon = Icon(hit.id), slot = hit.slot,
                            passive = hit.passive }
                ApplyRead(e, hit.id)
                e.cost, e.costState = Cost(r.cost)
                if type(r.cast) == "number" then
                    e.cast = r.cast
                    e.castKind = r.cast > 0 and "cast" or "instant"
                end
                if type(r.level) == "number" then e.level = r.level end
                fam.ranks[#fam.ranks + 1] = e
                book.spells[hit.id] = e
            end
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local fam = byName[name]
        table.sort(fam.ranks, ByRank)
        for i, e in ipairs(fam.ranks) do
            fam.ids[i] = e.id
            fam.maxKnown = e
        end
        book.families[name] = fam
    end
    return names
end

--------------------------------------------------------------------------------
-- The build
--------------------------------------------------------------------------------

-- The families the rank table leaves out (`exclude`; SD.familyOrder does
-- not list them): Tranquility, then Swiftmend, then any other by key.
local EXCLUDED_FIRST = { "Tranquility", "Swiftmend" }
local function ExcludedKeys(src)
    local out, seen = {}, {}
    local fams = src.families or {}
    for _, key in ipairs(EXCLUDED_FIRST) do
        if fams[key] and fams[key].exclude then out[#out + 1] = key; seen[key] = true end
    end
    local rest = {}
    for key, info in pairs(fams) do
        if type(info) == "table" and info.exclude and not seen[key] then rest[#rest + 1] = key end
    end
    table.sort(rest)
    for _, key in ipairs(rest) do out[#out + 1] = key end
    return out
end

function Book.DefaultPoolFrom(ctx)
    local pool = {}
    local maxMana = MD.API.UnitPowerMax("player", 0)
    if type(maxMana) == "number" then pool.max, pool.mana = maxMana, maxMana end
    if ctx and type(ctx.castingRegen) == "number" then pool.regenCasting = ctx.castingRegen end
    return pool
end

-- One book. `whatIf` reads MD.sim (RankMath:Compute()); else the live
-- context. RankMath.info, which other readers take as the last Compute's
-- context, is put back as it was.
function Book:Build(whatIf)
    local RM = MD.RankMath
    local book = { families = {}, order = {}, spells = {}, generation = Book.generation }
    local opts = (not whatIf) and { live = true } or nil
    local savedInfo = RM.info
    local results = RM:Compute(opts)
    RM.info = savedInfo
    local ctx = RM:Context(opts)
    if not whatIf then Book._bonus = ctx.bonus end

    local src = RM.Source and RM:Source() or MD.SpellData
    local canTable = CanRankTable() and src ~= nil
    if canTable then
        for _, key in ipairs(src.familyOrder or {}) do
            if results[key] then
                book.families[key] = HealFamily(book, src, key, results[key], ctx)
                book.order[#book.order + 1] = key
            end
        end
        for _, key in ipairs(ExcludedKeys(src)) do
            local all = src.all and src.all[key]
            if all and #all > 0 and not book.families[key] then
                book.families[key] = PlainHealFamily(book, src, key, ctx)
                book.order[#book.order + 1] = key
            end
        end
    end

    local B = Reader()
    local walk = (B and type(B.WalkAll) == "function") and B.WalkAll() or {}
    if canTable then
        for _, key in ipairs(DamageFamilies(book, walk, Book.DefaultPoolFrom(ctx))) do
            book.order[#book.order + 1] = key
        end
    end
    for _, key in ipairs(OtherFamilies(book, walk)) do
        book.order[#book.order + 1] = key
    end

    if BS then BS.Check(book, "Spells/Book_Model.lua") end
    return book
end

-- the generation's signature (Spells/Book.lua's EntrySig, minus casts)
local function Signature(book)
    local parts = {}
    for _, key in ipairs(book.order) do
        local fam = book.families[key]
        parts[#parts + 1] = "F" .. key
        for _, e in ipairs(fam.ranks) do
            parts[#parts + 1] = table.concat({ e.id, tostring(e.known), tostring(e.value),
                tostring(e.cost and e.cost.amount), tostring(e.cast), tostring(e.perMana), tostring(e.perSec),
                tostring(e.suggested), tostring(e.dominated) }, ":")
        end
    end
    return table.concat(parts, ";")
end

-- The live book rebuilt now: the cache replaced, the generation bumped and
-- BOOK_CHANGED fired when the signature moved (the first build counts).
function Book:Refresh()
    local book = Book:Build(false)
    local sig = Signature(book)
    local changed = sig ~= Book._sig
    if changed then
        Book.generation = Book.generation + 1
        Book._sig = sig
    end
    book.generation = Book.generation
    Book._cache, Book._cacheTime = book, Now()
    if changed then MD:Fire("BOOK_CHANGED", book) end
    return book
end

-- opts.whatIf: the What if's book, built for the call (T122's door).
function Book:Get(opts)
    if type(opts) == "table" and opts.whatIf then
        local book = Book:Build(true)
        book.generation = Book.generation
        return book
    end
    if not Book._cache or (Now() - (Book._cacheTime or 0)) >= CACHE_SECONDS then
        Book:Refresh()
    end
    return Book._cache
end

function Book:Entry(id)
    return Book:Get().spells[id]
end

-- TBC's book holds every spell a tooltip can name; an id outside it is nil.
function Book:ReadSpell(id)
    return Book:Get().spells[id]
end

--------------------------------------------------------------------------------
-- The contract's other methods
--------------------------------------------------------------------------------

-- Spells/Book.lua's CastsFor (its twin): the pool's mana, else its max.
function Book:CastsFor(entry, pool)
    if type(entry) ~= "table" or type(pool) ~= "table" then return nil end
    local amount = entry.cost and entry.cost.amount
    return MD.RankMath:CastsToOOM(amount, entry.interval, pool.mana or pool.max, pool.regenCasting)
end

-- the family's ranks as copies, casts recounted for `pool`; the book's own
-- entries never written
function Book:Rows(family, pool)
    local out = {}
    if type(family) ~= "table" then return out end
    for i, e in ipairs(family.ranks or {}) do
        local c = {}
        for k, v in pairs(e) do c[k] = v end
        if type(pool) == "table" then c.casts = Book:CastsFor(e, pool) end
        out[i] = c
    end
    return out
end

-- Spells/Book.lua's Compare, copied (its twin; that file is Forever's)
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

-- No TBC family keeps a second half (altKind) yet: the family and the entry
-- themselves (Spells/Book.lua's Half / HalfOf answer the same for them).
function Book:Half(family) return family end
function Book:HalfOf(entry) return entry end

-- Spells/Book.lua's IntervalFor, copied (its twin): what one cast of the
-- entry takes, never shorter than its cooldown; "cooldown" when that sets it.
function Book.IntervalFor(entry, part)
    local base
    if entry.castKind == "channeled" then
        base = part and part.periodDur or nil
    elseif part and (part.min ~= nil or part.max ~= nil) then
        base = math.max(entry.cast or 0, Book.GCD)
    elseif part and part.dur ~= nil then
        base = part.dur
    else
        base = math.max(entry.cast or 0, Book.GCD)
    end
    local cd = entry.cooldown
    if base ~= nil and type(cd) == "number" and cd > base then return cd, "cooldown" end
    return base, nil
end

-- { mana = max, max, regenCasting }: counted from full
function Book:DefaultPool()
    local RM = MD.RankMath
    return Book.DefaultPoolFrom(RM:Context({ live = true }))
end

-- { max, mana, regenCasting, modelled = false }: TBC reads its pool (no ~)
function Book:Pool()
    local d = Book:DefaultPool()
    local mana = MD.API.UnitPower("player", 0)
    return { max = d.max, mana = type(mana) == "number" and mana or d.max, regenCasting = d.regenCasting,
             modelled = false }
end

-- amount, stale: +healing of the last live build (TBC reads it in combat:
-- never stale); +damage of a school from Engine/DamageMath.lua
function Book:Bonus(kind, school)
    if kind == "heal" then
        if Book._bonus == nil then Book:Get() end
        if Book._bonus == nil then return nil end
        return Book._bonus, false
    elseif kind == "damage" then
        local DM = MD.DamageMath
        if not (DM and DM.Bonus) or school == nil then return nil end
        return DM.Bonus(school), false
    end
    return nil
end

--------------------------------------------------------------------------------
-- Rebuilt when what RankMath reads moves. SPELLS_REBUILT (login, a rank
-- trained) always rebuilds once the saved variables are there, read or not:
-- it is the event Spells/Families_TBC.lua reconciled the spell list on, and
-- a book nobody has read since must still fire the BOOK_CHANGED that runs
-- Tabs:Reconcile -- a heal family trained mid-session is appended with the
-- new dot. The other events rebuild only a book already read (a book nobody
-- asked for is built on the first Get).
--------------------------------------------------------------------------------

local function Rebuild()
    if Book._cache and type(MD.db) == "table" then Book:Refresh() end
end

MD:RegisterCallback("SPELLS_REBUILT", function()
    -- the known-rank index moved (a rank trained): the walk and the reads go
    -- first (Data/SpellData.lua fires this before Spells/Book_TBC.lua's own
    -- SPELLS_CHANGED handlers forget them)
    local B = Reader()
    if B and type(B.Forget) == "function" then B.Forget() end
    if type(MD.db) == "table" and type(MD.cdb) == "table" then Book:Refresh() end
end)
MD:RegisterCallback("TALENTS_CHANGED", Rebuild)
MD:RegisterCallback("FORM_CHANGED", Rebuild)
MD:On("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then Rebuild() end
end)
MD:On("PLAYER_LEVEL_UP", Rebuild)

-- T117: every method the contract names, present (Spells/BookShape.lua).
if BS then BS.CheckMethods(Book, "Spells/Book_Model.lua") end
