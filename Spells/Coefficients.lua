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
-- Pure: Lua's library only. No client call, no ST.db, no frame. Every main
-- TOC: TBC before Engine/RankMath.lua and Engine/DamageMath.lua (which call it
-- at run time), Forever before Spells/Book.lua.
local _, ST = ...

ST.Coefficients = ST.Coefficients or {}
local Coef = ST.Coefficients

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
-- Coef.Estimate(e, shape) -> counts, why [, short] | nil, reason  (short: T133, row path only)
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
-- T129: the direct part is taken at `e.baseCast` when it is a number (the
-- cast before a cast-time talent, Spells/Book.lua's talent seam), else at
-- `e.cast`; the words name it:
--   "cast 1.7 / 3.5 (1.5 + 0.2 Improved Wrath 2) x 0.47"   talent read
--   "cast 1.5 / 3.5 (talents not read) x 0.47"            a rule, ranks unread
-- A rank with no rule ("<talent> <r>: no rule") leaves the words as before.
--------------------------------------------------------------------------------
local function F1(v) return string.format("%.1f", v) end
-- up to two decimals, trailing zeros dropped: 1.5, 0.2, 0.17, 2
local function Num(v)
    local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
    return s
end

-- The cast the coefficient is taken at, and the words that say where it came from.
local function BaseCast(e)
    if type(e.baseCast) == "number" and type(e.cast) == "number" then
        local note = " (" .. Num(e.cast) .. " + " .. Num(e.baseCast - e.cast)
        if type(e.castTalent) == "string" then note = note .. " " .. e.castTalent end
        return e.baseCast, note .. ")"
    end
    local cast = (type(e.cast) == "number") and e.cast or GCD
    if e.castTalent == "talents not read" then return cast, " (talents not read)" end
    return cast, ""
end
local function Secs(v)
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return F1(v)
end

--------------------------------------------------------------------------------
-- T132 (docs/tasks/T132-forever-coefficients.md): an id Data/Coefs_Forever.lua
-- has a row for (ST.CoefRules, generated from talentsforever's per-rank
-- coefficients, PRELIMINARY) is estimated from that row instead:
--   counts = (share or 0) + (tick or 0) x ticks
-- share = the row's heal slot for a heal, its direct (damage) slot for damage,
-- the other when only one is there (never the two summed);
-- ticks = the part's duration / its tick period when Spells/Parse.lua read
-- one, else 3 s only for a family in TICK_MEASURED (review M1, the lead's
-- ruling: no tick period is guessed for an arbitrary spell); a channel the
-- same, from its own duration and period. A row with a per-tick share whose
-- period is unknown falls back to the old rule whole, direct part included
-- (never half applied), and says "tick period unknown -- old rule". No sub-20
-- factor and no group rule: the site's share is per target (review M2). The words:
--   "42.9% (talentsforever)"
--   "20% x 4 ticks, 3 s ticks (measured 2026-10-23) (talentsforever)"
--   "28.6% + 7.1% x 7 ticks, 3 s ticks (measured 2026-10-23) (talentsforever)"
-- `kind` ("heal" / "damage", optional) names which parsed part carries the
-- ticks; without it the heal part, else the damage part.
--------------------------------------------------------------------------------
-- The families whose 3 s tick a measurement confirmed, by the row's own name
-- (the site's, so the client's locale does not matter). Provenance: the
-- author's level-25 Forever export, 2026-10-23 (docs/TESTING.md section 54):
-- Rejuvenation R1-R4, Regrowth R2's HoT and Moonfire R1's DoT fit the site's
-- per-tick share only at one tick every 3 s. A family is added here only from
-- a measurement; any other spell with no parsed period takes the old rule.
-- T133: Entangling Roots added from the author's level-26 export (2026-10-23):
-- R1 read 0.244-0.255 of spell damage, which the site's 6% per tick fits only
-- at four ticks over its 12 s (one every 3 s) times Naturalist 5's 1.05.
local TICK_MEASURED = { Rejuvenation = true, Regrowth = true, Moonfire = true, ["Entangling Roots"] = true }
local TICK_MEASURED_SECS = 3
local TICK_MEASURED_NOTE = ", 3 s ticks (measured 2026-10-23)"
Coef.TICK_MEASURED = TICK_MEASURED

local function Pct(v)
    local s = string.format("%.1f", v * 100):gsub("%.0$", "")
    return s .. "%"
end

local function TickPart(e, kind)
    local p = e.parsed
    if type(p) ~= "table" then return nil end
    if kind ~= nil and type(p[kind]) == "table" then return p[kind] end
    if type(p.heal) == "table" then return p.heal end
    if type(p.damage) == "table" then return p.damage end
    return nil
end

-- The row's one-off share for `kind` (B1): the site's "(direct)" is the
-- damage part and "(heal)" the heal part, kept apart by tools/buildcoefs.py and
-- never summed (Holy Shock R1 is 0.429 as a heal and 0.429 as damage). A heal
-- reads heal, else direct; damage reads direct, else heal; a row with one slot
-- gives it to either kind.
local function Share(row, kind)
    local d = (type(row.direct) == "number") and row.direct or nil
    local h = (type(row.heal) == "number") and row.heal or nil
    if kind == "damage" then
        if d ~= nil then return d end
        return h
    end
    if h ~= nil then return h end
    return d
end

--------------------------------------------------------------------------------
-- T133 (docs/tasks/T133-forever-share-factors.md): the row's share is one
-- factor; the low-rank level penalty and the talent multipliers are others,
-- each named, each a PREDICTION (the author's ruling, 2026-10-23) until more
-- levels and gear are tested after launch. A measured share still wins.
--   counts = share x P(rank, level) x M(talents)
--
-- P, heals only: max(LEVEL_FLOOR, 1 - LEVEL_STEP x max(0, playerLevel - start)),
-- start = learnLevel + LEVEL_GRACE, or MEASURED_START[id] when a measurement
-- named it. Provenance: the author's Forever beta exports, 2026-10-23, druid
-- level 25 (ten readings, +0..+171 healing) and level 26 (eight readings, the
-- same gear steps): Healing Touch R1 0.593-0.614 / 0.535-0.556 of the share,
-- Rejuvenation R1 0.796-0.803 / 0.743-0.753, Healing Touch R2 0.996-1.005 /
-- 0.943-0.958, every higher rank 1.00 -- a step of 0.05 per level fits all
-- three penalised ranks at both levels; TBC's ratio rule does not. Damage has
-- no penalty: Wrath R1 and Moonfire R1 counted the full share at 26.
--------------------------------------------------------------------------------
Coef.LEVEL_STEP = 0.05   -- share lost per level past the start (2026-10-23, lvl 25-26)
Coef.LEVEL_GRACE = 17    -- the start is the learn level + this (2026-10-23, lvl 25-26)
-- The floor the penalty stops at. UNMEASURED (assumed 0): no export has yet
-- reached a level where a rank's penalty would go below it.
Coef.LEVEL_FLOOR = 0
-- Starts a measurement named, winning over the rule: Healing Touch R1 (5185,
-- learned at 1) starts at 17, one level early (2026-10-23, lvl 25-26).
Coef.MEASURED_START = { [5185] = 17 }

-- Coef.LevelPenalty(id, learnLevel, playerLevel, kind) -> P, start, source
-- P is 1 for damage, for an unknown level (either one), and below the start;
-- `source` "measured" (MEASURED_START) or "rule"; start and source nil when
-- no start applies (damage, an unknown level).
function Coef.LevelPenalty(id, learnLevel, playerLevel, kind)
    if kind == "damage" then return 1, nil, nil end
    if type(playerLevel) ~= "number" or playerLevel <= 0 then return 1, nil, nil end
    local start, source = Coef.MEASURED_START[id], "measured"
    if type(start) ~= "number" then
        if type(learnLevel) ~= "number" or learnLevel <= 0 then return 1, nil, nil end
        start, source = learnLevel + Coef.LEVEL_GRACE, "rule"
    end
    local over = playerLevel - start
    if over <= 0 then return 1, start, source end
    local p = 1 - Coef.LEVEL_STEP * over
    if p < Coef.LEVEL_FLOOR then p = Coef.LEVEL_FLOOR end
    return p, start, source
end

local function PlayerLevel()
    local l = ST.player and ST.player.level
    if type(l) == "number" and l > 0 then return l end
    return nil
end

-- The level factor's words: the long one for the estimate, the short one for
-- the measured line. Nothing when P is 1 and both levels are known; an
-- unknown player level or (a heal's) learn level is P 1 and said (review m2).
local function LevelWords(e, kind)
    if kind == "damage" then return 1, "", "" end
    local lvl = PlayerLevel()
    if lvl == nil then return 1, ", level unknown", "" end
    local p, start = Coef.LevelPenalty(e.id, e.level, lvl, kind)
    if start == nil then return 1, ", learn level unknown", "" end
    if p >= 1 then return 1, "", "" end
    local step = Num(Coef.LEVEL_STEP * 100)
    if p <= 0 then
        return 0, " x0 level " .. lvl .. " (from " .. start .. ", -" .. step .. "%/level: no bonus at this level)",
            " x0 level"
    end
    local f = string.format("%.2f", p)
    return p, " x " .. f .. " level " .. lvl .. " (from " .. start .. ", -" .. step .. "%/level)",
        " x " .. f .. " level"
end

-- The talent factor, from Spells/Book.lua's seam (entry.talentMult, for the
-- kind it was read for): factor, words. "talents not read" is factor 1 and
-- said as ", talents not read" (review m1, as T129's cast rule says it), not a
-- prediction; a "no rule" talent is said.
local function TalentWords(e, kind)
    local m = e.talentMult
    if type(m) ~= "table" or type(m.factor) ~= "number" then return 1, "" end
    if m.kind ~= nil and kind ~= nil and m.kind ~= kind then return 1, "" end
    if m.words == "talents not read" then return 1, ", talents not read" end
    if type(m.words) ~= "string" or m.words == "" then return 1, "" end
    if m.factor == 1 and not m.words:find("no rule", 1, true) then return 1, "" end
    return m.factor, " " .. m.words
end

local function FromRow(e, row, kind)
    local direct = Share(row, kind)
    local tick = (type(row.tick) == "number") and row.tick or nil
    if direct == nil and tick == nil then return nil, "no share in the row" end
    local counts, words = direct or 0, {}
    if direct then words[#words + 1] = Pct(direct) end
    local note = ""
    if tick then
        local part = TickPart(e, kind)
        local dur = part and (part.dur or part.periodDur)
        if type(dur) ~= "number" then dur = e.dur end
        if type(dur) ~= "number" or dur <= 0 then return nil, "no duration" end
        local period = part and part.period
        if type(period) ~= "number" or period <= 0 then
            if not (type(row.name) == "string" and TICK_MEASURED[row.name]) then
                return nil, "tick period unknown", true
            end
            period = TICK_MEASURED_SECS
            note = TICK_MEASURED_NOTE
        end
        local ticks = math.floor(dur / period + 1e-9)
        if ticks < 1 then return nil, "no ticks" end
        counts = counts + tick * ticks
        words[#words + 1] = Pct(tick) .. " x " .. ticks .. " tick" .. (ticks == 1 and "" or "s")
    end
    -- T133: the share, then each factor that is not 1, by name
    local share = counts
    local p, levelLong, levelShort = LevelWords(e, kind)
    local m, talent = TalentWords(e, kind)
    counts = share * p * m
    -- a prediction is a factor said by name; an unknown level or unread
    -- talents (factor 1, ", ... unknown" / ", talents not read") is not one
    local predicted = levelShort ~= "" or (talent ~= "" and talent:sub(1, 1) ~= ",")
    local why = table.concat(words, " + ") .. note .. levelLong .. talent
        .. (predicted and " (talentsforever, predicted)" or " (talentsforever)")
    -- the short form the measured line quotes: "80% x 0.75 level x1.05 Naturalist 5"
    local short = Pct(share) .. levelShort
    if talent:sub(1, 1) ~= "," then short = short .. talent end
    return counts, why, nil, short
end

local OldRule

function Coef.Estimate(e, shape, kind)
    if type(e) ~= "table" then return nil, "no entry" end
    local rules = ST.CoefRules
    local row = type(rules) == "table" and type(e.id) == "number" and rules[e.id] or nil
    if type(row) == "table" then
        local counts, why, unknown, short = FromRow(e, row, kind)
        -- M2: the site's share is already per target (Prayer of Healing's
        -- 28.6% is 3.0 / 3.5 x 1/3), so the group rule is the old path's only
        -- T133: `short` (third return) the factors in the measured line's words
        if not unknown then return counts, why, short end
        -- M1: the per-tick share cannot be counted, so the whole row is set
        -- aside and the old rule speaks, saying why
        local c, w = OldRule(e, shape)
        if c == nil then return nil, w end
        return c, w .. " (tick period unknown -- old rule)"
    end
    return OldRule(e, shape)
end

OldRule = function(e, shape)
    local counts, why
    local cast, castNote = BaseCast(e)
    local clamped = math.min(math.max(cast, 1.5), 3.5)
    if e.castKind == "channeled" and (shape == "hot" or shape == "direct") then
        local dur = (type(e.interval) == "number" and e.interval) or e.dur
        if type(dur) ~= "number" or dur <= 0 then return nil, "no duration" end
        counts = Coef.Channel(dur, false)
        why = "channel " .. Secs(dur) .. " s / 3.5"
    elseif shape == "direct" then
        counts = Coef.Direct(cast)
        why = "cast " .. F1(clamped) .. " / 3.5" .. castNote
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
        why = "cast " .. F1(clamped) .. " / 3.5" .. castNote .. " + over " .. Secs(dur) .. " s / 15, by amount"
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
