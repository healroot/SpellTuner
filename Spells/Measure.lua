-- T12b (docs/tasks/T12b-measure-attribution.md, M2 field failures): /st
-- measure -- pairs each amount that lands with the cast that caused it,
-- keeps several watches open at once (a Rejuvenation keeps ticking while a
-- Healing Touch is cast), and never issues a BELOW verdict on an amount it
-- cannot pin to one cast: it says ambiguous instead. Rewrites T12's
-- attribution half; the line format and verdict words stay. Forever only --
-- needs UNIT_COMBAT and MD.Book, both Forever's own. Reaches the client only
-- through MD.API; never indexes a client table.
local _, MD = ...
local Parse = MD.Parse
local Book = MD.Book

MD.Measure = MD.Measure or {}
local Measure = MD.Measure

Measure.on = false
Measure.registered = false
Measure.unreadable = 0 -- a secret or non-numeric amount or id, this session (Behaviour)
Measure.deficit = 0    -- known missing health: + WOUND, - HEAL on player, floored at 0 (Facts)
Measure.lastBonus = nil -- last PLAIN GetSpellBonusHealing() reading (Behaviour: "bonus healing")

-- Vanilla's rule, same constant/comment UI/SpellTip_Forever.lua already
-- carries -- not shared code (that file is T9's, out of scope here) but the
-- same number, checked by this task's own measurement (Facts).
local CRIT_MULT = 1.5

-- Windows (Behaviour), each with its own reason:
--   direct: heal [t0-0.3, t0+1.0], damage [t0-0.3, t0+2.5] (projectile travel);
--   a Healing Touch's own UNIT_COMBAT HEAL can arrive before or in the same
--   frame as its UNIT_SPELLCAST_SUCCEEDED (m2 field failures) -- UNKNOWN by
--   how much; this task uses 0.3 s on both sides.
--   tick: t0 + k*P +/- 0.4 s; a watch closes 0.4 s after its last window ends
--   (so a cast just after cannot still claim an event from it).
local DIRECT_PRE = 0.3
local DIRECT_POST_HEAL = 1.0
local DIRECT_POST_DAMAGE = 2.5
local TICK_SLACK = 0.4
local CLOSE_GRACE = 0.4
local HISTORY_SECS = 30 -- Contest: "other watches ... those closed in the last 30 s"
local PERIODS = { 3, 2, 1 } -- Facts: vanilla HoT/DoT periods; tie goes to the larger P

--------------------------------------------------------------------------------
-- Session state -- several watches open at once (Behaviour), plus the event
-- history a watch's resolution is read back out of (30 s).
--------------------------------------------------------------------------------
local watches = {}       -- open watches, in cast order
local closedRecent = {}  -- { watch = w, closeTime = t }, purged past HISTORY_SECS
local history = { player = {}, target = {} } -- { amount, time, deficitBefore?, descriptor }

--------------------------------------------------------------------------------
-- Reversible ASCII escaping, Client/Probe.lua's own rule (Rules: "every
-- client string ... through Esc"). Duplicated rather than imported: Probe.lua
-- exposes no public Esc, and this file's client strings (a spell's own name,
-- a UNIT_COMBAT descriptor) are already read through MD.API/MD.Book, never a
-- client table directly.
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
-- Entry lookup -- unchanged from T12: a family member first (whose kind
-- lives on the FAMILY, not the entry), else a standalone Book:ReadSpell (a
-- cast from outside the player's own book -- someone else's macro, a proc).
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
-- periodDur.
local function PartOf(entry, kind)
    if type(entry.parsed) ~= "table" then return nil end
    if kind == "damage" then return entry.parsed.damage end
    return entry.parsed.heal
end

--------------------------------------------------------------------------------
-- Event history and the known deficit
--------------------------------------------------------------------------------
local function PurgeList(list, now)
    local i = 1
    while i <= #list do
        if now - list[i].time > HISTORY_SECS then
            table.remove(list, i)
        else
            i = i + 1
        end
    end
end

local function PurgeClosed(now)
    local i = 1
    while i <= #closedRecent do
        if now - closedRecent[i].closeTime > HISTORY_SECS then
            table.remove(closedRecent, i)
        else
            i = i + 1
        end
    end
end

--------------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------------
local function DirectWindowOf(w)
    if w.kind == "heal" then
        return w.castTime - DIRECT_PRE, w.castTime + DIRECT_POST_HEAL
    end
    return w.castTime - DIRECT_PRE, w.castTime + DIRECT_POST_DAMAGE
end

-- Parse.Total() sums the direct AVERAGE plus the over amount -- right for a
-- pure over-time part, wrong for a hybrid (Moonfire: "11 to 15 ... and then
-- an additional 24 ... over 12 sec", Facts) whose over part must be judged
-- against its own 24, not 13+24. text.over is the ground truth when the text
-- states one; Parse.Total is the fallback only for a pure-tick shape that
-- never states an "over" total of its own (Tranquility-style).
local function OverTotal(text)
    if text.over ~= nil then return text.over end
    return Parse.Total(text)
end

-- Facts: "the period ... else inferred from the landed ticks among {3, 2, 1}
-- s". perTick is the text's own tick number when it states one, else the
-- total split evenly over the ticks that P implies.
local function PerTickBound(text, n)
    if n <= 0 then return nil, nil end
    local per = text.tick
    if per == nil then
        local total = OverTotal(text)
        if total ~= nil then per = total / n end
    end
    if per == nil then return nil, nil end
    return per, per * CRIT_MULT + 1
end

-- The events in the watch's own tick windows for period P, unfiltered by
-- contest (Behaviour: period choice ignores contest; only the aligned
-- verdict cares about it).
local function TicksForPeriod(w, P)
    local n = w.dur and math.floor(w.dur / P) or 0
    if n <= 0 then return {}, 0, nil, nil end
    local per, bound = PerTickBound(w.text, n)
    local hist = (w.kind == "heal") and history.player or history.target
    local out = {}
    for k = 1, n do
        local t = w.castTime + k * P
        local lo, hi = t - TICK_SLACK, t + TICK_SLACK
        for _, e in ipairs(hist) do
            if e.time >= lo and e.time <= hi and (bound == nil or e.amount <= bound) then
                out[#out + 1] = e
            end
        end
    end
    return out, n, per, bound
end

-- At close: "for each P in {3, 2, 1}, count the events ... that satisfy the
-- amount bound; take the P with the most; a tie goes to the larger P" (PERIODS
-- is already {3,2,1}, so the first P to reach a count keeps it on a tie);
-- "fewer than 2 aligned events -> period unknown".
local function ResolvePeriod(w)
    if type(w.text.period) == "number" and w.text.period > 0 then
        return w.text.period, true
    end
    local bestP, bestCount = nil, -1
    for _, P in ipairs(PERIODS) do
        local ticks = TicksForPeriod(w, P)
        if #ticks > bestCount then
            bestCount = #ticks
            bestP = P
        end
    end
    if not bestP then return nil, false end
    return bestP, bestCount >= 2
end

local function TickWindowList(w, P)
    local n = w.dur and math.floor(w.dur / P) or 0
    local out = {}
    for k = 1, n do
        local t = w.castTime + k * P
        out[#out + 1] = { lo = t - TICK_SLACK, hi = t + TICK_SLACK }
    end
    return out
end

-- Contest: "other watches are the open ones and those closed in the last
-- 30 s". A watch's DIRECT window contests only while it is still open (its
-- own close, pass 2, permanently removes it -- "the direct windows of the
-- watches resolved in pass 1" are gone for good, which is what hands a DoT
-- tick that fell inside a resolved Wrath's window back to the tick watch).
-- A watch's TICK windows keep contesting as long as it is known (open, with
-- the union over all three P while its own period is undecided, or closed
-- with its own resolved P) -- a HoT that keeps ticking is a real ongoing
-- fact, not something a later cast's own resolution erases.
local function OtherWindows(selfW)
    local out = {}
    for _, w in ipairs(watches) do
        if w ~= selfW and w.unit == selfW.unit then
            if w.hasDirect then
                local lo, hi = DirectWindowOf(w)
                out[#out + 1] = { lo = lo, hi = hi, bound = nil, name = w.name }
            end
            if w.hasOver and w.dur then
                for _, P in ipairs(PERIODS) do
                    local n = math.floor(w.dur / P)
                    if n > 0 then
                        local per, bound = PerTickBound(w.text, n)
                        for k = 1, n do
                            local t = w.castTime + k * P
                            out[#out + 1] = { lo = t - TICK_SLACK, hi = t + TICK_SLACK, bound = bound, name = w.name }
                        end
                    end
                end
            end
        end
    end
    for _, rec in ipairs(closedRecent) do
        local w = rec.watch
        if w ~= selfW and w.unit == selfW.unit and w.hasOver and w.period and w.tickWindows then
            for _, tw in ipairs(w.tickWindows) do
                out[#out + 1] = { lo = tw.lo, hi = tw.hi, bound = w.critBound, name = w.name }
            end
        end
        -- A closed watch's direct window never contests (Contest, pass 2).
    end
    return out
end

local function IsContested(e, windows)
    local names, any = {}, false
    for _, win in ipairs(windows) do
        if e.time >= win.lo and e.time <= win.hi and (win.bound == nil or e.amount <= win.bound) then
            any = true
            names[win.name] = true
        end
    end
    return any, names
end

local function SortedKeys(set)
    local out = {}
    for k in pairs(set) do out[#out + 1] = k end
    table.sort(out)
    return out
end

--------------------------------------------------------------------------------
-- Direct resolution
--------------------------------------------------------------------------------

-- Heal: "BELOW range only if deficitBefore >= text min" -- but a near-exact
-- match to the deficit is checked first (a heal that landed effective, not
-- gross, still looks like a clean cap); only past that does the gate decide
-- between a genuine BELOW and "not known to be missing that much" (Behaviour).
local function BelowHealText(min, amount, deficitBefore)
    local d = deficitBefore or 0
    if math.abs(amount - d) <= 1 then
        return string.format("capped at missing health %s (amount looks effective)", Round(d))
    elseif d >= min then
        return "BELOW range"
    else
        return string.format("below range, missing health not known (%s known)", Round(d))
    end
end

-- Damage: never BELOW (Behaviour). "Within +/-1 of 75%, 50% or 25% of a
-- value in [min, max]" is read as a PERCENTAGE tolerance (+/-1 point), not an
-- absolute-amount one: as v ranges over [min, max], 100*amount/v sweeps the
-- interval [100*amount/max, 100*amount/min]; a resist percentage p matches
-- when that interval reaches within 1 point of p.
local function BelowDamageText(min, max, amount, descriptor)
    local loRatio, hiRatio = 100 * amount / max, 100 * amount / min
    local best
    for _, p in ipairs({ 75, 50, 25 }) do
        if hiRatio >= p - 1 and loRatio <= p + 1 then
            best = p
            break
        end
    end
    local text
    if best then
        text = string.format("below range: partial resist %d%%?", best)
    else
        text = "below range (resist?)"
    end
    if type(descriptor) == "string" then
        text = text .. " descriptor " .. Esc(descriptor)
    end
    return text
end

local function DirectVerdictText(w, amount, event)
    local min, max = w.text.min, w.text.max
    if amount < min then
        if w.kind == "heal" then
            return BelowHealText(min, amount, event.deficitBefore)
        else
            return BelowDamageText(min, max, amount, event.descriptor)
        end
    elseif amount <= max then
        return "in range"
    elseif amount <= max * CRIT_MULT then
        return "crit range"
    else
        return "above"
    end
end

-- Verdicts, direct part: "the uncontested candidates in the window. Exactly
-- one -> judged as T12. None, but contested ones exist -> ambiguous: ...
-- also fit ... . None at all -> nothing landed. Two or more uncontested ->
-- ambiguous: ...".
local function ResolveDirect(w)
    if not w.hasDirect then return nil end
    local lo, hi = DirectWindowOf(w)
    local hist = (w.kind == "heal") and history.player or history.target
    local cands = {}
    for _, e in ipairs(hist) do
        if e.time >= lo and e.time <= hi then cands[#cands + 1] = e end
    end
    local others = OtherWindows(w)
    local uncontested, contestedNames = {}, {}
    for _, e in ipairs(cands) do
        local isC, names = IsContested(e, others)
        if isC then
            for n in pairs(names) do contestedNames[n] = true end
        else
            uncontested[#uncontested + 1] = e
        end
    end
    if #uncontested == 1 then
        return { status = "single", event = uncontested[1] }
    elseif #uncontested == 0 then
        if #cands > 0 then
            local amounts = {}
            for _, e in ipairs(cands) do amounts[#amounts + 1] = Round(e.amount) end
            return { status = "ambiguousOther", amounts = amounts, names = SortedKeys(contestedNames) }
        else
            return { status = "nothing" }
        end
    else
        local amounts = {}
        for _, e in ipairs(uncontested) do amounts[#amounts + 1] = Round(e.amount) end
        return { status = "ambiguousMulti", amounts = amounts }
    end
end

--------------------------------------------------------------------------------
-- Over-time resolution
--------------------------------------------------------------------------------
local function ResolveOver(w)
    if not w.hasOver then return nil end
    local P, confident = ResolvePeriod(w)
    local ticks, n, per, bound = {}, nil, nil, nil
    if P then
        ticks, n, per, bound = TicksForPeriod(w, P)
    end
    local ambiguous, contestedWith = false, {}
    if confident then
        local others = OtherWindows(w)
        for _, e in ipairs(ticks) do
            local isC, names = IsContested(e, others)
            if isC then
                ambiguous = true
                for nm in pairs(names) do contestedWith[nm] = true end
            end
        end
    end
    return {
        period = P, confident = confident, ticks = ticks, expectedCount = n,
        perTick = per, bound = bound, ambiguous = ambiguous, contestedWith = contestedWith,
    }
end

-- Behaviour: "matches" / BELOW / above / partial, crits counted separately,
-- BELOW only when all floor(dur/P) ticks arrived; a heal HoT's BELOW
-- additionally needs the deficit rule to hold for its first tick (else it is
-- "missing health not known", the same caution as a direct heal).
local function OverVerdictText(w, r)
    if not r.confident then return "ambiguous (cadence unknown)" end
    if r.ambiguous then
        return string.format("ambiguous (%d ticks shared with %s)", #r.ticks, table.concat(SortedKeys(r.contestedWith), ", "))
    end
    local sum = 0
    for _, t in ipairs(r.ticks) do sum = sum + t.amount end
    local total = OverTotal(w.text)
    local crits = 0
    if r.perTick then
        for _, t in ipairs(r.ticks) do
            if t.amount > r.perTick * CRIT_MULT then crits = crits + 1 end
        end
    end
    local verdict, allowCrits = nil, false
    if r.expectedCount and #r.ticks < r.expectedCount then
        verdict, allowCrits = "partial", true
    elseif total == nil then
        verdict, allowCrits = "matches", true
    elseif sum < total * 0.9 then
        if w.kind == "heal" then
            local d = r.ticks[1] and r.ticks[1].deficitBefore or 0
            if d >= total then
                verdict, allowCrits = "BELOW", true
            else
                verdict = string.format("below range, missing health not known (%s known)", Round(d))
            end
        else
            verdict, allowCrits = "BELOW", true
        end
    elseif sum > total * 1.5 then
        verdict, allowCrits = "above", true
    else
        verdict, allowCrits = "matches", true
    end
    if crits > 0 and allowCrits then verdict = verdict .. " (" .. crits .. " crits)" end
    return verdict
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------
local function RankTag(w)
    return w.rank and ("R" .. w.rank) or "R?"
end

-- Re-issue 1: "(learned <entry level>, you <caster level>, +heal <B>)" for a
-- heal. Behaviour: bonus healing not plain in combat -> the last plain
-- reading from before combat, marked "+heal <B> before combat"; none ever ->
-- "?".
local function ParenText(w)
    local learnedText = w.level and tostring(w.level) or "?"
    local casterText = w.casterLevel and tostring(w.casterLevel) or "?"
    if w.kind ~= "heal" then
        return string.format("(learned %s, you %s)", learnedText, casterText)
    end
    local bonusText
    if w.bonus == nil then
        bonusText = "?"
    elseif w.bonusBeforeCombat then
        bonusText = Round(w.bonus) .. " before combat"
    else
        bonusText = Round(w.bonus)
    end
    return string.format("(learned %s, you %s, +heal %s)", learnedText, casterText, bonusText)
end

local function DirectHead(w, dr)
    local min, max = w.text.min, w.text.max
    local landedText, verdict
    if dr.status == "single" then
        landedText = Round(dr.event.amount)
        verdict = DirectVerdictText(w, dr.event.amount, dr.event)
    elseif dr.status == "nothing" then
        landedText = "-"
        verdict = "nothing landed"
    elseif dr.status == "ambiguousOther" then
        landedText = table.concat(dr.amounts, "+")
        if #dr.names > 0 then
            verdict = "ambiguous: " .. table.concat(dr.amounts, ", ") .. " also fit " .. table.concat(dr.names, ", ")
        else
            verdict = "ambiguous: " .. table.concat(dr.amounts, ", ")
        end
    else -- ambiguousMulti
        landedText = table.concat(dr.amounts, "+")
        verdict = "ambiguous: " .. table.concat(dr.amounts, ", ")
    end
    return string.format("%s %s %s: landed %s [text %s-%s, crit %s-%s] %s",
        Esc(w.name), RankTag(w), ParenText(w), landedText,
        Round(min), Round(max), Round(min * CRIT_MULT), Round(max * CRIT_MULT), verdict)
end

local function OverBody(w, r)
    local ticks = r.ticks
    local k = #ticks
    local parts, sum = {}, 0
    for _, t in ipairs(ticks) do
        parts[#parts + 1] = Round(t.amount)
        sum = sum + t.amount
    end
    -- Behaviour: "every <P> s with the inferred or text period, every - s
    -- when unknown".
    local periodText = "-"
    if r.confident and r.period then periodText = string.format("%.1f", r.period) end
    local displayOver = w.text.over
    if displayOver == nil then displayOver = OverTotal(w.text) end
    local displayDur = w.text.dur or w.text.periodDur
    local verdict = OverVerdictText(w, r)
    return string.format("%d ticks %s = %s every %s s [text %s over %s sec] %s",
        k, (k > 0) and table.concat(parts, "+") or "-", Round(sum), periodText,
        Round(displayOver), Round(displayDur), verdict)
end

-- One line for a closed watch -- direct only, over-time only, or both
-- (Behaviour: a hybrid prints both parts on one line). reasonText, when
-- given (refreshed / target changed), replaces the over part's whole verdict
-- with the reason and prints no verdict word at all.
local function BuildLine(w, dr, r, reasonText)
    local overText
    if reasonText then
        overText = reasonText
    elseif r then
        overText = OverBody(w, r)
    end
    if w.hasDirect and w.hasOver then
        return DirectHead(w, dr) .. "; " .. Esc(w.name) .. " " .. RankTag(w) .. ": " .. overText
    elseif w.hasDirect then
        return DirectHead(w, dr)
    else
        return Esc(w.name) .. " " .. RankTag(w) .. ": " .. overText
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

--------------------------------------------------------------------------------
-- Closing
--------------------------------------------------------------------------------

-- How many events this watch's own unit has seen since it opened -- used
-- only for the "refreshed"/"target changed" line, which carries no verdict
-- (Behaviour), so it does not need a resolved period.
local function RawTickCountSoFar(w, now)
    local hist = (w.kind == "heal") and history.player or history.target
    local n = 0
    for _, e in ipairs(hist) do
        if e.time >= w.castTime and e.time <= now then n = n + 1 end
    end
    return n
end

-- Finishes a watch: normal resolution (deadline reached), or an early cut
-- with a reason (a same-family recast, or a target change) that ends the
-- over part without a verdict.
local function FinishClose(w, now, reasonKind)
    if reasonKind then
        local k = RawTickCountSoFar(w, now)
        local dr = w.hasDirect and ResolveDirect(w) or nil
        RecordLine(BuildLine(w, dr, nil, reasonKind .. " after " .. k .. " ticks"))
        table.insert(closedRecent, { watch = w, closeTime = now })
        PurgeClosed(now)
        return
    end

    local dr = w.hasDirect and ResolveDirect(w) or nil
    local r = w.hasOver and ResolveOver(w) or nil
    if r and r.confident and r.period then
        w.period = r.period
        w.perTick = r.perTick
        w.critBound = r.bound
        w.tickWindows = TickWindowList(w, r.period)
    end
    RecordLine(BuildLine(w, dr, r, nil))
    table.insert(closedRecent, { watch = w, closeTime = now })
    PurgeClosed(now)
end

--------------------------------------------------------------------------------
-- Opening a watch
--------------------------------------------------------------------------------
local function ComputeDeadline(w)
    local lastEnd
    if w.hasDirect then
        local _, hi = DirectWindowOf(w)
        lastEnd = hi
    end
    if w.hasOver and w.dur then
        local hi = w.castTime + w.dur + TICK_SLACK
        if not lastEnd or hi > lastEnd then lastEnd = hi end
    end
    if not lastEnd then lastEnd = w.castTime end
    return lastEnd + CLOSE_GRACE
end

-- Behaviour: "a new cast of the same family closes that family's open
-- over-time watch as refreshed after <k> ticks (no verdict on its over
-- part)". A direct-only watch of the same family is left alone -- it simply
-- contests the new one like any other open watch.
local function FamilyCloseIfSameFamily(name, now)
    for i = #watches, 1, -1 do
        local w = watches[i]
        if w.name == name and w.hasOver then
            table.remove(watches, i)
            FinishClose(w, now, "refreshed")
        end
    end
end

local function OpenWatch(id, castTime)
    local entry, kind = ResolveEntry(id)
    if not entry or not kind then return end -- no heal/damage part -- nothing to judge
    local part = PartOf(entry, kind)
    if not part then return end

    FamilyCloseIfSameFamily(entry.name, castTime)

    local bonus, bonusBeforeCombat = nil, false
    if kind == "heal" then
        local b = MD.API.SpellBonusHealing and MD.API.SpellBonusHealing()
        if type(b) == "number" and not MD.API.IsSecret(b) then
            bonus = b
            Measure.lastBonus = b
        elseif Measure.lastBonus ~= nil then
            bonus = Measure.lastBonus
            bonusBeforeCombat = true
        end
    end

    -- Re-issue 1: the watch also needs the caster's own level beside the
    -- rank's learn level, since the whole point of the line is Q10 -- a
    -- shortfall growing with the gap between the two.
    local casterLevel = MD.API.UnitLevel and MD.API.UnitLevel("player")
    if type(casterLevel) ~= "number" or MD.API.IsSecret(casterLevel) then casterLevel = nil end

    local hasDirect = part.min ~= nil or part.max ~= nil
    local hasOver = part.over ~= nil or part.tick ~= nil
    local dur = part.dur or part.periodDur

    local w = {
        unit = (kind == "heal") and "player" or "target",
        kind = kind,
        name = entry.name, rank = entry.rank, level = entry.level,
        casterLevel = casterLevel, bonus = bonus, bonusBeforeCombat = bonusBeforeCombat,
        text = {
            min = part.min, max = part.max, over = part.over, dur = part.dur,
            tick = part.tick, period = part.period, periodDur = part.periodDur,
        },
        hasDirect = hasDirect, hasOver = hasOver,
        castTime = castTime, dur = dur,
    }
    w.deadline = ComputeDeadline(w)
    table.insert(watches, w)
end

--------------------------------------------------------------------------------
-- Events -- registered once, on the first toggle (Behaviour).
--------------------------------------------------------------------------------
local function OnCastSucceeded(unit, castGUID, spellID)
    if not Measure.on then return end
    if MD.API.IsSecret(unit) or unit ~= "player" then return end

    local now = GetTime()
    if MD.API.IsSecret(spellID) or type(spellID) ~= "number" then
        Measure.unreadable = Measure.unreadable + 1
        return
    end
    OpenWatch(spellID, now)
end

local function OnUnitCombat(unit, action, descriptor, amount, school)
    -- descriptor's crit shape is UNKNOWN (Facts) -- read, escaped, and only
    -- printed on a damage line below range; never relied on for a verdict.
    if not Measure.on then return end
    if MD.API.IsSecret(unit) or type(unit) ~= "string" then return end
    if MD.API.IsSecret(action) or type(action) ~= "string" then return end

    local wantedPlayer = (unit == "player") and (action == "HEAL" or action == "WOUND")
    local wantedTarget = (unit == "target") and (action == "WOUND")
    if not (wantedPlayer or wantedTarget) then return end

    if MD.API.IsSecret(amount) or type(amount) ~= "number" then
        Measure.unreadable = Measure.unreadable + 1
        return
    end

    local now = GetTime()
    if unit == "player" and action == "WOUND" then
        -- Facts: "+ WOUND ... amounts on player" -- not kept as a pairing
        -- candidate (Behaviour: only HEAL/player and WOUND/target are).
        Measure.deficit = Measure.deficit + amount
        return
    end

    if unit == "player" and action == "HEAL" then
        local before = Measure.deficit
        Measure.deficit = math.max(0, Measure.deficit - amount)
        table.insert(history.player, { amount = amount, time = now, deficitBefore = before, descriptor = descriptor })
        PurgeList(history.player, now)
    else -- target WOUND
        table.insert(history.target, { amount = amount, time = now, descriptor = descriptor })
        PurgeList(history.target, now)
    end
end

-- Facts: PLAYER_TARGET_CHANGED exists on the retail engine. Behaviour: it
-- ends every open damage watch's over part as "target changed after <k>
-- ticks" (no verdict); a direct-only damage watch is unaffected.
local function OnTargetChanged()
    if not Measure.on then return end
    local now = GetTime()
    for i = #watches, 1, -1 do
        local w = watches[i]
        if w.kind == "damage" and w.hasOver then
            table.remove(watches, i)
            FinishClose(w, now, "target changed")
        end
    end
end

-- The deadlines are time-driven, not event-driven -- the master ticker is
-- what notices a watch nobody ever answered (CLAUDE.md: the model is
-- event-driven, tickers only accumulate/render; here the "render" is closing
-- a stale watch).
MD:OnTick(function()
    if not Measure.on then return end
    local now = GetTime()
    local i = 1
    while i <= #watches do
        local w = watches[i]
        if now >= w.deadline then
            table.remove(watches, i)
            FinishClose(w, now, nil)
        else
            i = i + 1
        end
    end
end)

--------------------------------------------------------------------------------
-- Public: the toggle, the dump, and (for the suite) the open watch.
--------------------------------------------------------------------------------
function Measure:Toggle()
    if not Measure.registered then
        MD:On("UNIT_SPELLCAST_SUCCEEDED", OnCastSucceeded)
        MD:On("UNIT_COMBAT", OnUnitCombat)
        MD:On("PLAYER_TARGET_CHANGED", OnTargetChanged)
        Measure.registered = true
    end
    Measure.on = not Measure.on
    if Measure.on then
        -- Session (Behaviour): "switching measuring on clears the event
        -- lists, the known deficit and the open watches".
        watches = {}
        closedRecent = {}
        history.player, history.target = {}, {}
        Measure.deficit = 0
        MD:Print("measure: on - cast on yourself for heals, on a target dummy for damage; several watches stay open at once")
    else
        watches = {} -- discard silently: turning off is not one of the three closing triggers
        MD:Print("measure: off")
    end
end

function Measure:Watch()
    return watches[#watches]
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
