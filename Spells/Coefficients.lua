-- T117 (docs/SPEC-one-ui.md 3.1, 4.3 "Else estimated"; docs/tasks/T117-book-contract.md):
-- the +healing rules, once. How much of the caster's +healing (or +damage) a
-- rank's value gets -- the rules Engine/RankMath.lua (the druid's rows and a
-- TBC class's ClassRow) and Engine/DamageMath.lua each spelled out before,
-- and the rules Forever's book estimates its share by (Coef.Estimate).
--
--   direct coefficient  = clamp(baseCast, 1.5, 3.5) / 3.5
--   HoT coefficient     = duration / 15
--   hybrid (Regrowth)   = the two parts weighted by their BASE amounts:
--                         direct x avg/(avg+hot), HoT x hot/(avg+hot)
--   channel             = duration / 3.5, halved for an area spell (Hurricane)
--   sub-level-20 malus  = 1 - (20 - spellLevel) * 0.0375
--   downrank penalty    = min(1, (spellLevel + 11) / casterLevel)  -- TBC's rule
--   group heal          = half the single-target coefficient (VERIFY)
--
-- Every number RankMath and DamageMath return is the same, to the last bit,
-- as before this file (tools/bookshapecheck.lua's golden): each function does
-- the arithmetic the callers did, in the same order.
--
-- Pure: Lua's library only. No client call, no MD.db, no frame. Every main
-- TOC: TBC before Engine/RankMath.lua and Engine/DamageMath.lua (which call it
-- at run time), Forever before Spells/Book.lua.
local _, MD = ...

MD.Coefficients = MD.Coefficients or {}
local Coef = MD.Coefficients

-- A heal that lands on the whole party carries half the single-target
-- coefficient (Prayer of Healing, Circle of Healing). VERIFY.
Coef.GROUP = 0.5

-- The global cooldown an instant's coefficient is taken at (the clamp's floor).
local GCD = 1.5

-- A direct part: the BASE cast clamped to the global cooldown and 3.5 s.
function Coef.Direct(cast)
    return math.min(math.max(cast, 1.5), 3.5) / 3.5
end

-- A heal or damage over time: its duration over 15 s.
function Coef.Hot(duration)
    return duration / 15
end

-- A spell with both (Regrowth, Moonfire): each part's coefficient weighted by
-- its share of the base amount. Returns directCoef, hotCoef, share (the direct
-- part's share of the amount). For Regrowth that is 0.286 / 0.70, for Moonfire
-- 0.15 / 0.52 -- the widely quoted numbers (docs/DECISIONS.md v0.6 15).
function Coef.Hybrid(cast, duration, directAmount, hotAmount)
    local share = directAmount / (directAmount + hotAmount)
    return Coef.Direct(cast) * share, Coef.Hot(duration) * (1 - share), share
end

-- A channelled spell: its duration over 3.5 s, halved when it hits an area.
function Coef.Channel(duration, aoe)
    local c = duration / 3.5
    if aoe then c = c * 0.5 end
    return c
end

-- A rank learned below level 20 gets a smaller share: 3.75% less per level.
-- 1 at 20 and above, and for a level nobody knows.
function Coef.Sub20(level)
    if type(level) ~= "number" or level >= 20 then return 1 end
    return 1 - (20 - level) * 0.0375
end

-- TBC's downrank rule: a rank learned more than 11 levels below the caster
-- loses share in proportion. Never above 1.
function Coef.Downrank(level, playerLevel)
    return math.min(1, (level + 11) / math.max(playerLevel, 1))
end

-- Both penalties, as RankMath applies them to the bonus part of a heal.
function Coef.Penalty(level, playerLevel)
    return Coef.Downrank(level, playerLevel) * Coef.Sub20(level)
end

--------------------------------------------------------------------------------
-- Coef.Estimate(e, shape) -> counts, why | nil, reason
--
-- Forever's estimate of how much of +healing (or +damage) a rank of the book
-- gets (docs/SPEC-one-ui.md 4.3, decision D3): the rules above by the family's
-- shape, the sub-20 malus, the group rule for a heal that reaches the party --
-- and NO downrank penalty, which is TBC's rule, not this client's. `e` is an
-- entry of Spells/Book.lua (cast, level, dur, min, max, over, castKind,
-- interval, targets); `shape` its family's ("direct", "hot", "hybrid"). The
-- caller says "estimated"; `why` names each factor in plain ASCII words:
--   "cast 1.5 / 3.5 x 0.29"          a direct heal, the sub-20 factor when below 1
--   "over 12 s / 15"                  a HoT
--   "channel 8 s / 3.5"               a channelled heal
--   "cast 2.0 / 3.5 + over 21 s / 15, by amount"   a hybrid
--   ", group rule" appended           a heal that reaches the party (x Coef.GROUP)
-- A shape with no rule, or a number the rule needs and the entry lacks:
-- nil, "no rule for <shape>" / "no duration".
--------------------------------------------------------------------------------
local function F1(v) return string.format("%.1f", v) end
local function Secs(v)
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return F1(v)
end

function Coef.Estimate(e, shape)
    if type(e) ~= "table" then return nil, "no entry" end
    local counts, why
    local cast = (type(e.cast) == "number") and e.cast or GCD
    local clamped = math.min(math.max(cast, 1.5), 3.5)
    if e.castKind == "channeled" and (shape == "hot" or shape == "direct") then
        local dur = (type(e.interval) == "number" and e.interval) or e.dur
        if type(dur) ~= "number" or dur <= 0 then return nil, "no duration" end
        counts = Coef.Channel(dur, false)
        why = "channel " .. Secs(dur) .. " s / 3.5"
    elseif shape == "direct" then
        counts = Coef.Direct(cast)
        why = "cast " .. F1(clamped) .. " / 3.5"
    elseif shape == "hot" then
        local dur = e.dur
        if type(dur) ~= "number" or dur <= 0 then return nil, "no duration" end
        counts = Coef.Hot(dur)
        why = "over " .. Secs(dur) .. " s / 15"
    elseif shape == "hybrid" then
        local dur, over = e.dur, e.over
        if type(dur) ~= "number" or dur <= 0 or type(over) ~= "number"
            or type(e.min) ~= "number" or type(e.max) ~= "number" then
            return nil, "no parts"
        end
        local d, h = Coef.Hybrid(cast, dur, (e.min + e.max) / 2, over)
        counts = d + h
        why = "cast " .. F1(clamped) .. " / 3.5 + over " .. Secs(dur) .. " s / 15, by amount"
    else
        return nil, "no rule for " .. tostring(shape)
    end
    local sub = Coef.Sub20(e.level)
    if sub < 1 then
        counts = counts * sub
        why = why .. " x " .. string.format("%.2f", sub)
    end
    if e.targets == "party" then
        counts = counts * Coef.GROUP
        why = why .. ", group rule"
    end
    return counts, why
end
