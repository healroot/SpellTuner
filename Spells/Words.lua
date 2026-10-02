-- T67 (P23 of docs/PLAN-refactor-ux.md, review A13): the spell words, once.
-- How a rank's facts are said -- its cost, its cast, per mana, per second,
-- casts to OOM, the value's parts and the crit range -- for the two surfaces
-- that say them, UI/SpellTip_Forever.lua (the block on a spell tooltip,
-- docs/SPEC-forever-ui.md 5.x) and UI/SpellsPane_Forever.lua (the RANKS
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
local _, MD = ...

MD.Words = MD.Words or {}
local W = MD.Words

-- Vanilla's crit rule (1.5x); Forever's own is UNVERIFIED (HoTs crit since
-- 70009, REFERENCES-FOREVER.md sec4, amount not stated). T12's /st measure
-- checks it against a landed heal above the crit range's top.
W.CRIT_MULT = 1.5
-- Spells/Book.lua's global cooldown: the interval a direct spell's per second
-- is over when its cast is shorter, and an Other spell's for casts to OOM.
W.GCD = MD.Book.GCD

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
function W.Cast(e, style)
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
    if (IsAbsorb(e) and part == nil) or (part and (part.min ~= nil or part.max ~= nil)) then
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

-- The suggested rule in words (3.5), its floor read from MD.Rules.
function W.SuggestedRule()
    return "Highest heal per mana among the ranks nothing beats on both per mana and per second, with at least "
        .. Num(MD.Rules.SUGGESTED_FLOOR * 100) .. "% of your highest rank's heal."
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
