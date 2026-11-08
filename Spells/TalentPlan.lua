local _, ST = ...

--------------------------------------------------------------------------------
-- T137 (docs/tasks/T137-forever-talent-planner.md): the talent planner's rules
-- and its bridge to the What if, Forever TOCs only. ST.TalentPlan:
--
--   TP.Trees(class)            the class's trees (Data/TalentTree_Forever.lua), or nil
--   TP.Find(trees, name)       { tree = i, t = talent } by name, or nil
--   TP.Points(level, live)     the points a level gives: level - 9, 0..51 (assumed:
--                              one a level from 10, VERIFY), never under what the
--                              live build already spends
--   TP.Level()                 the level the plan is judged at: the What if's
--                              typed Level (T138), else the player's, or nil
--   TP.NeedLevel(spent)        the level that gives `spent` points (T138)
--   TP.Spent(plan, trees, ti, belowRow)  points in tree ti (rows under belowRow)
--   TP.Total(plan, trees)      every point the plan spends in the trees
--   TP.CanAdd(plan, trees, name, points)  -> true | false, why
--   TP.CanRemove(plan, trees, name)       -> true | false, why
--       the game's rules: five points in a tree open its next tier; a talent with
--       a requirement opens when that one is at full rank; a point never comes off
--       when a later tier or a dependant would lose its footing
--   TP:Live()                  the live ranks (ST.Book:Talents), or nil unread
--   TP:Modelled(name)          true when the What if moves numbers by this talent
--   TP:Current()               the build the What if stands for: a modelled talent
--                              its typed rank, else the kept plan's (0 included), else
--                              live; every rank clamped to the talent's top
--   TP.Problems(plan, trees, points)  what in a plan breaks the game's rules (a
--                              spinner can type Bloom without its tier), as words
--   TP:Apply(plan)             the plan into the What if in one change: a modelled
--                              talent typed (cleared when equal to live); the rest
--                              kept for the next Current (they move no number)
--
-- Pure apart from TP:Live / Modelled / Current / Apply. The plan is a session
-- value like the What if's (never saved).
--------------------------------------------------------------------------------
local TP = {}
ST.TalentPlan = TP

local PREFIX = "talent:"
TP.MAX_POINTS = 51
TP.FIRST_LEVEL = 10

function TP.Level()
    local WI = ST.WhatIf
    local typed = WI and WI:Get("level")
    if type(typed) == "number" then return typed end
    local l = ST.player and ST.player.level
    return (type(l) == "number" and l > 0) and l or nil
end

function TP.NeedLevel(spent)
    if type(spent) ~= "number" or spent <= 0 then return nil end
    return spent + TP.FIRST_LEVEL - 1
end

function TP.Trees(class)
    class = class or (ST.player and ST.player.class)
    local all = ST.TalentTree
    local trees = type(all) == "table" and all[class] or nil
    return (type(trees) == "table" and #trees > 0) and trees or nil
end

function TP.Find(trees, name)
    for ti, tree in ipairs(trees or {}) do
        for _, t in ipairs(tree.talents or {}) do
            if t.name == name then return { tree = ti, t = t } end
        end
    end
    return nil
end

local function Rank(plan, name)
    local r = plan and plan[name]
    return (type(r) == "number" and r > 0) and r or 0
end
TP.Rank = Rank

function TP.Spent(plan, trees, ti, belowRow)
    local n = 0
    for _, t in ipairs(trees[ti] and trees[ti].talents or {}) do
        if belowRow == nil or t.row < belowRow then n = n + Rank(plan, t.name) end
    end
    return n
end

function TP.Total(plan, trees)
    local n = 0
    for ti in ipairs(trees or {}) do n = n + TP.Spent(plan, trees, ti) end
    return n
end

function TP.Points(level, live)
    local n = (type(level) == "number") and (level - TP.FIRST_LEVEL + 1) or 0
    n = math.max(0, math.min(TP.MAX_POINTS, n))
    if type(live) == "number" and live > n then n = live end
    return n
end

function TP.CanAdd(plan, trees, name, points)
    local f = TP.Find(trees, name)
    if not f then return false, "not in your trees" end
    local t = f.t
    if Rank(plan, name) >= t.max then return false, "at full rank" end
    if TP.Total(plan, trees) >= (points or 0) then return false, "no points left" end
    local need = (t.row - 1) * 5
    if TP.Spent(plan, trees, f.tree, t.row) < need then
        return false, "needs " .. need .. " points in " .. trees[f.tree].name
    end
    if t.req then
        local r = TP.Find(trees, t.req)
        if r and Rank(plan, t.req) < r.t.max then return false, "needs " .. t.req .. " at full rank" end
    end
    return true
end

function TP.Problems(plan, trees, points)
    local out = {}
    for ti, tree in ipairs(trees or {}) do
        for _, t in ipairs(tree.talents) do
            if Rank(plan, t.name) > 0 then
                local need = (t.row - 1) * 5
                if TP.Spent(plan, trees, ti, t.row) < need then
                    out[#out + 1] = t.name .. " needs " .. need .. " points in " .. tree.name
                end
                if t.req then
                    local r = TP.Find(trees, t.req)
                    if r and Rank(plan, t.req) < r.t.max then out[#out + 1] = t.name .. " needs " .. t.req end
                end
            end
        end
    end
    local total = TP.Total(plan, trees)
    if type(points) == "number" and total > points then
        out[#out + 1] = total .. " points spent, " .. points .. " to spend"
    end
    return out
end

function TP.CanRemove(plan, trees, name)
    local f = TP.Find(trees, name)
    if not f then return false, "not in your trees" end
    local r = Rank(plan, name)
    if r <= 0 then return false, "no points in it" end
    local next = {}
    for k, v in pairs(plan) do next[k] = v end
    next[name] = r - 1
    for _, u in ipairs(trees[f.tree].talents) do
        if Rank(next, u.name) > 0 then
            if u.req == name then return false, u.name .. " needs it" end
            if u.row > f.t.row and TP.Spent(next, trees, f.tree, u.row) < (u.row - 1) * 5 then
                return false, u.name .. " would lose its tier"
            end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- The bridge to the What if
--------------------------------------------------------------------------------
TP.kept = nil -- the last applied plan (its unmodelled talents), session only

function TP:Live()
    local ranks = ST.Book and ST.Book.Talents and ST.Book:Talents()
    return (type(ranks) == "table") and ranks or nil
end

function TP:Modelled(name)
    local WI = ST.WhatIf
    return WI ~= nil and WI:ClassRow(PREFIX .. name) ~= nil
end

function TP:Current()
    local trees, live, WI = TP.Trees(), self:Live(), ST.WhatIf
    if not (trees and live and WI) then return nil end
    -- the What if cleared since the plan was applied: it starts from the live build again
    if TP.kept and (WI.clears or 0) ~= TP.keptClears then TP.kept = nil end
    local plan = {}
    for _, tree in ipairs(trees) do
        for _, t in ipairs(tree.talents) do
            local typed = self:Modelled(t.name) and WI:Get(PREFIX .. t.name) or nil
            local r = typed
            -- review M1: the kept plan holds every talent, 0 included, so a talent the plan
            -- took to 0 stays at 0
            if r == nil and TP.kept and not self:Modelled(t.name) then r = TP.kept[t.name] end
            if r == nil then r = live[t.name] end
            if type(r) == "number" and r > 0 then plan[t.name] = math.min(r, t.max) end
        end
    end
    return plan
end

function TP:Apply(plan)
    local trees, live, WI = TP.Trees(), self:Live(), ST.WhatIf
    if not (trees and live and WI) then return 0 end
    local sets = {}
    for _, tree in ipairs(trees) do
        for _, t in ipairs(tree.talents) do
            if self:Modelled(t.name) then
                local r = Rank(plan, t.name)
                sets[#sets + 1] = { PREFIX .. t.name, (r ~= Rank(live, t.name)) and r or nil }
            end
        end
    end
    local kept = {}
    for _, tree in ipairs(trees) do
        for _, t in ipairs(tree.talents) do kept[t.name] = Rank(plan, t.name) end
    end
    TP.kept = kept
    TP.keptClears = WI.clears or 0
    return WI:SetMany(sets)
end
