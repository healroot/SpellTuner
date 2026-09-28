-- T12 (docs/tasks/T12-measure.md, M2): /st measure -- a diagnostic session
-- that matches a own cast to what landed (a heal on yourself, damage on your
-- target) and judges it against its own description's numbers, for the
-- author's M2 exit measurements and Q10 (a downrank penalty the text would
-- never show). Off by default, registers nothing until first switched on
-- (Behaviour). Forever only -- needs UNIT_COMBAT and MD.Book, both Forever's
-- own. Reaches the client only through MD.API; never indexes a client table.
local _, MD = ...
local Parse = MD.Parse
local Book = MD.Book

MD.Measure = MD.Measure or {}
local Measure = MD.Measure

Measure.on = false
Measure.registered = false
Measure.unreadable = 0 -- a secret or non-numeric amount or id, this session (Behaviour)

-- Vanilla's rule, same constant/comment UI/SpellTip_Forever.lua already
-- carries -- not shared code (that file is T9's, out of scope here) but the
-- same number, checked by this task's own measurement (Facts).
local CRIT_MULT = 1.5

-- Facts: the first UNIT_COMBAT within this many seconds of the cast is the
-- direct amount; a HoT/DoT watch stays open until its own duration plus this
-- much slack after the cast.
local DIRECT_WINDOW = 2.5
local TAIL_GRACE = 1.5

-- "One spell at a time" (Behaviour) -- a single open watch, not a table of
-- them; a new cast closes whatever was open first.
local watch

--------------------------------------------------------------------------------
-- Reversible ASCII escaping, Client/Probe.lua's own rule (Rules: "every
-- client string through the probe's escaping rule"). Duplicated rather than
-- imported: Probe.lua exposes no public Esc, and this file's only client
-- string is a spell's own name (already read through MD.API/MD.Book, never a
-- client table).
--------------------------------------------------------------------------------
local function Esc(s)
    if type(s) ~= "string" then return "" end
    local step1 = s:gsub("\\", "\\\\")
    local step2 = step1:gsub("|", "||")
    local step3 = step2:gsub("[^ -~]", function(c) return string.format("\\%03d", c:byte()) end)
    return step3
end

-- A number that is nil renders "-", never 0 (CLAUDE.md / this task's Rules).
local function Round(n)
    if type(n) ~= "number" then return "-" end
    return tostring(math.floor(n + 0.5))
end

--------------------------------------------------------------------------------
-- Entry lookup, the same rule UI/SpellTip_Forever.lua and UI/Clock_Forever.lua
-- already use: a family member first (whose kind lives on the FAMILY, not the
-- entry), else a standalone Book:ReadSpell (a cast from outside the player's
-- own book -- someone else's macro, a proc).
--------------------------------------------------------------------------------
local function ResolveEntry(id)
    local book = Book:Get()
    local entry = book.spells[id]
    local family = entry and book.families[entry.name]
    if not (family and family.kind) then
        local ok, e = pcall(Book.ReadSpell, Book, id)
        entry = ok and e or nil
        family = nil
    end
    if not entry then return nil end
    local kind = family and family.kind or entry.kind
    if not kind then return nil end
    return entry, kind
end

-- The relevant half of the entry's own parsed description -- read fresh from
-- entry.parsed (not entry.min/max/over/dur) because a pure tick shape
-- (Tranquility) leaves those four nil while still carrying tick/period/
-- periodDur (Facts: the watch needs all seven numbers).
local function PartOf(entry, kind)
    if type(entry.parsed) ~= "table" then return nil end
    if kind == "damage" then return entry.parsed.damage end
    return entry.parsed.heal
end

--------------------------------------------------------------------------------
-- Verdicts
--------------------------------------------------------------------------------

-- Facts: below the text's own minimum is BELOW range; inside it is in range;
-- above the top and at or under max*CRIT_MULT is crit range; past that,
-- above. No landed amount at all is its own verdict, never guessed at 0.
local function DirectVerdict(min, max, amount)
    if amount == nil then return "nothing landed" end
    if amount < min then return "BELOW range" end
    if amount <= max then return "in range" end
    if amount <= max * CRIT_MULT then return "crit range" end
    return "above"
end

-- Behaviour: "matches" (the sum within the text's total, crits aside --
-- crits are counted separately and named), BELOW, above, or partial (fewer
-- ticks than the text's own period would give, when a period is known).
-- Parse.Total is the one place this file invents a number -- everything else
-- is either read or added up, never typed in.
local function OverVerdict(text, ticks, sum)
    local total = Parse.Total(text)
    local dur = text.dur or text.periodDur
    local expectedCount
    if type(text.period) == "number" and text.period > 0 and dur ~= nil then
        expectedCount = math.floor(dur / text.period)
    end

    -- The per-tick share a crit is measured against: the text's own tick
    -- number when it states one (Tranquility), else the total split evenly
    -- over the ticks the text implies -- never guessed when neither is known.
    local perTickShare = text.tick
    if perTickShare == nil and expectedCount and expectedCount > 0 and total ~= nil then
        perTickShare = total / expectedCount
    end
    local crits = 0
    if perTickShare then
        for _, t in ipairs(ticks) do
            if t.amount > perTickShare * CRIT_MULT then crits = crits + 1 end
        end
    end

    local verdict
    if expectedCount and #ticks < expectedCount then
        verdict = "partial"
    elseif total == nil then
        verdict = "matches" -- nothing to total against -- never guess BELOW/above
    elseif sum < total * 0.9 then
        verdict = "BELOW"
    elseif sum > total * 1.5 then
        verdict = "above"
    else
        verdict = "matches"
    end
    if crits > 0 then verdict = verdict .. " (" .. crits .. " crits)" end
    return verdict
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

local function RankTag(w)
    return w.rank and ("R" .. w.rank) or "R?"
end

-- Re-issue 1: "(learned <entry level>, you <caster level>, +heal <B>)" for a
-- heal -- bonus healing says nothing about damage, so a damage spell's
-- parenthesis drops it rather than printing a meaningless "+heal 0".
local function DirectHead(w)
    local min, max = w.text.min, w.text.max
    local a = w.direct and w.direct.amount
    local verdict = DirectVerdict(min, max, a)
    local learnedText = w.level and tostring(w.level) or "?"
    local casterText = w.casterLevel and tostring(w.casterLevel) or "?"
    local paren
    if w.kind == "heal" then
        local bonusText = w.bonus and Round(w.bonus) or "?"
        paren = string.format("(learned %s, you %s, +heal %s)", learnedText, casterText, bonusText)
    else
        paren = string.format("(learned %s, you %s)", learnedText, casterText)
    end
    return string.format("%s %s %s: landed %s [text %s-%s, crit %s-%s] %s",
        Esc(w.name), RankTag(w), paren, Round(a),
        Round(min), Round(max), Round(min * CRIT_MULT), Round(max * CRIT_MULT), verdict)
end

local function OverBody(w)
    local ticks = w.ticks
    local k = #ticks
    local parts, sum = {}, 0
    local prevTime, intervalSum, intervalCount = nil, 0, 0
    for _, t in ipairs(ticks) do
        parts[#parts + 1] = Round(t.amount)
        sum = sum + t.amount
        if prevTime then
            intervalSum = intervalSum + (t.time - prevTime)
            intervalCount = intervalCount + 1
        end
        prevTime = t.time
    end
    local avgText = "-"
    if intervalCount > 0 then avgText = string.format("%.1f", intervalSum / intervalCount) end
    local displayOver = w.text.over
    if displayOver == nil then displayOver = Parse.Total(w.text) end
    local displayDur = w.text.dur or w.text.periodDur
    local verdict = OverVerdict(w.text, ticks, sum)
    return string.format("%d ticks %s = %s every %s s [text %s over %s sec] %s",
        k, (k > 0) and table.concat(parts, "+") or "-", Round(sum), avgText,
        Round(displayOver), Round(displayDur), verdict)
end

-- One line for a closed watch -- direct only, over-time only, or both
-- (Behaviour: "a hybrid prints both parts on one line").
local function BuildLine(w)
    if w.hasDirect and w.hasOver then
        return DirectHead(w) .. "; " .. Esc(w.name) .. " " .. RankTag(w) .. ": " .. OverBody(w)
    elseif w.hasDirect then
        return DirectHead(w)
    else
        return Esc(w.name) .. " " .. RankTag(w) .. ": " .. OverBody(w)
    end
end

--------------------------------------------------------------------------------
-- Storage: SpellTunerDB.measures, last 100, oldest dropped (Files).
--------------------------------------------------------------------------------
local function RecordLine(line)
    if type(SpellTunerDB) ~= "table" then SpellTunerDB = {} end
    SpellTunerDB.measures = SpellTunerDB.measures or {}
    table.insert(SpellTunerDB.measures, line)
    while #SpellTunerDB.measures > 100 do table.remove(SpellTunerDB.measures, 1) end
    MD:Print(line)
end

local function CloseWatch()
    if not watch then return end
    local w = watch
    watch = nil
    RecordLine(BuildLine(w))
end

--------------------------------------------------------------------------------
-- Opening a watch
--------------------------------------------------------------------------------
local function OpenWatch(id, castTime)
    local entry, kind = ResolveEntry(id)
    if not entry or not kind then return end -- no heal/damage part -- nothing to judge
    local part = PartOf(entry, kind)
    if not part then return end

    local bonus = MD.API.SpellBonusHealing and MD.API.SpellBonusHealing()
    if type(bonus) ~= "number" or MD.API.IsSecret(bonus) then bonus = nil end

    -- Re-issue 1: the watch also needs the caster's own level (Behaviour said
    -- "the caster's level" all along) beside the rank's learn level, since the
    -- whole point of the line is Q10 -- a shortfall growing with the gap
    -- between the two.
    local casterLevel = MD.API.UnitLevel and MD.API.UnitLevel("player")
    if type(casterLevel) ~= "number" or MD.API.IsSecret(casterLevel) then casterLevel = nil end

    local hasDirect = part.min ~= nil or part.max ~= nil
    local hasOver = part.over ~= nil or part.tick ~= nil
    local dur = part.dur or part.periodDur

    local deadline
    if hasOver and dur then
        deadline = castTime + dur + TAIL_GRACE
    else
        deadline = castTime + DIRECT_WINDOW
    end

    watch = {
        unit = (kind == "heal") and "player" or "target",
        kind = kind,
        name = entry.name, rank = entry.rank, level = entry.level,
        casterLevel = casterLevel, bonus = bonus,
        text = {
            min = part.min, max = part.max, over = part.over, dur = part.dur,
            tick = part.tick, period = part.period, periodDur = part.periodDur,
        },
        hasDirect = hasDirect, hasOver = hasOver,
        castTime = castTime, deadline = deadline,
        direct = nil, ticks = {},
    }
end

--------------------------------------------------------------------------------
-- Events -- registered once, on the first toggle (Behaviour).
--------------------------------------------------------------------------------
local function OnCastSucceeded(unit, castGUID, spellID)
    if not Measure.on then return end
    if MD.API.IsSecret(unit) or unit ~= "player" then return end

    local now = GetTime()
    CloseWatch() -- "a new cast closes every open watch first" -- whatever it was

    if MD.API.IsSecret(spellID) or type(spellID) ~= "number" then
        Measure.unreadable = Measure.unreadable + 1
        return
    end
    OpenWatch(spellID, now)
end

local function OnUnitCombat(unit, action, descriptor, amount, school)
    -- descriptor's crit shape is UNKNOWN (Facts) -- read, never relied on;
    -- not even stored, since the judgement uses the amount alone.
    if not Measure.on or not watch then return end
    if MD.API.IsSecret(unit) or unit ~= watch.unit then return end
    if MD.API.IsSecret(action) or type(action) ~= "string" then return end

    local wantAction = (watch.kind == "heal") and "HEAL" or "WOUND"
    if action ~= wantAction then return end

    if MD.API.IsSecret(amount) or type(amount) ~= "number" then
        Measure.unreadable = Measure.unreadable + 1
        return
    end

    local now = GetTime()
    if watch.hasDirect and watch.direct == nil and now <= watch.castTime + DIRECT_WINDOW then
        watch.direct = { amount = amount, time = now }
        if not watch.hasOver then
            CloseWatch() -- no over-time part: closes at once (Behaviour)
        end
        return
    end

    if watch.hasOver then
        watch.ticks[#watch.ticks + 1] = { amount = amount, time = now }
    end
end

-- The deadline is time-driven, not event-driven -- the master ticker is what
-- notices a watch nobody ever answered (CLAUDE.md: the model is event-driven,
-- tickers only accumulate/render; here the "render" is closing a stale watch).
MD:OnTick(function()
    if watch and GetTime() >= watch.deadline then CloseWatch() end
end)

--------------------------------------------------------------------------------
-- Public: the toggle, the dump, and (for the suite) the open watch.
--------------------------------------------------------------------------------
function Measure:Toggle()
    if not Measure.registered then
        MD:On("UNIT_SPELLCAST_SUCCEEDED", OnCastSucceeded)
        MD:On("UNIT_COMBAT", OnUnitCombat)
        Measure.registered = true
    end
    Measure.on = not Measure.on
    if Measure.on then
        MD:Print("measure: on - cast on yourself for heals, on a target dummy for damage; one spell at a time")
    else
        watch = nil -- discard silently: turning off is not one of the three closing triggers
        MD:Print("measure: off")
    end
end

function Measure:Watch()
    return watch
end

-- One copy block: a header (build, character, level, date) then every kept
-- line (Files: "shows them with a header ... in MD:ShowCopyPopup").
function Measure:Dump()
    local build = select(2, MD.API.BuildInfo())
    if type(build) ~= "string" or MD.API.IsSecret(build) then build = "?" end
    local charKey = (MD.player and MD.player.charKey) or "?"
    local level = (MD.player and MD.player.level) or "?"

    local lines = {
        string.format("=== SpellTuner measure  build %s  %s level %s  %s ===",
            Esc(build), Esc(charKey), tostring(level), date("%Y-%m-%d %H:%M:%S")),
    }
    for _, l in ipairs((SpellTunerDB and SpellTunerDB.measures) or {}) do
        lines[#lines + 1] = l
    end
    lines[#lines + 1] = "unreadable: " .. tostring(Measure.unreadable)
    return table.concat(lines, "\n")
end
