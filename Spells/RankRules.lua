-- T67 (P23 of docs/PLAN-refactor-ux.md, review A13): the rank rules, once.
-- Pure -- no client call, no frame, no MD.API: rows in, marks out. Both
-- lines read it: Engine/RankMath.lua's Compute() (TBC, the dashboard's rows:
-- `hpm`, `hps`, `heal`) and Spells/Book.lua's Rows() (Forever, the book's
-- entries: `perMana`, `perSec`, `value`). Before this file each carried its
-- own copy of the Pareto filter, the suggested rank and the casts-to-OOM
-- count, with the floor a literal 0.4 in one and a local constant in the
-- other; the floor is now MD.Rules.SUGGESTED_FLOOR (Core.lua), read at each
-- call.
--
-- `f` names the fields a caller's rows carry and which rows take part:
--   f.eff      -- the efficiency field (heal per mana)
--   f.rate     -- the throughput field (heal per second)
--   f.value    -- the amount the floor is a share of
--   f.eligible -- function(row): whether a row competes at all (known, real,
--                 and -- on Forever -- with both numbers present)
-- Loaded by SpellTuner_TBC.toc and the Forever main TOCs, after Core.lua.
local _, MD = ...

MD.RankRules = MD.RankRules or {}
local RR = MD.RankRules

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

-- The suggested rank: among the competing, non-dominated rows whose value is
-- at least SUGGESTED_FLOOR of `top`'s (the highest known rank), the one with
-- the best efficiency (the first of equals, in row order); else `top` itself
-- (assumption, both lines: below the floor, cast-count pressure outweighs
-- efficiency). Answers the row, or nil when there is no `top`. Marks nothing.
function RR.Suggested(rows, top, f)
    local best
    if top and top[f.value] ~= nil then
        local floor = MD.Rules.SUGGESTED_FLOOR * top[f.value]
        for _, r in ipairs(rows) do
            if f.eligible(r) and not r.dominated and r[f.value] ~= nil and r[f.value] >= floor then
                if not best or r[f.eff] > best[f.eff] then best = r end
            end
        end
    end
    return best or top
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
