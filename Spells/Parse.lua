-- T8 (docs/tasks/T8-spell-parse.md): a spell's own client-drawn text into plain
-- numbers. Pure Lua, no client call, no MD.API call -- everything here reads a
-- string and answers a table or nil. Q1 (FOREVER-PLAN.md Sec6) is answered
-- dynamic: the client already prints the caster's own value, so this file
-- supplies no coefficient, no default, no per-school table. The one number it
-- is allowed to invent is arithmetic on numbers it already read (Total).
local _, MD = ...
MD.Parse = MD.Parse or {}
local Parse = MD.Parse

-- A digit run that may carry thousands commas ("2,139"). Comma removal
-- happens only when a captured string is turned into a number (N()), never
-- to the text itself, so Clean()'s own commas (none, but a caller's raw text
-- might have one anywhere) are never touched.
-- T91 (docs/SPEC-next.md 4.2 P0 d): a decimal amount is one number ("0.5",
-- Mana Burn), never the "5" after its point. The frontier refuses a start
-- right after a letter, a digit, a point or a comma (so no match begins
-- inside "0.5" or "1,050"); the optional ".digits" tail reads the decimal.
-- A sentence's own full stop is never part of a number: every text a
-- pattern reads has passed DetachStops() first, which leaves a point after a
-- digit only where a digit follows it.
local NUM = "%f[%w.,]%d[%d,]*%.?%d*"

local SCHOOLS = {
    Physical = true, Holy = true, Fire = true, Nature = true,
    Frost = true, Shadow = true, Arcane = true,
}

-- Only WoW's four school colour codes plus |r are ever handed to Clean; a
-- 5th/6th hex digit or a bad code is not our business to detect, just to
-- remove: %x%x x8 matches exactly what |c always is.
local COLOR_START = "|c%x%x%x%x%x%x%x%x"
local COLOR_END = "|r"
local TEXTURE = "|T.-|t"

-- table.concat(gsub-result-truncated-to-one-value): gsub always returns the
-- string plus a count; feeding that pair straight into tonumber() or a table
-- field would hand the count along too on some calls, so every gsub used for
-- its string alone is wrapped in parens here (the multi-return trap named in
-- CLAUDE.md).
local function StripCommas(s)
    return (s:gsub(",", ""))
end

local function N(s)
    if s == nil then return nil end
    return tonumber(StripCommas(s))
end

local function NormSchool(word)
    if word and SCHOOLS[word] then return word end
    return nil
end

-- Replaces a matched span with spaces of the same length so a later, looser
-- pattern never re-reads a number a more specific pattern already claimed
-- (Renew's "of 45 damage over 15 sec" is a heal; blanking it is what keeps
-- the damage patterns from also reading a Renew damage part out of it).
local function Blank(text, s, e)
    if not s then return text end
    return text:sub(1, s - 1) .. string.rep(" ", e - s + 1) .. text:sub(e + 1)
end

-- T91: a full stop right after a digit ("for 40 to 55.") is moved one space
-- off it ("55 ."), so NUM's decimal tail never swallows a sentence's end and
-- a blanked amount never blanks the stop a later sentence test looks for. A
-- decimal point (a digit on both sides) is left alone. The sentence
-- boundary "%.%s" survives: the stop is still followed by a space or ends
-- the text.
local function DetachStops(text)
    local out = text:gsub("(%d)%.(%D)", "%1 .%2")
    out = out:gsub("(%d)%.$", "%1 .")
    return out
end

-- T91 (docs/SPEC-next.md 4.2 P0 d): a sentence about "your next" cast
-- describes what a LATER spell will do, never this one (Light's Vigil:
-- "Your next Holy Shock cast on them ... allied targets to heal their party
-- for 684 to 724" -- a buff, read before T91 as a 684-724 heal costing 1340
-- mana). Each such sentence is blanked, spaces of the same length, so no
-- pattern reads an amount out of it; the rest of the text is read as before
-- (Holy Nova R2+ ends with "... a 5% chance for your next Holy Nova to cost
-- no Mana", and its own heal and damage still read).
local FUTURE = "%f[%a][Yy]our%s+next%f[%A]"

local function DropFutureClauses(text)
    if not text:find(FUTURE) then return text end
    local out, from = text, 1
    while from <= #out do
        local stop = out:find("%.%s", from) or #out
        local sentence = out:sub(from, stop)
        if sentence:find(FUTURE) then out = Blank(out, from, stop) end
        from = stop + 1
    end
    return out
end

-- The working copy every reader below parses: cleaned, stops detached,
-- future clauses blanked. nil for a non-string or an empty text.
local function Prepare(text)
    local clean = Parse.Clean(text)
    if clean == nil or clean == "" then return nil end
    return DropFutureClauses(DetachStops(clean))
end

--------------------------------------------------------------------------------
-- Parse.Clean
--------------------------------------------------------------------------------

-- The client's own grammar escape (m2 lines 154, 161): |4singular:plural;,
-- chosen by the number immediately before it. Expanded before every other
-- strip (Files) so a colour/texture code straddling it is never the reason
-- the escape survives. A preceding "N " picks the singular only when N is
-- exactly 1, else the plural; with no number before it at all, the plural is
-- taken (UNKNOWN what the client does -- the safe reading for a count we
-- cannot see).
local function ExpandGrammar(text)
    local out = text:gsub("(%d+)(%s+)|4(.-):(.-);", function(num, gap, singular, plural)
        if tonumber(num) == 1 then return num .. gap .. singular end
        return num .. gap .. plural
    end)
    out = out:gsub("|4(.-):(.-);", function(_, plural) return plural end)
    return out
end

-- Strips the client's own escape codes and normalises whitespace. nil in,
-- nil out -- every other function here starts by calling this, which is what
-- lets them accept anything without raising.
function Parse.Clean(text)
    if type(text) ~= "string" then return nil end
    local out = ExpandGrammar(text)
    out = out:gsub(COLOR_START, "")
    out = out:gsub(COLOR_END, "")
    out = out:gsub(TEXTURE, "")
    out = out:gsub("|n", " ")
    out = out:gsub("[\n\r]", " ")
    out = out:gsub("%s+", " ")
    out = out:gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

--------------------------------------------------------------------------------
-- Parse.Description
--------------------------------------------------------------------------------

-- The three "amount every period for a duration" shapes seen so far
-- (docs/REFERENCES-FOREVER.md Sec1): a heal phrased as "for N every P sec for
-- D sec" (Tranquility), a damage tick phrased as "N Damage to enemies every P
-- sec" with the duration in a separate "Lasts D sec" sentence (Hurricane), and
-- "N Damage each second for D sec" where "each second" itself states the
-- period (Arcane Missiles). Tried before anything else, because a looser
-- direct/over pattern would otherwise read the tick's own number as a plain
-- damage amount and drop the periodic shape on the floor.
-- No "Heals"/"Heal" frontier here on purpose: Tranquility's own verb is
-- "Regenerates". The shape itself ("for N every P sec for D sec") is what
-- marks it a heal; the two damage tick shapes below read differently
-- ("to enemies every" / "each second for"), so there is no ambiguity to
-- resolve by requiring a particular verb.
local TICK_HEAL = "for%s+(" .. NUM .. ")%s+every%s+(%d+%.?%d*)%s+sec%s+for%s+(%d+%.?%d*)%s+sec"
local TICK_DAMAGE_ENEMIES = "(" .. NUM .. ")%s+(%a+)%s+damage%s+to%s+enemies%s+every%s+(%d+%.?%d*)%s+sec"
local TICK_DAMAGE_EACHSEC = "(" .. NUM .. ")%s+(%a+)%s+damage%s+each second%s+for%s+(%d+%.?%d*)%s+sec"
local LASTS = "Lasts%s+(%d+%.?%d*)%s+sec"

-- Heal shapes, most specific (a direct amount plus a HoT continuation) first
-- so a looser pattern never truncates a combined part to just its first half.
-- "and another" (Regrowth) and ", an additional" (Riptide) are the two
-- continuation idioms seen; a plain damage continuation reads differently
-- ("and then an additional"/"and an additional" -- see the damage patterns
-- below), which is what keeps these heal-only.
local HEAL_RANGE_AND_ANOTHER_OVER =
    "%f[%a][Hh]eals?%f[%A].-for%s+(" .. NUM .. ")%s+to%s+(" .. NUM .. ")%s+and%s+another%s+(" .. NUM .. ")%s+over%s+(%d+%.?%d*)%s+sec"
local HEAL_RANGE_ADDITIONAL_OVER =
    "%f[%a][Hh]eals?%f[%A].-for%s+(" .. NUM .. ")%s+to%s+(" .. NUM .. ")%s*,?%s*an%s+additional%s+(" .. NUM .. ")%s+over%s+(%d+%.?%d*)%s+sec"
-- A direct range only ("Heals a friendly target for 40 to 55.").
local HEAL_RANGE = "%f[%a][Hh]eals?%f[%A].-for%s+(" .. NUM .. ")%s+to%s+(" .. NUM .. ")"
-- An over-duration only, no direct amount ("Heals the target for 32 over 12 sec.").
local HEAL_OVER = "%f[%a][Hh]eals?%f[%A].-for%s+(" .. NUM .. ")%s+over%s+(%d+%.?%d*)%s+sec"
-- Renew's own phrasing: "damage" names the school-less heal amount, not a
-- damage clause, because the verb is a heal (the fixture's own rule).
local HEAL_OF_DAMAGE_OVER = "%f[%a][Hh]eals?%f[%A].-of%s+(" .. NUM .. ")%s+damage%s+over%s+(%d+%.?%d*)%s+sec"
-- The number comes before the word here ("110 to 118 healing to an ally.").
local HEAL_RANGE_TRAILING = "(" .. NUM .. ")%s+to%s+(" .. NUM .. ")%s+healing"
-- "... and healing all party members within 10 yards for 49 to 57."
local HEAL_TRAILING_FOR_RANGE = "healing%s+.-for%s+(" .. NUM .. ")%s+to%s+(" .. NUM .. ")"

-- Damage shapes. Combined direct+over first (most specific), then an
-- over-only tail, then a plain direct amount -- the same reasoning as the
-- heal list: a plain pattern tried first would truncate a combined one.
local DAMAGE_RANGE_THEN_ADDITIONAL_OVER =
    "(" .. NUM .. ")%s+to%s+(" .. NUM .. ")%s+(%a+)%s+damage%s+and%s+then%s+an%s+additional%s+(" .. NUM .. ")%s+(%a+)%s+damage%s+over%s+(%d+%.?%d*)%s+sec"
local DAMAGE_RANGE_ADDITIONAL_OVER =
    "(" .. NUM .. ")%s+to%s+(" .. NUM .. ")%s+(%a+)%s+damage%s+and%s+an%s+additional%s+(" .. NUM .. ")%s+(%a+)%s+damage%s+over%s+(%d+%.?%d*)%s+sec"
local DAMAGE_SINGLE_IMMEDIATELY_OVER =
    "(" .. NUM .. ")%s+(%a+)%s+damage%s+immediately%s+and%s+(" .. NUM .. ")%s+(%a+)%s+damage%s+over%s+(%d+%.?%d*)%s+sec"
local DAMAGE_SINGLE_THEN_ADDITIONAL_OVER =
    "(" .. NUM .. ")%s+(%a+)%s+damage%s+and%s+then%s+an%s+additional%s+(" .. NUM .. ")%s+(%a+)%s+damage%s+over%s+(%d+%.?%d*)%s+sec"
local DAMAGE_OVER_SCHOOL = "(" .. NUM .. ")%s+(%a+)%s+damage%s+over%s+(%d+%.?%d*)%s+sec"
local DAMAGE_OVER_NOSCHOOL = "(" .. NUM .. ")%s+damage%s+over%s+(%d+%.?%d*)%s+sec"
local DAMAGE_RANGE = "(" .. NUM .. ")%s+to%s+(" .. NUM .. ")%s+(%a+)%s+damage"
local DAMAGE_SINGLE = "(" .. NUM .. ")%s+(%a+)%s+damage"

local ABSORB = "absorbing%s+(" .. NUM .. ")%s+damage"

-- The sentence holding text[s..e]: from just after the previous ". " (or
-- the start) to the next "." followed by a space (or the end). A decimal
-- ("1.5 sec") is never a boundary -- no space follows its point.
local function SentenceBounds(text, s, e)
    local from = 1
    for p in text:sub(1, s - 1):gmatch("%.%s+()") do from = p end
    local to = text:find("%.%s", e + 1) or #text
    return from, to
end

local function SentenceAt(text, s, e)
    local from, to = SentenceBounds(text, s, e)
    return text:sub(from, to)
end

-- Review R35: "N School damage" that is not what the cast itself deals, so
-- DAMAGE_SINGLE refuses it rather than guess (this file's own rule):
--   * a ward's absorb -- the amount right after "Absorbs" (Fire / Frost /
--     Shadow Ward, Mana Shield: "Absorbs 162 Frost damage");
--   * a reactive clause -- a sentence about whoever hits the target: an
--     "attacker" (Thorns, Lightning Shield, Shadowguard, Fire Shield, Touch
--     of Weakness), a creature "that strikes" (Retribution Aura) or an attack
--     "blocked" (Holy Shield).
-- Texts: talentsforever.com's beta client 1.60.1.70009 descriptions. The
-- sentence test is DAMAGE_SINGLE's only: a range ("strikes an enemy for 286
-- to 314 Holy damage", Hammer of Wrath) is a cast's own and never reaches it.
local function NotCastDamage(text, s, e)
    if text:sub(1, s - 1):match("[Aa]bsorbs%s+$") then return true end
    local sentence = SentenceAt(text, s, e):lower()
    if sentence:find("attacker", 1, true) then return true end
    if sentence:find("%f[%a]that%s+strikes%f[%A]") then return true end
    if sentence:find("%f[%a]blocked%f[%A]") then return true end
    return false
end

-- Review B4 (docs/review/2026-09-30-project-review.md): DAMAGE_SINGLE is the
-- catch-all, so it refuses an amount the rest of its sentence says is not one
-- direct hit (this file's own rule: refuse rather than guess):
--   * a period phrase after the amount -- "every", "each second", "per
--     second", "Lasts" -- makes it one tick of a periodic effect whose shape
--     is none of the recognised ones (TICK_DAMAGE_ENEMIES / _EACHSEC):
--     Hellfire's "83 Fire damage to all nearby enemies every 1 sec", Volley's
--     "50 Arcane damage to enemy targets within 8 yards every 1 second";
--   * "or N healing" offers the same number as a heal on an ally (Penance),
--     so the amount is not damage alone.
-- No new shape is read from these: a periodic clause worded otherwise stays
-- unread until its wording is verified and given its own pattern.
local function PeriodicOrEitherAfter(text, e)
    local to = text:find("%.%s", e + 1) or #text
    local rest = text:sub(e + 1, to):lower()
    if rest:find("%f[%a]every%f[%A]") then return true end
    if rest:find("each%s+second") then return true end
    if rest:find("per%s+second") then return true end
    if rest:find("%f[%a]lasts%f[%A]") then return true end
    if rest:find("%f[%a]or%s+" .. NUM .. "%s+healing%f[%A]") then return true end
    return false
end

-- T91 (docs/SPEC-next.md 4.2 P0 d): the word between the amount and
-- "damage" is "additional" -- the catch-all DAMAGE_SINGLE (and DAMAGE_RANGE)
-- read Execute's "into 15 additional damage" as its hit. An "additional"
-- amount that belongs to the cast is always read by a combined pattern
-- above ("and then an additional 12 Arcane damage over 9 sec"), never here.
local function AddedPerPoint(word)
    return type(word) == "string" and word:lower() == "additional"
end

-- Description() reads one clause shape at a time out of the cleaned text,
-- blanking whatever it just read so a looser pattern tried afterwards never
-- re-reads the same digits under a different (wrong) role.
function Parse.Description(text)
    local clean = Prepare(text)
    if clean == nil then return nil end

    local heal, damage, absorb

    local s, e, aAmt = clean:find(ABSORB)
    if s then
        absorb = N(aAmt)
        clean = Blank(clean, s, e)
    end

    s, e = nil, nil
    local hs, he, thN, thP, thD = clean:find(TICK_HEAL)
    if hs then
        heal = { tick = N(thN), period = tonumber(thP), periodDur = tonumber(thD) }
        clean = Blank(clean, hs, he)
    end

    local ds, de, dN, dSchool, dP = clean:find(TICK_DAMAGE_ENEMIES)
    if not ds then
        ds, de, dN, dSchool, dP = clean:find(TICK_DAMAGE_EACHSEC)
        if ds then
            damage = { tick = N(dN), period = 1, periodDur = tonumber(dP), school = NormSchool(dSchool) }
            clean = Blank(clean, ds, de)
        end
    else
        local lastsDur = clean:match(LASTS)
        damage = { tick = N(dN), period = tonumber(dP), periodDur = tonumber(lastsDur), school = NormSchool(dSchool) }
        clean = Blank(clean, ds, de)
    end

    if heal == nil then
        local a, b, x1, y1, x2, y2 = clean:find(HEAL_RANGE_AND_ANOTHER_OVER)
        if not a then a, b, x1, y1, x2, y2 = clean:find(HEAL_RANGE_ADDITIONAL_OVER) end
        if a then
            heal = { min = N(x1), max = N(y1), over = N(x2), dur = tonumber(y2) }
            clean = Blank(clean, a, b)
        end
    end
    if heal == nil then
        local a, b, x1, y1 = clean:find(HEAL_RANGE)
        if a then
            heal = { min = N(x1), max = N(y1) }
            clean = Blank(clean, a, b)
        end
    end
    if heal == nil then
        local a, b, x1, y1 = clean:find(HEAL_OVER)
        if a then
            heal = { over = N(x1), dur = tonumber(y1) }
            clean = Blank(clean, a, b)
        end
    end
    if heal == nil then
        local a, b, x1, y1 = clean:find(HEAL_OF_DAMAGE_OVER)
        if a then
            heal = { over = N(x1), dur = tonumber(y1) }
            clean = Blank(clean, a, b)
        end
    end
    if heal == nil then
        local a, b, x1, y1 = clean:find(HEAL_RANGE_TRAILING)
        if a then
            heal = { min = N(x1), max = N(y1) }
            clean = Blank(clean, a, b)
        end
    end
    if heal == nil then
        local a, b, x1, y1 = clean:find(HEAL_TRAILING_FOR_RANGE)
        if a then
            heal = { min = N(x1), max = N(y1) }
            clean = Blank(clean, a, b)
        end
    end

    if damage == nil then
        local a, b, x1, y1, sc1, x2, sc2, y2 = clean:find(DAMAGE_RANGE_THEN_ADDITIONAL_OVER)
        if not a then a, b, x1, y1, sc1, x2, sc2, y2 = clean:find(DAMAGE_RANGE_ADDITIONAL_OVER) end
        if a then
            damage = { min = N(x1), max = N(y1), over = N(x2), dur = tonumber(y2), school = NormSchool(sc1) }
            clean = Blank(clean, a, b)
        end
    end
    if damage == nil then
        local a, b, x1, sc1, x2, sc2, y1 = clean:find(DAMAGE_SINGLE_IMMEDIATELY_OVER)
        if not a then a, b, x1, sc1, x2, sc2, y1 = clean:find(DAMAGE_SINGLE_THEN_ADDITIONAL_OVER) end
        if a then
            damage = { min = N(x1), max = N(x1), over = N(x2), dur = tonumber(y1), school = NormSchool(sc1) }
            clean = Blank(clean, a, b)
        end
    end
    if damage == nil then
        local a, b, x1, sc1, y1 = clean:find(DAMAGE_OVER_SCHOOL)
        if a then
            damage = { over = N(x1), dur = tonumber(y1), school = NormSchool(sc1) }
            clean = Blank(clean, a, b)
        else
            a, b, x1, y1 = clean:find(DAMAGE_OVER_NOSCHOOL)
            if a then
                damage = { over = N(x1), dur = tonumber(y1) }
                clean = Blank(clean, a, b)
            end
        end
    end
    if damage == nil then
        local a, b, x1, y1, sc1 = clean:find(DAMAGE_RANGE)
        if a and not AddedPerPoint(sc1) then
            damage = { min = N(x1), max = N(y1), school = NormSchool(sc1) }
            clean = Blank(clean, a, b)
        end
    end
    if damage == nil then
        local a, b, x1, sc1 = clean:find(DAMAGE_SINGLE)
        -- Thorns' shape (m2 line 91): "N School damage to attackers when
        -- hit" is a reactive aura's per-hit damage, not the cast's own --
        -- refused rather than read as a direct amount. Review R35: so is
        -- every other reactive or ward clause (NotCastDamage).
        -- Review B4: nor one tick of an unrecognised periodic clause, nor an
        -- amount offered "or N healing" to an ally (PeriodicOrEitherAfter).
        -- T91: nor "N additional damage" -- an amount added per spare point
        -- (Execute: "converting each extra point of rage into 15 additional
        -- damage"; Ferocious Bite's energy), never the cast's own hit.
        if a and not NotCastDamage(clean, a, b) and not PeriodicOrEitherAfter(clean, b)
            and not AddedPerPoint(sc1) then
            damage = { min = N(x1), max = N(x1), school = NormSchool(sc1) }
            clean = Blank(clean, a, b)
        end
    end

    if heal == nil and damage == nil and absorb == nil then return nil end
    return { heal = heal, damage = damage, absorb = absorb }
end

--------------------------------------------------------------------------------
-- Parse.Total / Parse.Duration
--------------------------------------------------------------------------------

-- The one arithmetic this file is allowed: adding up what the text already
-- gave. A tick whose text never said how long it runs for (no periodDur)
-- cannot be totalled, so it is refused rather than guessed at 0 or 1 tick.
function Parse.Total(part)
    if type(part) ~= "table" then return nil end
    if part.tick ~= nil and part.periodDur == nil and part.min == nil and part.max == nil and part.over == nil then
        return nil
    end
    local total = 0
    if part.min ~= nil or part.max ~= nil then
        total = total + ((part.min or 0) + (part.max or 0)) / 2
    end
    if part.over ~= nil then
        total = total + part.over
    end
    if part.tick ~= nil and part.periodDur ~= nil and part.period ~= nil and part.period > 0 then
        total = total + part.tick * math.floor(part.periodDur / part.period)
    end
    return total
end

function Parse.Duration(part)
    if type(part) ~= "table" then return nil end
    return part.dur or part.periodDur or nil
end

--------------------------------------------------------------------------------
-- Parse.Cost
--------------------------------------------------------------------------------

function Parse.Cost(line)
    local clean = Parse.Clean(line)
    if clean == nil or clean == "" then return nil end

    local pct = clean:match("^(%d+%.?%d*)%%%s+of%s+base%s+mana$")
    if pct then
        return { percent = tonumber(pct), power = "Mana" }
    end

    local amt, power = clean:match("^(" .. NUM .. ")%s+(%a+)$")
    if amt then
        return { amount = N(amt), power = power }
    end

    return nil
end

--------------------------------------------------------------------------------
-- Parse.Cast
--------------------------------------------------------------------------------

function Parse.Cast(line)
    local clean = Parse.Clean(line)
    if clean == nil or clean == "" then return nil end

    if clean == "Instant" then return 0, "instant" end
    if clean == "Channeled" then return 0, "channeled" end

    local secs = clean:match("^(%d+%.?%d*)%s+sec%s+cast$")
    if secs then return tonumber(secs), "cast" end

    return nil
end

--------------------------------------------------------------------------------
-- Parse.Rank
--------------------------------------------------------------------------------

function Parse.Rank(text)
    local clean = Parse.Clean(text)
    if clean == nil or clean == "" then return nil end

    local rank = clean:match("^Rank%s+(%d+)$")
    if rank then return tonumber(rank) end

    return nil
end

--------------------------------------------------------------------------------
-- T91 (docs/SPEC-next.md 4.2 P1 and P4): what a spell's text says about its
-- cooldown, its lockout, whom it reaches and the mana it gives. The file's
-- rule holds: every number returned is in the text, or plain arithmetic on
-- one (a unit turned into seconds, a percent into a fraction, a target count
-- into its jumps), and a wording no shape recognises is refused -- nil, never
-- a guess. Texts: talentsforever.com's export of the beta client
-- 1.60.1.70009 (tools/data/parse-fixture.lua names each).
--------------------------------------------------------------------------------

-- A duration's unit word -> seconds per unit; any other word is not a
-- duration this file reads.
local UNIT_SECS = {
    sec = 1, secs = 1, second = 1, seconds = 1,
    min = 60, mins = 60, minute = 60, minutes = 60,
    hour = 3600, hours = 3600, hr = 3600, hrs = 3600,
}

local function Seconds(amount, unit)
    local n = N(amount)
    local per = type(unit) == "string" and UNIT_SECS[unit:lower()] or nil
    if n == nil or per == nil then return nil end
    return n * per
end

--------------------------------------------------------------------------------
-- Parse.Cooldown
--------------------------------------------------------------------------------

-- The right-hand text of a tooltip line ("10 sec cooldown", "6 min
-- cooldown", "1 hour cooldown", "1.7 sec cooldown") as seconds. The whole
-- text must be that phrase: "40 yd range", "Melee Range", "" and anything
-- else are nil. These are the export's own lines (634, all three units);
-- the shape on a live Forever tooltip is T87's probe question.
function Parse.Cooldown(rightText)
    local clean = Parse.Clean(rightText)
    if clean == nil or clean == "" then return nil end
    local amt, unit = clean:match("^(" .. NUM .. ")%s+(%a+)%s+[Cc]ooldown$")
    if amt == nil then return nil end
    return Seconds(amt, unit)
end

--------------------------------------------------------------------------------
-- Parse.Lockout
--------------------------------------------------------------------------------

-- "cannot be <verb> again for N <unit>": a per-target lockout the caster's
-- own text states (Power Word: Shield -- "Once shielded, the target cannot
-- be shielded again for 15 sec", Weakened Soul) as seconds; nil without one.
local LOCKOUT = "cannot%s+be%s+%a+%s+again%s+for%s+(" .. NUM .. ")%s+(%a+)"

function Parse.Lockout(text)
    local clean = Prepare(text)
    if clean == nil then return nil end
    local amt, unit = clean:lower():match(LOCKOUT)
    if amt == nil then return nil end
    return Seconds(amt, unit)
end

--------------------------------------------------------------------------------
-- Parse.ManaSource
--------------------------------------------------------------------------------

-- Mana a buff, a totem or a blessing gives, in the two shapes the texts use
-- (docs/SPEC-next.md 4.2 P4; T105 feeds them to the modelled pool):
--   * a rate, "restores N mana every P sec" -- Mana Spring / Mana Tide Totem
--     ("... for 12 sec that restores 290 mana every 3 seconds"), Blessing of
--     Wisdom ("restoring 12 mana every 5 seconds for 1 hour") ->
--     { kind = "rate", mana = N, period = P, dur = D }, D the one "for D
--     <unit>" the same sentence gives (the source's own duration), nil when
--     it gives none or more than one;
--   * a regeneration increase, Innervate's "Increases the target's Mana
--     regeneration by 400% and allows 100% of the target's Mana regeneration
--     to continue while casting. Lasts 20 sec." ->
--     { kind = "regen", regenPct = 400, castingPct = 100, dur = 20 } -- all
--     three in the text, else nil.
-- Anything else is nil: Life Tap's conversion, Mana Burn's drain, a share of
-- the pool. Who receives it is not this function's question.
local RATE = "restor%a*%s+(" .. NUM .. ")%s+mana%s+every%s+(" .. NUM .. ")%s+(%a+)"
local DUR_FOR = "for%s+(" .. NUM .. ")%s+(%a+)"
local REGEN = "increases%s+[^%.]-mana%s+regeneration%s+by%s+(" .. NUM .. ")%%"
local CASTING = "allows%s+(" .. NUM .. ")%%%s+of%s+[^%.]-mana%s+regeneration%s+to%s+continue%s+while%s+casting"
local LASTS_ANY = "lasts%s+(" .. NUM .. ")%s+(%a+)"

local function DurationsIn(text, out)
    for amt, unit in text:gmatch(DUR_FOR) do
        local secs = Seconds(amt, unit)
        if secs then out[#out + 1] = secs end
    end
    return out
end

function Parse.ManaSource(text)
    local clean = Prepare(text)
    if clean == nil then return nil end
    local low = clean:lower()

    local s, e, amt, per, unit = low:find(RATE)
    if s then
        local mana, period = N(amt), Seconds(per, unit)
        if mana == nil or period == nil or period <= 0 then return nil end
        local from, to = SentenceBounds(low, s, e)
        local durs = DurationsIn(low:sub(e + 1, to), DurationsIn(low:sub(from, s - 1), {}))
        return { kind = "rate", mana = mana, period = period, dur = (#durs == 1) and durs[1] or nil }
    end

    local r = low:match(REGEN)
    if r then
        local c = low:match(CASTING)
        local lAmt, lUnit = low:match(LASTS_ANY)
        local dur = lAmt and Seconds(lAmt, lUnit) or nil
        if c == nil or dur == nil then return nil end
        return { kind = "regen", regenPct = N(r), castingPct = N(c), dur = dur }
    end

    return nil
end

--------------------------------------------------------------------------------
-- Parse.Targets
--------------------------------------------------------------------------------

-- Whom a heal reaches, from the text (docs/SPEC-next.md 4.2 P1, 4.5):
--   targets = "single"        no reach wording at all (Healing Touch, Renew;
--                             Power Word: Shield's "the party member")
--             "party"         from = "target": "the target and their party"
--                             (Prayer of Healing, Wild Growth), range from
--                             "Party members must be within N yards of
--                             target"; from = "caster": "all [nearby] party
--                             members [within N yards]" (Holy Nova,
--                             Tranquility)
--             "chain"         Chain Heal: count ("Heals 3 total targets"),
--                             jumps = count - 1, falloff ("Each jump is 50%
--                             as effective" -> 0.5), partyOnly when the text
--                             says a party member's heal jumps to the party
--             "selfAndTarget" "a friendly target and the caster" (Binding Heal)
--             "caster"        "heals the caster" (Desperate Prayer)
--   plus, on any of them, belowPct ("below 50% Health", Divine Grace),
--   charges ("5 charges", Lightwell) and lockout (Parse.Lockout's seconds).
-- Refuse-unknown: a reach word left over once every recognised phrase is
-- taken out of the text (party, raid, group, jump, members, allies, nearby,
-- caster, charge, total / friendly targets, below N%), or two reaches in
-- one text, answers nil plus a reason naming it -- never "single". A
-- clause about the enemy ("to all enemy targets within 10 yards") is not a
-- reach: these are the heal's targets. "Your next" sentences are not read
-- (Prepare).
local REACH = {
    "%f[%a]party%f[%A]", "%f[%a]raid%f[%A]", "%f[%a]group%f[%A]", "%f[%a]jump",
    "%f[%a]members%f[%A]", "%f[%a]allies%f[%A]", "%f[%a]nearby%f[%A]",
    "%f[%a]caster%f[%A]", "%f[%a]charges?%f[%A]",
    "total%s+targets", "friendly%s+targets", "%f[%a]below%s+" .. NUM .. "%%",
}

local CHAIN_JUMPS = "then%s+jumps%s+to%s+heal%s+additional%s+nearby%s+targets"
local CHAIN_PARTY = "if%s+cast%s+on%s+a%s+party%s+member,%s*the%s+heal%s+will%s+only%s+jump%s+to%s+other%s+party%s+members"
local CHAIN_FALLOFF = "each%s+jump%s+is%s+(" .. NUM .. ")%%%s+as%s+effective%s+as%s+the%s+previous%s+target"
local CHAIN_COUNT = "heals%s+(" .. NUM .. ")%s+total%s+targets"
local TARGET_PARTY = "the%s+target%s+and%s+their%s+party"
local TARGET_PARTY_RANGE = "party%s+members%s+must%s+be%s+within%s+(" .. NUM .. ")%s+yards%s+of%s+target"
local ALL_PARTY = { "all%s+nearby%s+party%s+members", "all%s+party%s+members" }
local WITHIN = "^%s+within%s+(" .. NUM .. ")%s+yards"
local AROUND_CASTER = "around%s+the%s+caster"
local SELF_AND_TARGET = { "a%s+friendly%s+target%s+and%s+the%s+caster", "the%s+target%s+and%s+the%s+caster" }
local CASTER_ONLY = "heals%s+the%s+caster"
local ONE_PARTY_MEMBER = "the%s+party%s+member%f[%A]"
local BELOW = "below%s+(" .. NUM .. ")%%%s+health"
local CHARGES = "(" .. NUM .. ")%s+charges"
local LOCKOUT_CLAUSE = "cannot%s+be%s+%a+%s+again%s+for%s+" .. NUM .. "%s+%a+"

-- Finds pat in text; answers the text with the match blanked plus the
-- match's start, end and captures (nil start when it is not there).
local function Take(text, pat)
    local r = { text:find(pat) }
    if r[1] == nil then return text, nil end
    return Blank(text, r[1], r[2]), r[1], r[2], r[3], r[4]
end

function Parse.Targets(text)
    local clean = Prepare(text)
    if clean == nil then return nil, "no text" end
    local low = clean:lower()
    local out, reaches = {}, 0
    local s, e, cap

    -- chain (Chain Heal): every phrase of it taken together, the count and
    -- the falloff required.
    local jumped, partyOnly, falloff, count
    low, jumped = Take(low, CHAIN_JUMPS)
    low, partyOnly = Take(low, CHAIN_PARTY)
    low, s, e, falloff = Take(low, CHAIN_FALLOFF)
    low, s, e, count = Take(low, CHAIN_COUNT)
    if jumped or partyOnly or falloff or count then
        local n, pct = N(count), N(falloff)
        if n == nil or pct == nil or n < 2 then return nil, "chain without its count or falloff" end
        reaches = reaches + 1
        out.targets, out.count, out.jumps, out.falloff = "chain", n, n - 1, pct / 100
        out.partyOnly = partyOnly and true or nil
    end

    -- the target's party (Prayer of Healing, Wild Growth).
    low, s = Take(low, TARGET_PARTY)
    if s then
        reaches = reaches + 1
        out.targets, out.from = "party", "target"
        low, s, e, cap = Take(low, TARGET_PARTY_RANGE)
        if s then out.range = N(cap) end
    end

    -- the caster's party (Holy Nova, Tranquility).
    for _, pat in ipairs(ALL_PARTY) do
        local a, b = low:find(pat)
        if a then
            reaches = reaches + 1
            out.targets, out.from = "party", "caster"
            local yards = low:sub(b + 1):match(WITHIN)
            local wEnd = yards and select(2, low:sub(b + 1):find(WITHIN)) or 0
            low = Blank(low, a, b + wEnd)
            if yards then out.range = N(yards) end
            low = Take(low, AROUND_CASTER)
            break
        end
    end

    -- the target and the caster (Binding Heal).
    for _, pat in ipairs(SELF_AND_TARGET) do
        low, s = Take(low, pat)
        if s then
            reaches = reaches + 1
            out.targets = "selfAndTarget"
            break
        end
    end

    -- the caster alone (Desperate Prayer).
    low, s = Take(low, CASTER_ONLY)
    if s then
        reaches = reaches + 1
        out.targets = "caster"
    end

    -- one party member is one target (Power Word: Shield).
    low = Take(low, ONE_PARTY_MEMBER)

    -- conditions and counts that ride on any reach.
    low, s, e, cap = Take(low, BELOW)
    if s then out.belowPct = N(cap) end
    low, s, e, cap = Take(low, CHARGES)
    if s then out.charges = N(cap) end
    local lockout = Parse.Lockout(text)
    if lockout then
        out.lockout = lockout
        low = Take(low, LOCKOUT_CLAUSE)
    end

    if reaches > 1 then return nil, "two reaches in one text" end
    for _, pat in ipairs(REACH) do
        local word = low:match("(" .. pat .. ")")
        if word then return nil, "unrecognised reach: " .. word end
    end
    out.targets = out.targets or "single"
    return out
end
