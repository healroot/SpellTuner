-- T67 (P23 of docs/PLAN-refactor-ux.md, review A13): the spell words, once.
-- How a rank's facts are said -- its cost, its cast, per mana, per second,
-- casts to OOM, the value's parts and the crit range -- for the two surfaces
-- that say them, UI/SpellTip.lua (the block on a spell tooltip,
-- docs/SPEC-forever-ui.md 5.x) and UI/SpellsPane.lua (the RANKS
-- table, the rank card and the export, 3.5 / 3.6). Before this file each
-- carried its own helpers, with the crit multiplier and the global cooldown
-- copied into both. Where the spec wants different wording for the same fact
-- (`no mana (10 Rage)` in the block, `10 Rage` in a cell; `inf` in a cell,
-- `never - regen keeps up` on the card), the function takes a `style` and
-- says which spec section each style is.
--
-- Pure: an entry of Spells/Book.lua in, a string out. No client call, no
-- frame; colour codes come in as arguments (`c.muted`, `c.reset`), so the
-- words never pick a colour. Every string is ASCII with no bare pipe apart
-- from the colour codes a caller hands in. A number that is nil renders "-",
-- never 0 (CLAUDE.md). Forever main TOCs, after Spells/Book.lua.
--
-- T117 (docs/SPEC-one-ui.md 3.4, 4.3): on the TBC TOC too, right after
-- Spells/RankRules.lua -- before TBC has a book (T118), so nothing here reads
-- a Forever-only value at load (W.GCD falls back to 1.5). And the words of
-- the +healing share a rank gets (W.Bonus, W.BonusLabel) and of a signed
-- change (W.Signed, the What if footer, T122).
local _, ST = ...

ST.Words = ST.Words or {}
local W = ST.Words

-- Vanilla's crit rule (1.5x); Forever's own is UNVERIFIED (HoTs crit since
-- 70009, REFERENCES-FOREVER.md sec4, amount not stated). T12's /st measure
-- checks it against a landed heal above the crit range's top.
W.CRIT_MULT = 1.5
-- Spells/Book.lua's global cooldown: the interval a direct spell's per second
-- is over when its cast is shorter, and an Other spell's for casts to OOM.
W.GCD = (ST.Book and ST.Book.GCD) or 1.5

function W.Num(v, decimals)
    if type(v) ~= "number" or v ~= v then return "-" end -- nil or NaN
    if decimals then return string.format("%." .. decimals .. "f", v) end
    return tostring(math.floor(v + 0.5))
end
local Num = W.Num

-- The crit range of a part with a min and a max, "a - b".
function W.CritRange(part)
    return Num(part.min * W.CRIT_MULT) .. " - " .. Num(part.max * W.CRIT_MULT)
end

-- Review R13: a Rage / Focus / Energy cost is no mana; named "10 Rage".
-- nil when the cost is not one of those.
function W.OtherPower(e)
    if e.cost and type(e.cost.power) == "string" and type(e.cost.powerAmount) == "number" then
        return Num(e.cost.powerAmount) .. " " .. e.cost.power
    end
    return nil
end

-- A rank's cost.
--   "cell"   -- the RANKS / Whole book Mana cell (3.5): "25", "5%", "free",
--               "10 Rage", "-"
--   "card"   -- the rank card and a Utility header (3.5): "25 mana",
--               "5% of base mana", "free", "10 Rage", "-"
--   "export" -- the export, in the probe's words (3.6): "25 Mana",
--               "5% of base mana", "free", "10 Rage", "unknown"
local COST = {
    cell   = { amount = "",      percent = "%",              none = "-" },
    card   = { amount = " mana", percent = "% of base mana", none = "-" },
    export = { amount = " Mana", percent = "% of base mana", none = "unknown" },
}
function W.Cost(e, style)
    local s = COST[style] or COST.card
    if not e then return s.none end
    local other = W.OtherPower(e)
    if other then return other end
    if e.costState == "free" then return "free" end
    if e.cost then
        if type(e.cost.amount) == "number" then return Num(e.cost.amount) .. s.amount end
        if type(e.cost.percent) == "number" then return Num(e.cost.percent, 0) .. s.percent end
    end
    return s.none
end

-- A rank's cast.
--   "cell"   -- the Cast cell (3.5): "inst", "chan", "1.5s", "-"
--   "phrase" -- a header's words (3.5): "2.0 s cast", "instant",
--               "channeled"; nil when the book has no cast
--   "card"   -- the card's Cast pair (3.5): "2.0 s" for a timed cast, else
--               the phrase, else "-"
--   "export" -- the probe's words (3.6): "Instant", "Channeled",
--               "2.0 sec cast", "unknown"
--   "header" -- T120 (docs/tasks/T120-one-spells-pane.md): the phrase and,
--               when the book says how the cast was counted (entry.castNote,
--               TBC's model), "2.9 s cast with Nature's Grace averaged"
function W.Cast(e, style)
    if style == "header" then
        local phrase = W.Cast(e, "phrase")
        local note = W.CastNote(e)
        if phrase and note then return phrase .. " with " .. note end
        return phrase
    end
    if style == "cell" then
        if e.castKind == "instant" then return "inst" end
        if e.castKind == "channeled" then return "chan" end
        if type(e.cast) == "number" then return Num(e.cast, 1) .. "s" end
        return "-"
    elseif style == "export" then
        if e.castKind == "instant" then return "Instant" end
        if e.castKind == "channeled" then return "Channeled" end
        if e.castKind == "cast" and type(e.cast) == "number" then
            return string.format("%.1f sec cast", e.cast)
        end
        return "unknown"
    elseif style == "card" then
        if e.castKind == "cast" and type(e.cast) == "number" then return string.format("%.1f s", e.cast) end
        return W.Cast(e, "phrase") or "-"
    end
    if not e then return nil end
    if e.castKind == "instant" then return "instant" end
    if e.castKind == "channeled" then return "channeled" end
    if type(e.cast) == "number" then return string.format("%.1f s cast", e.cast) end
    return nil
end

-- T120: how the book counted a cast ("Nature's Grace averaged"), or nil --
-- entry.castNote, sent by a book whose cast time is a model's (TBC).
function W.CastNote(e)
    if type(e) == "table" and type(e.castNote) == "string" and e.castNote ~= "" then return e.castNote end
    return nil
end

-- T120: where a value comes from, beside the range on the card:
-- "(3691 with 15% crit)" when the value is crit-averaged (entry.crit, TBC's
-- model, D1), "from the text" when it is the spell's own text (Forever's
-- entry.parsed), else nil.
function W.ValueSource(e)
    if type(e) ~= "table" then return nil end
    if type(e.crit) == "number" and type(e.value) == "number" then
        return "(" .. Num(e.value) .. " with " .. Num(e.crit * 100) .. "% crit)"
    end
    if type(e.parsed) == "table" then return "from the text" end
    return nil
end

-- Per mana.
--   "cell" -- a number to two places, else "-" (3.5)
--   "tip"  -- the block's Per mana (5.1): the number, else why there is
--             none: "no mana (10 Rage)", "free", "5% of base mana",
--             "cost unknown"; T95: a group or bounce heal's number is one
--             target's, followed by its reach (W.Reach): "0.61  x up to 5
--             targets"
function W.PerMana(e, style)
    if style ~= "tip" then return Num(e.perMana, 2) end
    if e.perMana then
        -- T95: one target's number, the reach beside it in words (decision 12)
        local reach = W.Reach(e)
        if reach then return Num(e.perMana, 2) .. "  " .. reach end
        return Num(e.perMana, 2)
    end
    local other = W.OtherPower(e)
    if other then return "no mana (" .. other .. ")" end
    if e.costState == "free" then return "free" end
    if e.cost and e.cost.percent then return Num(e.cost.percent, 0) .. "% of base mana" end
    return "cost unknown"
end

local function IsAbsorb(e)
    return type(e.parsed) == "table" and e.parsed.absorb ~= nil
end

-- The relevant half of an entry's own parsed text (heal or damage, by the
-- kind) -- read from entry.parsed, because a tick shape and an absorb both
-- leave entry.min/max/over/dur nil.
function W.PartOf(e, kind)
    if type(e) ~= "table" or type(e.parsed) ~= "table" then return nil end
    if kind == "damage" then return e.parsed.damage end
    return e.parsed.heal
end

--------------------------------------------------------------------------------
-- T95 (docs/SPEC-next.md 4.2 P1, decision 12): cooldowns, reach, lockouts.
-- A group or bounce heal's reach is said as an upper bound in words, and
-- never multiplied into a number: per mana and per second stay one target's.
--------------------------------------------------------------------------------

-- A five-man party: the most a party heal can reach (4.5 treats a raid as the
-- caster's own subgroup). The one number here that is not in the spell's text.
W.PARTY_SIZE = 5

-- A length of time: "10 s", "1.5 s", "5 min" (whole minutes from two up).
function W.Seconds(secs)
    if type(secs) ~= "number" or secs ~= secs then return "-" end
    if secs >= 120 and secs % 60 == 0 then return Num(secs / 60) .. " min" end
    if secs % 1 == 0 then return Num(secs) .. " s" end
    return Num(secs, 1) .. " s"
end

-- A multiplier with no trailing zeros: 1.75 -> "1.75", 1.5 -> "1.5", 2 -> "2".
local function Mult(v)
    local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
    return s
end

-- What a chain heal's jumps add up to when every target is hurt: 1 + f + f^2
-- ... over its count (Chain Heal: 1 + 0.5 + 0.25 = 1.75 for 3 targets).
function W.ChainSum(reach)
    if type(reach) ~= "table" or type(reach.count) ~= "number" or type(reach.falloff) ~= "number" then
        return nil
    end
    local sum, f = 0, 1
    for _ = 1, reach.count do sum = sum + f; f = f * reach.falloff end
    return sum
end

-- The reach in a few words, an upper bound, or nil for a heal on one target:
--   party          "x up to 5 targets"
--   chain          "up to 1.75x if 3 are hurt"
--   selfAndTarget  "x up to 2 targets"
--   caster         "on you only"
function W.Reach(e)
    if type(e) ~= "table" then return nil end
    local t = e.targets
    if t == "party" then return "x up to " .. W.PARTY_SIZE .. " targets" end
    if t == "chain" then
        local sum = W.ChainSum(e.reach)
        if not sum then return nil end
        return "up to " .. Mult(sum) .. "x if " .. Num(e.reach.count) .. " are hurt"
    end
    if t == "selfAndTarget" then return "x up to 2 targets" end
    if t == "caster" then return "on you only" end
    return nil
end

-- The reach spelled out, for the block's detail and the card's hover: who,
-- the range the text gives, and that it is an upper bound (no positions are
-- read). nil for a heal on one target.
function W.ReachDetail(e)
    if type(e) ~= "table" then return nil end
    local r = type(e.reach) == "table" and e.reach or {}
    local within = type(r.range) == "number" and (" within " .. Num(r.range) .. " yd") or ""
    if e.targets == "party" then
        local who = (r.from == "caster") and "your party" or "the target's party"
        return who .. within .. ", up to " .. W.PARTY_SIZE .. " - an upper bound"
    end
    if e.targets == "chain" then
        local sum = W.ChainSum(r)
        if not sum then return nil end
        return Num(r.count) .. " targets, each jump " .. Num((r.falloff or 0) * 100) .. "% of the last"
            .. ": up to " .. Mult(sum) .. "x - an upper bound"
    end
    if e.targets == "selfAndTarget" then return "the target and you - an upper bound" end
    if e.targets == "caster" then return "you only" end
    return nil
end

-- "every 10 s" when the cooldown is what paces the spell (Spells/Book.lua's
-- intervalBy), else nil.
function W.Every(e)
    if type(e) == "table" and e.intervalBy == "cooldown" and type(e.interval) == "number" then
        return "every " .. W.Seconds(e.interval)
    end
    return nil
end

-- Per second.
--   "tip"  -- the block (5.1): a plain number for a cast, the GCD, a hybrid
--             or an absorb (the game's own cast line already says which);
--             "N over T s" when the interval is the spell's own duration (a
--             HoT with no direct part, or a channel); "-" with no number;
--             T95: "N  every 10 s" when the cooldown sets the interval
--   "card" -- the rank card (3.5): the number and, in `c.muted`, what it is
--             over -- "over the 10 s channel", "over a 2.0 s cast", "over the
--             1.5 s global cooldown", "over its 12 s"; T95: "over its 10 s
--             cooldown"
function W.PerSec(e, kind, style, c)
    if style == "tip" then
        if not (e.perSec and e.interval) then return "-" end
        local every = W.Every(e)
        if every then return Num(e.perSec, 1) .. "  " .. every end
        if e.castKind == "channeled" or (e.min == nil and e.max == nil and not IsAbsorb(e)) then
            return Num(e.perSec, 1) .. " over " .. Num(e.interval, 0) .. " s"
        end
        return Num(e.perSec, 1)
    end
    local part = W.PartOf(e, kind)
    local muted, reset = c and c.muted or "", c and c.reset or ""
    if type(e.perSec) ~= "number" then return "-" end
    local base = Num(e.perSec, 1) .. " "
    if e.intervalBy == "cooldown" then
        return base .. muted .. "over its " .. W.Seconds(e.interval) .. " cooldown" .. reset
    end
    if e.castKind == "channeled" then
        return base .. muted .. "over the " .. Num(e.interval, 0) .. " s channel" .. reset
    end
    -- T120: a model's entry (no parsed text, TBC's book) is per second over
    -- its cast, or the global cooldown when the cast is shorter (RankMath's HPS)
    if type(e.parsed) ~= "table" or (IsAbsorb(e) and part == nil)
        or (part and (part.min ~= nil or part.max ~= nil)) then
        if e.castKind == "cast" and type(e.cast) == "number" and e.cast >= W.GCD then
            return base .. muted .. string.format("over a %.1f s cast", e.cast) .. reset
        end
        return base .. muted .. string.format("over the %.1f s global cooldown", W.GCD) .. reset
    end
    return base .. muted .. "over its " .. Num(e.interval, 0) .. " s" .. reset
end

-- Casts to OOM (a count from Book:CastsFor).
--   "short" -- a cell and the block (3.5, 5.1): "inf", the count, "-"
--   "card"  -- the card's To OOM (3.5): "never - regen keeps up",
--              "N casts from full", "-"
function W.Casts(n, style)
    if style == "card" then
        if n == math.huge then return "never - regen keeps up" end
        if type(n) == "number" then return Num(n, 0) .. " casts from full" end
        return "-"
    end
    if n == math.huge then return "inf" end
    return Num(n, 0)
end

-- The value's parts by shape, as { {label, value}, ... }, and whether a crit
-- range was among them.
--   "tip"  -- the block's detail lines (5.2-5.4): "Ticks" (a tick the text
--             states), a hybrid's "Hit" (avg and crit) / "Over time" /
--             "Total", a direct range's "Average" and "Crit", an absorb's
--             "Absorbs"; a HoT with no stated tick adds nothing (its amount
--             is the game's own description)
--   "card" -- the rank card (3.5): "Absorbs"; a hybrid's "Hit" / "Crit" /
--             "Over time" / "Total"; "Heals" or "Damage" as a range with its
--             average and "Crit"; an amount over a duration; a tick's total
--             over its channel and "Ticks"; the crit range followed by
--             `c.muted` "(x1.5 assumed)"
function W.Value(e, kind, style, c)
    local out = {}
    local function P(l, v) out[#out + 1] = { l, v } end
    local part = W.PartOf(e, kind)
    if style == "tip" then
        if part == nil then
            if kind == "heal" and IsAbsorb(e) then P("Absorbs", Num(e.parsed.absorb)) end
            return out, false
        end
        if part.tick ~= nil and part.periodDur ~= nil then
            P("Ticks", Num(part.tick) .. " every " .. Num(part.period) .. " s for " .. Num(part.periodDur) .. " s")
            return out, false
        end
        if part.min ~= nil and part.max ~= nil then
            local critRange = W.CritRange(part)
            if part.over ~= nil and part.dur ~= nil then
                P("Hit", "avg " .. Num((part.min + part.max) / 2) .. ", crit " .. critRange)
                P("Over time", Num(part.over) .. " over " .. Num(part.dur) .. " s")
                P("Total", Num(e.value))
            else
                P("Average", Num(e.value) .. " (" .. Num(part.min) .. " - " .. Num(part.max) .. ")")
                P("Crit", critRange)
            end
            return out, true
        end
        return out, false
    end

    local muted, reset = c and c.muted or "", c and c.reset or ""
    local valueWord = (kind == "damage") and "Damage" or "Heals"
    if part == nil and kind == "heal" and IsAbsorb(e) then
        P("Absorbs", Num(e.parsed.absorb))
    elseif part and part.min ~= nil and part.max ~= nil then
        local crit = W.CritRange(part) .. " " .. muted .. "(x" .. Num(W.CRIT_MULT, 1) .. " assumed)" .. reset
        if part.over ~= nil and part.dur ~= nil then
            P("Hit", Num(part.min) .. " - " .. Num(part.max))
            P("Crit", crit)
            P("Over time", Num(part.over) .. " over " .. Num(part.dur) .. " s")
            P("Total", Num(e.value))
        else
            P(valueWord, Num(part.min) .. " - " .. Num(part.max) .. " (avg " .. Num(e.value) .. ")")
            P("Crit", crit)
        end
        return out, true
    elseif part and part.over ~= nil and part.dur ~= nil then
        P(valueWord, Num(part.over) .. " over " .. Num(part.dur) .. " s")
    elseif part and part.tick ~= nil then
        if part.periodDur ~= nil then P(valueWord, Num(e.value) .. " over " .. Num(part.periodDur) .. " s") end
        -- only what the text states: a tick and its period, never derived
        if part.period ~= nil then P("Ticks", Num(part.tick) .. " every " .. Num(part.period) .. " s") end
    end
    return out, false
end

-- The crit multiplier line of the block's detail (5.1): "assumed", once.
function W.CritNote()
    return "x" .. Num(W.CRIT_MULT, 1) .. ", not measured"
end

-- T127 (docs/tasks/T127-rank-marks.md, mockup docs/mockups/rank-marks.html
-- M5): the three rank marks in words. `k` is Spells/RankRules.lua's
-- RR.TradeK(kind) (the settings tradeKDamage / tradeKHeal), read at each call.
local function TradeK(kind)
    local RR = ST.RankRules
    if RR and RR.TradeK then return RR.TradeK(kind) end
    if kind == "damage" then return ST.Rules.TRADE_K_DAMAGE end
    return ST.Rules.TRADE_K_HEAL
end

-- "4:1" (1% per mana is worth 4% per second at k 0.25), "6.7:1" at 0.15,
-- "1:1" at 1; nil at k 0 (per mana only).
function W.TradeRatio(k)
    if type(k) ~= "number" or k <= 0 then return nil end
    local x = 1 / k
    if math.abs(x - math.floor(x + 0.5)) < 0.05 then return Num(x) .. ":1" end
    return Num(x, 1) .. ":1"
end

-- "1% per mana for 4% per second" at `k` 0.25; "the most per mana" at k 0.
-- The settings' tips say it too (review T127 m5).
function W.TradePhrase(k)
    if type(k) ~= "number" or k <= 0 then return "the most per mana" end
    local x = 1 / k
    local n = (math.abs(x - math.floor(x + 0.5)) < 0.05) and Num(x) or Num(x, 1)
    return "1% per mana for " .. n .. "% per second"
end
local function Weight(kind) return W.TradePhrase(TradeK(kind)) end

-- T128 (docs/tasks/T128-trade-score-and-rank-tips.md): the score as the rule
-- computes it (Spells/RankRules.lua's RR.Score, multiplicative: max scores
-- exactly 1) and as it is said, a ratio against max: "1.075".
local SCORE_FIELDS = { eff = "perMana", rate = "perSec" }
local function ScoreOf(e, maxR, kind)
    local RR = ST.RankRules
    if not (RR and RR.Score) or type(e) ~= "table" or type(maxR) ~= "table" then return nil end
    if type(e.perMana) ~= "number" or type(e.perSec) ~= "number" then return nil end
    return RR.Score(e, maxR, SCORE_FIELDS, TradeK(kind))
end
W.ScoreOf = ScoreOf
function W.Score(x)
    if type(x) ~= "number" or x ~= x then return "-" end
    return string.format("%.3f", x)
end
-- "score 1.075 vs max 1.000"; nil without a score.
local function ScoreVsMax(e, maxR, kind)
    local sc = ScoreOf(e, maxR, kind)
    if sc == nil then return nil end
    return "score " .. W.Score(sc) .. " vs max " .. W.Score(1)
end
W.ScoreVsMax = ScoreVsMax
-- ", score 0.887" -- a rank's score against max, "" without one.
local function ScoreTail(e, maxR, kind)
    local sc = ScoreOf(e, maxR, kind)
    if sc == nil then return "" end
    return ", score " .. W.Score(sc)
end

-- The best rule in words (the chip's and the best tag's hover), its weights
-- and floor read at each call (ST.Rules, the settings).
-- T128: the score multiplies (per mana / max's x (per sec / max's) ^ k).
function W.SuggestedRule()
    return "Best: the rank that scores highest against max, the rank with the most per second."
        .. " Score = per mana / max's x (per sec / max's) ^ k; max scores 1.000, so best must score above it."
        .. " Damage: " .. Weight("damage") .. " at the margin. Heals: " .. Weight("heal") .. ", and at least "
        .. Num(ST.Rules.SUGGESTED_FLOOR * 100) .. "% of your highest rank's heal. Else max."
end

-- " (damage, 4:1)" / " at 4:1": the ratio a sentence names, "" at k 0.
local function At(kind)
    local r = W.TradeRatio(TradeK(kind))
    if not r then return "" end
    return " at " .. r
end

-- (a / b - 1) * 100, nil when either is missing or b is not positive.
local function Change(a, b)
    if type(a) ~= "number" or type(b) ~= "number" or b <= 0 then return nil end
    return (a / b - 1) * 100
end

-- Whether `e`'s value is under the heal floor of `fam`'s highest known rank;
-- as RR.Marks (review T127 m7), max's value when the highest has none.
local function FloorBase(fam)
    local top, max = fam and fam.maxKnown, fam and fam.maxRank
    if type(top) == "table" and type(top.value) == "number" then return top.value end
    if type(max) == "table" and type(max.value) == "number" then return max.value end
    return nil
end
W.FloorBase = FloorBase
local function UnderFloor(e, fam, kind)
    if kind == "damage" then return false end
    local tv = FloorBase(fam)
    if tv == nil or type(e.value) ~= "number" then return false end
    return e.value < ST.Rules.SUGGESTED_FLOOR * tv
end
W.UnderFloor = UnderFloor

-- The marks `e` holds in `fam` (fam.suggested best, fam.maxRank max,
-- fam.effRank eff), in the order best, max, eff: { "best", "max" }.
function W.MarksOf(e, fam)
    local out = {}
    if type(e) ~= "table" or type(fam) ~= "table" then return out end
    if fam.suggested == e then out[#out + 1] = "best" end
    if fam.maxRank == e then out[#out + 1] = "max" end
    if fam.effRank == e then out[#out + 1] = "eff" end
    return out
end

-- One mark's reason (the rank card's Marks block, M5), the rule's own
-- numbers read back; `kind` "heal" or "damage".
--   best (also max, eff elsewhere) "no trade pays at 4:1; Rank 6: +5% per mana, -49% per sec"
--   best (all three)               "nothing to trade: it is also the most per mana"
--   best (not max)                 "+9% per mana for -7% per second: score 1.075 vs max 1.000 (damage at 4:1)"
--   max                            "most per second: 720"
--   eff                            "most per mana: 4.44 (+5% vs Rank 10 for -49% per second)"
--   eff under the floor            "most per mana: 4.75; under the 40% heal floor, so not best"
function W.MarkReason(mark, e, fam, kind)
    if type(e) ~= "table" or type(fam) ~= "table" then return "" end
    local maxR, effR = fam.maxRank, fam.effRank
    if mark == "max" then return "most per second: " .. Num(e.perSec) end
    if mark == "eff" then
        local text = "most per mana: " .. Num(e.perMana, 2)
        if fam.suggested ~= e then
            if UnderFloor(e, fam, kind) then
                return text .. "; under the " .. Num(ST.Rules.SUGGESTED_FLOOR * 100) .. "% heal floor, so not best"
            end
            if type(maxR) == "table" and maxR ~= e then
                local pm, ps = Change(e.perMana, maxR.perMana), Change(e.perSec, maxR.perSec)
                if pm and ps then
                    text = text .. " (" .. W.Signed(pm) .. " vs Rank " .. tostring(maxR.rank or "-") .. " for "
                        .. W.Signed(ps) .. " per second)"
                end
            end
        end
        return text
    end
    if mark ~= "best" then return "" end
    if type(maxR) ~= "table" then return "your highest rank: nothing to compare it with" end
    if maxR == e then
        if effR == nil or effR == e then return "nothing to trade: it is also the most per mana" end
        local pm, ps = Change(effR.perMana, e.perMana), Change(effR.perSec, e.perSec)
        local text = "no trade pays" .. At(kind)
        if pm and ps then
            text = text .. "; Rank " .. tostring(effR.rank or "-") .. ": " .. W.Signed(pm) .. " per mana, "
                .. W.Signed(ps) .. " per sec" .. ScoreTail(effR, e, kind) -- T128
        end
        return text
    end
    local pm, ps = Change(e.perMana, maxR.perMana), Change(e.perSec, maxR.perSec)
    if not (pm and ps) then return "the best trade against max" end
    local text = W.Signed(pm) .. " per mana for " .. W.Signed(ps) .. " per second"
    local vs = ScoreVsMax(e, maxR, kind) -- T128: the score as a ratio
    if vs then text = text .. ": " .. vs end
    return text .. " (" .. ((kind == "damage") and "damage" or "heals") .. At(kind) .. ")"
end

-- The tag's hover sentence (M5), for the strongest mark `tag` of `e`.
--   best = max: "The most per second, and no rank's extra per mana is worth
--               what it loses per second (damage: 1% per mana for 4% per
--               second). Most per mana is Rank 6: +5% for -49% per second."
--   best:       "The best trade against max (Rank 12): +1% per mana for -1%
--               per second. For heals 1% per mana is worth 6.7% per second,
--               among ranks with at least 40% of your highest heal."
--   max:        "The most per second: 986. The rank to press when time, not
--               mana, runs out."
--   eff:        "The most per mana, 10% more than Rank 12. Not best: its heal
--               is under 40% of your highest rank's, and below that a heal
--               costs you casts."
-- Answers title, sentence.
function W.MarkTip(tag, e, fam, kind)
    local maxR, effR = fam and fam.maxRank, fam and fam.effRank
    local heal = (kind ~= "damage")
    local rankName = "Rank " .. tostring(e and e.rank or "-")
    if tag == "best" then
        if type(maxR) ~= "table" then return "Best " .. rankName, W.SuggestedRule() end
        if maxR == e then
            -- review T128 m3: the rate holds at the margin only
            local text = "The most per second, and no rank's extra per mana is worth what it loses per second ("
                .. (heal and "heals" or "damage") .. ": " .. Weight(kind) .. " at the margin)."
            if type(effR) == "table" and effR ~= e then
                local pm, ps = Change(effR.perMana, e.perMana), Change(effR.perSec, e.perSec)
                if pm and ps then
                    text = text .. " Most per mana is Rank " .. tostring(effR.rank or "-") .. ": " .. W.Signed(pm)
                        .. " for " .. W.Signed(ps) .. " per second" .. ScoreTail(effR, e, kind) .. "." -- T128
                end
            else
                text = text .. " It is also the most per mana."
            end
            return "Best and max " .. rankName, text
        end
        local pm, ps = Change(e.perMana, maxR.perMana), Change(e.perSec, maxR.perSec)
        local text = "The best trade against max (Rank " .. tostring(maxR.rank or "-") .. ")"
        if pm and ps then text = text .. ": " .. W.Signed(pm) .. " per mana for " .. W.Signed(ps) .. " per second" end
        local vs = ScoreVsMax(e, maxR, kind) -- T128
        if vs then text = text .. ", " .. vs end
        text = text .. ". For " .. (heal and "heals" or "damage") .. " " .. Weight(kind):gsub(" for ", " is worth ")
            .. " at the margin"
        if heal then
            text = text .. ", among ranks with at least " .. Num(ST.Rules.SUGGESTED_FLOOR * 100)
                .. "% of your highest heal."
        else
            text = text .. "."
        end
        return "Best " .. rankName, text
    end
    if tag == "max" then
        return "Max " .. rankName, "The most per second: " .. Num(e and e.perSec)
            .. ". The rank to press when time, not mana, runs out."
    end
    if tag == "eff" then
        local text = "The most per mana"
        if type(maxR) == "table" and maxR ~= e then
            local pm = Change(e.perMana, maxR.perMana)
            if pm then text = text .. ", " .. Num(math.abs(pm)) .. "% more than Rank " .. tostring(maxR.rank or "-") end
        end
        text = text .. "."
        if UnderFloor(e, fam, kind) then
            text = text .. " Not best: its heal is under " .. Num(ST.Rules.SUGGESTED_FLOOR * 100)
                .. "% of your highest rank's, and below that a heal costs you casts."
        elseif fam and fam.suggested ~= e then
            text = text .. " Not best: the per second it gives up costs more than the mana it saves"
                .. At(kind) .. ". Press it when mana runs out before the fight does."
        end
        return "Eff " .. rankName, text
    end
    return nil
end

-- T128 (docs/tasks/T128-trade-score-and-rank-tips.md section 2): a rank
-- row's TRADE block against max, from the book the row shows (the what-if
-- book while What if is active). `ctx`:
--   e, best, max, eff -- the hovered row and the three marks' rows (a
--                        family's, or a rank's rolled rows')
--   beatenBy          -- the row that beats `e`, else nil
--   floorRow          -- the highest known row when `e` is a heal under the
--                        floor, else nil
--   kind              -- "heal" or "damage" (the trade-off k)
--   name(row)         -- "Rank 7", "rolled x3"
--   shown(row)        -- optional: the numbers the row's cells show (After
--                        overheal), for the Per mana / Per sec changes
--                        (review T128 m1); the score stays the marks'
--   note              -- optional: a closing line (what the score is from)
--   selfWord          -- optional: the TRADE line when `e` is max ("this
--                        rank is max"; a stack's "max of the stack")
-- Answers { label, text } pairs: TRADE, Per mana, Per sec, Score, then the
-- verdict(s) -- "holds best, max", "beaten by Rank 6", "under 40% of Rank
-- 12's heal", "Rank 6 trades better (1.075 vs 1.054)", "trade does not pay
-- (0.959)". {} without a max to trade against.
function W.TradeLines(ctx)
    local out = {}
    if type(ctx) ~= "table" then return out end
    local e, maxR, best = ctx.e, ctx.max, ctx.best
    if type(e) ~= "table" or type(maxR) ~= "table" then return out end
    local name = ctx.name or function(r) return "Rank " .. tostring(r and r.rank or "-") end
    local kind = ctx.kind
    local sc = ScoreOf(e, maxR, kind)
    if e == maxR then
        out[#out + 1] = { "TRADE", ctx.selfWord or "this rank is max" }
    else
        out[#out + 1] = { "TRADE", "vs max " .. name(maxR) }
        local se, sm = e, maxR
        if type(ctx.shown) == "function" then se, sm = ctx.shown(e) or e, ctx.shown(maxR) or maxR end
        local pm, ps = Change(se.perMana, sm.perMana), Change(se.perSec, sm.perSec)
        if pm then out[#out + 1] = { "Per mana", W.Signed(pm) } end
        if ps then out[#out + 1] = { "Per sec", W.Signed(ps) } end
    end
    if sc ~= nil then out[#out + 1] = { "Score", W.Score(sc) .. " vs max " .. W.Score(1) } end
    local holds = {}
    if best == e then holds[#holds + 1] = "best" end
    if maxR == e then holds[#holds + 1] = "max" end
    if ctx.eff == e then holds[#holds + 1] = "eff" end
    if #holds > 0 then out[#out + 1] = { "Verdict", "holds " .. table.concat(holds, ", ") } end
    if best ~= e then
        local why
        if type(ctx.beatenBy) == "table" then
            why = "beaten by " .. name(ctx.beatenBy)
        elseif type(ctx.floorRow) == "table" then
            why = "under " .. Num(ST.Rules.SUGGESTED_FLOOR * 100) .. "% of " .. name(ctx.floorRow) .. "'s "
                .. ((kind == "damage") and "damage" or "heal")
        else
            local bs = (type(best) == "table" and best ~= maxR) and ScoreOf(best, maxR, kind) or nil
            if bs ~= nil and sc ~= nil and (e == maxR or sc > 1) then
                why = name(best) .. " trades better (" .. W.Score(bs) .. " vs " .. W.Score(sc) .. ")"
            elseif sc ~= nil and e ~= maxR then
                why = "trade does not pay (" .. W.Score(sc) .. ")"
            end
        end
        if why then out[#out + 1] = { (#holds > 0) and "" or "Verdict", why } end
    end
    if type(ctx.note) == "string" and ctx.note ~= "" then out[#out + 1] = { ctx.note } end
    return out
end

-- The Spells pane's decision strip (3.5): the suggested rank against the
-- highest known, from Book:Compare's numbers `c` ({ perMana, value, cast } in
-- percent); `rank` the highest rank's number, `kind` "heal" or "damage". The
-- strip holds two lines beside the chip, so the pane tries the styles in
-- W.COMPARE_STYLES order and paints the first that fits; the "full" sentence
-- is always the hover's when a shorter one is painted.
--   "full"  -- "vs Rank 2 (your highest): 22% more damage per mana, 61% of
--              the damage, a 13% shorter cast."
--   "short" -- "vs Rank 2: 22% more per mana, 61% of the damage, 13%
--              shorter cast."
--   "tight" -- "vs R2: +22%/mana, 61% damage, -13% cast"
-- `c` nil (no comparison) is "".
-- T128: "brief" drops the cast ("vs R2: +22%/mana, 61% damage") and
-- "least" says per mana alone ("vs R2: +22%/mana"), so a narrow strip at a
-- large font still finds a wording that fits; `score` (optional, RR.Score's
-- number) closes the full and short sentences: "...; score 1.075 vs max 1.000."
W.COMPARE_STYLES = { "full", "short", "tight", "brief", "least" }
local function Pct(x) return math.floor(math.abs(x) + 0.5) end
-- `highest` true: the rank compared against is the highest known standing in
-- for a missing max (review T127 m7), headed "(highest)" not "(max)".
function W.Compare(c, rank, kind, style, highest, score)
    if type(c) ~= "table" then return "" end
    local dmg = (kind == "damage")
    local what = dmg and "damage" or "healing"
    local noun = dmg and "damage" or "heal"
    local r = tostring(rank or "-")
    local parts = {}
    if style == "tight" or style == "brief" or style == "least" then
        if type(c.perMana) == "number" then
            local p = Pct(c.perMana)
            parts[#parts + 1] = (p == 0) and "same/mana" or ((c.perMana > 0 and "+" or "-") .. p .. "%/mana")
        end
        if type(c.value) == "number" and style ~= "least" then parts[#parts + 1] = Pct(c.value) .. "% " .. noun end
        if type(c.cast) == "number" and style == "tight" then
            local p = Pct(c.cast)
            parts[#parts + 1] = (p == 0) and "same cast" or ((c.cast < 0 and "-" or "+") .. p .. "% cast")
        end
        local head = "vs R" .. r
        if #parts == 0 then return head end
        return head .. ": " .. table.concat(parts, ", ")
    end
    local short = (style == "short")
    if type(c.perMana) == "number" then
        local p = Pct(c.perMana)
        local per = short and "per mana" or (what .. " per mana")
        if p == 0 then
            parts[#parts + 1] = "the same " .. per
        else
            parts[#parts + 1] = p .. "% " .. (c.perMana > 0 and "more" or "less") .. " " .. per
        end
    end
    if type(c.value) == "number" then parts[#parts + 1] = Pct(c.value) .. "% of the " .. noun end
    if type(c.cast) == "number" then
        local p = Pct(c.cast)
        if p == 0 then
            parts[#parts + 1] = "the same cast time"
        else
            parts[#parts + 1] = (short and "" or "a ") .. p .. "% " .. (c.cast < 0 and "shorter" or "longer") .. " cast"
        end
    end
    local tag = highest and " (highest)" or " (max)" -- T127: against max
    local head = "vs Rank " .. r
    if not short then head = head .. tag end
    if #parts == 0 then return head .. "." end
    local tail = ""
    if type(score) == "number" then -- T128
        if short then tail = ", score " .. W.Score(score)
        else tail = "; score " .. W.Score(score) .. " vs max " .. W.Score(1) end
    end
    return head .. ": " .. table.concat(parts, ", ") .. tail .. "."
end

-- The strip when the suggested rank is the highest known, by the same styles.
function W.CompareSame(style)
    if style ~= "full" and style ~= "short" then return "Your highest is best." end
    return "Your highest rank is also the best rank."
end

-- T127 (mockup M5): the strip when best is also max, by the same styles;
-- `fam` gives the marks, `kind` "heal" or "damage".
--   one known rank   "Your only rank."
--   all three marks  "Rank 12 holds all three marks: the most per mana and
--                    per second. Every lower rank is beaten."
--   eff elsewhere    full  "Rank 10 is best and max: no rank's extra per
--                          mana is worth what it loses per second (damage,
--                          4:1 at the margin). Rank 6 has the most per mana: 5% more for
--                          49% less per second."
--                    short "Also max. Most per mana: Rank 6, +5% per mana,
--                          -49% per sec."
--                    tight "Also max. Most per mana: R6."
-- No max (no rank with numbers): W.CompareSame.
function W.CompareBestIsMax(fam, kind, style)
    local best, effR = fam and fam.suggested, fam and fam.effRank
    -- a rank with rolled rows (TBC's Lifebloom): the row that holds best
    if type(best) == "table" and type(best.variants) == "table" then
        if best.bestOfStacks then return "One cast holds all three marks: let it bloom." end
        for _, v in ipairs(best.variants) do
            if v.bestOfStacks then
                return "Rolled " .. tostring(v.variantLabel or ("x" .. tostring(v.variant))) .. " holds all three marks."
            end
        end
    end
    local known = 0
    for _, x in ipairs(fam and fam.ranks or {}) do
        if x.known then known = known + 1 end
    end
    if known == 1 then return "Your only rank." end
    if type(best) ~= "table" or fam.maxRank ~= best then return W.CompareSame(style) end
    local rn = tostring(best.rank or "-")
    if effR == nil or effR == best then
        if style ~= "full" and style ~= "short" then return "Rank " .. rn .. " holds all three marks." end
        return "Rank " .. rn .. " holds all three marks: the most per mana and per second. Every lower rank is beaten."
    end
    local er = tostring(effR.rank or "-")
    local pm, ps = Change(effR.perMana, best.perMana), Change(effR.perSec, best.perSec)
    if (style ~= "full" and style ~= "short") or not (pm and ps) then return "Also max. Most per mana: R" .. er .. "." end
    if style == "short" then
        return "Also max. Most per mana: Rank " .. er .. ", " .. W.Signed(pm) .. " per mana, " .. W.Signed(ps) .. " per sec."
    end
    local ratio = W.TradeRatio(TradeK(kind))
    local paren = (kind == "damage") and "damage" or "heals"
    if ratio then paren = paren .. ", " .. ratio .. " at the margin" end -- review T128 m3
    return "Rank " .. rn .. " is best and max: no rank's extra per mana is worth what it loses per second ("
        .. paren .. "). Rank " .. er .. " has the most per mana: " .. Num(math.abs(pm)) .. "% "
        .. ((pm >= 0) and "more" or "less") .. " for " .. Num(math.abs(ps)) .. "% "
        .. ((ps <= 0) and "less" or "more") .. " per second" .. ScoreTail(effR, best, kind) .. "."
end

-- T110 (docs/SPEC-next.md 4.2 P6): an either-or spell's other half, for the
-- tooltip's detail -- label, text, or nil. On the damage half a role picked
-- (Book:Half's view entry, `of` the heal entry) it is the heal: "Or heals";
-- on a heal entry that keeps a damage half (entry.alt, T95) the damage:
-- "Or damage". The text is the half's value and its per mana, one target's
-- (decision 12): "320  0.98 per mana".
function W.OtherHalf(e)
    if type(e) ~= "table" then return nil end
    local label, value, perMana
    if e.half == "damage" and type(e.of) == "table" then
        label, value, perMana = "Or heals", e.of.value, e.of.perMana
    elseif type(e.alt) == "table" and e.alt.kind == "damage" then
        label, value, perMana = "Or damage", e.alt.value, e.alt.perMana
    else
        return nil
    end
    if type(value) ~= "number" then return nil end
    local text = Num(value)
    if type(perMana) == "number" then text = text .. "  " .. Num(perMana, 2) .. " per mana" end
    return label, text
end

--------------------------------------------------------------------------------
-- T117 (docs/SPEC-one-ui.md 3.1, 4.3; mockup M1's +Healing pair, M2's
-- estimated hover, M5's How lines): the share of +healing (or +damage) a
-- rank gets, from entry.bonus = { counts, from, amount, of, why, at }.
--------------------------------------------------------------------------------

-- "+Healing" for a heal, "+Damage" for a damage family.
function W.BonusLabel(kind)
    if kind == "damage" then return "+Damage" end
    return "+Healing"
end

-- "+5%", "-3%": a change in percent, rounded, its sign always said.
function W.Signed(pct)
    if type(pct) ~= "number" or pct ~= pct then return "-" end
    local n = math.floor(pct + 0.5)
    if n > 0 then return "+" .. n .. "%" end
    return n .. "%"
end

-- T124 (docs/tasks/T124-whatif-fair-compare-spell-damage.md): the What if's
-- footer when the suggestion moved. `old` and `new` are the two ranks' entries
-- read from ONE book (the what-if book: like with like); `beatenBy` the rank
-- number that beats `old` in that book, else nil; `top` the highest known
-- rank's number; `kind` "heal" or "damage". When the new rank gives less per
-- mana, the rule did not pick it on per mana, so the reason follows: beaten,
-- else under the floor (ST.Rules.SUGGESTED_FLOOR, Spells/RankRules.lua's).
--   "Suggested: Rank 1 -> Rank 2. With these stats Rank 2 gives 7.40 per
--    mana, Rank 1 6.83 (+8%)."
-- T127: `underFloor` true when `old` is a heal under the floor; else, when
-- neither beaten nor under the floor, its trade against max no longer pays:
--   "... Rank 6's trade against max no longer pays."
function W.SuggestionMoved(old, new, beatenBy, top, kind, underFloor)
    local oldR, newR = tostring(old.rank or "-"), tostring(new.rank or "-")
    local text = "Best: Rank " .. oldR .. " -> Rank " .. newR .. "."
    local p, q = new.perMana, old.perMana
    if type(p) ~= "number" or type(q) ~= "number" then return text end
    local pct = ""
    if q > 0 then pct = " (" .. W.Signed((p / q - 1) * 100) .. ")" end
    text = text .. " With these stats Rank " .. newR .. " gives " .. Num(p, 2) .. " per mana, Rank " .. oldR
        .. " " .. Num(q, 2) .. pct .. "."
    if p < q then
        if beatenBy ~= nil then
            text = text .. " Rank " .. oldR .. " is beaten by Rank " .. tostring(beatenBy) .. "."
        elseif underFloor and top ~= nil then
            local floor = (ST.Rules and ST.Rules.SUGGESTED_FLOOR) or 0.4
            text = text .. " Rank " .. oldR .. " is under " .. Num(floor * 100) .. "% of Rank " .. tostring(top)
                .. "'s " .. ((kind == "damage") and "damage" or "heal") .. "."
        else
            text = text .. " Rank " .. oldR .. "'s trade against max no longer pays."
        end
    end
    return text
end

-- "2 Oct": a measurement's day, the leading zero dropped.
local function Day(at)
    if type(at) ~= "number" or type(date) ~= "function" then return nil end
    local ok, s = pcall(date, "%d %b", at)
    if not ok or type(s) ~= "string" then return nil end
    return (s:gsub("^0", ""))
end

-- W.Bonus(e, style, kind) -> the words, or nil when the entry has no share.
-- `kind` names the label ("heal" by default; "damage" -> "+Damage").
--   "card" -- the rank card's +Healing value (3.5):
--             model     "840 of your 700 (x1.20 Empowered Touch)"
--             estimated "counts ~12% estimated (cast 1.5 / 3.5 x 0.29)"
--             measured  "31% measured: your gear change, 2 Oct"
--   "how"  -- the block's How line (5.x):
--             "+Healing counts 120% (x1.20 Empowered Touch)",
--             "+Healing counts ~12%, estimated", "+Healing counts 31%, measured 2 Oct"
--   "tip"  -- the percentage alone: "120%", "~12%", "31%"
-- An estimate carries "~"; the source's word is the caller's `from`.
function W.Bonus(e, style, kind)
    local b = type(e) == "table" and e.bonus
    if type(b) ~= "table" or type(b.counts) ~= "number" or b.counts ~= b.counts then return nil end
    local pct = Num(b.counts * 100) .. "%"
    local est = (b.from == "estimated")
    if est then pct = "~" .. pct end
    local why = (type(b.why) == "string" and b.why ~= "") and b.why or nil
    local day = (b.from == "measured") and Day(b.at) or nil

    if style == "tip" then return pct end

    if style == "how" then
        local text = W.BonusLabel(kind) .. " counts " .. pct
        if est then return text .. ", estimated" end
        if b.from == "measured" then return text .. ", measured" .. (day and (" " .. day) or "") end
        return text .. (why and (" (" .. why .. ")") or "")
    end

    -- "card"
    if est then
        return "counts " .. pct .. " estimated" .. (why and (" (" .. why .. ")") or "")
    end
    if b.from == "measured" then
        return pct .. " measured: " .. (why or "your gear change") .. (day and (", " .. day) or "")
    end
    if type(b.amount) == "number" and type(b.of) == "number" then
        return Num(b.amount) .. " of your " .. Num(b.of) .. (why and (" (" .. why .. ")") or "")
    end
    return "counts " .. pct .. (why and (" (" .. why .. ")") or "")
end
