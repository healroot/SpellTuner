-- T67 (P23 of docs/PLAN-refactor-ux.md, review A13): the rank rules, once.
-- Pure -- no client call, no frame, no ST.API: rows in, marks out. Both
-- lines read it: Engine/RankMath.lua's Compute() (TBC, the dashboard's rows:
-- `hpm`, `hps`, `heal`) and Spells/Book.lua's Rows() (Forever, the book's
-- entries: `perMana`, `perSec`, `value`). Before this file each carried its
-- own copy of the Pareto filter, the suggested rank and the casts-to-OOM
-- count, with the floor a literal 0.4 in one and a local constant in the
-- other; the floor is now ST.Rules.SUGGESTED_FLOOR (Core.lua), read at each
-- call.
--
-- `f` names the fields a caller's rows carry and which rows take part:
--   f.eff      -- the efficiency field (heal per mana)
--   f.rate     -- the throughput field (heal per second)
--   f.value    -- the amount the floor is a share of
--   f.eligible -- function(row): whether a row competes at all (known, real,
--                 and -- on Forever -- with both numbers present)
-- T127 (docs/tasks/T127-rank-marks.md): three marks instead of one
-- suggested rank -- eff (the most per mana), max (the most per second) and
-- best (the trade against max, RR.Score at RR.TradeK) -- RR.Marks; the
-- settings tradeKDamage / tradeKHeal are registered here.
-- Loaded by SpellTuner_TBC.toc and the Forever main TOCs, after Core.lua.
local _, ST = ...

ST.RankRules = ST.RankRules or {}
local RR = ST.RankRules

if ST.RegisterDefaults then
    ST:RegisterDefaults({
        tradeKDamage = ST.Rules.TRADE_K_DAMAGE,
        tradeKHeal = ST.Rules.TRADE_K_HEAL,
    })
end

-- Whether rank `rj` beats rank `ri` on both numbers (at least as good on
-- each, strictly better on one); `rj` must itself compete.
function RR.Beats(rj, ri, f)
    if rj == ri or not f.eligible(rj) then return false end
    local ej, ei, sj, si = rj[f.eff], ri[f.eff], rj[f.rate], ri[f.rate]
    return ej >= ei and sj >= si and (ej > ei or sj > si)
end

-- Pareto dominance: every competing row that another competing row beats is
-- marked `dominated = true`. Rows are visited in the order given; nothing is
-- cleared here (the caller starts from fresh rows or clears them itself).
function RR.Pareto(rows, f)
    for _, ri in ipairs(rows) do
        if f.eligible(ri) then
            for _, rj in ipairs(rows) do
                if RR.Beats(rj, ri, f) then
                    ri.dominated = true
                    break
                end
            end
        end
    end
end

-- T127: how much a lost per second weighs against a gained per mana in the
-- `best` mark, for `kind` "damage" or a heal (anything else): the setting
-- tradeKDamage / tradeKHeal, read at each call; a value that is not a number
-- in 0..1 falls back to ST.Rules.TRADE_K_DAMAGE / TRADE_K_HEAL (Core.lua).
function RR.TradeK(kind)
    local key, fallback = "tradeKHeal", ST.Rules.TRADE_K_HEAL
    if kind == "damage" then key, fallback = "tradeKDamage", ST.Rules.TRADE_K_DAMAGE end
    local v
    if ST.db then v = ST.db[key] end
    if type(v) == "number" and v >= 0 and v <= 1 then return v end
    return fallback
end

-- The trade of row `r` against `maxRow` (the most per second):
-- (eff / eff of max - 1) - k * (1 - rate / rate of max). Positive when the
-- per mana gained outweighs the per second lost at weight `k`; 0 for max
-- itself. nil when either row lacks a number or max's are not positive.
function RR.Score(r, maxRow, f, k)
    if not r or not maxRow then return nil end
    local e, me, s, ms = r[f.eff], maxRow[f.eff], r[f.rate], maxRow[f.rate]
    if e == nil or me == nil or s == nil or ms == nil or me <= 0 or ms <= 0 then return nil end
    return (e / me - 1) - k * (1 - s / ms)
end

-- T127: the three rank marks over the competing, non-dominated rows (run
-- RR.Pareto first). Answers best, max, eff (rows); marks nothing.
--   eff  -- the most per mana (first of equals, in row order)
--   max  -- the most per second (first of equals)
--   best -- the row with the highest RR.Score above 0 against max at
--           RR.TradeK(kind) (first of equals); a heal must also be worth at
--           least SUGGESTED_FLOOR of `top`'s value (the highest known rank;
--           assumption, both lines: below the floor, cast-count pressure
--           outweighs efficiency); no row above 0 -> max.
-- With no competing row, best is `top` (nil without one), max and eff nil.
function RR.Marks(rows, top, f, kind)
    local eff, max
    for _, r in ipairs(rows) do
        if f.eligible(r) and not r.dominated then
            if not eff or r[f.eff] > eff[f.eff] then eff = r end
            if not max or r[f.rate] > max[f.rate] then max = r end
        end
    end
    if not max then return top, nil, nil end
    local k = RR.TradeK(kind)
    local floor
    if kind ~= "damage" then
        local tv = top and top[f.value]
        if tv == nil then tv = max[f.value] end
        if tv ~= nil then floor = ST.Rules.SUGGESTED_FLOOR * tv end
    end
    local best, bestScore = nil, 0
    for _, r in ipairs(rows) do
        if f.eligible(r) and not r.dominated and r ~= max then
            local passes = true
            if floor then passes = r[f.value] ~= nil and r[f.value] >= floor end
            if passes then
                local sc = RR.Score(r, max, f, k)
                if sc ~= nil and sc > bestScore then best, bestScore = r, sc end
            end
        end
    end
    return best or max, max, eff
end

-- The suggested rank (T67's name, kept for its readers): RR.Marks' best;
-- `kind` defaults to a heal. Answers the row, or nil when there is no `top`
-- and no competing row.
function RR.Suggested(rows, top, f, kind)
    local best = RR.Marks(rows, top, f, kind)
    return best
end

-- T127: a rank whose rolled rows (Lifebloom's x2 / x3, `entry.variants`,
-- each { perMana, perSec, value }) are one choice at one cost on one GCD:
-- the rank and its rows are marked as a heal, against the rank as `top`, and
-- the winner alone holds `bestOfStacks = true` (the others are cleared). An
-- entry that is not known holds none.
local STACK_FIELDS = {
    eff = "perMana", rate = "perSec", value = "value",
    eligible = function(p) return p.known and p.perMana ~= nil and p.perSec ~= nil end,
}
function RR.MarkVariants(entry)
    if not entry then return end
    entry.bestOfStacks = nil
    local vs = entry.variants
    if type(vs) ~= "table" then return end
    for _, v in ipairs(vs) do v.bestOfStacks = nil end
    if not entry.known then return end
    local function Proxy(src)
        return { src = src, known = true, perMana = src.perMana, perSec = src.perSec, value = src.value }
    end
    local proxies = { Proxy(entry) }
    for _, v in ipairs(vs) do proxies[#proxies + 1] = Proxy(v) end
    RR.Pareto(proxies, STACK_FIELDS)
    local best = RR.Marks(proxies, proxies[1], STACK_FIELDS, "heal")
    if best and STACK_FIELDS.eligible(best) then best.src.bestOfStacks = true end
end

-- For each dominated row, the id of the row that beats it: `suggested` when
-- it does, else the beating row with the best efficiency (the first of
-- equals). Written as `dominatedBy` (a plain number, or nil).
function RR.DominatedBy(rows, suggested, f)
    for _, ri in ipairs(rows) do
        if ri.dominated then
            local by
            if suggested and RR.Beats(suggested, ri, f) then
                by = suggested
            else
                for _, rj in ipairs(rows) do
                    if RR.Beats(rj, ri, f) and (not by or rj[f.eff] > by[f.eff]) then by = rj end
                end
            end
            ri.dominatedBy = by and by.id or nil
        end
    end
end

-- Chain-casts until the next cast is unaffordable: each cast nets
-- (cost - regen * interval) mana, so floor((mana - cost) / net) + 1 casts.
-- math.huge when the spell is free or regen covers the chain, 0 when the
-- pool cannot afford one cast; nil when any input is missing -- never
-- guessed at 0.
function RR.CastsToOOM(cost, interval, mana, regen)
    if cost == nil or interval == nil or mana == nil or regen == nil then return nil end
    if cost <= 0 then return math.huge end
    local net = cost - regen * interval
    if net <= 0 then return math.huge end
    if mana < cost then return 0 end
    return math.floor((mana - cost) / net) + 1
end
