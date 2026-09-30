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
local NUM = "%d[%d,]*"

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
local function SentenceAt(text, s, e)
    local from = 1
    for p in text:sub(1, s - 1):gmatch("%.%s+()") do from = p end
    local to = text:find("%.%s", e + 1) or #text
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

-- Description() reads one clause shape at a time out of the cleaned text,
-- blanking whatever it just read so a looser pattern tried afterwards never
-- re-reads the same digits under a different (wrong) role.
function Parse.Description(text)
    local clean = Parse.Clean(text)
    if clean == nil or clean == "" then return nil end

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
        if a then
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
        if a and not NotCastDamage(clean, a, b) and not PeriodicOrEitherAfter(clean, b) then
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
